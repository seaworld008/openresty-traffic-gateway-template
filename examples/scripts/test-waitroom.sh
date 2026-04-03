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

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少命令: $1" >&2
    exit 1
  fi
}

require_cmd docker
require_cmd python3
require_cmd jq

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
sleep 1
docker compose exec -T openresty openresty -t >/dev/null

echo "[1/6] 前四个用户在稳态容量+突发缓冲内获得准入"
USER1=$(mktemp)
USER2=$(mktemp)
USER3=$(mktemp)
USER4=$(mktemp)
USER5=$(mktemp)

curl -k -sS -D "${USER1}.headers" -o "${USER1}.body" \
  -H 'X-User-Id: user-001' \
  --resolve enroll.example.test:443:127.0.0.1 \
  -X POST https://enroll.example.test/api/enroll/submit >/dev/null
curl -k -sS -D "${USER2}.headers" -o "${USER2}.body" \
  -H 'X-User-Id: user-002' \
  --resolve enroll.example.test:443:127.0.0.1 \
  -X POST https://enroll.example.test/api/enroll/submit >/dev/null
curl -k -sS -D "${USER3}.headers" -o "${USER3}.body" \
  -H 'X-User-Id: user-003' \
  --resolve enroll.example.test:443:127.0.0.1 \
  -X POST https://enroll.example.test/api/enroll/submit >/dev/null
curl -k -sS -D "${USER4}.headers" -o "${USER4}.body" \
  -H 'X-User-Id: user-004' \
  --resolve enroll.example.test:443:127.0.0.1 \
  -X POST https://enroll.example.test/api/enroll/submit >/dev/null

jq -e '.status == "admitted"' "${USER1}.body" >/dev/null
jq -e '.status == "admitted"' "${USER2}.body" >/dev/null
jq -e '.status == "admitted"' "${USER3}.body" >/dev/null
jq -e '.status == "admitted"' "${USER4}.body" >/dev/null

echo "[2/6] 第五个用户进入排队"
curl -k -sS -D "${USER5}.headers" -o "${USER5}.body" \
  -H 'X-User-Id: user-005' \
  --resolve enroll.example.test:443:127.0.0.1 \
  -X POST https://enroll.example.test/api/enroll/submit >/dev/null
jq -e '.status == "queued"' "${USER5}.body" >/dev/null
TICKET=$(jq -r '.ticket_id' "${USER5}.body")

echo "[3/6] 已准入用户可以继续关键链路"
COOKIE1=$(awk -F': ' 'tolower($1)=="set-cookie" {print $2}' "${USER1}.headers" | tr -d '\r' | sed 's/;.*//')
curl -k -sS \
  -H 'X-User-Id: user-001' \
  -H "Cookie: ${COOKIE1}" \
  --resolve enroll.example.test:443:127.0.0.1 \
  https://enroll.example.test/api/cart/add | jq -e '.headers["X-Admission-Activity"][0] == "course-enroll-demo"' >/dev/null

echo "[4/6] 未准入用户不能直接走关键链路"
curl -k -sS \
  -H 'X-User-Id: user-999' \
  --resolve enroll.example.test:443:127.0.0.1 \
  https://enroll.example.test/api/pay/create | jq -e '.code == "missing_token"' >/dev/null

echo "[5/6] 令牌 TTL 到期后，排队用户转为准入"
sleep 13
curl -k -sS -D "${USER5}.status.headers" -o "${USER5}.status.body" \
  -H 'X-User-Id: user-005' \
  --resolve enroll.example.test:443:127.0.0.1 \
  "https://enroll.example.test/api/queue/status?ticket=${TICKET}" >/dev/null
jq -e '.status == "admitted"' "${USER5}.status.body" >/dev/null

echo "[6/6] 排队转准入后可继续下游步骤"
COOKIE5=$(awk -F': ' 'tolower($1)=="set-cookie" {print $2}' "${USER5}.status.headers" | tr -d '\r' | sed 's/;.*//')
curl -k -sS \
  -H 'X-User-Id: user-005' \
  -H "Cookie: ${COOKIE5}" \
  --resolve enroll.example.test:443:127.0.0.1 \
  https://enroll.example.test/api/pay/create | jq -e '.headers["X-Admission-Activity"][0] == "course-enroll-demo"' >/dev/null

rm -f \
  "${USER1}.headers" "${USER1}.body" \
  "${USER2}.headers" "${USER2}.body" \
  "${USER3}.headers" "${USER3}.body" \
  "${USER4}.headers" "${USER4}.body" \
  "${USER5}.headers" "${USER5}.body" \
  "${USER5}.status.headers" "${USER5}.status.body"

echo "第二阶段等待室/准入保护测试全部通过。"
