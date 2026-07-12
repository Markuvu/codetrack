import assert from "node:assert/strict"
import { after, before, describe, it } from "node:test"
import { signUp, startTestServer } from "./helpers/testServer.js"

// Tenant isolation: a valid session for user A must never expose or modify
// user B's handles, submissions or import jobs.
describe("tenant isolation", () => {
  let server, alice, bob
  before(async () => {
    server = await startTestServer()
    alice = await signUp(server.api, { name: "Alice", email: "alice@example.com" })
    bob = await signUp(server.api, { name: "Bob", email: "bob@example.com" })

    await server.api("PUT", "/api/me/handles", {
      token: alice.accessToken,
      body: { handles: { codechef: "alice_chef" } },
    })
    await server.repos.submissions.upsert(alice.user.id, {
      submissionId: "111",
      problemCode: "SECRET",
      result: "accepted",
      sourceCode: "int main() { /* alice's code */ }",
      sourceFetchedAt: new Date(),
    })
  })
  after(() => server.close())

  it("does not leak handles across users", async () => {
    const res = await server.api("GET", "/api/me/handles", { token: bob.accessToken })
    assert.equal(res.status, 200)
    assert.deepEqual(res.body.handles, {})
  })

  it("does not leak submissions across users", async () => {
    const mine = await server.api("GET", "/api/me/submissions", { token: alice.accessToken })
    assert.equal(mine.body.total, 1)

    const theirs = await server.api("GET", "/api/me/submissions", { token: bob.accessToken })
    assert.equal(theirs.status, 200)
    assert.equal(theirs.body.total, 0)
    assert.deepEqual(theirs.body.submissions, [])
  })

  it("blocks direct submission lookups by id across users", async () => {
    const list = await server.api("GET", "/api/me/submissions", { token: alice.accessToken })
    const submissionRowId = list.body.submissions[0].id

    const asAlice = await server.api("GET", `/api/me/submissions/${submissionRowId}`, {
      token: alice.accessToken,
    })
    assert.equal(asAlice.status, 200)
    assert.match(asAlice.body.submission.sourceCode, /alice's code/)

    const asBob = await server.api("GET", `/api/me/submissions/${submissionRowId}`, {
      token: bob.accessToken,
    })
    assert.equal(asBob.status, 404)
  })

  it("scopes import status to the requesting user", async () => {
    await server.repos.importJobs.create(alice.user.id, { handle: "alice_chef" })
    const asBob = await server.api("GET", "/api/me/import/codechef", { token: bob.accessToken })
    assert.equal(asBob.status, 200)
    assert.equal(asBob.body.job, null)
  })

  it("writes handles only for the authenticated user", async () => {
    await server.api("PUT", "/api/me/handles", {
      token: bob.accessToken,
      body: { handles: { codechef: "bob_chef" } },
    })
    const aliceHandles = await server.api("GET", "/api/me/handles", { token: alice.accessToken })
    assert.equal(aliceHandles.body.handles.codechef, "alice_chef")
  })
})
