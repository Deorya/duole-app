#!/usr/bin/env bash
# 主控端点位标注服务：沿用现有配对与地图数据库，导航保持未放行。
set -euo pipefail

case "${1:-}" in
  --help|-h)
    cat <<'HELP'
用法：./script/start-map-semantics.sh [--check]

启动 Product App Runtime 和点位标注 Gateway；Ctrl+C 关闭这两个服务。
--check 仅检查配置和端口，不启动服务。
沿用现有配对数据；不会重定位、解除导航抑制或自动指令机器人移动。

可通过环境变量设置：
  DUOLE_PROVIDER_WORKSPACE  Provider 仓库目录
  DUOLE_APP_STATE_DIR       现有配对、证书和数据库目录
  DUOLE_MAP_SEMANTICS_HOST  主控局域网地址（默认 172.22.205.44）
  DUOLE_MAP_SEMANTICS_PORT  Gateway 端口（默认 8443）
  DUOLE_MAP_SEMANTICS_SOCKET  Runtime IPC 路径
HELP
    exit 0
    ;;
  ""|--check) ;;
  *) printf '未知参数：%s；使用 --help 查看用法。\n' "$1" >&2; exit 2 ;;
esac
if (($# > 1)); then
  printf '只支持一个参数；使用 --help 查看用法。\n' >&2
  exit 2
fi

app_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${DUOLE_PROVIDER_WORKSPACE:-$app_root/../duole-workspace}"
state_dir="${DUOLE_APP_STATE_DIR:-$app_root/flutter/duole_engineering_app/build/issue33-phaseA-local-20260927/session-20260929}"
gateway_host="${DUOLE_MAP_SEMANTICS_HOST:-172.22.205.44}"
gateway_port="${DUOLE_MAP_SEMANTICS_PORT:-8443}"
runtime_socket="${DUOLE_MAP_SEMANTICS_SOCKET:-/tmp/issue33-session/app-read.sock}"
tls_key="${DUOLE_TLS_KEY_FILE:-$HOME/.local/share/duole-hil-tls/gateway-key.pem}"
board_identity="${DUOLE_NAVIGATION_BOARD_IDENTITY_FILE:-$HOME/.ssh/id_ed25519_duole_nav_172_22_205_19}"
board_known_hosts="${DUOLE_NAVIGATION_BOARD_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"
entry="$workspace/scripts/start_product_voice_board_session.sh"

for file in "$entry" "$tls_key" "$board_identity" "$board_known_hosts" \
  "$state_dir/engineering.token" "$state_dir/gateway-cert.pem" \
  "$state_dir/pairing.sqlite3" "$state_dir/pairing.secret"; do
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    printf '缺少或无法读取配置：%s\n' "$file" >&2
    exit 1
  fi
done
if [[ -e "$runtime_socket" || -L "$runtime_socket" ]]; then
  printf 'Runtime IPC 已存在，请先结束原服务：%s\n' "$runtime_socket" >&2
  exit 1
fi
python3 - "$gateway_host" "$gateway_port" <<'PY'
import socket
import sys

try:
    port = int(sys.argv[2])
    if not 1 <= port <= 65535:
        raise ValueError("端口必须在 1–65535 之间")
    with socket.socket() as probe:
        probe.bind((sys.argv[1], port))
except (OSError, ValueError) as exc:
    sys.exit(f"Gateway 地址不可用：{exc}")
PY
IFS= read -r DUOLE_APP_ENGINEERING_TOKEN < "$state_dir/engineering.token" || true
if [[ -z "$DUOLE_APP_ENGINEERING_TOKEN" ]]; then
  printf '工程凭据为空，请检查 engineering.token。\n' >&2
  exit 1
fi
if [[ "${1:-}" == --check ]]; then
  printf '配置与端口检查通过，未启动服务。\n'
  exit 0
fi
export DUOLE_APP_ENGINEERING_TOKEN
export PYTHONDONTWRITEBYTECODE=1
export DUOLE_PRODUCT_RUNTIME_DELEGATE=0
workspace="$(cd -- "$workspace" && pwd)"
state_dir="$(cd -- "$state_dir" && pwd)"
entry="$workspace/scripts/start_product_voice_board_session.sh"
export PYTHONPATH="$workspace${PYTHONPATH:+:$PYTHONPATH}"
umask 077
mkdir -p "$state_dir/map-semantics-runs"
run_dir="$(mktemp -d "$state_dir/map-semantics-runs/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
readiness="$run_dir/navigation-readiness"
printf 'disabled\n' > "$readiness"
product_pid=""
gateway_pid=""

stop_child() {
  local child_pid="$1"
  [[ -n "$child_pid" ]] || return 0
  if kill -0 "$child_pid" 2>/dev/null; then
    kill -INT "$child_pid" 2>/dev/null || true
  fi
  wait "$child_pid" 2>/dev/null || true
}
cleanup() {
  trap '' INT TERM HUP
  stop_child "$gateway_pid"
  stop_child "$product_pid"
  printf 'Product/Gateway 已关闭；日志：%s\n' "$run_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

start_child() {
  local name="$1"
  shift
  # Bash 后台命令继承忽略 SIGINT 的状态；exec 前恢复，确保 Ctrl+C 能正常收尾。
  python3 -c 'import os,signal,sys; signal.signal(signal.SIGINT,signal.SIG_DFL); os.execvp(sys.argv[1],sys.argv[1:])' \
    "$@" > "$run_dir/$name.log" 2>&1 &
  launched_pid=$!
}

wait_ready() {
  local name="$1" child_pid="$2" deadline=$((SECONDS + 30))
  while ((SECONDS < deadline)); do
    if ! kill -0 "$child_pid" 2>/dev/null; then
      printf '%s 提前退出，请查看 %s/%s.log\n' "$name" "$run_dir" "$name" >&2
      return 1
    fi
    if [[ "$name" == product ]]; then
      [[ -S "$runtime_socket" ]] && return 0
    elif python3 - "$gateway_host" "$gateway_port" <<'PY'
import socket
import sys

try:
    with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=0.2):
        pass
except OSError:
    sys.exit(1)
PY
    then
      return 0
    fi
    sleep 0.2
  done
  printf '%s 启动超时，请查看 %s/%s.log\n' "$name" "$run_dir" "$name" >&2
  return 1
}

cd -- "$workspace"
printf '启动点位标注服务；日志：%s\n' "$run_dir"
start_child product bash "$entry" \
  --app-only --app-manual-mapping-development --max-session-seconds 0 --json-summary \
  --app-runtime-mode REAL --app-robot-id DUOLE-RK3588-ENG-01 \
  --app-runtime-ipc-socket-path "$runtime_socket" \
  --app-projection-database-path "$state_dir/projection.sqlite3" \
  --app-navigation-map-database-path "$state_dir/navigation-map.sqlite3" \
  --app-emergency-stop-database-path "$state_dir/emergency-stop.sqlite3" \
  --enable-navigation-command-topic-actions --navigation-readiness-path "$readiness"
product_pid=$launched_pid
wait_ready product "$product_pid"

start_child gateway python3 -u -m duole_central.app_gateway.cli \
  --socket "$runtime_socket" --certificate "$state_dir/gateway-cert.pem" \
  --private-key "$tls_key" --host "$gateway_host" --port "$gateway_port" \
  --robot-id DUOLE-RK3588-ENG-01 --robot-display-name 多乐机器人 \
  --app-runtime-mode REAL --manual-mapping-session-control-development --map-switch-development \
  --navigation-board-host ztl@172.22.205.19 \
  --navigation-board-identity-file "$board_identity" \
  --navigation-board-known-hosts-file "$board_known_hosts" \
  --navigation-board-remote-command /home/ztl/duole-issue31-nav-ws/bin/issue31-navigation-board-agent \
  --map-challenge-screen-websocket ws://127.0.0.1:8765 \
  --controlled-lan-id lan-home --controlled-lan-network 172.22.205.0/24 \
  --discovery-address "$gateway_host" \
  --pairing-database "$state_dir/pairing.sqlite3" --pairing-secret-file "$state_dir/pairing.secret" \
  --projection-database "$state_dir/projection.sqlite3" \
  --navigation-map-database "$state_dir/navigation-map.sqlite3" \
  --emergency-stop-database "$state_dir/emergency-stop.sqlite3" \
  --map-management-database "$state_dir/map-management.sqlite3" \
  --map-switch-database "$state_dir/map-switch.sqlite3" --mapping-database "$state_dir/mapping.sqlite3"
gateway_pid=$launched_pid
wait_ready gateway "$gateway_pid"
printf '服务就绪：%s:%s；App → 家庭地图 → 点位标注与导航。\n' "$gateway_host" "$gateway_port"
printf '导航保持未放行。保持本窗口开启，按 Ctrl+C 关闭服务。\n'

set +e
wait -n "$product_pid" "$gateway_pid"
child_status=$?
set -e
printf '服务进程退出（状态 %s），正在关闭本次会话。\n' "$child_status" >&2
exit 1
