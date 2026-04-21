import { PublicClientApplication } from "@azure/msal-browser";
import { MsalProvider } from "@azure/msal-react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";

import { App } from "./App";
import { AppConfigContext } from "./lib/config-context";
import { buildMsalConfig, fetchAppConfig } from "./lib/auth";

const root = ReactDOM.createRoot(document.getElementById("root")!);

function BootstrapError({ error }: { error: unknown }) {
  return (
    <div style={{ fontFamily: "-apple-system, Segoe UI, sans-serif", maxWidth: 640, margin: "10vh auto", padding: 24, color: "#1f2937" }}>
      <h1 style={{ color: "#C0392B", marginBottom: 8 }}>Admin UI failed to start</h1>
      <p style={{ marginTop: 0 }}>
        The admin service couldn't load its configuration. This usually means
        the backend is unreachable or the <code>ENTRA_TENANT_ID</code> /
        <code>ADMIN_API_AUDIENCE</code> env vars aren't set on the container.
      </p>
      <pre style={{ background: "#F3F4F6", padding: 12, borderRadius: 6, fontSize: 12, overflowX: "auto" }}>
        {String(error instanceof Error ? error.message : error)}
      </pre>
      <p style={{ fontSize: 13, color: "#6b7280" }}>Refresh once the backend is back, or contact the platform team.</p>
    </div>
  );
}

// Wrapped in an async IIFE — top-level await needs an ES2022 module target,
// and Vite's default target (ES2020) rejects it.
(async () => {
  try {
    const config = await fetchAppConfig();
    const msal = new PublicClientApplication(buildMsalConfig(config));
    await msal.initialize();

    const queryClient = new QueryClient({
      defaultOptions: { queries: { staleTime: 30_000, retry: 1 } },
    });

    root.render(
      <React.StrictMode>
        <AppConfigContext.Provider value={config}>
          <MsalProvider instance={msal}>
            <QueryClientProvider client={queryClient}>
              <BrowserRouter>
                <App />
              </BrowserRouter>
            </QueryClientProvider>
          </MsalProvider>
        </AppConfigContext.Provider>
      </React.StrictMode>,
    );
  } catch (err) {
    console.error("admin bootstrap failed", err);
    root.render(<BootstrapError error={err} />);
  }
})();
