# 📱 CodeTrack

All your coding profiles, contest reminders, progress tracking & flashcards — in one mobile app.

## What it does

- **Profiles hub** — track Codeforces, LeetCode, CodeChef, AtCoder & GeeksforGeeks stats in one dashboard
- **Contest calendar** — unified upcoming-contest list (via [CLIST](https://clist.by), with Codeforces-only fallback) with one-tap local notification reminders
- **Progress tracking** — rating history graphs, daily stat snapshots, and solve streaks
- **Flashcards** — FSRS spaced-repetition review for problems and concepts, stored offline, with auto-generated cards from your recent Codeforces solves
- **Friend leaderboards** — compare rating & solved counts with friends

## Architecture

```
Mobile App (Flutter)  ──REST──▶  Backend (Node.js + Express)
                                    ├── Codeforces official API (throttled 1 req/2s)
                                    ├── LeetCode GraphQL (unofficial)
                                    ├── CodeChef profile scraper (cheerio)
                                    ├── AtCoder history JSON + kenkoooo API
                                    ├── GeeksforGeeks __NEXT_DATA__ parser
                                    ├── CLIST API (contests, all judges)
                                    ├── Daily snapshot store (JSON file)
                                    └── In-memory TTL cache
```

All platform data is fetched by **your backend**, never by the app directly — this respects rate limits and lets you cache aggressively.

## Quick start

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env   # optional: add CLIST credentials for multi-platform contests
npm start              # http://localhost:3000
```

Test it:

```bash
curl http://localhost:3000/api/profile/codeforces/tourist
curl http://localhost:3000/api/contests
```

### 2. Mobile app (Flutter)

The `app/` folder contains the Dart source. Generate the platform folders once:

```bash
cd app
flutter create . --project-name codetrack
flutter pub get
flutter run
```

By default the app talks to `http://10.0.2.2:3000` (Android emulator → your machine's localhost). Change the backend URL in the app's **Settings** screen.

## API endpoints

| Endpoint | Description |
| --- | --- |
| `GET /api/profile/:platform/:handle` | Profile stats. Platforms: `codeforces`, `leetcode`, `codechef`, `atcoder`, `gfg` |
| `GET /api/profiles?codeforces=a&leetcode=b` | Batch profile fetch |
| `GET /api/contests` | Upcoming contests across platforms |
| `GET /api/snapshots/:platform/:handle` | Daily progress snapshots (auto-recorded on fresh fetches) |
| `GET /api/solved/codeforces/:handle?limit=20` | Recently solved problems (powers auto-flashcards) |
| `GET /api/leaderboard?platform=codeforces&handles=a,b,c` | Friend leaderboard sorted by rating |
| `GET /health` | Health check |

## Notes & fair use

- Codeforces is the only official API here; LeetCode GraphQL, CodeChef/GFG scraping and the AtCoder history JSON are unofficial — responses are cached for 6h to keep request volume minimal. Fetch only public profiles of users who connect their own handles.
- Get a free CLIST API key at [clist.by](https://clist.by/api/v4/doc/) for contests across all judges.
- Snapshots are stored in `backend/data/snapshots.json` (git-ignored). Refresh profiles daily to build progress history.

## Roadmap

- [x] Codeforces / LeetCode / CodeChef profile fetchers
- [x] Unified contest list + local notification reminders
- [x] AtCoder + GeeksforGeeks fetchers
- [x] Daily stat snapshots → progress graphs & streaks
- [x] FSRS scheduler for flashcards
- [x] Auto-generated flashcards from solved problems (Codeforces)
- [x] Friend leaderboards
- [ ] Home-screen contest countdown widget (requires generated platform folders)
- [ ] Server-side push notifications (FCM) & cloud sync
