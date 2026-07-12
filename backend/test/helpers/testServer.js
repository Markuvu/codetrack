import { createApp } from "../../src/app.js"
import { loadConfig } from "../../src/config.js"
import { createImporter } from "../../src/services/importer.js"
import { createMemoryRepos } from "./memoryRepos.js"

export function testConfig(overrides = {}) {
  const config = loadConfig({
    JWT_SECRET: "test-secret-test-secret-test-secret!",
    BCRYPT_ROUNDS: "4", // fast hashes for tests only
    ACCESS_TOKEN_TTL_SECONDS: "900",
    REFRESH_TOKEN_TTL_DAYS: "30",
  })
  return { ...config, ...overrides }
}

/**
 * Boot the real Express app on an ephemeral port with in-memory repos.
 * Returns { base, repos, config, close, importedClient } plus a tiny JSON
 * fetch helper bound to the server.
 */
export async function startTestServer({ client, configOverrides } = {}) {
  const repos = createMemoryRepos()
  const config = testConfig(configOverrides)
  const importer = createImporter({
    repos,
    config,
    client: client ?? { hasSession: false, fetchRecentPage: async () => ({ submissions: [], maxPage: 0 }) },
    sleep: async () => {},
    log: { error: () => {} },
  })
  const app = createApp({ repos, config, importer })
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s))
  })
  const base = `http://127.0.0.1:${server.address().port}`

  async function api(method, path, { body, token } = {}) {
    const res = await fetch(base + path, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
    const text = await res.text()
    return { status: res.status, body: text ? JSON.parse(text) : null }
  }

  return {
    base,
    repos,
    config,
    api,
    close: () => new Promise((resolve) => server.close(resolve)),
  }
}

export async function signUp(api, { name = "Test User", email, password = "password123" }) {
  const res = await api("POST", "/api/auth/signup", { body: { name, email, password } })
  if (res.status !== 201) throw new Error(`signup failed: ${JSON.stringify(res.body)}`)
  return res.body
}
