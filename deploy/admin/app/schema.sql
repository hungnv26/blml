-- Admin console tables.
--
-- Everything lives in its own `admin` schema, never in Tinode's public
-- tables. BLML tracks upstream, and a future merge should be a merge rather
-- than an archaeology exercise: nothing here can collide with a column
-- upstream decides to add.

CREATE SCHEMA IF NOT EXISTS admin;

-- The single operator. One row, by design (see the CHECK): the console was
-- specified for one person, so there is no role model and no invitations.
CREATE TABLE IF NOT EXISTS admin.operator (
    id            SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    username      TEXT        NOT NULL,
    password_hash TEXT        NOT NULL,
    totp_secret   TEXT,
    totp_enrolled BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sessions are stored as a hash of the cookie value, so a database read
-- cannot mint a working session.
CREATE TABLE IF NOT EXISTS admin.session (
    token_hash  TEXT PRIMARY KEY,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    -- Set when the operator re-enters their password for a restart or a
    -- delete. Short-lived and separate from the session's own expiry.
    stepup_at   TIMESTAMPTZ,
    ip          TEXT,
    user_agent  TEXT
);

CREATE INDEX IF NOT EXISTS session_expires_idx ON admin.session (expires_at);

-- Every action the console takes, and every failed login.
--
-- With one operator this is not about attribution, it is about "when did
-- that change, and what did it look like before". `before`/`after` are JSON
-- so a new action type does not need a migration.
CREATE TABLE IF NOT EXISTS admin.audit (
    id         BIGSERIAL PRIMARY KEY,
    at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    action     TEXT NOT NULL,
    target     TEXT,
    outcome    TEXT NOT NULL DEFAULT 'ok',
    detail     JSONB,
    ip         TEXT
);

CREATE INDEX IF NOT EXISTS audit_at_idx ON admin.audit (at DESC);
CREATE INDEX IF NOT EXISTS audit_action_idx ON admin.audit (action, at DESC);
