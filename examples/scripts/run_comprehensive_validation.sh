#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

cd "${REPO_ROOT}"

echo "[1/6] 第一层功能测试"
bash examples/scripts/test-first-layer.sh

echo "[2/6] 第二阶段等待室功能测试"
bash examples/scripts/test-waitroom.sh

echo "[3/6] 挂载外部 Redis 测试容器"
docker rm -f openresty-local-redis >/dev/null 2>&1 || true
docker run -d --name openresty-local-redis --network openresty-install_gateway --network-alias redis redis:7.2.5-alpine >/dev/null
docker exec openresty-local-redis redis-cli SET gateway:partner:test-client \
  '{"tenant":"acme","jwt_secret":"partner-jwt-secret","hmac_secret":"partner-hmac-secret"}' >/dev/null
docker exec openresty-local-redis redis-cli SET gateway:gray:enabled 1 >/dev/null

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

echo "综合验证完成。"
