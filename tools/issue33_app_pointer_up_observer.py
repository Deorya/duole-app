#!/usr/bin/env python3
"""Observe one real App pointer-up run without owning or commanding motion."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import math
import sys
import time


WAIT_FOR_MOTION_SECONDS = 180.0
MOTION_WINDOW_SECONDS = 8.0
STABLE_STOP_SECONDS = 0.25
MAX_OBSERVED_DISPLACEMENT_M = 0.15
MIN_FORWARD_CLEARANCE_M = 0.25


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _xy(message: object) -> tuple[float, float]:
    return (
        float(message.pose.pose.position.x),
        float(message.pose.pose.position.y),
    )


def _forward_clearance(scan: object, *, half_width_m: float = 0.28) -> float | None:
    center = math.pi
    angle = float(scan.angle_min)
    increment = float(scan.angle_increment)
    range_max = float(scan.range_max)
    nearest: float | None = None
    for raw in scan.ranges:
        value = float(raw)
        if math.isfinite(value) and value > 0.0:
            candidate = value
        elif math.isinf(value) and value > 0.0 and range_max > 0.0:
            candidate = range_max
        else:
            angle += increment
            continue
        delta = math.atan2(math.sin(angle - center), math.cos(angle - center))
        x = candidate * math.cos(delta)
        y = candidate * math.sin(delta)
        if x > 0.0 and abs(y) <= half_width_m:
            nearest = x if nearest is None else min(nearest, x)
        angle += increment
    return nearest


def main() -> int:
    import rclpy
    from geometry_msgs.msg import Twist
    from nav_msgs.msg import Odometry
    from rclpy.signals import SignalHandlerOptions
    from sensor_msgs.msg import LaserScan

    state: dict[str, object] = {
        "cmd": None,
        "cmd_at": None,
        "odom": None,
        "odom_at": None,
        "scan": None,
        "scan_at": None,
        "motion_started_at": None,
        "start_xy": None,
        "zero_at": None,
        "stopped_since": None,
        "wheels_stopped_at": None,
        "max_abs_linear": 0.0,
        "max_abs_angular": 0.0,
        "max_displacement": 0.0,
        "min_forward_clearance": None,
    }

    def cmd_callback(message: object) -> None:
        now_mono = time.monotonic()
        state["cmd"] = message
        state["cmd_at"] = now_mono
        linear = abs(float(message.linear.x))
        angular = abs(float(message.angular.z))
        nonzero = linear > 1e-6 or angular > 1e-6
        if nonzero:
            state["max_abs_linear"] = max(float(state["max_abs_linear"]), linear)
            state["max_abs_angular"] = max(float(state["max_abs_angular"]), angular)
            if state["motion_started_at"] is None:
                state["motion_started_at"] = _utc_now()
                odom = state["odom"]
                if odom is not None:
                    state["start_xy"] = _xy(odom)
        elif state["motion_started_at"] is not None and state["zero_at"] is None:
            state["zero_at"] = _utc_now()

    def odom_callback(message: object) -> None:
        now_mono = time.monotonic()
        state["odom"] = message
        state["odom_at"] = now_mono
        start_xy = state["start_xy"]
        if start_xy is not None:
            x, y = _xy(message)
            displacement = math.hypot(x - start_xy[0], y - start_xy[1])
            state["max_displacement"] = max(
                float(state["max_displacement"]), displacement
            )
        if state["zero_at"] is None:
            return
        velocity = message.twist.twist
        stopped = (
            abs(float(velocity.linear.x)) <= 0.01
            and abs(float(velocity.angular.z)) <= 0.02
        )
        if stopped:
            if state["stopped_since"] is None:
                state["stopped_since"] = now_mono
            elif (
                state["wheels_stopped_at"] is None
                and now_mono - float(state["stopped_since"]) >= STABLE_STOP_SECONDS
            ):
                state["wheels_stopped_at"] = _utc_now()
        else:
            state["stopped_since"] = None

    def scan_callback(message: object) -> None:
        state["scan"] = message
        state["scan_at"] = time.monotonic()
        clearance = _forward_clearance(message)
        if clearance is None:
            return
        previous = state["min_forward_clearance"]
        state["min_forward_clearance"] = (
            clearance if previous is None else min(float(previous), clearance)
        )

    rclpy.init(args=None, signal_handler_options=SignalHandlerOptions.NO)
    node = rclpy.create_node("issue33_app_pointer_up_observer")
    node.create_subscription(Twist, "/cmd_vel", cmd_callback, 10)
    node.create_subscription(Odometry, "/odom/unfiltered", odom_callback, 10)
    node.create_subscription(LaserScan, "/scan_filtered", scan_callback, 10)
    started_mono = time.monotonic()
    motion_mono: float | None = None
    try:
        while True:
            rclpy.spin_once(node, timeout_sec=0.03)
            now_mono = time.monotonic()
            if state["motion_started_at"] is None:
                if now_mono - started_mono > WAIT_FOR_MOTION_SECONDS:
                    raise RuntimeError("app_pointer_up_motion_not_observed")
                continue
            if motion_mono is None:
                motion_mono = now_mono
            if state["odom_at"] is None or now_mono - float(state["odom_at"]) > 0.6:
                raise RuntimeError("app_pointer_up_odom_stale")
            if state["scan_at"] is None or now_mono - float(state["scan_at"]) > 0.5:
                raise RuntimeError("app_pointer_up_scan_stale")
            clearance = state["min_forward_clearance"]
            if clearance is not None and float(clearance) <= MIN_FORWARD_CLEARANCE_M:
                raise RuntimeError("app_pointer_up_clearance_below_abort_boundary")
            if float(state["max_displacement"]) > MAX_OBSERVED_DISPLACEMENT_M:
                raise RuntimeError("app_pointer_up_displacement_exceeded")
            if now_mono - motion_mono > MOTION_WINDOW_SECONDS:
                raise RuntimeError("app_pointer_up_stop_not_observed")
            if state["zero_at"] is None or state["wheels_stopped_at"] is None:
                continue
            motion_started_at = state["motion_started_at"]
            zero_at = state["zero_at"]
            wheels_stopped_at = state["wheels_stopped_at"]
            assert isinstance(motion_started_at, datetime)
            assert isinstance(zero_at, datetime)
            assert isinstance(wheels_stopped_at, datetime)
            payload = {
                "schema_version": "1.0",
                "issue": 33,
                "kind": "app_pointer_up_observation",
                "motion_started_at": motion_started_at.isoformat(),
                "zero_at": zero_at.isoformat(),
                "wheels_stopped_at": wheels_stopped_at.isoformat(),
                "zero_to_wheels_stopped_ms": round(
                    (wheels_stopped_at - zero_at).total_seconds() * 1000
                ),
                "max_abs_cmd_linear_mps": float(state["max_abs_linear"]),
                "max_abs_cmd_angular_rps": float(state["max_abs_angular"]),
                "max_displacement_m": float(state["max_displacement"]),
                "min_forward_clearance_m": state["min_forward_clearance"],
                "read_only_observer": True,
            }
            print(
                "ISSUE33_APP_POINTER_UP_OBSERVATION="
                + json.dumps(payload, sort_keys=True, separators=(",", ":")),
                flush=True,
            )
            return 0
    except Exception as exc:
        print(f"ISSUE33_APP_POINTER_UP_OBSERVER_ERROR={exc}", file=sys.stderr, flush=True)
        return 6
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
