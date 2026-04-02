#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
CONF_DIR="${REPO_ROOT}/openresty/conf.d"

find "${CONF_DIR}" -maxdepth 1 -type f -name "*.conf" \
  ! -name "00-global.conf" \
  ! -name "01-upstreams.conf" \
  ! -name "10-real-ip.conf" \
  -delete

echo "已清理由模板生成的站点 .conf 文件。"
