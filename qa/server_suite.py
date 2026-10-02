#!/usr/bin/env python3
"""BLML server protocol suite: correctness, permissions, edge cases, robustness.

    python3 qa/server_suite.py                 # run everything against localhost:6060
    python3 qa/server_suite.py --only p2p,groups
    python3 qa/server_suite.py --md out.md     # also write the PASS/FAIL table as Markdown
    python3 qa/server_suite.py --probe-port 6070
        # ALSO run the crash checks (firebase garbage token, unknown tmpscheme) against a
        # DISPOSABLE second server on that port first. Since the 2026-10-02 fixes they run
        # against the shared server too. Start a probe with:
        #   docker run -d --name blml-qa-probe --network blml-qa_default \
        #     -p 127.0.0.1:6070:6060 -v "$PWD/deploy/blml.conf:/etc/blml/blml.conf:ro" \
        #     -v "$PWD/deploy/fcm-service-account.json:/etc/blml/fcm-service-account.json:ro" blml-qa-blml

Every account it creates is a throwaway (login qs<run><n>) and is hard-deleted at
the end. Phone numbers come from ACMA's fiction range +61 491 570 110-159.
It never logs in as qa_ios / qa_android / qa_web; it only sends them nothing.
qa_peer / qa_peer2 are not needed either: the suite makes its own people.

Like blml_qa.py it refuses to talk to anything but a server on this machine, and
it never prints passwords, tokens or the invite code.
"""
import argparse
import base64
import json
import os
import secrets
import socket
import string
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

from websocket import create_connection, WebSocketTimeoutException, ABNF

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
API_KEY = "AQAAAAABAAC-d-KsShjNeHzNi7myV36_"  # same key the apps ship with
LOCAL = ("localhost", "127.0.0.1", "[::1]")
PHONE_POOL = [f"+61491570{n}" for n in range(110, 160)]
COMPOSE_DIR = ROOT / "deploy"

ap = argparse.ArgumentParser()
ap.add_argument("--host", default=os.environ.get("QA_HOST", "localhost:6060"))
ap.add_argument("--only", default="", help="comma list of sections")
ap.add_argument("--md", default="", help="write the result table to this Markdown file")
ap.add_argument("--probe-port", type=int, default=0,
                help="port of a disposable server for checks that may crash it")
ap.add_argument("--no-cleanup", action="store_true")
ARGS = ap.parse_args()

HOST = ARGS.host
if HOST.rsplit(":", 1)[0] not in LOCAL:
    sys.exit(f"refusing to run against {HOST}: this suite creates throwaway accounts; local servers only")

RUN = format(int(time.time()) % 46656, "x")  # short run tag, keeps logins <= 32 chars


def invite_code():
    for line in (ROOT / "deploy" / "secrets.env").read_text().splitlines():
        if line.startswith("REGISTRATION_CODE="):
            return line.split("=", 1)[1].strip().strip('"')
    sys.exit("REGISTRATION_CODE not found in deploy/secrets.env")


CODE = invite_code()

# ───────────────────────────── result bookkeeping ─────────────────────────────

RESULTS = []  # (section, id, name, status, detail)
SECTION = ["-"]


def check(cid, name, ok, detail="", status=None):
    st = status or ("PASS" if ok else "FAIL")
    RESULTS.append((SECTION[0], cid, name, st, detail))
    print(f"  {st:5} {cid:5} {name}" + (f"  — {detail}" if detail else ""), flush=True)
    return ok


def info(cid, name, detail):
    return check(cid, name, True, detail, status="INFO")


def skip(cid, name, detail):
    return check(cid, name, True, detail, status="SKIP")


def code_of(c):
    return c.get("code") if c else None


# ───────────────────────────── protocol client ────────────────────────────────

class Conn:
    """One websocket session. call() sends a message with a fresh id and returns
    the ctrl answering it; everything else that arrives is kept in self.inbox."""

    def __init__(self, host=None, lang="en-AU", hi=True, timeout=8):
        self.url = f"ws://{host or HOST}/v0/channels?apikey={API_KEY}"
        self.ws = create_connection(self.url, timeout=timeout)
        self.n = 0
        self.inbox = []
        self.closed = False
        self.hi = None
        if hi:
            self.hi = self.call({"hi": {"ver": "0.23", "ua": "blml-server-suite/1.0", "lang": lang}})

    # low level
    def _recv(self, timeout):
        if timeout <= 0:
            return None
        self.ws.settimeout(timeout)
        try:
            raw = self.ws.recv()
        except WebSocketTimeoutException:
            return None
        except Exception:
            self.closed = True
            return None
        if raw in ("", None):
            return None
        try:
            return json.loads(raw)
        except ValueError:
            return {"_raw": raw}

    def send(self, obj):
        self.ws.send(obj if isinstance(obj, str) else json.dumps(obj))

    def next_id(self):
        self.n += 1
        return f"q{self.n}"

    def call(self, msg, timeout=8):
        """Returns the ctrl dict for msg (or None on timeout)."""
        ctrl, _ = self.call_full(msg, timeout)
        return ctrl

    def call_full(self, msg, timeout=8, quiet_after=0.0):
        mid = self.next_id()
        next(iter(msg.values()))["id"] = mid
        self.send(msg)
        frames = []
        end = time.time() + timeout
        while True:
            f = self._recv(end - time.time())
            if f is None:
                return None, frames
            body = next(iter(f.values())) if isinstance(f, dict) and f else {}
            if isinstance(body, dict) and body.get("id") == mid:
                frames.append(f)
                if "ctrl" in f:
                    return f["ctrl"], frames
                if quiet_after:
                    end = min(end, time.time() + quiet_after)
            else:
                self.inbox.append(f)

    def get(self, topic, what, **extra):
        """{get}: meta replies carry the id but there is no closing ctrl on success."""
        body = {"topic": topic, "what": what}
        body.update(extra)
        ctrl, frames = self.call_full({"get": body}, timeout=6, quiet_after=1.0)
        metas = [f["meta"] for f in frames if "meta" in f]
        datas = [f for f in self.inbox if "data" in f and f["data"].get("topic") == topic]
        return ctrl, metas, datas

    def wait(self, pred, timeout=4.0):
        for i, f in enumerate(self.inbox):
            if pred(f):
                return self.inbox.pop(i)
        end = time.time() + timeout
        while True:
            f = self._recv(end - time.time())
            if f is None:
                return None
            if pred(f):
                return f
            self.inbox.append(f)

    def drain(self, seconds=0.8):
        end = time.time() + seconds
        while True:
            f = self._recv(end - time.time())
            if f is None:
                return
            self.inbox.append(f)

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass
        self.closed = True


def b64(s):
    return base64.b64encode(s.encode()).decode()


class User:
    def __init__(self, login, password, uid, token, conn, phone=None):
        self.login, self.password, self.uid, self.token = login, password, uid, token
        self.conn, self.phone = conn, phone
        self.deleted = False

    @property
    def p2p(self):  # how others address this user
        return self.uid


CREATED = []
_seq = [0]


def new_login():
    _seq[0] += 1
    return f"qs{RUN}{_seq[0]:02d}"


def make_user(name=None, phone=None, lang="en-AU"):
    """Create + log in a throwaway account. phone: True = allocate from the pool."""
    login = new_login()
    pw = secrets.token_urlsafe(10)
    c = Conn(lang=lang)
    ctrl = c.call({"acc": {"user": "new", "scheme": "basic", "secret": b64(f"{login}:{pw}"), "login": True,
                           "tags": ["code:" + CODE], "desc": {"public": {"fn": name or f"QS {login}"}}}})
    if code_of(ctrl) != 200:
        raise RuntimeError(f"create {login}: {ctrl}")
    u = User(login, pw, ctrl["params"]["user"], ctrl["params"].get("token"), c)
    CREATED.append(u)
    c.call({"sub": {"topic": "me", "get": {"what": "desc sub"}}})
    if phone:
        u.phone = claim_phone(u) if phone is True else phone
    return u


def claim_phone(u, skip=()):
    while True:
        p = free_phone()
        c = u.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": p}}})
        if code_of(c) == 200:
            return p
        # 409: held by an account search cannot see (e.g. soft-deleted); try the next one


USED_PHONES = set()


def ensure_conn(u):
    """Reconnect u's main session if the server dropped it while it sat idle (the client only
    answers the server's pings while reading, and some sections sleep for seconds)."""
    alive = not u.conn.closed
    if alive:
        try:
            u.conn.ws.ping()
            u.conn.drain(0.2)
            alive = not u.conn.closed
        except Exception:
            alive = False
    if not alive:
        u.conn = Conn()
        u.conn.call({"login": {"scheme": "token", "secret": u.token}})
        u.conn.call({"sub": {"topic": "me"}})


_SEARCHER = []


def free_phone():
    """A pool number no account currently owns. Other testers share the pool, so
    every candidate is checked with a directory search first."""
    if not _SEARCHER:
        _SEARCHER.append(make_user("QS Pool Checker"))
    s = _SEARCHER[0]
    ensure_conn(s)
    for p in PHONE_POOL:
        if p in USED_PHONES:
            continue
        USED_PHONES.add(p)
        subs, _ = find(s.conn, f"tel:{p}")
        if not subs:
            return p
    raise RuntimeError("phone pool exhausted")


def login_conn(login, pw, lang="en-AU"):
    c = Conn(lang=lang)
    ctrl = c.call({"login": {"scheme": "basic", "secret": b64(f"{login}:{pw}")}})
    return c, ctrl


def sub(u, topic, get="desc sub", **extra):
    body = {"topic": topic, "get": {"what": get}}
    body.update(extra)
    return u.conn.call({"sub": body})


def pub(u, topic, content, head=None, noecho=False):
    body = {"topic": topic, "content": content, "noecho": noecho}
    if head:
        body["head"] = head
    return u.conn.call({"pub": body})


FULL_P2P = "JRWPAD"  # what a p2p chat ends up with on this server (p2p_delete_enabled)


def accept(b, a):
    """b accepts a's chat request the way the contract says: own want with W, in a {sub}."""
    return b.conn.call({"sub": {"topic": a.uid, "set": {"sub": {"mode": FULL_P2P}}, "get": {"what": "desc sub"}}})


def befriend(a, b):
    """A working 1:1 chat since round 2: a requests (plain sub), b accepts. Returns (a's ctrl, b's ctrl)."""
    r1 = sub(a, b.uid)
    r2 = accept(b, a)
    return r1, r2


def acs_of(ctrl):
    return ((ctrl or {}).get("params") or {}).get("acs") or {}


def desc_acs(u, topic):
    ctrl, metas, _ = u.conn.get(topic, "desc")
    for m in metas:
        acs = (m.get("desc") or {}).get("acs")
        if acs:
            return acs
    return {}


def seq_of(ctrl):
    return ((ctrl or {}).get("params") or {}).get("seq")


def fuid(x):
    return x.get("user") or x.get("topic")


def find(conn, query, lang=None):
    """fnd search on its own connection state: set public, get sub."""
    conn.call({"sub": {"topic": "fnd"}})
    c = conn.call({"set": {"topic": "fnd", "desc": {"public": query}}})
    ctrl, metas, _ = conn.get("fnd", "sub")
    subs = [s for m in metas for s in (m.get("sub") or [])]
    return subs, ctrl


def history(u, topic, limit=50):
    """Messages the server holds for topic, as this user sees them, read on a
    fresh connection so live frames from the user's main session cannot mix in."""
    c = Conn()
    c.call({"login": {"scheme": "token", "secret": u.token}})
    ctrl = c.call({"sub": {"topic": topic, "get": {"what": "data", "data": {"limit": limit}}}})
    c.drain(0.8)
    datas = [f["data"] for f in c.inbox if "data" in f and f["data"].get("topic") == topic]
    c.close()
    return ctrl, datas


def http(method, path, headers=None, body=None, timeout=30):
    req = urllib.request.Request(f"http://{HOST}{path}", data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()
    except Exception as e:  # connection reset on oversized bodies, etc.
        return None, {}, str(e).encode()


def multipart(fields, filename, content, ctype="application/octet-stream"):
    boundary = "----blmlqa" + uuid.uuid4().hex
    out = []
    for k, v in fields.items():
        out.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode())
    out.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
               f"Content-Type: {ctype}\r\n\r\n".encode())
    out.append(content)
    out.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(out), f"multipart/form-data; boundary={boundary}"


def server_alive():
    try:
        c = Conn()
        ok = code_of(c.hi) == 201
        c.close()
        return ok
    except Exception:
        return False


def server_log_since(since):
    try:
        out = subprocess.run(["docker", "compose", "-p", "blml-qa", "logs", "--since", since, "blml"],
                             cwd=COMPOSE_DIR, capture_output=True, text=True, timeout=60)
        return out.stdout + out.stderr
    except Exception as e:
        return f"(could not read logs: {e})"


def is_pres(topic=None, what=None, src=None):
    def p(f):
        if "pres" not in f:
            return False
        x = f["pres"]
        return (topic is None or x.get("topic") == topic) and (what is None or x.get("what") == what) \
            and (src is None or x.get("src") == src)
    return p


def is_data(topic, seq=None):
    return lambda f: "data" in f and f["data"].get("topic") == topic and (seq is None or f["data"].get("seq") == seq)


