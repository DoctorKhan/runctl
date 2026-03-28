# Runctl

Picks a **free port**, runs your **dev server in the background**, and keeps **PID + port** state in **`.run/`** and **`~/.run`** so projects don't collide.

**Needs Node.js 18+**, **bash**, and **`lsof`** (for free-port detection and `gc`; common on macOS, often `apt install lsof` on Linux).

**Platforms:** macOS / Linux / **WSL**. Not aimed at native Windows shells.

---

## Install

The published package on npm is **`@zendero/runctl`**. The CLI binary on your PATH is still **`runctl`**.

**From the npm registry (recommended):**

```bash
pnpm add -D @zendero/runctl          # or npm install -D / yarn add -D
```

**Global CLI** (`runctl` on your PATH everywhere):

```bash
pnpm add -g @zendero/runctl           # or npm install -g
```

**One-liner (tries npm first, then GitHub):** `scripts/install-global.sh` runs `pnpm add -g @zendero/runctl` (or `npm install -g`). If that fails (offline, 404, auth), it falls back to `git+https://github.com/DoctorKhan/runctl.git#main`. Override the fallback with `RUNCTL_GIT=…`.

```bash
curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh | bash
```

**Directly from this repository (git)** — use the latest `main` without waiting for an npm publish, or pin a branch/tag:

```bash
# dev dependency
pnpm add -D "github:DoctorKhan/runctl#main"
# or with a full URL (same effect)
pnpm add -D "git+https://github.com/DoctorKhan/runctl.git#main"

# global
pnpm add -g "github:DoctorKhan/runctl#main"
```

In `package.json` the dependency resolves to **`@zendero/runctl`** (the name in this repo’s `package.json`). To **pull the latest `main`** after new commits, reinstall (pnpm/npm do not always move git deps on a plain `update`):

```bash
pnpm add -D "github:DoctorKhan/runctl#main"
```

npm (no pnpm):

```bash
npm install -D github:DoctorKhan/runctl#main
```

---

## Quick start

Add scripts to your `package.json`:

```json
{
  "scripts": {
    "dev": "runctl start --script dev:server",
    "dev:server": "next dev",
    "dev:stop": "runctl stop"
  }
}
```

- **`pnpm dev`** — start (port in `.run/ports.env`, logs in `.run/logs/`).
- **`pnpm dev:stop`** — stop and release ports.

**Why two scripts?** `runctl start` runs `pnpm run <name>` under the hood. If `dev` called itself, it would loop. The real server lives on `dev:server`; `--script` tells runctl which one to run. Without `--script`, it defaults to running `dev`.

**`predev`:** If you define `predev` next to `dev` (e.g. a doctor step) and your script name is `dev:*` or `dev_*` without its own `pre<script>`, runctl runs `predev` once before starting. Set `RUNCTL_SKIP_PREDEV=1` to skip.

---

## Commands

| Command | What it does |
|---------|-------------|
| `runctl start [dir] [--script name]` | Start dev server (picks free port, backgrounds) |
| `runctl stop [dir]` | Stop daemons & release ports |
| `runctl status [dir]` | Show `.run` state for this package |
| `runctl ports` | List user-wide port registry (`~/.run`) |
| `runctl ports gc` | Clean up stale port claims |
| `runctl env expand <manifest> [--out file]` | Generate `.env.local` from manifest |
| `runctl update` | Update to latest version |
| `runctl version` | Print install location |

**Monorepo:** `runctl start ./apps/web --script dev:server`

**Vite:** if `--port` isn't forwarded, set `server.port` from `process.env.PORT` in `vite.config`.

---

## Fits / doesn't fit

| Kind of repo | Runctl |
|--------------|--------|
| Next.js, Vite, SvelteKit, Nuxt, Astro, Remix | **Good fit** — port flags wired for common stacks. |
| **pnpm**, **npm**, **yarn**, **bun** lockfiles | **Supported** for `run <script>`. |
| **`predev`** + split `dev` / `dev:server` | **Supported** — see above. |
| Monorepo app in a subfolder | Use `runctl start ./apps/web`. |
| **No `package.json`** (Python, Go, etc.) | **Not a fit** — this tool is for Node package scripts. |
| Custom Node entry (gateways, CLIs) | **Weak fit** — `PORT`/`HOST` are set, but no framework CLI flags. |

---

## Docs & examples

[`examples/consumer-package.json`](examples/consumer-package.json) · [`docs/vercel-and-env.md`](docs/vercel-and-env.md) · [`examples/env.manifest.example`](examples/env.manifest.example)

**Develop this repo:** `pnpm install` → `./run.sh ports`
