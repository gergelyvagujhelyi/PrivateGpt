import { useMsal } from "@azure/msal-react";
import { useQuery } from "@tanstack/react-query";

import { useApi } from "../lib/api";

export function Dashboard() {
  const msal = useMsal();
  const userId = msal.accounts[0]?.homeAccountId ?? "";
  const api = useApi();

  const { data, isLoading, error } = useQuery({
    queryKey: ["usage", userId],
    queryFn: () => api.getUsage(userId),
    enabled: Boolean(userId),
  });

  if (isLoading) return <p>Loading…</p>;
  if (error) return <p style={{ color: "#C0392B" }}>Error: {String(error)}</p>;
  if (!data) return null;

  return (
    <section>
      <h2>Your last {data.windowDays} days</h2>
      <dl style={{ display: "grid", gridTemplateColumns: "max-content 1fr", gap: "4px 16px" }}>
        <dt>Conversations</dt>    <dd>{data.traceCount}</dd>
        <dt>Tokens</dt>           <dd>{data.totalTokens.toLocaleString()}</dd>
        <dt>Cost (USD)</dt>       <dd>{data.costUsd.toFixed(3)}</dd>
        <dt>Top models</dt>
        <dd>{data.topModels.map((m) => `${m.name} (${m.count})`).join(", ") || "—"}</dd>
      </dl>
    </section>
  );
}