def is_info(topic=None, what=None, src=None):
    def p(f):
        if "info" not in f:
            return False
        x = f["info"]
        return (topic is None or x.get("topic") == topic) and (what is None or x.get("what") == what) \
            and (src is None or x.get("from") == src)
    return p


# ─────────────────────────────────── sections ─────────────────────────────────

def s_accounts():
    login = new_login()
    pw = secrets.token_urlsafe(10)
    c = Conn()
    acc = {"user": "new", "scheme": "basic", "secret": b64(f"{login}:{pw}"), "login": False,
           "desc": {"public": {"fn": "QS nocode"}}}
    r = c.call({"acc": dict(acc)})
    check("A1", "signup without invite code refused (403)", code_of(r) == 403, f"{code_of(r)} {r and r.get('text')}")
    r = c.call({"acc": dict(acc, tags=["code:WRONG-CODE"])})
    check("A2", "signup with wrong invite code refused (403)", code_of(r) == 403, f"{code_of(r)} {r and r.get('text')}")
    r = c.call({"acc": dict(acc, tags=["code:" + CODE.lower()])})
    info("A2b", "invite code case-sensitivity", f"lower-cased code -> {code_of(r)}")
    if code_of(r) == 200:
        # it created an account; log in to clean it up later
        c2, lc = login_conn(login, pw)
        CREATED.append(User(login, pw, lc["params"]["user"], None, c2))
        login = new_login()
        acc["secret"] = b64(f"{login}:{pw}")
    r = c.call({"acc": dict(acc, tags=["code:" + CODE], login=True)})
    ok = code_of(r) == 200 and (r.get("params") or {}).get("user")
    check("A3", "signup with right code succeeds (200 + uid + token)", bool(ok and r["params"].get("token")),
          f"{code_of(r)}")
    if not ok:
        return
    u = User(login, pw, r["params"]["user"], r["params"].get("token"), c)
    CREATED.append(u)
    sub(u, "me")
    ctrl, metas, _ = c.get("me", "tags")
    tags = [t for m in metas for t in (m.get("tags") or [])]
    check("A3b", "invite code is not stored as a tag", not any(t.startswith("code:") for t in tags), str(tags))

    # duplicate login name
    c3 = Conn()
    r = c3.call({"acc": dict(acc, tags=["code:" + CODE], secret=b64(f"{login}:{pw}x"))})
    check("A4", "signup with an existing login -> 409", code_of(r) == 409, f"{code_of(r)} {r and r.get('text')}")

    # login good/bad
    c4, r = login_conn(login, pw)
    check("A5", "basic login, right password -> 200", code_of(r) == 200, f"{code_of(r)}")
    r2 = c4.call({"login": {"scheme": "basic", "secret": b64(f"{login}:{pw}")}})
    check("A6", "second login on an authenticated session -> 409", code_of(r2) == 409, f"{code_of(r2)} {r2 and r2.get('text')}")
    c4.close()
    c5, r = login_conn(login, pw + "x")
    check("A7", "basic login, wrong password -> 401", code_of(r) == 401, f"{code_of(r)} {r and r.get('text')}")
    c5.close()
    c5, r = login_conn("nosuchuser" + RUN, "whatever1")
    check("A8", "basic login, unknown login -> 401 (same as wrong password)", code_of(r) == 401, f"{code_of(r)}")
    r = c5.call({"login": {"scheme": "nonexistent", "secret": b64("x")}})
    check("A9", "login with unknown scheme -> 401/400, not 5xx", code_of(r) in (400, 401), f"{code_of(r)} {r and r.get('text')}")
    c5.close()

    # token login
    c6 = Conn()
    r = c6.call({"login": {"scheme": "token", "secret": u.token}})
    check("A10", "token login -> 200", code_of(r) == 200, f"{code_of(r)}")
    c6.close()

    # firebase scheme
    c7 = Conn()
    r = c7.call({"login": {"scheme": "firebase", "secret": ""}})
    check("A11", "firebase login, empty token -> 4xx", code_of(r) is not None and 400 <= code_of(r) < 500,
          f"{code_of(r)} {r and r.get('text')}")
    r = c7.call({"acc": {"user": "new", "scheme": "firebase", "secret": b64("garbage"), "login": True,
                          "desc": {"public": {"fn": "QS fb"}}}})
    check("A12", "firebase signup without invite code refused (403, or 400 when firebase is not configured)",
          code_of(r) in (400, 403), f"{code_of(r)} {r and r.get('text')}")
    c7.close()
    # Crash checks. Run on the disposable probe first (if given), then on the shared server:
    # since the 2026-10-02 fix an unconfigured firebase scheme is refused with a 4xx.
    targets = ([("probe", f"localhost:{ARGS.probe_port}")] if ARGS.probe_port else []) + [("shared", HOST)]
    for label, target in targets:
        sfx = "p" if label == "probe" else ""
        try:
            cp = Conn(host=target)
            r = cp.call({"login": {"scheme": "firebase", "secret": b64("garbage.token.value")}}, timeout=5)
            r2 = cp.call({"acc": {"user": "new", "scheme": "firebase", "secret": b64("garbage.token.value"),
                                  "login": True, "tags": ["code:" + CODE], "desc": {"public": {"fn": "QS fb"}}}},
                         timeout=5)
            # Unknown temp-auth scheme on an account update: was a nil-handler panic upstream.
            r3 = cp.call({"acc": {"user": "usrAAAAAAAAAAA", "tmpscheme": "nonexistent", "tmpsecret": b64("x"),
                                  "scheme": "basic", "secret": b64(":whatever1")}}, timeout=5)
            # Same scheme through the file endpoint's auth header.
            st, _, _ = http("GET", "/v0/file/s/nonexistent.png", {"X-Tinode-APIKey": API_KEY,
                            "X-Tinode-Auth": "firebase " + b64("garbage.token.value")}) if label == "shared" else (None, 0, 0)
            cp.close()
            time.sleep(1.5)
            alive = True
            try:
                Conn(host=target).close()
            except Exception:
                alive = False
            four = lambda c: c is not None and 400 <= c < 500
            check("A13" + sfx, f"firebase login, garbage token, firebase not configured -> 4xx and server stays up ({label})",
                  four(code_of(r)) and alive, f"reply={code_of(r)} {r and r.get('text')} alive_after={alive}")
            check("A13b" + sfx, f"firebase signup (with invite code), garbage token -> 4xx ({label})",
                  four(code_of(r2)) and alive, f"reply={code_of(r2)} {r2 and r2.get('text')}")
            check("A13c" + sfx, f"acc with unknown tmpscheme -> 4xx, no crash ({label})",
                  four(code_of(r3)) and alive, f"reply={code_of(r3)} {r3 and r3.get('text')}")
            if label == "shared":
                check("A13d", "file download authenticated with the unconfigured firebase scheme -> 4xx",
                      four(st) and server_alive(), f"{st}")
        except Exception as e:
            check("A13" + sfx, f"firebase crash checks ({label})", False, f"server unreachable: {e}")

    # password change
    newpw = secrets.token_urlsafe(10)
    r = u.conn.call({"acc": {"user": u.uid, "scheme": "basic", "secret": b64(f":{newpw}")}})
    check("A14", "password change on own account -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    c8, r_old = login_conn(login, pw)
    c9, r_new = login_conn(login, newpw)
    check("A15", "after change: old password 401, new password 200",
          code_of(r_old) == 401 and code_of(r_new) == 200, f"old={code_of(r_old)} new={code_of(r_new)}")
    u.password = newpw
    c8.close()
    # old token still valid after a password change?
    c10 = Conn()
    r = c10.call({"login": {"scheme": "token", "secret": u.token}})
    check("A16", "token issued before a password change is revoked", code_of(r) != 200,
          f"old token login -> {code_of(r)}")
    c10.close()
    # an existing session survives?
    r = u.conn.call({"get": {"topic": "me", "what": "desc"}})
    info("A16b", "already-open sessions after password change", "still usable" if not u.conn.closed else "closed")
    # change someone else's password
    other = make_user()
    r = c9.call({"acc": {"user": other.uid, "scheme": "basic", "secret": b64(":hacked123")}})
    check("A17", "non-root cannot change another user's password", code_of(r) in (401, 403), f"{code_of(r)} {r and r.get('text')}")
    c9.close()
    # too-short password
    r = u.conn.call({"acc": {"user": u.uid, "scheme": "basic", "secret": b64(":abc")}})
    check("A18", "password shorter than 6 refused (4xx)", code_of(r) in (400, 422), f"{code_of(r)} {r and r.get('text')}")

    s_account_deletion()


def s_account_deletion():
    d = make_user("QS Doomed", phone=True)
    peer = make_user("QS DelPeer")
    # p2p between d and peer, with history
    befriend(d, peer)
    r = pub(d, peer.uid, "msg from soon-deleted user")
    # group owned by d with peer as member
    g1 = d.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS doomed-owned"}}}}})
    g_owned = g1.get("topic")
    d.conn.call({"set": {"topic": g_owned, "sub": {"user": peer.uid}}})
    sub(peer, g_owned)
    # group owned by peer with d as member, d posts there
    g2 = peer.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS peer-owned"}}}}})
    g_peer = g2.get("topic")
    peer.conn.call({"set": {"topic": g_peer, "sub": {"user": d.uid}}})
    sub(d, g_peer)
    pub(d, g_peer, "group msg from soon-deleted user")
    peer.conn.drain(0.5)
    peer.conn.inbox.clear()

    r = d.conn.call({"del": {"what": "user", "hard": True}})
    d.deleted = True
    check("D1", "account self-delete (hard, as the apps do) -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    time.sleep(1)
    peer.conn.drain(1.0)
    pres = [f["pres"] for f in peer.conn.inbox if "pres" in f]
    gone = [p for p in pres if p.get("what") == "gone"]
    info("D2", "what the peer is told", json.dumps([{k: p.get(k) for k in ('topic', 'what', 'src')} for p in pres])[:300])
    c, lr = login_conn(d.login, d.password)
    check("D3", "deleted account cannot log in", code_of(lr) == 401, f"{code_of(lr)}")
    c.close()
    r = Conn().call({"login": {"scheme": "token", "secret": d.token}})
    check("D4", "deleted account's token no longer works", code_of(r) != 200, f"{code_of(r)}")
    # peer's view of the p2p topic
    peer2 = Conn()
    peer2.call({"login": {"scheme": "token", "secret": peer.token}})
    r = peer2.call({"sub": {"topic": d.uid, "get": {"what": "desc"}}})
    info("D5", "peer subscribes to p2p with deleted user", f"{code_of(r)} {r and r.get('text')}")
    r2 = peer2.call({"pub": {"topic": d.uid, "content": "are you there?"}})
    check("D6", "peer cannot post to a deleted user's p2p topic", code_of(r2) is not None and code_of(r2) >= 400,
          f"{code_of(r2)} {r2 and r2.get('text')}")
    peer2.call({"sub": {"topic": "me"}})
    ctrl, metas, _ = peer2.get("me", "sub")
    p2p_still = [s for m in metas for s in (m.get("sub") or []) if s.get("topic") == d.uid]
    info("D7", "deleted user's chat still in the peer's chat list", f"{bool(p2p_still)} {json.dumps(p2p_still)[:200]}")
    r = peer2.call({"sub": {"topic": g_owned}})
    check("D8", "group owned by the deleted user is gone for members (404)", code_of(r) == 404, f"{code_of(r)} {r and r.get('text')}")
    r = peer2.call({"sub": {"topic": g_peer, "get": {"what": "sub data", "data": {"limit": 10}}}})
    peer2.drain(0.8)
    msgs = [f["data"] for f in peer2.inbox if "data" in f and f["data"]["topic"] == g_peer]
    left = [m for m in msgs if m.get("from") == d.uid]
    info("D9", "deleted user's messages in other people's groups", f"{len(left)} left, attributed to {d.uid}")
    subs = [s for f in peer2.inbox if "meta" in f for s in (f["meta"].get("sub") or [])]
    check("D10", "deleted user removed from member list of a group they did not own",
          not any(s.get("user") == d.uid for s in subs), f"members={[s.get('user') for s in subs]}")
    subs_f, _ = find(peer2, f"basic:{d.login}")
    check("D11", "deleted user not found by login search", not subs_f, f"{len(subs_f)} result(s)")
    subs_f, _ = find(peer2, f"tel:{d.phone}")
    check("D12", "deleted user not found by phone search", not subs_f, f"{len(subs_f)} result(s)")
    # number is free again
    n = make_user()
    r = n.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": d.phone}}})
    check("D13", "deleted user's phone number can be claimed by a new account", code_of(r) == 200,
          f"{code_of(r)} {r and r.get('text')}")
    peer2.close()


def get_tags(u):
    ctrl, metas, _ = u.conn.get("me", "tags")
    return [t for m in metas for t in (m.get("tags") or [])]


def get_creds(u):
    ctrl, metas, _ = u.conn.get("me", "cred")
    return [c for m in metas for c in (m.get("cred") or [])]


def s_tel():
    a = make_user("QS Tel A")
    b = make_user("QS Tel B")
    p = free_phone()
    r = a.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": p}}})
    params = (r or {}).get("params") or {}
    check("T1", "adding a phone auto-confirms (200, params done=true)",
          code_of(r) == 200 and params.get("done") is True, f"{code_of(r)} params={params}")
    creds = get_creds(a)
    check("T2", "credential stored as confirmed", any(c.get("val") == p and c.get("done") for c in creds), str(creds))
    check("T3", "tel tag added for discovery", f"tel:{p}" in get_tags(a), str(get_tags(a)))
    r = a.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": p}}})
    check("T4", "re-adding own number is a no-op 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": p}}})
    check("T5", "same number on a second account -> 409", code_of(r) == 409, f"{code_of(r)} {r and r.get('text')}")
    spaced = p[:3] + " " + p[3:6] + " " + p[6:9] + " " + p[9:]
    r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": spaced}}})
    check("T6", "same number written with spaces on a second account -> 409", code_of(r) == 409,
          f"{spaced!r} -> {code_of(r)}")
    for bad, reason in (("12345", "region-required"), ("abc", "not-a-number"), ("+6149157", "too-short"),
                        ("+61 2 9999 9999 9999", "too-long"), ("<script>", "not-a-number"),
                        ("+999 123 456 789", "invalid-country-code")):
        r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": bad}}})
        got = ((r or {}).get("params") or {}).get("reason")
        check("T7", f"malformed number {bad!r} -> 400 reason={reason} with a readable text",
              code_of(r) == 400 and got == reason and (r.get("text") or "") not in ("", "malformed"),
              f"{code_of(r)} {r and r.get('text')!r} reason={got}")
    r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": "0491 570 999", "params": {"region": "XX"}}}})
    check("T7b", "unknown region hint -> 400 reason=invalid-region",
          code_of(r) == 400 and ((r or {}).get("params") or {}).get("reason") == "invalid-region", f"{code_of(r)} {r and r.get('text')!r}")
    # landline: any plausible number is accepted now, not only mobiles (ACMA fiction range 02 5550 xxxx)
    x = make_user("QS Tel X")
    fixed = f"+61 2 5550 {secrets.randbelow(10000):04d}"
    r = x.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": fixed}}})
    want_tag = "tel:" + fixed.replace(" ", "")
    check("T8", "fixed-line number accepted and stored as E.164", code_of(r) == 200 and want_tag in get_tags(x),
          f"{fixed} -> {code_of(r)} {r and r.get('text')} tags={get_tags(x)}")
    x.conn.call({"del": {"topic": "me", "what": "cred", "cred": {"meth": "tel", "val": fixed.replace(" ", "")}}})
    # local format
    p2 = free_phone()
    local = "0" + p2[3:]
    r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": local}}})
    reason = ((r or {}).get("params") or {}).get("reason")
    check("T9", "local-format number without a region -> 400 reason=region-required (clear message, not a bare 400)",
          code_of(r) == 400 and reason == "region-required", f"{local} -> {code_of(r)} {r and r.get('text')!r} reason={reason}")
    if code_of(r) != 200:
        r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": local, "params": {"countryCode": "AU"}}}})
        check("T10", "local-format number with countryCode=AU -> 200 and stored as E.164",
              code_of(r) == 200 and f"tel:{p2}" in get_tags(b), f"{code_of(r)} tags={get_tags(b)}")
    else:
        check("T10", "local-format number stored as E.164", f"tel:{p2}" in get_tags(b), str(get_tags(b)))
    b.phone = p2
    # region hint (the documented name) and every common notation; all stored as E.164
    for cid, fmt, params in (("T10b", lambda q: f"0{q[3:6]} {q[6:9]} {q[9:]}", {"region": "AU"}),
                             ("T10c", lambda q: f"{q[:3]}-{q[3:6]}-{q[6:9]}-{q[9:]}", None),
                             ("T10d", lambda q: f"({q[3:4].replace('4', '04')}{q[4:6]}) {q[6:9]}.{q[9:]}", {"region": "au"}),
                             ("T10e", lambda q: f"{q[:3]} (0) {q[3:6]} {q[6:9]} {q[9:]}", None)):
        u = make_user("QS Tel " + cid)
        q = free_phone()
        val = fmt(q)
        cred = {"meth": "tel", "val": val}
        if params:
            cred["params"] = params
        r = u.conn.call({"set": {"topic": "me", "cred": cred}})
        check(cid, f"{val!r} params={params} -> 200 and tagged tel:{q}", code_of(r) == 200 and f"tel:{q}" in get_tags(u),
              f"{code_of(r)} {r and r.get('text')} tags={[t for t in get_tags(u) if t.startswith('tel:')]}")
    # "possible but not valid": 0495 is not an AU mobile range in libphonenumber's metadata
    u = make_user("QS Tel Possible")
    q = free_phone()
    odd = "+61495" + q[6:]
    r = u.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": odd[:3] + " " + odd[3:6] + " " + odd[6:]}}})
    check("T10f", "possible-but-not-valid number (+61 495 …) accepted", code_of(r) == 200 and f"tel:{odd}" in get_tags(u),
          f"{code_of(r)} {r and r.get('text')}")
    # one account per number, whatever the notation
    r = u.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": f"(0{p[3:6]}) {p[6:9]}-{p[9:]}",
                                                     "params": {"region": "AU"}}}})
    check("T6b", "a taken number in local notation with region -> 409", code_of(r) == 409, f"{code_of(r)} {r and r.get('text')}")

    # tag namespace is protected
    r = b.conn.call({"set": {"topic": "me", "tags": ["tel:" + p, "hello"]}})
    tags_b = get_tags(b)
    check("T11", "user cannot add someone else's number as a raw tel: tag", f"tel:{p}" not in tags_b,
          f"{code_of(r)} tags={tags_b}")
    r = b.conn.call({"set": {"topic": "me", "tags": ["email:victim@example.com"]}})
    check("T12", "user cannot add an unverified email: tag", "email:victim@example.com" not in get_tags(b),
          f"{code_of(r)} {r and r.get('text')}")
    r = b.conn.call({"set": {"topic": "me", "tags": ["basic:qa_ios"]}})
    check("T13", "user cannot add a basic: (login) tag", "basic:qa_ios" not in get_tags(b), f"{code_of(r)}")

    # second number on the same account (a "change number" without deleting the old one)
    p3 = free_phone()
    r = a.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": p3}}})
    creds = [c for c in get_creds(a) if c.get("meth") == "tel"]
    tags = [t for t in get_tags(a) if t.startswith("tel:")]
    info("T14", "adding a 2nd number keeps the first", f"{code_of(r)} creds={[(c['val'], c.get('done')) for c in creds]} tags={tags}")

    # removing a number
    r = a.conn.call({"del": {"topic": "me", "what": "cred", "cred": {"meth": "tel", "val": p}}})
    check("T15", "removing a number -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    tags = get_tags(a)
    check("T16", "removed number's tel: tag is gone", f"tel:{p}" not in tags, str(tags))
    subs, _ = find(b.conn, f"tel:{p}")
    check("T17", "removed number no longer finds the account", not any(s.get("user") == a.uid for s in subs),
          f"{[s.get('user') for s in subs]}")
    r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "tel", "val": p}}})
    check("T18", "removed number can be claimed by another account", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    subs, _ = find(make_user().conn, f"tel:{p}")
    users = [fuid(s) for s in subs]
    check("T19", "after re-claim, the number finds only the new owner", users == [b.uid], f"{users} (a={a.uid}, b={b.uid})")
    # remove the last number
    r = a.conn.call({"del": {"topic": "me", "what": "cred", "cred": {"meth": "tel", "val": p3}}})
    info("T20", "removing the only remaining number", f"{code_of(r)} {r and r.get('text')}")
    # phone at signup: duplicate
    login = new_login()
    c = Conn()
    r = c.call({"acc": {"user": "new", "scheme": "basic", "secret": b64(f"{login}:pw{RUN}xyz"), "login": False,
                        "tags": ["code:" + CODE], "desc": {"public": {"fn": "QS dupe-at-signup"}},
                        "cred": [{"meth": "tel", "val": p2}]}})
    check("T21", "signup carrying an already-taken number -> 409", code_of(r) == 409, f"{code_of(r)} {r and r.get('text')}")
    c2, lr = login_conn(login, f"pw{RUN}xyz")
    check("T22", "...and no half-made account is left behind", code_of(lr) == 401, f"login after failed signup -> {code_of(lr)}")
    if code_of(lr) == 200:
        CREATED.append(User(login, f"pw{RUN}xyz", lr["params"]["user"], None, c2))
    # phone at signup, fresh number
    p4 = free_phone()
    login = new_login()
    r = Conn().call({"acc": {"user": "new", "scheme": "basic", "secret": b64(f"{login}:pw{RUN}xyz"), "login": True,
                             "tags": ["code:" + CODE], "desc": {"public": {"fn": "QS phone-at-signup"}},
                             "cred": [{"meth": "tel", "val": p4}]}})
    ok = code_of(r) == 200
    if ok:
        c3, lr = login_conn(login, f"pw{RUN}xyz")
        u = User(login, f"pw{RUN}xyz", lr["params"]["user"], None, c3)
        CREATED.append(u)
        sub(u, "me")
        check("T23", "signup with a fresh number -> confirmed and tagged", f"tel:{p4}" in get_tags(u), str(get_tags(u)))
    else:
        check("T23", "signup with a fresh number", False, f"{code_of(r)} {r and r.get('text')}")
    # email credential (validator configured with debug_response, not auto_confirm)
    r = b.conn.call({"set": {"topic": "me", "cred": {"meth": "email", "val": f"qs{RUN}@example.com"}}})
    info("T24", "adding an email credential", f"{code_of(r)} {r and r.get('text')} params={(r or {}).get('params')}")


def s_p2p():
    a = make_user("QS Alice")
    b = make_user("QS Bob")
    c = make_user("QS Carol")
    r = sub(a, b.uid)
    check("P1", "A subscribes to p2p with B", code_of(r) in (200, 201), f"{code_of(r)}")
    r = accept(b, a)
    r = pub(a, b.uid, "hello bob")
    s1 = seq_of(r)
    check("P2", "A publishes -> 202 + seq", code_of(r) == 202 and s1, f"{code_of(r)} seq={s1}")
    f = b.conn.wait(is_data(a.uid, s1))
    check("P3", "B receives the data frame live", bool(f) and f["data"].get("content") == "hello bob" and f["data"].get("from") == a.uid,
          f"{bool(f)}")
    # notes
    a.conn.inbox.clear()
    b.conn.send({"note": {"topic": a.uid, "what": "recv", "seq": s1}})
    fr = a.conn.wait(is_info(b.uid, "recv", b.uid))
    check("P4", "recv note propagates to sender", bool(fr) and fr["info"].get("seq") == s1, json.dumps(fr)[:150] if fr else "none")
    b.conn.send({"note": {"topic": a.uid, "what": "read", "seq": s1}})
    fr = a.conn.wait(is_info(b.uid, "read", b.uid))
    check("P5", "read note propagates to sender", bool(fr) and fr["info"].get("seq") == s1, json.dumps(fr)[:150] if fr else "none")
    b.conn.send({"note": {"topic": a.uid, "what": "kp"}})
    fr = a.conn.wait(is_info(b.uid, "kp", b.uid))
    check("P6", "typing (kp) note propagates", bool(fr), "")
    # read pointer beyond last seq
    b.conn.send({"note": {"topic": a.uid, "what": "read", "seq": 999999}})
    time.sleep(0.5)
    ctrl, metas, _ = b.conn.get(a.uid, "desc")
    d = (metas[0].get("desc") if metas else {}) or {}
    check("P7", "read note with seq beyond the last message is ignored", (d.get("read") or 0) <= (d.get("seq") or 0),
          f"read={d.get('read')} seq={d.get('seq')}")
    # reply
    r = pub(b, a.uid, "re: hello", head={"reply": f":{s1}"})
    s2 = seq_of(r)
    f = a.conn.wait(is_data(b.uid, s2))
    check("P8", "reply head delivered intact", bool(f) and (f["data"].get("head") or {}).get("reply") == f":{s1}",
          json.dumps((f or {}).get("data", {}).get("head"))[:100])
    # edit by author
    r = pub(a, b.uid, "hello bob (edited)", head={"replace": f":{s1}"})
    s3 = seq_of(r)
    f = b.conn.wait(is_data(a.uid, s3))
    check("P9", "author edit (head.replace) accepted and delivered", code_of(r) == 202 and bool(f)
          and (f["data"].get("head") or {}).get("replace") == f":{s1}", f"{code_of(r)}")
    # edit of someone else's message
    r = pub(b, a.uid, "I never said this", head={"replace": f":{s1}"})
    check("P10", "non-author cannot edit (head.replace of another user's message refused)",
          code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)} — server stored it as seq {seq_of(r)}")
    # edit pointing at a non-existent / future seq
    r = pub(a, b.uid, "ghost edit", head={"replace": ":99999"})
    check("P11", "edit of a non-existent message refused", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)}")
    # head spoofing: sender
    r = pub(b, a.uid, "spoof", head={"sender": a.uid, "forwarded": "usrXXXX:1"})
    f = a.conn.wait(is_data(b.uid, seq_of(r)))
    hd = (f or {}).get("data", {}).get("head") or {}
    info("P12", "client-supplied head keys (sender/forwarded)", f"{code_of(r)} delivered head={hd}")
    # delete for everyone by author
    r = pub(a, b.uid, "to be deleted")
    s4 = seq_of(r)
    b.conn.inbox.clear()
    r = a.conn.call({"del": {"topic": b.uid, "what": "msg", "delseq": [{"low": s4}], "hard": True}})
    check("P13", "author delete-for-everyone -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    _, msgs = history(b, a.uid)
    check("P14", "deleted message is gone from the peer's history", not any(m["seq"] == s4 for m in msgs),
          f"seqs={[m['seq'] for m in msgs]}")
    # non-author delete-for-everyone
    r = pub(a, b.uid, "B should not be able to unsend this")
    s5 = seq_of(r)
    r = b.conn.call({"del": {"topic": a.uid, "what": "msg", "delseq": [{"low": s5}], "hard": True}})
    _, msgs = history(a, b.uid)
    gone = not any(m["seq"] == s5 for m in msgs)
    check("P15", "non-author cannot delete-for-everyone in p2p (explicit 403)", code_of(r) == 403 and not gone,
          f"B del A's msg -> {code_of(r)}; gone from A's history: {gone}")
    # B can still unsend B's own message
    r = pub(b, a.uid, "B unsends this")
    sb = seq_of(r)
    r = b.conn.call({"del": {"topic": a.uid, "what": "msg", "delseq": [{"low": sb}], "hard": True}})
    _, msgs = history(a, b.uid)
    check("P15b", "peer can delete-for-everyone their own p2p message", code_of(r) == 200 and not any(m["seq"] == sb for m in msgs),
          f"{code_of(r)}")
    # "clear chat for everyone" spans both people's messages: refused, nothing deleted
    r = b.conn.call({"del": {"topic": a.uid, "what": "msg", "delseq": [{"low": 1, "hi": sb + 1}], "hard": True}})
    _, msgs = history(a, b.uid)
    check("P15c", "p2p clear-all-for-everyone (range incl. the peer's messages) refused, nothing deleted",
          code_of(r) == 403 and any(m["seq"] == s5 for m in msgs), f"{code_of(r)} {r and r.get('text')}")
    # soft delete (for me)
    r = pub(a, b.uid, "soft delete me")
    s6 = seq_of(r)
    r = b.conn.call({"del": {"topic": a.uid, "what": "msg", "delseq": [{"low": s6}]}})
    _, msgs_a = history(a, b.uid)
    _, msgs_b = history(b, a.uid)
    check("P16", "delete-for-me hides only for the deleter",
          code_of(r) == 200 and any(m["seq"] == s6 for m in msgs_a) and not any(m["seq"] == s6 for m in msgs_b),
          f"{code_of(r)}")
    # outsider
    r = c.conn.call({"pub": {"topic": a.uid, "content": "hi from carol"}})
    info("P17", "third party publishing to A's p2p address creates their own p2p (not A-B)", f"{code_of(r)}")
    # pub to self
    r = a.conn.call({"pub": {"topic": a.uid, "content": "to myself"}})
    info("P19", "publish to own usr id", f"{code_of(r)} {r and r.get('text')}")
    # message order under fast sends
    seqs = []
    for i in range(30):
        a.conn.send({"pub": {"id": f"fast{i}", "topic": b.uid, "content": f"fast {i}", "noecho": True}})
    got = {}
    end = time.time() + 8
    while len(got) < 30 and time.time() < end:
        f = a.conn._recv(end - time.time())
        if f and "ctrl" in f and str(f["ctrl"].get("id", "")).startswith("fast"):
            got[f["ctrl"]["id"]] = seq_of(f["ctrl"])
        elif f:
            a.conn.inbox.append(f)
    ordered = [got.get(f"fast{i}") for i in range(30)]
    check("P20", "30 rapid sends: all acked, seq in send order", None not in ordered and ordered == sorted(ordered),
          f"{len(got)}/30 acked")
    # deleting someone's message after msg_delete_age? (600s) — not waited for; report config only
    return a, b, c


def s_groups():
    o = make_user("QS Owner")
    m = make_user("QS Member")
    x = make_user("QS Outsider")
    m2 = make_user("QS Member2")
    r = o.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS group"}}, "tags": [f"qsgrp{RUN}"]},
                             "get": {"what": "desc sub"}}})
    g = (r or {}).get("topic", "")
    check("G1", "create group -> 200 grp…", code_of(r) == 200 and g.startswith("grp"), f"{code_of(r)} {g}")
    ctrl, metas, _ = o.conn.get(g, "desc")
    defacs = (metas[0].get("desc") or {}).get("defacs") if metas else None
    info("G1b", "default access of a group created the way the apps do", json.dumps(defacs))
    r = o.conn.call({"set": {"topic": g, "sub": {"user": m.uid}}})
    check("G2", "owner invites a member -> 200", code_of(r) == 200, f"{code_of(r)}")
    inv = m.conn.wait(lambda f: ("pres" in f and f["pres"].get("src") == g) or ("data" in f and f["data"].get("topic") == "me"), 3)
    info("G2b", "invitee is notified", json.dumps(inv)[:160] if inv else "nothing on me")
    r = sub(m, g)
    check("G3", "member joins", code_of(r) in (200, 201), f"{code_of(r)}")
    r = pub(m, g, "member says hi")
    s = seq_of(r)
    fo = o.conn.wait(is_data(g, s))
    check("G4", "member can post; owner receives it", code_of(r) == 202 and bool(fo), f"{code_of(r)}")

    # outsider
    r = x.conn.call({"get": {"topic": g, "what": "data"}})
    check("G5", "non-member cannot read history without subscribing", code_of(r) is not None and code_of(r) >= 400,
          f"{code_of(r)} {r and r.get('text')}")
    r = x.conn.call({"pub": {"topic": g, "content": "outsider post"}})
    check("G6", "non-member cannot post without subscribing", code_of(r) is not None and code_of(r) >= 400,
          f"{code_of(r)} {r and r.get('text')}")
    r = x.conn.call({"sub": {"topic": g, "get": {"what": "data sub", "data": {"limit": 20}}}})
    x.conn.drain(0.8)
    leaked = [f for f in x.conn.inbox if "data" in f and f["data"].get("topic") == g]
    check("G7", "uninvited user who knows the group id cannot join and read it", code_of(r) not in (200, 201) and not leaked,
          f"sub -> {code_of(r)} {r and r.get('text')}; {len(leaked)} message(s) readable")
    check("G7b", "...refused at once with a clear 403 (what=invite-only), not a timeout",
          code_of(r) == 403 and ((r or {}).get("params") or {}).get("what") == "invite-only", json.dumps(r)[:160])
    r2 = x.conn.call({"set": {"topic": g, "sub": {"mode": "JRWPS"}}})
    check("G7c", "...nor by {set sub} on themselves (4xx)", code_of(r2) in (403, 404), f"{code_of(r2)} {r2 and r2.get('text')}")
    if code_of(r) in (200, 201):
        r = pub(x, g, "uninvited user posting")
        check("G8", "...and cannot post after self-joining", code_of(r) != 202, f"{code_of(r)}")
        x.conn.call({"leave": {"topic": g, "unsub": True}})
    # discoverable by tag?
    subs, _ = find(x.conn, f"qsgrp{RUN}")
    info("G9", "group with tags discoverable via fnd by any user", f"{[s.get('topic') for s in subs]}")

    # member can't manage
    r = m.conn.call({"set": {"topic": g, "desc": {"public": {"fn": "renamed by member"}}}})
    check("G10", "plain member cannot rename the group", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)}")
    r = o.conn.call({"set": {"topic": g, "sub": {"user": m2.uid}}})
    sub(m2, g)
    r = m.conn.call({"del": {"topic": g, "what": "sub", "user": m2.uid}})
    check("G11", "plain member cannot remove another member", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)}")
    # member deleting own message for everyone
    r = pub(m, g, "member wants to unsend this")
    sm = seq_of(r)
    r = m.conn.call({"del": {"topic": g, "what": "msg", "delseq": [{"low": sm}], "hard": True}})
    _, msgs = history(o, g)
    still = any(x["seq"] == sm for x in msgs)
    check("G12", "member can delete-for-everyone their OWN group message", code_of(r) == 200 and not still,
          f"del hard -> {code_of(r)}; still visible to others: {still}")
    r = pub(o, g, "owner's message")
    so = seq_of(r)
    r = m.conn.call({"del": {"topic": g, "what": "msg", "delseq": [{"low": so}], "hard": True}})
    _, msgs = history(m2, g)
    still = any(x["seq"] == so for x in msgs)
    check("G13", "member cannot delete-for-everyone someone else's message", still,
          f"del hard -> {code_of(r)}; still visible to others: {still}")
    check("G13b", "a hard-delete the member is not allowed to do is refused (403), not silently downgraded",
          code_of(r) == 403 and still, f"reply {code_of(r)}; message stays for everyone: {still}")
    # the owner (D permission) can still remove anyone's message for everyone
    r = pub(m2, g, "member2's message the owner removes")
    s_m2 = seq_of(r)
    r = o.conn.call({"del": {"topic": g, "what": "msg", "delseq": [{"low": s_m2}], "hard": True}})
    _, msgs = history(m, g)
    check("G13c", "owner can delete-for-everyone a member's message", code_of(r) == 200 and not any(x["seq"] == s_m2 for x in msgs),
          f"{code_of(r)}")
    r = m.conn.call({"pub": {"topic": g, "content": "rewrite", "head": {"replace": f":{so}"}}})
    check("G14", "member cannot edit the owner's message (head.replace)", code_of(r) is not None and code_of(r) >= 400,
          f"{code_of(r)} stored as seq {seq_of(r)}")

    # read-only member
    r = o.conn.call({"set": {"topic": g, "sub": {"user": m2.uid, "mode": "JR"}}})
    check("G15", "owner sets a member read-only (JR) -> 200", code_of(r) == 200, f"{code_of(r)}")
    time.sleep(0.3)
    r = pub(m2, g, "read-only member tries to post")
    check("G16", "read-only member cannot post", code_of(r) == 403, f"{code_of(r)} {r and r.get('text')}")
    r = m2.conn.call({"set": {"topic": g, "sub": {"mode": "JRWPS"}}})
    r2 = pub(m2, g, "after self-upgrade")
    check("G17", "read-only member cannot grant themselves W back", code_of(r2) == 403, f"set want -> {code_of(r)}, pub -> {code_of(r2)}")

    # removed member
    m.conn.inbox.clear()
    r = o.conn.call({"del": {"topic": g, "what": "sub", "user": m.uid}})
    check("G18", "owner removes a member -> 200", code_of(r) == 200, f"{code_of(r)}")
    ev = m.conn.wait(lambda f: ("pres" in f and f["pres"].get("topic") in (g, "me")) or ("ctrl" in f and f["ctrl"].get("topic") == g), 3)
    info("G18b", "removed member is told", json.dumps(ev)[:180] if ev else "nothing")
    r = pub(m, g, "removed member posting")
    check("G19", "removed member cannot post", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)} {r and r.get('text')}")
    r = m.conn.call({"get": {"topic": g, "what": "data"}})
    check("G20", "removed member cannot fetch history", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)}")
    m.conn.inbox.clear()
    r = m.conn.call({"sub": {"topic": g, "get": {"what": "data", "data": {"limit": 50}}}})
    m.conn.drain(0.8)
    leaked = [f for f in m.conn.inbox if "data" in f and f["data"].get("topic") == g]
    check("G21", "removed member cannot simply re-join", code_of(r) not in (200, 201) and not leaked,
          f"re-sub -> {code_of(r)}; {len(leaked)} message(s) readable incl. ones sent after removal")
    if code_of(r) in (200, 201):
        r = pub(m, g, "I'm back without an invite")
        info("G21b", "re-joined removed member posting", f"{code_of(r)}")
        m.conn.call({"leave": {"topic": g, "unsub": True}})
    # ...but the owner can invite them back, and then they join and post as before
    r = o.conn.call({"set": {"topic": g, "sub": {"user": m.uid}}})
    r2 = sub(m, g)
    r3 = pub(m, g, "back after a fresh invite")
    check("G21c", "owner re-invites the removed member: they join (200) and post (202)",
          code_of(r) == 200 and code_of(r2) in (200, 201) and code_of(r3) == 202,
          f"invite {code_of(r)}, sub {code_of(r2)}, pub {code_of(r3)}")
    m.conn.call({"leave": {"topic": g, "unsub": True}})
    # a member who leaves on their own needs a new invite too
    r = sub(m, g)
    check("G21d", "member who left voluntarily cannot re-join without an invite", code_of(r) == 403, f"{code_of(r)}")

    # owner transfer
    r = o.conn.call({"set": {"topic": g, "sub": {"user": m2.uid, "mode": "JRWPASDO"}}})
    check("G22", "owner offers ownership -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    time.sleep(0.3)
    r = m2.conn.call({"set": {"topic": g, "sub": {"mode": "JRWPASDO"}}})
    check("G22b", "new owner accepts (sets own want incl. O) -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    time.sleep(0.5)
    ctrl, metas, _ = o.conn.get(g, "sub")
    modes = {s.get("user"): (s.get("acs") or {}).get("mode") for mm in metas for s in (mm.get("sub") or [])}
    check("G23", "after transfer: new owner has O, old owner does not",
          "O" in (modes.get(m2.uid) or "") and "O" not in (modes.get(o.uid) or "O"), f"{modes}")
    r = m2.conn.call({"set": {"topic": g, "desc": {"public": {"fn": "renamed by new owner"}}}})
    check("G24", "new owner can rename", code_of(r) == 200, f"{code_of(r)}")

    # leave
    r = o.conn.call({"leave": {"topic": g, "unsub": True}})
    check("G25", "ex-owner leaves (unsub) -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    r = o.conn.call({"get": {"topic": g, "what": "data"}})
    check("G26", "after leaving, history not readable", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)}")
    # owner cannot leave without transfer?
    r = m2.conn.call({"leave": {"topic": g, "unsub": True}})
    check("G27", "sole owner cannot just leave (must delete or transfer)", code_of(r) is not None and code_of(r) >= 400,
          f"{code_of(r)} {r and r.get('text')}")

    # delete topic: by non-owner
    r = o.conn.call({"sub": {"topic": g}})  # may or may not work; then try deleting
    r = x.conn.call({"del": {"topic": g, "what": "topic", "hard": True}})
    info("G28", "non-member/non-owner deletes topic", f"{code_of(r)} {r and r.get('text')}")
    r = m2.conn.call({"del": {"topic": g, "what": "topic", "hard": True}})
    check("G29", "owner deletes group -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    r = x.conn.call({"sub": {"topic": g}})
    check("G30", "deleted group cannot be subscribed (404)", code_of(r) == 404, f"{code_of(r)}")
    # max subscriber/invite edge: invite a non-existent user
    r2 = o.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS g2"}}}}})
    g2 = (r2 or {}).get("topic")
    r = o.conn.call({"set": {"topic": g2, "sub": {"user": "usrAAAAAAAAAAA"}}})
    check("G31", "inviting a non-existent user -> 4xx", code_of(r) is not None and 400 <= code_of(r) < 500, f"{code_of(r)} {r and r.get('text')}")
    o.conn.call({"del": {"topic": g2, "what": "topic", "hard": True}})

    # admins (not just the owner) can still add people; the invitee joins and posts
    adm = make_user("QS Admin")
    newbie = make_user("QS Newbie")
    r = o.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS g3"}}}}})
    g3 = (r or {}).get("topic")
    o.conn.call({"set": {"topic": g3, "sub": {"user": adm.uid, "mode": "JRWPAS"}}})
    sub(adm, g3)
    r = adm.conn.call({"set": {"topic": g3, "sub": {"user": newbie.uid}}})
    r2 = sub(newbie, g3)
    r3 = pub(newbie, g3, "hello from the newbie")
    check("G32", "admin invites a user, who then joins and posts", code_of(r) == 200 and code_of(r2) in (200, 201)
          and code_of(r3) == 202, f"invite {code_of(r)}, sub {code_of(r2)}, pub {code_of(r3)}")
    o.conn.call({"del": {"topic": g3, "what": "topic", "hard": True}})


def my_want(u, topic):
    ctrl, metas, _ = u.conn.get(topic, "desc")
    for m in metas:
        acs = (m.get("desc") or {}).get("acs") or {}
        if acs.get("want"):
            return acs["want"]
    return "JRWPA"


def update_mode(u, topic, delta):
    """What the apps' topic.updateMode(null, delta) sends: the SDK applies the
    delta to the current 'want' and sends the absolute result."""
    want = my_want(u, topic)
    sign = None
    out = list(want if want != "N" else "")
    for ch in delta:
        if ch in "+-":
            sign = ch
        elif sign == "+" and ch not in out:
            out.append(ch)
        elif sign == "-" and ch in out:
            out.remove(ch)
    order = "JRWPASDO"
    mode = "".join(sorted(out, key=order.index)) or "N"
    return u.conn.call({"set": {"topic": topic, "sub": {"mode": mode}}}), mode


def s_blocking():
    a = make_user("QS Blocker")
    b = make_user("QS Blocked")
    befriend(a, b)
    pub(a, b.uid, "hi")
    r = pub(b, a.uid, "before block")
    check("B1", "B can post to A before the block", code_of(r) == 202, f"{code_of(r)}")
    # the apps: topic.updateMode(null, "-JP")
    b.conn.inbox.clear()
    r, mode = update_mode(a, b.uid, "-JP")
    check("B2", "A blocks B (want -JP, as the apps do) -> 200", code_of(r) == 200, f"want={mode} -> {code_of(r)} {r and r.get('text')}")
    time.sleep(0.5)
    r = pub(b, a.uid, "after block")
    check("B3", "blocked B cannot post to A", code_of(r) == 403, f"{code_of(r)} {r and r.get('text')}")
    ev = b.conn.wait(lambda f: "pres" in f or ("meta" in f), 1.5)
    info("B4", "what B is told about the block", json.dumps(ev)[:180] if ev else "nothing")
    # B tries to fix it from their side
    r = b.conn.call({"set": {"topic": a.uid, "sub": {"mode": "JRWPS"}}})
    r2 = pub(b, a.uid, "after self-repair")
    check("B5", "B cannot undo the block from their side", code_of(r2) == 403, f"set -> {code_of(r)}, pub -> {code_of(r2)}")
    # B leaves and re-subscribes
    b.conn.call({"leave": {"topic": a.uid, "unsub": True}})
    r = b.conn.call({"sub": {"topic": a.uid}})
    r2 = pub(b, a.uid, "after unsub+resub")
    check("B6", "B cannot escape the block by unsubscribing and re-subscribing", code_of(r2) == 403,
          f"resub -> {code_of(r)}, pub -> {code_of(r2)}")
    # B can still find A
    subs, _ = find(b.conn, f"basic:{a.login}")
    info("B7", "blocked user can still find the blocker in search", f"{len(subs)} result(s)")
    # B adds A to a group: block is p2p-only
    r = b.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS block-bypass"}}}}})
    gb = (r or {}).get("topic")
    r = b.conn.call({"set": {"topic": gb, "sub": {"user": a.uid}}})
    info("B8", "blocked user can still add the blocker to a group", f"{code_of(r)}")
    b.conn.call({"del": {"topic": gb, "what": "topic", "hard": True}})
    # does A still receive anything? A's own posting
    r = pub(a, b.uid, "A can still write to B?")
    info("B9", "blocker can still message the blocked user", f"{code_of(r)}")
    # A opens the chat the way the apps do: plain {sub}, no mode. Must not undo the block.
    a.conn.inbox.clear()
    r = a.conn.call({"sub": {"topic": b.uid, "get": {"what": "desc sub data del", "data": {"limit": 50}}}})
    a.conn.drain(0.8)
    seen = [f["data"].get("content") for f in a.conn.inbox if "data" in f and f["data"].get("topic") == b.uid]
    check("B11", "blocker can open the blocked chat (plain sub -> 200) and read the history",
          code_of(r) == 200 and "before block" in seen, f"{code_of(r)} {r and r.get('text')}; {len(seen)} message(s)")
    check("B11b", "...and nothing B sent while blocked was stored", not any(str(c).startswith("after") for c in seen),
          f"{[c for c in seen if str(c).startswith('after')]}")
    r = pub(b, a.uid, "after A opened the chat")
    check("B12", "opening the chat does not unblock: B's pub still 403", code_of(r) == 403, f"{code_of(r)} {r and r.get('text')}")
    want = my_want(a, b.uid)
    check("B12b", "A's want still lacks J after the plain sub", "J" not in want, f"want={want}")
    a.conn.inbox.clear()
    b.conn.send({"note": {"topic": a.uid, "what": "kp"}})
    b.conn.send({"note": {"topic": a.uid, "what": "read", "seq": 1}})
    f = a.conn.wait(lambda f: "info" in f and f["info"].get("from") == b.uid, 1.5)
    check("B13", "B's typing/read notes are not delivered to A while blocked", f is None, json.dumps(f)[:150] if f else "none")
    r = pub(a, b.uid, "A writes while blocking")
    check("B14", "blocker cannot post either until they unblock (403)", code_of(r) == 403, f"{code_of(r)} {r and r.get('text')}")
    # what would work: the blocker lowers the PEER's given mode (no W)
    c2 = make_user("QS Blocker2")
    d2 = make_user("QS Blocked2")
    befriend(c2, d2)
    pub(c2, d2.uid, "hi")
    r = c2.conn.call({"set": {"topic": d2.uid, "sub": {"user": d2.uid, "mode": "JRP"}}})
    r2 = pub(d2, c2.uid, "after given change")
    check("B3b", "server does enforce a p2p ban when the peer's given mode drops W (set sub user=peer mode=JRP)",
          code_of(r) == 200 and code_of(r2) == 403, f"set -> {code_of(r)}, pub -> {code_of(r2)}")
    r = c2.conn.call({"set": {"topic": d2.uid, "sub": {"user": d2.uid, "mode": "N"}}})
    d2.conn.call({"leave": {"topic": c2.uid}})
    r2 = d2.conn.call({"sub": {"topic": c2.uid}})
    check("B3c", "given mode N: the peer cannot even re-subscribe (403)", code_of(r) == 200 and code_of(r2) == 403,
          f"set -> {code_of(r)}, resub -> {code_of(r2)}")
    # unblock
    r, mode = update_mode(a, b.uid, "+JP")
    time.sleep(0.5)
    b.conn.call({"sub": {"topic": a.uid}})
    r2 = pub(b, a.uid, "after unblock")
    check("B10", "after unblock (+JP) B can post again", code_of(r2) == 202, f"set -> {code_of(r)}, pub -> {code_of(r2)}")
    a.conn.call({"sub": {"topic": b.uid}})
    b.conn.inbox.clear()
    r3 = pub(a, b.uid, "A after unblock")
    fb = b.conn.wait(is_data(a.uid, seq_of(r3)), 3)
    a.conn.inbox.clear()
    b.conn.send({"note": {"topic": a.uid, "what": "kp"}})
    fa = a.conn.wait(is_info(b.uid, "kp", b.uid), 3)
    check("B15", "after unblock messages and typing flow both ways", code_of(r3) == 202 and bool(fb) and bool(fa),
          f"A pub {code_of(r3)}, B got it {bool(fb)}, A got B's kp {bool(fa)}")
    return a, b


def s_fnd():
    t = make_user("Zebedee Quokka" + RUN, phone=True)
    s = make_user("QS Searcher", lang="en-AU")
    subs, ctrl = find(s.conn, "Zebedee")
    info("F1", "search by display name word", f"{len(subs)} result(s) (Tinode matches tags, not names)")
    subs, ctrl = find(s.conn, t.login)
    check("F2", "search by login (bare)", any(fuid(x) == t.uid for x in subs), f"{len(subs)} result(s)")
    subs, ctrl = find(s.conn, f"basic:{t.login}")
    check("F3", "search by login tag basic:<login>", any(fuid(x) == t.uid for x in subs), f"{len(subs)}")
    subs, ctrl = find(s.conn, t.phone)
    check("F4", "search by phone E.164", any(fuid(x) == t.uid for x in subs), f"{len(subs)}")
    hit = next((x for x in subs if fuid(x) == t.uid), {})
    keys = sorted(hit.keys())
    leak = [k for k in keys if k in ("trusted_private", "cred", "tags", "acs_given")]
    info("F5", "fields in a search result", f"{keys} private={hit.get('private')}")
    subs2, _ = find(s.conn, f"basic:{t.login}")
    hit2 = next((x for x in subs2 if fuid(x) == t.uid), {})
    blob = json.dumps(hit2)
    check("F6", "login search does not reveal the user's phone number", t.phone not in blob, blob[:200])
    local = "0" + t.phone[3:]
    subs, _ = find(s.conn, local)
    check("F7", "search by local-format phone (hi.lang en-AU)", any(fuid(x) == t.uid for x in subs), f"{local} -> {len(subs)}")
    spaced = "+61 " + t.phone[3:6] + " " + t.phone[6:9] + " " + t.phone[9:]
    subs, _ = find(s.conn, spaced.replace(" ", "_"))
    info("F8", "search by '+61_491_570_1xx' (spaces as underscores)", f"{len(subs)} result(s)")
    local_spaced = f"(0{t.phone[3:6]}) {t.phone[6:9]} {t.phone[9:]}"
    for cid, q in (("F8b", spaced), ("F8c", f'"{spaced}"'), ("F8d", spaced.replace(" ", "-")),
                   ("F8e", f'"tel:{spaced}"'), ("F8f", local_spaced), ("F8g", f"tel:0{t.phone[3:]}")):
        subs, _ = find(s.conn, q)
        check(cid, f"phone search tolerant of formatting: {q!r}", any(fuid(x) == t.uid for x in subs), f"{len(subs)} result(s)")
    s_us = make_user("QS Searcher US", lang="en-US")
    subs, _ = find(s_us.conn, local)
    info("F9", "local-format phone search from a client with hi.lang en-US", f"{len(subs)} result(s)")
    # prefix / partial enumeration
    subs, _ = find(s.conn, t.phone[:-1])
    check("F10", "partial phone number does not match (no prefix enumeration)", not any(fuid(x) == t.uid for x in subs),
          f"{len(subs)}")
    subs, _ = find(s.conn, "tel:")
    check("F11", "bare 'tel:' does not list everyone", len(subs) == 0, f"{len(subs)}")
    # bulk enumeration: many OR terms in one query
    q = ",".join(PHONE_POOL[:50])
    subs, ctrl = find(s.conn, q)
    info("F12", "one query with 50 OR'ed numbers", f"{len(subs)} account(s) returned, ctrl={code_of(ctrl)}")
    # private fields of the found user
    r = s.conn.call({"sub": {"topic": t.uid, "get": {"what": "desc"}}})
    ctrl, metas, _ = s.conn.get(t.uid, "desc")
    d = metas[0].get("desc") if metas else {}
    check("F13", "a stranger's p2p desc has no private field of the other user", "tel" not in json.dumps(d) or t.phone not in json.dumps(d),
          json.dumps(d)[:200])
    # blocked user searching
    a, b = s_blocking_for_fnd()
    subs, _ = find(b.conn, f"basic:{a.login}")
    info("F14", "search for someone who blocked you", f"{len(subs)} result(s)")
    # self in results?
    subs, _ = find(t.conn, t.phone)
    info("F15", "searching your own number", f"{len(subs)} result(s)")
    # fnd pub is rejected
    r = s.conn.call({"pub": {"topic": "fnd", "content": "x"}})
    check("F16", "publishing to fnd is rejected", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)}")
    # query-length / many tags
    r = s.conn.call({"set": {"topic": "fnd", "desc": {"public": "a" * 5000}}})
    ctrl, metas, _ = s.conn.get("fnd", "sub")
    info("F17", "5000-char query", f"set -> {code_of(r)}, get -> {code_of(ctrl)} metas={len(metas)}")


def s_blocking_for_fnd():
    a = make_user("QS FBlocker")
    b = make_user("QS FBlocked")
    befriend(a, b)
    update_mode(a, b.uid, "-JP")
    return a, b


def psql(sql):
    try:
        out = subprocess.run(["docker", "compose", "-p", "blml-qa", "exec", "-T", "db", "psql", "-U", "postgres",
                              "-d", "tinode", "-At", "-c", sql], cwd=COMPOSE_DIR, capture_output=True, text=True, timeout=30)
        return out.stdout.strip()
    except Exception as e:
        return f"(psql failed: {e})"


def s_report():
    rep = make_user("QS Reporter")
    bad = make_user("QS Abuser")
    befriend(rep, bad)
    pub(bad, rep.uid, "abusive message")
    before = psql("select count(*) from messages where topic='sys'")
    # iOS / Android frames
    content = {"ent": [{"tp": "EX", "data": {"mime": "application/json",
                                               "val": {"action": "report", "target": bad.uid}}}],
               "fmt": [{"at": -1, "len": 0, "key": 0}]}
    r = rep.conn.call({"pub": {"topic": "sys", "head": {"mime": "text/x-drafty"}, "content": content}})
    check("R1", "report (pub to sys, as iOS/Android send it) accepted", code_of(r) == 202, f"{code_of(r)} {r and r.get('text')}")
    # webapp frame: same, via tinode.report()
    r2 = rep.conn.call({"pub": {"topic": "sys", "content": content}})
    check("R2", "report as the webapp sends it accepted", code_of(r2) == 202, f"{code_of(r2)}")
    time.sleep(1)
    after = psql("select count(*) from messages where topic='sys'")
    row = psql(f"select seqid, encode(convert_to(content::text,'UTF8'),'escape') from messages where topic='sys' order by seqid desc limit 1")
    try:
        landed = int(after) - int(before)
    except ValueError:
        landed = -1
    check("R3", "reports stored in the sys topic in the DB", landed == 2, f"before={before} after={after} last={row[:160]}")
    check("R3b", "stored report names the reported user", bad.uid in row, "")
    # block side of the flow
    r, _ = update_mode(rep, bad.uid, "-JP")
    r2 = pub(bad, rep.uid, "after report")
    check("R4", "report flow's block stops the reported user posting", code_of(r2) == 403, f"{code_of(r)} / {code_of(r2)}")
    # unauthenticated report
    c = Conn()
    r = c.call({"pub": {"topic": "sys", "content": "anon report"}})
    check("R5", "unauthenticated pub to sys refused", code_of(r) == 401, f"{code_of(r)}")
    # non-root cannot read sys
    r = rep.conn.call({"sub": {"topic": "sys"}})
    check("R6", "non-root cannot subscribe to / read sys", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)} {r and r.get('text')}")
    roots = psql("select count(*) from auth where authlvl=30")
    info("R7", "root accounts able to read sys", f"{roots}")
    # report a group (target grp)
    content["ent"][0]["data"]["val"]["target"] = "grpNONEXISTENT"
    r = rep.conn.call({"pub": {"topic": "sys", "content": content}})
    info("R8", "report naming a non-existent topic", f"{code_of(r)} (server does not validate targets)")
    # is there an operator view of reports?
    admin = (ROOT / "deploy" / "admin")
    hits = []
    for p in admin.rglob("*"):
        if p.is_file() and p.suffix in (".py", ".js", ".go", ".html", ".ts", ".sql"):
            try:
                txt = p.read_text(errors="ignore")
            except Exception:
                continue
            if "'sys'" in txt or '"sys"' in txt or "report" in txt.lower():
                hits.append(str(p.relative_to(ROOT)))
    info("R9", "operator dashboard code mentioning sys/report", ", ".join(hits) or "none")


def s_uploads():
    u = make_user("QS Uploader")
    data = b"\x89PNG\r\n\x1a\n" + os.urandom(2048)
    body, ctype = multipart({}, "x.png", data, "image/png")
    st, hd, resp = http("POST", "/v0/file/u/", {"X-Tinode-APIKey": API_KEY, "Content-Type": ctype}, body)
    check("U1", "upload without auth refused", st in (401, 403), f"{st} {resp[:120]!r}")
    st, hd, resp = http("POST", "/v0/file/u/", {"Content-Type": ctype}, body)
    check("U2", "upload without API key refused", st in (400, 401, 403), f"{st}")
    body2, ctype2 = multipart({"topic": "newacc"}, "x.png", data, "image/png")
    st, hd, resp = http("POST", "/v0/file/u/", {"X-Tinode-APIKey": API_KEY, "Content-Type": ctype2}, body2)
    info("U3", "unauthenticated upload with topic=newacc (sign-up avatar path)", f"{st} {resp[:120]!r}")
    auth = {"X-Tinode-APIKey": API_KEY, "X-Tinode-Auth": "Token " + u.token}
    st, hd, resp = http("POST", "/v0/file/u/", dict(auth, **{"Content-Type": ctype}), body)
    url = None
    try:
        url = json.loads(resp)["ctrl"]["params"]["url"]
    except Exception:
        pass
    check("U4", "authenticated upload -> 200 + url", st == 200 and url, f"{st} {url}")
    if url:
        st, hd, _ = http("GET", url, {"X-Tinode-APIKey": API_KEY})
        check("U5", "download without auth refused", st in (401, 403), f"{st}")
        st, hd, got = http("GET", url, auth)
        check("U6", "download with auth -> 200, same bytes", st == 200 and got == data, f"{st} {len(got)} bytes")
        st, hd, got = http("GET", f"{url}?apikey={API_KEY}&auth=token&secret={urllib.parse.quote(u.token)}")
        info("U6b", "download with token in the query string", f"{st}")
        other = make_user("QS Stranger")
        st, hd, got = http("GET", url, {"X-Tinode-APIKey": API_KEY, "X-Tinode-Auth": "Token " + other.token})
        info("U7", "any logged-in user who has the URL can download (no per-file ACL)", f"{st}")
    # HTML / SVG content
    for name, payload, ct in (("x.html", b"<html><script>alert(1)</script></html>", "text/html"),
                              ("x.svg", b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "image/svg+xml")):
        b3, c3 = multipart({}, name, payload, ct)
        st, hd, resp = http("POST", "/v0/file/u/", dict(auth, **{"Content-Type": c3}), b3)
        try:
            url2 = json.loads(resp)["ctrl"]["params"]["url"]
        except Exception:
            url2 = None
        if url2:
            st2, hd2, _ = http("GET", url2, auth)
            disp = hd2.get("Content-Disposition", "")
            ctyp = hd2.get("Content-Type", "")
            check("U8", f"active content ({name}) is served as a download, not inline",
                  "attachment" in disp or not any(k in ctyp for k in ("html", "svg", "xml")),
                  f"Content-Type={ctyp} Content-Disposition={disp!r} nosniff={hd2.get('X-Content-Type-Options')}")
        else:
            info("U8", f"upload of {name}", f"{st}")
    # path traversal
    for path in ("/v0/file/s/../../../etc/passwd", "/v0/file/s/%2e%2e%2f%2e%2e%2fetc%2fpasswd", "/v0/file/s/nonexistent.png"):
        st, hd, got = http("GET", path, auth)
        check("U9", f"traversal/unknown path {path} -> 4xx", st is not None and 400 <= st < 500 and b"root:" not in got, f"{st}")
    # size limit: max_size from config
    limit = None
    try:
        conf = (ROOT / "deploy" / "blml.conf").read_text()
        import re
        m = re.search(r'"max_size":\s*(\d+)', conf)
        limit = int(m.group(1)) if m else None
    except Exception:
        pass
    if limit and limit <= 120 * 1024 * 1024:
        big = b"\0" * (limit + 1024 * 1024)
        b4, c4 = multipart({}, "big.bin", big)
        t0 = time.time()
        st, hd, resp = http("POST", "/v0/file/u/", dict(auth, **{"Content-Type": c4}), b4, timeout=120)
        check("U10", f"upload over media.max_size ({limit // 1048576} MB) refused with 413", st == 413,
              f"{st} {resp[:100]!r} in {time.time() - t0:.1f}s")
        del big, b4
    else:
        skip("U10", "upload over max_size", f"limit={limit}")
    # in-band size advertised
    info("U11", "server-advertised limits (hi params)", json.dumps({k: v for k, v in ((u.conn.hi or {}).get('params') or {}).items()
                                                                  if k in ('maxMessageSize', 'maxFileUploadSize', 'maxSubscriberCount', 'maxTagCount')}))


def s_robustness():
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 2))
    u = make_user("QS Robust")
    sub(u, "me")
    # malformed JSON
    c = Conn()
    c.send("{not json")
    f = c.wait(lambda f: "ctrl" in f, 3)
    check("X1", "malformed JSON -> 400 ctrl, connection kept", code_of((f or {}).get("ctrl")) == 400 and not c.closed,
          json.dumps(f)[:120] if f else "no reply")
    c.send('{"foo":{"id":"x1"}}')
    f = c.wait(lambda f: "ctrl" in f, 3)
    check("X2", "unknown message type -> 400", code_of((f or {}).get("ctrl")) == 400, json.dumps(f)[:120] if f else "no reply")
    c.send('[]')
    f = c.wait(lambda f: "ctrl" in f, 3)
    check("X3", "JSON array frame -> 400", code_of((f or {}).get("ctrl")) == 400, json.dumps(f)[:120] if f else "no reply")
    c.send('{"pub":{"id":"x2","topic":"me","content":"x"},"sub":{"id":"x3","topic":"me"}}')
    f = c.wait(lambda f: "ctrl" in f, 3)
    info("X4", "two message types in one frame (one is silently picked)", json.dumps(f)[:120] if f else "no reply")
    c.ws.send_binary(b"\x00\x01\x02binary")
    f = c.wait(lambda f: "ctrl" in f, 2)
    info("X5", "binary frame", json.dumps(f)[:120] if f else f"no reply, closed={c.closed}")
    c.close()
    # before hi / before login
    c = Conn(hi=False)
    r = c.call({"pub": {"topic": "me", "content": "x"}})
    check("X6", "pub before hi/login -> error, not served", code_of(r) is not None and code_of(r) >= 400, f"{code_of(r)} {r and r.get('text')}")
    c.close()
    c = Conn()
    r = c.call({"sub": {"topic": "me"}})
    check("X7", "sub before login -> 401", code_of(r) == 401, f"{code_of(r)}")
    c.close()
    # deep nesting
    c = Conn()
    c.send('{"pub":{"id":"d","topic":"me","content":' + "[" * 20000 + "]" * 20000 + "}}")
    f = c.wait(lambda f: "ctrl" in f, 4)
    info("X8", "20000-deep nested JSON", json.dumps(f)[:100] if f else f"no reply, closed={c.closed}")
    c.close()
    # long topic names
    for n in (100, 5000, 60000):
        r = u.conn.call({"sub": {"topic": "grp" + "A" * n}})
        check("X9", f"sub to a {n}-char topic name -> 4xx", code_of(r) is not None and 400 <= code_of(r) < 500,
              f"{code_of(r)} {r and r.get('text')}")
    r = u.conn.call({"sub": {"topic": "usr" + "Z" * 40}})
    check("X10", "sub to a malformed usr id -> 4xx", code_of(r) is not None and 400 <= code_of(r) < 500, f"{code_of(r)}")
    r = u.conn.call({"sub": {"topic": "usr"}})
    check("X11", "sub to bare 'usr' -> 4xx", code_of(r) is not None and 400 <= code_of(r) < 500, f"{code_of(r)}")
    r = u.conn.call({"sub": {"topic": ""}})
    check("X12", "sub with empty topic -> 4xx", code_of(r) is not None and 400 <= code_of(r) < 500, f"{code_of(r)}")
    # NUL and odd unicode in content
    peer = make_user("QS Robust Peer")
    befriend(u, peer)
    r = pub(u, peer.uid, "nul\u0000byte")
    check("X13", "message containing U+0000 -> accepted or 400, never 5xx", code_of(r) is not None and code_of(r) < 500,
          f"{code_of(r)} {r and r.get('text')}")
    r = u.conn.call({"set": {"topic": "me", "desc": {"public": {"fn": "nul\u0000name"}}}})
    check("X14", "display name containing U+0000 -> never 5xx", code_of(r) is not None and code_of(r) < 500,
          f"{code_of(r)} {r and r.get('text')}")
    r = pub(u, peer.uid, "\ud83d\ude00 emoji \u202e rtl \ufeff bom")
    check("X15", "emoji / RTL override / BOM text accepted", code_of(r) == 202, f"{code_of(r)}")
    r = pub(u, peer.uid, {"weird": [1, 2, {"x": None}]})
    info("X16", "non-Drafty JSON object as content", f"{code_of(r)}")
    r = pub(u, peer.uid, None)
    check("X17", "pub with null content -> 400", code_of(r) == 400, f"{code_of(r)}")
    # oversized head
    r = pub(u, peer.uid, "big head", head={"x-junk": "j" * 70000})
    info("X18", "70 KB head", f"{code_of(r)} {r and r.get('text')}")
    # huge message beyond max_message_size
    c2 = Conn()
    c2.call({"login": {"scheme": "token", "secret": u.token}})
    c2.call({"sub": {"topic": peer.uid}})
    c2.send({"pub": {"id": "huge", "topic": peer.uid, "content": "H" * (140 * 1024)}})
    f = c2.wait(lambda f: "ctrl" in f and f["ctrl"].get("id") == "huge", 3)
    try:
        still = c2.call({"get": {"topic": "me", "what": "desc"}}, timeout=3) is not None
    except Exception:
        still = False
    info("X19", "pub of 140 KB (> max_message_size 128 KB)",
         f"reply={json.dumps(f)[:100] if f else None}; connection still usable: {still}")
    check("X19b", "oversized message is not stored", not any(len(json.dumps(m.get("content"))) > 130000
                                                          for m in history(peer, u.uid)[1]), "")
    r = pub(u, peer.uid, "M" * (120 * 1024))
    info("X20", "pub of 120 KB (just under the limit)", f"{code_of(r)}")
    c2.close()
    # just-over-limit whole frame of junk
    c3 = Conn()
    try:
        c3.send("x" * (2 * 1024 * 1024))
        f = c3.wait(lambda f: True, 3)
        info("X21", "2 MB junk frame", f"reply={json.dumps(f)[:80] if f else None} closed={c3.closed}")
    except Exception as e:
        info("X21", "2 MB junk frame", f"send raised {type(e).__name__} (connection dropped by server)")
    c3.close()
    # hammering: many requests on one connection
    c4 = Conn()
    c4.call({"login": {"scheme": "token", "secret": u.token}})
    for i in range(150):
        c4.send({"get": {"id": f"h{i}", "topic": "me", "what": "desc"}})
    got = 0
    end = time.time() + 10
    while time.time() < end and got < 150:
        f = c4._recv(end - time.time())
        if f is None:
            break
        if ("meta" in f and str(f["meta"].get("id", "")).startswith("h")) or ("ctrl" in f and str(f["ctrl"].get("id", "")).startswith("h")):
            got += 1
    info("X22", "150 pipelined {get} on one session", f"{got}/150 answered, closed={c4.closed}")
    c4.close()
    # rapid connect/disconnect
    fails = 0
    t0 = time.time()
    for i in range(100):
        try:
            cc = Conn(timeout=4)
            if i % 2:
                cc.call({"login": {"scheme": "token", "secret": u.token}})
            cc.close()
        except Exception:
            fails += 1
    check("X23", "100 rapid connect/hi/disconnect cycles", fails == 0, f"{fails} failed in {time.time() - t0:.1f}s")
    # abrupt TCP drop mid-frame
    try:
        s = socket.create_connection(HOST.split(":")[0] == "localhost" and ("127.0.0.1", int(HOST.split(":")[1])) or HOST, timeout=3)
        s.send(b"GET /v0/channels?apikey=" + API_KEY.encode() + b" HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n"
               b"Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n")
        s.recv(1024)
        s.send(b"\x81\xfe\xff\xff")  # header claiming a 65535-byte masked frame, then hang up
        s.close()
    except Exception:
        pass
    # many messages
    a = make_user("QS Load A")
    b = make_user("QS Load B")
    befriend(a, b)
    t0 = time.time()
    for i in range(200):
        a.conn.send({"pub": {"id": f"L{i}", "topic": b.uid, "content": f"load {i}", "noecho": True}})
    codes = {}
    end = time.time() + 20
    while sum(codes.values()) < 200 and time.time() < end:
        f = a.conn._recv(end - time.time())
        if f and "ctrl" in f and str(f["ctrl"].get("id", "")).startswith("L"):
            codes[code_of(f["ctrl"])] = codes.get(code_of(f["ctrl"]), 0) + 1
    check("X24", "200-message burst: every message gets a reply (202 or an explicit error)",
          sum(codes.values()) == 200, f"replies by code {codes} in {time.time() - t0:.1f}s")
    info("X24b", "200-message burst: how many were accepted", f"{codes.get(202, 0)}/200 accepted; 503 = server queue full")
    alive = server_alive()
    check("X25", "server alive after robustness section", alive, "")
    logs = server_log_since(since)
    panics = [l for l in logs.splitlines() if "panic" in l.lower() or "fatal error" in l.lower()]
    check("X26", "no panic in server logs during the run", not panics, "; ".join(panics[:3])[:200])
    errs = [l for l in logs.splitlines() if " E20" in l or l.startswith("E20") or "| E20" in l]
    info("X27", "server error-level log lines during robustness", f"{len(errs)}: " + " | ".join(e[-140:] for e in errs[:4]))


