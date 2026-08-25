"""Session handling: login, step-up, and the dependency that guards routes.

The primitives live in security.py (stdlib, unit-tested). This module is the
part that touches the database and the request.
"""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

from . import audit, db
from .security import (
    RateLimiter, hash_password, hash_session_token, new_session_token,
    verify_password, verify_totp,
)

COOKIE_NAME = "blml_admin"
# Hours, not weeks. The console is internet-exposed and can restart the chat
# server, so a forgotten open tab is a real exposure rather than a nuisance.
SESSION_HOURS = int(os.environ.get("ADMIN_SESSION_HOURS", "12"))
# How long a password re-entry authorises destructive actions for.
STEPUP_MINUTES = 10

limiter = RateLimiter()


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── Operator bootstrap ───────────────────────────────────────────────────────

def ensure_operator() -> None:
    """Creates the operator row on first boot from ADMIN_USER/ADMIN_PASSWORD.

    The password is hashed immediately and the environment value is never
    stored. Rotating it means changing the env and restarting, which is the
    same shape as every other secret in this deployment.
    """
    existing = db.query_one("SELECT id, password_hash FROM admin.operator "
                            "WHERE id = 1")
    username = os.environ.get("ADMIN_USER", "admin")
    password = os.environ.get("ADMIN_PASSWORD")
    if existing:
        # Allow the env to rotate the password without a manual SQL step.
        if password and not verify_password(password, existing["password_hash"]):
            db.execute(
                "UPDATE admin.operator SET password_hash = %s, username = %s,"
                " updated_at = now() WHERE id = 1",
                (hash_password(password), username))
            audit.record("operator.password_rotated", target=username)
        return
    if not password:
        raise RuntimeError(
            "ADMIN_PASSWORD must be set on first start to create the operator")
    db.execute(
        "INSERT INTO admin.operator (id, username, password_hash) "
        "VALUES (1, %s, %s)", (username, hash_password(password)))
    audit.record("operator.created", target=username)


def operator() -> dict | None:
    return db.query_one(
        "SELECT username, password_hash, totp_secret, totp_enrolled "
        "FROM admin.operator WHERE id = 1")


# ── Login ────────────────────────────────────────────────────────────────────

def check_credentials(username: str, password: str, totp: str | None,
                      ip: str) -> tuple[bool, str]:
    """(ok, message). Rate limited per source address."""
    wait = limiter.retry_after(ip)
    if wait > 0:
        audit.record("login.throttled", target=username, outcome="denied",
                     detail={"retry_after_s": round(wait)}, ip=ip)
        return False, f"Too many attempts. Try again in {round(wait)}s."

    op = operator()
    # Same message and same work either way: a distinct "no such user"
    # response would confirm the username to someone guessing.
    ok = bool(op) and op["username"] == username and \
        verify_password(password, op["password_hash"])

    if ok and op["totp_enrolled"]:
        if not verify_totp(op["totp_secret"], totp or ""):
            limiter.record_failure(ip)
            audit.record("login.failed", target=username, outcome="denied",
                         detail={"reason": "totp"}, ip=ip)
            return False, "That code is not right."

    if not ok:
        limiter.record_failure(ip)
        audit.record("login.failed", target=username, outcome="denied",
                     detail={"reason": "password"}, ip=ip)
        return False, "Those details are not right."

    limiter.reset(ip)
    return True, ""


def start_session(ip: str, user_agent: str) -> str:
    token = new_session_token()
    db.execute(
        "INSERT INTO admin.session (token_hash, expires_at, ip, user_agent) "
        "VALUES (%s, %s, %s, %s)",
        (hash_session_token(token), _now() + timedelta(hours=SESSION_HOURS),
         ip, user_agent[:300]))
    audit.record("login.ok", ip=ip)
    return token


def end_session(token: str | None, ip: str | None = None) -> None:
    if token:
        db.execute("DELETE FROM admin.session WHERE token_hash = %s",
                   (hash_session_token(token),))
    audit.record("logout", ip=ip)


def session_for(token: str | None) -> dict | None:
    """The live session, or None. Expired rows are swept as they are met."""
    if not token:
        return None
    row = db.query_one(
        "SELECT token_hash, expires_at, stepup_at FROM admin.session "
        "WHERE token_hash = %s", (hash_session_token(token),))
    if not row:
        return None
    if row["expires_at"] <= _now():
        db.execute("DELETE FROM admin.session WHERE token_hash = %s",
                   (row["token_hash"],))
        return None
    return row


def sweep_sessions() -> int:
    return db.execute("DELETE FROM admin.session WHERE expires_at <= now()")


# ── Step-up for destructive actions ──────────────────────────────────────────

def grant_stepup(token: str) -> None:
    db.execute("UPDATE admin.session SET stepup_at = now() "
               "WHERE token_hash = %s", (hash_session_token(token),))


def has_stepup(session: dict | None) -> bool:
    """True while a recent password re-entry still authorises a restart or a
    delete. Deliberately short: the whole point is that holding a session is
    not the same as standing at the keyboard right now."""
    if not session or not session.get("stepup_at"):
        return False
    return session["stepup_at"] > _now() - timedelta(minutes=STEPUP_MINUTES)
