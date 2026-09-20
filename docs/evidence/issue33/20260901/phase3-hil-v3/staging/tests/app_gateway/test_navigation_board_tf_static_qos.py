from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

from duole_central.navigation_board.manual_mapping_runtime_cli import build_runtime
from duole_central.navigation_board.ros_manual_mapping_runtime import (
    RosManualMappingMessageTypes,
)


def test_build_runtime_forwards_transient_local_qos_to_tf_static(tmp_path) -> None:
    node = _Node()
    transient_local_qos = object()

    build_runtime(
        state_directory=tmp_path / "state",
        map_root=tmp_path / "maps",
        active_map_path=tmp_path / "active-map.json",
        node=node,
        message_types=RosManualMappingMessageTypes(
            twist=_Twist,
            odometry=_Message,
            laser_scan=_Message,
            occupancy_grid=_Message,
            battery_state=_Message,
            string=_Message,
            boolean=_Message,
            tf_message=_Message,
        ),
        map_saver=_MapSaver(),
        clock=lambda: datetime(2026, 9, 1, tzinfo=timezone.utc),
        tf_static_qos_profile=transient_local_qos,
    )

    assert node.subscription_qos["/tf"] == 10
    assert node.subscription_qos["/tf_static"] is transient_local_qos


class _Message:
    pass


class _Twist:
    def __init__(self) -> None:
        self.linear = SimpleNamespace(x=0.0)
        self.angular = SimpleNamespace(z=0.0)


class _MapSaver:
    pass


class _Publisher:
    def publish(self, _message: object) -> None:
        pass


class _Node:
    def __init__(self) -> None:
        self.subscription_qos: dict[str, object] = {}

    def create_publisher(
        self,
        _message_type: type,
        _topic: str,
        _qos: object,
    ) -> _Publisher:
        return _Publisher()

    def create_subscription(
        self,
        _message_type: type,
        topic: str,
        _callback: object,
        qos: object,
    ) -> object:
        self.subscription_qos[topic] = qos
        return object()
