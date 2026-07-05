import axios from "axios"

// LeetCode has no official public API; this uses the same GraphQL endpoint the
// website itself uses. Keep request volume low (responses are cached upstream).
const GRAPHQL_URL = "https://leetcode.com/graphql"

const HEADERS = {
  "Content-Type": "application/json",
  Referer: "https://leetcode.com",
  "User-Agent": "Mozilla/5.0 (compatible; CodeTrack/0.1)",
}

const PROFILE_QUERY = `
query userProfile($username: String!) {
  matchedUser(username: $username) {
    username
    profile { ranking reputation }
    submitStatsGlobal { acSubmissionNum { difficulty count } }
  }
  userContestRanking(username: $username) {
    attendedContestsCount
    rating
    globalRanking
    topPercentage
  }
}`

export async function getLeetCodeProfile(username) {
  const { data } = await axios.post(
    GRAPHQL_URL,
    { query: PROFILE_QUERY, variables: { username } },
    { headers: HEADERS, timeout: 15000 },
  )

  const user = data?.data?.matchedUser
  if (!user) throw new Error(`LeetCode user '${username}' not found`)

  const solvedByDifficulty = Object.fromEntries(
    (user.submitStatsGlobal?.acSubmissionNum ?? []).map((s) => [s.difficulty.toLowerCase(), s.count]),
  )
  const contest = data.data.userContestRanking

  return {
    platform: "leetcode",
    handle: user.username,
    ranking: user.profile?.ranking ?? null,
    solvedCount: solvedByDifficulty.all ?? 0,
    solvedByDifficulty,
    rating: contest ? Math.round(contest.rating) : null,
    contestsAttended: contest?.attendedContestsCount ?? 0,
    globalRanking: contest?.globalRanking ?? null,
    topPercentage: contest?.topPercentage ?? null,
  }
}

const RECENT_AC_QUERY = `
query recentAc($username: String!, $limit: Int!) {
  recentAcSubmissionList(username: $username, limit: $limit) {
    titleSlug
    timestamp
  }
}`

/**
 * Recent accepted solves with timestamps, deduplicated per problem (earliest
 * AC kept). LeetCode only exposes the latest ~100 accepted submissions, which
 * comfortably covers a week for most users. [{ id, at }] with `at` in epoch ms.
 */
export async function getLeetCodeRecentActivity(username, sinceMs) {
  const { data } = await axios.post(
    GRAPHQL_URL,
    { query: RECENT_AC_QUERY, variables: { username, limit: 100 } },
    { headers: HEADERS, timeout: 15000 },
  )
  const list = data?.data?.recentAcSubmissionList
  if (!Array.isArray(list)) throw new Error(`LeetCode user '${username}' not found`)

  const earliest = new Map()
  for (const sub of list) {
    const at = Number(sub.timestamp) * 1000
    if (!Number.isFinite(at) || at < sinceMs) continue
    const prev = earliest.get(sub.titleSlug)
    if (prev === undefined || at < prev) earliest.set(sub.titleSlug, at)
  }
  return [...earliest.entries()].map(([id, at]) => ({ id, at }))
}
