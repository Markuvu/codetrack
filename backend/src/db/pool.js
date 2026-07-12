import pg from "pg"

// Single shared connection pool. SSL is enabled automatically for URLs that
// request it (e.g. `?sslmode=require` on managed Postgres providers).
export function createPool(databaseUrl) {
  return new pg.Pool({ connectionString: databaseUrl, max: 10 })
}
