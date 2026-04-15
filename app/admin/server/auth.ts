import { createRemoteJWKSet, jwtVerify } from "jose";

const tenantId = requireEnv("ENTRA_TENANT_ID");
const audience = requireEnv("ADMIN_API_AUDIENCE");
const issuer = `https://login.microsoftonline.com/${tenantId}/v2.0`;

const jwks = createRemoteJWKSet(
  new URL(`https://login.microsoftonline.com/${tenantId}/discovery/v2.0/keys`),
);

export async function verifyEntraJwt(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, jwks, { issuer, audience });
  const userId = (payload.oid ?? payload.sub) as string | undefined;
  if (!userId) throw new Error("token missing oid/sub");
  return userId;
}

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`missing env: ${key}`);
  return v;
}
