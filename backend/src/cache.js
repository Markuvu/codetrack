// Minimal in-memory TTL cache. Swap for Redis when you deploy for real users.
const store = new Map()

export const cache = {
  get(key) {
    const entry = store.get(key)
    if (!entry) return undefined
    if (Date.now() > entry.expiresAt) {
      store.delete(key)
      return undefined
    }
    return entry.value
  },

  set(key, value, ttlSeconds) {
    store.set(key, { value, expiresAt: Date.now() + ttlSeconds * 1000 })
  },

  /** Return cached value for key, or compute it with fn and cache for ttlSeconds. */
  async wrap(key, ttlSeconds, fn) {
    const hit = this.get(key)
    if (hit !== undefined) return hit
    const value = await fn()
    this.set(key, value, ttlSeconds)
    return value
  },
}
