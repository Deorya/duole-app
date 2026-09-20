from datetime import datetime, timedelta, timezone

import pytest

from duole_central.navigation_board.manual_mapping_guard import (
    ManualMappingGuardError,
    ManualMappingSafetyProfile,
    ManualMappingTeleopGuard,
)


NOW = datetime(2026, 9, 1, 13, 34, 45, tzinfo=timezone.utc)
SESSION_ID = "manual_mapping_" + "e" * 32
LEASE_ID = "mapping_lease_" + "3" * 32


class _VelocitySink:
    def __init__(self) -> None:
        self.samples: list[tuple[float, float]] = []

    def publish(self, *, linear_mps: float, angular_radps: float) -> None:
        self.samples.append((linear_mps, angular_radps))


class _StoppedWheels:
    def is_stopped(self) -> bool:
        return True


def test_expired_first_intent_keeps_stop_binding_for_gateway_retry() -> None:
    current = [NOW]
    velocity = _VelocitySink()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=0.20,
            max_angular_accel_radps2=0.60,
            base_watchdog_timeout_ms=400,
        ),
        velocity_sink=velocity,
        stop_confirmation=_StoppedWheels(),
        clock=lambda: current[0],
    )
    guard.arm(session_id=SESSION_ID, lease_id=LEASE_ID, epoch=2)

    current[0] += timedelta(milliseconds=401)
    with pytest.raises(
        ManualMappingGuardError,
        match="manual_mapping_guard_lease_expired",
    ):
        guard.apply(
            session_id=SESSION_ID,
            lease_id=LEASE_ID,
            epoch=2,
            seq=1,
            sent_at=current[0],
            ttl_ms=200,
            linear=1.0,
            angular=0.0,
        )

    confirmed = guard.request_stop(
        session_id=SESSION_ID,
        lease_id=LEASE_ID,
        epoch=2,
        reason="websocket_closed",
    )
    assert confirmed.state == "stopped"
    assert confirmed.stop_confirmed is True
    assert confirmed.reason == "manual_mapping_guard_lease_expired"
    assert confirmed.session_id == SESSION_ID
    assert confirmed.lease_id == LEASE_ID
    assert confirmed.epoch == 2
    assert velocity.samples[-1] == (0.0, 0.0)
