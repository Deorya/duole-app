#!/usr/bin/env python3
"""Navigation-board probe for one authorized Issue 33 pointer-up HIL stop."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import secrets
import sys
import time


SCENARIO = "pointer_up"
TARGET_ALONG_M = 0.06
PREFLIGHT_CORRIDOR_M = 1.0
CORRIDOR_HALF_WIDTH_M = 0.28
MAX_MOTION_SECONDS = 4.0
STOP_TIMEOUT_SECONDS = 1.5


def corridor_forward_clearance(
    scan: object,
    *,
    half_width_m: float,
) -> float | None:
    center = math.pi
    angle = float(scan.angle_min)
    increment = float(scan.angle_increment)
    range_max = float(scan.range_max)
    nearest_x: float | None = None
    for raw in scan.ranges:
        value = float(raw)
        candidate: float | None = None
        if math.isfinite(value) and value > 0.0:
            candidate = value
        elif (
            math.isinf(value)
            and value > 0.0
            and math.isfinite(range_max)
            and range_max > 0.0
        ):
            candidate = range_max
        if candidate is not None:
            delta = math.atan2(
                math.sin(angle - center),
                math.cos(angle - center),
            )
            x = candidate * math.cos(delta)
            y = candidate * math.sin(delta)
            if x > 0.0 and abs(y) <= half_width_m:
                nearest_x = x if nearest_x is None else min(nearest_x, x)
        angle += increment
    return nearest_x


def _yaw(message: object) -> float:
    q = message.pose.pose.orientation
    return math.atan2(
        2.0 * (float(q.w) * float(q.z) + float(q.x) * float(q.y)),
        1.0 - 2.0 * (float(q.y) ** 2 + float(q.z) ** 2),
    )


def _xy(message: object) -> tuple[float, float]:
    return float(message.pose.pose.position.x), float(message.pose.pose.position.y)


def main() -> int:
    import rclpy
    from geometry_msgs.msg import Twist
    from nav_msgs.msg import Odometry
    from rclpy.signals import SignalHandlerOptions
    from sensor_msgs.msg import LaserScan

    from duole_central.navigation_board.manual_mapping_guard_ipc import (
        ManualMappingGuardIpcClient,
    )

    state: dict[str, object] = {
        "scan": None,
        "scan_at": None,
        "odom": None,
        "odom_at": None,
        "cmd_nonzero_observed": False,
        "raw_motion_observed": False,
        "fault_at": None,
        "zero_at": None,
        "wheels_stopped_at": None,
        "stopped_since": None,
    }

    def scan_callback(message: object) -> None:
        state["scan"] = message
        state["scan_at"] = time.monotonic()

    def odom_callback(message: object) -> None:
        now_mono = time.monotonic()
        state["odom"] = message
        state["odom_at"] = now_mono
        velocity = message.twist.twist
        stopped = (
            abs(float(velocity.linear.x)) <= 0.01
            and abs(float(velocity.angular.z)) <= 0.02
        )
        if not stopped:
            state["raw_motion_observed"] = True
        if state["fault_at"] is None:
            return
        if stopped:
            if state["stopped_since"] is None:
                state["stopped_since"] = now_mono
            elif (
                state["wheels_stopped_at"] is None
                and now_mono - float(state["stopped_since"]) >= 0.25
            ):
                state["wheels_stopped_at"] = datetime.now(timezone.utc)
        else:
            state["stopped_since"] = None

    def cmd_callback(message: object) -> None:
        nonzero = (
            abs(float(message.linear.x)) > 1e-6
            or abs(float(message.angular.z)) > 1e-6
        )
        if nonzero:
            state["cmd_nonzero_observed"] = True
        elif (
            state["fault_at"] is not None
            and state["zero_at"] is None
            and state["cmd_nonzero_observed"] is True
        ):
            state["zero_at"] = datetime.now(timezone.utc)

    rclpy.init(args=None, signal_handler_options=SignalHandlerOptions.NO)
    node = rclpy.create_node("issue33_pointer_up_hil_probe")
    node.create_subscription(LaserScan, "/scan_filtered", scan_callback, 10)
    node.create_subscription(Odometry, "/odom/unfiltered", odom_callback, 10)
    node.create_subscription(Twist, "/cmd_vel", cmd_callback, 10)
    client = ManualMappingGuardIpcClient(
        Path("/home/ztl/duole-issue31-nav-ws/state/manual-mapping-guard.sock"),
        timeout_seconds=0.5,
    )
    token = secrets.token_hex(16)
    session_id = "mapping_session_" + token
    lease_id = "mapping_lease_" + token
    epoch = 1
    armed = False
    stop_requested = False
    last_seq = 0
    try:
        topic_deadline = time.monotonic() + 6.0
        while time.monotonic() < topic_deadline and (
            state["scan"] is None or state["odom"] is None
        ):
            rclpy.spin_once(node, timeout_sec=0.05)
        if state["scan"] is None or state["odom"] is None:
            raise RuntimeError("pointer_up_preflight_topics_unavailable")
        clearance = corridor_forward_clearance(
            state["scan"],
            half_width_m=CORRIDOR_HALF_WIDTH_M,
        )
        if clearance is None or clearance < PREFLIGHT_CORRIDOR_M:
            raise RuntimeError("pointer_up_preflight_corridor_below_1_0m")

        start_x, start_y = _xy(state["odom"])
        start_yaw = _yaw(state["odom"])
        client.arm(
            session_id=session_id,
            lease_id=lease_id,
            epoch=epoch,
            expires_at=datetime.now(timezone.utc) + timedelta(seconds=30),
        )
        armed = True
        motion_started = time.monotonic()
        next_send = motion_started
        while True:
            rclpy.spin_once(node, timeout_sec=0.02)
            now = time.monotonic()
            if state["odom_at"] is None or now - float(state["odom_at"]) > 0.5:
                raise RuntimeError("pointer_up_wheel_odometry_stale")
            if state["scan_at"] is None or now - float(state["scan_at"]) > 0.3:
                raise RuntimeError("pointer_up_laser_scan_stale")
            clearance = corridor_forward_clearance(
                state["scan"],
                half_width_m=CORRIDOR_HALF_WIDTH_M,
            )
            if clearance is None or clearance <= 0.5:
                raise RuntimeError("pointer_up_corridor_reached_stop_margin")
            x, y = _xy(state["odom"])
            dx, dy = x - start_x, y - start_y
            along = dx * math.cos(start_yaw) + dy * math.sin(start_yaw)
            if along >= TARGET_ALONG_M:
                break
            if now - motion_started > MAX_MOTION_SECONDS:
                raise RuntimeError("pointer_up_motion_timeout")
            if now >= next_send:
                last_seq += 1
                result = client.apply(
                    session_id=session_id,
                    lease_id=lease_id,
                    epoch=epoch,
                    seq=last_seq,
                    sent_at=datetime.now(timezone.utc),
                    ttl_ms=200,
                    linear=0.7,
                    angular=0.0,
                )
                if result.status != "applied":
                    raise RuntimeError("pointer_up_guard_non_applied:" + result.status)
                next_send = now + 0.09
        if (
            state["cmd_nonzero_observed"] is not True
            or state["raw_motion_observed"] is not True
        ):
            raise RuntimeError("pointer_up_motion_not_observed")

        state["fault_at"] = datetime.now(timezone.utc)
        stop_status = client.request_stop(
            session_id=session_id,
            lease_id=lease_id,
            epoch=epoch,
            reason=SCENARIO,
        )
        stop_requested = True
        stop_deadline = time.monotonic() + STOP_TIMEOUT_SECONDS
        while time.monotonic() < stop_deadline and (
            state["zero_at"] is None
            or state["wheels_stopped_at"] is None
            or not stop_status.stop_confirmed
        ):
            rclpy.spin_once(node, timeout_sec=0.03)
            stop_status = client.stop_status(
                session_id=session_id,
                lease_id=lease_id,
                epoch=epoch,
            )
        fault_at = state["fault_at"]
        zero_at = state["zero_at"]
        wheels_stopped_at = state["wheels_stopped_at"]
        if (
            not isinstance(fault_at, datetime)
            or not isinstance(zero_at, datetime)
            or not isinstance(wheels_stopped_at, datetime)
            or not stop_status.stop_confirmed
        ):
            raise RuntimeError("pointer_up_stop_confirmation_timeout")
        latency = round((wheels_stopped_at - fault_at).total_seconds() * 1_000)
        if not fault_at <= zero_at <= wheels_stopped_at:
            raise RuntimeError("pointer_up_stop_timestamps_invalid")
        if not 0 <= latency <= 1_000:
            raise RuntimeError("pointer_up_stop_latency_exceeded")
        telemetry = {
            "schema_version": "1.0",
            "issue": 33,
            "kind": "stop_telemetry",
            "scenario": SCENARIO,
            "lease_id": lease_id,
            "last_accepted_seq": last_seq,
            "fault_at": fault_at.isoformat(),
            "zero_at": zero_at.isoformat(),
            "wheels_stopped_at": wheels_stopped_at.isoformat(),
            "stop_latency_ms": latency,
        }
        print(
            "ISSUE33_STOP_TELEMETRY="
            + json.dumps(telemetry, sort_keys=True, separators=(",", ":")),
            flush=True,
        )
        return 0
    except Exception as exc:
        print(f"ISSUE33_POINTER_UP_ERROR={exc}", file=sys.stderr, flush=True)
        return 6
    finally:
        if armed and not stop_requested:
            try:
                client.request_stop(
                    session_id=session_id,
                    lease_id=lease_id,
                    epoch=epoch,
                    reason="pointer_up_probe_abort",
                )
            except Exception as stop_exc:
                print(
                    f"ISSUE33_POINTER_UP_ABORT_STOP_ERROR={stop_exc}",
                    file=sys.stderr,
                    flush=True,
                )
        try:
            node.destroy_node()
        finally:
            rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
