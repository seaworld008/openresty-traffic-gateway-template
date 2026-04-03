#!/usr/bin/env bash

set -euo pipefail

SERVICE_NAME="openresty"
COMPOSE_FILE_NAME="docker-compose.yml"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/${COMPOSE_FILE_NAME}"
ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_BIN=()

usage() {
  cat <<'EOF'
用法：
  ./confctl.sh test
  ./confctl.sh reload
  ./confctl.sh restart
  ./confctl.sh logs
  ./confctl.sh ps
EOF
}

detect_compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN=(docker-compose)
    return 0
  fi

  echo "未找到可用的 Compose 命令，请安装 docker compose 或 docker-compose" >&2
  exit 1
}

compose_run() {
  detect_compose_bin

  if [[ -f "${ENV_FILE}" ]]; then
    "${COMPOSE_BIN[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
    return 0
  fi

  "${COMPOSE_BIN[@]}" -f "${COMPOSE_FILE}" "$@"
}

container_is_running() {
  local container_id

  container_id="$(compose_run ps -q "${SERVICE_NAME}" 2>/dev/null || true)"
  [[ -n "${container_id}" ]] || return 1

  docker inspect -f '{{.State.Running}}' "${container_id}" 2>/dev/null | grep -q '^true$'
}

test_config() {
  if container_is_running; then
    echo "使用运行中的 OpenResty 容器检查配置"
    compose_run exec -T "${SERVICE_NAME}" openresty -t -q
    return 0
  fi

  echo "OpenResty 容器未运行，使用临时容器检查配置"
  compose_run run --rm --no-deps --entrypoint openresty "${SERVICE_NAME}" -t -q
}

reload_config() {
  if ! container_is_running; then
    echo "OpenResty 容器未运行，无法 reload，请先启动容器" >&2
    exit 1
  fi

  test_config
  echo "重新加载 OpenResty 配置"
  compose_run exec -T "${SERVICE_NAME}" openresty -s reload
}

restart_service() {
  echo "重启 OpenResty 容器"
  compose_run restart "${SERVICE_NAME}"
}

show_logs() {
  compose_run logs -f "${SERVICE_NAME}"
}

show_ps() {
  compose_run ps "${SERVICE_NAME}"
}

COMMAND="${1:-}"

case "${COMMAND}" in
  test)
    test_config
    ;;
  reload)
    reload_config
    ;;
  restart)
    restart_service
    ;;
  logs)
    show_logs
    ;;
  ps)
    show_ps
    ;;
  *)
    usage
    exit 1
    ;;
esac
