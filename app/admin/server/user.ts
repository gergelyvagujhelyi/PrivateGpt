import { pool } from "./db.js";

const cache = new Map<string, string>(); // email → openwebui user id

export async function resolveOpenwebuiUserId(email: string): Promise<string | null> {
  const cached = cache.get(email);
  if (cached) return cached;

  const { rows } = await pool().query<{ id: string }>(
    'SELECT id FROM "user" WHERE LOWER(email) = $1 LIMIT 1',
    [email],
  );
  if (rows.length === 0) return null;
  cache.set(email, rows[0].id);
  return rows[0].id;
}
