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
  target_file="${example_file%.example}"
  case "$(basename "${example_file}")" in
    frontend-proxy.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/www.example.test/g' "${example_file}" > "${target_file}"
      ;;
    api-proxy.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/api.example.test/g' "${example_file}" > "${target_file}"
      ;;
    admin-console-proxy.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/admin.example.test/g' "${example_file}" > "${target_file}"
      ;;
    static-local-root.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/static.example.test/g' "${example_file}" > "${target_file}"
      ;;
    risk-protected-proxy.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/risk-gateway.example.test/g' "${example_file}" > "${target_file}"
      ;;
    partner-api-gateway.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/partner-api.example.test/g' "${example_file}" > "${target_file}"
      ;;
    gray-release-proxy.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/gray-release.example.test/g' "${example_file}" > "${target_file}"
      ;;
    waitroom-enrollment-gateway.conf.example)
      sed 's/REPLACE_WITH_DOMAIN/enroll.example.test/g' "${example_file}" > "${target_file}"
      ;;
  esac
done

echo "已启用 conf.d 下所有 .conf.example 模板。"
