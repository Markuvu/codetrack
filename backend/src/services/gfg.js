import axios from "axios"

// The new GFG profile UI (geeksforgeeks.org/profile/<handle>) fetches its
// data from this JSON endpoint - the page itself no longer embeds
// __NEXT_DATA__, so scraping the HTML yields nothing.
const AUTH_API_BASE = "https://authapi.geeksforgeeks.org/api-get/user-profile-info/"
const COMMUNITY_API_BASE = "https://geeks-for-geeks-api.vercel.app/"

const HEADERS = {
  Accept: "application/json, text/plain, */*",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
  Referer: "https://www.geeksforgeeks.org/",
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

// Primary: official (undocumented) profile-info endpoint used by the GFG
// profile page itself. Returns { message, data: { score, monthly_score,
// total_problems_solved, institute_rank, pod_solved_longest_streak, ... } }.
async function fetchAuthApi(handle) {
  const url = AUTH_API_BASE + "?handle=" + encodeURIComponent(handle) + "&article_count=false"
  const response = await axios.get(url, { headers: HEADERS, timeout: 15000 })
  const data = response.data?.data
  if (!data || typeof data !== "object") {
    throw new Error("profile-info API returned no data (handle may not exist)")
  }
  return normalize(handle, {
    codingScore: data.score ?? null,
    solvedCount: data.total_problems_solved ?? null,
    instituteRank: data.institute_rank ?? null,
    longestStreak: data.pod_solved_longest_streak ?? null,
  })
}

// Fallback: community-maintained mirror API.
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
  const attempts = [
    { name: "gfg profile-info API", run: () => fetchAuthApi(handle) },
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
    "GeeksforGeeks profile for '" + handle + "' could not be fetched. Tried " + errors.join("; "),
  )
}
