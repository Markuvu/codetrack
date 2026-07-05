# 03 - Backend API Reference

Base URL: `http://localhost:3000` (dev). All responses are JSON unless noted. Upstream failures return `502 {"error": "..."}`; bad input returns `400`.

## Endpoints

### `GET /health`
`{ ok: true }` - liveness check.

### `GET /api/profile/:platform/:handle`
Single normalized profile. `platform` in `codeforces | leetcode | codechef | atcoder | gfg`.
Cached 6h; every fresh fetch also records a daily snapshot.

### `GET /api/profiles?codeforces=tourist&leetcode=neal_wu&...`
Batch fetch. Returns `{ profiles: [{ platform, handle, data? , error? }] }` - per-entry errors, never all-or-nothing.

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
| Profiles | 6 h |
| Contests | 3 h |
| Recent solved | 1 h |
| Logos | 7 d in memory, 1 d client cache |
