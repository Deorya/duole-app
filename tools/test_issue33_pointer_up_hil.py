from datetime import datetime, timedelta, timezone
from io import StringIO
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from issue33_pointer_up_board_probe import corridor_forward_clearance
from issue33_pointer_up_hil import (
    MOTION_AUTHORIZATION_TOKEN,
    execute_pointer_up_hil,
    main,
)


class Issue33PointerUpHilTest(unittest.TestCase):
    def test_missing_authorization_never_invokes_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock()
            output = Path(directory) / "pointer-up.json"

            with self.assertRaisesRegex(PermissionError, "motion_authorization_required"):
                execute_pointer_up_hil(
                    output,
                    authorization_token="",
                    run_command=runner,
                )

            runner.assert_not_called()
            self.assertFalse(output.exists())

    def test_success_requires_valid_telemetry_and_restored_service_state(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "pointer-up.json"
            telemetry = _telemetry()
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    args=["ssh"],
                    returncode=0,
                    stdout=(
                        "ISSUE33_STOP_TELEMETRY="
                        + json.dumps(telemetry, sort_keys=True)
                        + "\n"
                        + "ISSUE33_SERVICE_STATE="
                        + "manual:inactive,runtime:inactive,navigation:active\n"
                    ),
                    stderr="",
                )
            )

            result = execute_pointer_up_hil(
                output,
                authorization_token=MOTION_AUTHORIZATION_TOKEN,
                run_command=runner,
            )

            self.assertEqual(result, telemetry)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), telemetry)
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)
            command = runner.call_args.args[0]
            self.assertEqual(command[0], "ssh")
            self.assertIn("ztl@172.22.205.19", command)
            self.assertIn("BatchMode=yes", command)

    def test_unsafe_final_service_state_never_writes_telemetry(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "pointer-up.json"
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    args=["ssh"],
                    returncode=0,
                    stdout=(
                        "ISSUE33_STOP_TELEMETRY="
                        + json.dumps(_telemetry())
                        + "\n"
                        + "ISSUE33_SERVICE_STATE="
                        + "manual:active,runtime:active,navigation:inactive\n"
                    ),
                    stderr="",
                )
            )

            with self.assertRaisesRegex(RuntimeError, "safe_service_state_not_restored"):
                execute_pointer_up_hil(
                    output,
                    authorization_token=MOTION_AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(output.exists())

    def test_remote_failure_never_writes_telemetry(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "pointer-up.json"
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    args=["ssh"],
                    returncode=6,
                    stdout="ISSUE33_SERVICE_STATE=manual:inactive,runtime:inactive,navigation:active\n",
                    stderr="probe failed",
                )
            )

            with self.assertRaisesRegex(RuntimeError, "remote_probe_failed"):
                execute_pointer_up_hil(
                    output,
                    authorization_token=MOTION_AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(output.exists())

    def test_over_limit_stop_telemetry_is_rejected_after_safe_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "pointer-up.json"
            telemetry = _telemetry()
            fault_at = datetime.fromisoformat(str(telemetry["fault_at"]))
            telemetry["wheels_stopped_at"] = (
                fault_at + timedelta(milliseconds=1001)
            ).isoformat()
            telemetry["stop_latency_ms"] = 1001
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    args=["ssh"],
                    returncode=0,
                    stdout=(
                        "ISSUE33_STOP_TELEMETRY="
                        + json.dumps(telemetry)
                        + "\n"
                        + "ISSUE33_SERVICE_STATE="
                        + "manual:inactive,runtime:inactive,navigation:active\n"
                    ),
                    stderr="",
                )
            )

            with self.assertRaisesRegex(RuntimeError, "pointer_up_telemetry_invalid"):
                execute_pointer_up_hil(
                    output,
                    authorization_token=MOTION_AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(output.exists())

    def test_dry_run_reports_exact_target_without_invoking_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            output = StringIO()
            evidence = Path(directory) / "pointer-up.json"

            exit_code = main(
                ["--output", str(evidence), "--dry-run"],
                stdout=output,
            )

            self.assertEqual(exit_code, 0)
            self.assertFalse(evidence.exists())
            self.assertIn("ztl@172.22.205.19", output.getvalue())
            self.assertIn("approximately 0.06 m", output.getvalue())

    def test_corridor_gate_excludes_side_obstacle_but_keeps_center_obstacle(self):
        scan = _scan(
            center_distance=2.0,
            side_distance=0.95,
            side_angle_degrees=45,
        )

        clearance = corridor_forward_clearance(scan, half_width_m=0.28)

        self.assertAlmostEqual(clearance, 2.0, places=2)


def _telemetry() -> dict[str, object]:
    fault_at = datetime(2026, 8, 28, 1, 0, tzinfo=timezone.utc)
    stopped_at = fault_at + timedelta(milliseconds=800)
    return {
        "schema_version": "1.0",
        "issue": 33,
        "kind": "stop_telemetry",
        "scenario": "pointer_up",
        "lease_id": "mapping_lease_" + "b" * 32,
        "last_accepted_seq": 12,
        "fault_at": fault_at.isoformat(),
        "zero_at": (fault_at + timedelta(milliseconds=20)).isoformat(),
        "wheels_stopped_at": stopped_at.isoformat(),
        "stop_latency_ms": 800,
    }


class _Scan:
    angle_min: float
    angle_increment: float
    range_max: float
    ranges: list[float]


def _scan(
    *,
    center_distance: float,
    side_distance: float,
    side_angle_degrees: int,
) -> _Scan:
    import math

    scan = _Scan()
    scan.angle_min = -math.pi
    scan.angle_increment = math.radians(1)
    scan.range_max = 12.0
    scan.ranges = [float("inf")] * 361
    center_index = round((math.pi - scan.angle_min) / scan.angle_increment)
    side_angle = math.pi + math.radians(side_angle_degrees)
    while side_angle > math.pi:
        side_angle -= 2 * math.pi
    side_index = round((side_angle - scan.angle_min) / scan.angle_increment)
    scan.ranges[center_index] = center_distance
    scan.ranges[side_index] = side_distance
    return scan


if __name__ == "__main__":
    unittest.main()
