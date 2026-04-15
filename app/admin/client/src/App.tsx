import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from "@azure/msal-react";
import { Link, Route, Routes } from "react-router-dom";

import { loginRequest } from "./lib/auth";
import { Dashboard } from "./pages/Dashboard";
import { Models } from "./pages/Models";
import { Preferences } from "./pages/Preferences";

export function App() {
  const { instance } = useMsal();
  return (
    <div style={{ fontFamily: "-apple-system, Segoe UI, sans-serif", maxWidth: 960, margin: "0 auto", padding: 24 }}>
      <header style={{ display: "flex", justifyContent: "space-between", marginBottom: 24 }}>
        <h1 style={{ color: "#0078D4", margin: 0 }}>AI Assistant — Admin</h1>
        <AuthenticatedTemplate>
          <button onClick={() => instance.logoutRedirect()}>Sign out</button>
        </AuthenticatedTemplate>
      </header>

      <UnauthenticatedTemplate>
        <div style={{ textAlign: "center", padding: 48 }}>
          <button onClick={() => instance.loginRedirect(loginRequest)}>Sign in with Microsoft</button>
        </div>
      </UnauthenticatedTemplate>

      <AuthenticatedTemplate>
        <nav style={{ display: "flex", gap: 16, marginBottom: 16 }}>
          <Link to="/">Dashboard</Link>
          <Link to="/preferences">Preferences</Link>
          <Link to="/models">Models</Link>
        </nav>
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/preferences" element={<Preferences />} />
          <Route path="/models" element={<Models />} />
        </Routes>
      </AuthenticatedTemplate>
    </div>
  );
}
