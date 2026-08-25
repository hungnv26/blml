"""Authentication primitives for the admin console.

Deliberately stdlib-only: PBKDF2 from hashlib, TOTP from hmac. Two reasons.
The console is a small container that should not grow a crypto dependency
tree it does not need — and, more practically, this is the security-critical
half of the app, so it is worth being able to test it anywhere without
installing anything. Every function here is covered by tests/test_security.py,
which runs on a bare Python.

The operator password is PBKDF2-HMAC-SHA256 rather than bcrypt. For a single
operator password with a high iteration count that is a sound choice, and it
avoids shelling out to a native extension for the one thing that must never
be subtly wrong.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import secrets
import struct
import time

# Deliberately high: this verifies once per login, never in a loop, so the
# cost is paid by an attacker far more often than by the operator.
PBKDF2_ROUNDS = 600_000
_SALT_BYTES = 16


# ── Operator password ────────────────────────────────────────────────────────

def hash_password(password: str, *, rounds: int = PBKDF2_ROUNDS,
                  salt: bytes | None = None) -> str:
    """Returns `pbkdf2_sha256$<rounds>$<salt-b64>$<hash-b64>`.

    The format carries its own parameters so the cost can be raised later
    without invalidating existing hashes.
    """
    if salt is None:
        salt = os.urandom(_SALT_BYTES)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, rounds)
    return "pbkdf2_sha256${}${}${}".format(
        rounds,
        base64.b64encode(salt).decode("ascii"),
        base64.b64encode(digest).decode("ascii"),
    )


def verify_password(password: str, encoded: str) -> bool:
    """Constant-time check against an encoded hash.

    Returns False rather than raising on a malformed record: a corrupt row
    must fail the login, not crash the login endpoint.
    """
    try:
        scheme, rounds, salt_b64, hash_b64 = encoded.split("$")
        if scheme != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"),
            base64.b64decode(salt_b64), int(rounds))
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(digest, base64.b64decode(hash_b64))


# ── TOTP (RFC 6238) ──────────────────────────────────────────────────────────

def generate_totp_secret() -> str:
    """A base32 secret, the format authenticator apps expect."""
    return base64.b32encode(os.urandom(20)).decode("ascii").rstrip("=")


def totp_at(secret_b32: str, timestamp: float, *, period: int = 30,
            digits: int = 6) -> str:
    """The TOTP code for a given moment. Split out from verification so the
    tests can drive it with the RFC's published vectors."""
    # Authenticator apps strip base32 padding; put it back before decoding.
    padded = secret_b32.upper() + "=" * (-len(secret_b32) % 8)
    key = base64.b32decode(padded)
    counter = struct.pack(">Q", int(timestamp) // period)
    mac = hmac.new(key, counter, hashlib.sha1).digest()
    offset = mac[-1] & 0x0F
    code = struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFF_FFFF
    return str(code % (10 ** digits)).zfill(digits)


def verify_totp(secret_b32: str, code: str, *, now: float | None = None,
                period: int = 30, window: int = 1) -> bool:
    """Checks a code against the current step and `window` steps either side.

    The window absorbs clock drift between the phone and the server. One step
    is the usual compromise: thirty seconds of slack in each direction,
    without widening the guessing surface more than necessary.
    """
    if not secret_b32 or not code:
        return False
    code = code.strip().replace(" ", "")
    if not code.isdigit():
        return False
    now = time.time() if now is None else now
    for step in range(-window, window + 1):
        candidate = totp_at(secret_b32, now + step * period, period=period,
                            digits=len(code))
        if hmac.compare_digest(candidate, code):
            return True
    return False


def provisioning_uri(secret_b32: str, account: str, issuer: str) -> str:
    """otpauth:// URI for enrolling an authenticator app."""
    from urllib.parse import quote
    label = quote(f"{issuer}:{account}")
    return (f"otpauth://totp/{label}?secret={secret_b32}"
            f"&issuer={quote(issuer)}&algorithm=SHA1&digits=6&period=30")


# ── Sessions ─────────────────────────────────────────────────────────────────

def new_session_token() -> str:
    """Opaque, 256 bits. Stored hashed, so a database read cannot mint one."""
    return secrets.token_urlsafe(32)


def hash_session_token(token: str) -> str:
    """SHA-256 is right here and bcrypt would be wrong: the token is already
    high-entropy random, so there is nothing to brute-force and no reason to
    pay a slow hash on every single request."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


# ── Login rate limiting ──────────────────────────────────────────────────────

class RateLimiter:
    """In-memory failed-login limiter with exponential backoff.

    Process-local on purpose: the console is one container with one operator,
    so a shared store would be complexity for nothing. It resets on restart,
    which is a real limitation — an attacker able to restart the container
    could clear it, but anyone with that access has already won.
    """

    def __init__(self, *, threshold: int = 5, base_delay: float = 2.0,
                 max_delay: float = 900.0) -> None:
        self.threshold = threshold
        self.base_delay = base_delay
        self.max_delay = max_delay
        self._failures: dict[str, tuple[int, float]] = {}

    def retry_after(self, key: str, *, now: float | None = None) -> float:
        """Seconds the caller must wait; 0.0 when a try is allowed now."""
        now = time.time() if now is None else now
        count, last = self._failures.get(key, (0, 0.0))
        if count < self.threshold:
            return 0.0
        delay = min(self.base_delay * (2 ** (count - self.threshold)), self.max_delay)
        remaining = (last + delay) - now
        return max(0.0, remaining)

    def record_failure(self, key: str, *, now: float | None = None) -> None:
        now = time.time() if now is None else now
        count, _ = self._failures.get(key, (0, 0.0))
        self._failures[key] = (count + 1, now)

    def reset(self, key: str) -> None:
        self._failures.pop(key, None)
