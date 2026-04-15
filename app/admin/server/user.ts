import { pool } from "./db.js";

const TTL_MS = 5 * 60 * 1000;
const MAX_ENTRIES = 500;

type Entry = { userId: string; expiresAt: number };
const cache = new Map<string, Entry>();

function get(email: string): string | null {
  const hit = cache.get(email);
  if (!hit) return null;
  if (hit.expiresAt < Date.now()) {
    cache.delete(email);
    return null;
  }
  return hit.userId;
}

function put(email: string, userId: string): void {
  if (cache.size >= MAX_ENTRIES) {
    // Drop the oldest-inserted entry. Map preserves insertion order.
    const oldest = cache.keys().next().value;
    if (oldest) cache.delete(oldest);
  }
  cache.set(email, { userId, expiresAt: Date.now() + TTL_MS });
}

export async function resolveOpenwebuiUserId(email: string): Promise<string | null> {
  const cached = get(email);
  if (cached) return cached;

  const { rows } = await pool().query<{ id: string }>(
    'SELECT id FROM "user" WHERE LOWER(email) = $1 LIMIT 1',
    [email],
  );
  if (rows.length === 0) return null;
  put(email, rows[0].id);
  return rows[0].id;
}

/** Test helper — clears the cache so unit tests don't leak state. */
export function _clearCache(): void {
  cache.clear();
}