def s_misc():
    u = make_user("QS Misc")
    params = (u.conn.hi or {}).get("params") or {}
    ice = params.get("iceServers") or []
    has_cred = any("credential" in s for s in ice)
    c = Conn()
    pre = (c.hi or {}).get("params") or {}
    check("M1", "TURN credentials are not handed to unauthenticated clients",
          not any("credential" in s for s in (pre.get("iceServers") or [])),
          f"hi (before login) carries iceServers with credential: {any('credential' in s for s in (pre.get('iceServers') or []))}")
    info("M2", "hi params", ", ".join(sorted(k for k in pre.keys())))
    # aux, trusted
    r = u.conn.call({"set": {"topic": "me", "desc": {"trusted": {"verified": True}}}})
    check("M3", "user cannot set their own 'trusted' (verified badge)", code_of(r) is not None and code_of(r) >= 400,
          f"{code_of(r)} {r and r.get('text')}")
    # account state change by self
    r = u.conn.call({"acc": {"user": u.uid, "state": "ok"}})
    info("M4", "non-root acc state change", f"{code_of(r)} {r and r.get('text')}")
    # deleting another user
    v = make_user("QS Victim")
    r = u.conn.call({"del": {"what": "user", "user": v.uid, "hard": True}})
    check("M5", "non-root cannot delete another account", code_of(r) in (401, 403), f"{code_of(r)}")
    # sys topic flood size
    big = {"ent": [{"tp": "EX", "data": {"mime": "application/json", "val": {"action": "report", "target": "x" * 100000}}}]}
    r = u.conn.call({"pub": {"topic": "sys", "content": big}})
    info("M6", "100 KB report to sys", f"{code_of(r)}")
    # urlpreview SSRF quick check (exists in this fork)
    st, hd, body = http("GET", f"/v0/urlpreview?apikey={API_KEY}&url=http://127.0.0.1:6060/")
    info("M7", "urlpreview to loopback", f"{st}")
    st, hd, body = http("GET", f"/v0/urlpreview?apikey={API_KEY}&url=http://169.254.169.254/latest/meta-data/")
    info("M8", "urlpreview to cloud metadata IP", f"{st}")
    st, hd, body = http("GET", f"/v0/urlpreview?apikey={API_KEY}&url=http://db:5432/")
    info("M9", "urlpreview to an internal docker hostname (db:5432)", f"{st} {body[:80]!r}")


