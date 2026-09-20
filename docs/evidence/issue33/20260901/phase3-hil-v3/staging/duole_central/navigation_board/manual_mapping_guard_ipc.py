"""Owner-local persistent IPC boundary for the base-side mapping guard."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import errno
import json
import os
from pathlib import Path
import socket
import stat
import struct
import threading
from types import SimpleNamespace
from typing import Mapping

from duole_central.navigation_board.manual_mapping_guard import (
    ManualMappingArmResult,
    ManualMappingGuardError,
    ManualMappingGuardResult,
    ManualMappingStopStatus,
    ManualMappingTeleopGuard,
)


PROTOCOL_VERSION = "duole.manual-mapping-guard.v1"
# A REAL occupancy snapshot already exceeds the original 16 KiB control-only
# envelope.  Keep the bounded local transport aligned with the authenticated
# navigation-board response boundary so map progress can cross it without
# removing the size guard.
MAX_MESSAGE_BYTES = 4 * 1024 * 1024


class ManualMappingGuardIpcServer:
    def __init__(
        self,
        socket_path: str | Path,
        guard: ManualMappingTeleopGuard,
        *,
        slam: object | None = None,
        allowed_peer_uid: int | None = None,
    ) -> None:
        self.socket_path = Path(socket_path)
        self.guard = guard
        self.slam = slam
        self.allowed_peer_uid = (
            os.getuid() if allowed_peer_uid is None else int(allowed_peer_uid)
        )
        self._listener: socket.socket | None = None
        self._thread: threading.Thread | None = None
        self._watchdog_thread: threading.Thread | None = None
        self._shutdown = threading.Event()
        self._guard_lock = threading.Lock()
        self._slam_lock = threading.Lock()
        self._socket_identity: tuple[int, int] | None = None

    def __enter__(self) -> "ManualMappingGuardIpcServer":
        self.start()
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def start(self) -> None:
        _prepare_parent(self.socket_path.parent)
        _prepare_socket_path(self.socket_path)
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.settimeout(0.1)
        listener.bind(str(self.socket_path))
        os.chmod(self.socket_path, 0o600)
        metadata = self.socket_path.lstat()
        self._socket_identity = (metadata.st_dev, metadata.st_ino)
        listener.listen(8)
        self._listener = listener
        self._thread = threading.Thread(
            target=self._serve,
            name="duole-manual-mapping-guard-ipc",
            daemon=True,
        )
        self._watchdog_thread = threading.Thread(
            target=self._watchdog,
            name="duole-manual-mapping-base-watchdog",
            daemon=True,
        )
        self._thread.start()
        self._watchdog_thread.start()

    def close(self) -> None:
        self._shutdown.set()
        shutdown_error: Exception | None = None
        try:
            with self._guard_lock:
                self.guard.shutdown()
        except Exception as exc:
            shutdown_error = exc
        finally:
            listener = self._listener
            if listener is not None:
                listener.close()
            for thread in (self._thread, self._watchdog_thread):
                if thread is not None:
                    thread.join(timeout=2.0)
            _unlink_if_owned(self.socket_path, self._socket_identity)
            self._socket_identity = None
        if shutdown_error is not None:
            raise shutdown_error

    def _serve(self) -> None:
        listener = self._listener
        assert listener is not None
        while not self._shutdown.is_set():
            try:
                connection, _ = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with connection:
                connection.settimeout(0.5)
                try:
                    if _peer_uid(connection) != self.allowed_peer_uid:
                        raise PermissionError("manual_mapping_guard_peer_rejected")
                    request = _read_message(connection)
                    action = request.get("action")
                    lock = (
                        self._slam_lock
                        if isinstance(action, str) and action.startswith("slam_")
                        else self._guard_lock
                    )
                    with lock:
                        data = self._dispatch(request)
                    response = {
                        "protocol": PROTOCOL_VERSION,
                        "ok": True,
                        "data": data,
                    }
                except Exception as exc:
                    response = {
                        "protocol": PROTOCOL_VERSION,
                        "ok": False,
                        "error": str(exc) or type(exc).__name__,
                    }
                try:
                    _write_message(connection, response)
                except ValueError as exc:
                    # A large or otherwise non-serializable SLAM response must
                    # fail this request without killing the persistent guard
                    # thread (and therefore the stop/watchdog boundary).
                    error = str(exc)
                    if error != "manual_mapping_guard_ipc_message_too_large":
                        error = "manual_mapping_guard_ipc_response_invalid"
                    try:
                        _write_message(
                            connection,
                            {
                                "protocol": PROTOCOL_VERSION,
                                "ok": False,
                                "error": error,
                            },
                        )
                    except (OSError, ValueError):
                        pass
                except OSError:
                    pass

    def _watchdog(self) -> None:
        while not self._shutdown.wait(0.05):
            with self._guard_lock:
                self.guard.poll_watchdog()

    def _dispatch(self, request: Mapping[str, object]) -> dict[str, object]:
        action = request.get("action")
        if action == "slam_begin":
            slam = self.slam
            if slam is None:
                raise RuntimeError("manual_mapping_slam_unavailable")
            state = getattr(slam, "begin")(
                operation_id=str(request["operation_id"]),
                session_id=str(request["session_id"]),
            )
            return {"state": state}
        if action == "slam_progress":
            slam = self.slam
            if slam is None:
                raise RuntimeError("manual_mapping_slam_unavailable")
            progress = getattr(slam, "read_progress")(
                session_id=str(request["session_id"]),
            )
            if not isinstance(progress, Mapping):
                raise ValueError("manual_mapping_slam_progress_invalid")
            return dict(progress)
        if action == "slam_save":
            slam = self.slam
            if slam is None:
                raise RuntimeError("manual_mapping_slam_unavailable")
            result = getattr(slam, "save")(
                session_id=str(request["session_id"]),
                dock_verified=request["dock_verified"],
                save_kind=request["save_kind"],
            )
            if not isinstance(result, Mapping):
                raise ValueError("manual_mapping_slam_save_invalid")
            return dict(result)
        if action == "slam_abandon":
            slam = self.slam
            if slam is None:
                raise RuntimeError("manual_mapping_slam_unavailable")
            state = getattr(slam, "abandon")(
                session_id=str(request["session_id"]),
            )
            if state != "abandoned":
                raise ValueError("manual_mapping_slam_abandon_invalid")
            return {"state": state}
        if action == "arm":
            return self.guard.arm(
                session_id=str(request["session_id"]),
                lease_id=str(request["lease_id"]),
                epoch=int(request["epoch"]),
            ).to_data()
        if action == "apply":
            return self.guard.apply(
                session_id=str(request["session_id"]),
                lease_id=str(request["lease_id"]),
                epoch=int(request["epoch"]),
                seq=int(request["seq"]),
                sent_at=datetime.fromisoformat(str(request["sent_at"])),
                ttl_ms=int(request["ttl_ms"]),
                linear=float(request["linear"]),
                angular=float(request["angular"]),
            ).to_data()
        if action == "request_stop":
            return self.guard.request_stop(
                session_id=str(request["session_id"]),
                lease_id=str(request["lease_id"]),
                epoch=int(request["epoch"]),
                reason=str(request["reason"]),
            ).to_data()
        if action == "stop_status":
            return self.guard.stop_status(
                session_id=str(request["session_id"]),
                lease_id=str(request["lease_id"]),
                epoch=int(request["epoch"]),
            ).to_data()
        raise ValueError("manual_mapping_guard_action_invalid")


@dataclass(frozen=True)
class ManualMappingGuardIpcClient:
    socket_path: Path
    timeout_seconds: float = 0.5
    expected_owner_uid: int | None = None
    profile_id: str = "manual_mapping_safe_low_speed_v1"

    def __init__(
        self,
        socket_path: str | Path,
        *,
        timeout_seconds: float = 0.5,
        expected_owner_uid: int | None = None,
        profile_id: str = "manual_mapping_safe_low_speed_v1",
    ) -> None:
        object.__setattr__(self, "socket_path", Path(socket_path))
        object.__setattr__(self, "timeout_seconds", float(timeout_seconds))
        object.__setattr__(
            self,
            "expected_owner_uid",
            os.getuid() if expected_owner_uid is None else int(expected_owner_uid),
        )
        object.__setattr__(self, "profile_id", profile_id)

    @property
    def profile(self) -> object:
        return SimpleNamespace(profile_id=self.profile_id)

    def arm(self, **request: object) -> ManualMappingArmResult:
        data = self._invoke("arm", request)
        if set(data) != {"profile_id", "armed_at", "expires_at"}:
            raise ManualMappingGuardError("manual_mapping_guard_profile_mismatch")
        try:
            armed_at = datetime.fromisoformat(str(data["armed_at"]))
            expires_at = datetime.fromisoformat(str(data["expires_at"]))
        except (TypeError, ValueError) as exc:
            raise ManualMappingGuardError(
                "manual_mapping_guard_response_invalid"
            ) from exc
        if (
            data["profile_id"] != self.profile_id
            or armed_at.tzinfo is None
            or expires_at.tzinfo is None
            or expires_at <= armed_at
        ):
            raise ManualMappingGuardError(
                "manual_mapping_guard_response_invalid"
            )
        return ManualMappingArmResult(
            profile_id=self.profile_id,
            armed_at=armed_at,
            expires_at=expires_at,
        )

    def apply(self, **request: object) -> ManualMappingGuardResult:
        data = self._invoke("apply", request)
        try:
            return ManualMappingGuardResult(
                status=str(data["status"]),
                accepted_seq=int(data["accepted_seq"]),
                effective_linear_mps=float(data["effective_linear_mps"]),
                effective_angular_radps=float(data["effective_angular_radps"]),
                blocked_reason=(
                    str(data["blocked_reason"])
                    if data.get("blocked_reason") is not None
                    else None
                ),
                profile_id=str(data["profile_id"]),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ManualMappingGuardError(
                "manual_mapping_guard_response_invalid"
            ) from exc

    def request_stop(self, **request: object) -> ManualMappingStopStatus:
        return _stop_status(self._invoke("request_stop", request))

    def stop_status(self, **request: object) -> ManualMappingStopStatus:
        return _stop_status(self._invoke("stop_status", request))

    def _invoke(
        self,
        action: str,
        request: Mapping[str, object],
    ) -> dict[str, object]:
        _validate_client_socket(
            self.socket_path,
            int(self.expected_owner_uid),
        )
        payload = {
            "protocol": PROTOCOL_VERSION,
            "action": action,
            **{
                key: value.isoformat() if isinstance(value, datetime) else value
                for key, value in request.items()
            },
        }
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(self.timeout_seconds)
                client.connect(str(self.socket_path))
                _write_message(client, payload)
                response = _read_message(client)
        except OSError as exc:
            raise ManualMappingGuardError(
                "manual_mapping_guard_ipc_unavailable"
            ) from exc
        if response.get("ok") is not True:
            raise ManualMappingGuardError(
                str(response.get("error") or "manual_mapping_guard_ipc_failed")
            )
        data = response.get("data")
        if not isinstance(data, dict):
            raise ManualMappingGuardError("manual_mapping_guard_response_invalid")
        return {str(key): value for key, value in data.items()}


class ManualMappingSlamIpcClient:
    def __init__(
        self,
        socket_path: str | Path,
        *,
        timeout_seconds: float = 12.0,
        expected_owner_uid: int | None = None,
    ) -> None:
        self._client = ManualMappingGuardIpcClient(
            socket_path,
            timeout_seconds=timeout_seconds,
            expected_owner_uid=expected_owner_uid,
        )

    def begin(self, *, operation_id: str, session_id: str) -> str:
        data = self._client._invoke(
            "slam_begin",
            {"operation_id": operation_id, "session_id": session_id},
        )
        state = data.get("state")
        if state != "begun":
            raise ManualMappingGuardError("manual_mapping_slam_begin_failed")
        return "begun"

    def read_progress(self, *, session_id: str) -> dict[str, object]:
        return self._client._invoke(
            "slam_progress",
            {"session_id": session_id},
        )

    def save(
        self,
        *,
        session_id: str,
        dock_verified: bool,
        save_kind: str,
    ) -> dict[str, object]:
        return self._client._invoke(
            "slam_save",
            {
                "session_id": session_id,
                "dock_verified": dock_verified,
                "save_kind": save_kind,
            },
        )

    def abandon(self, *, session_id: str) -> str:
        data = self._client._invoke(
            "slam_abandon",
            {"session_id": session_id},
        )
        if data != {"state": "abandoned"}:
            raise ManualMappingGuardError("manual_mapping_slam_abandon_failed")
        return "abandoned"


def _stop_status(data: Mapping[str, object]) -> ManualMappingStopStatus:
    try:
        confirmed_raw = data.get("stop_confirmed_at")
        stop_confirmed = data["stop_confirmed"]
        if not isinstance(stop_confirmed, bool):
            raise ValueError("manual_mapping_stop_confirmed_invalid")
        return ManualMappingStopStatus(
            state=str(data["state"]),
            stop_confirmed=stop_confirmed,
            reason=str(data["reason"]),
            session_id=str(data["session_id"]),
            lease_id=str(data["lease_id"]),
            epoch=int(data["epoch"]),
            stop_requested_at=datetime.fromisoformat(
                str(data["stop_requested_at"])
            ),
            stop_confirmed_at=(
                datetime.fromisoformat(str(confirmed_raw))
                if confirmed_raw is not None
                else None
            ),
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise ManualMappingGuardError(
            "manual_mapping_guard_response_invalid"
        ) from exc


def _prepare_parent(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    metadata = path.lstat()
    if (
        path.is_symlink()
        or not stat.S_ISDIR(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or metadata.st_mode & 0o077
    ):
        raise RuntimeError("manual_mapping_guard_ipc_parent_invalid")


def _prepare_socket_path(path: Path) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    if path.is_symlink() or not stat.S_ISSOCK(metadata.st_mode):
        raise RuntimeError("manual_mapping_guard_ipc_socket_invalid")
    identity = (metadata.st_dev, metadata.st_ino)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
        probe.settimeout(0.1)
        try:
            probe.connect(str(path))
        except OSError as exc:
            if exc.errno not in {errno.ECONNREFUSED, errno.ENOENT}:
                raise RuntimeError(
                    "manual_mapping_guard_ipc_socket_in_use"
                ) from exc
        else:
            raise RuntimeError("manual_mapping_guard_ipc_socket_in_use")
    _unlink_if_owned(path, identity)


def _validate_client_socket(path: Path, expected_owner_uid: int) -> None:
    parent = path.parent.lstat()
    metadata = path.lstat()
    if (
        path.parent.is_symlink()
        or not stat.S_ISDIR(parent.st_mode)
        or parent.st_uid != expected_owner_uid
        or parent.st_mode & 0o077
        or path.is_symlink()
        or not stat.S_ISSOCK(metadata.st_mode)
        or metadata.st_uid != expected_owner_uid
        or metadata.st_mode & 0o077
    ):
        raise ManualMappingGuardError("manual_mapping_guard_ipc_path_invalid")


def _unlink_if_owned(path: Path, identity: tuple[int, int] | None) -> None:
    if identity is None:
        return
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return
    if stat.S_ISSOCK(metadata.st_mode) and (
        metadata.st_dev,
        metadata.st_ino,
    ) == identity:
        path.unlink()


def _peer_uid(connection: socket.socket) -> int | None:
    option = getattr(socket, "SO_PEERCRED", None)
    if option is None:
        return None
    try:
        _pid, uid, _gid = struct.unpack(
            "3i",
            connection.getsockopt(
                socket.SOL_SOCKET,
                option,
                struct.calcsize("3i"),
            ),
        )
    except OSError:
        return None
    return int(uid)


def _read_message(connection: socket.socket) -> dict[str, object]:
    raw = b""
    while b"\n" not in raw:
        chunk = connection.recv(min(4096, MAX_MESSAGE_BYTES + 1 - len(raw)))
        if not chunk:
            break
        raw += chunk
        if len(raw) > MAX_MESSAGE_BYTES:
            raise ValueError("manual_mapping_guard_ipc_message_too_large")
    try:
        value = json.loads(raw.split(b"\n", 1)[0].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("manual_mapping_guard_ipc_message_invalid") from exc
    if not isinstance(value, dict) or value.get("protocol") != PROTOCOL_VERSION:
        raise ValueError("manual_mapping_guard_ipc_protocol_invalid")
    return {str(key): item for key, item in value.items()}


def _write_message(connection: socket.socket, value: Mapping[str, object]) -> None:
    payload = json.dumps(
        dict(value),
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8") + b"\n"
    if len(payload) > MAX_MESSAGE_BYTES:
        raise ValueError("manual_mapping_guard_ipc_message_too_large")
    connection.sendall(payload)


__all__ = [
    "ManualMappingGuardIpcClient",
    "ManualMappingGuardIpcServer",
    "ManualMappingSlamIpcClient",
]
