import { useMsal } from "@azure/msal-react";

import { loginRequest } from "./auth";
import type { ModelCatalogue, Preferences, UsageSummary } from "../../../shared/schema";

async function getToken(msal: ReturnType<typeof useMsal>): Promise<string> {
  const account = msal.accounts[0];
  if (!account) throw new Error("not signed in");
  const result = await msal.instance.acquireTokenSilent({
    ...loginRequest,
    account,
  });
  return result.accessToken;
}

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
  return {
    getUsage: async (userId: string): Promise<UsageSummary> =>
      call(`/usage/${encodeURIComponent(userId)}`, await getToken(msal)),
    getPreferences: async (userId: string): Promise<Preferences> =>
      call(`/preferences/${encodeURIComponent(userId)}`, await getToken(msal)),
    updatePreferences: async (userId: string, patch: Partial<Preferences>): Promise<Preferences> =>
      call(`/preferences/${encodeURIComponent(userId)}`, await getToken(msal), {
        method: "PUT",
        body: JSON.stringify(patch),
      }),
    getModels: async (): Promise<ModelCatalogue> => call("/models", await getToken(msal)),
  };
}
