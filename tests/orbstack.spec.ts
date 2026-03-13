import { test, expect } from "@playwright/test";

// OrbStack assigns .orb.local domains to Docker Compose services automatically.
// The domain format is: <service>.<project>.orb.local
// For this repo the service is "web" and the project is "orbstack-playwright-repro".

const DOMAIN = "web.orbstack-playwright-repro.orb.local";

test("curl can reach OrbStack container (sanity check)", async () => {
  const { execSync } = await import("child_process");
  const result = execSync(`curl -sk --max-time 5 https://${DOMAIN}`, {
    encoding: "utf8",
  });
  expect(result).toContain("Welcome to nginx");
});

test("Playwright can reach OrbStack container via HTTPS", async ({ page }) => {
  const response = await page.goto(`https://${DOMAIN}`);
  expect(response?.status()).toBe(200);
  await expect(page.locator("h1")).toContainText("Welcome to nginx");
});

test("Playwright can reach OrbStack container via HTTP", async ({ page }) => {
  const response = await page.goto(`http://${DOMAIN}`);
  expect(response?.status()).toBe(200);
  await expect(page.locator("h1")).toContainText("Welcome to nginx");
});
