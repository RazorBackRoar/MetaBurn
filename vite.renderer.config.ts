import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const appCore = path.resolve(__dirname, "..", "electron-core");
const nodeModules = path.resolve(__dirname, "node_modules");

const packageAliases: Record<string, string> = {};
for (const pkg of ["react", "react-dom"]) {
  const pkgRoot = path.resolve(nodeModules, pkg);
  packageAliases[pkg] = pkgRoot;
  packageAliases[pkg + "/jsx-runtime"] = path.resolve(pkgRoot, "jsx-runtime");
  packageAliases[pkg + "/jsx-dev-runtime"] = path.resolve(pkgRoot, "jsx-dev-runtime");
  packageAliases[pkg + "/client"] = path.resolve(pkgRoot, "client");
  packageAliases[pkg + "/server"] = path.resolve(pkgRoot, "server");
}

const appAliases = Object.fromEntries(
  [
    "backend",
    "preload",
    "ipc",
    "components",
    "hooks",
    "utils",
    "oauth",
    "build",
  ].map((name) => [
    "@electron-core/" + name,
    path.resolve(appCore, name),
  ]),
);

export default defineConfig({
  root: __dirname,
  base: "./",
  publicDir: "public",
  build: {
    outDir: "build",
    emptyOutDir: false,
    rollupOptions: {
      input: {
        main: path.resolve(__dirname, "main-window.html"),
        settings: path.resolve(__dirname, "settings-window.html"),
      },
    },
  },
  resolve: {
    alias: { ...packageAliases, ...appAliases },
  },
  server: {
    strictPort: true,
    port: 5173,
    fs: {
      allow: [__dirname, appCore],
    },
  },
  define: {
    __APP_DISPLAY_NAME__: JSON.stringify("MetaBurn"),
  },
  plugins: [react(), tailwindcss()],
});
