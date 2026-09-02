#!/usr/bin/env python3
"""Run one authorized no-motion persistent board-session control diagnostic."""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Callable, Mapping, Sequence, TextIO

from issue33_app_background_hil import _provider_bundle


TARGET = "ztl@172.22.205.19"
IDENTITY = Path("/home/ztl/.ssh/id_ed25519_duole_nav_172_22_205_19")
AUTHORIZATION_TOKEN = "ISSUE33_PERSISTENT_SESSION_CONTROL_DIAGNOSTIC_AUTHORIZED"
SAFE_SERVICE_STATE = "manual:inactive,runtime:inactive,navigation:active"
_PROBE = Path(__file__).with_name(
    "issue33_persistent_session_control_board_probe.py"
)
_MAPPING_OPERATION_ID = re.compile(r"^mapping_[0-9a-f]{32}$")
_MANUAL_MAPPING_SESSION_ID = re.compile(r"^manual_mapping_[0-9a-f]{32}$")
_MANUAL_MAPPING_LEASE_ID = re.compile(r"^mapping_lease_[0-9a-f]{32}$")
_STAGES = (
    "mapping_started",
    "runtime_ready",
    "application_session_started",
    "application_control_acquired",
    "application_zero_intent_applied",
    "application_stop_confirmed",
    "application_session_abandoned",
    "mapping_stopped",
)
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


def execute_diagnostic(
    output_path: str | Path,
    *,
    authorization_token: str,
    run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, object]:
    if authorization_token != AUTHORIZATION_TOKEN:
        raise PermissionError(
            "persistent_session_control_diagnostic_authorization_required"
        )
    output = Path(output_path)
    if output.exists():
        raise FileExistsError(
            "persistent_session_control_diagnostic_output_already_exists"
        )
    if not IDENTITY.is_file():
        raise FileNotFoundError(
            "persistent_session_control_diagnostic_ssh_identity_missing"
        )
    probe_payload, provider_digest = _build_probe_payload()
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
    try:
        completed = run_command(
            command,
            input=probe_payload,
            text=True,
            capture_output=True,
            timeout=150,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError(
            "persistent_session_control_diagnostic_remote_unavailable"
        ) from exc
    service_state = _line_value(completed.stdout, "ISSUE33_SERVICE_STATE=")
    if service_state != SAFE_SERVICE_STATE:
        raise RuntimeError("safe_service_state_not_restored")
    result = _decode_result(completed.stdout)
    _validate_result(
        result,
        provider_bundle_sha256=provider_digest,
        remote_returncode=completed.returncode,
    )
    _atomic_json(output, result)
    return result


def main(
    arguments: Sequence[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--authorize", default="")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(arguments)
    if args.dry_run:
        stdout.write(
            "DRY-RUN target="
            + TARGET
            + " no_motion=true linear=0.0 angular=0.0 "
            + "stages="
            + ",".join(_STAGES)
            + " output="
            + str(args.output)
            + "\n"
        )
        return 0
    try:
        result = execute_diagnostic(
            args.output,
            authorization_token=args.authorize,
        )
    except (
        FileExistsError,
        FileNotFoundError,
        PermissionError,
        RuntimeError,
        ValueError,
    ) as exc:
        stdout.write(f"FAIL {exc}\n")
        return 1
    status = str(result["status"])
    stdout.write(
        ("PASS" if status == "passed" else "FAIL")
        + " issue33_persistent_session_control_diagnostic status="
        + status
        + " output="
        + str(args.output)
        + "\n"
    )
    return 0 if status == "passed" else 1


def provider_bundle_sha256() -> str:
    return _provider_bundle()[1]


def _build_probe_payload() -> tuple[str, str]:
    try:
        probe = _PROBE.read_bytes()
    except OSError as exc:
        raise RuntimeError(
            "persistent_session_control_diagnostic_probe_unreadable"
        ) from exc
    archive, digest = _provider_bundle()
    bootstrap = f'''
import base64
import os
from pathlib import Path
import sys
import tempfile

issue33_provider_directory = tempfile.TemporaryDirectory(prefix="issue33-provider-")
issue33_provider_archive = Path(issue33_provider_directory.name) / "provider.zip"
issue33_provider_archive.write_bytes(base64.b64decode("{base64.b64encode(archive).decode('ascii')}"))
sys.path.insert(0, str(issue33_provider_archive))
os.environ["ISSUE33_PROVIDER_BUNDLE_SHA256"] = "{digest}"
exec(compile(base64.b64decode("{base64.b64encode(probe).decode('ascii')}"), "issue33_persistent_session_control_board_probe.py", "exec"))
'''
    return bootstrap, digest


def _decode_result(output: str) -> dict[str, object]:
    encoded = _line_value(output, "ISSUE33_DIAGNOSTIC_RESULT=")
    if encoded is None:
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_missing"
        )
    try:
        decoded = json.loads(encoded)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        ) from exc
    if not isinstance(decoded, Mapping):
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        )
    return {str(key): value for key, value in decoded.items()}


