import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { useApi } from "../lib/api";
import type { PreferencesPatch } from "../../../shared/schema";

export function Preferences() {
  const api = useApi();
  const qc = useQueryClient();

  const { data } = useQuery({
    queryKey: ["preferences", "me"],
    queryFn: () => api.getPreferences(),
  });

  const { mutate, isPending } = useMutation({
    mutationFn: (patch: PreferencesPatch) => api.updatePreferences(patch),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["preferences", "me"] }),
  });

  if (!data) return <p>Loading…</p>;

  return (
    <section>
      <h2>Digest email</h2>
      <label>
        Frequency:{" "}
        <select
          value={data.digestFrequency}
          onChange={(e) => mutate({ digestFrequency: e.target.value as PreferencesPatch["digestFrequency"] })}
          disabled={isPending}
        >
          <option value="off">Off</option>
          <option value="daily">Daily</option>
          <option value="weekly">Weekly</option>
        </select>
      </label>
      <p style={{ fontSize: 13, color: "#6b7280" }}>
        Last sent: {data.lastSentAt ?? "never"}
        {data.unsubscribedAt && <> · Unsubscribed at {data.unsubscribedAt}</>}
      </p>
    </section>
  );
}
