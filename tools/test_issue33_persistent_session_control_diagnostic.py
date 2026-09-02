from datetime import datetime, timezone
from io import StringIO
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock

from issue33_persistent_session_control_board_probe import (
    apply_application_zero_intent,
)
from issue33_persistent_session_control_diagnostic import (
    AUTHORIZATION_TOKEN,
    execute_diagnostic,
    main,
    provider_bundle_sha256,
)


class Issue33PersistentSessionControlDiagnosticTest(unittest.TestCase):
    def test_board_probe_sends_exact_zero_intent_through_application_service(self):
        service = Mock()
        service.apply_intent.return_value = Mock(
            status="applied",
            accepted_seq=1,
        )
        sent_at = datetime(2026, 8, 28, 8, 0, tzinfo=timezone.utc)

        result = apply_application_zero_intent(
            service,
            session_id="manual_mapping_" + "a" * 32,
            actor_id="issue33-persistent-session-control-diagnostic",
            lease_id="mapping_lease_" + "b" * 32,
            lease_epoch=7,
            sent_at=sent_at,
        )

        service.apply_intent.assert_called_once_with(
            session_id="manual_mapping_" + "a" * 32,
            actor_id="issue33-persistent-session-control-diagnostic",
            lease_id="mapping_lease_" + "b" * 32,
            lease_epoch=7,
            seq=1,
            sent_at=sent_at,
            ttl_ms=200,
            linear=0.0,
            angular=0.0,
        )
        self.assertEqual(result.status, "applied")

    def test_missing_authorization_never_invokes_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diagnostic.json"
            runner = Mock()

            with self.assertRaisesRegex(
                PermissionError,
                "persistent_session_control_diagnostic_authorization_required",
            ):
                execute_diagnostic(
                    output,
                    authorization_token="",
                    run_command=runner,
                )

            runner.assert_not_called()
            self.assertFalse(output.exists())

    def test_success_writes_exact_zero_motion_staged_result(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diagnostic.json"
            result = _result(status="passed")
            runner = _runner(result=result, returncode=0)

            actual = execute_diagnostic(
                output,
                authorization_token=AUTHORIZATION_TOKEN,
                run_command=runner,
            )

            self.assertEqual(actual, result)
            self.assertEqual(json.loads(output.read_text()), result)
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)
            self.assertEqual(result["zero_intent"], {"linear": 0.0, "angular": 0.0})
            command = runner.call_args.args[0]
            self.assertEqual(command[0], "ssh")
            self.assertIn("BatchMode=yes", command)
            self.assertIn("ztl@172.22.205.19", command)

    def test_failed_remote_stage_is_preserved_when_services_are_safe(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diagnostic.json"
            result = _result(
                status="failed",
                failed_stage="application_control_acquired",
                error="MAPPING_GUARD_UNAVAILABLE",
            )
            runner = _runner(result=result, returncode=6, stderr="probe failed")

            actual = execute_diagnostic(
                output,
                authorization_token=AUTHORIZATION_TOKEN,
                run_command=runner,
            )

            self.assertEqual(actual, result)
            self.assertEqual(json.loads(output.read_text()), result)

    def test_failed_mapping_start_without_session_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diagnostic.json"
            result = _result(
                status="failed",
                failed_stage="mapping_started",
                error="MAPPING_BOARD_PRECHECK_FAILED",
            )
            result["session_id"] = None
            result["session_process_reused"] = False
            runner = _runner(result=result, returncode=6)

            actual = execute_diagnostic(
                output,
                authorization_token=AUTHORIZATION_TOKEN,
                run_command=runner,
            )

            self.assertEqual(actual, result)
            self.assertEqual(json.loads(output.read_text()), result)

    def test_nonzero_intent_result_is_rejected_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diagnostic.json"
            result = _result(status="passed")
            result["zero_intent"] = {"linear": 0.01, "angular": 0.0}
            runner = _runner(result=result, returncode=0)

            with self.assertRaisesRegex(
                RuntimeError,
                "persistent_session_control_diagnostic_result_invalid",
            ):
                execute_diagnostic(
                    output,
                    authorization_token=AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(output.exists())

    def test_unsafe_final_service_state_never_writes_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "diagnostic.json"
            runner = _runner(
                result=_result(status="passed"),
                returncode=0,
                service_state="manual:active,runtime:active,navigation:inactive",
            )

            with self.assertRaisesRegex(RuntimeError, "safe_service_state_not_restored"):
                execute_diagnostic(
                    output,
                    authorization_token=AUTHORIZATION_TOKEN,
                    run_command=runner,
                )

            self.assertFalse(output.exists())

    def test_dry_run_reports_zero_only_and_never_invokes_ssh(self):
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "diagnostic.json"
            stdout = StringIO()

            exit_code = main(
                ["--output", str(output_path), "--dry-run"],
                stdout=stdout,
            )

            self.assertEqual(exit_code, 0)
            self.assertFalse(output_path.exists())
            self.assertIn("linear=0.0 angular=0.0", stdout.getvalue())
            self.assertIn("no_motion=true", stdout.getvalue())


def _runner(
    *,
    result: dict[str, object],
    returncode: int,
    stderr: str = "",
    service_state: str = "manual:inactive,runtime:inactive,navigation:active",
) -> Mock:
    return Mock(
        return_value=subprocess.CompletedProcess(
            args=["ssh"],
            returncode=returncode,
            stdout=(
                "ISSUE33_DIAGNOSTIC_RESULT="
                + json.dumps(result, sort_keys=True)
                + "\nISSUE33_SERVICE_STATE="
                + service_state
                + "\n"
            ),
            stderr=stderr,
        )
    )


def _result(
    *,
    status: str,
    failed_stage: str | None = None,
    error: str | None = None,
) -> dict[str, object]:
    stages = [
        "mapping_started",
        "runtime_ready",
        "application_session_started",
        "application_control_acquired",
        "application_zero_intent_applied",
        "application_stop_confirmed",
        "application_session_abandoned",
        "mapping_stopped",
    ]
    return {
        "schema_version": "1.0",
        "issue": 33,
        "kind": "persistent_session_application_control_no_motion_diagnostic",
        "status": status,
        "completed_stages": (
            stages
            if status == "passed"
            else stages[: stages.index(str(failed_stage))]
        ),
        "failed_stage": failed_stage,
        "error": error,
        "operation_id": "mapping_" + "a" * 32,
        "session_id": "manual_mapping_" + "b" * 32,
        "lease_id": "mapping_lease_" + "c" * 32 if status == "passed" else None,
        "zero_intent": {"linear": 0.0, "angular": 0.0},
        "accepted_seq": 1 if status == "passed" else 0,
        "intent_status": "applied" if status == "passed" else None,
        "stop_confirmed": status == "passed",
        "terminal_phase": "abandoned" if status == "passed" else None,
        "terminal_outcome": "abandoned" if status == "passed" else None,
        "application_service": "RealManualMappingService",
        "session_process_reused": True,
        "provider_bundle_sha256": provider_bundle_sha256(),
        "cleanup_errors": [],
    }


if __name__ == "__main__":
    unittest.main()
