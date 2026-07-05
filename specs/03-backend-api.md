# 03 - Backend API Reference

Base URL: `http://localhost:3000` (dev). All responses are JSON unless noted. Upstream failures return `502 {"error": "..."}`; bad input returns `400`.

## Endpoints

### `GET /health`
`{ ok: true }` - liveness check.

### `GET /api/profile/:platform/:handle[?fresh=1]`
Single normalized profile. `platform` in `codeforces | leetcode | codechef | atcoder | gfg`.
Cached 6h; every fresh fetch also records a daily snapshot. Pass `fresh=1` (used by the app's pull-to-refresh) to bypass the cache - still subject to a **5-minute per-handle cooldown** so refresh-spamming can't hammer the platforms.

### `GET /api/profiles?codeforces=tourist&leetcode=neal_wu&...[&fresh=1]`
Batch fetch. Returns `{ profiles: [{ platform, handle, data? , error? }] }` - per-entry errors, never all-or-nothing. `fresh=1` applies to every entry.

### `GET /api/activity/:platform/:handle?days=8[&fresh=1]`
Per-solve history for the weekly-progress chart: `{ supported, solves: [{ id, at }] }` with `at` in epoch **ms**, accepted solves only, deduplicated per problem (earliest AC kept). Covers the full window even for handles linked mid-week; the app buckets days in the device's local timezone.

- Supported: **codeforces** (`user.status`), **leetcode** (GraphQL `recentAcSubmissionList`, latest ~100 ACs), **codechef** (recent-activity table scrape - fragile, errors degrade to snapshots), **atcoder** (kenkoooo submissions API)
- **gfg**: no public history -> `{ supported: false, solves: [] }`; the app falls back to daily snapshot deltas
- `days` 1-31 (default 7). Cached 10 min; `fresh=1` bypasses with a 60s cooldown

### `GET /api/heatmap/:platform/:handle?days=365[&fresh=1]`
Per-day submission counts for the unified activity calendar: `{ supported, days: { "yyyy-mm-dd": count } }`. Dates are bucketed by **UTC day** and count **all submissions (any verdict)**, matching the platforms' own heatmap conventions (see `05` #14).

- **codeforces**: counted from `user.status` (paged, up to 3 x 2000 submissions)
- **leetcode**: GraphQL `matchedUser.userCalendar.submissionCalendar` - LeetCode ships a ready-made year of per-day counts in a single request
- **codechef**: reuses the `userDailySubmissionsStats` heatmap already scraped for the profile (no extra request; dates are IST-ish, see `05` #14)
- **atcoder**: kenkoooo submissions API, paged by `from_second` (up to 10 pages)
- **gfg**: no public per-day history -> `{ supported: false, days: {} }`; excluded from the merged calendar
- `days` 1-366 (default 365). Cached 6h; `fresh=1` bypasses with a 5-min cooldown

### `GET /api/contests`
`{ contests: [{ id, platform, name, startsAt, durationSeconds, url }] }` - upcoming contests via CLIST v4 (`resource__in` filter), Codeforces API fallback when empty. Cached 3h.

### `GET /api/logo/:platform`
Binary image (PNG/ICO) for the platform's logo, proxied server-side to avoid browser CORS. Tries multiple sources in order (direct PNG -> Google favicon CDN -> DuckDuckGo). In-memory cache 7 days + `Cache-Control: public, max-age=86400`. Unknown platform -> `404`; all sources failed -> `502` listing each source's error.

### `GET /api/snapshots/:platform/:handle`
`{ snapshots: [...] }` - daily history recorded on fresh profile fetches.

### `GET /api/solved/codeforces/:handle?limit=20`
`{ problems: [...] }` - recently solved Codeforces problems (max 100). Used to auto-generate flashcards. Cached 1h. Codeforces-only for now.

### `GET /api/leaderboard?platform=codeforces&handles=a,b,c`
`{ platform, leaderboard: [{ handle, rating, solvedCount, error? }] }` sorted by rating desc, then solvedCount desc. Powers the Friends tab.

## Environment

| Var | Purpose |
|---|---|
| `PORT` | default 3000 |
| `CLIST_USERNAME` / `CLIST_API_KEY` | CLIST v4 credentials (get from clist.by -> API) |

## Caching summary

| Data | TTL |
|---|---|
| Profiles | 6 h (bypassable with `fresh=1`, 5-min cooldown) |
| Activity | 10 min (bypassable with `fresh=1`, 60s cooldown) |
| Heatmap | 6 h (bypassable with `fresh=1`, 5-min cooldown) |
| Contests | 3 h |
| Recent solved | 1 h |
| Logos | 7 d in memory, 1 d client cache |
