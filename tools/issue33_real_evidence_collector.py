#!/usr/bin/env python3
"""Build a fail-closed Issue 33 REAL evidence bundle without controlling hardware."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Mapping, Sequence, TextIO

from issue33_real_gate import REQUIRED_CHECKS, REQUIRED_STOP_SCENARIOS


_VERSION_KEYS = {
    "app",
    "gateway",
    "runtime",
    "teleop_guard",
    "slam",
    "navigation_board",
    "base",
    "schema",
    "hardware",
    "safety_profile",
}
_LEASE_ID = re.compile(r"^mapping_lease_[0-9a-f]{32}$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_CHECK_ARTIFACT_KINDS = {"external_video", "log", "photo"}


def initialize_bundle(
    bundle_path: str | Path,
    *,
    robot_id: str,
    started_at: datetime,
    versions: Mapping[str, object],
    candidate_manifest_sha256: str,
) -> None:
    bundle = Path(bundle_path)
    if bundle.exists():
        raise FileExistsError("bundle_already_exists")
    if not isinstance(robot_id, str) or not robot_id.strip():
        raise ValueError("robot_id_invalid")
    _require_aware(started_at, "started_at_invalid")
    normalized_versions = _validated_versions(versions)
    if _SHA256.fullmatch(str(candidate_manifest_sha256)) is None:
        raise ValueError("candidate_manifest_sha256_invalid")
    payload = {
        "schema_version": "1.0",
        "issue": 33,
        "candidate_manifest_sha256": candidate_manifest_sha256,
        "evidence_class": "PRELIMINARY_REAL",
        "robot_id": robot_id.strip(),
        "started_at": started_at.isoformat(),
        "completed_at": None,
        "versions": normalized_versions,
        "artifacts": {},
        "stops": {
            scenario: {"status": "pending"}
            for scenario in REQUIRED_STOP_SCENARIOS
        },
        "checks": {name: {"status": "pending"} for name in REQUIRED_CHECKS},
    }
    _atomic_json(bundle, payload, require_absent=True)


def record_stop(
    bundle_path: str | Path,
    *,
    scenario: str,
    telemetry_path: str | Path,
    operator_id: str,
    observed_at: datetime,
    emergency_stop_accessible: bool,
    robot_stopped: bool,
    visible_reverse: bool,
    continued_sliding: bool,
    stable_final_stop: bool,
) -> None:
    bundle = Path(bundle_path)
    payload = _load_mutable_bundle(bundle)
    if scenario not in REQUIRED_STOP_SCENARIOS:
        raise ValueError("stop_scenario_invalid")
    stop_entry = payload["stops"].get(scenario)
    if not isinstance(stop_entry, Mapping) or stop_entry.get("status") != "pending":
        raise ValueError("stop_already_recorded")
    telemetry = _load_json_mapping(Path(telemetry_path), "telemetry_invalid")
    fault_at, stopped_at = validate_stop_telemetry(
        telemetry,
        scenario=scenario,
    )
    if not isinstance(operator_id, str) or not operator_id.strip():
        raise ValueError("operator_id_invalid")
    _require_aware(observed_at, "observed_at_invalid")
    if not fault_at <= observed_at <= stopped_at + timedelta(minutes=5):
        raise ValueError("observed_at_outside_allowed_window")
    if not (
        emergency_stop_accessible is True
        and robot_stopped is True
        and visible_reverse is False
        and continued_sliding is False
        and stable_final_stop is True
    ):
        raise ValueError("operator_observation_not_passed")

    telemetry_id = f"{scenario}-stop-telemetry"
    observation_id = f"{scenario}-operator-observation"
    artifacts = payload["artifacts"]
    if telemetry_id in artifacts or observation_id in artifacts:
        raise ValueError("stop_artifact_already_exists")
    artifact_root = bundle.parent / "artifacts"
    telemetry_target = artifact_root / f"{scenario}-stop-telemetry.json"
    observation_target = artifact_root / f"{scenario}-operator-observation.json"
    if telemetry_target.exists() or observation_target.exists():
        raise FileExistsError("stop_artifact_path_already_exists")

    telemetry_encoded = _encode_json(telemetry)
    observation = {
        "schema_version": "1.0",
        "issue": 33,
        "kind": "operator_observation",
        "scenario": scenario,
        "operator_id": operator_id.strip(),
        "observed_at": observed_at.isoformat(),
        "observation_mode": "direct_onsite",
        "emergency_stop_accessible": True,
        "robot_stopped": True,
        "visible_reverse": False,
        "continued_sliding": False,
        "stable_final_stop": True,
        "telemetry_evidence_id": telemetry_id,
    }
    observation_encoded = _encode_json(observation)
    _atomic_bytes(telemetry_target, telemetry_encoded, require_absent=True)
    _atomic_bytes(observation_target, observation_encoded, require_absent=True)
    artifacts[telemetry_id] = _artifact_metadata(
        bundle,
        telemetry_target,
        telemetry_encoded,
        kind="log",
    )
    artifacts[observation_id] = _artifact_metadata(
        bundle,
        observation_target,
        observation_encoded,
        kind="operator_observation",
    )
    payload["stops"][scenario] = {
        "status": "passed",
        "lease_id": telemetry["lease_id"],
        "last_accepted_seq": telemetry["last_accepted_seq"],
        "fault_at": telemetry["fault_at"],
        "zero_at": telemetry["zero_at"],
        "wheels_stopped_at": telemetry["wheels_stopped_at"],
        "stop_latency_ms": telemetry["stop_latency_ms"],
        "evidence_ids": [telemetry_id, observation_id],
    }
    _atomic_json(bundle, payload)


def record_check(
    bundle_path: str | Path,
    *,
    check_name: str,
    artifact_path: str | Path,
    kind: str,
) -> None:
    bundle = Path(bundle_path)
    payload = _load_mutable_bundle(bundle)
    if check_name not in REQUIRED_CHECKS:
        raise ValueError("check_name_invalid")
    check_entry = payload["checks"].get(check_name)
    if not isinstance(check_entry, Mapping) or check_entry.get("status") != "pending":
        raise ValueError("check_already_recorded")
    if kind not in _CHECK_ARTIFACT_KINDS:
        raise ValueError("check_artifact_kind_invalid")
    source = Path(artifact_path)
    try:
        encoded = source.read_bytes()
    except OSError as exc:
        raise ValueError("check_artifact_unreadable") from exc
    if not encoded:
        raise ValueError("check_artifact_empty")
    artifact_id = f"check-{check_name}"
    if artifact_id in payload["artifacts"]:
        raise ValueError("check_artifact_already_exists")
    target = bundle.parent / "artifacts" / f"{artifact_id}.bin"
    if target.exists():
        raise FileExistsError("check_artifact_path_already_exists")
    _atomic_bytes(target, encoded, require_absent=True)
    payload["artifacts"][artifact_id] = _artifact_metadata(
        bundle,
        target,
        encoded,
        kind=kind,
    )
    payload["checks"][check_name] = {
        "status": "passed",
        "evidence_ids": [artifact_id],
    }
    _atomic_json(bundle, payload)


def bundle_status(bundle_path: str | Path) -> dict[str, object]:
    payload = _load_bundle(Path(bundle_path))
    stops = payload["stops"]
    checks = payload["checks"]
    missing_stops = [
        scenario
        for scenario in REQUIRED_STOP_SCENARIOS
        if not isinstance(stops.get(scenario), Mapping)
        or stops[scenario].get("status") != "passed"
    ]
    missing_checks = [
        name
        for name in REQUIRED_CHECKS
        if not isinstance(checks.get(name), Mapping)
        or checks[name].get("status") != "passed"
    ]
    finalized = payload.get("evidence_class") == "REAL"
    return {
        "evidence_class": payload.get("evidence_class"),
        "completed_stop_count": len(REQUIRED_STOP_SCENARIOS) - len(missing_stops),
        "required_stop_count": len(REQUIRED_STOP_SCENARIOS),
        "missing_stops": missing_stops,
        "completed_check_count": len(REQUIRED_CHECKS) - len(missing_checks),
        "required_check_count": len(REQUIRED_CHECKS),
        "missing_checks": missing_checks,
        "ready_for_finalize": not missing_stops and not missing_checks,
        "ready_for_gate": finalized and not missing_stops and not missing_checks,
    }


def finalize_bundle(
    bundle_path: str | Path,
    *,
    completed_at: datetime,
) -> None:
    bundle = Path(bundle_path)
    payload = _load_mutable_bundle(bundle)
    status = bundle_status(bundle)
    if not status["ready_for_finalize"]:
        raise ValueError(
            "bundle_incomplete:"
            f"stops={','.join(status['missing_stops'])};"
            f"checks={','.join(status['missing_checks'])}"
        )
    _require_aware(completed_at, "completed_at_invalid")
    started_at = _timestamp(payload.get("started_at"), "started_at_invalid")
    if completed_at < started_at:
        raise ValueError("completed_at_before_started_at")
    _verify_artifacts_intact(bundle, payload["artifacts"])
    payload["evidence_class"] = "REAL"
    payload["completed_at"] = completed_at.isoformat()
    _atomic_json(bundle, payload)
    bundle.chmod(0o444)


def main(
    arguments: Sequence[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
) -> int:
    parser = _build_parser()
    args = parser.parse_args(arguments)
    try:
        if args.action == "init":
            versions = _load_json_mapping(args.versions, "versions_invalid")
            initialize_bundle(
                args.bundle,
                robot_id=args.robot_id,
                started_at=_timestamp(args.started_at, "started_at_invalid"),
                versions=versions,
                candidate_manifest_sha256=args.candidate_manifest_sha256,
            )
        elif args.action == "record-stop":
            record_stop(
                args.bundle,
                scenario=args.scenario,
                telemetry_path=args.telemetry,
                operator_id=args.operator_id,
                observed_at=_timestamp(args.observed_at, "observed_at_invalid"),
                emergency_stop_accessible=args.emergency_stop_accessible,
                robot_stopped=args.robot_stopped,
                visible_reverse=not args.no_visible_reverse,
                continued_sliding=not args.no_continued_sliding,
                stable_final_stop=args.stable_final_stop,
            )
        elif args.action == "record-check":
            record_check(
                args.bundle,
                check_name=args.check,
                artifact_path=args.artifact,
                kind=args.kind,
            )
        elif args.action == "status":
            stdout.write(json.dumps(bundle_status(args.bundle), sort_keys=True) + "\n")
            return 0
        elif args.action == "finalize":
            finalize_bundle(
                args.bundle,
                completed_at=_timestamp(args.completed_at, "completed_at_invalid"),
            )
        else:
            raise ValueError("collector_action_invalid")
    except (FileExistsError, OSError, ValueError, json.JSONDecodeError) as exc:
        stdout.write(f"FAIL {exc}\n")
        return 1
    stdout.write(f"PASS issue33_evidence_collector: {args.action}\n")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)

    init = subparsers.add_parser("init")
    init.add_argument("--bundle", type=Path, required=True)
    init.add_argument("--robot-id", required=True)
    init.add_argument("--started-at", required=True)
    init.add_argument("--versions", type=Path, required=True)
    init.add_argument("--candidate-manifest-sha256", required=True)

    stop = subparsers.add_parser("record-stop")
    stop.add_argument("--bundle", type=Path, required=True)
    stop.add_argument("--scenario", choices=REQUIRED_STOP_SCENARIOS, required=True)
    stop.add_argument("--telemetry", type=Path, required=True)
    stop.add_argument("--operator-id", required=True)
    stop.add_argument("--observed-at", required=True)
    stop.add_argument("--emergency-stop-accessible", action="store_true", required=True)
    stop.add_argument("--robot-stopped", action="store_true", required=True)
    stop.add_argument("--no-visible-reverse", action="store_true", required=True)
    stop.add_argument("--no-continued-sliding", action="store_true", required=True)
    stop.add_argument("--stable-final-stop", action="store_true", required=True)

    check = subparsers.add_parser("record-check")
    check.add_argument("--bundle", type=Path, required=True)
    check.add_argument("--check", choices=REQUIRED_CHECKS, required=True)
    check.add_argument("--artifact", type=Path, required=True)
    check.add_argument("--kind", choices=sorted(_CHECK_ARTIFACT_KINDS), required=True)

    status = subparsers.add_parser("status")
    status.add_argument("--bundle", type=Path, required=True)

    finalize = subparsers.add_parser("finalize")
    finalize.add_argument("--bundle", type=Path, required=True)
    finalize.add_argument("--completed-at", required=True)
    return parser


def _validated_versions(raw: Mapping[str, object]) -> dict[str, str]:
    if set(raw) != _VERSION_KEYS:
        raise ValueError("versions_incomplete")
    if any(not isinstance(value, str) or not value.strip() for value in raw.values()):
        raise ValueError("versions_invalid")
    if raw.get("safety_profile") != "manual_mapping_safe_low_speed_v1":
        raise ValueError("safety_profile_invalid")
    return {key: str(raw[key]).strip() for key in sorted(_VERSION_KEYS)}


def _load_bundle(path: Path) -> dict[str, object]:
    payload = _load_json_mapping(path, "bundle_invalid")
    stops = payload.get("stops")
    checks = payload.get("checks")
    artifacts = payload.get("artifacts")
    if (
        payload.get("schema_version") != "1.0"
        or payload.get("issue") != 33
        or _SHA256.fullmatch(str(payload.get("candidate_manifest_sha256"))) is None
        or not isinstance(stops, Mapping)
        or set(stops) != set(REQUIRED_STOP_SCENARIOS)
        or not isinstance(checks, Mapping)
        or set(checks) != set(REQUIRED_CHECKS)
        or not isinstance(artifacts, Mapping)
    ):
        raise ValueError("bundle_invalid")
    return dict(payload)


def _load_mutable_bundle(path: Path) -> dict[str, object]:
    payload = _load_bundle(path)
    if payload.get("evidence_class") != "PRELIMINARY_REAL":
        raise ValueError("bundle_not_mutable")
    return payload


def _load_json_mapping(path: Path, code: str) -> dict[str, object]:
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(code) from exc
    if not isinstance(decoded, Mapping):
        raise ValueError(code)
    return dict(decoded)


def validate_stop_telemetry(
    telemetry: Mapping[str, object],
    *,
    scenario: str,
) -> tuple[datetime, datetime]:
    if set(telemetry) != {
        "schema_version",
        "issue",
        "kind",
        "scenario",
        "lease_id",
        "last_accepted_seq",
        "fault_at",
        "zero_at",
        "wheels_stopped_at",
        "stop_latency_ms",
    }:
        raise ValueError("telemetry_invalid")
    if telemetry.get("scenario") != scenario:
        raise ValueError("telemetry_scenario_mismatch")
    seq = telemetry.get("last_accepted_seq")
    latency = telemetry.get("stop_latency_ms")
    if (
        telemetry.get("schema_version") != "1.0"
        or telemetry.get("issue") != 33
        or telemetry.get("kind") != "stop_telemetry"
        or _LEASE_ID.fullmatch(str(telemetry.get("lease_id"))) is None
        or isinstance(seq, bool)
        or not isinstance(seq, int)
        or seq < 0
        or isinstance(latency, bool)
        or not isinstance(latency, int)
        or not 0 <= latency <= 1_000
    ):
        raise ValueError("telemetry_invalid")
    fault_at = _timestamp(telemetry.get("fault_at"), "telemetry_time_invalid")
    zero_at = _timestamp(telemetry.get("zero_at"), "telemetry_time_invalid")
    stopped_at = _timestamp(
        telemetry.get("wheels_stopped_at"),
        "telemetry_time_invalid",
    )
    measured = round((stopped_at - fault_at).total_seconds() * 1_000)
    if not fault_at <= zero_at <= stopped_at or measured != latency:
        raise ValueError("telemetry_timing_invalid")
    return fault_at, stopped_at


def _verify_artifacts_intact(
    bundle: Path,
    artifacts: object,
) -> None:
    if not isinstance(artifacts, Mapping) or not artifacts:
        raise ValueError("artifacts_invalid")
    root = bundle.resolve().parent
    for metadata in artifacts.values():
        if (
            not isinstance(metadata, Mapping)
            or set(metadata) != {"path", "sha256", "kind"}
            or not isinstance(metadata.get("path"), str)
            or not isinstance(metadata.get("sha256"), str)
        ):
            raise ValueError("artifacts_invalid")
        path = (root / str(metadata["path"])).resolve()
        try:
            path.relative_to(root)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
        except (OSError, ValueError) as exc:
            raise ValueError("artifacts_invalid") from exc
        if digest != metadata["sha256"]:
            raise ValueError("artifact_digest_mismatch")


def _artifact_metadata(
    bundle: Path,
    artifact: Path,
    encoded: bytes,
    *,
    kind: str,
) -> dict[str, str]:
    relative = artifact.resolve().relative_to(bundle.resolve().parent)
    return {
        "path": relative.as_posix(),
        "sha256": hashlib.sha256(encoded).hexdigest(),
        "kind": kind,
    }


def _timestamp(raw: object, code: str) -> datetime:
    if not isinstance(raw, str):
        raise ValueError(code)
    try:
        value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(code) from exc
    _require_aware(value, code)
    return value


def _require_aware(value: datetime, code: str) -> None:
    if not isinstance(value, datetime) or value.tzinfo is None:
        raise ValueError(code)


def _encode_json(payload: Mapping[str, object]) -> bytes:
    return (
        json.dumps(
            dict(payload),
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def _atomic_json(
    path: Path,
    payload: Mapping[str, object],
    *,
    require_absent: bool = False,
) -> None:
    _atomic_bytes(path, _encode_json(payload), require_absent=require_absent)


def _atomic_bytes(
    path: Path,
    encoded: bytes,
    *,
    require_absent: bool = False,
) -> None:
    if require_absent and path.exists():
        raise FileExistsError("target_already_exists")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(raw)
    try:
        os.fchmod(descriptor, 0o644)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        if require_absent and path.exists():
            raise FileExistsError("target_already_exists")
        os.replace(temporary, path)
        path.chmod(0o644)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
