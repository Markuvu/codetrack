# 06 - Roadmap / Deferred Items

Things discussed but intentionally not built yet, in rough priority order.

## Near-term

- [ ] **Deploy the backend** (Render / Railway / Fly.io) so the app works without a PC running locally; move the app's default backend URL to the hosted instance
- [ ] **Server accounts + cloud sync** - upgrade the local auth (`auth_service.dart`) to real accounts once the backend is hosted over HTTPS; sync handles/friends/flashcards across devices
- ~~**Open links** (`url_launcher`)~~ - **won't do** (user decision, Jul 2026): links would open in the phone browser, but nobody solves problems or joins contests on the phone, so tappable rows add no value

## Dashboard

- [x] Day streak in the app UI - streak headline merged into the **Overview hero card** (reuses the same `_activeDays()` / `_currentStreak()` math as the home-screen widget). Per-day tiles were tried (rolling 7-day, then Mon-Sun) and deliberately dropped - week-boundary resets contradicted the streak number
- [ ] Submissions and AC-rate tiles
- [x] Recent Activity feed - **Recent Solves** card on the Dashboard; `/api/activity` enriched to return `{ id, name, url, at }` per solve on all four supported platforms
- [x] Weekly goal ring + weekly solved chart - CF/LC/CodeChef/AtCoder use real per-submission history via `/api/activity` (local-timezone day buckets, full week even for handles linked mid-week); GFG falls back to daily snapshot deltas
- [ ] Show CodeChef extras somewhere (league, global/country rank, institution - now scraped and available in `raw`)

## Progress

- [x] **Solved by Topic** card (like leetcode.com/progress) - `/api/topics`: LeetCode skillStats tags + Easy/Medium/Hard split; Codeforces tag aggregation from `user.status`. CodeChef/AtCoder/GFG have no public tag data
- [ ] Topic breakdown for more platforms if tag sources appear (e.g. CodeChef problem pages carry tags but would need per-problem scraping)

## Contests & reminders

- [x] Exact alarms (`SCHEDULE_EXACT_ALARM`) with automatic inexact fallback + reschedule-on-boot receivers (manifest steps in `app/README.md`)
- [x] Home-screen widget - animated ViewFlipper widget cycling streak / weekly progress / next reminder (`home_widget` + `CodeTrackWidgetProvider`; setup in `app/README.md`)
- [ ] Push notifications via FCM once the backend is hosted (server-driven reminders)

## Flashcards

- [ ] LeetCode solved-problem import (`recentAcSubmissionList` is now wired up in `leetcode.js` - reuse it)
- [ ] CodeChef solved-problem import (recent-activity scrape in `codechef.js` has problem codes + solution ids)
- [ ] Deck sharing/export

## Misc

- [ ] Optionally bundle official platform logo assets (licensing check first) for offline crispness
- [ ] Make the repo public once secrets/config are audited
- [ ] iOS build (needs a Mac for signing; the home-screen widget is Android-only for now - iOS needs a WidgetKit extension)

## Known limitations

- Reminders created before commit `3987f229` fire but don't appear in the manage list
- Recent-solved (flashcard seeding) is Codeforces-only
- Weekly Progress: GFG has no public submission history, so its bars come from daily snapshot deltas (need a prior-day baseline, UTC dates); LeetCode history is capped at the latest ~100 accepted submissions; CodeChef activity is scraped (fragile - breaks silently back to snapshots if the layout changes)
- CodeChef scraping (profile + activity) depends on page layout and embedded script variables (`all_rating`, `userDailySubmissionsStats`); selectors fail loudly on redesign
- Codeforces topic totals overlap by design (a problem counts once per tag); its tag aggregation reads up to the latest 5000 submissions, so extremely active accounts may undercount old topics
- Snapshots live on the backend's disk - lost if the backend host is wiped (until a real DB)
- Home-screen widget data refreshes when the app syncs it (dashboard refresh / reminder changes) plus a 30-min system cycle - it can lag behind live platform activity until the app is opened