def s_logs():
    """Secrets must not reach the server log. Uses a throwaway account's generated password;
    nothing secret is printed, only whether it was found."""
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 2))
    u = make_user("QS Logcheck")  # acc frame: secret + code: tag
    c, r = login_conn(u.login, u.password)  # login frame
    c.close()
    c2 = Conn()
    c2.call({"login": {"scheme": "token", "secret": u.token}})  # token as a login secret
    c2.close()
    newpw = secrets.token_urlsafe(12)
    u.conn.call({"acc": {"user": u.uid, "scheme": "basic", "secret": b64(f":{newpw}")}})  # password change
    old_pw, u.password = u.password, newpw
    marker = "qs-log-marker-" + secrets.token_hex(8)
    peer = make_user("QS Logpeer")
    befriend(u, peer)
    r = pub(u, peer.uid, marker, head={"mime": "text/plain"})
    time.sleep(1.5)
    logs = server_log_since(since)
    if logs.startswith("(could not read logs"):
        check("L0", "server log readable", False, logs[:120])
        return
    secret_b64 = b64(f"{u.login}:{old_pw}")
    found = {
        "password": old_pw in logs or newpw in logs,
        "base64 login:password": secret_b64 in logs or b64(f":{newpw}") in logs,
        "token": bool(u.token) and u.token in logs,
        "invite code": CODE in logs,
        "message text": marker in logs,
    }
    for i, (what, hit) in enumerate(found.items(), 1):
        check(f"L{i}", f"{what} absent from `docker compose -p blml-qa logs blml`", not hit,
              "found" if hit else "not found")
    in_lines = [l for l in logs.splitlines() if " in: '" in l]
    useful = any('"login"' in l for l in in_lines) and any('"pub"' in l and peer.uid in l for l in in_lines)
    check("L6", "frames are still logged with type, id and topic (redacted, not dropped)", useful,
          f"{len(in_lines)} 'in:' line(s) since {since}")


