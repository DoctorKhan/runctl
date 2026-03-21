# Runctl

Picks a **free port**, runs your **dev server in the background**, and keeps **PID + port** state in **`.run/`** and **`~/.run`** so projects don’t collide.

**Needs Node.js 18+** and **bash**.

---

## Install

**In a project (most people):**

```bash
pnpm add -D runctl
```

Same idea with npm or yarn: `npm install -D runctl`, `yarn add -D runctl`.  
If the published name is scoped, use that instead (e.g. `@your-org/runctl`).

**Global CLI** (`runctl` on your PATH everywhere):

```bash
pnpm add -g runctl
# or
npm install -g runctl
```

**One-liner with curl** (uses npm/pnpm to install from this repo on GitHub — you need Node installed):

```bash
curl -fsSL https://raw.githubusercontent.com/DoctorKhan/devport-kit/main/scripts/install-global.sh | bash
```

After you **[publish to npm](https://docs.npmjs.com/creating-and-publishing-scoped-public-packages)**, install from the registry instead:

```bash
RUNCTL_PACKAGE=runctl curl -fsSL https://raw.githubusercontent.com/DoctorKhan/devport-kit/main/scripts/install-global.sh | bash
```

For a **scoped** registry package:  
`RUNCTL_PACKAGE=@your-org/runctl curl -fsSL https://raw.githubusercontent.com/DoctorKhan/devport-kit/main/scripts/install-global.sh | bash`

---

## Quick start

Add scripts (change `next dev` to match your app):

```json
{
  "scripts": {
    "dev:server": "next dev",
    "dev": "RUNCTL_PM_RUN_SCRIPT=dev:server runctl start-dev",
    "dev:stop": "runctl stop-dev"
  }
}
```

- **`pnpm run dev`** — start (port in `.run/ports.env`, logs in `.run/logs/`).
- **`pnpm run dev:stop`** — stop and drop this repo’s port entries in `~/.run`.

**Why two scripts?** `runctl start-dev` runs `pnpm run <name>`. If `dev` were only `runctl start-dev`, it would call itself in a loop. The real server lives on **`dev:server`**; **`RUNCTL_PM_RUN_SCRIPT`** tells runctl which script to run.

---

## More commands

| Command | What it does |
|---------|----------------|
| `runctl status-dev` | `.run` state for this package |
| `runctl list` / `runctl gc` | List / clean `~/.run/ports` |
| `runctl expand-env env.manifest --out .env.local` | Expand env aliases |

**Monorepo:** `runctl start-dev ./apps/web`  
**Vite:** if `--port` isn’t forwarded, set `server.port` from `process.env.PORT` in `vite.config`.

---

## Docs & examples

[`examples/consumer-package.json`](examples/consumer-package.json) · [`docs/vercel-and-env.md`](docs/vercel-and-env.md) · [`examples/env.manifest.example`](examples/env.manifest.example)

**Develop this repo:** `pnpm install` → `pnpm run run -- list`
