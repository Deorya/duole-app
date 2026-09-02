#!/usr/bin/env python3
"""Minimal production-factory IPC owner for Issue 33 Phase 3 HIL."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import signal
import threading

from duole_central.app_gateway.models import AppRuntimeInfo
from duole_central.app_gateway.projection import AppProjectionStore
from duole_central.runtime.product_runtime_config import ProductRuntimeConfig
from duole_central.runtime.product_runtime_factory import ProductRuntimeFactory
from duole_central.runtime.product_voice_live_session import (
    ProductVoiceLiveSessionConfig,
    _issue33_manual_mapping_acceptance_permit_accepted,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=Path, required=True)
    parser.add_argument("--projection-database", type=Path, required=True)
    parser.add_argument("--robot-id", required=True)
    parser.add_argument("--display-name", default="多乐机器人")
    parser.add_argument("--acceptance-permit", type=Path, required=True)
    parser.add_argument("--candidate-manifest-sha256", required=True)
    args = parser.parse_args()

    permit_config = ProductVoiceLiveSessionConfig(
        app_robot_id=args.robot_id,
        app_runtime_mode="REAL",
        app_real_manual_mapping_acceptance_permit_path=str(
            args.acceptance_permit.resolve()
        ),
        app_real_manual_mapping_candidate_manifest_sha256=(
            args.candidate_manifest_sha256
        ),
    )
    if not _issue33_manual_mapping_acceptance_permit_accepted(permit_config):
        raise SystemExit("issue33_phase3_acceptance_permit_rejected")

    runtime_info = AppRuntimeInfo(
        robot_id=args.robot_id,
        display_name=args.display_name,
        product_model="DUOLE",
        mode="REAL",
        real_manual_mapping_acceptance_run_permitted=True,
    )
    projection_store = AppProjectionStore(args.projection_database)
    bundle = ProductRuntimeFactory(
        app_runtime_info=runtime_info,
        app_projection_store=projection_store,
        app_projection_refresh_interval_seconds=1.0,
    ).build(ProductRuntimeConfig(mode="dry_run"))
    if bundle.validation_errors:
        raise SystemExit(
            "runtime_validation_failed:" + ",".join(bundle.validation_errors)
        )

    stopped = threading.Event()

    def request_stop(_signum: int, _frame: object) -> None:
        stopped.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    projection_runtime = bundle.app_projection_runtime
    if projection_runtime is None:
        raise SystemExit("issue33_phase3_projection_runtime_missing")

    server = bundle.app_runtime_ipc_server(args.socket)
    projection_status = projection_runtime.start()
    try:
        with server:
            print(
                json.dumps(
                    {
                        "event": "issue33_phase3_runtime_ready",
                        "robot_id": args.robot_id,
                        "mode": "REAL",
                        "acceptance_run_permitted": True,
                        "socket": str(args.socket),
                        "projection_database": str(args.projection_database),
                        "projection_snapshot_seq": projection_status["last_seq"],
                        "candidate_manifest_sha256": (
                            args.candidate_manifest_sha256
                        ),
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                ),
                flush=True,
            )
            stopped.wait()
    finally:
        projection_runtime.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
