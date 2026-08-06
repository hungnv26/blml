#!/usr/bin/env python3
"""BLML admin dashboard: one read-only page for the operator.

Reads Postgres directly rather than the chat API — member last-seen, message
and storage totals are not exposed over the Tinode protocol at all. Guarded by
a bearer token (ADMIN_TOKEN) and, in the compose file, bound to 127.0.0.1 so
it is unreachable from the network even with the token.
"""
import html
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

import psycopg2

DSN = dict(
    host=os.environ.get("PGHOST", "db"),
    dbname=os.environ.get("PGDATABASE", "tinode"),
    user=os.environ.get("PGUSER", "postgres"),
    password=os.environ["PGPASSWORD"],
)
ADMIN_TOKEN = os.environ["ADMIN_TOKEN"]
REGISTRATION_CODE = os.environ.get("REGISTRATION_CODE", "(not set)")


def query(sql, args=()):
    with psycopg2.connect(**DSN) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchall()


def gather():
    users = query("""
        SELECT public->>'fn', state, createdat, lastseen,
               (SELECT string_agg(tag, ', ') FROM usertags t WHERE t.userid = u.id)
        FROM users u ORDER BY createdat""")
    topics = query("""
        SELECT name, public->>'fn', seqid, touchedat FROM topics
        WHERE name NOT IN ('sys') AND name NOT LIKE 'usr%%' ORDER BY touchedat DESC NULLS LAST""")
    msgs = query("SELECT COUNT(*) FROM messages WHERE deletedat IS NULL")[0][0]
    files = query("SELECT COUNT(*), COALESCE(SUM(size),0) FROM fileuploads")[0]
    db_size = query("SELECT pg_size_pretty(pg_database_size(current_database()))")[0][0]
    return users, topics, msgs, files, db_size


def human_bytes(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def ago(ts):
    if ts is None:
        return "never"
    delta = datetime.now(timezone.utc) - ts.replace(tzinfo=timezone.utc)
    days = delta.days
    if days == 0:
        hours = delta.seconds // 3600
        return f"{hours}h ago" if hours else f"{delta.seconds // 60}m ago"
    return f"{days}d ago"


PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>BLML admin</title>
<style>
 body {{ font: 15px -apple-system, system-ui, sans-serif; margin: 2rem auto; max-width: 720px;
        padding: 0 1rem; background: #0b141a; color: #e9edef; }}
 h1 {{ font-size: 1.4rem }} h2 {{ font-size: 1.05rem; margin-top: 2rem; color: #8696a0 }}
 table {{ border-collapse: collapse; width: 100% }}
 td, th {{ text-align: left; padding: .45rem .6rem; border-bottom: 1px solid #1f2c33 }}
 th {{ color: #8696a0; font-weight: 600 }}
 .num {{ text-align: right }}
 .cards {{ display: flex; gap: .8rem; flex-wrap: wrap; margin-top: 1rem }}
 .card {{ background: #1f2c33; border-radius: 10px; padding: .8rem 1.1rem; flex: 1; min-width: 8rem }}
 .card b {{ display: block; font-size: 1.4rem }}
 .card span {{ color: #8696a0; font-size: .85rem }}
 code {{ background: #1f2c33; padding: .15rem .45rem; border-radius: 6px }}
</style></head><body>
<h1>BLML admin</h1>
<div class="cards">
 <div class="card"><b>{nusers}</b><span>members</span></div>
 <div class="card"><b>{nmsgs}</b><span>messages</span></div>
 <div class="card"><b>{upload_size}</b><span>uploads ({nfiles} files)</span></div>
 <div class="card"><b>{db_size}</b><span>database</span></div>
</div>
<h2>Members</h2>
<table><tr><th>Name</th><th>Joined</th><th>Last seen</th><th>Tags</th></tr>{user_rows}</table>
<h2>Group topics</h2>
<table><tr><th>Topic</th><th>Name</th><th class="num">Messages</th><th>Last activity</th></tr>{topic_rows}</table>
<h2>Invite code</h2>
<p>Current code: <code>{regcode}</code></p>
<p style="color:#8696a0">To rotate it: edit REGISTRATION_CODE in deploy/secrets.env, then run
<code>./gen-config.sh</code> and <code>docker compose up -d --build</code>.</p>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _deny(self):
        self.send_response(403)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"token required: /?token=...\n")

    def do_GET(self):
        parsed = urlparse(self.path)
        token = parse_qs(parsed.query).get("token", [""])[0]
        if token != ADMIN_TOKEN:
            self._deny()
            return
        try:
            users, topics, msgs, files, db_size = gather()
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
            return

        user_rows = "".join(
            "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>".format(
                html.escape(fn or "?"),
                created.date().isoformat() if created else "?",
                ago(lastseen),
                html.escape(tags or ""))
            for fn, state, created, lastseen, tags in users)
        topic_rows = "".join(
            "<tr><td><code>{}</code></td><td>{}</td><td class=\"num\">{}</td><td>{}</td></tr>".format(
                html.escape(name), html.escape(fn or ""), seq or 0, ago(touched))
            for name, fn, seq, touched in topics)

        body = PAGE.format(
            nusers=len(users), nmsgs=msgs,
            nfiles=files[0], upload_size=human_bytes(files[1]),
            db_size=db_size,
            user_rows=user_rows, topic_rows=topic_rows,
            regcode=html.escape(REGISTRATION_CODE)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 6061), Handler).serve_forever()
