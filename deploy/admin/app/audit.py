"""The audit log.

Written for every state-changing action and every failed login. With a single
operator this is not about attribution — it is about answering "when did that
change, and what did it look like before", months later, when the answer is
not in anyone's memory.

Failures are recorded too. An action that errored is exactly the one you will
want to find later, and a log that only contains successes quietly tells you
nothing went wrong.
"""
from __future__ import annotations

import json
from typing import Any

from . import db


def record(action: str, *, target: str | None = None, outcome: str = "ok",
           detail: dict[str, Any] | None = None, ip: str | None = None) -> None:
    """Never raises.

    A broken audit insert must not take down the action it is describing, nor
    leave the caller half-committed. It is better to lose a log line than to
    fail a password reset because the logging table was unhappy.
    """
    try:
        db.execute(
            "INSERT INTO admin.audit (action, target, outcome, detail, ip) "
            "VALUES (%s, %s, %s, %s, %s)",
            (action, target, outcome,
             json.dumps(detail or {}, default=str), ip))
    except Exception:  # noqa: BLE001 - deliberately swallowed, see docstring
        pass


def recent(limit: int = 100, action: str | None = None) -> list:
    if action:
        return db.query(
            "SELECT at, action, target, outcome, detail, ip FROM admin.audit "
            "WHERE action = %s ORDER BY at DESC LIMIT %s", (action, limit))
    return db.query(
        "SELECT at, action, target, outcome, detail, ip FROM admin.audit "
        "ORDER BY at DESC LIMIT %s", (limit,))
