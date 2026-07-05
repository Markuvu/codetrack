# 02 - Data Sources

How each platform's data is obtained, and the gotchas discovered along the way.

## Profiles

| Platform | Source | Normalized fields (`raw`) |
|---|---|---|
| Codeforces | Official API (`user.info`, `user.rating`, `user.status`) | `rating, maxRating, rank, maxRank, contestsAttended, solvedCount, ratingHistory[{contest, at, newRating}]` |
| LeetCode | Public GraphQL endpoint | `ranking, solvedCount, solvedByDifficulty{easy,medium,hard,all}, rating, contestsAttended, globalRanking, topPercentage` |
| CodeChef | Profile page scrape (see notes) | `rating, stars, maxRating, solvedCount, contestsAttended, globalRank, countryRank, country, role, institution, league, profileImage, ratingHistory[{contest, at, newRating}], heatmap[{date, submissions}]` |
| AtCoder | atcoder.jp history JSON + Kenkoooo/AtCoder Problems APIs | `rating, maxRating, contestsAttended, solvedCount, ratingHistory` |
| GeeksforGeeks | `authapi.geeksforgeeks.org/api-get/user-profile-info/?handle=<h>&article_count=false`, fallback `geeks-for-geeks-api.vercel.app/<h>` | `codingScore, solvedCount, instituteRank, longestStreak` |

### CodeChef notes

No official API, so `codechef.js` scrapes `codechef.com/users/<handle>` with cheerio. The best data is NOT in the rendered HTML but embedded as script variables:

- `var all_rating = [...]` -> full **rating history** (contest name, rating, rank, end date). Normalized to `{contest, at, newRating}` to match the other platforms, so the dashboard sparkline and Progress charts work unchanged.
- `var userDailySubmissionsStats = [...]` -> **heatmap** of submissions per day. Counts ALL submissions (including WAs), so it's exposed as context, not used as a solve count.

HTML selectors used: `.rating-number` (rating), `.rating-star` (stars), `.rating-header small` (highest rating), `section.problems-solved h3` (solved count, contest count), `.rating-ranks li strong` (global/country rank), `.user-country-name`, `section.user-details li:contains(...)` (role, institution), `.user-league-container .tooltip` (league), header `img` (avatar).

**Recent activity** (per-solve timestamps for `/api/activity`) comes from the AJAX endpoint `codechef.com/recent/user?page=N&user_handle=<h>`, which returns `{ content: "<table html>", max_page }`. Rows are parsed for time (`td1` title attr, IST, e.g. "10:43 PM 04/07/26", or relative "5 min ago"), problem (`td2 a` href `/CONTEST/problems/CODE`), and result (`td3 span` title contains "accepted"). Up to 4 pages fetched, stopping at the window edge.

All of this is layout-dependent and **fails loudly** when CodeChef redesigns (profile throws; activity errors degrade to the snapshot fallback). Not scraped (yet, unused by the app): per-contest problem lists, learning paths, badges.

### GFG notes
- The redesigned GFG profile page has **no `__NEXT_DATA__`** - HTML scraping is dead. The `authapi` endpoint is the reliable path (found July 2026).
- GFG has **no contest rating**; the app shows **Coding Score** as its headline metric and hides "Rating" labels for gfg (in dashboard, friends list, etc.).

## Per-solve activity (`/api/activity`)

| Platform | Source | Notes |
|---|---|---|
| Codeforces | `user.status` | exact, full history |
| LeetCode | GraphQL `recentAcSubmissionList` | latest ~100 ACs |
| CodeChef | recent-activity table scrape | IST timestamps, most fragile |
| AtCoder | kenkoooo submissions API | exact, full history |
| GFG | none | snapshot-delta fallback |

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

Every *fresh* (non-cached) profile fetch appends a daily snapshot `{date, rating, solvedCount, ...}` per `platform:handle`, exposed at `/api/snapshots/:platform/:handle`. This powers the Progress tab's history charts, and is the weekly-progress fallback for platforms without per-solve activity (now only GFG).

## Politeness / rate limiting

- All upstream calls go through `cache.wrap` (profiles 6h, activity 10min, contests 3h, solved 1h); `fresh=1` bypasses with short cooldowns
- Codeforces calls are additionally serialized through a queue (1 request / 2.1s)
- Batch endpoints (`/api/profiles`, `/api/leaderboard`) use `Promise.allSettled` so one bad handle doesn't fail the batch
- Upstream failures surface as `502 {"error": ...}` to the app, which renders them inline per-card/per-row
