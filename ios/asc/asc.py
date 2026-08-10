#!/usr/bin/env python3
"""Minimal App Store Connect API client.

Signs its own ES256 JWT with the .p8 rather than pulling in PyJWT, so this runs
on a stock Python. Reads credentials from ios/.testflight.env.
"""
import base64, json, os, subprocess, time, urllib.error, urllib.request

BASE = "https://api.appstoreconnect.apple.com"


def _creds():
    env = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".testflight.env")
    vals = {}
    with open(env) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                vals[k] = v
    return vals["ASC_KEY_ID"], vals["ASC_ISSUER_ID"]


def token():
    key_id, issuer = _creds()
    path = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
    now = int(time.time())
    head = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    body = b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 900,
                           "aud": "appstoreconnect-v1"}).encode())
    signing_input = head + b"." + body
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", path],
                         input=signing_input, capture_output=True, check=True).stdout
    # DER (SEQUENCE of two INTEGERs) -> the raw r||s pair JWS expects.
    i = 2 if der[1] & 0x80 == 0 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        ln = der[i + 1]
        parts.append(der[i + 2:i + 2 + ln].lstrip(b"\x00").rjust(32, b"\x00"))
        i += 2 + ln
    return (signing_input + b"." + b64(parts[0] + parts[1])).decode()


def call(method, path, payload=None):
    req = urllib.request.Request(
        BASE + path, method=method,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Authorization": "Bearer " + token(),
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        try:
            errs = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errs)
        except Exception:
            pass
        raise SystemExit(f"{method} {path} -> HTTP {e.code}\n  {detail}")
