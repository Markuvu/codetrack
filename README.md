# 📱 CodeTrack

All your coding profiles, contest reminders, progress tracking & flashcards — in one mobile app.

## What it does

- **Profiles hub** — track your Codeforces, LeetCode and CodeChef stats (rating, solved count, contest history) in one dashboard
- **Contest calendar** — unified upcoming-contest list (via [CLIST](https://clist.by), with Codeforces-only fallback) with one-tap local notification reminders
- **Flashcards** — spaced-repetition review (SM-2 algorithm) for problems and concepts, stored offline
- **Progress tracking** — rating history from platform APIs; daily snapshots planned

## Architecture

```
Mobile App (Flutter)  ──REST──▶  Backend (Node.js + Express)
                                    ├── Codeforces official API (throttled 1 req/2s)
                                    ├── LeetCode GraphQL (unofficial)
                                    ├── CodeChef profile scraper (cheerio)
                                    ├── CLIST API (contests, all judges)
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
| `GET /api/profile/:platform/:handle` | Profile stats. Platforms: `codeforces`, `leetcode`, `codechef` |
| `GET /api/contests` | Upcoming contests across platforms |
| `GET /health` | Health check |

## Notes & fair use

- Codeforces is the only official API here; LeetCode GraphQL and CodeChef scraping are unofficial — responses are cached for 6h to keep request volume minimal. Fetch only public profiles of users who connect their own handles.
- Get a free CLIST API key at [clist.by](https://clist.by/api/v4/doc/) for contests across all judges.

## Roadmap

- [ ] AtCoder + GeeksforGeeks fetchers
- [ ] Daily stat snapshots → progress graphs & streaks
- [ ] FSRS scheduler upgrade for flashcards
- [ ] Auto-generated flashcards from solved problems
- [ ] Friend leaderboards
- [ ] Home-screen contest countdown widget
