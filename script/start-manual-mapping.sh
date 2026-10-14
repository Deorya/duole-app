#!/usr/bin/env bash
# 主控端无机器人屏幕启动入口：准备服务，在终端显示 App 可输入的备用码。
set -euo pipefail

exec python3 - "$0" "$@" <<'PY'
import argparse
import json
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time

repo = Path(sys.argv[1]).resolve().parent.parent
parser = argparse.ArgumentParser(
    prog=Path(sys.argv[1]).name,
    description="启动当前 REAL 手动建图开发环境，并生成无屏幕备用码。"
)
parser.add_argument("--check", action="store_true", help="仅检查本地配置，不启动服务或生成备用码")
parser.add_argument("--workspace", type=Path, default=repo.parent / "duole-workspace", help="Provider 仓库目录")
parser.add_argument(
    "--state-dir", type=Path,
    default=repo / "flutter/duole_engineering_app/build/issue33-phaseA-local-20260927/session-20260929",
    help="现有配对、证书及数据库目录",
)
parser.add_argument("--host", default=os.environ.get("DUOLE_MANUAL_MAPPING_HOST", "172.22.205.44"), help="Gateway 在主控上的局域网地址")
parser.add_argument("--port", type=int, default=int(os.environ.get("DUOLE_MANUAL_MAPPING_PORT", "8443")))
parser.add_argument("--socket", type=Path, default=Path("/tmp/issue33-session/app-read.sock"), help="Runtime IPC socket")
args = parser.parse_args(sys.argv[2:])
workspace, state = args.workspace.resolve(), args.state_dir.resolve()
entry = workspace / "scripts/start_product_voice_board_session.sh"
tls_key = Path("/home/ztl/.local/share/duole-hil-tls/gateway-key.pem")
nav_key = Path("/home/ztl/.ssh/id_ed25519_duole_nav_172_22_205_19")
known_hosts = Path("/home/ztl/.ssh/known_hosts")
files = [entry, tls_key, nav_key, known_hosts] + [
    state / name for name in ("engineering.token", "gateway-cert.pem", "pairing.sqlite3", "pairing.secret")
]
missing = [str(path) for path in files if not path.is_file() or not os.access(path, os.R_OK)]
if missing:
    parser.exit(1, "缺少当前开发环境配置：\n" + "\n".join(missing) + "\n")
if not 1 <= args.port <= 65535:
    parser.error("port 必须在 1–65535 之间")
if args.check:
    print("本地配置检查通过。未启动 Runtime/Gateway，未生成备用码。")
    sys.exit(0)
if args.socket.exists():
    parser.exit(1, "Runtime socket 已存在，请先结束现有服务；不会接管或删除它。\n")
try:
    with socket.socket() as probe:
        probe.bind((args.host, args.port))
except OSError as exc:
    parser.exit(1, f"无法使用 {args.host}:{args.port}：{exc}\n")

os.umask(0o077)
logs = state / "headless-runs"
logs.mkdir(exist_ok=True)
run_dir = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), dir=logs))
env = os.environ.copy()
env.update(
    DUOLE_APP_ENGINEERING_TOKEN=(state / "engineering.token").read_text().strip(),
    PYTHONDONTWRITEBYTECODE="1", DUOLE_PRODUCT_RUNTIME_DELEGATE="0",
    PYTHONPATH=str(workspace) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""),
)
children, streams = [], []

def start(name, command):
    stream = (run_dir / (name + ".log")).open("xb")
    streams.append(stream)
    proc = subprocess.Popen(
        command, cwd=workspace, env=env, stdin=subprocess.DEVNULL,
        stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
    )
    children.append(proc)
    return proc

def wait_ready(proc, name, ready, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"{name} 提前退出，请查看 {run_dir / (name + '.log')}")
        if ready():
            return
        time.sleep(0.2)
    raise RuntimeError(f"{name} 启动超时，请查看 {run_dir / (name + '.log')}")

def gateway_ready():
    try:
        with socket.create_connection((args.host, args.port), timeout=0.2):
            return True
    except OSError:
        return False

def show_code():
    # 临时维护开关只在创建码期间存在；码仅显示在操作者终端，不写进服务日志。
    descriptor, marker_name = tempfile.mkstemp(prefix="maintenance-", dir=run_dir)
    marker = Path(marker_name)
    try:
        with os.fdopen(descriptor, "w") as output:
            output.write("enabled\n")
        completed = subprocess.run(
            [sys.executable, "-m", "duole_central.app_gateway.map_management_cli", "create-short-code",
             "--database", str(state / "map-management.sqlite3"),
             "--robot-id", "DUOLE-RK3588-ENG-01", "--purpose", "manual_mapping",
             "--operator-id", "ztl-onsite", "--maintenance-marker", str(marker),
             "--audit-log", str(state / "map-code-audit.jsonl")],
            cwd=workspace, env=env, capture_output=True, text=True, timeout=15,
        )
        if completed.returncode:
            raise RuntimeError("备用码生成失败：请检查维护审计文件与数据库权限")
        result = json.loads(completed.stdout)
        print(f"\n手动建图备用码：{result['short_code']}  到期时间：{result['expires_at']}", flush=True)
    finally:
        marker.unlink(missing_ok=True)

