import axios from "axios"
import * as cheerio from "cheerio"

// CodeChef solution retrieval for the signed-in user's saved handle.
//
// Discovery uses the same public recent-activity AJAX endpoint the profile
// pages use (https://www.codechef.com/recent/user?page=N&user_handle=H).
// Each row links to /viewsolution/<id>, which is how we learn submission ids.
//
// Source code is fetched through ONE server-side CodeChef service session:
// the session cookies + CSRF token of a dedicated CodeChef account are kept
// in environment variables / the deployment secret manager (never in Git).
// When no session is configured, or a solution isn't visible to it, the
// import degrades gracefully to metadata-only rows.

const RECENT_URL = "https://www.codechef.com/recent/user"
const SITE_BASE = "https://www.codechef.com"
const UA = "Mozilla/5.0 (compatible; CodeTrack/0.2)"

// CodeChef renders times in IST for anonymous requests.
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000

/** "10:43 PM 04/07/26" (IST) or "5 min ago" -> epoch ms, or null. */
export function parseRecentTime(raw, now = Date.now()) {
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
    const unitMs = { sec: 1000, min: 60000, hour: 3600000, day: 86400000 }[rel[2].toLowerCase()]
    return now - Number(rel[1]) * unitMs
  }
  return null
}

/**
 * Parse one recent-activity table (the `content` HTML fragment of the AJAX
 * response) into submission metadata rows:
 *   [{ submissionId, problemCode, problemUrl, result, language, submittedAt }]
 * Rows without a /viewsolution/<id> link are skipped - without the id there
 * is nothing to import or deduplicate against.
 */
export function parseRecentSubmissions(html, { now = Date.now() } = {}) {
  const $ = cheerio.load(html)
  const submissions = []

  for (const row of $("tr").toArray()) {
    const tds = $(row).find("td")
    if (tds.length < 3) continue

    const idMatch = $(row)
      .find('a[href*="/viewsolution/"]')
      .first()
      .attr("href")
      ?.match(/\/viewsolution\/(\d+)/)
    if (!idMatch) continue

    const timeCell = $(tds[0])
    const at = parseRecentTime(timeCell.attr("title") || timeCell.text().trim(), now)

    const problemLink = $(tds[1]).find("a").first()
    const href = problemLink.attr("href") || ""
    const hrefMatch = href.match(/\/([^/]+)\/problems\/([^/?#]+)/) || href.match(/\/problems\/([^/?#]+)/)
    const problemCode = hrefMatch
      ? hrefMatch[2] ?? hrefMatch[1]
      : problemLink.text().trim() || null
    if (!problemCode) continue

    const resultCell = $(tds[2])
    const result =
      resultCell.find("span").first().attr("title")?.trim() || resultCell.text().trim() || null
    const language = tds.length >= 4 ? $(tds[3]).text().trim() || null : null

    submissions.push({
      submissionId: idMatch[1],
      problemCode,
      problemUrl: href ? (href.startsWith("http") ? href : SITE_BASE + href) : null,
      result,
      language,
      submittedAt: at === null ? null : new Date(at),
    })
  }
  return submissions
}

/** Extract the plain source code from a /viewplaintext/<id> response. */
export function parseSolutionSource(html) {
  if (!html) return null
  const $ = cheerio.load(html)
  const pre = $("pre").first()
  const text = (pre.length ? pre.text() : $.root().text()).replace(/\r\n/g, "\n")
  const trimmed = text.trim()
  return trimmed.length > 0 ? text : null
}

export function createCodeChefClient(config) {
  const { sessionCookies, csrfToken, timeoutMs } = config.codechef

  const sessionHeaders = () => {
    const headers = { "User-Agent": UA }
    if (sessionCookies) headers.Cookie = sessionCookies
    if (csrfToken) headers["x-csrf-token"] = csrfToken
    return headers
  }

  return {
    hasSession: Boolean(sessionCookies),

    /**
     * One page of the user's recent submissions (public endpoint).
     * Returns { submissions, maxPage }.
     */
    async fetchRecentPage(handle, page) {
      const { data } = await axios.get(RECENT_URL, {
        params: { page, user_handle: handle },
        headers: { "User-Agent": UA, "X-Requested-With": "XMLHttpRequest" },
        timeout: timeoutMs,
      })
      const html = data?.content
      if (!html) return { submissions: [], maxPage: 0 }
      return {
        submissions: parseRecentSubmissions(html),
        maxPage: Number(data?.max_page) || 0,
      }
    },

    /**
     * Source code for one submission via the service session. Returns null
     * (metadata-only fallback) when the solution is not visible or the
     * request fails - callers treat null as "skip, don't retry this run".
     */
    async fetchSolutionSource(submissionId) {
      try {
        const { data, status } = await axios.get(
          `${SITE_BASE}/viewplaintext/${encodeURIComponent(submissionId)}`,
          {
            headers: sessionHeaders(),
            timeout: timeoutMs,
            validateStatus: (s) => s < 500,
          },
        )
        if (status !== 200) return null
        return parseSolutionSource(typeof data === "string" ? data : null)
      } catch {
        return null
      }
    },
  }
}
