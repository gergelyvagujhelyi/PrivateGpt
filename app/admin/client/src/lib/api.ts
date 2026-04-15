import { useMsal } from "@azure/msal-react";

import { buildLoginRequest } from "./auth";
import { useAppConfig } from "./config-context";
import type { ModelCatalogue, Preferences, UsageSummary } from "../../../shared/schema";

async function call<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`/api${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json() as Promise<T>;
}

export function useApi() {
  const msal = useMsal();
  const cfg = useAppConfig();

  async function getToken(): Promise<string> {
    const account = msal.accounts[0];
    if (!account) throw new Error("not signed in");
    const result = await msal.instance.acquireTokenSilent({
      ...buildLoginRequest(cfg),
      account,
    });
    return result.accessToken;
  }

  return {
    getUsage: async (): Promise<UsageSummary> =>
      call("/usage/me", await getToken()),
    getPreferences: async (): Promise<Preferences> =>
      call("/preferences/me", await getToken()),
    updatePreferences: async (patch: Partial<Preferences>): Promise<Preferences> =>
      call("/preferences/me", await getToken(), {
        method: "PUT",
        body: JSON.stringify(patch),
      }),
    getModels: async (): Promise<ModelCatalogue> => call("/models", await getToken()),
  };
}
