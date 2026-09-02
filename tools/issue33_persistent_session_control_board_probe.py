#!/usr/bin/env python3
"""Navigation-board probe for one authorized zero-motion control diagnostic."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time


BOARD_AGENT = Path(
    "/home/ztl/duole-issue31-nav-ws/bin/issue31-navigation-board-agent"
)
ZERO_LINEAR = 0.0
ZERO_ANGULAR = 0.0
ACTOR_ID = "issue33-persistent-session-control-diagnostic"
INSTALLATION_ID = "issue33-persistent-session-control-diagnostic"
_STAGES = (
    "mapping_started",
    "runtime_ready",
    "application_session_started",
    "application_control_acquired",
    "application_zero_intent_applied",
    "application_stop_confirmed",
    "application_session_abandoned",
    "mapping_stopped",
)


def _run_local_agent(
    _ignored_command: object,
    **kwargs: object,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(BOARD_AGENT)],
        input=str(kwargs.get("input") or ""),
        capture_output=True,
        text=True,
        check=False,
        timeout=float(kwargs.get("timeout") or 30.0),
    )


def _service_active(unit: str) -> bool:
    completed = subprocess.run(
        ["/usr/bin/systemctl", "is-active", "--quiet", unit],
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    return completed.returncode == 0


def _error_chain(exc: BaseException) -> str:
    values: list[str] = []
    current: BaseException | None = exc
    while current is not None and len(values) < 6:
        value = str(current) or type(current).__name__
        if value not in values:
            values.append(value)
        current = current.__cause__ or current.__context__
    return " <- ".join(values)[:512]


def apply_application_zero_intent(
    service: object,
    *,
    session_id: str,
    actor_id: str,
    lease_id: str,
    lease_epoch: int,
    sent_at: datetime,
) -> object:
    return getattr(service, "apply_intent")(
        session_id=session_id,
        actor_id=actor_id,
        lease_id=lease_id,
        lease_epoch=lease_epoch,
        seq=1,
        sent_at=sent_at,
        ttl_ms=200,
        linear=ZERO_LINEAR,
        angular=ZERO_ANGULAR,
    )


def _emit_stage(stage: str) -> None:
    print(
        "ISSUE33_DIAGNOSTIC_STAGE="
        + json.dumps(
            {
                "stage": stage,
                "observed_at": datetime.now(timezone.utc).isoformat(),
            },
            sort_keys=True,
            separators=(",", ":"),
        ),
        flush=True,
    )


def main() -> int:
    from duole_central.app_gateway.real_manual_mapping import (
        NavigationBoardManualMappingSlam,
        RealManualMappingService,
    )
    from duole_central.app_gateway.navigation_board_ssh import (
        JsonLineBoardSession,
        SshNavigationBoardClient,
        SshNavigationBoardConfig,
    )

    digest = os.environ.get("ISSUE33_PROVIDER_BUNDLE_SHA256", "")
    token = secrets.token_hex(16)
    operation_id = "mapping_" + token
    session_id: str | None = None
    lease_id: str | None = None
    lease_epoch: int | None = None
    completed_stages: list[str] = []
    cleanup_errors: list[str] = []
    failed_stage: str | None = None
    error: str | None = None
    accepted_seq = 0
    intent_status: str | None = None
    stop_confirmed = False
    terminal_phase: str | None = None
    terminal_outcome: str | None = None
    mapping_started = False
    application_session_started = False
    application_control_acquired = False
    application_session_abandoned = False
    mapping_stopped = False
    board: SshNavigationBoardClient | None = None
    service: RealManualMappingService | None = None
    diagnostic_directory: tempfile.TemporaryDirectory[str] | None = None
    returncode = 6
    try:
        board = SshNavigationBoardClient(
            SshNavigationBoardConfig(
                host="ztl@localhost",
                identity_file=Path("/dev/null"),
                known_hosts_file=Path("/dev/null"),
                remote_command=str(BOARD_AGENT),
                command_timeout_seconds=30.0,
            ),
            command_runner=_run_local_agent,
            session_factory=lambda _command: JsonLineBoardSession(
                (str(BOARD_AGENT), "--session"),
                ready_timeout_seconds=30.0,
            ),
        )

        failed_stage = "mapping_started"
        board.start_mapping(operation_id=operation_id, mode="manual_mapping")
        mapping_started = True
        completed_stages.append("mapping_started")
        _emit_stage("mapping_started")

        failed_stage = "runtime_ready"
        deadline = time.monotonic() + 30.0
        while time.monotonic() < deadline and not (
            _service_active("duole-mapping-manual.service")
            and _service_active("duole-manual-mapping-runtime.service")
        ):
            time.sleep(0.1)
        if not (
            _service_active("duole-mapping-manual.service")
            and _service_active("duole-manual-mapping-runtime.service")
        ):
            raise RuntimeError("persistent_session_diagnostic_runtime_not_ready")
        completed_stages.append("runtime_ready")
        _emit_stage("runtime_ready")

        diagnostic_directory = tempfile.TemporaryDirectory(
            prefix="issue33-application-control-"
        )
        service = RealManualMappingService(
            Path(diagnostic_directory.name) / "manual-mapping.sqlite3",
            robot_id="robot-home",
            board=board,
            slam=NavigationBoardManualMappingSlam(board),
        )

        failed_stage = "application_session_started"
        session = service.start_session(
            mapping_operation_id=operation_id,
            actor_id=ACTOR_ID,
            installation_id=INSTALLATION_ID,
        )
        session_id = str(session.session_id)
        application_session_started = True
        completed_stages.append("application_session_started")
        _emit_stage("application_session_started")

        failed_stage = "application_control_acquired"
        lease = service.acquire_control(
            session_id=session_id,
            actor_id=ACTOR_ID,
        )
        lease_id = str(lease.lease_id)
        lease_epoch = int(lease.epoch)
        application_control_acquired = True
        completed_stages.append("application_control_acquired")
        _emit_stage("application_control_acquired")

        failed_stage = "application_zero_intent_applied"
        intent = apply_application_zero_intent(
            service,
            session_id=session_id,
            actor_id=ACTOR_ID,
            lease_id=lease_id,
            lease_epoch=lease_epoch,
            sent_at=datetime.now(timezone.utc),
        )
        intent_status = str(intent.status)
        accepted_seq = int(intent.accepted_seq)
        if intent_status != "applied" or accepted_seq != 1:
            raise RuntimeError(
                "persistent_session_application_zero_intent_not_applied"
            )
        completed_stages.append("application_zero_intent_applied")
        _emit_stage("application_zero_intent_applied")

        failed_stage = "application_stop_confirmed"
        stopped = service.release_control(
            session_id=session_id,
            actor_id=ACTOR_ID,
            lease_id=lease_id,
            lease_epoch=lease_epoch,
            reason="terminal_abandon",
        )
        if not stopped.stop_confirmed:
            raise RuntimeError(
                "persistent_session_application_stop_not_confirmed"
            )
        stop_confirmed = True
        completed_stages.append("application_stop_confirmed")
        _emit_stage("application_stop_confirmed")

        failed_stage = "application_session_abandoned"
        terminal = service.command_session(
            session_id,
            actor_id=ACTOR_ID,
            action="abandon",
        )
        terminal_phase = str(terminal.phase)
        terminal_outcome = str(terminal.outcome)
        if (
            terminal_phase != "abandoned"
            or terminal_outcome != "abandoned"
            or not terminal.stop_confirmed
        ):
            raise RuntimeError(
                "persistent_session_application_abandon_not_confirmed"
            )
        application_session_abandoned = True
        completed_stages.append("application_session_abandoned")
        _emit_stage("application_session_abandoned")

        failed_stage = "mapping_stopped"
        board.stop_mapping(operation_id=operation_id, mode="manual_mapping")
        mapping_stopped = True
        completed_stages.append("mapping_stopped")
        _emit_stage("mapping_stopped")
        failed_stage = None
        returncode = 0
    except Exception as exc:
        error = _error_chain(exc)
    finally:
        if board is not None:
            if (
                application_control_acquired
                and not stop_confirmed
                and session_id is not None
                and lease_id is not None
                and lease_epoch is not None
            ):
                try:
                    status = board.request_manual_mapping_stop(
                        session_id=session_id,
                        lease_id=lease_id,
                        epoch=lease_epoch,
                        reason="persistent_session_application_diagnostic_abort",
                    )
                    stop_confirmed = bool(status.stop_confirmed)
                except Exception as exc:
                    cleanup_errors.append("stop:" + _error_chain(exc))
            if (
                application_session_started
                and not application_session_abandoned
                and session_id is not None
            ):
                try:
                    if service is None:
                        raise RuntimeError("application_service_unavailable")
                    terminal = service.command_session(
                        session_id,
                        actor_id=ACTOR_ID,
                        action="abandon",
                    )
                    terminal_phase = str(terminal.phase)
                    terminal_outcome = str(terminal.outcome)
                    application_session_abandoned = (
                        terminal_phase == "abandoned"
                    )
                except Exception as exc:
                    cleanup_errors.append("abandon:" + _error_chain(exc))
            if mapping_started and not mapping_stopped:
                try:
                    board.stop_mapping(
                        operation_id=operation_id,
                        mode="manual_mapping",
                    )
                    mapping_stopped = True
                except Exception as exc:
                    cleanup_errors.append("mapping_stop:" + _error_chain(exc))
            board.close()
        if diagnostic_directory is not None:
            diagnostic_directory.cleanup()
        result = {
            "schema_version": "1.0",
            "issue": 33,
            "kind": "persistent_session_application_control_no_motion_diagnostic",
            "status": "passed" if returncode == 0 else "failed",
            "completed_stages": completed_stages,
            "failed_stage": failed_stage,
            "error": error,
            "operation_id": operation_id,
            "session_id": session_id,
            "lease_id": lease_id if application_control_acquired else None,
            "zero_intent": {
                "linear": ZERO_LINEAR,
                "angular": ZERO_ANGULAR,
            },
            "accepted_seq": accepted_seq,
            "intent_status": intent_status,
            "stop_confirmed": stop_confirmed,
            "terminal_phase": terminal_phase,
            "terminal_outcome": terminal_outcome,
            "application_service": "RealManualMappingService",
            "session_process_reused": mapping_started,
            "provider_bundle_sha256": digest,
            "cleanup_errors": cleanup_errors,
        }
        print(
            "ISSUE33_DIAGNOSTIC_RESULT="
            + json.dumps(result, sort_keys=True, separators=(",", ":")),
            flush=True,
        )
    return returncode


if __name__ == "__main__":
    raise SystemExit(main())
