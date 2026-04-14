import { Router } from "express";

import { pool } from "../db.ts";
import { PreferencesPatchSchema, PreferencesSchema } from "../../shared/schema.ts";

export const preferencesRouter = Router();

preferencesRouter.get("/:userId", async (req, res) => {
  if (req.params.userId !== (req as express.Request & { userId?: string }).userId) {
    return res.status(403).json({ error: "can only read your own preferences" });
  }
  const { rows } = await pool().query(
    `SELECT user_id, digest_frequency, unsubscribed_at, last_sent_at
       FROM user_preferences WHERE user_id = $1`,
    [req.params.userId],
  );
  if (rows.length === 0) {
    return res.json(
      PreferencesSchema.parse({
        userId: req.params.userId,
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

preferencesRouter.put("/:userId", async (req, res) => {
  if (req.params.userId !== (req as express.Request & { userId?: string }).userId) {
    return res.status(403).json({ error: "can only update your own preferences" });
  }
  const patch = PreferencesPatchSchema.parse(req.body);
  const { rows } = await pool().query(
    `INSERT INTO user_preferences (user_id, digest_frequency)
     VALUES ($1, $2)
     ON CONFLICT (user_id) DO UPDATE
       SET digest_frequency = EXCLUDED.digest_frequency,
           updated_at       = NOW()
     RETURNING user_id, digest_frequency, unsubscribed_at, last_sent_at`,
    [req.params.userId, patch.digestFrequency ?? "off"],
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

import type express from "express";
