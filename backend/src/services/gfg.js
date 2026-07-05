import axios from "axios"
import * as cheerio from "cheerio"

const OLD_PROFILE_BASE = "https://www.geeksforgeeks.org/user/"
const NEW_PROFILE_BASE = "https://www.geeksforgeeks.org/profile/"
const COMMUNITY_API_BASE = "https://geeks-for-geeks-api.vercel.app/"

// GFG sits behind aggressive bot protection; a minimal UA gets blocked.
// Send a realistic browser header set.
const BROWSER_HEADERS = {
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  Accept:
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
  "Accept-Language": "en-US,en;q=0.9",
  "Cache-Control": "no-cache",
}

function normalize(handle, fields) {
  return {
    platform: "gfg",
    handle,
    rating: null, // GFG has no contest rating; codingScore is the closest metric
    codingScore: fields.codingScore ?? null,
    solvedCount: fields.solvedCount ?? null,
    instituteRank: fields.instituteRank ?? null,
    longestStreak: fields.longestStreak ?? null,
  }
}

// Strategy A/B: scrape a GFG profile page and read the JSON embedded in the
// Next.js __NEXT_DATA__ script tag.
async function scrapeProfilePage(url, handle) {
  const response = await axios.get(url, { headers: BROWSER_HEADERS, timeout: 15000 })
  const $ = cheerio.load(response.data)
  const nextData = $("#__NEXT_DATA__").html()
  if (!nextData) throw new Error("page loaded but no __NEXT_DATA__ found")

  const pageProps = JSON.parse(nextData)?.props?.pageProps ?? {}
  const info = pageProps.userInfo ?? pageProps.userData ?? pageProps.user ?? null
  if (!info) throw new Error("page loaded but profile JSON was not where expected")

  return normalize(handle, {
    codingScore: info.score ?? info.coding_score ?? info.codingScore ?? null,
    solvedCount:
      info.total_problems_solved ?? info.totalProblemsSolved ?? info.problems_solved ?? null,
    instituteRank: info.institute_rank ?? info.instituteRank ?? null,
    longestStreak: info.pod_solved_longest_streak ?? info.maxStreak ?? null,
  })
}

// Strategy C: community-maintained mirror API (github.com/... geeks-for-geeks-api).
async function fetchCommunityApi(handle) {
  const url = COMMUNITY_API_BASE + encodeURIComponent(handle)
  const response = await axios.get(url, { timeout: 15000 })
  const info = response.data?.info
  if (!info) throw new Error("community API returned no profile info")

  return normalize(handle, {
    codingScore: info.codingScore ?? null,
    solvedCount: info.totalProblemsSolved ?? null,
    instituteRank: info.instituteRank ?? null,
    longestStreak: info.maxStreak ?? null,
  })
}

export async function getGfgProfile(handle) {
  const encoded = encodeURIComponent(handle)
  const attempts = [
    { name: "gfg /user/ page", run: () => scrapeProfilePage(OLD_PROFILE_BASE + encoded + "/", handle) },
    { name: "gfg /profile/ page", run: () => scrapeProfilePage(NEW_PROFILE_BASE + encoded, handle) },
    { name: "community API", run: () => fetchCommunityApi(handle) },
  ]

  const errors = []
  for (const attempt of attempts) {
    try {
      return await attempt.run()
    } catch (err) {
      const status = err.response?.status
      errors.push(attempt.name + ": " + (status ? "HTTP " + status : err.message))
    }
  }

  throw new Error(
    "GeeksforGeeks profile for '" +
      handle +
      "' could not be fetched (GFG blocks many automated requests). Tried " +
      errors.join("; "),
  )
}
