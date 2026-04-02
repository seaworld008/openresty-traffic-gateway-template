#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

if ! command -v openssl >/dev/null 2>&1; then
  echo "本地生成测试证书依赖 openssl，请先安装。" >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  set -- \
    www.example.test \
    api.example.test \
    admin.example.test \
    static.example.test \
    risk-gateway.example.test \
    partner-api.example.test \
    gray-release.example.test \
    enroll.example.test
fi

for domain in "$@"; do
  live_dir="${REPO_ROOT}/ssl/certbot/conf/live/${domain}"
  archive_dir="${REPO_ROOT}/ssl/certbot/conf/archive/${domain}"
  mkdir -p "${live_dir}" "${archive_dir}"

  openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -subj "/CN=${domain}" \
    -addext "subjectAltName=DNS:${domain}" \
    -keyout "${archive_dir}/privkey1.pem" \
    -out "${archive_dir}/fullchain1.pem" >/dev/null 2>&1

  cp "${archive_dir}/privkey1.pem" "${live_dir}/privkey.pem"
  cp "${archive_dir}/fullchain1.pem" "${live_dir}/fullchain.pem"

  echo "已为 ${domain} 生成本地自签证书。"
done
