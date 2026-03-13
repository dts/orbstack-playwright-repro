# OrbStack + Playwright/CDP: ERR_ADDRESS_UNREACHABLE (from ad-hoc signed terminals)

Minimal reproduction showing that Playwright (and any CDP-based automation) cannot reach OrbStack container domains on macOS **when run from an ad-hoc signed parent process** (e.g. Homebrew-installed tmux).

## The Bug

OrbStack routes container traffic through a macOS **Network Extension**. macOS restricts Network Extension access based on **code signing** of the process tree. When a parent process (like tmux) is **ad-hoc signed** (`flags=0x2(adhoc)`), all child processes lose access to Network Extension routes — even if the child itself is properly signed.

This means BSD socket connections to OrbStack container IPs fail with `EHOSTUNREACH` / `ERR_ADDRESS_UNREACHABLE`, while Network.framework-based tools (curl, Chrome address bar) continue to work.

| Method | Network layer | Ad-hoc signed parent | Properly signed parent |
|--------|--------------|---------------------|----------------------|
| `curl` | Network.framework | Works | Works |
| Chrome address bar | Network.framework | Works | Works |
| Chrome CDP `Page.navigate` | BSD sockets | **Fails** | Works |
| Playwright (uses CDP) | BSD sockets | **Fails** | Works |
| Node.js `net.connect()` | BSD sockets | **Fails** | Works |
| Python `socket.connect()` | BSD sockets | **Fails** | Works |

## Preconditions to reproduce

You must run the repro script from inside a terminal whose parent process is **ad-hoc signed**. The most common case is **Homebrew-installed tmux**:

```bash
# Check if tmux is ad-hoc signed:
codesign -dvvv $(which tmux) 2>&1 | grep -E 'flags|Signature'
# Ad-hoc will show: flags=0x2(adhoc), Signature=adhoc
```

If you run the repro from a properly signed terminal (e.g. Terminal.app or iTerm2 directly, without tmux), everything will pass.

## Prerequisites

- macOS (tested on macOS 15 Sequoia, Apple Silicon)
- [OrbStack](https://orbstack.dev/) installed and running
- [Node.js](https://nodejs.org/) 18+
- Docker (via OrbStack)
- **tmux** (Homebrew-installed, ad-hoc signed) to trigger the failure

## Reproduce

```bash
# Start tmux (must be ad-hoc signed to trigger the bug)
tmux

# Inside tmux:
git clone <this-repo>
cd orbstack-playwright-repro
npm install
bash repro.sh
```

The script will:
1. Start an nginx container via `docker compose`
2. Show that `curl` can reach `https://web.orbstack-playwright-repro.orb.local` (Network.framework — works)
3. Show that Node.js TCP `connect()` to the container IP fails with `EHOSTUNREACH` (BSD sockets — fails)
4. Run Playwright tests — they fail with `ERR_ADDRESS_UNREACHABLE`
5. Launch Chrome manually, show the address bar loads the page, then show CDP `Page.navigate` to the same URL fails

**Running the same script outside tmux (directly in Terminal.app / iTerm2) will pass all tests.**

## Fix

Sign tmux with your Apple Developer identity:

```bash
# List your signing identities:
security find-identity -v -p codesigning

# Sign tmux (replace with your identity):
codesign -fs "Apple Development: Your Name (XXXXXXXXXX)" /opt/homebrew/bin/tmux

# Verify:
codesign -dvvv /opt/homebrew/bin/tmux 2>&1 | grep -E 'Authority|Signature'
# Should show your developer identity, not "adhoc"
```

Then **restart tmux** (`tmux kill-server && tmux`) and re-run the repro — all tests will pass.

> **Note:** `codesign -fs - /opt/homebrew/bin/tmux` (re-signing ad-hoc) is NOT sufficient. You need a real Apple Developer identity to get Network Extension access.

## Workaround (without signing)

Expose container ports to localhost via `docker-compose.override.yml`:

```yaml
services:
  web:
    ports:
      - "8080:80"
```

Then use `http://localhost:8080` instead of `https://web.project.local`.

Or simply run your tests outside tmux.

## Related Issues

- [orbstack/orbstack#1266](https://github.com/orbstack/orbstack/issues/1266) — Containers accessible via Safari but not Chrome (macOS 15)
- [orbstack/orbstack#1415](https://github.com/orbstack/orbstack/issues/1415) — Container domain names do not work in chrome://inspect
- [orbstack/orbstack#2244](https://github.com/orbstack/orbstack/issues/2244) — Local Network Access Broken in Chrome 142
