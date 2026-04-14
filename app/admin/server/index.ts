import express from "express";
import pinoHttp from "pino-http";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { verifyEntraJwt } from "./auth.ts";
import { modelsRouter } from "./routes/models.ts";
import { preferencesRouter } from "./routes/preferences.ts";
import { usageRouter } from "./routes/usage.ts";

const app = express();
app.use(express.json());
app.use(pinoHttp());

app.get("/health", (_req, res) => res.json({ ok: true }));

// Everything under /api requires a valid Entra JWT.
app.use("/api", async (req, res, next) => {
  const auth = req.header("authorization");
  if (!auth?.startsWith("Bearer ")) return res.status(401).json({ error: "missing bearer token" });
  try {
    (req as express.Request & { userId?: string }).userId = await verifyEntraJwt(auth.slice(7));
    next();
  } catch (err) {
    req.log.warn({ err }, "jwt_verification_failed");
    return res.status(401).json({ error: "invalid token" });
  }
});

app.use("/api/usage", usageRouter);
app.use("/api/preferences", preferencesRouter);
app.use("/api/models", modelsRouter);

// Serve the Vite-built SPA for anything else.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientDist = path.resolve(__dirname, "..", "client");
app.use(express.static(clientDist));
app.get("*", (_req, res) => res.sendFile(path.join(clientDist, "index.html")));

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => console.log(`admin listening on ${port}`));
