import { Router } from "express"
import { requireAuth } from "../auth/middleware.js"
import { hashPassword, verifyPassword } from "../auth/passwords.js"
import { publicUser } from "../auth/routes.js"

const PLATFORMS = new Set(["codeforces", "leetcode", "codechef", "atcoder", "gfg"])
const HANDLE_RE = /^[A-Za-z0-9_.\-]{1,64}$/
const MIN_PASSWORD_LENGTH = 8

function handlesToMap(rows) {
  return Object.fromEntries(rows.map((r) => [r.platform, r.handle]))
}

/**
 * Authenticated per-user routes. Every query is scoped by req.userId, so a
 * valid token for user A can never read or modify user B's rows.
 */
export function createMeRouter({ repos, config, importer }) {
  const router = Router()
  router.use(requireAuth(config))

  // GET /api/me - current user
  router.get("/", async (req, res, next) => {
    try {
      const user = await repos.users.findById(req.userId)
      if (!user) return res.status(401).json({ error: "Account no longer exists" })
      res.json({ user: publicUser(user) })
    } catch (err) {
      next(err)
    }
  })

  // PATCH /api/me { name } - profile update
  router.patch("/", async (req, res, next) => {
    try {
      const name = String(req.body?.name ?? "").trim()
      if (!name) return res.status(400).json({ error: "Name is required" })
      const user = await repos.users.updateName(req.userId, name)
      res.json({ user: publicUser(user) })
    } catch (err) {
      next(err)
    }
  })

  // POST /api/me/password { currentPassword, newPassword }
  // Revokes every refresh token, so stolen sessions die with the old password.
  router.post("/password", async (req, res, next) => {
    try {
      const current = String(req.body?.currentPassword ?? "")
      const fresh = String(req.body?.newPassword ?? "")
      if (fresh.length < MIN_PASSWORD_LENGTH) {
        return res
          .status(400)
          .json({ error: `New password must be at least ${MIN_PASSWORD_LENGTH} characters` })
      }
      const user = await repos.users.findById(req.userId)
      if (!user || !(await verifyPassword(current, user.passwordHash))) {
        return res.status(403).json({ error: "Current password is incorrect" })
      }
      await repos.users.updatePassword(req.userId, await hashPassword(fresh, config.bcryptRounds))
      await repos.refreshTokens.revokeAllForUser(req.userId)
      res.status(204).end()
    } catch (err) {
      next(err)
    }
  })

  // GET /api/me/handles -> { handles: { codeforces: "tourist", ... } }
  router.get("/handles", async (req, res, next) => {
    try {
      res.json({ handles: handlesToMap(await repos.handles.list(req.userId)) })
    } catch (err) {
      next(err)
    }
  })

  // PUT /api/me/handles { handles: { codechef: "foo", leetcode: null } }
  // Upserts non-empty values, removes null/empty ones; other platforms are
  // left untouched. Returns the resulting full map.
  router.put("/handles", async (req, res, next) => {
    try {
      const handles = req.body?.handles
      if (!handles || typeof handles !== "object" || Array.isArray(handles)) {
        return res.status(400).json({ error: "Provide a 'handles' object" })
      }
      for (const [platform, handle] of Object.entries(handles)) {
        if (!PLATFORMS.has(platform)) {
          return res.status(400).json({ error: `Unsupported platform '${platform}'` })
        }
        if (handle !== null && handle !== "" && !HANDLE_RE.test(String(handle))) {
          return res.status(400).json({ error: `Invalid handle for '${platform}'` })
        }
      }
      for (const [platform, handle] of Object.entries(handles)) {
        if (handle === null || handle === "") {
          await repos.handles.remove(req.userId, platform)
        } else {
          await repos.handles.upsert(req.userId, platform, String(handle))
        }
      }
      res.json({ handles: handlesToMap(await repos.handles.list(req.userId)) })
    } catch (err) {
      next(err)
    }
  })

  // POST /api/me/import/codechef - queue an import of the signed-in user's
  // saved CodeChef handle. 409 while a previous run is still active.
  router.post("/import/codechef", async (req, res, next) => {
    try {
      const handle = await repos.handles.get(req.userId, "codechef")
      if (!handle) {
        return res.status(400).json({ error: "Link a CodeChef handle first" })
      }
      const active = await repos.importJobs.findActive(req.userId, "codechef")
      if (active) return res.status(409).json({ error: "An import is already running", job: active })
      const job = await importer.start(req.userId, handle)
      res.status(202).json({ job })
    } catch (err) {
      next(err)
    }
  })

  // GET /api/me/import/codechef -> { job: latest run or null }
  router.get("/import/codechef", async (req, res, next) => {
    try {
      res.json({ job: await repos.importJobs.latest(req.userId, "codechef") })
    } catch (err) {
      next(err)
    }
  })

  // GET /api/me/submissions?limit=50&offset=0 - imported CodeChef
  // submissions (metadata only; fetch one by id for the source code).
  router.get("/submissions", async (req, res, next) => {
    try {
      const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 200)
      const offset = Math.max(Number(req.query.offset) || 0, 0)
      const [submissions, total] = await Promise.all([
        repos.submissions.list(req.userId, { limit, offset }),
        repos.submissions.count(req.userId),
      ])
      res.json({
        total,
        submissions: submissions.map((s) => ({
          id: s.id,
          submissionId: s.submissionId,
          problemCode: s.problemCode,
          problemUrl: s.problemUrl,
          result: s.result,
          language: s.language,
          submittedAt: s.submittedAt,
          hasSource: s.sourceCode !== null && s.sourceCode !== undefined,
        })),
      })
    } catch (err) {
      next(err)
    }
  })

  // GET /api/me/submissions/:id - one submission including source code.
  router.get("/submissions/:id", async (req, res, next) => {
    try {
      const submission = await repos.submissions.findById(req.userId, req.params.id)
      if (!submission) return res.status(404).json({ error: "Submission not found" })
      res.json({ submission })
    } catch (err) {
      next(err)
    }
  })

  return router
}
