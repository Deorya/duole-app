#!/usr/bin/env python3
"""Fail-closed field acceptance gate for Duole App Issue 31."""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Callable, Sequence, TextIO


CommandRunner = Callable[..., subprocess.CompletedProcess[str]]
REQUIRED_HIL_CHECKS = (
    "screen_qr_exchange",
    "screen_short_code_exchange",
    "screen_unavailable_fail_closed",
    "mapping_authorization_one_shot",
    "presence_expiry",
    "presence_app_background",
    "presence_token_revocation",
    "presence_lan_departure",
    "mapping_preflight_no_bypass",
    "switch_safety_rejections",
    "on_dock_switch_commit",
    "restart_explicit_map_restore",
    "load_failure_rollback",
    "localization_failure_rollback",
    "two_phone_operator_busy",
    "global_stop_available_to_second_phone",
    "stable_operation_event_recovery",
)
_IDENTIFIER = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_SECRET_FIELD_NAMES = frozenset(
    {
        "authorization_token",
        "installation_private_key",
        "presence_token",
        "private_key",
        "proof",
        "qr_payload",
        "secret",
        "short_code",
        "token",
    }
)
_REDACTED_VALUES = frozenset({"", "***", "[redacted]", "<redacted>"})


def main(
    arguments: Sequence[str] | None = None,
    *,
    command_runner: CommandRunner = subprocess.run,
    stdout: TextIO = sys.stdout,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--expected-apk-sha256", required=True)
    parser.add_argument("--adb-bin", default="adb")
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args(arguments)

    actual_digest = hashlib.sha256(args.apk.read_bytes()).hexdigest()
    if actual_digest != args.expected_apk_sha256.lower():
        stdout.write(
            f"FAIL apk_sha256: expected {args.expected_apk_sha256.lower()}, "
            f"found {actual_digest}\n"
        )
        return 1
    stdout.write(f"PASS apk_sha256: {actual_digest}\n")

    try:
        devices = command_runner(
            [args.adb_bin, "devices", "-l"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        stdout.write("FAIL adb_devices: unavailable\n")
        return 1
    if devices.returncode != 0:
        stdout.write("FAIL adb_devices: unavailable\n")
        return 1
    phone_serials = []
    for line in devices.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) < 2 or fields[1] != "device":
            continue
        serial = fields[0]
        try:
            sdk = command_runner(
                [
                    args.adb_bin,
                    "-s",
                    serial,
                    "shell",
                    "getprop",
                    "ro.build.version.sdk",
                ],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError:
            stdout.write("FAIL adb_devices: unavailable\n")
            return 1
        if sdk.returncode == 0 and sdk.stdout.strip().isdigit():
            phone_serials.append(serial)
    if len(phone_serials) < 2:
        stdout.write(
            f"FAIL android_phones: found {len(phone_serials)}, need at least 2\n"
        )
        return 1
    stdout.write(f"PASS android_phones: {len(phone_serials)}\n")

    evidence = json.loads(args.evidence.read_text(encoding="utf-8"))
    if evidence.get("schema_version") != "1.0":
        stdout.write("FAIL evidence.schema_version: expected 1.0\n")
        return 1
    stdout.write("PASS evidence.schema_version: 1.0\n")
    if evidence.get("issue") != 31:
        stdout.write("FAIL evidence.issue: expected 31\n")
        return 1
    robot_id = evidence.get("robot_id")
    if not isinstance(robot_id, str) or _IDENTIFIER.fullmatch(robot_id) is None:
        stdout.write("FAIL evidence.robot_id: invalid\n")
        return 1
    if evidence.get("apk_sha256") != actual_digest:
        stdout.write("FAIL evidence.apk_sha256: does not match tested APK\n")
        return 1
    try:
        started_at = _parse_timestamp(evidence.get("started_at"))
        completed_at = _parse_timestamp(evidence.get("completed_at"))
    except ValueError:
        stdout.write("FAIL evidence.session_time: invalid\n")
        return 1
    if completed_at < started_at:
        stdout.write("FAIL evidence.session_time: completed before started\n")
        return 1
    secret_field = _find_unredacted_secret(evidence)
    if secret_field is not None:
        stdout.write(
            f"FAIL evidence.secrets: unredacted {secret_field}\n"
        )
        return 1
    artifacts = evidence.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        stdout.write("FAIL evidence.artifacts: at least one required\n")
        return 1
    evidence_root = args.evidence.resolve().parent
    for artifact_id, artifact in artifacts.items():
        if (
            not isinstance(artifact_id, str)
            or _IDENTIFIER.fullmatch(artifact_id) is None
            or not isinstance(artifact, dict)
            or set(artifact) != {"path", "sha256", "media_type"}
        ):
            stdout.write("FAIL evidence.artifacts: invalid metadata\n")
            return 1
        relative_path = artifact["path"]
        expected_digest = artifact["sha256"]
        media_type = artifact["media_type"]
        if (
            not isinstance(relative_path, str)
            or not relative_path
            or Path(relative_path).is_absolute()
            or not isinstance(expected_digest, str)
            or _SHA256.fullmatch(expected_digest) is None
            or not isinstance(media_type, str)
            or not media_type
        ):
            stdout.write(
                f"FAIL evidence.artifacts.{artifact_id}: invalid metadata\n"
            )
            return 1
        artifact_path = (evidence_root / relative_path).resolve()
        try:
            artifact_path.relative_to(evidence_root)
        except ValueError:
            stdout.write(
                f"FAIL evidence.artifacts.{artifact_id}: path escapes bundle\n"
            )
            return 1
        if not artifact_path.is_file():
            stdout.write(
                f"FAIL evidence.artifacts.{artifact_id}: file missing\n"
            )
            return 1
        actual_artifact_digest = hashlib.sha256(
            artifact_path.read_bytes()
        ).hexdigest()
        if actual_artifact_digest != expected_digest:
            stdout.write(
                f"FAIL evidence.artifacts.{artifact_id}: sha256 mismatch\n"
            )
            return 1
    stdout.write(f"PASS evidence.artifacts: {len(artifacts)} verified\n")
    map_ids = evidence.get("map_ids")
    if not (
        isinstance(map_ids, list)
        and len(map_ids) == 2
        and all(isinstance(map_id, str) and map_id for map_id in map_ids)
        and len(set(map_ids)) == 2
    ):
        stdout.write("FAIL evidence.map_ids: need 2 distinct map IDs\n")
        return 1
    stdout.write("PASS evidence.map_ids: 2 distinct map IDs\n")
    evidence_phones = evidence.get("phone_serials")
    if not (
        isinstance(evidence_phones, list)
        and len(evidence_phones) == 2
        and all(
            isinstance(serial, str) and serial for serial in evidence_phones
        )
        and len(set(evidence_phones)) == 2
        and set(evidence_phones).issubset(phone_serials)
    ):
        stdout.write(
            "FAIL evidence.phone_serials: need 2 connected Android phones\n"
        )
        return 1
    stdout.write("PASS evidence.phone_serials: 2 connected Android phones\n")
    checks = evidence.get("checks")
    for check_name in REQUIRED_HIL_CHECKS:
        if not isinstance(checks, dict) or check_name not in checks:
            stdout.write(f"FAIL evidence.checks: missing {check_name}\n")
            return 1
        check = checks[check_name]
        if not isinstance(check, dict) or check.get("status") != "passed":
            stdout.write(
                f"FAIL evidence.checks.{check_name}: status must be passed\n"
            )
            return 1
        evidence_ids = check.get("evidence_ids")
        if not (
            isinstance(evidence_ids, list)
            and evidence_ids
            and all(
                isinstance(evidence_id, str) and evidence_id
                for evidence_id in evidence_ids
            )
        ):
            stdout.write(
                f"FAIL evidence.checks.{check_name}: evidence_ids required\n"
            )
            return 1
        if not set(evidence_ids).issubset(artifacts):
            stdout.write(
                f"FAIL evidence.checks.{check_name}: unknown evidence_ids\n"
            )
            return 1
        try:
            observed_at = _parse_timestamp(check.get("observed_at"))
        except ValueError:
            stdout.write(
                f"FAIL evidence.checks.{check_name}.observed_at: invalid\n"
            )
            return 1
        if not started_at <= observed_at <= completed_at:
            stdout.write(
                f"FAIL evidence.checks.{check_name}.observed_at: "
                "outside session\n"
            )
            return 1
        if check_name == "stable_operation_event_recovery":
            for field in ("operation_ids", "event_ids"):
                values = check.get(field)
                if not (
                    isinstance(values, list)
                    and values
                    and all(
                        isinstance(value, str)
                        and _IDENTIFIER.fullmatch(value) is not None
                        for value in values
                    )
                ):
                    stdout.write(
                        f"FAIL evidence.checks.{check_name}.{field}: "
                        "at least one valid ID required\n"
                    )
                    return 1
    stdout.write(f"PASS evidence.checks: {len(REQUIRED_HIL_CHECKS)} present\n")
    return 0


def _parse_timestamp(value: object) -> datetime:
    if not isinstance(value, str):
        raise ValueError("timestamp_invalid")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("timestamp_invalid") from exc
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("timestamp_invalid")
    return parsed


def _find_unredacted_secret(value: object) -> str | None:
    if isinstance(value, dict):
        for raw_key, child in value.items():
            key = str(raw_key).casefold()
            if key in _SECRET_FIELD_NAMES:
                if child is None:
                    continue
                if (
                    isinstance(child, str)
                    and child.casefold() in _REDACTED_VALUES
                ):
                    continue
                return key
            found = _find_unredacted_secret(child)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _find_unredacted_secret(child)
            if found is not None:
                return found
    return None


if __name__ == "__main__":
    raise SystemExit(main())
