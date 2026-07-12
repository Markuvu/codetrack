// CodeChef import job runner.
//
// One run: page through the handle's recent submissions (public endpoint),
// deduplicate against already-stored rows, and fetch source code for new
// accepted submissions through the configured service session - politely:
// a fixed delay between every upstream request and a per-run cap on source
// fetches. Jobs run in-process; state lives in the import_jobs table so the
// app can poll status.

const ACCEPTED_RE = /accepted/i

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

export function createImporter({ repos, config, client, sleep = defaultSleep, log = console }) {
  const { throttleMs, maxPages, maxSourceFetchesPerRun } = config.codechef

  async function run(job, handle) {
    const counters = { discovered: 0, imported: 0, sourceFetched: 0, skipped: 0 }
    let sourceBudget = maxSourceFetchesPerRun

    for (let page = 0; page < maxPages; page++) {
      if (page > 0) await sleep(throttleMs)
      const { submissions, maxPage } = await client.fetchRecentPage(handle, page)
      if (submissions.length === 0) break

      counters.discovered += submissions.length
      const existing = await repos.submissions.existing(
        job.userId,
        submissions.map((s) => s.submissionId),
      )

      let sawKnown = false
      for (const sub of submissions) {
        const known = existing.get(sub.submissionId)
        if (known?.hasSource) {
          // Fully imported already - nothing to do for this row.
          counters.skipped++
          sawKnown = true
          continue
        }
        if (known) sawKnown = true

        let sourceCode = null
        const wantsSource =
          client.hasSession && ACCEPTED_RE.test(sub.result ?? "") && sourceBudget > 0
        if (wantsSource) {
          await sleep(throttleMs)
          sourceBudget--
          sourceCode = await client.fetchSolutionSource(sub.submissionId)
          if (sourceCode !== null) counters.sourceFetched++
        }

        const { inserted } = await repos.submissions.upsert(job.userId, {
          ...sub,
          sourceCode,
          sourceFetchedAt: sourceCode !== null ? new Date() : null,
        })
        if (inserted) counters.imported++
        else if (sourceCode === null) counters.skipped++
      }

      await repos.importJobs.update(job.id, counters)

      // Once a page contained only already-known submissions, everything
      // older is known too - stop paging early.
      if (sawKnown && submissions.every((s) => existing.has(s.submissionId))) break
      if (maxPage > 0 && page + 1 >= maxPage) break
    }

    return counters
  }

  return {
    /** Create a job row and run it asynchronously. Returns the queued job. */
    async start(userId, handle) {
      const job = await repos.importJobs.create(userId, { platform: "codechef", handle })
      ;(async () => {
        await repos.importJobs.update(job.id, { status: "running", startedAt: new Date() })
        try {
          const counters = await run(job, handle)
          await repos.importJobs.update(job.id, {
            ...counters,
            status: "completed",
            finishedAt: new Date(),
          })
        } catch (err) {
          log.error?.(`codechef import ${job.id} failed:`, err.message)
          await repos.importJobs
            .update(job.id, { status: "failed", error: err.message, finishedAt: new Date() })
            .catch(() => {})
        }
      })()
      return job
    },

    /** Exposed for tests: run a job to completion synchronously. */
    _run: run,
  }
}
