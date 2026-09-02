from datetime import datetime, timedelta, timezone
from io import StringIO
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from issue33_app_background_board_probe import invoke_app_background_action
from issue33_app_background_hil import (
    MOTION_AUTHORIZATION_TOKEN,
    execute_app_background_hil,
    main,
    provider_bundle_sha256,
)


class Issue33AppBackgroundHilTest(unittest.TestCase):
    def test_missing_authorization_never_invokes_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = Mock()
            telemetry = Path(directory) / "app-background.json"
            lifecycle = Path(directory) / "app-background-result.json"

            with self.assertRaisesRegex(PermissionError, "motion_authorization_required"):
                execute_app_background_hil(
                    telemetry,
                    lifecycle,
                    authorization_token="",
                    run_command=runner,
                )

            runner.assert_not_called()
            self.assertFalse(telemetry.exists())
            self.assertFalse(lifecycle.exists())

    def test_success_requires_bound_telemetry_lifecycle_and_safe_services(self):
        with tempfile.TemporaryDirectory() as directory:
            telemetry_path = Path(directory) / "app-background.json"
            lifecycle_path = Path(directory) / "app-background-result.json"
            telemetry = _telemetry()
            lifecycle = _lifecycle_result()
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    args=["ssh"],
                    returncode=0,
                    stdout=(
                        "ISSUE33_STOP_TELEMETRY="
                        + json.dumps(telemetry, sort_keys=True)
                        + "\nISSUE33_LIFECYCLE_RESULT="
                        + json.dumps(lifecycle, sort_keys=True)
                        + "\nISSUE33_SERVICE_STATE="
                        + "manual:inactive,runtime:inactive,navigation:active\n"
                    ),
                    stderr="",
                )
            )

            actual_telemetry, actual_lifecycle = execute_app_background_hil(
                telemetry_path,
                lifecycle_path,
                authorization_token=MOTION_AUTHORIZATION_TOKEN,
                run_command=runner,
            )

            self.assertEqual(actual_telemetry, telemetry)
            self.assertEqual(actual_lifecycle, lifecycle)
            self.assertEqual(
                json.loads(telemetry_path.read_text(encoding="utf-8")), telemetry
            )
            self.assertEqual(
                json.loads(lifecycle_path.read_text(encoding="utf-8")), lifecycle
            )
            self.assertEqual(telemetry_path.stat().st_mode & 0o777, 0o644)
            self.assertEqual(lifecycle_path.stat().st_mode & 0o777, 0o644)
            command = runner.call_args.args[0]
            self.assertEqual(command[0], "ssh")
            self.assertIn("ztl@172.22.205.19", command)
            self.assertIn("BatchMode=yes", command)

    def test_lifecycle_result_must_match_telemetry_lease_and_seq(self):
        with tempfile.TemporaryDirectory() as directory:
            telemetry_path = Path(directory) / "app-background.json"
            lifecycle_path = Path(directory) / "app-background-result.json"
            lifecycle = _lifecycle_result()
            lifecycle["last_accepted_seq"] = 99
            runner = _successful_runner(_telemetry(), lifecycle)

            with self.assertRaisesRegex(RuntimeError, "lifecycle_result_invalid"):
                execute_app_background_hil(
                    telemetry_path,
                    lifecycle_path,
                    authorization_token=MOTION_AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(telemetry_path.exists())
            self.assertFalse(lifecycle_path.exists())

    def test_failed_map_restore_or_new_activation_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            telemetry_path = Path(directory) / "app-background.json"
            lifecycle_path = Path(directory) / "app-background-result.json"
            lifecycle = _lifecycle_result()
            lifecycle["previous_active_map_restored"] = False
            lifecycle["new_map_activated"] = True
            runner = _successful_runner(_telemetry(), lifecycle)

            with self.assertRaisesRegex(RuntimeError, "lifecycle_result_invalid"):
                execute_app_background_hil(
                    telemetry_path,
                    lifecycle_path,
                    authorization_token=MOTION_AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(telemetry_path.exists())
            self.assertFalse(lifecycle_path.exists())

    def test_unsafe_final_service_state_never_writes_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            telemetry_path = Path(directory) / "app-background.json"
            lifecycle_path = Path(directory) / "app-background-result.json"
            runner = Mock(
                return_value=subprocess.CompletedProcess(
                    args=["ssh"],
                    returncode=0,
                    stdout=(
                        "ISSUE33_STOP_TELEMETRY="
                        + json.dumps(_telemetry())
                        + "\nISSUE33_LIFECYCLE_RESULT="
                        + json.dumps(_lifecycle_result())
                        + "\nISSUE33_SERVICE_STATE="
                        + "manual:active,runtime:active,navigation:inactive\n"
                    ),
                    stderr="",
                )
            )

            with self.assertRaisesRegex(RuntimeError, "safe_service_state_not_restored"):
                execute_app_background_hil(
                    telemetry_path,
                    lifecycle_path,
                    authorization_token=MOTION_AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(telemetry_path.exists())
            self.assertFalse(lifecycle_path.exists())

    def test_dry_run_reports_exact_action_without_invoking_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            output = StringIO()
            telemetry = Path(directory) / "app-background.json"
            lifecycle = Path(directory) / "app-background-result.json"

            exit_code = main(
                [
                    "--output",
                    str(telemetry),
                    "--lifecycle-output",
                    str(lifecycle),
                    "--dry-run",
                ],
                stdout=output,
            )

            self.assertEqual(exit_code, 0)
            self.assertFalse(telemetry.exists())
            self.assertFalse(lifecycle.exists())
            self.assertIn("ztl@172.22.205.19", output.getvalue())
            self.assertIn("RealManualMappingService.command_session", output.getvalue())
            self.assertIn("action=app_background", output.getvalue())

    def test_board_helper_invokes_exact_terminal_action(self):
        session = Mock(
            phase="terminated",
            outcome="unverified_saved",
            transition_reason="app_background",
            stop_confirmed=True,
        )
        service = Mock()
        service.command_session.return_value = session

        result = invoke_app_background_action(
            service,
            session_id="manual_mapping_" + "a" * 32,
            actor_id="device_session_issue33_hil",
        )

        service.command_session.assert_called_once_with(
            "manual_mapping_" + "a" * 32,
            actor_id="device_session_issue33_hil",
            action="app_background",
        )
        self.assertIs(result, session)


def _successful_runner(
    telemetry: dict[str, object],
    lifecycle: dict[str, object],
) -> Mock:
    return Mock(
        return_value=subprocess.CompletedProcess(
            args=["ssh"],
            returncode=0,
            stdout=(
                "ISSUE33_STOP_TELEMETRY="
                + json.dumps(telemetry)
                + "\nISSUE33_LIFECYCLE_RESULT="
                + json.dumps(lifecycle)
                + "\nISSUE33_SERVICE_STATE="
                + "manual:inactive,runtime:inactive,navigation:active\n"
            ),
            stderr="",
        )
    )


def _telemetry() -> dict[str, object]:
    fault_at = datetime(2026, 8, 28, 2, 0, tzinfo=timezone.utc)
    stopped_at = fault_at + timedelta(milliseconds=820)
    return {
        "schema_version": "1.0",
        "issue": 33,
        "kind": "stop_telemetry",
        "scenario": "app_background",
        "lease_id": "mapping_lease_" + "b" * 32,
        "last_accepted_seq": 12,
        "fault_at": fault_at.isoformat(),
        "zero_at": (fault_at + timedelta(milliseconds=20)).isoformat(),
        "wheels_stopped_at": stopped_at.isoformat(),
        "stop_latency_ms": 820,
    }


def _lifecycle_result() -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "issue": 33,
        "kind": "lifecycle_result",
        "scenario": "app_background",
        "operation_id": "mapping_" + "c" * 32,
        "session_id": "manual_mapping_" + "a" * 32,
        "lease_id": "mapping_lease_" + "b" * 32,
        "last_accepted_seq": 12,
        "action": "app_background",
        "release_reason": "terminal_app_background",
        "terminal_phase": "terminated",
        "terminal_outcome": "unverified_saved",
        "transition_reason": "app_background",
        "stop_confirmed": True,
        "save_kind": "unverified",
        "save_succeeded": True,
        "save_outcome": "unverified_saved",
        "charging_confirmed": True,
        "previous_active_map_restored": True,
        "new_map_activated": False,
        "real_manual_mapping_sha256": (
            "e928846e4fab0f341b4a9e32acc0cca0c57ab32db995ad8bb15c21672cce1a99"
        ),
        "provider_bundle_sha256": provider_bundle_sha256(),
    }


if __name__ == "__main__":
    unittest.main()
