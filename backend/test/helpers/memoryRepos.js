import crypto from "node:crypto"

// In-memory implementation of the repository interface in src/db/repos.js,
// so route/importer tests exercise real HTTP handlers without PostgreSQL.

export function createMemoryRepos() {
  const users = new Map()
  const tokens = new Map()
  const handles = new Map() // `${userId}:${platform}` -> handle
  const submissions = new Map() // `${userId}:${submissionId}` -> row
  const jobs = new Map()

  return {
    users: {
      async create({ email, name, passwordHash }) {
        for (const u of users.values()) {
          if (u.email.toLowerCase() === email.toLowerCase()) {
            const err = new Error("email already registered")
            err.code = "EMAIL_TAKEN"
            throw err
          }
        }
        const user = { id: crypto.randomUUID(), email, name, passwordHash, createdAt: new Date() }
        users.set(user.id, user)
        return { ...user }
      },
      async findByEmail(email) {
        for (const u of users.values()) {
          if (u.email.toLowerCase() === email.toLowerCase()) return { ...u }
        }
        return null
      },
      async findById(id) {
        const u = users.get(id)
        return u ? { ...u } : null
      },
      async updateName(id, name) {
        const u = users.get(id)
        u.name = name
        return { ...u }
      },
      async updatePassword(id, passwordHash) {
        users.get(id).passwordHash = passwordHash
      },
    },

    refreshTokens: {
      async create({ userId, tokenHash, expiresAt }) {
        const row = {
          id: crypto.randomUUID(),
          userId,
          tokenHash,
          expiresAt,
          revokedAt: null,
          replacedBy: null,
        }
        tokens.set(row.id, row)
        return { ...row }
      },
      async findByHash(tokenHash) {
        for (const t of tokens.values()) if (t.tokenHash === tokenHash) return { ...t }
        return null
      },
      async revoke(id, { replacedBy = null } = {}) {
        const t = tokens.get(id)
        if (t && !t.revokedAt) {
          t.revokedAt = new Date()
          t.replacedBy = replacedBy
        }
      },
      async revokeAllForUser(userId) {
        for (const t of tokens.values()) {
          if (t.userId === userId && !t.revokedAt) t.revokedAt = new Date()
        }
      },
    },

    handles: {
      async list(userId) {
        const rows = []
        for (const [key, handle] of handles) {
          const [uid, platform] = key.split(":")
          if (uid === userId) rows.push({ platform, handle })
        }
        return rows.sort((a, b) => a.platform.localeCompare(b.platform))
      },
      async upsert(userId, platform, handle) {
        handles.set(`${userId}:${platform}`, handle)
      },
      async remove(userId, platform) {
        handles.delete(`${userId}:${platform}`)
      },
      async get(userId, platform) {
        return handles.get(`${userId}:${platform}`) ?? null
      },
    },

    submissions: {
      async upsert(userId, sub) {
        const key = `${userId}:${sub.submissionId}`
        const existing = submissions.get(key)
        if (existing) {
          submissions.set(key, {
            ...existing,
            problemCode: sub.problemCode,
            problemUrl: sub.problemUrl ?? existing.problemUrl,
            result: sub.result ?? existing.result,
            language: sub.language ?? existing.language,
            submittedAt: sub.submittedAt ?? existing.submittedAt,
            sourceCode: sub.sourceCode ?? existing.sourceCode,
            sourceFetchedAt: sub.sourceFetchedAt ?? existing.sourceFetchedAt,
          })
          return { inserted: false }
        }
        submissions.set(key, {
          id: crypto.randomUUID(),
          userId,
          submissionId: String(sub.submissionId),
          problemCode: sub.problemCode,
          problemUrl: sub.problemUrl ?? null,
          result: sub.result ?? null,
          language: sub.language ?? null,
          submittedAt: sub.submittedAt ?? null,
          sourceCode: sub.sourceCode ?? null,
          sourceFetchedAt: sub.sourceFetchedAt ?? null,
        })
        return { inserted: true }
      },
      async existing(userId, submissionIds) {
        const map = new Map()
        for (const id of submissionIds) {
          const row = submissions.get(`${userId}:${id}`)
          if (row) map.set(String(id), { hasSource: row.sourceCode !== null })
        }
        return map
      },
      async list(userId, { limit = 50, offset = 0 } = {}) {
        return [...submissions.values()]
          .filter((s) => s.userId === userId)
          .sort(
            (a, b) =>
              (b.submittedAt?.getTime() ?? 0) - (a.submittedAt?.getTime() ?? 0) ||
              Number(b.submissionId) - Number(a.submissionId),
          )
          .slice(offset, offset + limit)
          .map((s) => ({ ...s }))
      },
      async count(userId) {
        return [...submissions.values()].filter((s) => s.userId === userId).length
      },
      async findById(userId, id) {
        for (const s of submissions.values()) {
          if (s.userId === userId && s.id === id) return { ...s }
        }
        return null
      },
    },

    importJobs: {
      async create(userId, { platform = "codechef", handle = null } = {}) {
        const job = {
          id: crypto.randomUUID(),
          userId,
          platform,
          status: "queued",
          handle,
          discovered: 0,
          imported: 0,
          sourceFetched: 0,
          skipped: 0,
          error: null,
          createdAt: new Date(),
          startedAt: null,
          finishedAt: null,
        }
        jobs.set(job.id, job)
        return { ...job }
      },
      async update(id, fields) {
        const job = jobs.get(id)
        for (const key of [
          "status",
          "discovered",
          "imported",
          "sourceFetched",
          "skipped",
          "error",
          "startedAt",
          "finishedAt",
        ]) {
          if (fields[key] !== undefined) job[key] = fields[key]
        }
      },
      async latest(userId, platform = "codechef") {
        const rows = [...jobs.values()]
          .filter((j) => j.userId === userId && j.platform === platform)
          .sort((a, b) => b.createdAt - a.createdAt)
        return rows[0] ? { ...rows[0] } : null
      },
      async findActive(userId, platform = "codechef") {
        for (const j of jobs.values()) {
          if (
            j.userId === userId &&
            j.platform === platform &&
            (j.status === "queued" || j.status === "running")
          ) {
            return { ...j }
          }
        }
        return null
      },
    },
  }
}
