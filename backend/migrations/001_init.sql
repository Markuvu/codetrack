-- 001_init.sql
-- Core account, session, handle, submission and import-job tables.
-- Applied by `npm run migrate` (src/db/migrate.js), which records applied
-- files in schema_migrations so each migration runs exactly once.

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid() on PG < 13

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL,
  name          text NOT NULL,
  password_hash text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Case-insensitive email uniqueness without the citext extension.
CREATE UNIQUE INDEX users_email_lower_idx ON users (lower(email));

-- Refresh tokens are stored only as SHA-256 hashes. A row is one session;
-- rotation revokes the old row and links it to its replacement so token
-- reuse (a stolen, already-rotated token) can be detected.
CREATE TABLE refresh_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash  text NOT NULL,
  expires_at  timestamptz NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  revoked_at  timestamptz,
  replaced_by uuid REFERENCES refresh_tokens (id)
);

CREATE UNIQUE INDEX refresh_tokens_token_hash_idx ON refresh_tokens (token_hash);
CREATE INDEX refresh_tokens_user_id_idx ON refresh_tokens (user_id);

-- Platform handles linked to an account (codeforces, leetcode, codechef,
-- atcoder, gfg). One handle per platform per user.
CREATE TABLE linked_handles (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  platform   text NOT NULL,
  handle     text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, platform)
);

CREATE INDEX linked_handles_user_id_idx ON linked_handles (user_id);

-- Imported CodeChef submissions. source_code is null when only metadata
-- could be retrieved (no service session configured, or the solution is
-- not visible). platform_submission_id is CodeChef's numeric submission id.
CREATE TABLE codechef_submissions (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  platform_submission_id bigint NOT NULL,
  problem_code           text NOT NULL,
  problem_url            text,
  result                 text,
  language               text,
  submitted_at           timestamptz,
  source_code            text,
  source_fetched_at      timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, platform_submission_id)
);

CREATE INDEX codechef_submissions_user_recent_idx
  ON codechef_submissions (user_id, submitted_at DESC NULLS LAST);

-- One row per import run. Counters let the app show progress/status.
CREATE TABLE import_jobs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  platform       text NOT NULL DEFAULT 'codechef',
  status         text NOT NULL DEFAULT 'queued', -- queued | running | completed | failed
  handle         text,
  discovered     integer NOT NULL DEFAULT 0,
  imported       integer NOT NULL DEFAULT 0,
  source_fetched integer NOT NULL DEFAULT 0,
  skipped        integer NOT NULL DEFAULT 0,
  error          text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  started_at     timestamptz,
  finished_at    timestamptz
);

CREATE INDEX import_jobs_user_recent_idx ON import_jobs (user_id, created_at DESC);
