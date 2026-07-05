import axios from "axios"
import { getCodeforcesContests } from "./codeforces.js"

// CLIST (https://clist.by) aggregates contests across nearly every judge.
// Sign up for a free API key: https://clist.by/api/v4/doc/
const CLIST_CONTESTS_URL = "https://clist.by/api/v4/contest/"
const RESOURCES = ["codeforces.com", "leetcode.com", "codechef.com", "atcoder.jp"]

export async function getUpcomingContests() {
  const { CLIST_USERNAME, CLIST_API_KEY } = process.env

  if (!CLIST_USERNAME || !CLIST_API_KEY) {
    // No CLIST credentials: fall back to the official Codeforces API only.
    return getCodeforcesContests()
  }

  const { data } = await axios.get(CLIST_CONTESTS_URL, {
    params: {
      upcoming: "true",
      // Multi-value filters use the Django-style __in suffix. A plain
      // `resource=a,b,c` matches nothing and yields an empty list.
      resource__in: RESOURCES.join(","),
      order_by: "start",
      limit: 50,
    },
    headers: { Authorization: `ApiKey ${CLIST_USERNAME}:${CLIST_API_KEY}` },
    timeout: 15000,
  })

  const contests = (data.objects ?? []).map((c) => {
    const startIso = c.start.endsWith("Z") ? c.start : `${c.start}Z` // CLIST times are UTC
    return {
      id: `clist-${c.id}`,
      platform: c.resource,
      name: c.event,
      startsAt: Math.floor(new Date(startIso).getTime() / 1000),
      durationSeconds: c.duration,
      url: c.href,
    }
  })

  // If CLIST unexpectedly returns nothing, show Codeforces contests rather
  // than an empty screen.
  if (contests.length === 0) {
    return getCodeforcesContests()
  }
  return contests
}
