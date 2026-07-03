import { promises as fs } from "fs"
import path from "path"

// Daily progress snapshots, persisted to a JSON file so history survives
// restarts. Swap for Postgres/sqlite when you outgrow a single file.
const DATA_FILE = path.join(process.cwd(), "data", "snapshots.json")

async function loadAll() {
  try {
    return JSON.parse(await fs.readFile(DATA_FILE, "utf8"))
  } catch {
    return {}
  }
}

async function saveAll(all) {
  await fs.mkdir(path.dirname(DATA_FILE), { recursive: true })
  await fs.writeFile(DATA_FILE, JSON.stringify(all, null, 2))
}

/** Record (or update) today's snapshot for a platform:handle pair. */
export async function recordSnapshot(platform, handle, profile) {
  const key = `${platform}:${handle}`
  const today = new Date().toISOString().slice(0, 10)
  const all = await loadAll()
  const list = all[key] ?? []

  const snapshot = {
    date: today,
    rating: profile.rating ?? null,
    solvedCount: profile.solvedCount ?? null,
  }

  const existingIndex = list.findIndex((s) => s.date === today)
  if (existingIndex >= 0) list[existingIndex] = snapshot
  else list.push(snapshot)

  all[key] = list
  await saveAll(all)
}

/** All snapshots for a platform:handle pair, oldest first. */
export async function getSnapshots(platform, handle) {
  const all = await loadAll()
  return all[`${platform}:${handle}`] ?? []
}
