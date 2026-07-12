import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { createImporter } from "../src/services/importer.js"
import { createMemoryRepos } from "./helpers/memoryRepos.js"
import { testConfig } from "./helpers/testServer.js"

function sub(id, { result = "accepted", problem = "PROB" } = {}) {
  return {
    submissionId: String(id),
    problemCode: problem,
    problemUrl: `https://www.codechef.com/problems/${problem}`,
    result,
    language: "C++17",
    submittedAt: new Date(1_700_000_000_000 + Number(id)),
  }
}

function makeClient({ pages, sources = {}, hasSession = true }) {
  const calls = { recent: 0, source: [] }
  return {
    calls,
    client: {
      hasSession,
      async fetchRecentPage(_handle, page) {
        calls.recent++
        return { submissions: pages[page] ?? [], maxPage: pages.length }
      },
      async fetchSolutionSource(id) {
        calls.source.push(id)
        return sources[id] ?? null
      },
    },
  }
}

async function runImport(repos, client, userId, { config } = {}) {
  const sleeps = []
  const importer = createImporter({
    repos,
    config: config ?? testConfig(),
    client,
    sleep: async (ms) => sleeps.push(ms),
    log: { error: () => {} },
  })
  const job = await repos.importJobs.create(userId, { handle: "chef" })
  await repos.importJobs.update(job.id, { status: "running" })
  const counters = await importer._run(job, "chef")
  await repos.importJobs.update(job.id, { ...counters, status: "completed" })
  return { counters, sleeps }
}

describe("codechef importer", () => {
  it("imports submissions with source for accepted ones", async () => {
    const repos = createMemoryRepos()
    const { client, calls } = makeClient({
      pages: [[sub(1), sub(2, { result: "wrong answer" }), sub(3)]],
      sources: { 1: "int main() {}", 3: "print(1)" },
    })

    const { counters } = await runImport(repos, client, "user-a")
    assert.equal(counters.discovered, 3)
    assert.equal(counters.imported, 3)
    assert.equal(counters.sourceFetched, 2)
    // Source is only requested for accepted submissions.
    assert.deepEqual(calls.source.sort(), ["1", "3"])

    const rows = await repos.submissions.list("user-a")
    assert.equal(rows.length, 3)
    const withSource = rows.filter((r) => r.sourceCode !== null)
    assert.equal(withSource.length, 2)
  })

  it("deduplicates: re-running imports nothing new and refetches no source", async () => {
    const repos = createMemoryRepos()
    const pages = [[sub(1), sub(2)]]
    const first = makeClient({ pages, sources: { 1: "code-1", 2: "code-2" } })
    await runImport(repos, first.client, "user-a")
    assert.equal(await repos.submissions.count("user-a"), 2)

    const second = makeClient({ pages, sources: { 1: "code-1", 2: "code-2" } })
    const { counters } = await runImport(repos, second.client, "user-a")
    assert.equal(await repos.submissions.count("user-a"), 2)
    assert.equal(counters.imported, 0)
    assert.equal(counters.skipped, 2)
    // Fully-imported submissions are never refetched.
    assert.deepEqual(second.calls.source, [])
    // And paging stops after the first all-known page.
    assert.equal(second.calls.recent, 1)
  })

  it("keeps existing source when a later run cannot fetch it", async () => {
    const repos = createMemoryRepos()
    const pages = [[sub(1)]]
    await runImport(repos, makeClient({ pages, sources: { 1: "the code" } }).client, "user-a")

    // Session expired: fetches now return null, but the stored source stays.
    await runImport(repos, makeClient({ pages, sources: {} }).client, "user-a")
    const [row] = await repos.submissions.list("user-a")
    assert.equal(row.sourceCode, "the code")
  })

  it("falls back to metadata-only rows without a service session", async () => {
    const repos = createMemoryRepos()
    const { client, calls } = makeClient({ pages: [[sub(1), sub(2)]], hasSession: false })
    const { counters } = await runImport(repos, client, "user-a")

    assert.equal(counters.imported, 2)
    assert.equal(counters.sourceFetched, 0)
    assert.deepEqual(calls.source, [])
    const rows = await repos.submissions.list("user-a")
    assert.ok(rows.every((r) => r.sourceCode === null && r.problemCode === "PROB"))
  })

  it("throttles every upstream request and caps source fetches per run", async () => {
    const config = testConfig()
    config.codechef = { ...config.codechef, maxSourceFetchesPerRun: 2, throttleMs: 123 }
    const repos = createMemoryRepos()
    const { client, calls } = makeClient({
      pages: [[sub(1), sub(2), sub(3), sub(4)]],
      sources: { 1: "a", 2: "b", 3: "c", 4: "d" },
    })

    const { counters, sleeps } = await runImport(repos, client, "user-a", { config })
    assert.equal(calls.source.length, 2) // capped
    assert.equal(counters.sourceFetched, 2)
    assert.equal(counters.imported, 4) // the rest are metadata-only
    assert.ok(sleeps.length >= 2)
    assert.ok(sleeps.every((ms) => ms === 123))
  })

  it("stops at the configured max pages", async () => {
    const config = testConfig()
    config.codechef = { ...config.codechef, maxPages: 2 }
    const repos = createMemoryRepos()
    const pages = [[sub(1)], [sub(2)], [sub(3)], [sub(4)]]
    const { client, calls } = makeClient({ pages, hasSession: false })

    await runImport(repos, client, "user-a", { config })
    assert.equal(calls.recent, 2)
    assert.equal(await repos.submissions.count("user-a"), 2)
  })

  it("marks the job failed when discovery blows up", async () => {
    const repos = createMemoryRepos()
    const importer = createImporter({
      repos,
      config: testConfig(),
      client: {
        hasSession: false,
        async fetchRecentPage() {
          throw new Error("codechef is down")
        },
      },
      sleep: async () => {},
      log: { error: () => {} },
    })
    const job = await importer.start("user-a", "chef")
    // start() runs asynchronously; poll until it settles.
    for (let i = 0; i < 50; i++) {
      const latest = await repos.importJobs.latest("user-a")
      if (latest.status === "failed") {
        assert.match(latest.error, /codechef is down/)
        return
      }
      await new Promise((r) => setTimeout(r, 10))
    }
    assert.fail("job never reached failed state")
  })
})
