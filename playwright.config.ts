import { defineConfig } from "@playwright/test";

export default defineConfig({
  timeout: 15000,
  use: {
    ignoreHTTPSErrors: true,
  },
});
