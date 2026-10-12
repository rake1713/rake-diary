"""Точка входа: `uv run diary` или `uvicorn diary.main:app`."""

from __future__ import annotations

import logging
import os

import uvicorn

from diary.app import create_app

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")

app = create_app()


def run() -> None:
    uvicorn.run(
        "diary.main:app",
        host=os.environ.get("DIARY_HOST", "127.0.0.1"),
        port=int(os.environ.get("DIARY_PORT", "8000")),
        proxy_headers=True,
        forwarded_allow_ips=os.environ.get("DIARY_FORWARDED_ALLOW_IPS", "127.0.0.1"),
        server_header=False,
    )
