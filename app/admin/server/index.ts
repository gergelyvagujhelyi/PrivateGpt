import express from "express";
import { pinoHttp } from "pino-http";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { verifyEntraJwt } from "./auth.js";
import { configRouter } from "./routes/config.js";
import { modelsRouter } from "./routes/models.js";
import { preferencesRouter } from "./routes/preferences.js";
import { usageRouter } from "./routes/usage.js";
import type {} from "./types.js";
import { resolveOpenwebuiUserId } from "./user.js";

const app = express();
app.use(express.json());
app.use(pinoHttp());

app.get("/health", (_req, res) => res.json({ ok: true }));

// Public — the SPA needs this before it can initialise MSAL.
app.use("/api/config", configRouter);

// Everything else under /api requires a valid Entra JWT and a resolvable OpenWebUI user row.
app.use("/api", async (req, res, next) => {
  const auth = req.header("authorization");
  if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "missing bearer token" });
  try {
    const user = await verifyEntraJwt(auth.slice(7));
    const openwebuiUserId = await resolveOpenwebuiUserId(user.email);
    if (!openwebuiUserId) {
      return res.status(403).json({ error: "user not provisioned in OpenWebUI" });
    }
    req.auth = user;
    req.openwebuiUserId = openwebuiUserId;
    next();
  } catch (err) {
    req.log.warn({ err }, "auth_failed");
    return res.status(401).json({ error: "invalid token" });
  }
});

app.use("/api/usage", usageRouter);
app.use("/api/preferences", preferencesRouter);
app.use("/api/models", modelsRouter);

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientDist = path.resolve(__dirname, "..", "client");
app.use(express.static(clientDist));
app.get("*", (_req, res) => res.sendFile(path.join(clientDist, "index.html")));

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => console.log(`admin listening on ${port}`));
