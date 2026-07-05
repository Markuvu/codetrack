# 06 - Roadmap / Deferred Items

Things discussed but intentionally not built yet, in rough priority order.

## Near-term

- [ ] **Deploy the backend** (Render / Railway / Fly.io) so the app works without a PC running locally; move the app's default backend URL to the hosted instance
- [ ] **Server accounts + cloud sync** - upgrade the local auth (`auth_service.dart`) to real accounts once the backend is hosted over HTTPS; sync handles/friends/flashcards across devices
- [ ] **Open links** - `url_launcher` so contest cards and flashcards open the contest/problem page

## Dashboard

- [ ] Day-streak, submissions and AC-rate tiles (can now reuse `/api/activity` for CF/LC/AtCoder)
- [ ] Recent Activity feed (latest accepted submissions across platforms - `/api/activity` already has the data for CF/LC/AtCoder)
- [x] Weekly goal ring + weekly solved chart - CF/LC/AtCoder use real per-submission history via `/api/activity` (local-timezone day buckets, full week even for handles linked mid-week); CodeChef/GFG fall back to daily snapshot deltas

## Contests & reminders

- [ ] Exact alarms (`SCHEDULE_EXACT_ALARM`) and reschedule-on-boot receiver
- [ ] Home-screen widget for the next contest
- [ ] Push notifications via FCM once the backend is hosted (server-driven reminders)

## Flashcards

- [ ] LeetCode solved-problem import (`recentAcSubmissionList` is now wired up in `leetcode.js` - reuse it)
- [ ] Deck sharing/export

## Misc

- [ ] Optionally bundle official platform logo assets (licensing check first) for offline crispness
- [ ] Make the repo public once secrets/config are audited
- [ ] iOS build (needs a Mac for signing)

## Known limitations

- Reminders created before commit `3987f229` fire but don't appear in the manage list
- Recent-solved (flashcard seeding) is Codeforces-only
- Weekly Progress: CodeChef and GFG have no public submission history, so their bars come from daily snapshot deltas (need a prior-day baseline, UTC dates); LeetCode history is capped at the latest ~100 accepted submissions (only matters if you solve 100+ in a week)
- Snapshots live on the backend's disk - lost if the backend host is wiped (until a real DB)
