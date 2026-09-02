#!/usr/bin/env python3
"""Authorize and orchestrate one Issue 33 app-background HIL run."""

from __future__ import annotations

import argparse
import base64
from functools import lru_cache
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Callable, Mapping, Sequence, TextIO
import zipfile

from issue33_real_evidence_collector import validate_stop_telemetry


TARGET = "ztl@172.22.205.19"
IDENTITY = Path("/home/ztl/.ssh/id_ed25519_duole_nav_172_22_205_19")
MOTION_AUTHORIZATION_TOKEN = "ISSUE33_APP_BACKGROUND_HIL_AUTHORIZED"
SAFE_SERVICE_STATE = "manual:inactive,runtime:inactive,navigation:active"
REAL_MANUAL_MAPPING_SHA256 = (
    "e928846e4fab0f341b4a9e32acc0cca0c57ab32db995ad8bb15c21672cce1a99"
)
PROVIDER_SOURCE_ROOT = Path("/home/ztl/duole-workspace/duole_central")
_PROBE = Path(__file__).with_name("issue33_app_background_board_probe.py")
_MAPPING_OPERATION_ID = re.compile(r"^mapping_[0-9a-f]{32}$")
_MANUAL_MAPPING_SESSION_ID = re.compile(r"^manual_mapping_[0-9a-f]{32}$")
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


