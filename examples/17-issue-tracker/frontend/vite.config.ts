import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const backendPort = process.env.BACKEND_PORT || "5167";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    proxy: {
      "/api": `http://localhost:${backendPort}`,
    },
  },
  build: {
    outDir: "../backend/wwwroot",
    emptyOutDir: true,
  },
});
