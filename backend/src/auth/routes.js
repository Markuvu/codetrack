import { Router } from "express"
import { rateLimit } from "./middleware.js"
import { hashPassword, verifyPassword } from "./passwords.js"
import {
  generateRefreshToken,
  hashRefreshToken,
  refreshTokenExpiry,
  signAccessToken,
} from "./tokens.js"

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const MIN_PASSWORD_LENGTH = 8

export function publicUser(user) {
  return { id: user.id, email: user.email, name: user.name }
}

async function issueSession(repos, config, userId) {
  const refreshToken = generateRefreshToken()
  await repos.refreshTokens.create({
    userId,
    tokenHash: hashRefreshToken(refreshToken),
    expiresAt: refreshTokenExpiry(config),
  })
  return {
    accessToken: signAccessToken(userId, config),
    refreshToken,
    expiresIn: config.accessTokenTtlSeconds,
  }
}

export function createAuthRouter({ repos, config }) {
  const router = Router()
  const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 30 })

  // POST /api/auth/signup { name, email, password }
  router.post("/signup", limiter, async (req, res, next) => {
    try {
      const name = String(req.body?.name ?? "").trim()
      const email = String(req.body?.email ?? "").trim().toLowerCase()
      const password = String(req.body?.password ?? "")
      if (!name) return res.status(400).json({ error: "Name is required" })
      if (!EMAIL_RE.test(email)) return res.status(400).json({ error: "Invalid email address" })
      if (password.length < MIN_PASSWORD_LENGTH) {
        return res
          .status(400)
          .json({ error: `Password must be at least ${MIN_PASSWORD_LENGTH} characters` })
      }
      let user
      try {
        user = await repos.users.create({
          email,
          name,
          passwordHash: await hashPassword(password, config.bcryptRounds),
        })
      } catch (err) {
        if (err.code === "EMAIL_TAKEN") {
          return res.status(409).json({ error: "An account with this email already exists" })
        }
        throw err
      }
      res.status(201).json({ user: publicUser(user), ...(await issueSession(repos, config, user.id)) })
    } catch (err) {
      next(err)
    }
  })

  // POST /api/auth/login { email, password }
  router.post("/login", limiter, async (req, res, next) => {
    try {
      const email = String(req.body?.email ?? "").trim()
      const password = String(req.body?.password ?? "")
      const user = email ? await repos.users.findByEmail(email) : null
      // Same response for unknown email and wrong password.
      if (!user || !(await verifyPassword(password, user.passwordHash))) {
        return res.status(401).json({ error: "Wrong email or password" })
      }
      res.json({ user: publicUser(user), ...(await issueSession(repos, config, user.id)) })
    } catch (err) {
      next(err)
    }
  })

  // POST /api/auth/refresh { refreshToken } - rotates the refresh token.
  router.post("/refresh", limiter, async (req, res, next) => {
    try {
      const presented = String(req.body?.refreshToken ?? "")
      if (!presented) return res.status(400).json({ error: "refreshToken is required" })
      const record = await repos.refreshTokens.findByHash(hashRefreshToken(presented))
      if (!record) return res.status(401).json({ error: "Invalid refresh token" })
      if (record.revokedAt) {
        // Reuse of a rotated/revoked token: assume the token leaked and
        // revoke every session for this user.
        await repos.refreshTokens.revokeAllForUser(record.userId)
        return res.status(401).json({ error: "Refresh token has been revoked" })
      }
      if (new Date(record.expiresAt).getTime() < Date.now()) {
        return res.status(401).json({ error: "Refresh token has expired" })
      }
      const user = await repos.users.findById(record.userId)
      if (!user) return res.status(401).json({ error: "Account no longer exists" })

      const refreshToken = generateRefreshToken()
      const replacement = await repos.refreshTokens.create({
        userId: user.id,
        tokenHash: hashRefreshToken(refreshToken),
        expiresAt: refreshTokenExpiry(config),
      })
      await repos.refreshTokens.revoke(record.id, { replacedBy: replacement.id })

      res.json({
        user: publicUser(user),
        accessToken: signAccessToken(user.id, config),
        refreshToken,
        expiresIn: config.accessTokenTtlSeconds,
      })
    } catch (err) {
      next(err)
    }
  })

  // POST /api/auth/logout { refreshToken } - revokes the session. Works
  // without an access token so expired sessions can still be cleaned up.
  router.post("/logout", async (req, res, next) => {
    try {
      const presented = String(req.body?.refreshToken ?? "")
      if (presented) {
        const record = await repos.refreshTokens.findByHash(hashRefreshToken(presented))
        if (record && !record.revokedAt) await repos.refreshTokens.revoke(record.id)
      }
      res.status(204).end()
    } catch (err) {
      next(err)
    }
  })

  return router
}