def _validate_result(
    result: Mapping[str, object],
    *,
    provider_bundle_sha256: str,
    remote_returncode: int,
) -> None:
    status = result.get("status")
    completed = result.get("completed_stages")
    failed_stage = result.get("failed_stage")
    error = result.get("error")
    operation_id = result.get("operation_id")
    session_id = result.get("session_id")
    lease_id = result.get("lease_id")
    zero_intent = result.get("zero_intent")
    accepted_seq = result.get("accepted_seq")
    intent_status = result.get("intent_status")
    stop_confirmed = result.get("stop_confirmed")
    terminal_phase = result.get("terminal_phase")
    terminal_outcome = result.get("terminal_outcome")
    cleanup_errors = result.get("cleanup_errors")
    if (
        result.get("schema_version") != "1.0"
        or result.get("issue") != 33
        or result.get("kind")
        != "persistent_session_application_control_no_motion_diagnostic"
        or status not in {"passed", "failed"}
        or not isinstance(completed, list)
        or not all(isinstance(stage, str) for stage in completed)
        or tuple(completed) != _STAGES[: len(completed)]
        or not isinstance(zero_intent, Mapping)
        or dict(zero_intent) != {"linear": 0.0, "angular": 0.0}
        or isinstance(accepted_seq, bool)
        or not isinstance(accepted_seq, int)
        or accepted_seq not in {0, 1}
        or result.get("session_process_reused")
        is not ("mapping_started" in completed)
        or result.get("application_service") != "RealManualMappingService"
        or result.get("provider_bundle_sha256") != provider_bundle_sha256
        or not isinstance(cleanup_errors, list)
        or not all(isinstance(item, str) and item for item in cleanup_errors)
    ):
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        )
    if operation_id is not None and (
        not isinstance(operation_id, str)
        or _MAPPING_OPERATION_ID.fullmatch(operation_id) is None
    ):
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        )
    if session_id is not None and (
        not isinstance(session_id, str)
        or _MANUAL_MAPPING_SESSION_ID.fullmatch(session_id) is None
    ):
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        )
    if lease_id is not None and (
        not isinstance(lease_id, str)
        or _MANUAL_MAPPING_LEASE_ID.fullmatch(lease_id) is None
    ):
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        )
    if status == "passed":
        valid = (
            tuple(completed) == _STAGES
            and failed_stage is None
            and error is None
            and operation_id is not None
            and session_id is not None
            and lease_id is not None
            and accepted_seq == 1
            and intent_status == "applied"
            and stop_confirmed is True
            and terminal_phase == "abandoned"
            and terminal_outcome == "abandoned"
            and not cleanup_errors
            and remote_returncode == 0
        )
    else:
        valid = (
            isinstance(failed_stage, str)
            and failed_stage in _STAGES
            and failed_stage not in completed
            and isinstance(error, str)
            and bool(error)
            and stop_confirmed in {False, True}
            and remote_returncode != 0
        )
    if not valid:
        raise RuntimeError(
            "persistent_session_control_diagnostic_result_invalid"
        )


def _line_value(output: str, prefix: str) -> str | None:
    matches = [
        line[len(prefix) :]
        for line in output.splitlines()
        if line.startswith(prefix)
    ]
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
            raise FileExistsError(
                "persistent_session_control_diagnostic_output_already_exists"
            )
        os.replace(temporary, path)
        path.chmod(0o644)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
