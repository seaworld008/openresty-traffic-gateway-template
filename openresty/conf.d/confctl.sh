#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<'EOF'
用法：
  ./confctl.sh new <template.conf.example> <domain> [output.conf]

示例：
  ./confctl.sh new frontend-proxy.conf.example www.example.com
  ./confctl.sh new waitroom-enrollment-gateway.conf.example enroll.example.com enroll-campus-a.conf
EOF
}

COMMAND="${1:-}"
if [[ "${COMMAND}" != "new" ]]; then
  usage
  exit 1
fi

TEMPLATE="${2:-}"
DOMAIN="${3:-}"
OUTPUT="${4:-}"

if [[ -z "${TEMPLATE}" || -z "${DOMAIN}" ]]; then
  usage
  exit 1
fi

TEMPLATE_PATH="${SCRIPT_DIR}/${TEMPLATE}"
if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "模板不存在：${TEMPLATE_PATH}" >&2
  exit 1
fi

if [[ -z "${OUTPUT}" ]]; then
  OUTPUT="${TEMPLATE%.example}"
fi

OUTPUT_PATH="${SCRIPT_DIR}/${OUTPUT}"

sed "s/REPLACE_WITH_DOMAIN/${DOMAIN}/g" "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"
echo "已生成配置：${OUTPUT_PATH}"
