#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)

cd "${REPO_ROOT}"

docker compose run --rm --profile ops certbot renew --webroot -w /var/www/certbot
"${SCRIPT_DIR}/reload-openresty.sh"
