import { Router } from "express";

import { pool } from "../db.js";
import { PreferencesPatchSchema, PreferencesSchema } from "../../shared/schema.js";

export const preferencesRouter = Router();

preferencesRouter.get("/me", async (req, res) => {
  const userId = req.openwebuiUserId!;
  const { rows } = await pool().query(
    `SELECT user_id, digest_frequency, unsubscribed_at, last_sent_at
       FROM user_preferences WHERE user_id = $1`,
    [userId],
  );
  if (rows.length === 0) {
    return res.json(
      PreferencesSchema.parse({
        userId,
        digestFrequency: "off",
        unsubscribedAt: null,
        lastSentAt: null,
      }),
    );
  }
  const row = rows[0];
  res.json(
    PreferencesSchema.parse({
      userId: row.user_id,
      digestFrequency: row.digest_frequency,
      unsubscribedAt: row.unsubscribed_at?.toISOString() ?? null,
      lastSentAt: row.last_sent_at?.toISOString() ?? null,
    }),
  );
});

preferencesRouter.put("/me", async (req, res) => {
  const userId = req.openwebuiUserId!;
  const patch = PreferencesPatchSchema.parse(req.body);
  const { rows } = await pool().query(
    `INSERT INTO user_preferences (user_id, digest_frequency)
     VALUES ($1, $2)
     ON CONFLICT (user_id) DO UPDATE
       SET digest_frequency = EXCLUDED.digest_frequency,
           updated_at       = NOW()
     RETURNING user_id, digest_frequency, unsubscribed_at, last_sent_at`,
    [userId, patch.digestFrequency ?? "off"],
  );
  const row = rows[0];
  res.json(
    PreferencesSchema.parse({
      userId: row.user_id,
      digestFrequency: row.digest_frequency,
      unsubscribedAt: row.unsubscribed_at?.toISOString() ?? null,
      lastSentAt: row.last_sent_at?.toISOString() ?? null,
    }),
  );
});
