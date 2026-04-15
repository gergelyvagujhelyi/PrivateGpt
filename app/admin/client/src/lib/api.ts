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
    // Identity is resolved server-side from the bearer token; client uses /me.
    getUsage: async (): Promise<UsageSummary> =>
      call("/usage/me", await getToken(msal)),
    getPreferences: async (): Promise<Preferences> =>
      call("/preferences/me", await getToken(msal)),
    updatePreferences: async (patch: Partial<Preferences>): Promise<Preferences> =>
      call("/preferences/me", await getToken(msal), {
        method: "PUT",
        body: JSON.stringify(patch),
      }),
    getModels: async (): Promise<ModelCatalogue> => call("/models", await getToken(msal)),
  };
}
