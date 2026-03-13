# OrbStack + Playwright/CDP: ERR_ADDRESS_UNREACHABLE

Minimal reproduction showing that Playwright (and any CDP-based automation) cannot reach OrbStack container domains on macOS, even though the same Chrome binary can reach them via the address bar.

## The Bug

OrbStack routes container IP traffic through macOS **Network.framework**. Chrome's DevTools Protocol (CDP) `Page.navigate` uses Chrome's internal network service which goes through **BSD sockets**, bypassing Network.framework entirely. This means:

| Method | Network layer | Works? |
|--------|--------------|--------|
| `curl` | Network.framework | Yes |
| Chrome address bar | Network.framework | Yes |
| Chrome CDP `Page.navigate` | BSD sockets | **No** |
| Playwright (uses CDP) | BSD sockets | **No** |
| Puppeteer (uses CDP) | BSD sockets | **No** |
| Node.js `net.connect()` | BSD sockets | **No** |
| Python `socket.connect()` | BSD sockets | **No** |

This affects **all** browser automation tools (Playwright, Puppeteer, Selenium via CDP) and **all** browsers (Chromium, Firefox, WebKit) when launched by these tools.

## Prerequisites

- macOS (tested on macOS 15 Sequoia, Apple Silicon)
- [OrbStack](https://orbstack.dev/) installed and running
- [Node.js](https://nodejs.org/) 18+
- Docker (via OrbStack)

## Reproduce

```bash
git clone <this-repo>
cd orbstack-playwright-repro
npm install
bash repro.sh
```

The script will:
1. Start an nginx container via `docker compose`
2. Show that `curl` can reach `https://web.orbstack-playwright-repro.local` (Network.framework)
3. Show that Node.js TCP `connect()` to the container IP fails with `EHOSTUNREACH` (BSD sockets)
4. Run Playwright tests — they fail with `ERR_ADDRESS_UNREACHABLE`
5. Launch Chrome manually, show the address bar loads the page, then show CDP `Page.navigate` to the same URL fails

## Expected behavior

Playwright should be able to navigate to OrbStack container domains, since the same Chrome binary can reach them via the address bar.

## Actual behavior

All CDP-initiated navigation to OrbStack container IPs fails with `net::ERR_ADDRESS_UNREACHABLE`, because CDP's network path uses BSD sockets instead of macOS Network.framework.

## Environment

- macOS 15 Sequoia (Apple Silicon)
- OrbStack 1.x / 2.x
- Playwright 1.52+
- Chrome / Chromium (any version)
- Node.js 18+

## Workaround

Expose container ports to localhost via `docker-compose.override.yml`:

```yaml
services:
  web:
    ports:
      - "8080:80"
```

Then use `http://localhost:8080` instead of `https://web.project.local`.

## Related Issues

- [orbstack/orbstack#1266](https://github.com/orbstack/orbstack/issues/1266) — Containers accessible via Safari but not Chrome (macOS 15)
- [orbstack/orbstack#1415](https://github.com/orbstack/orbstack/issues/1415) — Container domain names do not work in chrome://inspect
- [orbstack/orbstack#2244](https://github.com/orbstack/orbstack/issues/2244) — Local Network Access Broken in Chrome 142
