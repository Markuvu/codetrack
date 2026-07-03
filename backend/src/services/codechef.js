import axios from "axios"
import * as cheerio from "cheerio"

// CodeChef has no reliable official API, so we parse the public profile page.
// Selectors can break when CodeChef changes its layout - fail loudly if so.
export async function getCodeChefProfile(handle) {
  const url = `https://www.codechef.com/users/${encodeURIComponent(handle)}`
  const { data: html } = await axios.get(url, {
    headers: { "User-Agent": "Mozilla/5.0 (compatible; CodeTrack/0.1)" },
    timeout: 15000,
  })

  const $ = cheerio.load(html)

  const rating = Number($(".rating-number").first().text().replace(/[^\d]/g, "")) || null
  const stars = $(".rating-star").first().text().trim() || null
  const highestMatch = $(".rating-header small").first().text().match(/\d+/)
  const solvedMatch = $("section.problems-solved h3").last().text().match(/\d+/)

  if (rating === null && !stars) {
    throw new Error(
      `Could not parse CodeChef profile for '${handle}' - user may not exist or the page layout changed`,
    )
  }

  return {
    platform: "codechef",
    handle,
    rating,
    stars,
    maxRating: highestMatch ? Number(highestMatch[0]) : null,
    solvedCount: solvedMatch ? Number(solvedMatch[0]) : null,
  }
}
