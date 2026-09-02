from datetime import datetime, timedelta, timezone
from io import StringIO
import json
from pathlib import Path
import tempfile
import unittest

from issue33_real_evidence_collector import (
    bundle_status,
    finalize_bundle,
    initialize_bundle,
    record_check,
    record_stop,
)
from issue33_real_gate import REQUIRED_CHECKS, REQUIRED_STOP_SCENARIOS, main as gate_main


VERSIONS = {
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
}
CANDIDATE_MANIFEST_SHA256 = "c" * 64


class Issue33RealEvidenceCollectorTest(unittest.TestCase):
    def test_init_creates_pending_complete_matrix_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "evidence.json"
            started = datetime(2026, 8, 28, 1, 0, tzinfo=timezone.utc)

            initialize_bundle(
                bundle,
                robot_id="robot-home",
                started_at=started,
                versions=VERSIONS,
                candidate_manifest_sha256=CANDIDATE_MANIFEST_SHA256,
            )

            payload = json.loads(bundle.read_text(encoding="utf-8"))
            self.assertEqual(payload["evidence_class"], "PRELIMINARY_REAL")
            self.assertIsNone(payload["completed_at"])
            self.assertEqual(set(payload["stops"]), set(REQUIRED_STOP_SCENARIOS))
            self.assertTrue(
                all(item == {"status": "pending"} for item in payload["stops"].values())
            )
            self.assertEqual(set(payload["checks"]), set(REQUIRED_CHECKS))
            self.assertEqual(bundle_status(bundle)["completed_stop_count"], 0)
            with self.assertRaisesRegex(FileExistsError, "bundle_already_exists"):
                initialize_bundle(
                    bundle,
                    robot_id="robot-home",
                    started_at=started,
                    versions=VERSIONS,
                    candidate_manifest_sha256=CANDIDATE_MANIFEST_SHA256,
                )

    def test_record_stop_binds_canonical_telemetry_and_operator_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / "evidence.json"
            started = datetime(2026, 8, 28, 1, 0, tzinfo=timezone.utc)
            initialize_bundle(
                bundle,
                robot_id="robot-home",
                started_at=started,
                versions=VERSIONS,
                candidate_manifest_sha256=CANDIDATE_MANIFEST_SHA256,
            )
            telemetry = _write_telemetry(root, "pointer_up", started, index=0)
            stopped_at = datetime.fromisoformat(
                json.loads(telemetry.read_text(encoding="utf-8"))["wheels_stopped_at"]
            )

            record_stop(
                bundle,
                scenario="pointer_up",
                telemetry_path=telemetry,
                operator_id="ztl-onsite",
                observed_at=stopped_at + timedelta(seconds=1),
                emergency_stop_accessible=True,
                robot_stopped=True,
                visible_reverse=False,
                continued_sliding=False,
                stable_final_stop=True,
            )

            payload = json.loads(bundle.read_text(encoding="utf-8"))
            stop = payload["stops"]["pointer_up"]
            self.assertEqual(stop["status"], "passed")
            self.assertEqual(
                stop["evidence_ids"],
                ["pointer_up-stop-telemetry", "pointer_up-operator-observation"],
            )
            for artifact_id in stop["evidence_ids"]:
                artifact = payload["artifacts"][artifact_id]
                self.assertTrue((root / artifact["path"]).is_file())
            observation = json.loads(
                (root / payload["artifacts"][stop["evidence_ids"][1]]["path"]).read_text(
                    encoding="utf-8"
                )
            )
            self.assertEqual(observation["scenario"], "pointer_up")
            self.assertEqual(
                observation["telemetry_evidence_id"], "pointer_up-stop-telemetry"
            )
            with self.assertRaisesRegex(ValueError, "stop_already_recorded"):
                record_stop(
                    bundle,
                    scenario="pointer_up",
                    telemetry_path=telemetry,
                    operator_id="ztl-onsite",
                    observed_at=stopped_at + timedelta(seconds=1),
                    emergency_stop_accessible=True,
                    robot_stopped=True,
                    visible_reverse=False,
                    continued_sliding=False,
                    stable_final_stop=True,
                )

    def test_record_stop_rejects_mismatched_or_unsafe_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / "evidence.json"
            started = datetime(2026, 8, 28, 1, 0, tzinfo=timezone.utc)
            initialize_bundle(
                bundle,
                robot_id="robot-home",
                started_at=started,
                versions=VERSIONS,
                candidate_manifest_sha256=CANDIDATE_MANIFEST_SHA256,
            )
            telemetry = _write_telemetry(root, "app_background", started, index=1)

            with self.assertRaisesRegex(ValueError, "telemetry_scenario_mismatch"):
                record_stop(
                    bundle,
                    scenario="pointer_up",
                    telemetry_path=telemetry,
                    operator_id="ztl-onsite",
                    observed_at=started + timedelta(seconds=2),
                    emergency_stop_accessible=True,
                    robot_stopped=True,
                    visible_reverse=False,
                    continued_sliding=False,
                    stable_final_stop=True,
                )

            pointer_telemetry = _write_telemetry(root, "pointer_up", started, index=0)
            with self.assertRaisesRegex(ValueError, "operator_observation_not_passed"):
                record_stop(
                    bundle,
                    scenario="pointer_up",
                    telemetry_path=pointer_telemetry,
                    operator_id="ztl-onsite",
                    observed_at=started + timedelta(seconds=2),
                    emergency_stop_accessible=True,
                    robot_stopped=True,
                    visible_reverse=True,
                    continued_sliding=False,
                    stable_final_stop=True,
                )

    def test_finalize_fails_until_every_required_entry_is_recorded(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "evidence.json"
            started = datetime(2026, 8, 28, 1, 0, tzinfo=timezone.utc)
            initialize_bundle(
                bundle,
                robot_id="robot-home",
                started_at=started,
                versions=VERSIONS,
                candidate_manifest_sha256=CANDIDATE_MANIFEST_SHA256,
            )

            with self.assertRaisesRegex(ValueError, "bundle_incomplete"):
                finalize_bundle(bundle, completed_at=started + timedelta(minutes=10))

            self.assertEqual(
                json.loads(bundle.read_text(encoding="utf-8"))["evidence_class"],
                "PRELIMINARY_REAL",
            )

    def test_complete_operator_bundle_finalizes_and_passes_real_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / "evidence.json"
            marker = root / "accepted.json"
            started = datetime(2026, 8, 28, 1, 0, tzinfo=timezone.utc)
            initialize_bundle(
                bundle,
                robot_id="robot-home",
                started_at=started,
                versions=VERSIONS,
                candidate_manifest_sha256=CANDIDATE_MANIFEST_SHA256,
            )
            for index, scenario in enumerate(REQUIRED_STOP_SCENARIOS):
                telemetry = _write_telemetry(root, scenario, started, index=index)
                stopped_at = datetime.fromisoformat(
                    json.loads(telemetry.read_text(encoding="utf-8"))[
                        "wheels_stopped_at"
                    ]
                )
                record_stop(
                    bundle,
                    scenario=scenario,
                    telemetry_path=telemetry,
                    operator_id="ztl-onsite",
                    observed_at=stopped_at + timedelta(seconds=1),
                    emergency_stop_accessible=True,
                    robot_stopped=True,
                    visible_reverse=False,
                    continued_sliding=False,
                    stable_final_stop=True,
                )
            check_source = root / "check.log"
            check_source.write_text("issue33 acceptance check evidence\n", encoding="utf-8")
            for check in REQUIRED_CHECKS:
                record_check(
                    bundle,
                    check_name=check,
                    artifact_path=check_source,
                    kind="log",
                )
            completed = started + timedelta(minutes=45)
            finalize_bundle(bundle, completed_at=completed)

            status = bundle_status(bundle)
            self.assertTrue(status["ready_for_gate"])
            self.assertEqual(status["completed_stop_count"], len(REQUIRED_STOP_SCENARIOS))
            self.assertEqual(status["completed_check_count"], len(REQUIRED_CHECKS))
            output = StringIO()
            exit_code = gate_main(
                ["--evidence", str(bundle), "--marker", str(marker)],
                stdout=output,
            )

            self.assertEqual(exit_code, 0, output.getvalue())
            self.assertTrue(marker.is_file())


def _write_telemetry(
    root: Path,
    scenario: str,
    started: datetime,
    *,
    index: int,
) -> Path:
    fault_at = started + timedelta(seconds=index * 2)
    latency = 300 + index * 50
    stopped_at = fault_at + timedelta(milliseconds=latency)
    path = root / f"source-{scenario}.json"
    path.write_text(
        json.dumps(
            {
                "schema_version": "1.0",
                "issue": 33,
                "kind": "stop_telemetry",
                "scenario": scenario,
                "lease_id": f"mapping_lease_{index:032x}",
                "last_accepted_seq": index + 1,
                "fault_at": fault_at.isoformat(),
                "zero_at": (fault_at + timedelta(milliseconds=100)).isoformat(),
                "wheels_stopped_at": stopped_at.isoformat(),
                "stop_latency_ms": latency,
            },
            sort_keys=True,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
    return path


if __name__ == "__main__":
    unittest.main()
