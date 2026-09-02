#!/usr/bin/env python3
"""Navigation-board probe for one authorized Issue 33 app-background stop."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import inspect
import json
import math
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import threading
import time
from typing import Mapping


SCENARIO = "app_background"
TARGET_ALONG_M = 0.06
PREFLIGHT_CORRIDOR_M = 1.0
CORRIDOR_HALF_WIDTH_M = 0.28
MAX_MOTION_SECONDS = 5.0
STOP_TIMEOUT_SECONDS = 1.5
ACTOR_ID = "device_session_issue33_hil"
INSTALLATION_ID = "installation_issue33_hil"
REAL_MANUAL_MAPPING_SHA256 = (
    "e928846e4fab0f341b4a9e32acc0cca0c57ab32db995ad8bb15c21672cce1a99"
)
BOARD_AGENT = Path(
    "/home/ztl/duole-issue31-nav-ws/bin/issue31-navigation-board-agent"
)


def invoke_app_background_action(
    service: object,
    *,
    session_id: str,
    actor_id: str,
) -> object:
    session = service.command_session(
        session_id,
        actor_id=actor_id,
        action=SCENARIO,
    )
    if (
        getattr(session, "phase", None) != "terminated"
        or getattr(session, "outcome", None) != "unverified_saved"
        or getattr(session, "transition_reason", None) != SCENARIO
        or getattr(session, "stop_confirmed", None) is not True
    ):
        raise RuntimeError("app_background_terminal_result_invalid")
    return session


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


class _RecordingBoard:
    def __init__(self, delegate: object) -> None:
        self.delegate = delegate
        self.last_save: object | None = None
        self.last_stop_reason: str | None = None

    def __getattr__(self, name: str) -> object:
        return getattr(self.delegate, name)

    def request_manual_mapping_stop(self, **request: object) -> object:
        self.last_stop_reason = str(request.get("reason") or "")
        return self.delegate.request_manual_mapping_stop(**request)

    def save_manual_mapping_session(self, **request: object) -> object:
        self.last_save = self.delegate.save_manual_mapping_session(**request)
        return self.last_save


def _yaw(message: object) -> float:
    q = message.pose.pose.orientation
    return math.atan2(
        2.0 * (float(q.w) * float(q.z) + float(q.x) * float(q.y)),
        1.0 - 2.0 * (float(q.y) ** 2 + float(q.z) ** 2),
    )


def _xy(message: object) -> tuple[float, float]:
    return float(message.pose.pose.position.x), float(message.pose.pose.position.y)


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
        timeout=float(kwargs.get("timeout") or 20.0),
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


def _require_exact_real_manual_mapping_source(module: object) -> None:
    try:
        source = inspect.getsource(module).encode("utf-8")
    except (OSError, TypeError) as exc:
        raise RuntimeError("app_background_real_gateway_source_unavailable") from exc
    digest = hashlib.sha256(source).hexdigest()
    if digest != REAL_MANUAL_MAPPING_SHA256:
        raise RuntimeError("app_background_real_gateway_source_mismatch")


def main() -> int:
    import rclpy
    from geometry_msgs.msg import Twist
    from nav_msgs.msg import Odometry
    from rclpy.executors import SingleThreadedExecutor
    from rclpy.signals import SignalHandlerOptions
    from sensor_msgs.msg import LaserScan

    from duole_central.app_gateway.navigation_board_ssh import (
        JsonLineBoardSession,
        SshNavigationBoardClient,
        SshNavigationBoardConfig,
    )
    from duole_central.app_gateway.real_manual_mapping import (
        NavigationBoardManualMappingSlam,
        RealManualMappingService,
    )
    import duole_central.app_gateway.real_manual_mapping as real_manual_mapping_module

    lock = threading.Lock()
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
        with lock:
            state["scan"] = message
            state["scan_at"] = time.monotonic()

    def odom_callback(message: object) -> None:
        now_mono = time.monotonic()
        with lock:
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
        with lock:
            if nonzero:
                state["cmd_nonzero_observed"] = True
            elif (
                state["fault_at"] is not None
                and state["zero_at"] is None
                and state["cmd_nonzero_observed"] is True
            ):
                state["zero_at"] = datetime.now(timezone.utc)

    _require_exact_real_manual_mapping_source(real_manual_mapping_module)
    provider_bundle_sha256 = os.environ.get("ISSUE33_PROVIDER_BUNDLE_SHA256", "")
    if (
        len(provider_bundle_sha256) != 64
        or any(character not in "0123456789abcdef" for character in provider_bundle_sha256)
    ):
        raise RuntimeError("app_background_provider_bundle_digest_invalid")
    if not BOARD_AGENT.is_file():
        print(
            "ISSUE33_APP_BACKGROUND_ERROR=app_background_board_agent_missing",
            file=sys.stderr,
            flush=True,
        )
        return 6

    rclpy.init(args=None, signal_handler_options=SignalHandlerOptions.NO)
    node = rclpy.create_node("issue33_app_background_hil_probe")
    node.create_subscription(LaserScan, "/scan_filtered", scan_callback, 10)
    node.create_subscription(Odometry, "/odom/unfiltered", odom_callback, 10)
    node.create_subscription(Twist, "/cmd_vel", cmd_callback, 10)
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    spin_thread = threading.Thread(target=executor.spin, daemon=True)
    spin_thread.start()

    token = secrets.token_hex(16)
    operation_id = "mapping_" + token
    mapping_started = False
    mapping_stopped = False
    board: _RecordingBoard | None = None
    session_id: str | None = None
    lease: object | None = None
    last_seq = 0
    try:
        topic_deadline = time.monotonic() + 6.0
        while time.monotonic() < topic_deadline:
            with lock:
                topics_ready = state["scan"] is not None and state["odom"] is not None
            if topics_ready:
                break
            time.sleep(0.05)
        with lock:
            scan = state["scan"]
        if scan is None:
            raise RuntimeError("app_background_preflight_topics_unavailable")
        clearance = corridor_forward_clearance(
            scan,
            half_width_m=CORRIDOR_HALF_WIDTH_M,
        )
        if clearance is None or clearance < PREFLIGHT_CORRIDOR_M:
            raise RuntimeError("app_background_preflight_corridor_below_1_0m")

        raw_board = SshNavigationBoardClient(
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
        board = _RecordingBoard(raw_board)
        raw_board.start_mapping(operation_id=operation_id, mode="manual_mapping")
        mapping_started = True
        ready_deadline = time.monotonic() + 30.0
        while time.monotonic() < ready_deadline and not (
            _service_active("duole-mapping-manual.service")
            and _service_active("duole-manual-mapping-runtime.service")
        ):
            time.sleep(0.2)
        if not (
            _service_active("duole-mapping-manual.service")
            and _service_active("duole-manual-mapping-runtime.service")
        ):
            raise RuntimeError("app_background_runtime_not_ready")

        with tempfile.TemporaryDirectory(prefix="issue33-app-background-") as directory:
            service = RealManualMappingService(
                Path(directory) / "manual-mapping.sqlite3",
                robot_id="robot-home",
                board=board,
                slam=NavigationBoardManualMappingSlam(board),
            )
            session = service.start_session(
                mapping_operation_id=operation_id,
                actor_id=ACTOR_ID,
                installation_id=INSTALLATION_ID,
            )
            session_id = str(session.session_id)
            lease = service.acquire_control(session_id, actor_id=ACTOR_ID)

            with lock:
                odom = state["odom"]
            if odom is None:
                raise RuntimeError("app_background_wheel_odometry_unavailable")
            start_x, start_y = _xy(odom)
            start_yaw = _yaw(odom)
            motion_started = time.monotonic()
            while True:
                now = time.monotonic()
                with lock:
                    odom = state["odom"]
                    odom_at = state["odom_at"]
                    scan = state["scan"]
                    scan_at = state["scan_at"]
                if odom is None or odom_at is None or now - float(odom_at) > 0.5:
                    raise RuntimeError("app_background_wheel_odometry_stale")
                if scan is None or scan_at is None or now - float(scan_at) > 0.3:
                    raise RuntimeError("app_background_laser_scan_stale")
                clearance = corridor_forward_clearance(
                    scan,
                    half_width_m=CORRIDOR_HALF_WIDTH_M,
                )
                if clearance is None or clearance <= 0.5:
                    raise RuntimeError("app_background_corridor_reached_stop_margin")
                x, y = _xy(odom)
                dx, dy = x - start_x, y - start_y
                along = dx * math.cos(start_yaw) + dy * math.sin(start_yaw)
                if along >= TARGET_ALONG_M:
                    break
                if now - motion_started > MAX_MOTION_SECONDS:
                    raise RuntimeError("app_background_motion_timeout")
                last_seq += 1
                result = service.apply_intent(
                    session_id=session_id,
                    actor_id=ACTOR_ID,
                    lease_id=str(lease.lease_id),
                    lease_epoch=int(lease.epoch),
                    seq=last_seq,
                    sent_at=datetime.now(timezone.utc),
                    ttl_ms=200,
                    linear=0.7,
                    angular=0.0,
                )
                if getattr(result, "status", None) != "applied":
                    raise RuntimeError(
                        "app_background_guard_non_applied:"
                        + str(getattr(result, "status", "invalid"))
                    )
                time.sleep(0.05)

            with lock:
                if (
                    state["cmd_nonzero_observed"] is not True
                    or state["raw_motion_observed"] is not True
                ):
                    raise RuntimeError("app_background_motion_not_observed")
                fault_at = datetime.now(timezone.utc)
                state["fault_at"] = fault_at

            terminal = invoke_app_background_action(
                service,
                session_id=session_id,
                actor_id=ACTOR_ID,
            )
            mapping_stopped = True
            stop_deadline = time.monotonic() + STOP_TIMEOUT_SECONDS
            while time.monotonic() < stop_deadline:
                with lock:
                    stop_complete = (
                        state["zero_at"] is not None
                        and state["wheels_stopped_at"] is not None
                    )
                if stop_complete:
                    break
                time.sleep(0.02)

            with lock:
                zero_at = state["zero_at"]
                wheels_stopped_at = state["wheels_stopped_at"]
            if not isinstance(zero_at, datetime) or not isinstance(
                wheels_stopped_at, datetime
            ):
                raise RuntimeError("app_background_stop_confirmation_timeout")
            latency = round((wheels_stopped_at - fault_at).total_seconds() * 1_000)
            if not fault_at <= zero_at <= wheels_stopped_at:
                raise RuntimeError("app_background_stop_timestamps_invalid")
            if not 0 <= latency <= 1_000:
                raise RuntimeError("app_background_stop_latency_exceeded")
            saved = board.last_save
            if (
                saved is None
                or getattr(saved, "saved", None) is not True
                or getattr(saved, "outcome", None) != "unverified_saved"
                or getattr(saved, "previous_active_map_restored", None) is not True
                or getattr(saved, "new_map_activated", None) is not False
                or board.last_stop_reason != "terminal_app_background"
            ):
                raise RuntimeError("app_background_save_result_invalid")

            telemetry = {
                "schema_version": "1.0",
                "issue": 33,
                "kind": "stop_telemetry",
                "scenario": SCENARIO,
                "lease_id": str(lease.lease_id),
                "last_accepted_seq": last_seq,
                "fault_at": fault_at.isoformat(),
                "zero_at": zero_at.isoformat(),
                "wheels_stopped_at": wheels_stopped_at.isoformat(),
                "stop_latency_ms": latency,
            }
            lifecycle = {
                "schema_version": "1.0",
                "issue": 33,
                "kind": "lifecycle_result",
                "scenario": SCENARIO,
                "operation_id": operation_id,
                "session_id": session_id,
                "lease_id": str(lease.lease_id),
                "last_accepted_seq": last_seq,
                "action": SCENARIO,
                "release_reason": str(board.last_stop_reason),
                "terminal_phase": str(terminal.phase),
                "terminal_outcome": str(terminal.outcome),
                "transition_reason": str(terminal.transition_reason),
                "stop_confirmed": bool(terminal.stop_confirmed),
                "save_kind": "unverified",
                "save_succeeded": bool(saved.saved),
                "save_outcome": str(saved.outcome),
                "charging_confirmed": bool(saved.charging_confirmed),
                "previous_active_map_restored": bool(
                    saved.previous_active_map_restored
                ),
                "new_map_activated": bool(saved.new_map_activated),
                "real_manual_mapping_sha256": REAL_MANUAL_MAPPING_SHA256,
                "provider_bundle_sha256": provider_bundle_sha256,
            }
            print(
                "ISSUE33_STOP_TELEMETRY="
                + json.dumps(telemetry, sort_keys=True, separators=(",", ":")),
                flush=True,
            )
            print(
                "ISSUE33_LIFECYCLE_RESULT="
                + json.dumps(lifecycle, sort_keys=True, separators=(",", ":")),
                flush=True,
            )
            return 0
    except Exception as exc:
        print(f"ISSUE33_APP_BACKGROUND_ERROR={exc}", file=sys.stderr, flush=True)
        return 6
    finally:
        if board is not None and mapping_started and not mapping_stopped:
            if session_id is not None and lease is not None:
                try:
                    board.request_manual_mapping_stop(
                        session_id=session_id,
                        lease_id=str(lease.lease_id),
                        epoch=int(lease.epoch),
                        reason="app_background_probe_abort",
                    )
                except Exception as stop_exc:
                    print(
                        f"ISSUE33_APP_BACKGROUND_ABORT_STOP_ERROR={stop_exc}",
                        file=sys.stderr,
                        flush=True,
                    )
            if session_id is not None:
                try:
                    board.abandon_manual_mapping_session(
                        session_id=session_id,
                    )
                except Exception as abandon_exc:
                    print(
                        "ISSUE33_APP_BACKGROUND_ABORT_ABANDON_ERROR="
                        f"{abandon_exc}",
                        file=sys.stderr,
                        flush=True,
                    )
            try:
                board.stop_mapping(
                    operation_id=operation_id,
                    mode="manual_mapping",
                )
            except Exception as mapping_exc:
                print(
                    f"ISSUE33_APP_BACKGROUND_ABORT_MAPPING_ERROR={mapping_exc}",
                    file=sys.stderr,
                    flush=True,
                )
        executor.shutdown(timeout_sec=2.0)
        spin_thread.join(timeout=2.0)
        try:
            node.destroy_node()
        finally:
            rclpy.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
