#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

cd "${REPO_ROOT}"

docker compose exec -T openresty openresty -t
docker compose exec -T openresty openresty -s reload

echo "OpenResty 配置校验通过，已完成 reload。"
