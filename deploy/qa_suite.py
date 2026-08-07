#!/usr/bin/env python3
"""Pre-release functional pass against the live BLML stack."""
import json, base64, urllib.request, urllib.error, ssl, sys
from websocket import create_connection

WS = "ws://localhost:6060/v0/channels?apikey=AQAAAAABAAC-d-KsShjNeHzNi7myV36_"
HTTP = "http://localhost:6060"
APIKEY = "AQAAAAABAAC-d-KsShjNeHzNi7myV36_"
CODE = "BLML-738D9D"
results = []

def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(("PASS " if ok else "FAIL ") + name + (" — " + detail if detail else ""))

def conn():
    ws = create_connection(WS, timeout=6)
    ws.send(json.dumps({"hi":{"id":"1","ver":"0.23","ua":"qa/1.0","lang":"en_AU"}})); ws.recv()
    return ws

def ctrl(ws, mid, tries=12):
    """Read frames until the matching ctrl. A directory {get} answers with meta
    and no ctrl of its own, so a read timeout is a normal end-of-reply here, not
    an error — return what arrived instead of raising."""
    metas = []
    for _ in range(tries):
        try:
            m = json.loads(ws.recv())
        except Exception:
            break
        if "ctrl" in m and m["ctrl"].get("id") == mid:
            return m["ctrl"], metas
        if "meta" in m:
            metas.append(m["meta"])
    return None, metas

# ── 1. login ──
ws = conn()
ws.send(json.dumps({"login":{"id":"L","scheme":"basic",
    "secret": base64.b64encode(b"macs:blml-first-2026").decode()}}))
c,_ = ctrl(ws,"L")
check("login (macs)", c and c.get("code")==200)

# ── 2. send + receive a message ──
ws.send(json.dumps({"sub":{"id":"S","topic":"grpNxmWQNCdOmI"}}))
c,_ = ctrl(ws,"S")
check("subscribe group", c and c.get("code") in (200,304))
ws.send(json.dumps({"pub":{"id":"P","topic":"grpNxmWQNCdOmI","content":"qa check"}}))
c,_ = ctrl(ws,"P")
seq = (c.get("params") or {}).get("seq") if c else None
check("publish message", c and c.get("code")==202 and seq, f"seq={seq}")

ws.close()

# Searches run on a dedicated connection: a session also attached to a group
# topic stops answering fnd {get} queries (verified empirically; the fresh-
# connection pattern has been reliable throughout).
def search(term):
    w = conn()
    w.send(json.dumps({"login":{"id":"L","scheme":"basic",
        "secret": base64.b64encode(b"macs:blml-first-2026").decode()}}))
    ctrl(w,"L")
    w.send(json.dumps({"sub":{"id":"F","topic":"fnd"}})); ctrl(w,"F")
    w.send(json.dumps({"set":{"id":"F2","topic":"fnd","desc":{"public":term}}})); ctrl(w,"F2")
    w.send(json.dumps({"get":{"id":"F3","topic":"fnd","what":"sub"}}))
    c, metas = ctrl(w,"F3")
    w.close()
    return [s.get("public",{}).get("fn") for meta in metas for s in (meta.get("sub") or [])]

found = search("thao")
check("username search 'thao'", "Tho" in found, str(found))

# ── 4. invite gate ──
ws = conn()
ws.send(json.dumps({"acc":{"id":"A","user":"new","scheme":"basic",
    "secret": base64.b64encode(b"qathrow:qathrowpw1").decode(),"login":False,
    "desc":{"public":{"fn":"QA Throwaway"}}}}))
c,_ = ctrl(ws,"A")
check("signup without code rejected", c and c.get("code")==403)
ws.send(json.dumps({"acc":{"id":"B","user":"new","scheme":"basic",
    "secret": base64.b64encode(b"qathrow:qathrowpw1").decode(),"login":False,
    "tags":["code:WRONG"],"desc":{"public":{"fn":"QA Throwaway"}}}}))
c,_ = ctrl(ws,"B")
check("signup with wrong code rejected", c and c.get("code")==403)
ws.send(json.dumps({"acc":{"id":"C","user":"new","scheme":"basic",
    "secret": base64.b64encode(b"qathrow:qathrowpw1").decode(),"login":True,
    "tags":["code:"+CODE],"desc":{"public":{"fn":"QA Throwaway"}}}}))
c,_ = ctrl(ws,"C")
uid = (c.get("params") or {}).get("user") if c else None
code = c.get("code") if c else None
check("signup with correct code", bool(uid), f"code={code} uid={uid}")

# ── 5. phone add/confirm/search ──
if uid:
    ws.send(json.dumps({"sub":{"id":"M","topic":"me"}})); ctrl(ws,"M")
    ws.send(json.dumps({"set":{"id":"D","topic":"me","cred":{"meth":"tel","val":"+61499000111"}}}))
    c,_ = ctrl(ws,"D")
    check("attach phone", c and c.get("code")==200)
    ws.send(json.dumps({"set":{"id":"E","topic":"me","cred":{"meth":"tel","resp":"123456"}}}))
    c,_ = ctrl(ws,"E")
    check("confirm phone (debug code)", c and c.get("code")==200)
ws.close()

found = search("+61499000111")
check("phone search finds new user", "QA Throwaway" in found, str(found))

# ── 6. urlpreview ──
def http_get(path, binary=False):
    try:
        with urllib.request.urlopen(HTTP+path, timeout=10) as r:
            body = r.read()
            return r.status, body if binary else body.decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, b"" if binary else e.read().decode("utf-8", "replace")
st, body = http_get(f"/v0/urlpreview?apikey={APIKEY}&url=https://example.com")
check("urlpreview title", st==200 and "Example Domain" in body, body[:60])
st, body = http_get(f"/v0/urlpreview?apikey={APIKEY}&url=http://127.0.0.1:6060/")
check("urlpreview blocks loopback", st==403)
st, body = http_get("/v0/urlpreview?url=https://example.com")
check("urlpreview requires api key", st==403)

# ── 7. static assets ──
st, body = http_get("/img/bkg/index.json")
check("wallpaper index", st==200 and "d10.png" in body)
st, _ = http_get("/img/bkg/d10.png", binary=True)
check("wallpaper tile", st==200)
st, body = http_get("/")
check("webapp served", st==200 and ("BLML" in body or "<html" in body.lower()))

print()
fails = [r for r in results if not r[1]]
print(f"{len(results)-len(fails)}/{len(results)} passed" + (f", {len(fails)} FAILED" if fails else ""))
sys.exit(1 if fails else 0)
