import "dotenv/config"
import cors from "cors"
import express from "express"
import { cache } from "./cache.js"
import { getUpcomingContests } from "./services/clist.js"
import { getCodeChefProfile } from "./services/codechef.js"
import { getCodeforcesProfile } from "./services/codeforces.js"
import { getLeetCodeProfile } from "./services/leetcode.js"

const PROFILE_TTL_SECONDS = 6 * 60 * 60 // profiles change slowly; be gentle with sources
const CONTESTS_TTL_SECONDS = 3 * 60 * 60

const PLATFORMS = {
  codeforces: getCodeforcesProfile,
  leetcode: getLeetCodeProfile,
  codechef: getCodeChefProfile,
}

const app = express()
app.use(cors())
app.use(express.json())

app.get("/health", (_req, res) => res.json({ ok: true }))

// Single profile: GET /api/profile/codeforces/tourist
app.get("/api/profile/:platform/:handle", async (req, res) => {
  const { platform, handle } = req.params
  const fetcher = PLATFORMS[platform]
  if (!fetcher) {
    return res.status(400).json({
      error: `Unsupported platform '${platform}'. Supported: ${Object.keys(PLATFORMS).join(", ")}`,
    })
  }
  try {
    const data = await cache.wrap(`profile:${platform}:${handle}`, PROFILE_TTL_SECONDS, () =>
      fetcher(handle),
    )
    res.json(data)
  } catch (err) {
    res.status(502).json({ error: err.message })
  }
})

// Batch: GET /api/profiles?codeforces=tourist&leetcode=neal_wu
app.get("/api/profiles", async (req, res) => {
  const entries = Object.entries(req.query).filter(([platform]) => PLATFORMS[platform])
  const settled = await Promise.allSettled(
    entries.map(([platform, handle]) =>
      cache.wrap(`profile:${platform}:${handle}`, PROFILE_TTL_SECONDS, () =>
        PLATFORMS[platform](String(handle)),
      ),
    ),
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

const port = process.env.PORT || 3000
app.listen(port, () => console.log(`CodeTrack backend listening on http://localhost:${port}`))
