#!/usr/bin/env python3
"""Bounded navigation-board probe for Issue 33 acceptance-permit HIL checks."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
import math
from pathlib import Path
import secrets
import sys
import time


STATE_DIRECTORY = Path("/home/ztl/duole-issue31-nav-ws/state")
RUNTIME_ROOT = Path(
    "/home/ztl/duole-issue31-nav-ws/runtime/duole_central/navigation_board"
)
MANUAL_UNIT = Path("/etc/systemd/system/duole-mapping-manual.service")
FORWARD_ANGLE_RAD = math.pi
PROFILE_LINEAR_TARGET_M = 0.06
PROFILE_ANGULAR_TARGET_RAD = 0.20
PROFILE_PHASE_TIMEOUT_SECONDS = 1.8
COLLISION_PHASE_TIMEOUT_SECONDS = 4.0
COLLISION_MAX_DISPLACEMENT_M = 0.13
STOP_TIMEOUT_SECONDS = 1.5


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _angle_delta(value: float, origin: float) -> float:
    return math.atan2(math.sin(value - origin), math.cos(value - origin))


def _yaw(message: object) -> float:
    orientation = message.pose.pose.orientation
    return math.atan2(
        2.0
        * (
            float(orientation.w) * float(orientation.z)
            + float(orientation.x) * float(orientation.y)
        ),
        1.0
        - 2.0
        * (
            float(orientation.y) * float(orientation.y)
            + float(orientation.z) * float(orientation.z)
        ),
    )


def _xy(message: object) -> tuple[float, float]:
    pose = message.pose.pose.position
    return float(pose.x), float(pose.y)


def _scan_nearest(
    scan: object,
    *,
    center_angle: float,
    half_width: float,
) -> float | None:
    nearest: float | None = None
    angle = float(scan.angle_min)
    range_max = float(scan.range_max)
    for raw in scan.ranges:
        value = float(raw)
        candidate: float | None = None
        if math.isfinite(value) and value > 0.0:
            candidate = value
        elif math.isinf(value) and value > 0.0 and range_max > 0.0:
            candidate = range_max
        if (
            candidate is not None
            and abs(_angle_delta(angle, center_angle)) <= half_width
        ):
            nearest = candidate if nearest is None else min(nearest, candidate)
        angle += float(scan.angle_increment)
    return nearest


def _corridor_clearance(scan: object, *, half_width_m: float = 0.28) -> float | None:
    nearest: float | None = None
    angle = float(scan.angle_min)
    range_max = float(scan.range_max)
    for raw in scan.ranges:
        value = float(raw)
        candidate: float | None = None
        if math.isfinite(value) and value > 0.0:
            candidate = value
        elif math.isinf(value) and value > 0.0 and range_max > 0.0:
            candidate = range_max
        if candidate is not None:
            delta = _angle_delta(angle, FORWARD_ANGLE_RAD)
            x = candidate * math.cos(delta)
            y = candidate * math.sin(delta)
            if x > 0.0 and abs(y) <= half_width_m:
                nearest = x if nearest is None else min(nearest, x)
        angle += float(scan.angle_increment)
    return nearest


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"baseline", "collision"}:
        print("usage: issue33_permit_hil_board_probe.py baseline|collision", file=sys.stderr)
        return 2
    scenario = sys.argv[1]

    import rclpy
    from geometry_msgs.msg import Twist
    from nav_msgs.msg import Odometry
    from rclpy.qos import qos_profile_sensor_data
    from rclpy.signals import SignalHandlerOptions
    from sensor_msgs.msg import LaserScan

    from duole_central.navigation_board.manual_mapping_guard import (
        ManualMappingGuardError,
    )
    from duole_central.navigation_board.manual_mapping_guard_ipc import (
        ManualMappingGuardIpcClient,
    )

    state: dict[str, object] = {
        "scan": None,
        "scan_at": None,
        "odom": None,
        "odom_at": None,
        "cmd_samples": [],
        "raw_max_linear": 0.0,
        "raw_max_angular": 0.0,
    }

    def scan_callback(message: object) -> None:
        state["scan"] = message
        state["scan_at"] = time.monotonic()

    def odom_callback(message: object) -> None:
        state["odom"] = message
        state["odom_at"] = time.monotonic()
        velocity = message.twist.twist
        state["raw_max_linear"] = max(
            float(state["raw_max_linear"]),
            abs(float(velocity.linear.x)),
        )
        state["raw_max_angular"] = max(
            float(state["raw_max_angular"]),
            abs(float(velocity.angular.z)),
        )

    def cmd_callback(message: object) -> None:
        samples = state["cmd_samples"]
        assert isinstance(samples, list)
        samples.append((float(message.linear.x), float(message.angular.z)))

    rclpy.init(args=None, signal_handler_options=SignalHandlerOptions.NO)
    node = rclpy.create_node(f"issue33_permit_{scenario}_hil_probe")
    node.create_subscription(
        LaserScan,
        "/scan_filtered",
        scan_callback,
        qos_profile_sensor_data,
    )
    node.create_subscription(
        Odometry,
        "/odom/unfiltered",
        odom_callback,
        qos_profile_sensor_data,
    )
    node.create_subscription(Twist, "/cmd_vel", cmd_callback, 10)
    client = ManualMappingGuardIpcClient(
        STATE_DIRECTORY / "manual-mapping-guard.sock",
        timeout_seconds=0.5,
    )
    active: tuple[str, str, int] | None = None

    def spin(seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.03)

    def require_fresh_inputs() -> None:
        now = time.monotonic()
        if (
            state["scan"] is None
            or state["odom"] is None
            or state["scan_at"] is None
            or state["odom_at"] is None
            or now - float(state["scan_at"]) > 0.3
            or now - float(state["odom_at"]) > 0.5
        ):
            raise RuntimeError("permit_hil_inputs_stale")

    def require_stationary() -> None:
        odom = state["odom"]
        if odom is None:
            raise RuntimeError("permit_hil_odometry_unavailable")
        velocity = odom.twist.twist
        if (
            abs(float(velocity.linear.x)) > 0.01
            or abs(float(velocity.angular.z)) > 0.02
        ):
            raise RuntimeError("permit_hil_chassis_not_stationary")

    def arm() -> tuple[str, str, int]:
        nonlocal active
        token = secrets.token_hex(16)
        credentials = (
            "mapping_session_" + token,
            "mapping_lease_" + token,
            1,
        )
        client.arm(
            session_id=credentials[0],
            lease_id=credentials[1],
            epoch=credentials[2],
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=30),
        )
        active = credentials
        spin(0.60)
        return credentials

    def apply(
        credentials: tuple[str, str, int],
        *,
        seq: int,
        linear: float,
        angular: float,
    ) -> object:
        return client.apply(
            session_id=credentials[0],
            lease_id=credentials[1],
            epoch=credentials[2],
            seq=seq,
            sent_at=datetime.now(timezone.utc),
            ttl_ms=200,
            linear=linear,
            angular=angular,
        )

    def stop(credentials: tuple[str, str, int], *, reason: str) -> int:
        nonlocal active
        status = client.request_stop(
            session_id=credentials[0],
            lease_id=credentials[1],
            epoch=credentials[2],
            reason=reason,
        )
        deadline = time.monotonic() + STOP_TIMEOUT_SECONDS
        while time.monotonic() < deadline and not status.stop_confirmed:
            rclpy.spin_once(node, timeout_sec=0.03)
            status = client.stop_status(
                session_id=credentials[0],
                lease_id=credentials[1],
                epoch=credentials[2],
            )
        active = None
        latency = status.stop_latency_ms
        if not status.stop_confirmed or latency is None or not 0 <= latency <= 1_000:
            raise RuntimeError("permit_hil_stop_not_confirmed_within_1s")
        spin(0.30)
        require_stationary()
        return int(latency)

    try:
        spin(1.0)
        require_fresh_inputs()
        require_stationary()
        versions = {
            "manual_mapping_guard_sha256": _sha256(
                RUNTIME_ROOT / "manual_mapping_guard.py"
            ),
            "ros_manual_mapping_runtime_sha256": _sha256(
                RUNTIME_ROOT / "ros_manual_mapping_runtime.py"
            ),
            "manual_mapping_unit_sha256": _sha256(MANUAL_UNIT),
        }
        if versions != {
            "manual_mapping_guard_sha256": "d66de1f9c73e0253e1ae31100c0190baf632c86ec94da3cf1766e4391e74570d",
            "ros_manual_mapping_runtime_sha256": "548fa8d1d5e411486e0903d4b592697711d20f5cd410aea6170a9e7e579dfc1a",
            "manual_mapping_unit_sha256": "c4760979763ccb39f22bb104a320718fde838140909af915762612c08cb8b40d",
        }:
            raise RuntimeError("permit_hil_version_mismatch")

        if scenario == "baseline":
            samples = state["cmd_samples"]
            assert isinstance(samples, list)
            samples.clear()
            token = secrets.token_hex(16)
            rejection: str | None = None
            try:
                client.apply(
                    session_id="mapping_session_" + token,
                    lease_id="mapping_lease_" + token,
                    epoch=1,
                    seq=1,
                    sent_at=datetime.now(timezone.utc),
                    ttl_ms=200,
                    linear=1.0,
                    angular=0.0,
                )
            except ManualMappingGuardError as exc:
                rejection = str(exc)
            spin(0.40)
            if rejection != "manual_mapping_guard_lease_mismatch":
                raise RuntimeError("permit_hil_default_unarmed_not_rejected")
            if any(abs(linear) > 1e-6 or abs(angular) > 1e-6 for linear, angular in samples):
                raise RuntimeError("permit_hil_default_unarmed_nonzero_output")
            require_stationary()
            default_unarmed = {
                "status": "passed",
                "rejection": rejection,
                "cmd_vel_max_abs_linear_mps": max(
                    (abs(value[0]) for value in samples), default=0.0
                ),
                "cmd_vel_max_abs_angular_radps": max(
                    (abs(value[1]) for value in samples), default=0.0
                ),
            }

            scan = state["scan"]
            assert scan is not None
            corridor_before = _corridor_clearance(scan)
            all_around_before = _scan_nearest(
                scan,
                center_angle=0.0,
                half_width=math.pi,
            )
            if corridor_before is None or corridor_before < 1.0:
                raise RuntimeError("permit_hil_profile_corridor_below_1m")
            if all_around_before is None or all_around_before <= 0.50:
                raise RuntimeError("permit_hil_profile_rotation_clearance_below_0_5m")

            odom = state["odom"]
            assert odom is not None
            start_x, start_y = _xy(odom)
            start_yaw = _yaw(odom)
            credentials = arm()
            linear_results = []
            seq = 0
            phase_started = time.monotonic()
            next_send = phase_started
            along = 0.0
            while along < PROFILE_LINEAR_TARGET_M:
                rclpy.spin_once(node, timeout_sec=0.02)
                require_fresh_inputs()
                now = time.monotonic()
                if now - phase_started > PROFILE_PHASE_TIMEOUT_SECONDS:
                    raise RuntimeError("permit_hil_profile_linear_timeout")
                current = state["odom"]
                assert current is not None
                x, y = _xy(current)
                along = (x - start_x) * math.cos(start_yaw) + (y - start_y) * math.sin(start_yaw)
                scan = state["scan"]
                assert scan is not None
                clearance = _corridor_clearance(scan)
                if clearance is None or clearance <= 0.50:
                    raise RuntimeError("permit_hil_profile_linear_clearance_lost")
                if now >= next_send:
                    seq += 1
                    result = apply(credentials, seq=seq, linear=1.0, angular=0.0)
                    linear_results.append(result)
                    if result.status != "applied":
                        raise RuntimeError("permit_hil_profile_linear_not_applied")
                    next_send = now + 0.09
            linear_stop_latency_ms = stop(credentials, reason="hil_profile_linear")

            odom = state["odom"]
            assert odom is not None
            angular_start_yaw = _yaw(odom)
            credentials = arm()
            angular_results = []
            seq = 0
            phase_started = time.monotonic()
            next_send = phase_started
            yaw_delta = 0.0
            while abs(yaw_delta) < PROFILE_ANGULAR_TARGET_RAD:
                rclpy.spin_once(node, timeout_sec=0.02)
                require_fresh_inputs()
                now = time.monotonic()
                if now - phase_started > PROFILE_PHASE_TIMEOUT_SECONDS:
                    raise RuntimeError("permit_hil_profile_angular_timeout")
                current = state["odom"]
                assert current is not None
                yaw_delta = _angle_delta(_yaw(current), angular_start_yaw)
                if now >= next_send:
                    seq += 1
                    result = apply(credentials, seq=seq, linear=0.0, angular=1.0)
                    angular_results.append(result)
                    if result.status != "applied":
                        raise RuntimeError("permit_hil_profile_angular_not_applied")
                    next_send = now + 0.09
            angular_stop_latency_ms = stop(credentials, reason="hil_profile_angular")

            max_linear = max(float(item.effective_linear_mps) for item in linear_results)
            max_angular = max(float(item.effective_angular_radps) for item in angular_results)
            if not math.isclose(max_linear, 0.10, abs_tol=1e-9):
                raise RuntimeError("permit_hil_profile_linear_clamp_not_observed")
            if not math.isclose(max_angular, 0.30, abs_tol=1e-9):
                raise RuntimeError("permit_hil_profile_angular_clamp_not_observed")
            result_payload = {
                "schema_version": "1.0",
                "issue": 33,
                "kind": "hil_check_log",
                "run": "baseline",
                "observed_at": datetime.now(timezone.utc).isoformat(),
                "versions": versions,
                "hil_default_unarmed_zero": default_unarmed,
                "hil_profile_clamp": {
                    "status": "passed",
                    "profile_id": "manual_mapping_safe_low_speed_v1",
                    "corridor_before_m": corridor_before,
                    "all_around_clearance_before_m": all_around_before,
                    "observed_max_effective_linear_mps": max_linear,
                    "observed_max_effective_angular_radps": max_angular,
                    "linear_displacement_m": along,
                    "angular_displacement_rad": yaw_delta,
                    "linear_stop_latency_ms": linear_stop_latency_ms,
                    "angular_stop_latency_ms": angular_stop_latency_ms,
                },
            }
        else:
            scan = state["scan"]
            odom = state["odom"]
            assert scan is not None and odom is not None
            initial_distance = _scan_nearest(
                scan,
                center_angle=FORWARD_ANGLE_RAD,
                half_width=math.pi / 4,
            )
            if initial_distance is None or not 0.30 < initial_distance <= 0.50:
                raise RuntimeError("permit_hil_collision_initial_distance_not_slow_zone")
            start_x, start_y = _xy(odom)
            start_yaw = _yaw(odom)
            credentials = arm()
            seq = 0
            phase_started = time.monotonic()
            next_send = phase_started
            slowdown_results = []
            blocked_result = None
            minimum_distance = initial_distance
            displacement = 0.0
            while blocked_result is None:
                rclpy.spin_once(node, timeout_sec=0.02)
                require_fresh_inputs()
                now = time.monotonic()
                if now - phase_started > COLLISION_PHASE_TIMEOUT_SECONDS:
                    raise RuntimeError("permit_hil_collision_transition_timeout")
                current = state["odom"]
                scan = state["scan"]
                assert current is not None and scan is not None
                x, y = _xy(current)
                displacement = (x - start_x) * math.cos(start_yaw) + (y - start_y) * math.sin(start_yaw)
                if displacement > COLLISION_MAX_DISPLACEMENT_M:
                    raise RuntimeError("permit_hil_collision_displacement_exceeded")
                distance = _scan_nearest(
                    scan,
                    center_angle=FORWARD_ANGLE_RAD,
                    half_width=math.pi / 4,
                )
                if distance is None:
                    raise RuntimeError("permit_hil_collision_scan_invalid")
                minimum_distance = min(minimum_distance, distance)
                if distance <= 0.25:
                    raise RuntimeError("permit_hil_collision_stop_margin_exceeded")
                if now >= next_send:
                    seq += 1
                    result = apply(credentials, seq=seq, linear=1.0, angular=0.0)
                    if result.status == "scaled" and result.blocked_reason == "collision_slowdown":
                        slowdown_results.append(result)
                    elif result.status == "blocked" and result.blocked_reason == "collision_blocked":
                        blocked_result = result
                    else:
                        raise RuntimeError("permit_hil_collision_unexpected_guard_result")
                    next_send = now + 0.15
            stop_latency_ms = stop(credentials, reason="hil_collision_slowdown_block")
            if not slowdown_results:
                raise RuntimeError("permit_hil_collision_slowdown_not_observed")
            max_scaled = max(float(item.effective_linear_mps) for item in slowdown_results)
            if max_scaled > 0.05 + 1e-9 or max_scaled <= 0.0:
                raise RuntimeError("permit_hil_collision_scaled_output_invalid")
            if (
                float(blocked_result.effective_linear_mps) != 0.0
                or float(blocked_result.effective_angular_radps) != 0.0
            ):
                raise RuntimeError("permit_hil_collision_block_nonzero")
            result_payload = {
                "schema_version": "1.0",
                "issue": 33,
                "kind": "hil_check_log",
                "run": "collision",
                "observed_at": datetime.now(timezone.utc).isoformat(),
                "versions": versions,
                "hil_collision_slowdown_block": {
                    "status": "passed",
                    "profile_id": "manual_mapping_safe_low_speed_v1",
                    "initial_front_distance_m": initial_distance,
                    "minimum_front_distance_m": minimum_distance,
                    "observed_max_effective_linear_mps": max_scaled,
                    "blocked_reason": blocked_result.blocked_reason,
                    "blocked_effective_linear_mps": blocked_result.effective_linear_mps,
                    "displacement_m": displacement,
                    "stop_latency_ms": stop_latency_ms,
                },
            }
        print(
            "ISSUE33_PERMIT_HIL="
            + json.dumps(result_payload, sort_keys=True, separators=(",", ":")),
            flush=True,
        )
        return 0
    except Exception as exc:
        print(f"ISSUE33_PERMIT_HIL_ERROR={exc}", file=sys.stderr, flush=True)
        return 6
    finally:
        if active is not None:
            try:
                client.request_stop(
                    session_id=active[0],
                    lease_id=active[1],
                    epoch=active[2],
                    reason="permit_hil_probe_abort",
                )
            except Exception as stop_exc:
                print(
                    f"ISSUE33_PERMIT_HIL_ABORT_STOP_ERROR={stop_exc}",
                    file=sys.stderr,
                    flush=True,
                )
        try:
            node.destroy_node()
        finally:
            rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
