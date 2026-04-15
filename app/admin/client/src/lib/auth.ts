import type { Configuration } from "@azure/msal-browser";

export type AppConfig = {
  tenantId: string;
  clientId: string;
  apiScope: string;
};

export async function fetchAppConfig(): Promise<AppConfig> {
  const res = await fetch("/api/config");
  if (!res.ok) throw new Error(`/api/config returned ${res.status}`);
  return (await res.json()) as AppConfig;
}

export function buildMsalConfig(cfg: AppConfig): Configuration {
  return {
    auth: {
      clientId: cfg.clientId,
      authority: `https://login.microsoftonline.com/${cfg.tenantId}`,
      redirectUri: window.location.origin,
      navigateToLoginRequestUrl: true,
    },
    cache: { cacheLocation: "sessionStorage", storeAuthStateInCookie: false },
  };
}

export function buildLoginRequest(cfg: AppConfig) {
  return { scopes: [cfg.apiScope, "openid", "profile", "email"] };
}
