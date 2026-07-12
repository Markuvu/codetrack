import bcrypt from "bcryptjs"

export function hashPassword(password, rounds) {
  return bcrypt.hash(password, rounds)
}

export function verifyPassword(password, hash) {
  return bcrypt.compare(password, hash)
}
