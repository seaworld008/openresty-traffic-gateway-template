#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

cd "${REPO_ROOT}"

COMPOSE_LOCAL=(docker compose -f docker-compose.yml -f examples/backend/docker-compose.local.yml)
TEST_REDIS_PASSWORD="${TEST_REDIS_PASSWORD:-openresty-test-redis-pass}"

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

redis_cli() {
  docker exec -e REDISCLI_AUTH="${TEST_REDIS_PASSWORD}" openresty-local-redis redis-cli "$@"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd python3
require_cmd openssl
require_cmd xxd

cleanup() {
  docker rm -f openresty-local-redis >/dev/null 2>&1 || true
  bash examples/scripts/deactivate_conf_examples.sh >/dev/null 2>&1 || true
}

trap cleanup EXIT

cp -f .env.example .env
set_env_value .env GATEWAY_REDIS_PASSWORD "${TEST_REDIS_PASSWORD}"
chmod +x ssl/scripts/*.sh
./ssl/scripts/init-local-certs.sh >/dev/null
rm -f openresty/conf.d/10-real-ip.conf
bash examples/scripts/activate_conf_examples.sh >/dev/null

("${COMPOSE_LOCAL[@]}" down --remove-orphans) >/dev/null 2>&1 || true
docker compose down >/dev/null 2>&1 || true
docker compose up -d >/dev/null
sleep 2
("${COMPOSE_LOCAL[@]}" up -d >/dev/null)
sleep 2
docker compose restart openresty >/dev/null
sleep 2
docker rm -f openresty-local-redis >/dev/null 2>&1 || true
docker run -d --name openresty-local-redis --network openresty-install_gateway --network-alias redis \
  redis:7.2.5-alpine redis-server --requirepass "${TEST_REDIS_PASSWORD}" >/dev/null

redis_cli SET gateway:gray:enabled 1 >/dev/null
redis_cli SET gateway:partner:test-client \
  '{"tenant":"acme","jwt_secret":"partner-jwt-secret","hmac_secret":"partner-hmac-secret"}' >/dev/null

docker compose exec -T openresty openresty -t >/dev/null

echo "[1/7] 风控默认请求"
curl -k -sS -I --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/ | grep -qi 'x-gateway-route: risk_default'

echo "[2/7] UA 风控拦截"
curl -k -sS -i -H 'User-Agent: evil-bot/1.0' \
  --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/ | grep -q '"code":"ua_blocked"'

echo "[3/7] 熔断打开"
for _ in 1 2 3; do
  curl -k -sS -o /tmp/risk_unstable.out -D /tmp/risk_unstable.headers \
    --resolve risk-gateway.example.test:443:127.0.0.1 \
    https://risk-gateway.example.test/unstable >/dev/null || true
done
grep -qi 'x-gateway-circuit-state: open' /tmp/risk_unstable.headers

echo "[4/7] 限流生效"
STATUS_COUNTS=$(seq 1 25 | xargs -I{} -P25 sh -c \
  "curl -k -o /dev/null -s -w '%{http_code}\n' \
  --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/" | sort | uniq -c)
echo "${STATUS_COUNTS}" | grep -q '429'
sleep 2

echo "[5/8] 风控默认路由可正常通过"
curl -k -sS --resolve risk-gateway.example.test:443:127.0.0.1 \
  https://risk-gateway.example.test/ | grep -q 'Hostname:'

JWT_TOKEN=$(python3 - <<'PY'
import base64, hashlib, hmac, json, time

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()

header = b64url(json.dumps({'alg':'HS256','typ':'JWT'}, separators=(',', ':')).encode())
payload = b64url(json.dumps({'sub':'partner-user-1','exp':int(time.time())+3600}, separators=(',', ':')).encode())
signing_input = f"{header}.{payload}".encode()
signature = b64url(hmac.new(b'partner-jwt-secret', signing_input, hashlib.sha256).digest())
print(f"{header}.{payload}.{signature}")
PY
)

echo "[6/8] JWT + Redis + Body 改写"
ORDERS_RESPONSE=$(curl -k -sS \
  --resolve partner-api.example.test:443:127.0.0.1 \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H 'X-Partner-Key: test-client' \
  -H 'Content-Type: application/json' \
  -H 'X-Remove-Me: yes' \
  -d '{"order_id":"ORD-1001","amount":128}' \
  https://partner-api.example.test/v1/orders)
echo "${ORDERS_RESPONSE}" | grep -q '"gateway_route":"partner_orders"'
echo "${ORDERS_RESPONSE}" | grep -q '"partner_tenant":"acme"'

echo "[7/8] HMAC / 时间戳签名"
TS=$(date +%s)
SIG=$(printf 'POST\n/v1/hooks/inventory\n%s\n%s' "${TS}" '{"event":"inventory.low"}' \
  | openssl dgst -sha256 -hmac 'partner-hmac-secret' -binary \
  | xxd -p -c 256)
HOOK_RESPONSE=$(curl -k -sS \
  --resolve partner-api.example.test:443:127.0.0.1 \
  -H 'X-Partner-Key: test-client' \
  -H "X-Timestamp: ${TS}" \
  -H "X-Signature: ${SIG}" \
  -H 'Content-Type: application/json' \
  -d '{"event":"inventory.low"}' \
  https://partner-api.example.test/v1/hooks/inventory)
echo "${HOOK_RESPONSE}" | grep -q '"gateway_route":"partner_hook_inventory"'

echo "[8/8] 灰度路由与 Redis 开关"
curl -k -sS -D /tmp/gray_canary.headers -o /tmp/gray_canary.body \
  -H 'X-Gray-Release: canary' \
  --resolve gray-release.example.test:443:127.0.0.1 \
  https://gray-release.example.test/ >/dev/null
grep -qi 'x-gray-variant: canary' /tmp/gray_canary.headers
redis_cli SET gateway:gray:enabled 0 >/dev/null
sleep 3
curl -k -sS -D /tmp/gray_stable.headers -o /tmp/gray_stable.body \
  -H 'X-Gray-Release: canary' \
  --resolve gray-release.example.test:443:127.0.0.1 \
  https://gray-release.example.test/ >/dev/null
grep -qi 'x-gray-variant: stable' /tmp/gray_stable.headers

rm -f /tmp/risk_unstable.out /tmp/risk_unstable.headers /tmp/gray_canary.headers /tmp/gray_canary.body /tmp/gray_stable.headers /tmp/gray_stable.body

echo "第一层高级能力测试全部通过。"
