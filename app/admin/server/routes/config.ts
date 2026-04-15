import { Router } from "express";

// Unauthenticated: the SPA needs these values *before* it can even
// initialise MSAL. tenantId + clientId are public anyway — single-page
// apps traditionally bake them into the HTML. The sensitive side is
// verified server-side against Entra JWKS regardless.
export const configRouter = Router();

configRouter.get("/", (_req, res) => {
  const tenantId = process.env.ENTRA_TENANT_ID;
  const clientId = process.env.ADMIN_API_AUDIENCE;
  if (!tenantId || !clientId) {
    return res.status(500).json({ error: "server missing ENTRA_TENANT_ID / ADMIN_API_AUDIENCE" });
  }
  res.json({
    tenantId,
    clientId,
    apiScope: `api://${clientId}/.default`,
  });
});
