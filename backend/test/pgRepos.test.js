import assert from "node:assert/strict"
import { after, before, describe, it } from "node:test"
import { runMigrations } from "../src/db/migrate.js"
import { createPool } from "../src/db/pool.js"
import { createRepos } from "../src/db/repos.js"

// Integration test for the real PostgreSQL repositories + migrations.
// Runs only when TEST_DATABASE_URL points at a disposable database, e.g.
//   TEST_DATABASE_URL=postgres://codetrack:codetrack@localhost:5432/codetrack_test npm test
// The database is wiped (all app tables truncated) before the run.
const url = process.env.TEST_DATABASE_URL

describe("postgres repositories", { skip: url ? false : "TEST_DATABASE_URL not set" }, () => {
  let pool, repos
  before(async () => {
    pool = createPool(url)
    await runMigrations(pool, { log: () => {} })
    await pool.query(
      "TRUNCATE users, refresh_tokens, linked_handles, codechef_submissions, import_jobs CASCADE",
    )
    repos = createRepos(pool)
  })
  after(() => pool?.end())

  it("enforces case-insensitive unique emails", async () => {
    await repos.users.create({ email: "pg@example.com", name: "PG", passwordHash: "h" })
    await assert.rejects(
      repos.users.create({ email: "PG@Example.com", name: "PG2", passwordHash: "h" }),
      (err) => err.code === "EMAIL_TAKEN",
    )
    const found = await repos.users.findByEmail("PG@EXAMPLE.COM")
    assert.equal(found.name, "PG")
  })

  it("rotates and revokes refresh tokens", async () => {
    const user = await repos.users.create({
      email: "tokens@example.com",
      name: "T",
      passwordHash: "h",
    })
    const expiresAt = new Date(Date.now() + 86400000)
    const first = await repos.refreshTokens.create({
      userId: user.id,
      tokenHash: "hash-1",
      expiresAt,
    })
    const second = await repos.refreshTokens.create({
      userId: user.id,
      tokenHash: "hash-2",
      expiresAt,
    })
    await repos.refreshTokens.revoke(first.id, { replacedBy: second.id })

    const revoked = await repos.refreshTokens.findByHash("hash-1")
    assert.ok(revoked.revokedAt)
    assert.equal(revoked.replacedBy, second.id)

    await repos.refreshTokens.revokeAllForUser(user.id)
    const alsoRevoked = await repos.refreshTokens.findByHash("hash-2")
    assert.ok(alsoRevoked.revokedAt)
  })

  it("upserts handles per user+platform", async () => {
    const user = await repos.users.create({
      email: "handles-pg@example.com",
      name: "H",
      passwordHash: "h",
    })
    await repos.handles.upsert(user.id, "codechef", "first")
    await repos.handles.upsert(user.id, "codechef", "second")
    assert.equal(await repos.handles.get(user.id, "codechef"), "second")
    assert.deepEqual(await repos.handles.list(user.id), [
      { platform: "codechef", handle: "second" },
    ])
    await repos.handles.remove(user.id, "codechef")
    assert.equal(await repos.handles.get(user.id, "codechef"), null)
  })

  it("deduplicates submissions and preserves stored source", async () => {
    const user = await repos.users.create({
      email: "subs-pg@example.com",
      name: "S",
      passwordHash: "h",
    })
    const base = {
      submissionId: "9001",
      problemCode: "FLOW001",
      problemUrl: "https://www.codechef.com/problems/FLOW001",
      result: "accepted",
      language: "C++17",
      submittedAt: new Date("2026-07-04T17:13:00Z"),
    }
    const first = await repos.submissions.upsert(user.id, { ...base, sourceCode: "the code" })
    assert.equal(first.inserted, true)

    // Same submission again, this time without source: metadata refreshes,
    // stored source survives, and no duplicate row is created.
    const second = await repos.submissions.upsert(user.id, { ...base, sourceCode: null })
    assert.equal(second.inserted, false)
    assert.equal(await repos.submissions.count(user.id), 1)
    const [row] = await repos.submissions.list(user.id)
    assert.equal(row.sourceCode, "the code")

    const existing = await repos.submissions.existing(user.id, ["9001", "9999"])
    assert.deepEqual([...existing.keys()], ["9001"])
    assert.equal(existing.get("9001").hasSource, true)

    // Row lookups are scoped by user.
    assert.equal(await repos.submissions.findById("00000000-0000-0000-0000-000000000000", row.id), null)
    assert.equal(await repos.submissions.findById(user.id, "not-a-uuid"), null)
  })

  it("tracks import jobs with counters", async () => {
    const user = await repos.users.create({
      email: "jobs-pg@example.com",
      name: "J",
      passwordHash: "h",
    })
    const job = await repos.importJobs.create(user.id, { handle: "chef" })
    assert.equal(job.status, "queued")
    assert.deepEqual(await repos.importJobs.findActive(user.id), job)

    await repos.importJobs.update(job.id, {
      status: "completed",
      discovered: 5,
      imported: 3,
      sourceFetched: 2,
      skipped: 2,
      finishedAt: new Date(),
    })
    const latest = await repos.importJobs.latest(user.id)
    assert.equal(latest.status, "completed")
    assert.equal(latest.imported, 3)
    assert.equal(await repos.importJobs.findActive(user.id), null)
  })
})
