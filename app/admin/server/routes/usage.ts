import { Router } from "express";

import { UsageSummarySchema } from "../../shared/schema.js";
import { langfuseUsage } from "../langfuse.js";

export const usageRouter = Router();

usageRouter.get("/me", async (req, res) => {
  const userId = req.openwebuiUserId!;
  const windowDays = Number(req.query.days ?? 7);
  const since = new Date(Date.now() - windowDays * 24 * 3600 * 1000);
  const summary = await langfuseUsage(userId, since);
  res.json(UsageSummarySchema.parse({ userId, windowDays, ...summary }));
});
