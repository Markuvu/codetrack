import assert from "node:assert/strict"
import { after, before, describe, it } from "node:test"
import { signUp, startTestServer } from "./helpers/testServer.js"

describe("auth", () => {
  let server
  before(async () => {
    server = await startTestServer()
  })
  after(() => server.close())

  it("signs up, returns tokens and rejects duplicate emails", async () => {
    const { api } = server
    const res = await api("POST", "/api/auth/signup", {
      body: { name: "Ada", email: "ada@example.com", password: "hunter2hunter2" },
    })
    assert.equal(res.status, 201)
    assert.equal(res.body.user.email, "ada@example.com")
    assert.ok(res.body.accessToken)
    assert.ok(res.body.refreshToken)
    assert.ok(!("passwordHash" in res.body.user))

    // duplicate (case-insensitive)
    const dup = await api("POST", "/api/auth/signup", {
      body: { name: "Ada2", email: "ADA@example.com", password: "hunter2hunter2" },
    })
    assert.equal(dup.status, 409)
  })

  it("validates signup input", async () => {
    const { api } = server
    for (const body of [
      { name: "", email: "x@example.com", password: "longenough" },
      { name: "X", email: "not-an-email", password: "longenough" },
      { name: "X", email: "short@example.com", password: "short" },
    ]) {
      const res = await api("POST", "/api/auth/signup", { body })
      assert.equal(res.status, 400)
    }
  })

  it("logs in with correct credentials only", async () => {
    const { api } = server
    await signUp(api, { email: "login@example.com", password: "correct-horse" })

    const bad = await api("POST", "/api/auth/login", {
      body: { email: "login@example.com", password: "wrong-horse" },
    })
    assert.equal(bad.status, 401)

    const unknown = await api("POST", "/api/auth/login", {
      body: { email: "nobody@example.com", password: "correct-horse" },
    })
    assert.equal(unknown.status, 401)
    // Identical error body for unknown email vs wrong password.
    assert.deepEqual(unknown.body, bad.body)

    const ok = await api("POST", "/api/auth/login", {
      body: { email: "Login@Example.com", password: "correct-horse" },
    })
    assert.equal(ok.status, 200)
    assert.ok(ok.body.accessToken)
  })

  it("rotates refresh tokens and detects reuse", async () => {
    const { api } = server
    const session = await signUp(api, { email: "rotate@example.com" })

    const first = await api("POST", "/api/auth/refresh", {
      body: { refreshToken: session.refreshToken },
    })
    assert.equal(first.status, 200)
    assert.notEqual(first.body.refreshToken, session.refreshToken)

    // Reusing the rotated (now revoked) token fails...
    const reuse = await api("POST", "/api/auth/refresh", {
      body: { refreshToken: session.refreshToken },
    })
    assert.equal(reuse.status, 401)

    // ...and revokes the whole family: the newest token is dead too.
    const afterReuse = await api("POST", "/api/auth/refresh", {
      body: { refreshToken: first.body.refreshToken },
    })
    assert.equal(afterReuse.status, 401)
  })

  it("logout revokes the refresh token", async () => {
    const { api } = server
    const session = await signUp(api, { email: "logout@example.com" })

    const out = await api("POST", "/api/auth/logout", {
      body: { refreshToken: session.refreshToken },
    })
    assert.equal(out.status, 204)

    const res = await api("POST", "/api/auth/refresh", {
      body: { refreshToken: session.refreshToken },
    })
    assert.equal(res.status, 401)
  })

  it("requires authentication for /api/me", async () => {
    const { api } = server
    assert.equal((await api("GET", "/api/me")).status, 401)
    assert.equal((await api("GET", "/api/me", { token: "garbage" })).status, 401)
    assert.equal((await api("GET", "/api/me/handles")).status, 401)
    assert.equal((await api("GET", "/api/me/submissions")).status, 401)
    assert.equal((await api("POST", "/api/me/import/codechef")).status, 401)
  })

  it("returns and updates the current user", async () => {
    const { api } = server
    const session = await signUp(api, { name: "Old Name", email: "me@example.com" })
    const me = await api("GET", "/api/me", { token: session.accessToken })
    assert.equal(me.status, 200)
    assert.equal(me.body.user.name, "Old Name")

    const patched = await api("PATCH", "/api/me", {
      token: session.accessToken,
      body: { name: "New Name" },
    })
    assert.equal(patched.status, 200)
    assert.equal(patched.body.user.name, "New Name")
  })

  it("changes password, revokes sessions, and accepts the new password", async () => {
    const { api } = server
    const session = await signUp(api, { email: "pw@example.com", password: "oldpassword" })

    const wrong = await api("POST", "/api/me/password", {
      token: session.accessToken,
      body: { currentPassword: "not-it", newPassword: "newpassword1" },
    })
    assert.equal(wrong.status, 403)

    const ok = await api("POST", "/api/me/password", {
      token: session.accessToken,
      body: { currentPassword: "oldpassword", newPassword: "newpassword1" },
    })
    assert.equal(ok.status, 204)

    // Old refresh token is revoked by the password change.
    const refresh = await api("POST", "/api/auth/refresh", {
      body: { refreshToken: session.refreshToken },
    })
    assert.equal(refresh.status, 401)

    // Old password no longer works, new one does.
    const oldLogin = await api("POST", "/api/auth/login", {
      body: { email: "pw@example.com", password: "oldpassword" },
    })
    assert.equal(oldLogin.status, 401)
    const newLogin = await api("POST", "/api/auth/login", {
      body: { email: "pw@example.com", password: "newpassword1" },
    })
    assert.equal(newLogin.status, 200)
  })

  it("stores refresh tokens only as hashes", async () => {
    const { api, repos } = server
    const session = await signUp(api, { email: "hashes@example.com" })
    const record = await repos.refreshTokens.findByHash(
      (await import("../src/auth/tokens.js")).hashRefreshToken(session.refreshToken),
    )
    assert.ok(record)
    assert.notEqual(record.tokenHash, session.refreshToken)
  })

  it("manages linked handles", async () => {
    const { api } = server
    const session = await signUp(api, { email: "handles@example.com" })
    const token = session.accessToken

    const put = await api("PUT", "/api/me/handles", {
      token,
      body: { handles: { codechef: "chef_user", codeforces: "tourist" } },
    })
    assert.equal(put.status, 200)
    assert.deepEqual(put.body.handles, { codechef: "chef_user", codeforces: "tourist" })

    // Unlink one, keep the other.
    const del = await api("PUT", "/api/me/handles", {
      token,
      body: { handles: { codeforces: null } },
    })
    assert.equal(del.status, 200)
    assert.deepEqual(del.body.handles, { codechef: "chef_user" })

    // Validation: unknown platform / bad handle.
    assert.equal(
      (await api("PUT", "/api/me/handles", { token, body: { handles: { hackerrank: "x" } } }))
        .status,
      400,
    )
    assert.equal(
      (await api("PUT", "/api/me/handles", { token, body: { handles: { codechef: "bad handle!" } } }))
        .status,
      400,
    )
  })

  it("requires a linked CodeChef handle before importing", async () => {
    const { api } = server
    const session = await signUp(api, { email: "noimport@example.com" })
    const res = await api("POST", "/api/me/import/codechef", { token: session.accessToken })
    assert.equal(res.status, 400)
  })
})