def interrupted(_signum, _frame):
    raise KeyboardInterrupt

signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGTERM, interrupted)
exit_code = 0
tty = None
try:
    print(f"启动手动建图服务，日志目录：{run_dir}", flush=True)
    runtime = start("product", [
        "bash", str(entry), "--app-only", "--app-manual-mapping-development",
        "--max-session-seconds", "0", "--json-summary", "--app-runtime-mode", "REAL",
        "--app-robot-id", "DUOLE-RK3588-ENG-01", "--app-runtime-ipc-socket-path", str(args.socket),
        "--app-projection-database-path", str(state / "projection.sqlite3"),
        "--app-navigation-map-database-path", str(state / "navigation-map.sqlite3"),
        "--app-emergency-stop-database-path", str(state / "emergency-stop.sqlite3"),
    ])
    wait_ready(runtime, "product", args.socket.is_socket)
    command = [
        sys.executable, "-u", "-m", "duole_central.app_gateway.cli",
        "--socket", str(args.socket), "--certificate", str(state / "gateway-cert.pem"),
        "--private-key", str(tls_key), "--host", args.host, "--port", str(args.port),
        "--robot-id", "DUOLE-RK3588-ENG-01", "--robot-display-name", "多乐机器人",
        "--app-runtime-mode", "REAL", "--manual-mapping-session-control-development",
        "--map-switch-development",
        "--navigation-board-host", "ztl@172.22.205.19",
        "--navigation-board-identity-file", str(nav_key),
        "--navigation-board-known-hosts-file", str(known_hosts),
        "--navigation-board-remote-command", "/home/ztl/duole-issue31-nav-ws/bin/issue31-navigation-board-agent",
        "--map-challenge-screen-websocket", "ws://127.0.0.1:8765",
        "--controlled-lan-id", "lan-home", "--controlled-lan-network", "172.22.205.0/24",
        "--discovery-address", args.host,
    ]
    for option, name in (
        ("pairing-database", "pairing.sqlite3"), ("pairing-secret-file", "pairing.secret"),
        ("projection-database", "projection.sqlite3"), ("navigation-map-database", "navigation-map.sqlite3"),
        ("emergency-stop-database", "emergency-stop.sqlite3"), ("map-management-database", "map-management.sqlite3"),
        ("map-switch-database", "map-switch.sqlite3"), ("mapping-database", "mapping.sqlite3"),
    ):
        command.extend(["--" + option, str(state / name)])
    gateway = start("gateway", command)
    wait_ready(gateway, "gateway", gateway_ready)
    print(f"服务就绪：{args.host}:{args.port}。请保持本窗口开启。", flush=True)
    print("App：家庭地图 → 手动建图 → 扫描 → 输入6位备用码。", flush=True)
    show_code()
    print("码过期时输入 r 并回车刷新；在 App 停车并保存/放弃后，按 Ctrl+C 退出。", flush=True)
    if sys.stdout.isatty():
        try:
            tty = open("/dev/tty")
        except OSError:
            pass
    while True:
        for proc, name in ((runtime, "product"), (gateway, "gateway")):
            if proc.poll() is not None:
                raise RuntimeError(f"{name} 已退出，请查看 {run_dir / (name + '.log')}")
        if tty is not None:
            readable, _, _ = select.select([tty], [], [], 0.5)
            if readable and tty.readline().strip().lower() == "r":
                show_code()
        else:
            time.sleep(0.5)
except KeyboardInterrupt:
    print("\n正在关闭本脚本启动的服务……", flush=True)
except Exception as exc:
    print(f"启动/运行失败：{exc}", file=sys.stderr, flush=True)
    exit_code = 1
finally:
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if tty is not None:
        tty.close()
    # 先关闭 Gateway，使控制连接退出；再关闭 Product Runtime。
    for proc in reversed(children):
        if proc.poll() is not None:
            continue
        try:
            proc.send_signal(signal.SIGINT)
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        except ProcessLookupError:
            pass
    for stream in streams:
        stream.close()
    print("Runtime/Gateway 已关闭。", flush=True)
sys.exit(exit_code)
PY
