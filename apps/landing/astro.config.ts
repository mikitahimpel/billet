import { fileURLToPath } from "node:url";
import react from "@astrojs/react";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";
import { writeMarkdownTwins } from "./scripts/ai/build-markdown.mjs";
import { siteUrl } from "./src/config";

export default defineConfig({
  site: siteUrl,
  // Every page is a folder (/faq/ → /faq/index.html), so its Markdown twin sits beside it at /faq/index.md.
  trailingSlash: "always",
  integrations: [
    react(),
    {
      name: "markdown-twins",
      hooks: {
        "astro:build:done": ({ dir, logger }) => {
          logger.info(`${writeMarkdownTwins(fileURLToPath(dir), siteUrl)} markdown twins written`);
        },
      },
    },
  ],
  devToolbar: { enabled: false },
  vite: { plugins: [tailwindcss()] },
});
