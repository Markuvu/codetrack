# CodeTrack backend - production configuration

This document covers everything needed to run the backend with real user
accounts (PostgreSQL) and the CodeChef solution import.

## Components

```
Flutter app ──HTTPS──▶ Node/Express backend ──▶ PostgreSQL (users, sessions,
                            │                    handles, submissions, jobs)
                            └──▶ platform APIs (unchanged public endpoints)
```

- Public profile/contest endpoints work exactly as before and need no database.
- `/api/auth/*` and `/api/me/*` require `DATABASE_URL` + `JWT_SECRET`.
  Without them the backend starts, logs a warning, and those routes return 503.

## Environment variables

All variables are documented in [.env.example](./.env.example). Summary:

| Variable | Required | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | for accounts | PostgreSQL connection string. Append `?sslmode=require` for managed Postgres. |
| `JWT_SECRET` | with `DATABASE_URL` | 32+ char random secret signing access tokens (`openssl rand -hex 32`). |
| `ACCESS_TOKEN_TTL_SECONDS` | no (900) | Access-token lifetime. Keep short; clients refresh automatically. |
| `REFRESH_TOKEN_TTL_DAYS` | no (30) | Refresh-token lifetime. Tokens rotate on every refresh and are stored hashed. |
| `BCRYPT_ROUNDS` | no (12) | Password hashing work factor. |
| `CORS_ORIGINS` | production | Comma-separated browser origins. Empty allows all (dev only). |
| `CODECHEF_SESSION_COOKIES` | for source import | Cookie header of a dedicated CodeChef service-account session. |
| `CODECHEF_CSRF_TOKEN` | for source import | The session's `x-csrf-token` value. |
| `CODECHEF_FETCH_THROTTLE_MS` | no (2500) | Delay between every CodeChef request during an import. |
| `CODECHEF_FETCH_TIMEOUT_MS` | no (15000) | Per-request timeout. |
| `CODECHEF_IMPORT_MAX_PAGES` | no (10) | Max recent-activity pages scanned per run. |
| `CODECHEF_MAX_SOURCE_FETCHES_PER_RUN` | no (40) | Cap on source-code fetches per run. |

Keep secrets in your platform's secret manager (Fly/Render/Railway secrets,
AWS SSM, etc.), never in Git. `.env` is git-ignored for local development.

## Database

Local development:

```bash
cd backend
docker compose up -d db     # PostgreSQL 16 on localhost:5432
cp .env.example .env        # fill in JWT_SECRET
npm install
npm run migrate             # applies migrations/*.sql once each
npm start
```

Production: create a database, set `DATABASE_URL`, and run `npm run migrate`
during deploys (idempotent - applied files are tracked in `schema_migrations`).

Schema highlights (see `migrations/001_init.sql`):

- `users` - unique per lower-cased email, bcrypt password hashes.
- `refresh_tokens` - SHA-256 hashes only; rotation links `replaced_by`, reuse
  of a revoked token revokes every session for that user.
- `linked_handles` - `UNIQUE (user_id, platform)`.
- `codechef_submissions` - `UNIQUE (user_id, platform_submission_id)` gives
  import idempotency/deduplication; indexed for the recent-first listing.
- `import_jobs` - one row per run with progress counters.

## Security model

- Passwords: bcrypt (configurable rounds), never logged or returned.
- Access tokens: HS256 JWTs, 15-minute default lifetime.
- Refresh tokens: 256-bit random values stored only as SHA-256 hashes,
  rotated on every `/api/auth/refresh`, revocable via logout / password
  change, with reuse detection.
- All `/api/me/*` queries are scoped by the authenticated user id -
  parameterized SQL everywhere, no cross-user access paths.
- Credential endpoints are rate limited per IP (also rate-limit at your
  reverse proxy for multi-instance deployments).
- The mobile app stores tokens in platform secure storage
  (Keystore/Keychain via `flutter_secure_storage`), not SharedPreferences.

## HTTPS & CORS

- Terminate TLS in front of Node (managed platform, or nginx/Caddy). Never
  serve auth endpoints over plain HTTP outside local development.
- If a proxy sits in front, set Express `trust proxy` appropriately at the
  proxy level or forward `X-Forwarded-For` so rate limiting sees real IPs.
- Set `CORS_ORIGINS` to the exact web-app origins in production. Mobile apps
  are unaffected by CORS.

## CodeChef import - operational notes

- Discovery uses CodeChef's normal public recent-activity endpoint for the
  signed-in user's saved handle only; no other users are ever crawled.
- Source code is fetched through one dedicated service-account session
  (`viewplaintext`), throttled (default one request per 2.5 s), capped per
  run, deduplicated against already-imported submissions, and cached forever
  in PostgreSQL (a submission's source is fetched at most once).
- When the session is missing/expired or a solution is not visible, the run
  degrades to metadata-only rows instead of failing.
- Session cookies expire; refresh them periodically in the secret manager.
  The import keeps working (metadata-only) in the meantime.
- LeetCode source retrieval is intentionally not implemented.

## Operations checklist

- [ ] `DATABASE_URL` + `JWT_SECRET` set; `npm run migrate` run on deploy
- [ ] `CORS_ORIGINS` restricted to real origins
- [ ] TLS termination in place
- [ ] Secrets in a secret manager, `.env` absent from the image/repo
- [ ] Database backups enabled
- [ ] (Optional) CodeChef service-session cookies provisioned & rotated
