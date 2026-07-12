// PostgreSQL repositories. Every query is parameterized; no SQL is ever
// built from user input. The same interface is implemented in-memory by
// test/helpers/memoryRepos.js so route/importer tests run without Postgres.

function userRow(row) {
  if (!row) return null
  return {
    id: row.id,
    email: row.email,
    name: row.name,
    passwordHash: row.password_hash,
    createdAt: row.created_at,
  }
}

function tokenRow(row) {
  if (!row) return null
  return {
    id: row.id,
    userId: row.user_id,
    tokenHash: row.token_hash,
    expiresAt: row.expires_at,
    revokedAt: row.revoked_at,
    replacedBy: row.replaced_by,
  }
}

function submissionRow(row) {
  if (!row) return null
  return {
    id: row.id,
    userId: row.user_id,
    submissionId: String(row.platform_submission_id),
    problemCode: row.problem_code,
    problemUrl: row.problem_url,
    result: row.result,
    language: row.language,
    submittedAt: row.submitted_at,
    sourceCode: row.source_code,
    sourceFetchedAt: row.source_fetched_at,
  }
}

function jobRow(row) {
  if (!row) return null
  return {
    id: row.id,
    userId: row.user_id,
    platform: row.platform,
    status: row.status,
    handle: row.handle,
    discovered: row.discovered,
    imported: row.imported,
    sourceFetched: row.source_fetched,
    skipped: row.skipped,
    error: row.error,
    createdAt: row.created_at,
    startedAt: row.started_at,
    finishedAt: row.finished_at,
  }
}

