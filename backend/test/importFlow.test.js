import assert from "node:assert/strict"
import { after, before, describe, it } from "node:test"
import { signUp, startTestServer } from "./helpers/testServer.js"

// End-to-end: link a handle, trigger the import over HTTP, poll status,
// then read back the imported submissions and one full source.
describe("codechef import flow over HTTP", () => {
  let server, session
  before(async () => {
    server = await startTestServer({
      client: {
        hasSession: true,
        async fetchRecentPage(handle, page) {
          assert.equal(handle, "chef_user")
          if (page > 0) return { submissions: [], maxPage: 1 }
          return {
            maxPage: 1,
            submissions: [
              {
                submissionId: "42",
                problemCode: "FLOW001",
                problemUrl: "https://www.codechef.com/problems/FLOW001",
                result: "accepted",
                language: "PYTH 3",
                submittedAt: new Date("2026-07-04T17:13:00Z"),
              },
              {
                submissionId: "43",
                problemCode: "FLOW002",
                problemUrl: "https://www.codechef.com/problems/FLOW002",
                result: "wrong answer",
                language: "PYTH 3",
                submittedAt: new Date("2026-07-04T18:00:00Z"),
              },
            ],
          }
        },
        async fetchSolutionSource(id) {
          return id === "42" ? "print(sum(map(int, input().split())))" : null
        },
      },
    })
    session = await signUp(server.api, { email: "importer@example.com" })
    await server.api("PUT", "/api/me/handles", {
      token: session.accessToken,
      body: { handles: { codechef: "chef_user" } },
    })
  })
  after(() => server.close())

  it("runs an import and serves the results", async () => {
    const token = session.accessToken

    const trigger = await server.api("POST", "/api/me/import/codechef", { token })
    assert.equal(trigger.status, 202)
    assert.equal(trigger.body.job.status, "queued")

    // Poll until the job settles.
    let job
    for (let i = 0; i < 100; i++) {
      const status = await server.api("GET", "/api/me/import/codechef", { token })
      job = status.body.job
      if (job.status === "completed" || job.status === "failed") break
      await new Promise((r) => setTimeout(r, 10))
    }
    assert.equal(job.status, "completed")
    assert.equal(job.discovered, 2)
    assert.equal(job.imported, 2)
    assert.equal(job.sourceFetched, 1)

    const list = await server.api("GET", "/api/me/submissions", { token })
    assert.equal(list.status, 200)
    assert.equal(list.body.total, 2)
    // Newest first.
    assert.equal(list.body.submissions[0].submissionId, "43")
    assert.equal(list.body.submissions[0].hasSource, false)
    assert.equal(list.body.submissions[1].submissionId, "42")
    assert.equal(list.body.submissions[1].hasSource, true)

    const detail = await server.api(
      "GET",
      `/api/me/submissions/${list.body.submissions[1].id}`,
      { token },
    )
    assert.equal(detail.status, 200)
    assert.match(detail.body.submission.sourceCode, /print\(sum/)

    // A second trigger right after completion is allowed (no active job).
    const again = await server.api("POST", "/api/me/import/codechef", { token })
    assert.equal(again.status, 202)
  })
})
