import cors from "cors"
import express from "express"
import { createAuthRouter } from "./auth/routes.js"
import { createMeRouter } from "./routes/me.js"
import { cache } from "./cache.js"
import {
  getAtCoderHeatmap,
  getAtCoderProfile,
  getAtCoderRecentActivity,
} from "./services/atcoder.js"
import { getUpcomingContests } from "./services/clist.js"
import { getCodeChefProfile, getCodeChefRecentActivity } from "./services/codechef.js"
import {
  getCodeforcesHeatmap,
  getCodeforcesProfile,
  getCodeforcesRecentActivity,
  getCodeforcesRecentSolved,
  getCodeforcesTopics,
} from "./services/codeforces.js"
import { getGfgProfile } from "./services/gfg.js"
import {
  getLeetCodeHeatmap,
  getLeetCodeProfile,
  getLeetCodeRecentActivity,
  getLeetCodeTopics,
} from "./services/leetcode.js"
import { getSnapshots, recordSnapshot } from "./services/snapshots.js"

const PROFILE_TTL_SECONDS = 6 * 60 * 60 // profiles change slowly; be gentle with sources
const FRESH_COOLDOWN_SECONDS = 5 * 60 // forced refresh still waits 5 min between real fetches
const CONTESTS_TTL_SECONDS = 3 * 60 * 60
const SOLVED_TTL_SECONDS = 60 * 60
const ACTIVITY_TTL_SECONDS = 10 * 60 // per-solve history powers "just solved" updates
const ACTIVITY_FRESH_COOLDOWN_SECONDS = 60
const HEATMAP_TTL_SECONDS = 6 * 60 * 60 // a year of history changes slowly
const HEATMAP_FRESH_COOLDOWN_SECONDS = 5 * 60
const TOPICS_TTL_SECONDS = 6 * 60 * 60 // tag distributions shift slowly
const TOPICS_FRESH_COOLDOWN_SECONDS = 5 * 60

const PLATFORMS = {
  codeforces: getCodeforcesProfile,
  leetcode: getLeetCodeProfile,
  codechef: getCodeChefProfile,
  atcoder: getAtCoderProfile,
  gfg: getGfgProfile,
}

// Platforms with per-submission history. GFG is the only one without any
// public history, so the app falls back to daily snapshot deltas for it.
// CodeChef's comes from scraping its recent-activity table, so it is the
// most fragile of the four - failures degrade to the snapshot fallback.
const ACTIVITY_PLATFORMS = {
  codeforces: getCodeforcesRecentActivity,
  leetcode: getLeetCodeRecentActivity,
  codechef: getCodeChefRecentActivity,
  atcoder: getAtCoderRecentActivity,
}

// Fetch a profile through the cache; every fresh fetch also records a daily
// snapshot so the app can draw progress graphs and streaks over time.
// Pass fresh=true (user pulled to refresh) to bypass the TTL, limited by a
// 5-minute cooldown so repeated pulls don't hammer the platforms.
function fetchProfileCached(platform, handle, { fresh = false } = {}) {
  return cache.wrap(
    `profile:${platform}:${handle}`,
    PROFILE_TTL_SECONDS,
    async () => {
      const profile = await PLATFORMS[platform](handle)
      recordSnapshot(platform, handle, profile).catch((err) =>
        console.error(`snapshot failed for ${platform}:${handle}:`, err.message),
      )
      return profile
    },
    fresh ? { maxAgeSeconds: FRESH_COOLDOWN_SECONDS } : undefined,
  )
}

// Per-day submission counts (UTC dates) for the unified heatmap.
// Codeforces/AtCoder are counted from raw submission lists, LeetCode ships
// its own ready-made calendar, and CodeChef's heatmap is already extracted
// by the profile scrape (so it reuses the cached profile - note its dates
// come from CodeChef in IST rather than UTC). GFG has no public per-day
// history, so it is the one platform missing from the merged view.
const HEATMAP_PLATFORMS = {
  codeforces: getCodeforcesHeatmap,
  leetcode: (handle) => getLeetCodeHeatmap(handle),
  codechef: async (handle, sinceMs) => {
    const profile = await fetchProfileCached("codechef", handle)
    const days = {}
    for (const entry of profile.heatmap ?? []) {
      const date = String(entry.date ?? "").slice(0, 10)
      const count = Number(entry.value ?? entry.submissions ?? 0)
      if (!date || !Number.isFinite(count) || count <= 0) continue
      const at = Date.parse(date + "T00:00:00Z")
      if (Number.isFinite(at) && at < sinceMs) continue
      days[date] = (days[date] ?? 0) + count
    }
    return days
  },
  atcoder: getAtCoderHeatmap,
}

