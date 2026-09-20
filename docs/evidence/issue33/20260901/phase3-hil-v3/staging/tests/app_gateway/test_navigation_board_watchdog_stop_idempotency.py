from datetime import datetime, timedelta, timezone

import pytest

from duole_central.navigation_board.manual_mapping_guard import (
    ManualMappingGuardError,
    ManualMappingSafetyProfile,
    ManualMappingTeleopGuard,
)
from duole_central.navigation_board.manual_mapping_guard_ipc import (
    ManualMappingGuardIpcClient,
    ManualMappingGuardIpcServer,
)


NOW = datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
SESSION_ID = "manual_mapping_" + "a" * 32
LEASE_ID = "mapping_lease_" + "b" * 32


class _VelocitySink:
    def __init__(self) -> None:
        self.samples: list[tuple[float, float]] = []

    def publish(self, *, linear_mps: float, angular_radps: float) -> None:
        self.samples.append((linear_mps, angular_radps))


class _StopConfirmation:
    def __init__(self, stopped: bool) -> None:
        self.stopped = stopped

    def is_stopped(self) -> bool:
        return self.stopped


def _guard(current, velocity, confirmation):
    return ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=0.20,
            max_angular_accel_radps2=0.60,
            base_watchdog_timeout_ms=400,
        ),
        velocity_sink=velocity,
        stop_confirmation=confirmation,
        clock=lambda: current[0],
    )


def test_watchdog_stop_can_be_confirmed_idempotently_by_gateway() -> None:
    current = [NOW]
    velocity = _VelocitySink()
    confirmation = _StopConfirmation(False)
    guard = _guard(current, velocity, confirmation)
    guard.arm(session_id=SESSION_ID, lease_id=LEASE_ID, epoch=1)

    current[0] += timedelta(milliseconds=401)
    revoked = guard.poll_watchdog()
    assert revoked is not None
    assert velocity.samples[-1] == (0.0, 0.0)

    pending = guard.request_stop(
        session_id=SESSION_ID,
        lease_id=LEASE_ID,
        epoch=1,
        reason="websocket_closed",
    )
    assert pending.state == "stop_pending"
    assert pending.reason == "base_watchdog_timeout"

    confirmation.stopped = True
    current[0] += timedelta(milliseconds=250)
    confirmed = guard.request_stop(
        session_id=SESSION_ID,
        lease_id=LEASE_ID,
        epoch=1,
        reason="websocket_closed",
    )
    assert confirmed.state == "stopped"
    assert confirmed.stop_confirmed is True
    assert confirmed.reason == "base_watchdog_timeout"
    assert confirmed.stop_confirmed_at == current[0]


def test_watchdog_stop_does_not_authorize_a_different_lease() -> None:
    current = [NOW]
    guard = _guard(current, _VelocitySink(), _StopConfirmation(True))
    guard.arm(session_id=SESSION_ID, lease_id=LEASE_ID, epoch=1)
    current[0] += timedelta(milliseconds=401)
    guard.poll_watchdog()

    with pytest.raises(
        ManualMappingGuardError,
        match="manual_mapping_guard_lease_mismatch",
    ):
        guard.request_stop(
            session_id=SESSION_ID,
            lease_id="mapping_lease_" + "c" * 32,
            epoch=1,
            reason="websocket_closed",
        )


def test_watchdog_stop_confirmation_crosses_guard_ipc(tmp_path) -> None:
    current = [NOW]
    confirmation = _StopConfirmation(True)
    guard = _guard(current, _VelocitySink(), confirmation)
    socket_path = tmp_path / "guard" / "manual-mapping.sock"

    with ManualMappingGuardIpcServer(socket_path, guard):
        client = ManualMappingGuardIpcClient(socket_path)
        client.arm(session_id=SESSION_ID, lease_id=LEASE_ID, epoch=1)
        current[0] += timedelta(milliseconds=401)
        assert guard.poll_watchdog() is not None

        confirmed = client.request_stop(
            session_id=SESSION_ID,
            lease_id=LEASE_ID,
            epoch=1,
            reason="websocket_closed",
        )

    assert confirmed.state == "stopped"
    assert confirmed.stop_confirmed is True
    assert confirmed.reason == "base_watchdog_timeout"
