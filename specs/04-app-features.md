# 04 - App Features Implemented

State of the Flutter app as of v0.3.x (July 2026).

## Auth (local-only)

- Combined **login / signup** screen shown before the app when logged out (`auth_screen.dart`); defaults to login if an account exists on the device
- Password stored as salted SHA-256 (`sha256('$salt:$password')`, random 16-byte salt); never in plain text
- Settings -> Account: edit **Name**, view email, **Change password** (re-salts), **Log out**
- Account lives only on this device - no recovery, no sync (see `05` #9)

## Dashboard (tab 1)

Redesigned to match a purple-dark mockup (commit `21ef1d4a`):

- Greeting ("Hey, <name>") - prefers the account name, falls back to first handle
- **Overview card**: Problems Solved / Contests Participated / Platforms Linked icon tiles
- **Horizontal platform cards** (175px wide): real platform logo, headline metric (Rating, or Coding Score for GFG), two sub-stats per platform, rating **sparkline** (last 25 points of `ratingHistory` - CF, LC via `userContestRankingHistory`, CC via `all_rating`, AtCoder), badge pill (CF rank, LC top-%, CC stars, AtCoder max, GFG streak), "+ Add handle" empty state
- **Card ordering**: rated platforms first, then GFG with a coding score (it has no contest rating), then connected-but-unrated (incl. loading/errored), then unconnected last; ties keep the canonical order (CF, LC, CC, AtCoder, GFG)
- **Weekly Progress card**: Mon-Sun bar chart of problems solved per day + **goal ring** with `solved / goal`, percent, and a pace message. Codeforces / LeetCode / CodeChef / AtCoder counts come from **real per-submission history** (`/api/activity`), bucketed in the device's local timezone, so the whole week is covered even if a handle was linked mid-week; GFG has no public history and falls back to daily snapshot deltas. Goal is editable (pencil icon), stored locally (`weekly_goal`, default 50)
- **Upcoming Contests preview**: next 3 contests with month/day date boxes and countdown; **View all** button and tapping any row jumps to the Contests tab
- Pull-to-refresh forces fresh fetches (`fresh=1`) so a solve from moments ago shows up immediately
- Tap a card to add/edit that platform's handle
- Tabs live in an `IndexedStack`, so dashboard state (and card order) survives tab switches - no refetch/reshuffle when returning

## Contests (tab 2)

- Aggregated upcoming contests (CLIST) with a **segmented platform filter bar**: one fixed row of equal-width tiles ("All" + one per platform), each showing the logo and its contest count; the selected tile is tinted/outlined in the platform color, tapping the active tile clears the filter, and a caption under the bar names the active filter with the visible count. Never wraps or scrolls, regardless of platform count
- Logos render on a light disc (`PlatformLogo(backdrop: true)`) so dark logos (AtCoder's black crest) stay visible on the dark theme - used in the filter bar and contest cards
- Colored cards: platform logo, name, local start time, duration, platform pill, live countdown pill
- **Reminders** (Android only; snackbar explains on web):
  - Bell -> bottom sheet lead-time picker: 10 min / 30 min / 1 h / 1 day before (past options disabled)
  - Confirmation snackbar states the exact local notification time
  - **Manage reminders** sheet (edit-bell icon): list of scheduled reminders with notify times + cancel buttons; expired ones auto-pruned
  - Persisted in prefs (`scheduled_reminders`); notification ids derived from contest id + lead time

## Progress (tab 3)

- Rating-history and solved-count charts (`fl_chart`) per linked platform, backed by live `ratingHistory` plus backend daily snapshots

## Cards / Flashcards (tab 4)

- Spaced-repetition flashcards with **FSRS** scheduler (SM-2 kept as an alternative in `logic/`)
- Cards can be auto-seeded from recently solved Codeforces problems (`/api/solved`)
- Review flow with grading; state persisted locally

## Friends (tab 5)

- **Per-platform** friend lists (`friends_<platform>` in prefs) with a logo chip selector for all 5 platforms
- Leaderboard with medals, "(you)" marker, rating+solved subtitle (rating hidden for GFG / unrated), long-press to remove a friend
- Errors per row (bad handle doesn't break the list)

## Settings

- Account section (name / email / change password / log out)
- Backend URL override (default `http://10.0.2.2:3000`)

## Platform support

- **Android**: full feature set (requires NDK 27 + desugaring, see `05` #6)
- **Web**: works for development; reminders/notifications disabled behind `kIsWeb` guards; logos work via the backend proxy (see `05` #10)