// Topic-wise breakdown of solved problems (like leetcode.com/progress).
// LeetCode ships tag counts + the Easy/Medium/Hard split via GraphQL;
// Codeforces tags are aggregated from the submission history. CodeChef,
// AtCoder and GFG expose no public per-problem tags -> { supported: false }.
const TOPIC_PLATFORMS = {
  leetcode: getLeetCodeTopics,
  codeforces: getCodeforcesTopics,
}

function wantsFresh(req) {
  const value = req.query.fresh
  return value === "1" || value === "true"
}

export function createApp({ repos = null, config = {}, importer = null } = {}) {
  const app = express()
  // Restrict browser origins in production via CORS_ORIGINS (see PRODUCTION.md).
  app.use(
    cors(config.corsOrigins?.length ? { origin: config.corsOrigins } : undefined),
  )
  app.use(express.json({ limit: "64kb" }))

  // Account & per-user routes need PostgreSQL; without DATABASE_URL the
  // backend still serves the public profile/contest endpoints.
  if (repos) {
    app.use("/api/auth", createAuthRouter({ repos, config }))
    app.use("/api/me", createMeRouter({ repos, config, importer }))
  } else {
    app.use(["/api/auth", "/api/me"], (_req, res) =>
      res.status(503).json({ error: "Accounts are not configured (DATABASE_URL is unset)" }),
    )
  }

  app.get("/health", (_req, res) => res.json({ ok: true }))

  // Single profile: GET /api/profile/codeforces/tourist[?fresh=1]
  app.get("/api/profile/:platform/:handle", async (req, res) => {
    const { platform, handle } = req.params
    if (!PLATFORMS[platform]) {
      return res.status(400).json({
        error: `Unsupported platform '${platform}'. Supported: ${Object.keys(PLATFORMS).join(", ")}`,
      })
    }
    try {
      res.json(await fetchProfileCached(platform, handle, { fresh: wantsFresh(req) }))
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Batch: GET /api/profiles?codeforces=tourist&leetcode=neal_wu[&fresh=1]
  app.get("/api/profiles", async (req, res) => {
    const fresh = wantsFresh(req)
    const entries = Object.entries(req.query).filter(([platform]) => PLATFORMS[platform])
    const settled = await Promise.allSettled(
      entries.map(([platform, handle]) => fetchProfileCached(platform, String(handle), { fresh })),
    )
    res.json({
      profiles: settled.map((result, i) => ({
        platform: entries[i][0],
        handle: entries[i][1],
        ...(result.status === "fulfilled" ? { data: result.value } : { error: result.reason.message }),
      })),
    })
  })

  // Per-solve activity with timestamps for the weekly-progress chart:
  // GET /api/activity/:platform/:handle?days=8[&fresh=1]
  // Covers the whole window even for handles linked mid-week. Platforms without
  // public history return { supported: false } and the app uses snapshot deltas.
  app.get("/api/activity/:platform/:handle", async (req, res) => {
    const { platform, handle } = req.params
    if (!PLATFORMS[platform]) {
      return res.status(400).json({ error: `Unsupported platform '${platform}'` })
    }
    const fetchActivity = ACTIVITY_PLATFORMS[platform]
    if (!fetchActivity) {
      return res.json({ supported: false, solves: [] })
    }
    const days = Math.min(Math.max(Number(req.query.days) || 7, 1), 31)
    const sinceMs = Date.now() - days * 24 * 60 * 60 * 1000
    try {
      const solves = await cache.wrap(
        `activity:${platform}:${handle}:${days}`,
        ACTIVITY_TTL_SECONDS,
        () => fetchActivity(handle, sinceMs),
        wantsFresh(req) ? { maxAgeSeconds: ACTIVITY_FRESH_COOLDOWN_SECONDS } : undefined,
      )
      res.json({ supported: true, solves })
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Unified heatmap source: GET /api/heatmap/:platform/:handle?days=365[&fresh=1]
  // Returns { supported, days: { "yyyy-mm-dd": submissionCount } } with UTC
  // dates. The app merges every linked platform's map into one calendar.
  app.get("/api/heatmap/:platform/:handle", async (req, res) => {
    const { platform, handle } = req.params
    if (!PLATFORMS[platform]) {
      return res.status(400).json({ error: `Unsupported platform '${platform}'` })
    }
    const fetchHeatmap = HEATMAP_PLATFORMS[platform]
    if (!fetchHeatmap) {
      return res.json({ supported: false, days: {} })
    }
    const daysBack = Math.min(Math.max(Number(req.query.days) || 365, 1), 366)
    const sinceMs = Date.now() - daysBack * 24 * 60 * 60 * 1000
    try {
      const days = await cache.wrap(
        `heatmap:${platform}:${handle}:${daysBack}`,
        HEATMAP_TTL_SECONDS,
        () => fetchHeatmap(handle, sinceMs),
        wantsFresh(req) ? { maxAgeSeconds: HEATMAP_FRESH_COOLDOWN_SECONDS } : undefined,
      )
      res.json({ supported: true, days })
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Topic categorization of solved problems:
  // GET /api/topics/:platform/:handle[?fresh=1]
  // -> { supported, topics: [{ tag, solved }], difficulty? } where difficulty
  // is LeetCode's Easy/Medium/Hard split. Codeforces counts each solved
  // problem once per tag, so topic totals intentionally overlap.
  app.get("/api/topics/:platform/:handle", async (req, res) => {
    const { platform, handle } = req.params
    if (!PLATFORMS[platform]) {
      return res.status(400).json({ error: `Unsupported platform '${platform}'` })
    }
    const fetchTopics = TOPIC_PLATFORMS[platform]
    if (!fetchTopics) {
      return res.json({ supported: false, topics: [] })
    }
    try {
      const result = await cache.wrap(
        `topics:${platform}:${handle}`,
        TOPICS_TTL_SECONDS,
        () => fetchTopics(handle),
        wantsFresh(req) ? { maxAgeSeconds: TOPICS_FRESH_COOLDOWN_SECONDS } : undefined,
      )
      res.json({ supported: true, ...result })
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Upcoming contests across platforms
  app.get("/api/contests", async (_req, res) => {
    try {
      const contests = await cache.wrap("contests", CONTESTS_TTL_SECONDS, getUpcomingContests)
      res.json({ contests })
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Platform logos, proxied server-side. Browsers block the favicon CDNs with
  // CORS errors when the web app fetches them directly; servers are exempt from
  // CORS, so we fetch here once, cache the bytes, and serve them same-origin.
  // Each platform has several candidate sources because no single favicon
  // service covers every site (e.g. Google's CDN 404s for leetcode.com).
  const FAVICON_BASE = "https://www.google.com/s2/favicons?sz=64&domain="
  const DDG_ICON_BASE = "https://icons.duckduckgo.com/ip3/"

  const LOGO_DOMAINS = {
    codeforces: "codeforces.com",
    leetcode: "leetcode.com",
    codechef: "codechef.com",
    atcoder: "atcoder.jp",
    gfg: "geeksforgeeks.org",
  }

  // Preferred direct PNG sources tried before the generic favicon services
  // (PNG decodes everywhere, unlike some .ico files).
  const EXTRA_LOGO_URLS = {
    leetcode: [
      "https://assets.leetcode.com/static_assets/public/icons/favicon-96x96.png",
      "https://leetcode.com/favicon.ico",
    ],
  }

  function logoCandidates(platform) {
    const domain = LOGO_DOMAINS[platform]
    const dotIco = ".ico"
    return [
      ...(EXTRA_LOGO_URLS[platform] || []),
      FAVICON_BASE + domain,
      DDG_ICON_BASE + domain + dotIco,
    ]
  }

  const LOGO_TTL_MS = 7 * 24 * 60 * 60 * 1000 // logos basically never change
  const logoCache = new Map() // platform -> { buffer, type, at }

  async function fetchLogo(platform) {
    const errors = []
    for (const url of logoCandidates(platform)) {
      try {
        const response = await fetch(url, {
          headers: { "User-Agent": "Mozilla/5.0 (CodeTrack logo proxy)" },
        })
        if (!response.ok) {
          errors.push(`${url} -> ${response.status}`)
          continue
        }
        const type = response.headers.get("content-type") || "image/png"
        if (!type.includes("image")) {
          errors.push(`${url} -> not an image (${type})`)
          continue
        }
        const buffer = Buffer.from(await response.arrayBuffer())
        if (buffer.length === 0) {
          errors.push(`${url} -> empty body`)
          continue
        }
        return { buffer, type }
      } catch (err) {
        errors.push(`${url} -> ${err.message}`)
      }
    }
    throw new Error(`all logo sources failed: ${errors.join("; ")}`)
  }

  app.get("/api/logo/:platform", async (req, res) => {
    const { platform } = req.params
    if (!LOGO_DOMAINS[platform]) {
      return res.status(404).json({ error: `Unknown platform '${platform}'` })
    }
    const cached = logoCache.get(platform)
    if (cached && Date.now() - cached.at < LOGO_TTL_MS) {
      return res
        .type(cached.type)
        .set("Cache-Control", "public, max-age=86400")
        .send(cached.buffer)
    }
    try {
      const { buffer, type } = await fetchLogo(platform)
      logoCache.set(platform, { buffer, type, at: Date.now() })
      res.type(type).set("Cache-Control", "public, max-age=86400").send(buffer)
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Daily progress snapshots (recorded automatically on fresh profile fetches)
  app.get("/api/snapshots/:platform/:handle", async (req, res) => {
    const { platform, handle } = req.params
    res.json({ snapshots: await getSnapshots(platform, handle) })
  })

  // Recently solved Codeforces problems - used for auto-generated flashcards
  app.get("/api/solved/codeforces/:handle", async (req, res) => {
    const { handle } = req.params
    const limit = Math.min(Number(req.query.limit) || 20, 100)
    try {
      const problems = await cache.wrap(
        `solved:codeforces:${handle}:${limit}`,
        SOLVED_TTL_SECONDS,
        () => getCodeforcesRecentSolved(handle, limit),
      )
      res.json({ problems })
    } catch (err) {
      res.status(502).json({ error: err.message })
    }
  })

  // Friend leaderboard: GET /api/leaderboard?platform=codeforces&handles=a,b,c
  app.get("/api/leaderboard", async (req, res) => {
    const platform = String(req.query.platform || "codeforces")
    if (!PLATFORMS[platform]) {
      return res.status(400).json({ error: `Unsupported platform '${platform}'` })
    }
    const handles = String(req.query.handles || "")
      .split(",")
      .map((h) => h.trim())
      .filter(Boolean)
    if (handles.length === 0) {
      return res
        .status(400)
        .json({ error: "Provide handles as a comma-separated 'handles' query param" })
    }
    const settled = await Promise.allSettled(handles.map((h) => fetchProfileCached(platform, h)))
    const leaderboard = settled
      .map((result, i) =>
        result.status === "fulfilled"
          ? {
              handle: handles[i],
              rating: result.value.rating ?? null,
              solvedCount: result.value.solvedCount ?? null,
            }
          : { handle: handles[i], rating: null, solvedCount: null, error: result.reason.message },
      )
      .sort(
        (a, b) =>
          (b.rating ?? -1) - (a.rating ?? -1) || (b.solvedCount ?? -1) - (a.solvedCount ?? -1),
      )
    res.json({ platform, leaderboard })
  })

  // Uniform JSON error handler (auth/me routes forward errors here).
  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    console.error(err)
    res.status(500).json({ error: "Internal server error" })
  })

  return app
}
