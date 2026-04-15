import { createContext, useContext } from "react";

import type { AppConfig } from "./auth";

export const AppConfigContext = createContext<AppConfig | null>(null);

export function useAppConfig(): AppConfig {
  const cfg = useContext(AppConfigContext);
  if (!cfg) throw new Error("AppConfig not loaded — provider missing");
  return cfg;
}
