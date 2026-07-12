import "dotenv/config"
import { createApp } from "./app.js"
import { loadConfig } from "./config.js"
import { createPool } from "./db/pool.js"
import { createRepos } from "./db/repos.js"
import { createCodeChefClient } from "./services/codechefSolutions.js"
import { createImporter } from "./services/importer.js"

const config = loadConfig()

let repos = null
let importer = null
if (config.databaseUrl) {
  const pool = createPool(config.databaseUrl)
  repos = createRepos(pool)
  importer = createImporter({ repos, config, client: createCodeChefClient(config) })
} else {
  console.warn(
    "DATABASE_URL is not set - accounts, handle sync and CodeChef import are disabled. " +
      "See .env.example and PRODUCTION.md.",
  )
}

const app = createApp({ repos, config, importer })
app.listen(config.port, () =>
  console.log(`CodeTrack backend listening on http://localhost:${config.port}`),
)