# ───────────────────── 1:1 chat requests (contract-friend-requests.md) ─────────────────────

def what_of(ctrl):
    return ((ctrl or {}).get("params") or {}).get("what")


def pending_incoming(acs):
    w, g = acs.get("want") or "", acs.get("given") or ""
    return "J" in w and "R" not in w and "W" not in w and "J" in g


def pending_outgoing(acs):
    w, g = acs.get("want") or "", acs.get("given") or ""
    return "W" in w and "W" not in g and "J" in g


def shipped_invitation(acs):
    """The test the App Store / Play / web builds use to show Accept/Ignore/Block."""
    w, g = acs.get("want") or "", acs.get("given") or ""
    excessive = "".join(ch for ch in "JRWPASDO" if ch in g and ch not in w)
    return "J" in g and "RW" in excessive


def pres_about(u, uid, seconds=1.5):
    """pres frames about uid that reached u's main session within `seconds`; clears the inbox."""
    u.conn.drain(seconds)
    got = [f["pres"] for f in u.conn.inbox if "pres" in f
           and (f["pres"].get("src") == uid or f["pres"].get("topic") == uid)]
    u.conn.inbox.clear()
    return got


def my_sub_in_list(u, topic):
    ctrl, metas, _ = u.conn.get("me", "sub")
    return [x for m in metas for x in (m.get("sub") or []) if x.get("topic") == topic and not x.get("deleted")]


