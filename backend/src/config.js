// Central environment configuration. Every value used by the auth/database
// layer is read here once so the rest of the code never touches process.env.
// See .env.example for documentation of each variable.

function int(value, fallback) {
  const n = Number(value)
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback
}

export function loadConfig(env = process.env) {
  const databaseUrl = env.DATABASE_URL || null
  const jwtSecret = env.JWT_SECRET || null

  if (databaseUrl && !jwtSecret) {
    throw new Error("JWT_SECRET must be set when DATABASE_URL is configured")
  }
  if (jwtSecret && jwtSecret.length < 32) {
    throw new Error("JWT_SECRET must be at least 32 characters")
  }

  const corsOrigins = String(env.CORS_ORIGINS || "")
    .split(",")
    .map((o) => o.trim())
    .filter(Boolean)

  return {
    port: int(env.PORT, 3000),
    databaseUrl,
    jwtSecret,
    // Comma-separated allowlist. Empty -> allow all (development only);
    // set explicitly in production. See PRODUCTION.md.
    corsOrigins,
    accessTokenTtlSeconds: int(env.ACCESS_TOKEN_TTL_SECONDS, 15 * 60),
    refreshTokenTtlDays: int(env.REFRESH_TOKEN_TTL_DAYS, 30),
    bcryptRounds: int(env.BCRYPT_ROUNDS, 12),
    codechef: {
      // Cookie header + CSRF token of a dedicated CodeChef service account
      // session. Kept in the environment / secret manager, never in Git.
      sessionCookies: env.CODECHEF_SESSION_COOKIES || null,
      csrfToken: env.CODECHEF_CSRF_TOKEN || null,
      throttleMs: int(env.CODECHEF_FETCH_THROTTLE_MS, 2500),
      timeoutMs: int(env.CODECHEF_FETCH_TIMEOUT_MS, 15000),
      maxPages: int(env.CODECHEF_IMPORT_MAX_PAGES, 10),
      maxSourceFetchesPerRun: int(env.CODECHEF_MAX_SOURCE_FETCHES_PER_RUN, 40),
    },
  }
}
