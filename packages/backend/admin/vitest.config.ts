import { defineConfig } from "vitest/config";

// The assets test imports web/app.css as text (`?raw`), which Vitest blanks unless CSS is processed.
export default defineConfig({ test: { css: true } });
