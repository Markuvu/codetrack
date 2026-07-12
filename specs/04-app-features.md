# 04 - App Features Implemented

State of the Flutter app as of v0.4.x (July 2026).

## Auth (server-backed)

- Combined **login / signup** screen shown before the app when logged out (`auth_screen.dart`); defaults to login if this device signed in before
- Accounts live on the backend (PostgreSQL, bcrypt hashes); the app holds a short-lived JWT access token + rotating refresh token in **platform secure storage** (Keystore/Keychain via `flutter_secure_storage`), never SharedPreferences
- Name/email are cached in SharedPreferences **for display only**; tokens refresh transparently in `AuthService.accessToken()`
- Settings -> Account: edit **Name** (synced to server), view email, **Change password** (revokes all sessions, re-logs-in this device), **Log out** (revokes the refresh token)
- Settings -> CodeChef solutions: trigger/poll the server-side import of the linked CodeChef handle's submissions and browse imported source code (`submissions_screen.dart`)
- Linked handles are mirrored to `/api/me/handles` (best-effort two-way merge on dashboard load; local copy keeps working offline)

## Dashboard (tab 1)

Redesigned to match a purple-dark mockup (commit `21ef1d4a`):

- Greeting ("Hey, <name>") - prefers the account name, falls back to first handle
- **Overview hero card**: streak headline (flame emoji in a tinted rounded square + `N day streak` + a motivational subline - same data/logic as the home-screen widget: consecutive active days from the merged heatmap, UTC, counting up to yesterday when today has no solves yet) over a slim three-stat row (**Solved / Contests / Platforms**) separated by hairline dividers. This replaced the old icon-tile Overview card *and* a short-lived separate streak card with per-day tiles: day tiles were dropped because both rolling-7-day and Mon-Sun tile layouts confused or contradicted the streak number at week boundaries - the headline number is the single source of truth, and the calendar-week story belongs to the Weekly Progress card
- **Horizontal platform cards** (175px wide): real platform logo, headline metric (Rating, or Coding Score for GFG), sub-stats per platform (**LeetCode shows Peak / Rank / Solved** - peak is derived as the highest point of the contest-rating history since LeetCode exposes no `maxRating`, and long global ranks are compacted like `#40.7K`; other platforms show two sub-stats), rating **sparkline** (last 25 points of `ratingHistory` - CF, LC via `userContestRankingHistory`, CC via `all_rating`, AtCoder), badge pill (CF rank, LC top-%, CC stars, AtCoder max, GFG streak), "+ Add handle" empty state
- **Card ordering**: rated platforms first, then GFG with a coding score (it has no contest rating), then connected-but-unrated (incl. loading/errored), then unconnected last; ties keep the canonical order (CF, LC, CC, AtCoder, GFG)
- **Weekly Progress card**: Mon-Sun bar chart of problems solved per day + **goal ring** with `solved / goal`, percent, and a pace message. Codeforces / LeetCode / CodeChef / AtCoder counts come from **real per-submission history** (`/api/activity`), bucketed in the device's local timezone, so the whole week is covered even if a handle was linked mid-week; GFG has no public history and falls back to daily snapshot deltas. Goal is editable (pencil icon), stored locally (`weekly_goal`, default 50)
- **Activity heatmap card** (`activity_heatmap.dart`): LeetCode-style contribution calendar merging **every platform's submissions into one grid** (`/api/heatmap`, past 365 days). Header shows bold stats - total submissions in the past year, **total active days**, **max streak** (longest run of consecutive active days); months render as separate blocks with the label **below** each block and gaps in between; 4-level intensity ramp in the theme's primary color; horizontally scrollable, auto-scrolled to the current month; **tap a cell** for the per-platform breakdown (`Sat, Mar 14, 2026 - 7 submissions - CF 3 - LC 3 - CC 1`). Hidden until at least one platform has data; GFG is excluded (no public per-day history). Day cells use UTC dates (see `05` #14-15)
- **Recent Solves feed**: merged list of the latest accepted solves across all linked platforms (activity window, last ~8 days), newest first, up to 8 rows - platform logo, problem name, and relative time (`LeetCode - 2h ago`); built from the same enriched `/api/activity` data (`{ id, name, url, at }`) as Weekly Progress. AtCoder rows show problem **ids** (kenkoooo exposes no titles); GFG is absent (no public history). Hidden when there are no solves in the window
- **Upcoming Contests preview**: next 3 contests with month/day date boxes and countdown; **View all** button and tapping any row jumps to the Contests tab
- Pull-to-refresh forces fresh fetches (`fresh=1`) so a solve from moments ago shows up immediately
- Tap a card to add/edit that platform's handle
- Tabs live in an `IndexedStack`, so dashboard state (and card order) survives tab switches - no refetch/reshuffle when returning

## Home-screen widget (Android)

- **Animated launcher widget** (`home_widget` package + native `CodeTrackWidgetProvider`): a `ViewFlipper` auto-cycles every 4s with slide transitions between three panes, each laid out as a **big emoji icon + label / value / subline** column:
  - **\uD83D\uDD25 Current streak** - consecutive active days from the merged heatmap (UTC days; counts up to yesterday if today has no solves yet), with a **motivational subline**: celebrates when today is already active, otherwise nudges "Solve one today to keep it alive" (or "Solve a problem to start one" at streak 0)
  - **\uD83D\uDCC8 Weekly progress** - `solved / goal - pct%` plus a tinted progress bar
  - **\u23F0 Next reminder** - the **platform name** as the headline (short and readable vs. long contest titles) with the notify time underneath (`Notifies Sat, 7:30 PM`); empty state "No reminders / Tap a contest bell to set one"
- Pane emoji are set **from Kotlin** (`setTextViewText`), not in the layout XML: AAPT silently drops 4-byte emoji (UTF-16 surrogate pairs) from XML string attributes, so only BMP characters like \u23F0 survive there
- Tapping the widget opens the app; **gradient** dark rounded background (135deg, `#2A2440` -> `#17151F`) matching the app theme
- Data flow: `lib/services/widget_sync.dart` saves `streak_text` / `streak_sub` / `progress_text` / `progress_pct` / `reminder_platform` / `reminder_time` via `HomeWidget.saveWidgetData` and triggers a widget update. Synced after every Dashboard refresh (which also passes whether today is active, for the streak subline), on weekly-goal edits, and whenever reminders are set / cancelled / pruned; also refreshed by the system every 30 min (`updatePeriodMillis`)
- Sync is fire-and-forget: no-ops on web and swallows errors, so the app never breaks if the native side isn't installed
- Native files (Kotlin provider, layout, widget info, background drawable) are **committed under `app/android/...`** even though the rest of `android/` is machine-local; manifest receiver registration + package-name check are manual steps documented in `app/README.md`

## Contests (tab 2)

- Aggregated upcoming contests (CLIST) with a **segmented platform filter bar**: one fixed row of equal-width tiles ("All" + one per platform), each showing the logo and its contest count; the selected tile is tinted/outlined in the platform color, tapping the active tile clears the filter, and a caption under the bar names the active filter with the visible count. Never wraps or scrolls, regardless of platform count
- Logos render on a light disc (`PlatformLogo(backdrop: true)`) so dark logos (AtCoder's black crest) stay visible on the dark theme - used in the filter bar and contest cards
- Colored cards: platform logo, name, local start time, duration, platform pill, live countdown pill
- **Reminders** (Android only; snackbar explains on web):
  - Bell -> bottom sheet lead-time picker: 10 min / 30 min / 1 h / 1 day before (past options disabled)
  - Confirmation snackbar states the exact local notification time
  - **Manage reminders** sheet (edit-bell icon): list of scheduled reminders with notify times + cancel buttons; expired ones auto-pruned
  - Persisted in prefs (`scheduled_reminders`); notification ids derived from contest id + lead time
  - **Hardened scheduling**: reminders use **exact alarms** (`exactAllowWhileIdle`) and silently fall back to inexact scheduling if the exact-alarm permission is denied; on Android 12+ the app requests the "Alarms & reminders" permission during init (opens system settings). Boot-persistence receivers + `SCHEDULE_EXACT_ALARM` / `RECEIVE_BOOT_COMPLETED` manifest steps are documented in `app/README.md` (the `android/` folder is machine-local, not committed)
  - Every reminder change also updates the home-screen widget's "next reminder" pane

## Progress (tab 3)

- **Segmented platform bar** of linked handles only (logo + CF/LC/CC/AC/GFG shorthand), same pattern as Contests/Friends; caption shows the active platform + handle. Tiles are **ordered the same way as the Dashboard cards** (rated first, then GFG with a score, then unrated; canonical order for ties)
- **Pull-to-refresh and the refresh button both force fresh fetches** (`fresh=1`), bypassing the 6h profile cache
- **Stats card**: Rating (Coding Score for GFG) / **Peak** (trophy icon; `maxRating`, or highest point of the rating history for LeetCode; hidden for GFG) / Solved / Streak / Tracked as icon tiles in the platform color
- **Chart card** (fl_chart line chart in the platform's color):
  - y-axis **fitted to the data range** with padding - no more dead space below the line
  - y-axis value labels + dashed gridlines at nice intervals; x-axis **date labels** (switches to month-'yy format for multi-year ranges)
  - dashed **peak-rating line** with a "Peak N" label when the peak falls inside the visible range (rating view only)
  - **touch tooltips**: rating, date, and contest name (or solved count + date)
  - gradient area fill, dots when <=30 points, **delta pill** (+/- net change from the first to the last visible point, green/red, with an explanatory tooltip)
  - **Rating / Solved toggle** (SegmentedButton) when both series have data; auto-falls back to solved-over-time when there's no rating history
- **Solved by Topic card** (modeled on leetcode.com/progress, via `/api/topics`):
  - **LeetCode**: Easy / Medium / Hard split as green/amber/red count tiles, then per-tag bars from the skillStats tag buckets
  - **Codeforces**: per-tag bars aggregated from the submission history; the caption notes that a problem counts once per tag, so totals overlap
  - Horizontal bars scaled to the top topic, in the platform color, count on the right; shows the **top 10** with a `Show all N topics` toggle
  - Best-effort: hidden for platforms without tag data (CodeChef / AtCoder / GFG) and on fetch failure - never blocks the rest of the tab
- Friendlier empty states (no linked handles / not enough snapshot data yet)

## Cards / Flashcards (tab 4)

- Spaced-repetition flashcards with **FSRS** scheduler (SM-2 kept as an alternative in `logic/`)
- Cards can be auto-seeded from recently solved Codeforces problems (`/api/solved`)
- Review flow with grading; state persisted locally

## Friends (tab 5)

- **Segmented platform bar** (same pattern as the Contests filter): one fixed row of equal-width logo tiles showing each platform's friend count; selected tile tinted/outlined in the platform color; caption underneath states platform, friend count, and ranking metric
- **Leaderboard cards**: medal badges (top 3) / numbered rank circles, **your row highlighted** (tinted + outlined + "You" pill), trailing headline stat in the platform color (rating, or solved for GFG/unrated) with solved count beneath
- **Swipe left to remove** a friend (red swipe background) with an **Undo** snackbar; long-press still works as an alternative; removal updates the list locally without a refetch
- Extended **Add friend** FAB; improved empty state with icon + call-to-action (mentions linking your own handle when missing)
- Per-platform friend lists (`friends_<platform>` in prefs); errors per row (bad handle shows inline and doesn't break the list)

## Settings

- Account section (name / email / change password / log out)
- Backend URL override (default `http://10.0.2.2:3000`)

## Platform support

- **Android**: full feature set (requires NDK 27 + desugaring, see `05` #6; exact-alarm + boot-receiver + widget manifest steps in `app/README.md`)
- **Web**: works for development; reminders/notifications and the home-screen widget are disabled behind `kIsWeb` guards; logos work via the backend proxy (see `05` #10)
