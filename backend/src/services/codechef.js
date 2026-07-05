import axios from "axios"
import * as cheerio from "cheerio"

const PROFILE_BASE = "https://www.codechef.com/users/"
const RECENT_URL = "https://www.codechef.com/recent/user"
const UA = { "User-Agent": "Mozilla/5.0 (compatible; CodeTrack/0.1)" }

// CodeChef displays times in IST for anonymous requests.
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000

// CodeChef has no reliable official API, so we parse the public profile page.
// Selectors can break when CodeChef changes its layout - fail loudly if so.
//
// Two goldmines are embedded as script variables rather than rendered HTML:
//   var all_rating = [...]              -> full rating history
//   var userDailySubmissionsStats = [...] -> submissions-per-day heatmap

function extractScriptArray(html, varName) {
  const match = html.match(new RegExp(varName + "\\s*=\\s*(\\[[\\s\\S]*?\\])\\s*;"))
  if (!match) return null
  try {
    return JSON.parse(match[1])
  } catch {
    return null
  }
}

/** "2026-06-25 22:00:02" (IST) -> epoch seconds, or null. */
function parseIstDateTime(text) {
  if (!text) return null
  const ms = Date.parse(String(text).replace(" ", "T") + "+05:30")
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null
}

export async function getCodeChefProfile(handle) {
  const url = PROFILE_BASE + encodeURIComponent(handle)
  const { data: html } = await axios.get(url, { headers: UA, timeout: 15000 })

  const $ = cheerio.load(html)

  const rating = Number($(".rating-number").first().text().replace(/[^\d]/g, "")) || null
  const starSpanCount = $(".rating-star span").length
  const stars =
    (starSpanCount > 0 ? `${starSpanCount}\u2605` : $(".rating-star").first().text().trim()) ||
    null
  const highestMatch = $(".rating-header small").first().text().match(/\d+/)
  const solvedMatch = $("section.problems-solved h3").last().text().match(/\d+/)

  if (rating === null && !stars) {
    throw new Error(
      `Could not parse CodeChef profile for '${handle}' - user may not exist or the page layout changed`,
    )
  }

  // --- extra profile details (all optional; null when the layout changes) ---
  const username = $("h1.h2-style").first().text().trim() || handle
  const country = $(".user-country-name").first().text().trim() || null
  const role =
    $('section.user-details li:contains("Student/Professional") span').last().text().trim() ||
    null
  const institution =
    $('section.user-details li:contains("Institution") span').last().text().trim() || null
  const globalRank =
    Number($(".rating-ranks li").first().find("strong").text().replace(/[^\d]/g, "")) || null
  const countryRank =
    Number($(".rating-ranks li").last().find("strong").text().replace(/[^\d]/g, "")) || null
  const league = $(".user-league-container .tooltip").first().text().trim() || null
  const profileImage = $(".user-details-container header img").first().attr("src") || null
  const contestMatch = $('section.problems-solved h3:contains("Contests")')
    .first()
    .text()
    .match(/\((\d+)\)/)

  // --- rating history from the embedded `all_rating` script variable ---
  // Normalized to { contest, at, newRating } to match every other platform,
  // so the dashboard sparkline and Progress charts work unchanged.
  const allRating = extractScriptArray(html, "all_rating")
  const ratingHistory = Array.isArray(allRating)
    ? allRating
        .map((r) => ({
          contest: r.name ?? r.contestName ?? r.code ?? "Contest",
          at: parseIstDateTime(r.end_date ?? r.date),
          newRating: Number(r.rating) || null,
        }))
        .filter((r) => r.at !== null && r.newRating !== null)
    : []

  // --- submissions-per-day heatmap from `userDailySubmissionsStats` ---
  // Counts ALL submissions (including wrong answers), so it is context, not a
  // solve count. Real solves come from getCodeChefRecentActivity below.
  const heatmapRaw = extractScriptArray(html, "userDailySubmissionsStats")
  const heatmap = Array.isArray(heatmapRaw)
    ? heatmapRaw
        .map((e) => ({
          date: e.date ?? null,
          submissions: Number(e.submissions ?? e.value ?? e.count ?? 0),
        }))
        .filter((e) => e.date !== null)
    : []

  return {
    platform: "codechef",
    handle,
    username,
    rating,
    stars,
    maxRating: highestMatch ? Number(highestMatch[0]) : null,
    solvedCount: solvedMatch ? Number(solvedMatch[0]) : null,
    contestsAttended: contestMatch ? Number(contestMatch[1]) : ratingHistory.length || null,
    globalRank,
    countryRank,
    country,
    role,
    institution,
    league,
    profileImage,
    ratingHistory,
    heatmap,
  }
}

