import axios from "axios"

const HISTORY_BASE = "https://atcoder.jp/users/"
const AC_RANK_URL = "https://kenkoooo.com/atcoder/atcoder-api/v3/user/ac_rank"
const SUBMISSIONS_URL = "https://kenkoooo.com/atcoder/atcoder-api/v3/user/submissions"
const UA = { "User-Agent": "Mozilla/5.0 (compatible; CodeTrack/0.1)" }

export async function getAtCoderProfile(handle) {
  // Official (undocumented but stable) rating history JSON from atcoder.jp
  const historyUrl = HISTORY_BASE + encodeURIComponent(handle) + "/history/json"
  let history
  try {
    const response = await axios.get(historyUrl, { headers: UA, timeout: 15000 })
    history = response.data
  } catch {
    throw new Error(`AtCoder user '${handle}' not found or atcoder.jp unreachable`)
  }
  if (!Array.isArray(history)) throw new Error(`AtCoder user '${handle}' not found`)

  const rated = history.filter((h) => h.IsRated)
  const rating = rated.length > 0 ? rated[rated.length - 1].NewRating : null
  const maxRating = rated.reduce((best, h) => Math.max(best, h.NewRating), 0) || null

  // Solved count from the community-run kenkoooo "AtCoder Problems" API
  let solvedCount = null
  try {
    const { data } = await axios.get(AC_RANK_URL, {
      params: { user: handle },
      headers: UA,
      timeout: 15000,
    })
    solvedCount = data?.count ?? null
  } catch {
    // kenkoooo being down should not break the whole profile
  }

  return {
    platform: "atcoder",
    handle,
    rating,
    maxRating,
    contestsAttended: rated.length,
    solvedCount,
    ratingHistory: rated.map((h) => ({
      contest: h.ContestName,
      at: Math.floor(new Date(h.EndTime).getTime() / 1000),
      newRating: h.NewRating,
    })),
  }
}

/**
 * Accepted solves since sinceMs via kenkoooo's submissions API, deduplicated
 * per problem (earliest AC kept). [{ id, at }] with `at` in epoch ms.
 */
export async function getAtCoderRecentActivity(handle, sinceMs) {
  const { data } = await axios.get(SUBMISSIONS_URL, {
    params: { user: handle, from_second: Math.floor(sinceMs / 1000) },
    headers: UA,
    timeout: 15000,
  })
  if (!Array.isArray(data)) {
    throw new Error(`AtCoder submissions unavailable for '${handle}'`)
  }
  const earliest = new Map()
  for (const sub of data) {
    if (sub.result !== "AC") continue
    const at = sub.epoch_second * 1000
    const prev = earliest.get(sub.problem_id)
    if (prev === undefined || at < prev) earliest.set(sub.problem_id, at)
  }
  return [...earliest.entries()].map(([id, at]) => ({ id, at }))
}
