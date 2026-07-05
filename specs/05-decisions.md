# 05 - Decision Log

Key decisions and the reasoning, roughly chronological.

### 1. Thin Node backend instead of calling platforms from the app
Scraping/GraphQL/auth headers are easier in Node; one shared cache keeps us polite to the platforms; the app gets one stable, normalized API; and the browser build avoids CORS entirely for data calls. Cost: users must run (or later, we must host) the backend.

### 2. Flutter over native Android / React Native
Single codebase for Android + iOS later, plus a web target that is genuinely useful for development. Material 3 dark theme with seed color `0xFF6C5CE7`.

### 3. Local-first storage (shared_preferences), no accounts server
Handles, friends, flashcards and reminders are small, personal, and don't need a server. Keeps the backend stateless (only caches + snapshots on disk).

### 4. CLIST as the contest aggregator
One API for all platforms beats scraping four contest pages. v4 requires `resource__in` (a plain `resource=` comma list silently matches nothing - this bug shipped and was fixed in `3f60a951`). Codeforces API kept as a fallback so an expired CLIST key degrades gracefully instead of showing an empty list.

### 5. GFG via authapi endpoint, not scraping
GFG's redesigned profile has no `__NEXT_DATA__` blob; scraping broke with 502s. `authapi.geeksforgeeks.org/api-get/user-profile-info/` returns clean JSON; a community Vercel API is the fallback. GFG shows **Coding Score** instead of rating everywhere (it has no contest rating).

### 6. Android build: NDK 27 + core-library desugaring
`flutter_local_notifications` requires Java desugaring and NDK `27.0.12077973`. Configured in `android/app/build.gradle.kts` (`isCoreLibraryDesugaringEnabled = true`, `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`). Documented in `app/README.md` since gradle files are machine-local.

### 7. Web support via `kIsWeb` guards, not a separate build
Notifications don't exist on web, so reminder actions show an explanatory snackbar instead. Everything else works, making `flutter run -d chrome` the fastest iteration loop.

### 8. FSRS for flashcards (SM-2 kept as fallback)
FSRS gives better-spaced reviews than classic SM-2; both live in `logic/` so the scheduler is swappable.

### 9. Local device auth instead of server accounts (v0.3)
Sign-up/login/change-password with a salted SHA-256 hash stored on the device. Chosen because the backend isn't deployed yet - real accounts without HTTPS + a hosted DB would be security theater. Explicitly labeled in-app ("stored only on this device"); designed to be swapped for server auth + cloud sync when the backend is deployed.

### 10. Platform logos: backend proxy, not bundled assets and not direct CDN calls
Direct favicon-CDN fetches are blocked by CORS on Flutter web. Options considered: (a) bundle logo PNGs - crisp and offline but raises trademark/licensing questions and bloats the repo; (b) proxy through our backend - servers are CORS-exempt, one cached fetch serves all clients, and the app always has a colored-initial fallback. Chose (b) (`/api/logo/:platform`, commit `5b87f740`).

### 11. Multiple logo sources with validation
Google's favicon CDN 404s for `leetcode.com`. The proxy now tries direct platform PNGs first, then Google, then DuckDuckGo, validating content-type and body before caching (commit `3b82318`). A shared `PlatformLogo` widget replaced per-screen colored-letter avatars.

### 12. Reminder UX: explicit lead times + a manage list
Users couldn't tell when a reminder would fire. Bell now opens a lead-time picker (10m/30m/1h/1d), the snackbar states the exact notification time, and a manage sheet lists + cancels scheduled reminders (persisted in prefs, since the OS API can't enumerate them nicely).

### 13. Repo conventions
Single `main` branch, direct pushes (solo project). Secrets only in `backend/.env` (git-ignored, `.env.example` committed). Machine-local gradle config kept out of git.
