from __future__ import annotations

from datetime import datetime, timedelta, timezone
import threading
import time

import pytest

from duole_central.navigation_board.agent import NavigationBoardAgent
from duole_central.navigation_board.manual_mapping_guard import (
    ManualMappingGuardError,
    ManualMappingSafetyProfile,
    ManualMappingTeleopGuard,
)
from duole_central.navigation_board.manual_mapping_guard_ipc import (
    MAX_MESSAGE_BYTES,
    ManualMappingGuardIpcClient,
    ManualMappingGuardIpcServer,
    ManualMappingSlamIpcClient,
)


NOW = datetime(2026, 8, 27, 8, 0, tzinfo=timezone.utc)


def test_board_agent_returns_local_arm_window_from_guard_ipc(tmp_path) -> None:
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=_VelocitySink(),
        clock=lambda: NOW,
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    with ManualMappingGuardIpcServer(socket_path, guard):
        agent = NavigationBoardAgent(
            switch_safety_source=object(),  # type: ignore[arg-type]
            manual_mapping_guard=ManualMappingGuardIpcClient(socket_path),
            clock=lambda: NOW,
        )
        result = agent.handle(
            {
                "schema_version": "1.0",
                "action": "manual_mapping_arm",
                "session_id": "manual_mapping_" + "a" * 32,
                "lease_id": "mapping_lease_" + "b" * 32,
                "epoch": 1,
            }
        )

    assert result["profile_id"] == "manual_mapping_safe_low_speed_v1"
    assert result["armed_at"] == NOW.isoformat()
    assert result["expires_at"] == (
        NOW + timedelta(milliseconds=400)
    ).isoformat()


def test_guard_lease_survives_independent_one_request_clients(tmp_path) -> None:
    current = [NOW]
    velocity = _VelocitySink()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=velocity,
        clock=lambda: current[0],
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "a" * 32
    lease_id = "mapping_lease_" + "b" * 32

    with ManualMappingGuardIpcServer(socket_path, guard):
        armed = ManualMappingGuardIpcClient(socket_path).arm(
            session_id=session_id,
            lease_id=lease_id,
            epoch=1,
        )
        current[0] = NOW + timedelta(milliseconds=100)
        result = ManualMappingGuardIpcClient(socket_path).apply(
            session_id=session_id,
            lease_id=lease_id,
            epoch=1,
            seq=1,
            sent_at=current[0],
            ttl_ms=200,
            linear=1.0,
            angular=-1.0,
        )

    assert armed.armed_at == NOW
    assert armed.expires_at == NOW + timedelta(milliseconds=400)
    assert result.status == "applied"
    assert result.accepted_seq == 1
    assert (0.10, -0.30) in velocity.samples


def test_persistent_runtime_shutdown_publishes_zero_velocity(tmp_path) -> None:
    current = [NOW]
    velocity = _VelocitySink()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=velocity,
        clock=lambda: current[0],
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "a" * 32
    lease_id = "mapping_lease_" + "b" * 32
    server = ManualMappingGuardIpcServer(socket_path, guard)
    server.start()
    ManualMappingGuardIpcClient(socket_path).arm(
        session_id=session_id,
        lease_id=lease_id,
        epoch=1,
    )
    current[0] += timedelta(milliseconds=100)
    ManualMappingGuardIpcClient(socket_path).apply(
        session_id=session_id,
        lease_id=lease_id,
        epoch=1,
        seq=1,
        sent_at=current[0],
        ttl_ms=200,
        linear=1.0,
        angular=0.0,
    )

    server.close()

    assert velocity.samples[-1] == (0.0, 0.0)


def test_shutdown_error_cannot_leave_owned_guard_socket_behind(tmp_path) -> None:
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    server = ManualMappingGuardIpcServer(socket_path, _ShutdownFailureGuard())
    server.start()

    with pytest.raises(RuntimeError, match="zero_publish_failed"):
        server.close()

    assert not socket_path.exists()


class _VelocitySink:
    def __init__(self) -> None:
        self.samples = []

    def publish(self, *, linear_mps, angular_radps) -> None:
        self.samples.append((linear_mps, angular_radps))


class _ShutdownFailureGuard:
    def poll_watchdog(self):
        return None

    def shutdown(self):
        raise RuntimeError("zero_publish_failed")


