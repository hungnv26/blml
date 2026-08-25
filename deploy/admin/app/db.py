"""Postgres access for the console.

Reads only. Per the plan's central decision, writes that change chat state go
through the Tinode API as a root account (app/tinode.py) so the server stays
authoritative over its own in-memory topics and sessions. The exceptions are
the console's own tables in the `admin` schema, which the server knows
nothing about and therefore cannot cache.
"""
from __future__ import annotations

import os
from contextlib import contextmanager
from pathlib import Path

import psycopg2
import psycopg2.extras

DSN = dict(
    host=os.environ.get("PGHOST", "db"),
    dbname=os.environ.get("PGDATABASE", "tinode"),
    user=os.environ.get("PGUSER", "postgres"),
    password=os.environ["PGPASSWORD"],
)


@contextmanager
def cursor(dict_rows: bool = True):
    conn = psycopg2.connect(**DSN)
    try:
        factory = psycopg2.extras.RealDictCursor if dict_rows else None
        with conn:
            with conn.cursor(cursor_factory=factory) as cur:
                yield cur
    finally:
        conn.close()


def query(sql: str, args: tuple = ()) -> list:
    with cursor() as cur:
        # `args or None`, not `args`: psycopg2 attempts %-interpolation
        # whenever args is not None, so an empty tuple makes a literal
        # `LIKE 'grp%'` blow up at runtime. Passing None skips it entirely.
        cur.execute(sql, args or None)
        return cur.fetchall()


def query_one(sql: str, args: tuple = ()):
    rows = query(sql, args)
    return rows[0] if rows else None


def execute(sql: str, args: tuple = ()) -> int:
    """Returns the affected row count.

    Callers are expected to check it. A password reset that matched zero rows
    reports success just as cheerfully as one that worked — that exact
    mistake, keyed on the wrong column, cost an afternoon once already.
    """
    with cursor(dict_rows=False) as cur:
        cur.execute(sql, args or None)
        return cur.rowcount


def init_schema() -> None:
    """Creates the admin schema. Idempotent; runs on every boot."""
    ddl = (Path(__file__).parent / "schema.sql").read_text()
    with cursor(dict_rows=False) as cur:
        cur.execute(ddl)


# ── Dashboard ────────────────────────────────────────────────────────────────

def dashboard_totals() -> dict:
    return {
        "members": query_one(
            "SELECT count(*) AS n FROM users WHERE state != 30")["n"],
        "active_7d": query_one(
            "SELECT count(*) AS n FROM users "
            "WHERE lastseen > now() - interval '7 days'")["n"],
        "messages": query_one(
            "SELECT count(*) AS n FROM messages WHERE deletedat IS NULL")["n"],
        "topics": query_one(
            "SELECT count(*) AS n FROM topics WHERE name LIKE 'grp%'")["n"],
        "uploads": query_one(
            "SELECT count(*) AS files, coalesce(sum(size), 0) AS bytes "
            "FROM fileuploads"),
        "db_size": query_one(
            "SELECT pg_size_pretty(pg_database_size(current_database())) AS s")["s"],
        "devices": query(
            "SELECT platform, count(*) AS n FROM devices GROUP BY platform "
            "ORDER BY platform"),
    }


def messages_per_day(days: int = 30) -> list:
    """Message counts per day, zero-filled so the sparkline has no gaps."""
    return query(
        """
        SELECT d::date AS day, coalesce(m.n, 0) AS n
        FROM generate_series(now() - make_interval(days => %s), now(),
                             interval '1 day') AS d
        LEFT JOIN (
            SELECT createdat::date AS day, count(*) AS n
            FROM messages WHERE deletedat IS NULL GROUP BY 1
        ) m ON m.day = d::date
        ORDER BY day
        """, (days,))


def recent_signups(limit: int = 8) -> list:
    return query(
        "SELECT id, public->>'fn' AS name, createdat, lastseen "
        "FROM users WHERE state != 30 ORDER BY createdat DESC LIMIT %s",
        (limit,))


# ── Groups and conversations ─────────────────────────────────────────────────

def list_topics() -> list:
    """Every conversation topic with its size and last activity.

    Includes p2p and saved-messages rows, not just groups: the page this
    console replaces listed them all, and losing that view would leave the
    operator worse off than before. Names and counts only — no message
    content, here or anywhere.
    """
    return query(
        """
        SELECT t.name,
               t.public->>'fn' AS title,
               CASE
                   WHEN t.name LIKE 'grp%' THEN 'group'
                   WHEN t.name LIKE 'p2p%' THEN 'one-to-one'
                   WHEN t.name LIKE 'slf%' THEN 'saved'
                   ELSE 'other'
               END AS kind,
               t.seqid AS messages,
               t.touchedat,
               (SELECT count(*) FROM subscriptions s
                 WHERE s.topic = t.name AND s.deletedat IS NULL) AS members
        FROM topics t
        WHERE t.name <> 'sys' AND t.name NOT LIKE 'usr%'
        ORDER BY t.touchedat DESC NULLS LAST
        """)


# ── People ───────────────────────────────────────────────────────────────────

def list_people(search: str | None = None) -> list:
    """Members with their tags and conversation counts.

    Metadata only — no message content anywhere in this module. That is the
    product's stated privacy position, not merely a scoping choice.
    """
    where, args = "u.state != 30", []
    if search:
        where += (" AND (u.public->>'fn' ILIKE %s OR EXISTS ("
                  "SELECT 1 FROM usertags t WHERE t.userid = u.id"
                  " AND t.tag ILIKE %s))")
        args += [f"%{search}%", f"%{search}%"]
    return query(
        f"""
        SELECT u.id, u.public->>'fn' AS name, u.state, u.createdat, u.lastseen,
               (SELECT string_agg(t.tag, ', ' ORDER BY t.tag)
                  FROM usertags t WHERE t.userid = u.id) AS tags,
               (SELECT count(*) FROM subscriptions s
                 WHERE s.userid = u.id AND s.deletedat IS NULL) AS subs
        FROM users u WHERE {where}
        ORDER BY u.lastseen DESC NULLS LAST
        """, tuple(args))


def get_person(user_id: int) -> dict | None:
    return query_one(
        "SELECT id, public->>'fn' AS name, state, createdat, updatedat, "
        "lastseen, public FROM users WHERE id = %s", (user_id,))


def person_extras(user_id: int) -> dict:
    return {
        "tags": query(
            "SELECT tag FROM usertags WHERE userid = %s ORDER BY tag",
            (user_id,)),
        "credentials": query(
            "SELECT method, value, done FROM credentials "
            "WHERE userid = %s ORDER BY method", (user_id,)),
        "devices": query(
            "SELECT hash, platform, lastseen FROM devices WHERE userid = %s",
            (user_id,)),
        "subscriptions": query(
            "SELECT topic, updatedat, deletedat FROM subscriptions "
            "WHERE userid = %s ORDER BY updatedat DESC NULLS LAST", (user_id,)),
        "auth": query(
            "SELECT uname, authlvl, expires FROM auth WHERE userid = %s",
            (user_id,)),
    }


def uid_encoded(user_id: int) -> str | None:
    """Tinode addresses users by an encoded id (usrXXXX); the database uses an
    integer. The auth table's uname carries the login, so it is the practical
    bridge for the API client."""
    row = query_one("SELECT uname FROM auth WHERE userid = %s LIMIT 1",
                    (user_id,))
    if not row or not row["uname"]:
        return None
    # Stored as `<scheme>:<login>`, e.g. `basic:noza` — not the bare login.
    return row["uname"].split(":", 1)[-1]
