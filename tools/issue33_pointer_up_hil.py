#!/usr/bin/env python3
"""Authorize and orchestrate one Issue 33 pointer-up HIL run."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Callable, Mapping, Sequence, TextIO

from issue33_real_evidence_collector import validate_stop_telemetry


TARGET = "ztl@172.22.205.19"
IDENTITY = Path("/home/ztl/.ssh/id_ed25519_duole_nav_172_22_205_19")
MOTION_AUTHORIZATION_TOKEN = "ISSUE33_POINTER_UP_HIL_AUTHORIZED"
SAFE_SERVICE_STATE = "manual:inactive,runtime:inactive,navigation:active"
_PROBE = Path(__file__).with_name("issue33_pointer_up_board_probe.py")
_REMOTE_COMMAND = r"""
set -u
manual_unit=duole-mapping-manual.service
runtime_unit=duole-manual-mapping-runtime.service
navigation_unit=duole-navigation-stack.service
cleanup() {
  sudo -n systemctl stop "$manual_unit" >/dev/null 2>&1 || true
  sudo -n systemctl start "$navigation_unit" >/dev/null 2>&1 || true
  sleep 2
  manual_state=$(systemctl is-active "$manual_unit" 2>/dev/null || true)
  runtime_state=$(systemctl is-active "$runtime_unit" 2>/dev/null || true)
  navigation_state=$(systemctl is-active "$navigation_unit" 2>/dev/null || true)
  printf 'ISSUE33_SERVICE_STATE=manual:%s,runtime:%s,navigation:%s\n' \
    "$manual_state" "$runtime_state" "$navigation_state"
}
trap cleanup EXIT INT TERM
if ! sudo -n systemctl start "$manual_unit"; then
  echo 'pointer_up_manual_service_start_failed' >&2
  exit 3
fi
ready=0
for _ in $(seq 1 150); do
  if systemctl is-active --quiet "$manual_unit" && \
     systemctl is-active --quiet "$runtime_unit"; then
    ready=1
    break
  fi
  sleep 0.2
done
if [ "$ready" -ne 1 ]; then
  echo 'pointer_up_runtime_not_ready' >&2
  exit 3
fi
set +u
source /opt/ros/humble/setup.bash
source /home/ztl/elderbot_ws/install/setup.bash
set -u
export ROS_DOMAIN_ID=42
export ROS_LOCALHOST_ONLY=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI='<CycloneDDS><Domain><General><Interfaces><NetworkInterface name="wlan0"/></Interfaces></General></Domain></CycloneDDS>'
export PYTHONPATH=/home/ztl/duole-issue31-nav-ws/runtime:${PYTHONPATH:-}
python3 -
probe_rc=$?
exit "$probe_rc"
""".strip()


def execute_pointer_up_hil(
    output_path: str | Path,
    *,
    authorization_token: str,
    run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, object]:
    if authorization_token != MOTION_AUTHORIZATION_TOKEN:
        raise PermissionError("motion_authorization_required")
    output = Path(output_path)
    if output.exists():
        raise FileExistsError("pointer_up_output_already_exists")
    if not IDENTITY.is_file():
        raise FileNotFoundError("pointer_up_ssh_identity_missing")
    try:
        probe = _PROBE.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError("pointer_up_board_probe_unreadable") from exc
    command = [
        "ssh",
        "-i",
        str(IDENTITY),
        "-o",
        "BatchMode=yes",
        "-o",
        "IdentitiesOnly=yes",
        "-o",
        "ConnectTimeout=6",
        TARGET,
        _REMOTE_COMMAND,
    ]
    completed = run_command(
        command,
        input=probe,
        text=True,
        capture_output=True,
        timeout=90,
        check=False,
    )
    service_state = _line_value(completed.stdout, "ISSUE33_SERVICE_STATE=")
    if service_state != SAFE_SERVICE_STATE:
        raise RuntimeError("safe_service_state_not_restored")
    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"exit_code={completed.returncode}"
        raise RuntimeError("remote_probe_failed:" + detail)
    encoded_telemetry = _line_value(
        completed.stdout,
        "ISSUE33_STOP_TELEMETRY=",
    )
    if encoded_telemetry is None:
        raise RuntimeError("pointer_up_telemetry_missing")
    try:
        telemetry = json.loads(encoded_telemetry)
    except json.JSONDecodeError as exc:
        raise RuntimeError("pointer_up_telemetry_invalid") from exc
    if not isinstance(telemetry, Mapping):
        raise RuntimeError("pointer_up_telemetry_invalid")
    normalized = {str(key): value for key, value in telemetry.items()}
    try:
        validate_stop_telemetry(normalized, scenario="pointer_up")
    except ValueError as exc:
        raise RuntimeError("pointer_up_telemetry_invalid") from exc
    _atomic_json(output, normalized)
    return normalized


def main(
    arguments: Sequence[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--authorize-motion", default="")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(arguments)
    if args.dry_run:
        stdout.write(
            "DRY-RUN target="
            + TARGET
            + " motion=approximately 0.06 m max_linear=0.07 m/s "
            + "scenario=pointer_up output="
            + str(args.output)
            + "\n"
        )
        return 0
    try:
        telemetry = execute_pointer_up_hil(
            args.output,
            authorization_token=args.authorize_motion,
        )
    except (FileExistsError, FileNotFoundError, PermissionError, RuntimeError) as exc:
        stdout.write(f"FAIL {exc}\n")
        return 1
    stdout.write(
        "PASS issue33_pointer_up_hil: stop_latency_ms="
        + str(telemetry["stop_latency_ms"])
        + " output="
        + str(args.output)
        + "\n"
    )
    return 0


def _line_value(output: str, prefix: str) -> str | None:
    matches = [line[len(prefix) :] for line in output.splitlines() if line.startswith(prefix)]
    return matches[0] if len(matches) == 1 else None


def _atomic_json(path: Path, payload: Mapping[str, object]) -> None:
    encoded = (
        json.dumps(
            dict(payload),
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(raw)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        if path.exists():
            raise FileExistsError("pointer_up_output_already_exists")
        os.replace(temporary, path)
        path.chmod(0o644)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
