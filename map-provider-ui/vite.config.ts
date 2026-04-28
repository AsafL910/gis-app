import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8010",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, "")
      },
      "/cog-data": {
        target: "http://127.0.0.1:8011",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/cog-data/, "")
      },
      "/height-api": {
        target: "http://127.0.0.1:8009",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/height-api/, "")
      }
    }
  }
});
