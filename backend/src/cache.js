// Minimal in-memory TTL cache. Swap for Redis when you deploy for real users.
const store = new Map()

export const cache = {
  getEntry(key) {
    const entry = store.get(key)
    if (!entry) return undefined
    if (Date.now() > entry.expiresAt) {
      store.delete(key)
      return undefined
    }
    return entry
  },

  get(key) {
    return this.getEntry(key)?.value
  },

  set(key, value, ttlSeconds) {
    store.set(key, {
      value,
      createdAt: Date.now(),
      expiresAt: Date.now() + ttlSeconds * 1000,
    })
  },

  /**
   * Return cached value for key, or compute it with fn and cache for ttlSeconds.
   *
   * Pass { maxAgeSeconds } to treat cached entries older than that as stale.
   * Used for user-triggered refreshes: the entry is refetched even though its
   * TTL hasn't expired, but a small maxAge acts as a cooldown so repeated
   * pull-to-refresh doesn't hammer the upstream sites.
   */
  async wrap(key, ttlSeconds, fn, { maxAgeSeconds } = {}) {
    const entry = this.getEntry(key)
    if (entry !== undefined) {
      const ageSeconds = (Date.now() - (entry.createdAt ?? 0)) / 1000
      if (maxAgeSeconds === undefined || ageSeconds <= maxAgeSeconds) {
        return entry.value
      }
    }
    const value = await fn()
    this.set(key, value, ttlSeconds)
    return value
  },
}