/**
 * "10:43 PM 04/07/26" (IST, from the recent-activity table's title attr) or
 * relative text like "5 min ago" -> epoch ms, or null when unparseable.
 */
function parseRecentTime(raw) {
  if (!raw) return null
  const abs = String(raw).match(/(\d{1,2}):(\d{2})\s*(AM|PM)\s+(\d{2})\/(\d{2})\/(\d{2})/i)
  if (abs) {
    const [, h, min, ap, dd, mm, yy] = abs
    let hour = Number(h) % 12
    if (/pm/i.test(ap)) hour += 12
    const utc = Date.UTC(2000 + Number(yy), Number(mm) - 1, Number(dd), hour, Number(min))
    return utc - IST_OFFSET_MS
  }
  const rel = String(raw).match(/(\d+)\s*(sec|min|hour|day)/i)
  if (rel) {
    const unitMs = { sec: 1000, min: 60000, hour: 3600000, day: 86400000 }[
      rel[2].toLowerCase()
    ]
    return Date.now() - Number(rel[1]) * unitMs
  }
  return null
}

/**
 * Accepted solves since sinceMs from the recent-activity AJAX endpoint
 * (https://www.codechef.com/recent/user?page=N&user_handle=H, which returns
 * { content: "<table html>", max_page }). Deduplicated per problem, earliest
 * AC kept. [{ id, at }] with `at` in epoch ms - same contract as the other
 * platforms' activity fetchers.
 */
export async function getCodeChefRecentActivity(handle, sinceMs) {
  const earliest = new Map()

  for (let page = 0; page < 4; page++) {
    const { data } = await axios.get(RECENT_URL, {
      params: { page, user_handle: handle },
      headers: { ...UA, "X-Requested-With": "XMLHttpRequest" },
      timeout: 15000,
    })
    const html = data?.content
    if (!html) break

    const $ = cheerio.load(html)
    const rows = $("tr").toArray()
    let parsedAny = false
    let sawOlder = false

    for (const row of rows) {
      const tds = $(row).find("td")
      if (tds.length < 3) continue

      const timeCell = $(tds[0])
      const at = parseRecentTime(timeCell.attr("title") || timeCell.text().trim())
      const problemLink = $(tds[1]).find("a").first()
      const href = problemLink.attr("href") || ""
      // "/START228C/problems/MNERROR" -> "START228C/MNERROR"; fall back to text
      const hrefMatch = href.match(/\/([^/]+)\/problems\/([^/?#]+)/)
      const problem = hrefMatch
        ? `${hrefMatch[1]}/${hrefMatch[2]}`
        : problemLink.text().trim()
      const resultCell = $(tds[2])
      const result = (
        resultCell.find("span").first().attr("title") || resultCell.text()
      ).toLowerCase()

      if (at === null || !problem) continue
      parsedAny = true
      if (at < sinceMs) {
        sawOlder = true
        continue
      }
      if (!result.includes("accepted")) continue

      const prev = earliest.get(problem)
      if (prev === undefined || at < prev) earliest.set(problem, at)
    }

    // Stop paging once rows stop parsing (layout change), we've reached
    // entries older than the window, or we've run out of pages.
    if (!parsedAny || sawOlder) break
    const maxPage = Number(data?.max_page)
    if (Number.isFinite(maxPage) && page + 1 >= maxPage) break
  }

  return [...earliest.entries()].map(([id, at]) => ({ id, at }))
}
