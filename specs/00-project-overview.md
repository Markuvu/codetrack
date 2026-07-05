# 00 - Project Overview

## Idea

**CodeTrack** is a mobile-first app (Flutter, Android primary + web for quick testing) that brings all of a competitive programmer's coding profiles into one place:

- **One dashboard** for Codeforces, LeetCode, CodeChef, AtCoder and GeeksforGeeks stats
- **Contest calendar** across platforms with local **reminders**
- **Progress tracking** (rating history, solved counts, daily snapshots)
- **Flashcards** with spaced repetition for revising solved problems/concepts
- **Friends leaderboard** to compare handles per platform

## Why

Each platform has its own profile page and contest page. Checking five sites daily is tedious; there is no single native app that aggregates profiles *and* contests *and* revision tooling. Existing aggregators (Codolio, StopStalk, CLIST) are web-first and don't do reminders/flashcards on-device.

## Target user

Students and competitive programmers active on 2+ platforms who want a daily driver app: check stats, know when the next contest is, get notified, and revise.

## Tech stack

| Layer | Choice | Notes |
|---|---|---|
| App | Flutter (Material 3, dark theme, seed `0xFF6C5CE7`) | Android is the primary target; web build used for quick iteration |
| Backend | Node.js + Express (`backend/`) | Thin aggregation/scraping proxy with in-memory + file caching |
| Storage (app) | `shared_preferences` | Handles, friends, flashcards, reminders, auth - all local |
| Charts | `fl_chart` | Rating sparklines + progress graphs |
| Notifications | `flutter_local_notifications` + `timezone` | Contest reminders, scheduled locally |
| Auth | Local-only (salted SHA-256 via `crypto`) | See decision log - no server accounts yet |

## Repo layout

```
codetrack/
  README.md
  specs/            <- these documents
  backend/          <- Node/Express aggregation API
    src/index.js
    src/cache.js
    src/services/   <- one module per platform + clist + snapshots
  app/              <- Flutter application
    lib/
      main.dart
      models/  services/  storage/  logic/  screens/  widgets/
```

## Status (July 2026)

v0.3.x - all five platforms integrated, contests + reminders working on Android, dashboard redesigned to mockup, local login/signup added, platform logos proxied through the backend. See `01`-`06` for details.
