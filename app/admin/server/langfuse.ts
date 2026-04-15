const host = requireEnv("LANGFUSE_HOST");
const publicKey = requireEnv("LANGFUSE_PUBLIC_KEY");
const secretKey = requireEnv("LANGFUSE_SECRET_KEY");

const basic = Buffer.from(`${publicKey}:${secretKey}`).toString("base64");

type Trace = {
  id: string;
  totalTokens?: number;
  totalCost?: number;
  model?: string;
};

export async function langfuseUsage(
  userId: string,
  since: Date,
): Promise<{
  traceCount: number;
  totalTokens: number;
  costUsd: number;
  topModels: { name: string; count: number }[];
}> {
  const url = new URL("/api/public/traces", host);
  url.searchParams.set("userId", userId);
  url.searchParams.set("fromTimestamp", since.toISOString());
  url.searchParams.set("limit", "500");

  const res = await fetch(url, { headers: { Authorization: `Basic ${basic}` } });
  if (!res.ok) throw new Error(`langfuse ${res.status}`);
  const { data } = (await res.json()) as { data: Trace[] };

  const models = new Map<string, number>();
  let tokens = 0;
  let cost = 0;
  for (const t of data) {
    tokens += t.totalTokens ?? 0;
    cost += t.totalCost ?? 0;
    const m = t.model ?? "unknown";
    models.set(m, (models.get(m) ?? 0) + 1);
  }
  const top = [...models.entries()]
    .sort(([, a], [, b]) => b - a)
    .slice(0, 3)
    .map(([name, count]) => ({ name, count }));

  return { traceCount: data.length, totalTokens: tokens, costUsd: cost, topModels: top };
}

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`missing env: ${key}`);
  return v;
}