export function createRepos(pool) {
  return {
    users: {
      async create({ email, name, passwordHash }) {
        try {
          const { rows } = await pool.query(
            `INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3)
             RETURNING *`,
            [email, name, passwordHash],
          )
          return userRow(rows[0])
        } catch (err) {
          if (err.code === "23505") {
            const conflict = new Error("email already registered")
            conflict.code = "EMAIL_TAKEN"
            throw conflict
          }
          throw err
        }
      },
      async findByEmail(email) {
        const { rows } = await pool.query(
          "SELECT * FROM users WHERE lower(email) = lower($1)",
          [email],
        )
        return userRow(rows[0])
      },
      async findById(id) {
        const { rows } = await pool.query("SELECT * FROM users WHERE id = $1", [id])
        return userRow(rows[0])
      },
      async updateName(id, name) {
        const { rows } = await pool.query(
          "UPDATE users SET name = $2, updated_at = now() WHERE id = $1 RETURNING *",
          [id, name],
        )
        return userRow(rows[0])
      },
      async updatePassword(id, passwordHash) {
        await pool.query(
          "UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1",
          [id, passwordHash],
        )
      },
    },

    refreshTokens: {
      async create({ userId, tokenHash, expiresAt }) {
        const { rows } = await pool.query(
          `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
           VALUES ($1, $2, $3) RETURNING *`,
          [userId, tokenHash, expiresAt],
        )
        return tokenRow(rows[0])
      },
      async findByHash(tokenHash) {
        const { rows } = await pool.query(
          "SELECT * FROM refresh_tokens WHERE token_hash = $1",
          [tokenHash],
        )
        return tokenRow(rows[0])
      },
      async revoke(id, { replacedBy = null } = {}) {
        await pool.query(
          `UPDATE refresh_tokens SET revoked_at = now(), replaced_by = $2
           WHERE id = $1 AND revoked_at IS NULL`,
          [id, replacedBy],
        )
      },
      async revokeAllForUser(userId) {
        await pool.query(
          "UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL",
          [userId],
        )
      },
    },

    handles: {
      async list(userId) {
        const { rows } = await pool.query(
          "SELECT platform, handle FROM linked_handles WHERE user_id = $1 ORDER BY platform",
          [userId],
        )
        return rows.map((r) => ({ platform: r.platform, handle: r.handle }))
      },
      async upsert(userId, platform, handle) {
        await pool.query(
          `INSERT INTO linked_handles (user_id, platform, handle) VALUES ($1, $2, $3)
           ON CONFLICT (user_id, platform)
           DO UPDATE SET handle = EXCLUDED.handle, updated_at = now()`,
          [userId, platform, handle],
        )
      },
      async remove(userId, platform) {
        await pool.query(
          "DELETE FROM linked_handles WHERE user_id = $1 AND platform = $2",
          [userId, platform],
        )
      },
      async get(userId, platform) {
        const { rows } = await pool.query(
          "SELECT handle FROM linked_handles WHERE user_id = $1 AND platform = $2",
          [userId, platform],
        )
        return rows[0]?.handle ?? null
      },
    },

    submissions: {
      /**
       * Insert or refresh a submission's metadata. Existing source code is
       * never overwritten with null. Returns { inserted } so the importer
       * can count new rows vs already-known ones.
       */
      async upsert(userId, sub) {
        const { rows } = await pool.query(
          `INSERT INTO codechef_submissions
             (user_id, platform_submission_id, problem_code, problem_url,
              result, language, submitted_at, source_code, source_fetched_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (user_id, platform_submission_id) DO UPDATE SET
             problem_code = EXCLUDED.problem_code,
             problem_url = COALESCE(EXCLUDED.problem_url, codechef_submissions.problem_url),
             result = COALESCE(EXCLUDED.result, codechef_submissions.result),
             language = COALESCE(EXCLUDED.language, codechef_submissions.language),
             submitted_at = COALESCE(EXCLUDED.submitted_at, codechef_submissions.submitted_at),
             source_code = COALESCE(EXCLUDED.source_code, codechef_submissions.source_code),
             source_fetched_at = COALESCE(EXCLUDED.source_fetched_at, codechef_submissions.source_fetched_at),
             updated_at = now()
           RETURNING (xmax = 0) AS inserted`,
          [
            userId,
            sub.submissionId,
            sub.problemCode,
            sub.problemUrl ?? null,
            sub.result ?? null,
            sub.language ?? null,
            sub.submittedAt ?? null,
            sub.sourceCode ?? null,
            sub.sourceFetchedAt ?? null,
          ],
        )
        return { inserted: rows[0]?.inserted === true }
      },
      /** submissionId -> { hasSource } for the given ids (dedup lookups). */
      async existing(userId, submissionIds) {
        if (submissionIds.length === 0) return new Map()
        const { rows } = await pool.query(
          `SELECT platform_submission_id, source_code IS NOT NULL AS has_source
           FROM codechef_submissions
           WHERE user_id = $1 AND platform_submission_id = ANY($2::bigint[])`,
          [userId, submissionIds],
        )
        return new Map(rows.map((r) => [String(r.platform_submission_id), { hasSource: r.has_source }]))
      },
      async list(userId, { limit = 50, offset = 0 } = {}) {
        const { rows } = await pool.query(
          `SELECT * FROM codechef_submissions WHERE user_id = $1
           ORDER BY submitted_at DESC NULLS LAST, platform_submission_id DESC
           LIMIT $2 OFFSET $3`,
          [userId, limit, offset],
        )
        return rows.map(submissionRow)
      },
      async count(userId) {
        const { rows } = await pool.query(
          "SELECT count(*)::int AS n FROM codechef_submissions WHERE user_id = $1",
          [userId],
        )
        return rows[0].n
      },
      async findById(userId, id) {
        try {
          const { rows } = await pool.query(
            "SELECT * FROM codechef_submissions WHERE user_id = $1 AND id = $2",
            [userId, id],
          )
          return submissionRow(rows[0])
        } catch (err) {
          if (err.code === "22P02") return null // not a valid uuid
          throw err
        }
      },
    },

    importJobs: {
      async create(userId, { platform = "codechef", handle = null } = {}) {
        const { rows } = await pool.query(
          `INSERT INTO import_jobs (user_id, platform, handle) VALUES ($1, $2, $3) RETURNING *`,
          [userId, platform, handle],
        )
        return jobRow(rows[0])
      },
      async update(id, fields) {
        const allowed = {
          status: "status",
          discovered: "discovered",
          imported: "imported",
          sourceFetched: "source_fetched",
          skipped: "skipped",
          error: "error",
          startedAt: "started_at",
          finishedAt: "finished_at",
        }
        const sets = []
        const values = [id]
        for (const [key, column] of Object.entries(allowed)) {
          if (fields[key] !== undefined) {
            values.push(fields[key])
            sets.push(`${column} = $${values.length}`)
          }
        }
        if (sets.length === 0) return
        await pool.query(`UPDATE import_jobs SET ${sets.join(", ")} WHERE id = $1`, values)
      },
      async latest(userId, platform = "codechef") {
        const { rows } = await pool.query(
          `SELECT * FROM import_jobs WHERE user_id = $1 AND platform = $2
           ORDER BY created_at DESC LIMIT 1`,
          [userId, platform],
        )
        return jobRow(rows[0])
      },
      async findActive(userId, platform = "codechef") {
        const { rows } = await pool.query(
          `SELECT * FROM import_jobs WHERE user_id = $1 AND platform = $2
           AND status IN ('queued', 'running') ORDER BY created_at DESC LIMIT 1`,
          [userId, platform],
        )
        return jobRow(rows[0])
      },
    },
  }
}
