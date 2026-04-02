#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

usage() {
  cat <<'EOF'
用法：
  ./ssl/scripts/init-cert.sh --email ops@example.com domain1 [domain2 ...]
  ./ssl/scripts/init-cert.sh --email ops@example.com --staging domain1 [domain2 ...]

说明：
  - 这些域名必须已经解析到当前主机。
  - 公网必须能访问到 80 端口。
  - 脚本使用 ./ssl/certbot/www 作为 webroot challenge 目录。
EOF
}

EMAIL=""
STAGING=0
DOMAINS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)
      EMAIL="${2:-}"
      shift 2
      ;;
    --staging)
      STAGING=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      DOMAINS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${EMAIL}" || ${#DOMAINS[@]} -eq 0 ]]; then
  usage
  exit 1
fi

cd "${REPO_ROOT}"
mkdir -p ssl/certbot/conf ssl/certbot/www

domain_args=()
for domain in "${DOMAINS[@]}"; do
  domain_args+=("-d" "${domain}")
done

staging_args=()
if [[ "${STAGING}" -eq 1 ]]; then
  staging_args+=("--staging")
fi

docker compose run --rm --profile ops certbot certonly \
  --webroot \
  -w /var/www/certbot \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  "${staging_args[@]}" \
  "${domain_args[@]}"

"${SCRIPT_DIR}/reload-openresty.sh"