def test_slam_progress_survives_independent_one_request_clients(tmp_path) -> None:
    velocity = _VelocitySink()
    slam = _Slam()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=velocity,
        clock=lambda: NOW,
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    operation_id = "mapping_" + "a" * 32
    session_id = "manual_mapping_" + "b" * 32

    with ManualMappingGuardIpcServer(socket_path, guard, slam=slam):
        ManualMappingSlamIpcClient(socket_path).begin(
            operation_id=operation_id,
            session_id=session_id,
        )
        progress = ManualMappingSlamIpcClient(socket_path).read_progress(
            session_id=session_id,
        )

    assert progress["revision"] == 7
    assert slam.begins == [(operation_id, session_id)]


def test_real_sized_slam_progress_crosses_ipc_boundary(tmp_path) -> None:
    slam = _SizedSlam("x" * (32 * 1024))
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=_VelocitySink(),
        clock=lambda: NOW,
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "b" * 32

    with ManualMappingGuardIpcServer(socket_path, guard, slam=slam):
        progress = ManualMappingSlamIpcClient(socket_path).read_progress(
            session_id=session_id,
        )

    assert progress == {"revision": 7, "payload": "x" * (32 * 1024)}


def test_oversized_slam_response_does_not_kill_ipc_server(tmp_path) -> None:
    slam = _SizedSlam("x" * MAX_MESSAGE_BYTES)
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=_VelocitySink(),
        clock=lambda: NOW,
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    client = ManualMappingSlamIpcClient(socket_path)
    session_id = "manual_mapping_" + "b" * 32

    with ManualMappingGuardIpcServer(socket_path, guard, slam=slam):
        with pytest.raises(
            ManualMappingGuardError,
            match="manual_mapping_guard_ipc_message_too_large",
        ):
            client.read_progress(session_id=session_id)
        slam.payload = "ok"
        progress = client.read_progress(session_id=session_id)

    assert progress == {"revision": 7, "payload": "ok"}


def test_slam_save_result_crosses_persistent_runtime_boundary(tmp_path) -> None:
    slam = _Slam()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=_VelocitySink(),
        clock=lambda: NOW,
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "b" * 32

    with ManualMappingGuardIpcServer(socket_path, guard, slam=slam):
        result = ManualMappingSlamIpcClient(socket_path).save(
            session_id=session_id,
            dock_verified=True,
            save_kind="dock_verified",
        )

    assert result["saved"] is True
    assert result["new_map_activated"] is False


def test_slam_abandon_crosses_persistent_runtime_boundary(tmp_path) -> None:
    slam = _Slam()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=_VelocitySink(),
        clock=lambda: NOW,
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "b" * 32

    with ManualMappingGuardIpcServer(socket_path, guard, slam=slam):
        result = ManualMappingSlamIpcClient(socket_path).abandon(
            session_id=session_id,
        )

    assert result == "abandoned"
    assert slam.abandons == [session_id]


def test_ipc_stop_confirmation_rejects_non_boolean_board_value(tmp_path) -> None:
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    guard = _InvalidStopGuard()

    with ManualMappingGuardIpcServer(socket_path, guard):
        with pytest.raises(
            ManualMappingGuardError,
            match="manual_mapping_guard_response_invalid",
        ):
            ManualMappingGuardIpcClient(socket_path).request_stop(
                session_id="manual_mapping_" + "a" * 32,
                lease_id="mapping_lease_" + "b" * 32,
                epoch=1,
                reason="pointer_up",
            )


def test_slow_slam_snapshot_cannot_block_the_base_watchdog(tmp_path) -> None:
    current = [NOW]
    velocity = _VelocitySink()
    slow_slam = _SlowSlam()
    guard = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=velocity,
        clock=lambda: current[0],
    )
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "a" * 32
    lease_id = "mapping_lease_" + "b" * 32
    with ManualMappingGuardIpcServer(socket_path, guard, slam=slow_slam):
        client = ManualMappingGuardIpcClient(socket_path)
        client.arm(
            session_id=session_id,
            lease_id=lease_id,
            epoch=1,
        )
        current[0] += timedelta(milliseconds=100)
        client.apply(
            session_id=session_id,
            lease_id=lease_id,
            epoch=1,
            seq=1,
            sent_at=current[0],
            ttl_ms=200,
            linear=1.0,
            angular=0.0,
        )
        worker = threading.Thread(
            target=lambda: ManualMappingSlamIpcClient(
                socket_path,
                timeout_seconds=1.0,
            ).read_progress(session_id=session_id)
        )
        worker.start()
        assert slow_slam.entered.wait(timeout=0.5)
        current[0] += timedelta(milliseconds=401)
        time.sleep(0.12)

        assert velocity.samples[-1] == (0.0, 0.0)
        slow_slam.release.set()
        worker.join(timeout=1.0)


