import crypto from "node:crypto"
import jwt from "jsonwebtoken"

// Access tokens: short-lived signed JWTs carried in the Authorization header.
// Refresh tokens: 256-bit random secrets; only their SHA-256 hash is stored,
// so a database leak cannot be replayed as a session.

export function signAccessToken(userId, { jwtSecret, accessTokenTtlSeconds }) {
  return jwt.sign({ sub: userId }, jwtSecret, { expiresIn: accessTokenTtlSeconds })
}

/** Returns the user id, or null when the token is invalid or expired. */
export function verifyAccessToken(token, { jwtSecret }) {
  try {
    const payload = jwt.verify(token, jwtSecret)
    return typeof payload.sub === "string" ? payload.sub : null
  } catch {
    return null
  }
}

export function generateRefreshToken() {
  return crypto.randomBytes(32).toString("hex")
}

export function hashRefreshToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex")
}

export function refreshTokenExpiry({ refreshTokenTtlDays }, now = Date.now()) {
  return new Date(now + refreshTokenTtlDays * 24 * 60 * 60 * 1000)
}
