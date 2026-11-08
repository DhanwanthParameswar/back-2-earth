-- Back2Earth database (Tiger Cloud: PostgreSQL + TimescaleDB). Owner: C.
-- Safe to run again: everything is IF NOT EXISTS / OR REPLACE.
-- Apply on the server (DATABASE_URL lives in /etc/back2earth/companion.env):
--   psql "$DATABASE_URL" -f server/schema.sql
-- Only the backend writes here; the game never connects to the database.

-- Player accounts. Playing needs no account; one is only needed to appear on
-- the leaderboard. Passwords are stored as scrypt hashes, never in plain text.
CREATE TABLE IF NOT EXISTS accounts (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username       text        NOT NULL CHECK (username ~ '^[A-Za-z0-9_]{3,16}$'),
    password_hash  text        NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS accounts_username_ci ON accounts (lower(username));

-- Login sessions. Only a SHA-256 of the token is stored; the game keeps the token.
CREATE TABLE IF NOT EXISTS sessions (
    token_hash  text        PRIMARY KEY,
    account_id  bigint      NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    expires_at  timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_account ON sessions (account_id);

-- One row per run (a playthrough from the suit picker to the win/lose screen).
-- started_at/ended_at come from the server clock, so the time can't be faked.
CREATE TABLE IF NOT EXISTS runs (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_token     text        NOT NULL UNIQUE,              -- random id the server hands out
    account_id    bigint      REFERENCES accounts (id) ON DELETE SET NULL,  -- NULL = guest
    suit          text,
    client        text,                                     -- 'web' or 'desktop'
    started_at    timestamptz NOT NULL DEFAULT now(),
    ended_at      timestamptz,
    outcome       text        CHECK (outcome IN ('won', 'lost', 'quit')),
    duration_s    real        CHECK (duration_s >= 0),      -- evacuation start -> end
    time_left_s   real        CHECK (time_left_s >= 0),
    debris_hits   integer     NOT NULL DEFAULT 0,
    boots_uses    integer     NOT NULL DEFAULT 0,
    npc_messages  integer     NOT NULL DEFAULT 0,
    objectives_done integer   NOT NULL DEFAULT 0
);
-- Upgrades for a database made from the first version of this file.
DROP VIEW IF EXISTS leaderboard;
ALTER TABLE runs DROP COLUMN IF EXISTS player_name;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS account_id bigint REFERENCES accounts (id) ON DELETE SET NULL;
-- Random id each device makes once; guests show on the leaderboard as Guest + its first 4 characters.
ALTER TABLE runs ADD COLUMN IF NOT EXISTS guest_id text CHECK (guest_id ~ '^[a-z0-9]{8,32}$');

CREATE INDEX IF NOT EXISTS runs_won_duration ON runs (duration_s) WHERE outcome = 'won';
CREATE INDEX IF NOT EXISTS runs_started_at ON runs (started_at DESC);
CREATE INDEX IF NOT EXISTS runs_account ON runs (account_id);

-- Time-stamped gameplay events (room entered, debris hit, objective done, NPC chat...).
-- A hypertable: TimescaleDB partitions it by time, which keeps stats queries fast.
CREATE TABLE IF NOT EXISTS events (
    time       timestamptz NOT NULL DEFAULT now(),
    run_token  text        NOT NULL,
    event      text        NOT NULL,
    room       text,
    objective  text,
    detail     jsonb
);
SELECT create_hypertable('events', by_range('time', INTERVAL '7 days'), if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS events_run ON events (run_token, time DESC);
CREATE INDEX IF NOT EXISTS events_event ON events (event, time DESC);

-- Fastest escapes: each player's best winning run. A player is an account
-- (shown by username) or a guest device (shown as Guest + 4 characters).
CREATE VIEW leaderboard AS
WITH won AS (
    SELECT r.*,
           CASE WHEN r.account_id IS NOT NULL THEN 'a' || r.account_id ELSE 'g' || r.guest_id END AS player_key
    FROM runs r
    WHERE r.outcome = 'won' AND r.duration_s IS NOT NULL
      AND (r.account_id IS NOT NULL OR r.guest_id IS NOT NULL)
), best AS (
    SELECT DISTINCT ON (player_key)
           player_key, account_id, guest_id, duration_s, time_left_s, debris_hits, suit, ended_at
    FROM won
    ORDER BY player_key, duration_s ASC, ended_at ASC
)
SELECT rank() OVER (ORDER BY b.duration_s ASC)                       AS rank,
       coalesce(a.username, 'Guest' || upper(left(b.guest_id, 4)))  AS player,
       b.player_key,
       b.account_id,
       b.suit,
       round(b.duration_s::numeric, 1)                               AS seconds,
       round(b.time_left_s::numeric, 1)                              AS seconds_left,
       b.debris_hits,
       b.ended_at
FROM best b
LEFT JOIN accounts a ON a.id = b.account_id
ORDER BY b.duration_s ASC
LIMIT 100;

-- Overall numbers for the demo: plays, wins, fails, best time.
CREATE OR REPLACE VIEW run_stats AS
SELECT count(*)                                         AS runs,
       count(*) FILTER (WHERE outcome = 'won')          AS wins,
       count(*) FILTER (WHERE outcome = 'lost')         AS fails,
       count(*) FILTER (WHERE outcome = 'quit')         AS quits,
       round(min(duration_s) FILTER (WHERE outcome = 'won')::numeric, 1) AS best_seconds,
       round(avg(debris_hits)::numeric, 1)               AS avg_debris_hits
FROM runs;

-- Where players struggle: events per room (e.g. debris hits by room).
CREATE OR REPLACE VIEW events_by_room AS
SELECT room, event, count(*) AS times
FROM events
GROUP BY room, event
ORDER BY times DESC;
