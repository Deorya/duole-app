#!/usr/bin/env python3
"""Fail-closed HIL/REAL acceptance gate for Duole App Issue 33."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timedelta
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import Mapping, Sequence, TextIO


REQUIRED_STOP_SCENARIOS = (
    "pointer_up",
    "app_background",
    "screen_locked",
    "app_process_ended",
    "reconnect_timeout",
    "ap_wifi_failure",
    "ipc_failure",
    "gateway_restart",
    "guard_restart",
    "slam_restart",
    "navigation_board_restart",
)
REQUIRED_CHECKS = (
    "hil_profile_clamp",
    "hil_collision_slowdown_block",
    "hil_default_unarmed_zero",
    "real_app_start_cover_manual_stop",
    "normal_no_dock_unverified_save",
    "unverified_save",
    "immediate_stop_save",
    "abandon_delete_and_operator_reposition",
    "atomic_snapshot_recovery_without_lease",
    "previous_map_restored_without_activation",
    "mock_no_motion_regression",
    "ordinary_teleop_remains_unavailable",
)
ACCEPTANCE_PERMIT_REQUIRED_CHECKS = (
    "hil_profile_clamp",
    "hil_collision_slowdown_block",
    "hil_default_unarmed_zero",
    "mock_no_motion_regression",
    "ordinary_teleop_remains_unavailable",
)
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
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_LEASE_ID = re.compile(r"^mapping_lease_[0-9a-f]{32}$")


@dataclass(frozen=True)
class _VerifiedArtifact:
    kind: str
    sha256: str
    document: Mapping[str, object] | None = None


def main(
    arguments: Sequence[str] | None = None,
    *,
    stdout: TextIO = sys.stdout,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--marker", type=Path)
    destination.add_argument("--acceptance-permit", type=Path)
    args = parser.parse_args(arguments)
    permit_requested = args.acceptance_permit is not None
    output_path = args.acceptance_permit if permit_requested else args.marker
    assert output_path is not None
    try:
        encoded = args.evidence.read_bytes()
        evidence = json.loads(encoded.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        stdout.write("FAIL evidence: unreadable\n")
        return 1
    if not isinstance(evidence, Mapping):
        stdout.write("FAIL evidence: object required\n")
        return 1
    if evidence.get("schema_version") != "1.0":
        stdout.write("FAIL evidence.schema_version: expected 1.0\n")
        return 1
    if evidence.get("issue") != 33:
        stdout.write("FAIL evidence.issue: expected 33\n")
        return 1
    expected_evidence_class = "PRELIMINARY_REAL" if permit_requested else "REAL"
    if evidence.get("evidence_class") != expected_evidence_class:
        stdout.write(
            "FAIL evidence.evidence_class: "
            f"expected {expected_evidence_class}\n"
        )
        return 1
    candidate_manifest_sha256 = evidence.get("candidate_manifest_sha256")
    if _SHA256.fullmatch(str(candidate_manifest_sha256)) is None:
        stdout.write("FAIL evidence.candidate_manifest_sha256: invalid\n")
        return 1
    robot_id = evidence.get("robot_id")
    if not isinstance(robot_id, str) or not robot_id.strip():
        stdout.write("FAIL evidence.robot_id: invalid\n")
        return 1
    try:
        started_at = _timestamp(evidence.get("started_at"))
        completed_at = (
            None
            if permit_requested and evidence.get("completed_at") is None
            else _timestamp(evidence.get("completed_at"))
        )
    except ValueError:
        stdout.write("FAIL evidence.session_time: invalid\n")
        return 1
    if permit_requested and completed_at is not None:
        stdout.write("FAIL evidence.completed_at: permit requires unfinished bundle\n")
        return 1
    if completed_at is not None and completed_at < started_at:
        stdout.write("FAIL evidence.session_time: reversed\n")
        return 1
    versions = evidence.get("versions")
    if (
        not isinstance(versions, Mapping)
        or set(versions) != _VERSION_KEYS
        or any(not isinstance(value, str) or not value.strip() for value in versions.values())
        or versions.get("safety_profile")
        != "manual_mapping_safe_low_speed_v1"
    ):
        stdout.write("FAIL evidence.versions: invalid or incomplete\n")
        return 1
    artifacts = _verified_artifacts(
        evidence.get("artifacts"),
        root=args.evidence.resolve().parent,
    )
    if artifacts is None:
        stdout.write("FAIL evidence.artifacts: invalid\n")
        return 1
    stops = evidence.get("stops")
    if not isinstance(stops, Mapping) or set(stops) != set(
        REQUIRED_STOP_SCENARIOS
    ):
        stdout.write("FAIL evidence.stops: required matrix incomplete\n")
        return 1
    latencies: list[int] = []
    used_stop_artifacts: set[str] = set()
    used_external_videos: set[str] = set()
    for scenario in REQUIRED_STOP_SCENARIOS:
        stop = stops[scenario]
        if permit_requested and stop == {"status": "pending"}:
            continue
        if not _valid_stop(
            stop,
            scenario=scenario,
            artifacts=artifacts,
            used_external_videos=used_external_videos,
        ):
            stdout.write(f"FAIL evidence.stops.{scenario}: invalid\n")
            return 1
        latencies.append(int(stop["stop_latency_ms"]))
        used_stop_artifacts.update(str(item) for item in stop["evidence_ids"])
    checks = evidence.get("checks")
    if not isinstance(checks, Mapping) or set(checks) != set(REQUIRED_CHECKS):
        stdout.write("FAIL evidence.checks: required matrix incomplete\n")
        return 1
    required_checks = (
        ACCEPTANCE_PERMIT_REQUIRED_CHECKS
        if permit_requested
        else REQUIRED_CHECKS
    )
    used_check_artifacts = set(used_stop_artifacts)
    for name in required_checks:
        check = checks[name]
        if not _valid_check_evidence(
            check,
            artifacts=artifacts,
            used_artifacts=used_check_artifacts,
        ):
            stdout.write(f"FAIL evidence.checks.{name}: invalid\n")
            return 1
    if permit_requested:
        for name in set(REQUIRED_CHECKS) - set(required_checks):
            check = checks[name]
            if check == {"status": "pending"}:
                continue
            if not _valid_check_evidence(
                check,
                artifacts=artifacts,
                used_artifacts=used_check_artifacts,
            ):
                stdout.write(f"FAIL evidence.checks.{name}: invalid\n")
                return 1
    worst_stop_latency_ms = max(latencies, default=0)
    receipt = {
        "schema_version": "1.0",
        "issue": 33,
        "verdict": (
            "acceptance_run_permitted" if permit_requested else "accepted"
        ),
        "evidence_class": expected_evidence_class,
        "robot_id": robot_id,
        "safety_profile_id": "manual_mapping_safe_low_speed_v1",
        "worst_stop_latency_ms": worst_stop_latency_ms,
        "evidence_sha256": hashlib.sha256(encoded).hexdigest(),
        "evidence_path": str(args.evidence.resolve()),
        "candidate_manifest_sha256": str(candidate_manifest_sha256),
    }
    try:
        _atomic_marker(output_path, receipt)
    except OSError:
        stdout.write("FAIL marker: cannot write atomically\n")
        return 1
    stdout.write(
        "PASS issue33_real_gate: "
        f"{'acceptance run permitted' if permit_requested else 'REAL accepted'}, "
        f"worst_stop_latency_ms={worst_stop_latency_ms}\n"
    )
    return 0


def _verified_artifacts(
    raw: object,
    *,
    root: Path,
) -> dict[str, _VerifiedArtifact] | None:
    if not isinstance(raw, Mapping) or not raw:
        return None
    verified: dict[str, _VerifiedArtifact] = {}
    for artifact_id, metadata in raw.items():
        if (
            not isinstance(artifact_id, str)
            or not artifact_id
            or not isinstance(metadata, Mapping)
            or set(metadata) != {"path", "sha256", "kind"}
            or metadata.get("kind")
            not in {"external_video", "log", "photo", "operator_observation"}
            or not isinstance(metadata.get("path"), str)
            or _SHA256.fullmatch(str(metadata.get("sha256"))) is None
        ):
            return None
        path = (root / str(metadata["path"])).resolve()
        try:
            path.relative_to(root)
            encoded = path.read_bytes()
            digest = hashlib.sha256(encoded).hexdigest()
        except (OSError, ValueError):
            return None
        if digest != metadata["sha256"]:
            return None
        document: Mapping[str, object] | None = None
        if metadata["kind"] in {"operator_observation", "log"}:
            try:
                decoded = json.loads(encoded.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                if metadata["kind"] == "operator_observation":
                    return None
            else:
                if not isinstance(decoded, Mapping):
                    if metadata["kind"] == "operator_observation":
                        return None
                else:
                    document = decoded
        verified[artifact_id] = _VerifiedArtifact(
            kind=str(metadata["kind"]),
            sha256=digest,
            document=document,
        )
    return verified


def _valid_stop(
    raw: object,
    *,
    scenario: str,
    artifacts: Mapping[str, _VerifiedArtifact],
    used_external_videos: set[str],
) -> bool:
    if not isinstance(raw, Mapping) or set(raw) != {
        "status",
        "lease_id",
        "last_accepted_seq",
        "fault_at",
        "zero_at",
        "wheels_stopped_at",
        "stop_latency_ms",
        "evidence_ids",
    }:
        return False
    if (
        raw.get("status") != "passed"
        or _LEASE_ID.fullmatch(str(raw.get("lease_id"))) is None
        or isinstance(raw.get("last_accepted_seq"), bool)
        or not isinstance(raw.get("last_accepted_seq"), int)
        or int(raw["last_accepted_seq"]) < 0
        or isinstance(raw.get("stop_latency_ms"), bool)
        or not isinstance(raw.get("stop_latency_ms"), int)
        or not 0 <= int(raw["stop_latency_ms"]) <= 1_000
        or not _valid_passed_evidence(raw, artifacts=artifacts, status_only=True)
    ):
        return False
    try:
        fault_at = _timestamp(raw.get("fault_at"))
        zero_at = _timestamp(raw.get("zero_at"))
        stopped_at = _timestamp(raw.get("wheels_stopped_at"))
    except ValueError:
        return False
    if not _valid_stop_evidence(
        raw["evidence_ids"],
        stop=raw,
        scenario=scenario,
        artifacts=artifacts,
        fault_at=fault_at,
        stopped_at=stopped_at,
        used_external_videos=used_external_videos,
    ):
        return False
    measured = round((stopped_at - fault_at).total_seconds() * 1_000)
    return (
        fault_at <= zero_at <= stopped_at
        and measured == raw["stop_latency_ms"]
    )


def _valid_stop_evidence(
    evidence_ids: object,
    *,
    stop: Mapping[str, object],
    scenario: str,
    artifacts: Mapping[str, _VerifiedArtifact],
    fault_at: datetime,
    stopped_at: datetime,
    used_external_videos: set[str],
) -> bool:
    if not isinstance(evidence_ids, list):
        return False
    external_videos = {
        str(evidence_id)
        for evidence_id in evidence_ids
        if artifacts[evidence_id].kind == "external_video"
    }
    if external_videos:
        if external_videos & used_external_videos:
            return False
        used_external_videos.update(external_videos)
        return True
    return any(
        _valid_operator_observation(
            artifacts[evidence_id],
            stop=stop,
            scenario=scenario,
            evidence_ids=evidence_ids,
            artifacts=artifacts,
            fault_at=fault_at,
            stopped_at=stopped_at,
        )
        for evidence_id in evidence_ids
        if artifacts[evidence_id].kind == "operator_observation"
    )


def _valid_operator_observation(
    artifact: _VerifiedArtifact,
    *,
    stop: Mapping[str, object],
    scenario: str,
    evidence_ids: list[object],
    artifacts: Mapping[str, _VerifiedArtifact],
    fault_at: datetime,
    stopped_at: datetime,
) -> bool:
    document = artifact.document
    if not isinstance(document, Mapping) or set(document) != {
        "schema_version",
        "issue",
        "kind",
        "scenario",
        "operator_id",
        "observed_at",
        "observation_mode",
        "emergency_stop_accessible",
        "robot_stopped",
        "visible_reverse",
        "continued_sliding",
        "stable_final_stop",
        "telemetry_evidence_id",
    }:
        return False
    operator_id = document.get("operator_id")
    telemetry_id = document.get("telemetry_evidence_id")
    if (
        document.get("schema_version") != "1.0"
        or document.get("issue") != 33
        or document.get("kind") != "operator_observation"
        or document.get("scenario") != scenario
        or not isinstance(operator_id, str)
        or not operator_id.strip()
        or document.get("observation_mode") != "direct_onsite"
        or document.get("emergency_stop_accessible") is not True
        or document.get("robot_stopped") is not True
        or document.get("visible_reverse") is not False
        or document.get("continued_sliding") is not False
        or document.get("stable_final_stop") is not True
        or not isinstance(telemetry_id, str)
        or telemetry_id not in evidence_ids
        or telemetry_id not in artifacts
        or artifacts[telemetry_id].kind != "log"
        or not _valid_bound_stop_telemetry(
            artifacts[telemetry_id],
            scenario=scenario,
            stop=stop,
        )
    ):
        return False
    try:
        observed_at = _timestamp(document.get("observed_at"))
    except ValueError:
        return False
    return fault_at <= observed_at <= stopped_at + timedelta(minutes=5)


def _valid_bound_stop_telemetry(
    artifact: _VerifiedArtifact,
    *,
    scenario: str,
    stop: Mapping[str, object],
) -> bool:
    document = artifact.document
    if not isinstance(document, Mapping) or set(document) != {
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
        return False
    return (
        document.get("schema_version") == "1.0"
        and document.get("issue") == 33
        and document.get("kind") == "stop_telemetry"
        and document.get("scenario") == scenario
        and document.get("lease_id") == stop.get("lease_id")
        and document.get("last_accepted_seq") == stop.get("last_accepted_seq")
        and document.get("fault_at") == stop.get("fault_at")
        and document.get("zero_at") == stop.get("zero_at")
        and document.get("wheels_stopped_at") == stop.get("wheels_stopped_at")
        and document.get("stop_latency_ms") == stop.get("stop_latency_ms")
    )


def _valid_passed_evidence(
    raw: object,
    *,
    artifacts: Mapping[str, _VerifiedArtifact],
    status_only: bool = False,
) -> bool:
    if not isinstance(raw, Mapping):
        return False
    if not status_only and set(raw) != {"status", "evidence_ids"}:
        return False
    evidence_ids = raw.get("evidence_ids")
    return (
        raw.get("status") == "passed"
        and isinstance(evidence_ids, list)
        and bool(evidence_ids)
        and all(
            isinstance(evidence_id, str) and evidence_id in artifacts
            for evidence_id in evidence_ids
        )
    )


def _valid_check_evidence(
    raw: object,
    *,
    artifacts: Mapping[str, _VerifiedArtifact],
    used_artifacts: set[str],
) -> bool:
    if not _valid_passed_evidence(raw, artifacts=artifacts):
        return False
    assert isinstance(raw, Mapping)
    evidence_ids = {str(item) for item in raw["evidence_ids"]}
    if evidence_ids & used_artifacts:
        return False
    if any(
        artifacts[evidence_id].kind
        not in {"external_video", "log", "photo"}
        for evidence_id in evidence_ids
    ):
        return False
    used_artifacts.update(evidence_ids)
    return True


def _timestamp(raw: object) -> datetime:
    if not isinstance(raw, str):
        raise ValueError("timestamp invalid")
    value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    if value.tzinfo is None:
        raise ValueError("timestamp timezone required")
    return value


def _atomic_marker(path: Path, marker: Mapping[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(raw)
    try:
        os.fchmod(descriptor, 0o444)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(
                dict(marker),
                stream,
                ensure_ascii=False,
                allow_nan=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        path.chmod(0o444)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
