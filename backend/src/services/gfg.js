import axios from "axios"
import * as cheerio from "cheerio"

const PROFILE_BASE = "https://www.geeksforgeeks.org/user/"
const UA = { "User-Agent": "Mozilla/5.0 (compatible; CodeTrack/0.1)" }

// GeeksforGeeks has no public API; the profile page is a Next.js app that
// embeds all profile data as JSON inside the __NEXT_DATA__ script tag.
export async function getGfgProfile(handle) {
  const url = PROFILE_BASE + encodeURIComponent(handle) + "/"
  let html
  try {
    const response = await axios.get(url, { headers: UA, timeout: 15000 })
    html = response.data
  } catch {
    throw new Error(`GeeksforGeeks user '${handle}' not found`)
  }

  const $ = cheerio.load(html)
  const nextData = $("#__NEXT_DATA__").html()
  if (!nextData) {
    throw new Error(
      `Could not parse GeeksforGeeks profile for '${handle}' - page layout may have changed`,
    )
  }

  let info
  try {
    info = JSON.parse(nextData)?.props?.pageProps?.userInfo
  } catch {
    info = null
  }
  if (!info) {
    throw new Error(`Could not parse GeeksforGeeks profile data for '${handle}'`)
  }

  return {
    platform: "gfg",
    handle,
    rating: null, // GFG has no contest rating; codingScore is the closest metric
    codingScore: info.score ?? null,
    solvedCount: info.total_problems_solved ?? null,
    instituteRank: info.institute_rank ?? null,
    longestStreak: info.pod_solved_longest_streak ?? null,
  }
}
