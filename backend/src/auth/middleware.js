import { verifyAccessToken } from "./tokens.js"

/** Express middleware: requires `Authorization: Bearer <access token>`. */
export function requireAuth(config) {
  return (req, res, next) => {
    const header = req.headers.authorization || ""
    const token = header.startsWith("Bearer ") ? header.slice(7) : null
    const userId = token ? verifyAccessToken(token, config) : null
    if (!userId) {
      return res.status(401).json({ error: "Authentication required" })
    }
    req.userId = userId
    next()
  }
}

/**
 * Small fixed-window per-IP rate limiter for the credential endpoints,
 * so leaked emails can't be brute-forced cheaply. In-memory on purpose:
 * multi-instance deployments should also rate-limit at the proxy.
 */
export function rateLimit({ windowMs = 15 * 60 * 1000, max = 30 } = {}) {
  const hits = new Map() // ip -> { count, resetAt }
  return (req, res, next) => {
    const now = Date.now()
    const key = req.ip || "unknown"
    let entry = hits.get(key)
    if (!entry || now > entry.resetAt) {
      entry = { count: 0, resetAt: now + windowMs }
      hits.set(key, entry)
    }
    entry.count++
    if (hits.size > 10_000) {
      for (const [k, v] of hits) if (now > v.resetAt) hits.delete(k)
    }
    if (entry.count > max) {
      return res.status(429).json({ error: "Too many attempts, try again later" })
    }
    next()
  }
}
