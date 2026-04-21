/// <reference types="vitest" />
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  root: "client",
  plugins: [react()],
  build: {
    outDir: "../dist/client",
    emptyOutDir: true,
    sourcemap: true,
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:4000",
    },
  },
  // Tests live alongside server + shared code; override Vite's client-only
  // root so vitest scans the whole package.
  test: {
    root: ".",
    include: ["{server,shared,client}/**/*.{test,spec}.?(c|m)[jt]s?(x)"],
  },
});
