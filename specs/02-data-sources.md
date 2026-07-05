# 02 - Data Sources

How each platform's data is obtained, and the gotchas discovered along the way.

## Profiles

| Platform | Source | Normalized fields (`raw`) |
|---|---|---|
| Codeforces | Official API (`user.info`, `user.rating`, `user.status`) | `rating, maxRating, rank, maxRank, contestsAttended, solvedCount, ratingHistory[{contest, at, newRating}]` |
| LeetCode | Public GraphQL endpoint | `ranking, solvedCount, solvedByDifficulty{easy,medium,hard,all}, rating, contestsAttended, globalRanking, topPercentage` |
| CodeChef | Profile page scrape | `rating, stars, maxRating, solvedCount` |
| AtCoder | Kenkoooo/AtCoder Problems APIs | `rating, maxRating, contestsAttended, solvedCount, ratingHistory` |
| GeeksforGeeks | `authapi.geeksforgeeks.org/api-get/user-profile-info/?handle=<h>&article_count=false`, fallback `geeks-for-geeks-api.vercel.app/<h>` | `codingScore, solvedCount, instituteRank, longestStreak` |

### GFG notes
- The redesigned GFG profile page has **no `__NEXT_DATA__`** - HTML scraping is dead. The `authapi` endpoint is the reliable path (found July 2026).
- GFG has **no contest rating**; the app shows **Coding Score** as its headline metric and hides "Rating" labels for gfg (in dashboard, friends list, etc.).

## Contests - CLIST v4

- Endpoint: `https://clist.by/api/v4/contest/`
- Params: `upcoming=true`, **`resource__in`**=`codeforces.com,leetcode.com,codechef.com,atcoder.jp`, `order_by=start`, `limit=50`
- Auth header: `Authorization: ApiKey <username>:<key>` from `backend/.env`
- **Gotcha:** using `resource=` (comma list) silently matches nothing in v4; it must be `resource__in`. This caused a "No upcoming contests found" bug.
- Fallback: if CLIST returns nothing or errors, the backend falls back to the Codeforces contests API (Codeforces-only list beats an empty screen).

Contest model: `{id, platform, name, start (UTC), duration, url}` from `startsAt` epoch seconds + `durationSeconds`.

## Platform logos

Served from our own backend at `/api/logo/:platform` (never fetched directly by the app - CORS, see `05` #10). Candidate sources tried in order:

1. Platform-specific direct PNGs (`EXTRA_LOGO_URLS`) - e.g. LeetCode's `assets.leetcode.com/.../favicon-96x96.png` (Google's favicon CDN 404s for leetcode.com)
2. Google favicon CDN `www.google.com/s2/favicons?sz=64&domain=<domain>`
3. DuckDuckGo `icons.duckduckgo.com/ip3/<domain>.ico`

Responses are validated (`content-type` contains `image`, non-empty body) and cached 7 days in memory.

## Snapshots

Every *fresh* (non-cached) profile fetch appends a daily snapshot `{date, rating, solvedCount, ...}` per `platform:handle`, exposed at `/api/snapshots/:platform/:handle`. This powers the Progress tab's history charts beyond what platforms expose natively.

## Politeness / rate limiting

- All upstream calls go through `cache.wrap` (profiles 6h, contests 3h, solved 1h)
- Batch endpoints (`/api/profiles`, `/api/leaderboard`) use `Promise.allSettled` so one bad handle doesn't fail the batch
- Upstream failures surface as `502 {"error": ...}` to the app, which renders them inline per-card/per-row
