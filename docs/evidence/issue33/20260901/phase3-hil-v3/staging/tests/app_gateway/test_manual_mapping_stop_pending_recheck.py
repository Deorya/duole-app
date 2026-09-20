from datetime import datetime, timedelta, timezone

from duole_central.app_gateway.mock_manual_mapping import (
    FakeTeleopGuard,
    MockManualMappingService,
)


NOW = datetime(2026, 9, 1, 13, 0, tzinfo=timezone.utc)


class _Clock:
    def __init__(self) -> None:
        self.value = NOW

    def __call__(self):
        return self.value

    def advance(self, delta: timedelta) -> None:
        self.value += delta


def test_expired_lease_keeps_binding_until_later_stop_confirmation(tmp_path) -> None:
    clock = _Clock()
    guard = FakeTeleopGuard(confirm_stop_immediately=False)
    service = MockManualMappingService(
        tmp_path / "manual-mapping.sqlite3",
        robot_id="robot-home",
        guard=guard,
        clock=clock,
    )
    session = service.start_session(
        mapping_operation_id="mapping_" + "a" * 32,
        actor_id="actor-alice",
        installation_id="installation-tablet-a",
    )
    lease = service.acquire_control(
        session.session_id,
        actor_id="actor-alice",
    )

    clock.advance(timedelta(milliseconds=401))
    pending = service.get_session(
        session.session_id,
        actor_id="actor-alice",
    )
    assert pending.control_state == "stop_pending"
    assert pending.stop_confirmed is False
    assert pending.lease_id == lease.lease_id

    guard.confirm_stop(session.session_id)
    stopped = service.get_session(
        session.session_id,
        actor_id="actor-alice",
    )
    assert stopped.control_state == "stopped"
    assert stopped.stop_confirmed is True
    assert stopped.lease_id is None
    assert stopped.transition_reason == "control_lease_expired"
