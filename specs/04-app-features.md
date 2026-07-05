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
- **Activity heatmap card** (`activity_heatmap.dart`): LeetCode-style contribution calendar merging **every platform's submissions into one grid** (`/api/heatmap`, past 365 days). Header shows bold stats - total submissions in the past year, **total active days**, **max streak** (longest run of consecutive active days); months render as separate blocks with the label **below** each block and gaps in between; 4-level intensity ramp in the theme's primary color; horizontally scrollable, auto-scrolled to the current month; **tap a cell** for the per-platform breakdown (`Sat, Mar 14, 2026 - 7 submissions - CF 3 - LC 3 - CC 1`). Hidden until at least one platform has data; GFG is excluded (no public per-day history). Day cells use UTC dates (see `05` #14-15)
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

- **Android**: full feature set (requires NDK 27 + desugaring, see `05` #6)
- **Web**: works for development; reminders/notifications disabled behind `kIsWeb` guards; logos work via the backend proxy (see `05` #10)