def execute_app_background_hil(
    output_path: str | Path,
    lifecycle_output_path: str | Path,
    *,
    authorization_token: str,
    run_command: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> tuple[dict[str, object], dict[str, object]]:
    if authorization_token != MOTION_AUTHORIZATION_TOKEN:
        raise PermissionError("motion_authorization_required")
    output = Path(output_path)
    lifecycle_output = Path(lifecycle_output_path)
    if output == lifecycle_output:
        raise ValueError("app_background_output_paths_not_distinct")
    if output.exists() or lifecycle_output.exists():
        raise FileExistsError("app_background_output_already_exists")
    if not IDENTITY.is_file():
        raise FileNotFoundError("app_background_ssh_identity_missing")
    try:
        probe = _PROBE.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError("app_background_board_probe_unreadable") from exc
    probe_payload, provider_digest = _build_probe_payload(probe)
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
        raise RuntimeError("app_background_remote_unavailable") from exc
    service_state = _line_value(completed.stdout, "ISSUE33_SERVICE_STATE=")
    if service_state != SAFE_SERVICE_STATE:
        raise RuntimeError("safe_service_state_not_restored")
    if completed.returncode != 0:
        detail = completed.stderr.strip() or f"exit_code={completed.returncode}"
        raise RuntimeError("remote_probe_failed:" + detail)
    telemetry = _decode_mapping_line(
        completed.stdout,
        prefix="ISSUE33_STOP_TELEMETRY=",
        error="app_background_telemetry_invalid",
    )
    lifecycle = _decode_mapping_line(
        completed.stdout,
        prefix="ISSUE33_LIFECYCLE_RESULT=",
        error="lifecycle_result_invalid",
    )
    try:
        validate_stop_telemetry(telemetry, scenario="app_background")
    except ValueError as exc:
        raise RuntimeError("app_background_telemetry_invalid") from exc
    _validate_lifecycle_result(
        lifecycle,
        telemetry=telemetry,
        provider_bundle_sha256=provider_digest,
    )
    _atomic_json(lifecycle_output, lifecycle)
    try:
        _atomic_json(output, telemetry)
    except Exception:
        raise
    return telemetry, lifecycle


def main(
    arguments: Sequence[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--lifecycle-output", type=Path, required=True)
    parser.add_argument("--authorize-motion", default="")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(arguments)
    if args.dry_run:
        stdout.write(
            "DRY-RUN target="
            + TARGET
            + " motion=approximately 0.06 m max_linear=0.07 m/s "
            + "path=RealManualMappingService.command_session "
            + "action=app_background output="
            + str(args.output)
            + " lifecycle_output="
            + str(args.lifecycle_output)
            + "\n"
        )
        return 0
    try:
        telemetry, _lifecycle = execute_app_background_hil(
            args.output,
            args.lifecycle_output,
            authorization_token=args.authorize_motion,
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
    stdout.write(
        "PASS issue33_app_background_hil: stop_latency_ms="
        + str(telemetry["stop_latency_ms"])
        + " output="
        + str(args.output)
        + " lifecycle_output="
        + str(args.lifecycle_output)
        + "\n"
    )
    return 0


def _validate_lifecycle_result(
    lifecycle: Mapping[str, object],
    *,
    telemetry: Mapping[str, object],
    provider_bundle_sha256: str,
) -> None:
    expected_fields = {
        "schema_version",
        "issue",
        "kind",
        "scenario",
        "operation_id",
        "session_id",
        "lease_id",
        "last_accepted_seq",
        "action",
        "release_reason",
        "terminal_phase",
        "terminal_outcome",
        "transition_reason",
        "stop_confirmed",
        "save_kind",
        "save_succeeded",
        "save_outcome",
        "charging_confirmed",
        "previous_active_map_restored",
        "new_map_activated",
        "real_manual_mapping_sha256",
        "provider_bundle_sha256",
    }
    if set(lifecycle) != expected_fields:
        raise RuntimeError("lifecycle_result_invalid")
    seq = lifecycle.get("last_accepted_seq")
    if (
        lifecycle.get("schema_version") != "1.0"
        or lifecycle.get("issue") != 33
        or lifecycle.get("kind") != "lifecycle_result"
        or lifecycle.get("scenario") != "app_background"
        or _MAPPING_OPERATION_ID.fullmatch(str(lifecycle.get("operation_id")))
        is None
        or _MANUAL_MAPPING_SESSION_ID.fullmatch(str(lifecycle.get("session_id")))
        is None
        or lifecycle.get("lease_id") != telemetry.get("lease_id")
        or isinstance(seq, bool)
        or not isinstance(seq, int)
        or seq != telemetry.get("last_accepted_seq")
        or lifecycle.get("action") != "app_background"
        or lifecycle.get("release_reason") != "terminal_app_background"
        or lifecycle.get("terminal_phase") != "terminated"
        or lifecycle.get("terminal_outcome") != "unverified_saved"
        or lifecycle.get("transition_reason") != "app_background"
        or lifecycle.get("stop_confirmed") is not True
        or lifecycle.get("save_kind") != "unverified"
        or lifecycle.get("save_succeeded") is not True
        or lifecycle.get("save_outcome") != "unverified_saved"
        or not isinstance(lifecycle.get("charging_confirmed"), bool)
        or lifecycle.get("previous_active_map_restored") is not True
        or lifecycle.get("new_map_activated") is not False
        or lifecycle.get("real_manual_mapping_sha256")
        != REAL_MANUAL_MAPPING_SHA256
        or lifecycle.get("provider_bundle_sha256") != provider_bundle_sha256
    ):
        raise RuntimeError("lifecycle_result_invalid")


def provider_bundle_sha256() -> str:
    return _provider_bundle()[1]


def _build_probe_payload(probe: str) -> tuple[str, str]:
    archive, digest = _provider_bundle()
    encoded_archive = base64.b64encode(archive).decode("ascii")
    encoded_probe = base64.b64encode(probe.encode("utf-8")).decode("ascii")
    bootstrap = f'''\
import base64
import os
from pathlib import Path
import sys
import tempfile

issue33_provider_directory = tempfile.TemporaryDirectory(prefix="issue33-provider-")
issue33_provider_archive = Path(issue33_provider_directory.name) / "provider.zip"
issue33_provider_archive.write_bytes(base64.b64decode("{encoded_archive}"))
sys.path.insert(0, str(issue33_provider_archive))
os.environ["ISSUE33_PROVIDER_BUNDLE_SHA256"] = "{digest}"
exec(compile(base64.b64decode("{encoded_probe}"), "issue33_app_background_board_probe.py", "exec"))
'''
    return bootstrap, digest


@lru_cache(maxsize=1)
def _provider_bundle() -> tuple[bytes, str]:
    if not PROVIDER_SOURCE_ROOT.is_dir():
        raise RuntimeError("app_background_provider_source_missing")
    sources = sorted(PROVIDER_SOURCE_ROOT.rglob("*.py"))
    if not sources:
        raise RuntimeError("app_background_provider_source_missing")
    archive_stream = io.BytesIO()
    with zipfile.ZipFile(
        archive_stream,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for source in sources:
            try:
                encoded = source.read_bytes()
            except OSError as exc:
                raise RuntimeError("app_background_provider_source_unreadable") from exc
            relative = source.relative_to(PROVIDER_SOURCE_ROOT.parent)
            info = zipfile.ZipInfo(str(relative), date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, encoded, compresslevel=9)
    payload = archive_stream.getvalue()
    return payload, hashlib.sha256(payload).hexdigest()


def _decode_mapping_line(
    output: str,
    *,
    prefix: str,
    error: str,
) -> dict[str, object]:
    encoded = _line_value(output, prefix)
    if encoded is None:
        raise RuntimeError(error)
    try:
        decoded = json.loads(encoded)
    except json.JSONDecodeError as exc:
        raise RuntimeError(error) from exc
    if not isinstance(decoded, Mapping):
        raise RuntimeError(error)
    return {str(key): value for key, value in decoded.items()}


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
            raise FileExistsError("app_background_output_already_exists")
        os.replace(temporary, path)
        path.chmod(0o644)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
