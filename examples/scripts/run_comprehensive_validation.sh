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

wait_for_openresty() {
  local retries="${1:-20}"
  local index

  for index in $(seq 1 "${retries}"); do
    if curl -sS --max-time 3 http://127.0.0.1/healthz >/dev/null 2>&1 \
      && curl -k -sS --max-time 3 --resolve www.example.test:443:127.0.0.1 \
        https://www.example.test/ >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "OpenResty 未在预期时间内恢复就绪" >&2
  exit 1
}

cp -f .env.example .env
set_env_value .env GATEWAY_REDIS_PASSWORD "${TEST_REDIS_PASSWORD}"
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
wait_for_openresty

echo "[1/6] 第一层功能测试"
TEST_REDIS_PASSWORD="${TEST_REDIS_PASSWORD}" bash examples/scripts/test-first-layer.sh

echo "[2/6] 第二阶段等待室功能测试"
TEST_REDIS_PASSWORD="${TEST_REDIS_PASSWORD}" bash examples/scripts/test-waitroom.sh

echo "[3/6] 挂载外部 Redis 测试容器"
rm -f openresty/conf.d/10-real-ip.conf
bash examples/scripts/activate_conf_examples.sh >/dev/null
docker rm -f openresty-local-redis >/dev/null 2>&1 || true
set_env_value .env GATEWAY_REDIS_PASSWORD "${TEST_REDIS_PASSWORD}"
docker compose up -d >/dev/null
sleep 2
("${COMPOSE_LOCAL[@]}" up -d >/dev/null)
sleep 2
docker compose restart openresty >/dev/null
sleep 2
wait_for_openresty
docker run -d --name openresty-local-redis --network openresty-install_gateway --network-alias redis \
  redis:7.2.5-alpine redis-server --requirepass "${TEST_REDIS_PASSWORD}" >/dev/null
sleep 1
redis_cli SET gateway:partner:test-client \
  '{"tenant":"acme","jwt_secret":"partner-jwt-secret","hmac_secret":"partner-hmac-secret"}' >/dev/null
redis_cli SET gateway:gray:enabled 1 >/dev/null

echo "[4/6] 第一层并发压测"
python3 examples/scripts/benchmark_gateway.py \
  --frontend-total 4000 \
  --frontend-concurrency 400 \
  --risk-total 1500 \
  --risk-concurrency 150 \
  --partner-total 1200 \
  --partner-concurrency 120

echo "[5/6] 第二阶段等待室入口并发模拟"
python3 examples/scripts/benchmark_waitroom.py --total 300 --concurrency 300

echo "[6/6] 等待室运维摘要"
curl -k -sS \
  -H 'X-Ops-Token: change-this-before-production' \
  --resolve enroll.example.test:443:127.0.0.1 \
  https://enroll.example.test/api/ops/waitroom/summary

docker rm -f openresty-local-redis >/dev/null 2>&1 || true
bash examples/scripts/deactivate_conf_examples.sh >/dev/null 2>&1 || true

echo "综合验证完成。"
