import axios from "axios"

const BASE = "https://codeforces.com/api"
const CONTEST_URL_BASE = "https://codeforces.com/contests/"
const PROBLEM_URL_BASE = "https://codeforces.com/contest/"
const MIN_INTERVAL_MS = 2100 // Codeforces allows at most 1 request per 2 seconds

// Serialize all Codeforces calls through one queue so the rate limit is
// respected no matter how many users hit our API at once.
let queue = Promise.resolve()
let lastCallAt = 0

function cfGet(method, params) {
  const run = async () => {
    const wait = Math.max(0, lastCallAt + MIN_INTERVAL_MS - Date.now())
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait))
    lastCallAt = Date.now()
    const { data } = await axios.get(`${BASE}/${method}`, { params, timeout: 15000 })
    if (data.status !== "OK") throw new Error(data.comment || `Codeforces ${method} failed`)
    return data.result
  }
  const result = queue.then(run, run)
  queue = result.catch(() => {})
  return result
}

export async function getCodeforcesProfile(handle) {
  const [user] = await cfGet("user.info", { handles: handle })
  const ratings = await cfGet("user.rating", { handle })
  const submissions = await cfGet("user.status", { handle, from: 1, count: 3000 })

  const solved = new Set()
  for (const sub of submissions) {
    if (sub.verdict === "OK" && sub.problem) {
      solved.add(`${sub.problem.contestId}-${sub.problem.index}`)
    }
  }

  return {
    platform: "codeforces",
    handle: user.handle,
    rating: user.rating ?? null,
    maxRating: user.maxRating ?? null,
    rank: user.rank ?? "unrated",
    maxRank: user.maxRank ?? null,
    contestsAttended: ratings.length,
    solvedCount: solved.size,
    ratingHistory: ratings.map((r) => ({
      contest: r.contestName,
      at: r.ratingUpdateTimeSeconds,
      newRating: r.newRating,
    })),
  }
}

/** Most recently solved problems, deduplicated - used for auto-flashcards. */
export async function getCodeforcesRecentSolved(handle, limit = 20) {
  const submissions = await cfGet("user.status", { handle, from: 1, count: 1000 })
  const seen = new Set()
  const problems = []
  for (const sub of submissions) {
    if (sub.verdict !== "OK" || !sub.problem || !sub.problem.contestId) continue
    const key = `${sub.problem.contestId}-${sub.problem.index}`
    if (seen.has(key)) continue
    seen.add(key)
    problems.push({
      id: key,
      name: sub.problem.name,
      rating: sub.problem.rating ?? null,
      tags: sub.problem.tags ?? [],
      solvedAt: sub.creationTimeSeconds,
      url: PROBLEM_URL_BASE + sub.problem.contestId + "/problem/" + sub.problem.index,
    })
    if (problems.length >= limit) break
  }
  return problems
}

/**
 * Accepted solves since sinceMs, deduplicated per problem (earliest AC kept).
 * Powers the weekly-progress chart and the recent-activity feed:
 * [{ id, name, url, at }] with `at` in epoch ms.
 */
export async function getCodeforcesRecentActivity(handle, sinceMs) {
  const submissions = await cfGet("user.status", { handle, from: 1, count: 1000 })
  const earliest = new Map()
  for (const sub of submissions) {
    if (sub.verdict !== "OK" || !sub.problem) continue
    const at = sub.creationTimeSeconds * 1000
    if (at < sinceMs) continue
    const key = `${sub.problem.contestId}-${sub.problem.index}`
    const prev = earliest.get(key)
    if (prev === undefined || at < prev.at) {
      earliest.set(key, {
        at,
        name: sub.problem.name ?? key,
        url: sub.problem.contestId
          ? PROBLEM_URL_BASE + sub.problem.contestId + "/problem/" + sub.problem.index
          : null,
      })
    }
  }
  return [...earliest.entries()].map(([id, solve]) => ({
    id,
    name: solve.name,
    url: solve.url,
    at: solve.at,
  }))
}

/**
 * ALL submissions per UTC day since sinceMs, for the unified heatmap.
 * Counts every submission (any verdict), matching how the platforms' own
 * heatmaps count activity. Pages through user.status and stops as soon as
 * submissions older than the window appear. Returns { "yyyy-mm-dd": count }.
 */
export async function getCodeforcesHeatmap(handle, sinceMs) {
  const days = {}
  const pageSize = 2000
  let from = 1
  for (let page = 0; page < 3; page++) {
    const submissions = await cfGet("user.status", { handle, from, count: pageSize })
    if (!Array.isArray(submissions) || submissions.length === 0) break
    let reachedOlder = false
    for (const sub of submissions) {
      const at = (sub.creationTimeSeconds ?? 0) * 1000
      if (at < sinceMs) {
        reachedOlder = true
        continue
      }
      const date = new Date(at).toISOString().slice(0, 10)
      days[date] = (days[date] ?? 0) + 1
    }
    if (reachedOlder || submissions.length < pageSize) break
    from += pageSize
  }
  return days
}

/**
 * Topic-wise solved counts aggregated from the submission history: every
 * uniquely solved problem contributes each of its Codeforces tags once.
 * Problems usually carry several tags, so the counts intentionally sum to
 * more than solvedCount. Returns { topics: [{ tag, solved }] } sorted by
 * count descending.
 */
export async function getCodeforcesTopics(handle) {
  const submissions = await cfGet("user.status", { handle, from: 1, count: 5000 })
  const seen = new Set()
  const counts = new Map()
  for (const sub of submissions) {
    if (sub.verdict !== "OK" || !sub.problem) continue
    const key = `${sub.problem.contestId}-${sub.problem.index}`
    if (seen.has(key)) continue
    seen.add(key)
    for (const tag of sub.problem.tags ?? []) {
      counts.set(tag, (counts.get(tag) ?? 0) + 1)
    }
  }
  const topics = [...counts.entries()]
    .map(([tag, solved]) => ({ tag, solved }))
    .sort((a, b) => b.solved - a.solved)
  return { topics }
}

export async function getCodeforcesContests() {
  const contests = await cfGet("contest.list", {})
  return contests
    .filter((c) => c.phase === "BEFORE")
    .sort((a, b) => a.startTimeSeconds - b.startTimeSeconds)
    .map((c) => ({
      id: `codeforces-${c.id}`,
      platform: "codeforces.com",
      name: c.name,
      startsAt: c.startTimeSeconds,
      durationSeconds: c.durationSeconds,
      url: CONTEST_URL_BASE + c.id,
    }))
}