def s_requests():
    a = make_user("QS Requester")
    b = make_user("QS Recipient")
    b.conn.inbox.clear()
    r = sub(a, b.uid)
    acs = acs_of(r)
    check("Q1", "request: A subscribes to B -> 200, A given JRA (no W/P), A want has W",
          code_of(r) == 200 and acs.get("given") == "JRA" and "W" in (acs.get("want") or ""), f"{code_of(r)} acs={acs}")
    check("Q1b", "requester's state is 'pending outgoing'", pending_outgoing(acs), str(acs))
    f = b.conn.wait(is_pres("me", "acs", a.uid), 3)
    dacs = ((f or {}).get("pres") or {}).get("dacs") or {}
    check("Q2", "recipient is told on 'me': pres acs src=A, want JA, given with W",
          bool(f) and dacs.get("want") == "JA" and "W" in (dacs.get("given") or ""), json.dumps(f)[:220] if f else "nothing")
    mine = my_sub_in_list(b, a.uid)
    acs_l = (mine[0].get("acs") if mine else {}) or {}
    check("Q2b", "request is in the recipient's chat list as 'pending incoming'", pending_incoming(acs_l), json.dumps(mine)[:200])
    info("Q2c", "push to the recipient", "what=sub on creation only (unit tests TestP2PRequest*; no device tokens locally)")
    r = pub(a, b.uid, "early hello")
    check("Q3", "requester publishing before acceptance -> 403 params.what=not-accepted",
          code_of(r) == 403 and what_of(r) == "not-accepted", f"{code_of(r)} params={r and r.get('params')}")
    r = sub(b, a.uid, get="desc sub data")
    acs_b = desc_acs(b, a.uid)
    check("Q4", "recipient opens the request (plain sub) -> 200, still pending incoming",
          code_of(r) == 200 and pending_incoming(acs_b), f"{code_of(r)} acs={acs_b}")
    check("Q4b", "...which is exactly when the shipped apps show Accept / Ignore / Block", shipped_invitation(acs_b), str(acs_b))
    r = pub(b, a.uid, "recipient early")
    check("Q5", "recipient publishing before accepting -> 403 not-accepted",
          code_of(r) == 403 and what_of(r) == "not-accepted", f"{code_of(r)} {r and r.get('params')}")
    b.conn.inbox.clear()
    a.conn.send({"note": {"topic": b.uid, "what": "kp"}})
    f = b.conn.wait(lambda f: "info" in f and f["info"].get("from") == a.uid, 1.5)
    check("Q6", "requester's typing note is not delivered before acceptance", f is None, json.dumps(f)[:150] if f else "none")
    r = pub(a, b.uid, "still early")
    check("Q7", "opening the request did not accept it (A still 403)", code_of(r) == 403, f"{code_of(r)}")
    # Accept exactly as the shipped apps do: own want = given, then the peer's given.
    a.conn.inbox.clear()
    given = acs_b.get("given") or FULL_P2P
    r = b.conn.call({"set": {"topic": a.uid, "sub": {"mode": given}}})
    check("Q8", "recipient accepts ({set sub mode=<given>}, the apps' Accept) -> 200",
          code_of(r) == 200 and "W" in (acs_of(r).get("want") or ""), f"{code_of(r)} acs={acs_of(r)}")
    f = a.conn.wait(lambda f: "pres" in f and f["pres"].get("what") == "acs"
                    and "W" in (((f["pres"].get("dacs") or {}).get("given")) or ""), 3)
    check("Q9", "requester is told at once: pres acs with given +W", bool(f), json.dumps(f)[:220] if f else "nothing")
    r2 = b.conn.call({"set": {"topic": a.uid, "sub": {"user": a.uid, "mode": given}}})
    check("Q8b", "the apps' second Accept frame (peer's given) is harmless", code_of(r2) in (200, 304),
          f"{code_of(r2)} {r2 and r2.get('text')}")
    acs_a = desc_acs(a, b.uid)
    check("Q10", "requester is now 'accepted' (want and given have W)",
          "W" in (acs_a.get("want") or "") and "W" in (acs_a.get("given") or ""), str(acs_a))
    b.conn.inbox.clear()
    r = pub(a, b.uid, "hello after accept")
    f = b.conn.wait(is_data(a.uid, seq_of(r)), 3)
    check("Q11", "after acceptance A's message is delivered", code_of(r) == 202 and bool(f), f"{code_of(r)} got={bool(f)}")
    a.conn.inbox.clear()
    r = pub(b, a.uid, "hi back")
    f = a.conn.wait(is_data(b.uid, seq_of(r)), 3)
    check("Q12", "...and B's reply reaches A", code_of(r) == 202 and bool(f), f"{code_of(r)} got={bool(f)}")
    b.conn.inbox.clear()
    a.conn.send({"note": {"topic": b.uid, "what": "kp"}})
    f = b.conn.wait(is_info(a.uid, "kp", a.uid), 3)
    check("Q13", "typing notes flow after acceptance", bool(f), "")
    _, msgs = history(b, a.uid)
    early = [m.get("content") for m in msgs if "early" in str(m.get("content"))]
    check("Q14", "nothing sent before acceptance was stored", not early, f"{len(msgs)} message(s), early={early}")

    # ── decline, and no re-request spam
    c = make_user("QS Spammer")
    d = make_user("QS Decliner")
    sub(c, d.uid)
    d.conn.wait(is_pres("me", "acs", c.uid), 3)
    sub(d, c.uid)
    c.conn.inbox.clear()
    r = d.conn.call({"del": {"topic": c.uid, "what": "topic", "hard": True}})
    check("Q15", "recipient declines (del topic hard = the apps' Ignore) -> 200", code_of(r) == 200, f"{code_of(r)} {r and r.get('text')}")
    told = pres_about(c, d.uid)
    check("Q16", "requester is not told about the decline", not told, json.dumps(told)[:200])
    r = pub(c, d.uid, "please?")
    check("Q17", "after a decline the requester still gets 403 not-accepted",
          code_of(r) == 403 and what_of(r) == "not-accepted", f"{code_of(r)} {r and r.get('params')}")
    acs_c = desc_acs(c, d.uid)
    check("Q17b", "...and still sees 'pending outgoing' (decline not revealed)", pending_outgoing(acs_c), str(acs_c))
    d.conn.inbox.clear()
    c.conn.call({"leave": {"topic": d.uid}})
    r1 = sub(c, d.uid)  # reopen
    rd = c.conn.call({"del": {"topic": d.uid, "what": "topic", "hard": True}})  # delete own side
    time.sleep(5.5)  # let the idle topic unload, so the re-request goes through the store
    r2 = sub(c, d.uid)  # request again
    acs2 = acs_of(r2) or desc_acs(c, d.uid)
    told = pres_about(d, c.uid)
    check("Q18", "requester reopening, deleting and re-requesting does not notify the recipient again",
          code_of(r1) == 200 and code_of(rd) == 200 and code_of(r2) == 200 and not told,
          f"reopen {code_of(r1)}, delete {code_of(rd)}, re-request {code_of(r2)}, recipient got {json.dumps(told)[:150]}")
    check("Q18b", "the re-request is the same pending request (given has no W)", "W" not in (acs2.get("given") or "W"), str(acs2))
    r = pub(c, d.uid, "spam")
    check("Q18c", "...and still cannot post", code_of(r) == 403, f"{code_of(r)}")
    check("Q19", "declined request stays out of the recipient's chat list", not my_sub_in_list(d, c.uid), "")
    r = sub(d, c.uid)
    acs_d = acs_of(r) or desc_acs(d, c.uid)
    check("Q20", "a decliner who opens the chat later sees the request again (pending incoming)",
          code_of(r) == 200 and pending_incoming(acs_d), f"{code_of(r)} acs={acs_d}")
    r = d.conn.call({"set": {"topic": c.uid, "sub": {"mode": FULL_P2P}}})
    r2 = pub(c, d.uid, "finally")
    check("Q21", "...can accept it, and then the requester can post", code_of(r) == 200 and code_of(r2) == 202,
          f"accept {code_of(r)}, pub {code_of(r2)}")

    # ── block from the request
    e = make_user("QS Req E")
    fb = make_user("QS Req Blocker")
    sub(e, fb.uid)
    sub(fb, e.uid)
    r, mode = update_mode(fb, e.uid, "-JP")
    check("Q22", "recipient blocks the request (want -JP, the apps' Block) -> 200", code_of(r) == 200 and "J" not in mode,
          f"want={mode} -> {code_of(r)}")
    r = pub(e, fb.uid, "hello?")
    check("Q23", "blocked requester gets the same 403 not-accepted (block not revealed)",
          code_of(r) == 403 and what_of(r) == "not-accepted", f"{code_of(r)} {r and r.get('params')}")
    r, mode = update_mode(fb, e.uid, "+JP")
    r2 = pub(e, fb.uid, "hello again?")
    check("Q24", "unblock with +JP returns to the pending request (requester still 403)",
          code_of(r) == 200 and "W" not in mode and code_of(r2) == 403, f"want={mode} -> {code_of(r)}, pub {code_of(r2)}")
    r = fb.conn.call({"set": {"topic": e.uid, "sub": {"mode": FULL_P2P}}})
    r2 = pub(e, fb.uid, "hello at last")
    check("Q25", "unblock with a full mode = unblock and accept", code_of(r) == 200 and code_of(r2) == 202,
          f"{code_of(r)} pub {code_of(r2)}")

    # ── chats that existed before this server version
    gname, hname = f"QS Legacy G {RUN}", f"QS Legacy H {RUN}"
    g = make_user(gname)
    h = make_user(hname)
    sub(g, h.uid)
    g.conn.call({"leave": {"topic": h.uid}})
    time.sleep(5.5)  # idle topic unloads after 4 s, so the next {sub} reads the rows below
    topic = psql("select s.topic from subscriptions s join users u on u.id=s.userid "
                 f"where u.public->>'fn'='{hname}' and s.topic like 'p2p%' limit 1")
    upd = psql(f"update subscriptions set modewant='JRWPAD', modegiven='JRWPAD' where topic='{topic}'")
    r1 = sub(g, h.uid)
    r2 = pub(g, h.uid, "legacy hello")
    r3 = sub(h, g.uid)
    r4 = pub(h, g.uid, "legacy reply")
    check("Q26", "a chat whose subscriptions predate the policy (JRWPAD both sides) works both ways, no request",
          topic.startswith("p2p") and upd == "UPDATE 2" and [code_of(x) for x in (r1, r2, r3, r4)] == [200, 202, 200, 202],
          f"{upd!r}; sub/pub/sub/pub = {[code_of(x) for x in (r1, r2, r3, r4)]}")
    r = h.conn.call({"del": {"topic": g.uid, "what": "topic", "hard": True}})
    g.conn.call({"leave": {"topic": h.uid}})
    time.sleep(5.5)
    r2 = sub(g, h.uid)
    r3 = pub(g, h.uid, "are you there?")
    r4 = sub(h, g.uid)
    acs_h = acs_of(r4) or desc_acs(h, g.uid)
    check("Q27", "an existing friend who deleted the chat gets it back on the next message, without a request",
          code_of(r) == 200 and code_of(r3) == 202 and "W" in (acs_h.get("want") or "") and "W" in (acs_h.get("given") or ""),
          f"del {code_of(r)}, pub {code_of(r3)}, sub {code_of(r4)} acs={acs_h}")

    # ── groups and "Saved messages" are not requests
    o = make_user("QS ReqGrpOwner")
    m = make_user("QS ReqGrpMember")
    r = o.conn.call({"sub": {"topic": "new", "set": {"desc": {"public": {"fn": "QS request-free group"}}}}})
    grp = (r or {}).get("topic")
    o.conn.call({"set": {"topic": grp, "sub": {"user": m.uid}}})
    sub(m, grp)
    r = pub(m, grp, "group works")
    check("Q28", "groups unaffected: an invited member posts at once", code_of(r) == 202, f"{code_of(r)}")
    sub(o, "slf")
    r = pub(o, "slf", "note to self")
    check("Q29", "'Saved messages' (slf) unaffected", code_of(r) == 202, f"{code_of(r)} {r and r.get('text')}")
    o.conn.call({"del": {"topic": grp, "what": "topic", "hard": True}})


