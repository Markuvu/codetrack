# 01 - Architecture

## High-level flow

```
Flutter app (Android / web)
        |  HTTP (JSON)
        v
Node/Express backend  --->  platform APIs & endpoints
  - normalizes shapes        (Codeforces API, LeetCode GraphQL,
  - caches responses          CodeChef page, AtCoder/Kenkoooo,
  - records snapshots         GFG authapi, CLIST v4, favicon CDNs)
```

The app **never talks to the platforms directly**. Everything goes through the backend because:

1. Some sources need scraping/headers that are awkward from Dart
2. Browsers enforce CORS on the web build; servers are exempt (see `05` decisions #7, #10)
3. Central caching keeps us polite toward the platforms (see TTLs below)

## Backend (`backend/`)

- `src/index.js` - Express app, routes, logo proxy, platform registry (`PLATFORMS` map)
- `src/cache.js` - simple TTL cache; `cache.wrap(key, ttl, fn)`
- `src/services/*.js` - one module per data source, each exporting `get<X>Profile(handle)` returning a normalized object
- `src/services/snapshots.js` - records a daily snapshot on every fresh profile fetch (for progress graphs/streaks)
- `src/services/clist.js` - upcoming contests via CLIST v4, with a Codeforces-API fallback

**Cache TTLs:** profiles 6h, contests 3h, recent-solved 1h, logos 7d (in-memory) + `Cache-Control: max-age=86400` for clients.

**Config:** `backend/.env` (`CLIST_USERNAME`, `CLIST_API_KEY`, `PORT`). `.env.example` documents the keys.

## App (`app/lib/`)

| Folder | Contents |
|---|---|
| `models/` | `PlatformProfile`, `Contest`, `Flashcard` |
| `services/` | `api_client.dart` (HTTP; backend URL stored in prefs, default `http://10.0.2.2:3000`), `notification_service.dart`, `auth_service.dart` |
| `storage/` | `app_store.dart` - shared_preferences wrapper (`handles`, `flashcards`, `friends_<platform>`, `scheduled_reminders`) |
| `logic/` | `fsrs.dart`, `sm2.dart` spaced-repetition schedulers |
| `screens/` | `dashboard`, `contests`, `progress`, `flashcards`, `leaderboard` (Friends), `settings`, `auth` |
| `widgets/` | `platform_logo.dart` - shared `PlatformLogo` widget + `platformColor()` / `platformDisplayName()` helpers |

`main.dart` boots async: reads `AuthService.isLoggedIn()` and routes to `AuthScreen` or `HomeShell` (NavigationBar with 5 tabs: Dashboard / Contests / Progress / Cards / Friends; Settings via AppBar icon).

## Platform keys

Everything is keyed by a normalized platform id: `codeforces`, `leetcode`, `codechef`, `atcoder`, `gfg`. Contest platform strings from CLIST (e.g. `codeforces.com`) are normalized in the app via `_key()`.

## Environments

- **Android device/emulator:** backend at `http://10.0.2.2:3000` (emulator) or the PC's LAN IP (real phone; requires a Windows firewall inbound rule for port 3000)
- **Web (`flutter run -d chrome`):** backend at `http://localhost:3000`; reminders are disabled behind `kIsWeb` guards
- **Android build:** requires NDK `27.0.12077973` and core-library desugaring (see `05` decision #6); configured in the local `android/app/build.gradle.kts`
