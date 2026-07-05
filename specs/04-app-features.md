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
- **Horizontal platform cards** (175px wide): real platform logo, headline metric (Rating, or Coding Score for GFG), two sub-stats per platform, rating **sparkline** (last 25 points of `ratingHistory`), badge pill (CF rank, LC top-%, CC stars, AtCoder max, GFG streak), "+ Add handle" empty state
- **Weekly Progress card**: Mon-Sun bar chart of problems solved per day (computed from consecutive daily snapshot deltas across all linked platforms; a platform's first snapshot contributes nothing so new handles don't spike the chart) + **goal ring** with `solved / goal`, percent, and a pace message. Goal is editable (pencil icon), stored locally (`weekly_goal`, default 50)
- **Upcoming Contests preview**: next 3 contests with month/day date boxes and countdown; **View all** button and tapping any row jumps to the Contests tab
- Tap a card to add/edit that platform's handle; pull-to-refresh

## Contests (tab 2)

- Aggregated upcoming contests (CLIST) with **platform filter chips** (with counts and logos)
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