SECTIONS = [("accounts", s_accounts), ("tel", s_tel), ("requests", s_requests), ("p2p", s_p2p), ("groups", s_groups),
            ("blocking", s_blocking), ("fnd", s_fnd), ("report", s_report), ("uploads", s_uploads),
            ("misc", s_misc), ("logs", s_logs), ("robustness", s_robustness)]


def cleanup():
    n = 0
    for u in CREATED:
        if u.deleted:
            continue
        try:
            c = Conn()
            r = c.call({"login": {"scheme": "basic", "secret": b64(f"{u.login}:{u.password}")}})
            if code_of(r) == 200:
                r = c.call({"del": {"what": "user", "hard": True}})
                n += code_of(r) == 200
            c.close()
        except Exception:
            pass
        try:
            u.conn.close()
        except Exception:
            pass
    print(f"cleanup: hard-deleted {n} throwaway account(s)")


def write_md(path):
    lines = ["| Section | ID | Check | Result | Detail |", "|---|---|---|---|---|"]
    for sec, cid, name, st, detail in RESULTS:
        d = str(detail).replace("|", "\\|").replace("\n", " ")
        if len(d) > 220:
            d = d[:217] + "..."
        lines.append(f"| {sec} | {cid} | {name} | **{st}** | {d} |")
    Path(path).write_text("\n".join(lines) + "\n")


def main():
    only = set(filter(None, ARGS.only.split(",")))
    print(f"BLML server suite, host={HOST}, run={RUN}")
    for name, fn in SECTIONS:
        if only and name not in only:
            continue
        SECTION[0] = name
        print(f"\n== {name}")
        try:
            fn()
        except Exception as e:
            check("ERR", f"section {name} aborted", False, f"{type(e).__name__}: {e}")
            traceback.print_exc()
    if not ARGS.no_cleanup:
        cleanup()
    counts = {}
    for r in RESULTS:
        counts[r[3]] = counts.get(r[3], 0) + 1
    print("\n" + ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    if ARGS.md:
        write_md(ARGS.md)
        print(f"wrote {ARGS.md}")
    sys.exit(1 if counts.get("FAIL") else 0)


if __name__ == "__main__":
    main()
