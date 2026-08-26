import hashlib
from io import StringIO
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from issue31_hil_gate import main


class Issue31HilGateTest(unittest.TestCase):
    def test_gate_reports_unusable_adb_without_a_traceback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps({}), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "wrong-architecture-adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_unusable_adb,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn("FAIL adb_devices: unavailable", output.getvalue())

    def test_gate_rejects_when_fewer_than_two_android_phones(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps({}), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_one_phone_and_one_linux_robot,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn("FAIL android_phones: found 1, need at least 2", output.getvalue())

    def test_gate_rejects_android_emulator_as_second_physical_phone(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps({}), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_one_phone_and_one_android_emulator,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL android_phones: found 1, need at least 2",
            output.getvalue(),
        )

    def test_gate_replaces_invalid_utf8_from_adb_device_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps({}), encoding="utf-8")
            output = StringIO()

            def replacement_decoding_runner(command, **kwargs):
                self.assertEqual(kwargs.get("encoding"), "utf-8")
                self.assertEqual(kwargs.get("errors"), "replace")
                return _two_android_phones(command, **kwargs)

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=replacement_decoding_runner,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn("PASS android_phones: 2", output.getvalue())

    def test_gate_rejects_evidence_without_the_issue_31_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps({}), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.schema_version: expected 1.0",
            output.getvalue(),
        )

    def test_gate_requires_two_distinct_real_map_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            payload = _complete_evidence(root, digest)
            payload["map_ids"] = ["map-home", "map-home"]
            evidence.write_text(
                json.dumps(payload),
                encoding="utf-8",
            )
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.map_ids: need 2 distinct map IDs",
            output.getvalue(),
        )

    def test_gate_binds_evidence_to_two_connected_android_phones(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            payload = _complete_evidence(root, digest)
            payload["phone_serials"] = ["phone-a", "offline-phone"]
            evidence.write_text(
                json.dumps(payload),
                encoding="utf-8",
            )
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.phone_serials: need 2 connected Android phones",
            output.getvalue(),
        )

    def test_gate_rejects_when_a_required_hil_check_is_missing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            payload = _complete_evidence(root, digest)
            payload["checks"] = {}
            evidence.write_text(
                json.dumps(payload),
                encoding="utf-8",
            )
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.checks: missing screen_qr_exchange",
            output.getvalue(),
        )

    def test_gate_rejects_a_required_hil_check_that_did_not_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            payload = _complete_evidence(root, digest)
            payload["checks"]["screen_qr_exchange"]["status"] = "failed"
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.checks.screen_qr_exchange: status must be passed",
            output.getvalue(),
        )

    def test_gate_requires_an_artifact_reference_for_each_hil_check(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            payload = _complete_evidence(root, digest)
            payload["checks"]["screen_qr_exchange"]["evidence_ids"] = []
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.checks.screen_qr_exchange: evidence_ids required",
            output.getvalue(),
        )

    def test_complete_bound_evidence_package_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            evidence = root / "evidence.json"
            evidence.write_text(
                json.dumps(_complete_evidence(root, digest)),
                encoding="utf-8",
            )
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 0, output.getvalue())
        self.assertIn("PASS evidence.artifacts: 1 verified", output.getvalue())

    def test_gate_rejects_evidence_for_a_different_apk(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            payload = _complete_evidence(root, digest)
            payload["apk_sha256"] = "0" * 64
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn("FAIL evidence.apk_sha256", output.getvalue())

    def test_gate_rejects_check_timestamp_outside_session(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            payload = _complete_evidence(root, digest)
            payload["checks"]["screen_qr_exchange"]["observed_at"] = (
                "2026-08-25T23:59:59Z"
            )
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.checks.screen_qr_exchange.observed_at",
            output.getvalue(),
        )

    def test_gate_rejects_unredacted_secret_material(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            payload = _complete_evidence(root, digest)
            payload["checks"]["screen_qr_exchange"]["token"] = (
                "mapping-authorization-secret"
            )
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn("FAIL evidence.secrets: unredacted token", output.getvalue())

    def test_gate_requires_operation_and_event_ids_for_recovery_check(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk = root / "app-debug.apk"
            apk.write_bytes(b"signed-apk-fixture")
            digest = hashlib.sha256(apk.read_bytes()).hexdigest()
            payload = _complete_evidence(root, digest)
            del payload["checks"]["stable_operation_event_recovery"][
                "operation_ids"
            ]
            evidence = root / "evidence.json"
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            output = StringIO()

            exit_code = main(
                [
                    "--apk",
                    str(apk),
                    "--expected-apk-sha256",
                    digest,
                    "--adb-bin",
                    "adb",
                    "--evidence",
                    str(evidence),
                ],
                command_runner=_two_android_phones,
                stdout=output,
            )

        self.assertEqual(exit_code, 1)
        self.assertIn(
            "FAIL evidence.checks.stable_operation_event_recovery.operation_ids",
            output.getvalue(),
        )


def _one_phone_and_one_linux_robot(command, **_kwargs):
    if command == ["adb", "devices", "-l"]:
        return subprocess.CompletedProcess(
            command,
            0,
            stdout=(
                "List of devices attached\n"
                "phone-a device product:PHK110 transport_id:1\n"
                "emulator-5554 device transport_id:2\n"
            ),
            stderr="",
        )
    if command[:3] == ["adb", "-s", "phone-a"]:
        return subprocess.CompletedProcess(command, 0, stdout="35\n", stderr="")
    if command[:3] == ["adb", "-s", "emulator-5554"]:
        return subprocess.CompletedProcess(command, 127, stdout="", stderr="getprop: not found")
    raise AssertionError(f"unexpected command: {command}")


def _one_phone_and_one_android_emulator(command, **_kwargs):
    if command == ["adb", "devices", "-l"]:
        return subprocess.CompletedProcess(
            command,
            0,
            stdout=(
                "List of devices attached\n"
                "phone-a device product:PHK110 transport_id:1\n"
                "emulator-5554 device product:sdk_gphone64_arm64 transport_id:2\n"
            ),
            stderr="",
        )
    if command[-1] == "ro.build.version.sdk":
        return subprocess.CompletedProcess(command, 0, stdout="35\n", stderr="")
    if command[-1] == "ro.kernel.qemu":
        value = "1\n" if command[2] == "emulator-5554" else "\n"
        return subprocess.CompletedProcess(command, 0, stdout=value, stderr="")
    raise AssertionError(f"unexpected command: {command}")


def _unusable_adb(_command, **_kwargs):
    raise OSError(8, "Exec format error")


def _two_android_phones(command, **_kwargs):
    if command == ["adb", "devices", "-l"]:
        return subprocess.CompletedProcess(
            command,
            0,
            stdout=(
                "List of devices attached\n"
                "phone-a device product:PHK110 transport_id:1\n"
                "phone-b device product:PHK110 transport_id:2\n"
            ),
            stderr="",
        )
    if command[:3] in (
        ["adb", "-s", "phone-a"],
        ["adb", "-s", "phone-b"],
    ):
        return subprocess.CompletedProcess(command, 0, stdout="35\n", stderr="")
    raise AssertionError(f"unexpected command: {command}")


def _complete_evidence(root, apk_digest):
    check_names = (
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
    artifact = root / "artifacts" / "session.log"
    artifact.parent.mkdir()
    artifact.write_text("redacted issue 31 HIL session\n", encoding="utf-8")
    artifact_digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    payload = {
        "schema_version": "1.0",
        "issue": 31,
        "robot_id": "robot-home",
        "apk_sha256": apk_digest,
        "started_at": "2026-08-26T00:55:00Z",
        "completed_at": "2026-08-26T02:00:00Z",
        "map_ids": ["map-home", "map-office"],
        "phone_serials": ["phone-a", "phone-b"],
        "artifacts": {
            "session-log": {
                "path": "artifacts/session.log",
                "sha256": artifact_digest,
                "media_type": "text/plain",
            }
        },
        "checks": {
            name: {
                "status": "passed",
                "observed_at": "2026-08-26T01:00:00Z",
                "evidence_ids": ["session-log"],
            }
            for name in check_names
        },
    }
    payload["checks"]["stable_operation_event_recovery"].update(
        {
            "operation_ids": ["map_switch_0123456789abcdef"],
            "event_ids": ["event_0123456789abcdef"],
        }
    )
    return payload


if __name__ == "__main__":
    unittest.main()
