import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"
import {
  parseRecentSubmissions,
  parseRecentTime,
  parseSolutionSource,
} from "../src/services/codechefSolutions.js"

const FIXTURES = path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures")
const recentHtml = readFileSync(path.join(FIXTURES, "codechef-recent-page0.html"), "utf8")
const plaintextHtml = readFileSync(path.join(FIXTURES, "codechef-viewplaintext.html"), "utf8")

describe("codechef parsing", () => {
  it("parses submissions from the recent-activity table", () => {
    const now = Date.UTC(2026, 6, 5, 12, 0, 0)
    const subs = parseRecentSubmissions(recentHtml, { now })

    // 4 rows have /viewsolution links; the banner row is skipped.
    assert.equal(subs.length, 4)

    const [accepted, wrong, scored, relative] = subs
    assert.equal(accepted.submissionId, "1090001234")
    assert.equal(accepted.problemCode, "MNERROR")
    assert.equal(accepted.problemUrl, "https://www.codechef.com/START228C/problems/MNERROR")
    assert.equal(accepted.result, "accepted")
    assert.equal(accepted.language, "C++17")
    // 10:43 PM 04/07/26 IST -> 17:13 UTC
    assert.equal(accepted.submittedAt.toISOString(), "2026-07-04T17:13:00.000Z")

    assert.equal(wrong.submissionId, "1090000987")
    assert.equal(wrong.result, "wrong answer")

    assert.equal(scored.submissionId, "1089990111")
    assert.equal(scored.problemCode, "FLOW001")
    assert.equal(scored.result, "accepted (100)")
    assert.equal(scored.language, "PYTH 3")

    // Relative timestamps resolve against `now`.
    assert.equal(relative.submissionId, "1090005555")
    assert.equal(relative.submittedAt.getTime(), now - 5 * 60 * 1000)
  })

  it("returns no submissions for markup without solution links", () => {
    assert.deepEqual(parseRecentSubmissions("<table><tr><td>empty</td></tr></table>"), [])
    assert.deepEqual(parseRecentSubmissions(""), [])
  })

  it("parses IST timestamps and relative times", () => {
    assert.equal(
      parseRecentTime("10:43 PM 04/07/26"),
      Date.UTC(2026, 6, 4, 22, 43) - 5.5 * 60 * 60 * 1000,
    )
    assert.equal(parseRecentTime("12:05 AM 01/01/25"), Date.UTC(2025, 0, 1, 0, 5) - 5.5 * 3600000)
    const now = 1_000_000_000_000
    assert.equal(parseRecentTime("2 hour ago", now), now - 2 * 3600000)
    assert.equal(parseRecentTime("garbage"), null)
    assert.equal(parseRecentTime(null), null)
  })

  it("extracts and decodes source code from viewplaintext", () => {
    const source = parseSolutionSource(plaintextHtml)
    assert.match(source, /#include <bits\/stdc\+\+\.h>/)
    assert.match(source, /cout << a \+ b << "\\n";/)
  })

  it("returns null for empty or missing source", () => {
    assert.equal(parseSolutionSource("<html><body><pre>   </pre></body></html>"), null)
    assert.equal(parseSolutionSource(""), null)
    assert.equal(parseSolutionSource(null), null)
  })
})
