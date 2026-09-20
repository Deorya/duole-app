#!/usr/bin/env bash
set -euo pipefail

readonly STATE_ROOT=/tmp/duole-issue33-phase3-hil-v1
readonly CANDIDATE_ROOT=/home/ztl/.local/share/duole-issue33/candidates/issue33-mapping-visualization-phase3-candidate-v1/gateway

IFS= read -r DUOLE_APP_ENGINEERING_TOKEN < "$STATE_ROOT/engineering.token"
export DUOLE_APP_ENGINEERING_TOKEN
export PYTHONPATH="$CANDIDATE_ROOT"
export PYTHONDONTWRITEBYTECODE=1

exec /usr/bin/python3 -u -m duole_central.app_gateway.cli \
  --socket "$STATE_ROOT/app-read.sock" \
  --certificate /home/ztl/.local/share/duole-hil-tls/gateway-cert.pem \
  --private-key /home/ztl/.local/share/duole-hil-tls/gateway-key.pem \
  --host 0.0.0.0 \
  --port 8443 \
  --robot-id DUOLE-RK3588-ENG-01 \
  --robot-display-name 多乐机器人 \
  --pairing-database "$STATE_ROOT/pairing.sqlite3" \
  --pairing-secret-file "$STATE_ROOT/pairing.secret" \
  --projection-database "$STATE_ROOT/projection.sqlite3" \
  --navigation-map-database "$STATE_ROOT/navigation-map.sqlite3" \
  --emergency-stop-database "$STATE_ROOT/emergency-stop.sqlite3" \
  --map-management-database "$STATE_ROOT/map-management.sqlite3" \
  --map-switch-database "$STATE_ROOT/map-switch.sqlite3" \
  --mapping-database "$STATE_ROOT/mapping.sqlite3" \
  --app-runtime-mode REAL \
  --navigation-board-host ztl@172.22.205.19 \
  --navigation-board-identity-file /home/ztl/.ssh/id_ed25519_duole_nav_172_22_205_19 \
  --navigation-board-known-hosts-file /home/ztl/.ssh/known_hosts \
  --navigation-board-remote-command /home/ztl/duole-issue31-nav-ws/bin/issue31-navigation-board-agent \
  --map-challenge-screen-websocket ws://127.0.0.1:8765 \
  --controlled-lan-id lan-home \
  --controlled-lan-network 172.22.205.0/24 \
  --discovery-address 172.22.205.44
