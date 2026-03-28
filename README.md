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

**Global install via curl** uses a single script: [`scripts/install-global.sh`](scripts/install-global.sh)

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash
```

With no arguments, `install-global.sh` prompts on a TTY; otherwise it defaults to registry install with Git fallback. Pass arguments to force a mode:

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --registry
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --auto
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --git --ref main
```

Optional flags: `--pm pnpm|npm`, `--ref <git-ref>`. Optional env: `RUNCTL_PACKAGE`, `RUNCTL_GIT_BASE`, `RUNCTL_GIT_REF`.

**Without curl:**

```bash
pnpm add -g @zendero/runctl
pnpm add -g "github:DoctorKhan/runctl#main"
```

**Project dependency from GitHub** (not global): dependency resolves to **`@zendero/runctl`**. Reinstall to pull the latest `main`:

```bash
pnpm add -D "github:DoctorKhan/runctl#main"
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
| `runctl start` \| `runctl dev` | Start dev server (same command; picks free port, backgrounds) |
| `runctl stop [dir]` | Stop daemons & release ports |
| `runctl status [dir]` | Show `.run` state for this package |
| `runctl logs [dir] [service]` | Tail `.run/logs/<service>.log` (default service: `web`) |
| `runctl ports` | List user-wide port registry (`~/.run`) |
| `runctl ports gc` | Clean up stale port claims |
| `runctl env expand <manifest> [--out file]` | Generate `.env.local` from manifest |
| `runctl doctor [dir]` | Check Node 18+, `lsof`, package manager, `package.json` |
| `runctl update` | Update the global `@zendero/runctl` install |
| `runctl version` | Print package version and install path |

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

**Develop this repo:** `pnpm install` → `./run.sh` (default **doctor**, like `elata-bio-sdk/run.sh`) → `./run.sh ports`

**Publish (maintainers)** — workflow similar to elata’s release preflight, scaled for one package:

| Step | Command |
|------|--------|
| Preflight | `./run.sh release-check` or `pnpm run release-check` |
| Publish | `./run.sh release latest` or `pnpm run release` |
| Promote dist-tag | After publishing under `next`, `./run.sh promote` sets **latest** for the version in `package.json` |

Put `NPM_TOKEN` in `.env`. `release` / `npm-whoami` use a **temporary `NPM_CONFIG_USERCONFIG`** so a stale `~/.npmrc` token does not override `.env` (npm 10+ / pnpm). Token lines can use `NPM_TOKEN=` or `npm_token=`; quoted values are supported without `source`-ing secrets as shell code first.
