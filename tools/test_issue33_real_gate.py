from datetime import datetime, timedelta, timezone
import hashlib
from io import StringIO
import json
from pathlib import Path
import tempfile
import unittest

from issue33_real_gate import REQUIRED_CHECKS, REQUIRED_STOP_SCENARIOS, main


class Issue33RealGateTest(unittest.TestCase):
    def test_required_matrix_uses_no_dock_manual_mapping_acceptance(self):
        self.assertIn("real_app_start_cover_manual_stop", REQUIRED_CHECKS)
        self.assertIn("normal_no_dock_unverified_save", REQUIRED_CHECKS)
        self.assertIn(
            "abandon_delete_and_operator_reposition",
            REQUIRED_CHECKS,
        )
        self.assertNotIn("real_depart_cover_manual_dock", REQUIRED_CHECKS)
        self.assertNotIn("normal_dock_verified_save", REQUIRED_CHECKS)
        self.assertNotIn("abandon_delete_and_manual_return", REQUIRED_CHECKS)

    def test_incomplete_evidence_never_writes_acceptance_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            evidence.write_text("{}", encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("FAIL evidence.schema_version", output.getvalue())

    def test_complete_real_evidence_writes_bound_read_only_marker(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_evidence(root)
            evidence.write_text(
                json.dumps(payload, sort_keys=True, separators=(",", ":")),
                encoding="utf-8",
            )
            evidence_digest = hashlib.sha256(evidence.read_bytes()).hexdigest()
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 0, output.getvalue())
            self.assertEqual(
                json.loads(marker.read_text(encoding="utf-8")),
                {
                    "schema_version": "1.0",
                    "issue": 33,
                    "verdict": "accepted",
                    "evidence_class": "REAL",
                    "robot_id": "robot-home",
                    "safety_profile_id": "manual_mapping_safe_low_speed_v1",
                    "worst_stop_latency_ms": 800,
                    "evidence_sha256": evidence_digest,
                    "evidence_path": str(evidence.resolve()),
                    "candidate_manifest_sha256": "c" * 64,
                },
            )
            self.assertEqual(marker.stat().st_mode & 0o777, 0o444)
            self.assertIn("PASS issue33_real_gate", output.getvalue())

    def test_evidence_without_candidate_manifest_digest_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_evidence(root)
            payload.pop("candidate_manifest_sha256", None)
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("candidate_manifest_sha256", output.getvalue())

    def test_external_video_cannot_be_reused_across_stop_scenarios(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_evidence(root)
            shared = payload["stops"]["pointer_up"]["evidence_ids"]
            payload["stops"]["app_background"]["evidence_ids"] = list(shared)
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("evidence.stops.app_background", output.getvalue())

    def test_preliminary_hil_matrix_can_write_acceptance_run_permit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            permit = root / "acceptance-permit.json"
            payload = _complete_evidence(root)
            payload["evidence_class"] = "PRELIMINARY_REAL"
            payload["completed_at"] = None
            for name in REQUIRED_STOP_SCENARIOS:
                payload["stops"][name] = {"status": "pending"}
            for name in REQUIRED_CHECKS:
                if name not in {
                    "hil_profile_clamp",
                    "hil_collision_slowdown_block",
                    "hil_default_unarmed_zero",
                    "mock_no_motion_regression",
                    "ordinary_teleop_remains_unavailable",
                }:
                    payload["checks"][name] = {"status": "pending"}
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--evidence",
                    str(evidence),
                    "--acceptance-permit",
                    str(permit),
                ],
                stdout=output,
            )

            self.assertEqual(exit_code, 0, output.getvalue())
            receipt = json.loads(permit.read_text(encoding="utf-8"))
            self.assertEqual(receipt["verdict"], "acceptance_run_permitted")
            self.assertEqual(receipt["evidence_class"], "PRELIMINARY_REAL")
            self.assertEqual(receipt["evidence_path"], str(evidence.resolve()))
            self.assertEqual(receipt["worst_stop_latency_ms"], 0)
            self.assertEqual(permit.stat().st_mode & 0o777, 0o444)

    def test_operator_observation_with_bound_telemetry_can_replace_video(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_operator_observation_evidence(root)
            evidence.write_text(
                json.dumps(payload, sort_keys=True, separators=(",", ":")),
                encoding="utf-8",
            )
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 0, output.getvalue())
            self.assertTrue(marker.exists())
            self.assertIn("PASS issue33_real_gate", output.getvalue())

    def test_operator_observation_fails_closed_when_required_field_is_false(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_operator_observation_evidence(root)
            observation_id = "operator-pointer_up"
            observation = root / str(
                payload["artifacts"][observation_id]["path"]
            )
            document = json.loads(observation.read_text(encoding="utf-8"))
            document["stable_final_stop"] = False
            _rewrite_json_artifact(
                observation,
                document,
                payload["artifacts"][observation_id],
            )
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("FAIL evidence.stops.pointer_up", output.getvalue())

    def test_log_without_video_or_operator_observation_cannot_pass_stop_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_operator_observation_evidence(root)
            payload["stops"]["pointer_up"]["evidence_ids"] = [
                "telemetry-pointer_up"
            ]
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("FAIL evidence.stops.pointer_up", output.getvalue())

    def test_operator_observation_cannot_be_reused_for_another_scenario(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_operator_observation_evidence(root)
            observation_id = "operator-pointer_up"
            observation = root / str(
                payload["artifacts"][observation_id]["path"]
            )
            document = json.loads(observation.read_text(encoding="utf-8"))
            document["scenario"] = "app_background"
            _rewrite_json_artifact(
                observation,
                document,
                payload["artifacts"][observation_id],
            )
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("FAIL evidence.stops.pointer_up", output.getvalue())

    def test_operator_observation_requires_telemetry_in_same_stop_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_operator_observation_evidence(root)
            observation_id = "operator-pointer_up"
            observation = root / str(
                payload["artifacts"][observation_id]["path"]
            )
            document = json.loads(observation.read_text(encoding="utf-8"))
            document["telemetry_evidence_id"] = "telemetry-app_background"
            _rewrite_json_artifact(
                observation,
                document,
                payload["artifacts"][observation_id],
            )
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("FAIL evidence.stops.pointer_up", output.getvalue())

    def test_operator_observation_rejects_telemetry_that_disagrees_with_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "evidence.json"
            marker = root / "accepted.json"
            payload = _complete_operator_observation_evidence(root)
            telemetry_id = "telemetry-pointer_up"
            telemetry = root / str(payload["artifacts"][telemetry_id]["path"])
            document = json.loads(telemetry.read_text(encoding="utf-8"))
            document["stop_latency_ms"] = int(document["stop_latency_ms"]) + 1
            _rewrite_json_artifact(
                telemetry,
                document,
                payload["artifacts"][telemetry_id],
            )
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                ["--evidence", str(evidence), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 1)
            self.assertFalse(marker.exists())
            self.assertIn("FAIL evidence.stops.pointer_up", output.getvalue())


def _complete_evidence(root: Path) -> dict[str, object]:
    started = datetime(2026, 8, 27, 12, 0, tzinfo=timezone.utc)
    stops = {}
    artifacts = {}
    for index, scenario in enumerate(REQUIRED_STOP_SCENARIOS):
        artifact_id = f"video-{scenario}"
        artifact = root / f"{artifact_id}.bin"
        artifact.write_bytes(f"external-real-wheel-stop-video:{scenario}".encode())
        artifacts[artifact_id] = {
            "path": artifact.name,
            "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
            "kind": "external_video",
        }
        fault_at = started + timedelta(seconds=index)
        latency = 300 + index * 50
        stopped_at = fault_at + timedelta(milliseconds=latency)
        stops[scenario] = {
            "status": "passed",
            "lease_id": f"mapping_lease_{index:032x}",
            "last_accepted_seq": index + 1,
            "fault_at": fault_at.isoformat(),
            "zero_at": (fault_at + timedelta(milliseconds=100)).isoformat(),
            "wheels_stopped_at": stopped_at.isoformat(),
            "stop_latency_ms": latency,
            "evidence_ids": [artifact_id],
        }
    checks = {}
    for name in REQUIRED_CHECKS:
        artifact_id = f"check-{name}"
        artifact = root / f"{artifact_id}.log"
        artifact.write_text(f"issue33 check evidence: {name}\n", encoding="utf-8")
        artifacts[artifact_id] = {
            "path": artifact.name,
            "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
            "kind": "log",
        }
        checks[name] = {"status": "passed", "evidence_ids": [artifact_id]}
    return {
        "schema_version": "1.0",
        "issue": 33,
        "candidate_manifest_sha256": "c" * 64,
        "evidence_class": "REAL",
        "robot_id": "robot-home",
        "started_at": started.isoformat(),
        "completed_at": (started + timedelta(minutes=45)).isoformat(),
        "versions": {
            "app": "1.7.0+33",
            "gateway": "0.4.0+33",
            "runtime": "0.2.0+33",
            "teleop_guard": "manual_mapping_guard.v1",
            "slam": "board_slam.v1",
            "navigation_board": "issue31-overlay+33",
            "base": "elderbot-base",
            "schema": "1.7.0",
            "hardware": "duole-home-robot",
            "safety_profile": "manual_mapping_safe_low_speed_v1",
        },
        "artifacts": artifacts,
        "stops": stops,
        "checks": checks,
    }


def _complete_operator_observation_evidence(root: Path) -> dict[str, object]:
    payload = _complete_evidence(root)
    payload["artifacts"] = {}
    for scenario, stop in payload["stops"].items():
        telemetry_id = f"telemetry-{scenario}"
        telemetry = root / f"{telemetry_id}.log"
        telemetry.write_text(
            json.dumps(
                {
                    "schema_version": "1.0",
                    "issue": 33,
                    "kind": "stop_telemetry",
                    "scenario": scenario,
                    "lease_id": stop["lease_id"],
                    "last_accepted_seq": stop["last_accepted_seq"],
                    "fault_at": stop["fault_at"],
                    "zero_at": stop["zero_at"],
                    "wheels_stopped_at": stop["wheels_stopped_at"],
                    "stop_latency_ms": stop["stop_latency_ms"],
                },
                sort_keys=True,
            ),
            encoding="utf-8",
        )
        payload["artifacts"][telemetry_id] = {
            "path": telemetry.name,
            "sha256": hashlib.sha256(telemetry.read_bytes()).hexdigest(),
            "kind": "log",
        }
        observation_id = f"operator-{scenario}"
        observation = root / f"{observation_id}.json"
        stopped_at = datetime.fromisoformat(str(stop["wheels_stopped_at"]))
        observation_document = {
            "schema_version": "1.0",
            "issue": 33,
            "kind": "operator_observation",
            "scenario": scenario,
            "operator_id": "onsite-operator-01",
            "observed_at": (stopped_at + timedelta(seconds=1)).isoformat(),
            "observation_mode": "direct_onsite",
            "emergency_stop_accessible": True,
            "robot_stopped": True,
            "visible_reverse": False,
            "continued_sliding": False,
            "stable_final_stop": True,
            "telemetry_evidence_id": telemetry_id,
        }
        observation.write_text(
            json.dumps(
                observation_document,
                sort_keys=True,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        payload["artifacts"][observation_id] = {
            "path": observation.name,
            "sha256": hashlib.sha256(observation.read_bytes()).hexdigest(),
            "kind": "operator_observation",
        }
        stop["evidence_ids"] = [telemetry_id, observation_id]
    for name in REQUIRED_CHECKS:
        artifact_id = f"check-{name}"
        artifact = root / f"{artifact_id}.log"
        artifact.write_text(f"issue33 check evidence: {name}\n", encoding="utf-8")
        payload["artifacts"][artifact_id] = {
            "path": artifact.name,
            "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
            "kind": "log",
        }
        payload["checks"][name] = {
            "status": "passed",
            "evidence_ids": [artifact_id],
        }
    return payload


def _rewrite_json_artifact(
    path: Path,
    document: dict[str, object],
    metadata: dict[str, object],
) -> None:
    path.write_text(
        json.dumps(document, sort_keys=True, separators=(",", ":")),
        encoding="utf-8",
    )
    metadata["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()


if __name__ == "__main__":
    unittest.main()
