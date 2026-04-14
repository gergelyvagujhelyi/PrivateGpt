import { Router } from "express";

import { UsageSummarySchema } from "../../shared/schema.ts";
import { langfuseUsage } from "../langfuse.ts";

export const usageRouter = Router();

usageRouter.get("/:userId", async (req, res) => {
  if (req.params.userId !== (req as express.Request & { userId?: string }).userId) {
    return res.status(403).json({ error: "can only read your own usage" });
  }
  const windowDays = Number(req.query.days ?? 7);
  const since = new Date(Date.now() - windowDays * 24 * 3600 * 1000);
  const summary = await langfuseUsage(req.params.userId, since);
  res.json(UsageSummarySchema.parse({ userId: req.params.userId, windowDays, ...summary }));
});

import type express from "express";
