// Minimal forward-only SQL migration runner: applies backend/migrations/*.sql
// in filename order, recording applied files in schema_migrations.
// Usage: DATABASE_URL=postgres://... npm run migrate
import "dotenv/config"
import { readdir, readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { createPool } from "./pool.js"

const MIGRATIONS_DIR = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "migrations",
)

export async function runMigrations(pool, { log = console.log } = {}) {
  const client = await pool.connect()
  try {
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`)

    const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith(".sql")).sort()
    const { rows } = await client.query("SELECT name FROM schema_migrations")
    const applied = new Set(rows.map((r) => r.name))

    for (const file of files) {
      if (applied.has(file)) continue
      const sql = await readFile(path.join(MIGRATIONS_DIR, file), "utf8")
      log(`applying ${file}...`)
      await client.query("BEGIN")
      try {
        await client.query(sql)
        await client.query("INSERT INTO schema_migrations (name) VALUES ($1)", [file])
        await client.query("COMMIT")
      } catch (err) {
        await client.query("ROLLBACK")
        throw new Error(`migration ${file} failed: ${err.message}`)
      }
    }
    log("migrations up to date")
  } finally {
    client.release()
  }
}

// Run directly via `npm run migrate`
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const url = process.env.DATABASE_URL
  if (!url) {
    console.error("DATABASE_URL is not set")
    process.exit(1)
  }
  const pool = createPool(url)
  runMigrations(pool)
    .then(() => pool.end())
    .catch((err) => {
      console.error(err.message)
      process.exit(1)
    })
}
