-- Additive migration for an existing Back2Earth database. Safe to run again.
-- One resumable escape per account. A NULL snapshot is a deletion tombstone.
-- Revisions prevent a stale device from overwriting or resurrecting another save.
CREATE TABLE IF NOT EXISTS game_saves (
    account_id bigint PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    snapshot jsonb CHECK (snapshot IS NULL OR octet_length(snapshot::text) <= 32768),
    revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
    updated_at timestamptz NOT NULL DEFAULT now()
);
