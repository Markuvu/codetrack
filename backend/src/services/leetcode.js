import axios from "axios"

// LeetCode has no official public API; this uses the same GraphQL endpoint the
// website itself uses. Keep request volume low (responses are cached upstream).
const GRAPHQL_URL = "https://leetcode.com/graphql"

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
    {
      headers: {
        "Content-Type": "application/json",
        Referer: "https://leetcode.com",
        "User-Agent": "Mozilla/5.0 (compatible; CodeTrack/0.1)",
      },
      timeout: 15000,
    },
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
