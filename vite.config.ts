import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  root: "src/frontend",
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
  // The proxy is no longer needed since we are targeting mainnet directly.
  server: undefined,
  define: {
    // Expose the DFX_NETWORK environment variable to the frontend code
    "process.env.DFX_NETWORK": JSON.stringify("ic"),
    // Polyfill Node's global in the browser for libraries that expect it
    global: "globalThis",
  },
});
