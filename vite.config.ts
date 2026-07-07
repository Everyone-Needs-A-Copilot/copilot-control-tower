import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST;

// The web UI lives in `src/` per the M1 architecture WP; Tauri's `frontendDist`
// (src-tauri/tauri.conf.json) points at `../dist`, so keep the build output there.
//
// https://vite.dev/config/
export default defineConfig(async () => ({
  root: "src",
  publicDir: false,
  build: {
    outDir: "../dist",
    emptyOutDir: true,
    // Three HTML entry points: the popover (index.html, M1), Settings
    // (settings.html, M2 S7 — the unmanaged/solo/author repo-URL screen), and
    // the first-run wizard (wizard.html, M3 S7). Vite only bundles
    // `index.html` by default; without this, the other two would build clean
    // but silently not ship in `dist/`, leaving S6/S8 with no page to point a
    // real window at.
    rollupOptions: {
      input: {
        popover: fileURLToPath(new URL("src/index.html", import.meta.url)),
        settings: fileURLToPath(new URL("src/settings.html", import.meta.url)),
        wizard: fileURLToPath(new URL("src/wizard.html", import.meta.url)),
      },
    },
  },

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || false,
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));
