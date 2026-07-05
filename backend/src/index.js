import "dotenv/config"
import cors from "cors"
import express from "express"
import { cache } from "./cache.js"
import { getAtCoderProfile } from "./services/atcoder.js"
import { getUpcomingContests } from "./services/clist.js"
import { getCodeChefProfile } from "./services/codechef.js"
import { getCodeforcesProfile, getCodeforcesRecentSolved } from "./services/codeforces.js"
import { getGfgProfile } from "./services/gfg.js"
import { getLeetCodeProfile } from "./services/leetcode.js"
import { getSnapshots, recordSnapshot } from "./services/snapshots.js"

const PROFILE_TTL_SECONDS = 6 * 60 * 60 // profiles change slowly; be gentle with sources
const CONTESTS_TTL_SECONDS = 3 * 60 * 60
const SOLVED_TTL_SECONDS = 60 * 60

const PLATFORMS = {
  codeforces: getCodeforcesProfile,
  leetcode: getLeetCodeProfile,
  codechef: getCodeChefProfile,
  atcoder: getAtCoderProfile,
  gfg: getGfgProfile,
}

// Fetch a profile through the cache; every fresh fetch also records a daily
// snapshot so the app can draw progress graphs and streaks over time.
function fetchProfileCached(platform, handle) {
  return cache.wrap(`profile:${platform}:${handle}`, PROFILE_TTL_SECONDS, async () => {
    const profile = await PLATFORMS[platform](handle)
    recordSnapshot(platform, handle, profile).catch((err) =>
      console.error(`snapshot failed for ${platform}:${handle}:`, err.message),
    )
    return profile
  })
}

const app = express()
app.use(cors())
app.use(express.json())

app.get("/health", (_req, res) => res.json({ ok: true }))

// Single profile: GET /api/profile/codeforces/tourist
app.get("/api/profile/:platform/:handle", async (req, res) => {
  const { platform, handle } = req.params
  if (!PLATFORMS[platform]) {
    return res.status(400).json({
      error: `Unsupported platform '${platform}'. Supported: ${Object.keys(PLATFORMS).join(", ")}`,
    })
  }
  try {
    res.json(await fetchProfileCached(platform, handle))
  } catch (err) {
    res.status(502).json({ error: err.message })
  }
})

// Batch: GET /api/profiles?codeforces=tourist&leetcode=neal_wu
app.get("/api/profiles", async (req, res) => {
  const entries = Object.entries(req.query).filter(([platform]) => PLATFORMS[platform])
  const settled = await Promise.allSettled(
    entries.map(([platform, handle]) => fetchProfileCached(platform, String(handle))),
  )
  res.json({
    profiles: settled.map((result, i) => ({
      platform: entries[i][0],
      handle: entries[i][1],
      ...(result.status === "fulfilled" ? { data: result.value } : { error: result.reason.message }),
    })),
  })
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

// Platform logos, proxied server-side. Browsers block the favicon CDN with
// CORS errors when the web app fetches it directly; servers are exempt from
// CORS, so we fetch here once, cache the bytes, and serve them same-origin.
const LOGO_DOMAINS = {
  codeforces: "codeforces.com",
  leetcode: "leetcode.com",
  codechef: "codechef.com",
  atcoder: "atcoder.jp",
  gfg: "geeksforgeeks.org",
}
const FAVICON_BASE = "https://www.google.com/s2/favicons?sz=64&domain="
const LOGO_TTL_MS = 7 * 24 * 60 * 60 * 1000 // logos basically never change
const logoCache = new Map() // platform -> { buffer, type, at }

app.get("/api/logo/:platform", async (req, res) => {
  const { platform } = req.params
  const domain = LOGO_DOMAINS[platform]
  if (!domain) {
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
    const response = await fetch(FAVICON_BASE + domain)
    if (!response.ok) throw new Error(`favicon fetch failed (${response.status})`)
    const buffer = Buffer.from(await response.arrayBuffer())
    const type = response.headers.get("content-type") || "image/png"
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

const port = process.env.PORT || 3000
app.listen(port, () => console.log(`CodeTrack backend listening on http://localhost:${port}`))
