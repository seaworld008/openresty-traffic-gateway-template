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

for example_file in "${CONF_DIR}"/*.conf.example; do
  [[ -e "${example_file}" ]] || continue
  if [[ "$(basename "${example_file}")" == "10-real-ip.conf.example" ]]; then
    continue
  fi
  cp "${example_file}" "${example_file%.example}"
done

echo "已启用 conf.d 下所有 .conf.example 模板。"
