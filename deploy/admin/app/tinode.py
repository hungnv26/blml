"""Privileged writes, performed through the chat API as a root account.

This exists because of the plan's central decision. The chat server holds
topics, subscriptions and sessions in memory; a row changed behind its back
may not take effect until a restart and can leave invariants it assumes are
true quietly broken. Going through the API means every change follows the
same path the phone apps use.

It also sidesteps a trap that has already cost real time: `auth.uname` stores
`<scheme>:<login>`, not the bare login, so a password reset written as SQL
keyed on the login silently matches zero rows and reports success. The API
takes a user id and a login, and has no opinion about how they are stored.

The root account is created once with:  tinode-db --make_root <login>
"""
from __future__ import annotations

import base64
import json
import os
import ssl
import time
from contextlib import contextmanager

import websocket

HOST = os.environ.get("TINODE_HOST", "blml:6060")
API_KEY = os.environ["TINODE_API_KEY"]
ROOT_LOGIN = os.environ.get("TINODE_ROOT_LOGIN", "")
ROOT_PASSWORD = os.environ.get("TINODE_ROOT_PASSWORD", "")
USE_TLS = os.environ.get("TINODE_TLS", "false").lower() == "true"


class TinodeError(RuntimeError):
    pass


class RootSession:
    """One short-lived websocket, authenticated at root level.

    Not pooled: admin actions are rare and a long-lived privileged connection
    is a liability, not an optimisation.
    """

    def __init__(self, ws: websocket.WebSocket) -> None:
        self.ws = ws
        self._id = 0

    def _next_id(self) -> str:
        self._id += 1
        return str(self._id)

    def call(self, payload: dict, timeout: float = 20.0) -> dict:
        """Sends one packet and waits for the ctrl reply carrying its id."""
        msg_id = self._next_id()
        for value in payload.values():
            value["id"] = msg_id
        self.ws.send(json.dumps(payload))

        deadline = time.time() + timeout
        while time.time() < deadline:
            frame = json.loads(self.ws.recv())
            ctrl = frame.get("ctrl")
            if not ctrl or ctrl.get("id") != msg_id:
                continue  # data/pres for something else; not our reply
            if not 200 <= ctrl.get("code", 500) < 300:
                raise TinodeError(f"{ctrl.get('code')} {ctrl.get('text')}")
            return ctrl
        raise TinodeError("timed out waiting for a reply")

    # ── Actions ─────────────────────────────────────────────────────────────

    def resolve_uid(self, login: str) -> str:
        """Encoded uid (`usrXXXX`) for a login, asked of the server.

        NOT computed locally. The wire uid is the database id encrypted with
        UID_ENCRYPTION_KEY, not an encoding of it — reproducing that here
        would mean reimplementing the server's cipher and shipping its key
        into this container, and getting it subtly wrong would address
        privileged actions at the wrong account. Asking the server costs a
        round trip and cannot drift.

        Searches the `fnd` topic for the `basic:<login>` tag, which is how
        every account is indexed.
        """
        self.call({"sub": {"topic": "fnd"}})
        self.call({"set": {"topic": "fnd",
                           "desc": {"public": f"basic:{login}"}}})
        self.call({"get": {"topic": "fnd", "what": "sub"}})
        deadline = time.time() + 15.0
        while time.time() < deadline:
            frame = json.loads(self.ws.recv())
            for sub in (frame.get("meta") or {}).get("sub", []) or []:
                if sub.get("user"):
                    return sub["user"]
            if frame.get("ctrl", {}).get("code", 0) >= 400:
                break
        raise TinodeError(f"could not resolve a uid for login {login!r}")

    def set_password(self, uid: str, login: str, new_password: str) -> None:
        """Resets another account's password. Root only."""
        secret = base64.b64encode(f"{login}:{new_password}".encode()).decode()
        self.call({"acc": {"user": uid, "scheme": "basic", "secret": secret}})

    def set_state(self, uid: str, state: str) -> None:
        """`suspended` or `ok`. Rejected for non-root by the server itself."""
        if state not in ("ok", "suspended"):
            raise ValueError(f"refusing unknown account state {state!r}")
        self.call({"acc": {"user": uid, "status": state}})

    def delete_user(self, uid: str, hard: bool = True) -> None:
        self.call({"del": {"what": "user", "user": uid, "hard": hard}})


@contextmanager
def root_session():
    """Opens, authenticates, and always closes.

    Raises rather than degrading to SQL if root credentials are absent: a
    console that silently falls back to writing the database behind the
    server's back is the exact failure this design exists to prevent.
    """
    if not ROOT_LOGIN or not ROOT_PASSWORD:
        raise TinodeError(
            "TINODE_ROOT_LOGIN/TINODE_ROOT_PASSWORD are not set — create the "
            "root account with `tinode-db --make_root <login>` first")

    scheme = "wss" if USE_TLS else "ws"
    url = f"{scheme}://{HOST}/v0/channels?apikey={API_KEY}"
    opts = {"cert_reqs": ssl.CERT_NONE} if not USE_TLS else None
    ws = websocket.create_connection(url, timeout=25, sslopt=opts)
    try:
        session = RootSession(ws)
        session.call({"hi": {"ver": "0.22", "ua": "blml-admin/1.0"}})
        secret = base64.b64encode(
            f"{ROOT_LOGIN}:{ROOT_PASSWORD}".encode()).decode()
        ctrl = session.call({"login": {"scheme": "basic", "secret": secret}})
        if (ctrl.get("params") or {}).get("authlvl") != "root":
            raise TinodeError(
                f"{ROOT_LOGIN} authenticated but is not root — promote it "
                "with `tinode-db --make_root`")
        yield session
    finally:
        try:
            ws.close()
        except Exception:  # noqa: BLE001 - closing must not mask a real error
            pass
