import { useQuery } from "@tanstack/react-query";

import { useApi } from "../lib/api";

export function Models() {
  const api = useApi();
  const { data, isLoading } = useQuery({ queryKey: ["models"], queryFn: api.getModels });

  if (isLoading || !data) return <p>Loading…</p>;

  return (
    <section>
      <h2>Models available</h2>
      <table style={{ borderCollapse: "collapse", width: "100%" }}>
        <thead>
          <tr>
            {["Name", "Provider", "Purpose", "Exposed as"].map((h) => (
              <th key={h} style={{ textAlign: "left", borderBottom: "2px solid #eee", padding: "6px 8px" }}>
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {data.models.map((m) => (
            <tr key={m.name}>
              <td style={{ padding: "6px 8px" }}>{m.name}</td>
              <td style={{ padding: "6px 8px" }}>{m.provider}</td>
              <td style={{ padding: "6px 8px" }}>{m.purpose}</td>
              <td style={{ padding: "6px 8px" }}><code>{m.exposedAs}</code></td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
