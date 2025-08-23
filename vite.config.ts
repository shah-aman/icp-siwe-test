import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "path";

// Get the network from the DFX_NETWORK environment variable
const network = process.env.DFX_NETWORK || "local";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  root: "src/frontend",
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
  // The proxy is only needed for local development.
  // When targeting mainnet, the agent will correctly handle requests.
  server:
    network === "local"
      ? {
          proxy: {
            "/api": {
              target: "http://127.0.0.1:4943",
              changeOrigin: true,
              rewrite: (path) => path.replace(/^\/api/, "/api"),
            },
          },
        }
      : undefined,
  define: {
    // Expose the DFX_NETWORK environment variable to the frontend code
    "process.env.DFX_NETWORK": JSON.stringify(network),
    // Polyfill Node's global in the browser for libraries that expect it
    global: "globalThis",
  },
});