def test_guard_runtime_restart_never_restores_old_lease(tmp_path) -> None:
    socket_path = tmp_path / "guard" / "manual-mapping.sock"
    session_id = "manual_mapping_" + "a" * 32
    lease_id = "mapping_lease_" + "b" * 32
    first_velocity = _VelocitySink()
    first = ManualMappingTeleopGuard(
        ManualMappingSafetyProfile(
            profile_id="manual_mapping_safe_low_speed_v1",
            max_linear_mps=0.10,
            max_angular_radps=0.30,
            max_linear_accel_mps2=1.0,
            max_angular_accel_radps2=3.0,
        ),
        velocity_sink=first_velocity,
        clock=lambda: NOW,
    )
    with ManualMappingGuardIpcServer(socket_path, first):
        ManualMappingGuardIpcClient(socket_path).arm(
            session_id=session_id,
            lease_id=lease_id,
            epoch=1,
        )
    restarted_velocity = _VelocitySink()
    restarted = ManualMappingTeleopGuard(
        first.profile,
        velocity_sink=restarted_velocity,
        clock=lambda: NOW,
    )

    with ManualMappingGuardIpcServer(socket_path, restarted):
        with pytest.raises(
            ManualMappingGuardError,
            match="manual_mapping_guard_lease_mismatch",
        ):
            ManualMappingGuardIpcClient(socket_path).apply(
                session_id=session_id,
                lease_id=lease_id,
                epoch=1,
                seq=1,
                sent_at=NOW,
                ttl_ms=200,
                linear=1.0,
                angular=0.0,
            )

    assert restarted_velocity.samples[0] == (0.0, 0.0)
    assert restarted_velocity.samples[-1] == (0.0, 0.0)


class _Slam:
    def __init__(self) -> None:
        self.begins = []
        self.abandons = []

    def begin(self, *, operation_id, session_id):
        self.begins.append((operation_id, session_id))
        return "begun"

    def read_progress(self, *, session_id):
        assert session_id == "manual_mapping_" + "b" * 32
        return {"revision": 7}

    def save(self, *, session_id, dock_verified, save_kind):
        del session_id, dock_verified, save_kind
        return {
            "saved": True,
            "new_map_activated": False,
        }

    def abandon(self, *, session_id):
        self.abandons.append(session_id)
        return "abandoned"


class _SizedSlam:
    def __init__(self, payload):
        self.payload = payload

    def read_progress(self, *, session_id):
        assert session_id == "manual_mapping_" + "b" * 32
        return {"revision": 7, "payload": self.payload}


class _InvalidStopResult:
    def to_data(self):
        return {
            "state": "stop_pending",
            "stop_confirmed": "false",
            "reason": "pointer_up",
            "session_id": "manual_mapping_" + "a" * 32,
            "lease_id": "mapping_lease_" + "b" * 32,
            "epoch": 1,
            "stop_requested_at": NOW.isoformat(),
            "stop_confirmed_at": None,
            "stop_latency_ms": None,
        }


class _InvalidStopGuard:
    profile = type(
        "Profile",
        (),
        {"profile_id": "manual_mapping_safe_low_speed_v1"},
    )()

    def request_stop(self, **_request):
        return _InvalidStopResult()

    def poll_watchdog(self):
        return None

    def shutdown(self):
        return None


class _SlowSlam:
    def __init__(self):
        self.entered = threading.Event()
        self.release = threading.Event()

    def read_progress(self, *, session_id):
        del session_id
        self.entered.set()
        self.release.wait(timeout=0.5)
        return {"revision": 1}
