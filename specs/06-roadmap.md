# 06 - Roadmap / Deferred Items

Things discussed but intentionally not built yet, in rough priority order.

## Near-term

- [ ] **Deploy the backend** (Render / Railway / Fly.io) so the app works without a PC running locally; move the app's default backend URL to the hosted instance
- [ ] **Server accounts + cloud sync** - upgrade the local auth (`auth_service.dart`) to real accounts once the backend is hosted over HTTPS; sync handles/friends/flashcards across devices
- [ ] **Open links** - `url_launcher` so contest cards and flashcards open the contest/problem page

## Dashboard

- [ ] Day-streak, submissions and AC-rate tiles (needs a submissions-history endpoint)
- [ ] Recent Activity feed (latest accepted submissions across platforms)
- [x] Weekly goal ring + weekly solved chart - shipped using daily snapshot deltas; accuracy improves once a real per-submission history endpoint exists (snapshots only capture days the app fetched fresh data, and snapshot dates are UTC)

## Contests & reminders

- [ ] Exact alarms (`SCHEDULE_EXACT_ALARM`) and reschedule-on-boot receiver
- [ ] Home-screen widget for the next contest
- [ ] Push notifications via FCM once the backend is hosted (server-driven reminders)

## Flashcards

- [ ] LeetCode solved-problem import (needs per-problem history from GraphQL)
- [ ] Deck sharing/export

## Misc

- [ ] Optionally bundle official platform logo assets (licensing check first) for offline crispness
- [ ] Make the repo public once secrets/config are audited
- [ ] iOS build (needs a Mac for signing)

## Known limitations

- Reminders created before commit `3987f229` fire but don't appear in the manage list
- Recent-solved (flashcard seeding) is Codeforces-only
- Weekly Progress bars only count days where the backend recorded a fresh snapshot (open the app daily for best accuracy); snapshot dates are UTC so late-night solves can land on the neighboring bar
- Snapshots live on the backend's disk - lost if the backend host is wiped (until a real DB)
