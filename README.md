# Runctl

Lightweight **project `.run/`** + **user `~/.run/`** helpers: PID files, logs, a small **port → project** registry, and **optional `pnpm|yarn|npm run dev` wiring** for Vite, Next.js, Nuxt, Astro, Remix, or anything that only needs `PORT`. **npm package:** `runctl` (CLI: **`runctl`**). No daemon, no containers.

*(This git repo may still be named `Runner` on disk—that’s fine.)*

## Install once, use in every other repo

You **do not** copy `lib/`, `scripts/`, and `docs/` into each application. Keep **one** Runctl install (clone or package); each app only needs a **short** `run.sh` (see [`examples/run.sh.example`](examples/run.sh.example)) or **`package.json` scripts** that call **`runctl`**.

**Ways to expose the toolkit:**

| Method | What you do | In each app’s `run.sh` |
|--------|-------------|-------------------------|
| **Global CLI** | From this directory: `pnpm link --global` (or add `bin/` to your `PATH`) | `source "$(runctl lib-path)"` |
| **Env var** | In `~/.zshrc`: `export RUNCTL_HOME="$HOME/Documents/Projects/Runner"` (path to this clone) | `source "$RUNCTL_HOME/lib/run-lib.sh"` |
| **Explicit path** | Nothing | `RUN_LIB=/path/to/runctl/lib/run-lib.sh` then `source "$RUN_LIB"` |
| **pnpm dependency** | In an app: `pnpm add -D runctl@file:../Runner` (adjust path) | `source "$PWD/node_modules/runctl/lib/run-lib.sh"` (or `pnpm exec runctl lib-path`) |
| **package.json only** | Same dependency; **no `run.sh`** | Add `"scripts"` that call `runctl` (see below) |

The **`runctl`** binary ([`bin/runctl`](bin/runctl)) resolves paths relative to the package root, so `runctl expand-env …`, `runctl list`, and `runctl lib-path` work from any cwd after it is on `PATH`.

### `package.json` scripts only (no `run.sh`)

After `pnpm add -D @your-org/runctl`, npm/pnpm put `node_modules/.bin` on `PATH` when you run **`pnpm run`**, so you can wire everything as scripts.

**Important:** `runctl start-dev` runs **`pnpm run <script>`** (default script name **`dev`**). If you set `"dev": "runctl start-dev"`, that **recurses**. Use either:

1. **Split scripts** — real server on another name, `dev` points at Runctl (set **`RUNCTL_PM_RUN_SCRIPT`**):

```json
{
  "scripts": {
    "dev:server": "next dev",
    "dev": "RUNCTL_PM_RUN_SCRIPT=dev:server runctl start-dev",
    "dev:stop": "runctl stop-dev",
    "dev:status": "runctl status-dev",
    "ports:list": "runctl list",
    "ports:gc": "runctl gc",
    "env:expand": "runctl expand-env env.manifest --out .env.local"
  }
}
```

2. **Keep `dev` as the framework** — add a separate script for the managed background dev:

```json
"dev": "next dev",
"dev:bg": "runctl start-dev"
```

Full fragment: [`examples/consumer-package.json`](examples/consumer-package.json). Monorepo app dir (first arg to `start-dev`):  
`"dev:web": "RUNCTL_PM_RUN_SCRIPT=dev:server runctl start-dev ./apps/web"`.

Legacy env **`RUN_RUNNER_PM_RUN_SCRIPT`** is still read if **`RUNCTL_PM_RUN_SCRIPT`** is unset.

That is “scripts in `package.json`” + **one devDependency**: the package ships **`runctl`** (and `lib/` / `scripts/`); you do not vendor our bash into your repo.

### How other developers get it (npm vs no install)

**npm / pnpm (per project)** — publish under **`@your-org/runctl`** (recommended) or try unscoped **`runctl`** if available:

```bash
pnpm add -D @your-org/runctl
# or from git, before publishing:
pnpm add -D runctl@github:your-org/Runner#main
```

They get `node_modules/@your-org/runctl/` with `lib/`, `bin/`, `scripts/`. Point `run.sh` at:

`source "$PWD/node_modules/@your-org/runctl/lib/run-lib.sh"`

or use `pnpm exec runctl lib-path`. To publish: set `"private": false`, `"name": "@your-org/runctl"`, then `npm publish` / `pnpm publish`.

**npm global** — `npm install -g .` or `pnpm link --global` from a clone puts **`runctl`** on `PATH`.

**No package manager (bash-only)** — the **core** workflow only needs **`lib/run-lib.sh`**: copy or `curl` that file and `source` it. You **skip** `runctl expand-env` unless you also vendor [`scripts/expand-env-manifest.mjs`](scripts/expand-env-manifest.mjs) (Node, no npm deps).

So: **npm install is optional**; it ships **`bin/runctl` + lib + script** together. A lone bash file is enough if you accept manual updates.

## Layout

| Location | Purpose |
|----------|---------|
| `<repo>/.run/pids/<name>.pid` | Background service PID |
| `<repo>/.run/logs/<name>.log` | Log append from `run_daemon_start` |
| `<repo>/.run/ports.env` | Last chosen `PORT` / `HOST` (source for scripts) |
| `<repo>/.run/claimed-ports` | Ports this repo registered globally (one per line) |
| `~/.run/ports/<port>` | Key/value file: `project_root`, `slug`, `service`, `pid`, `started` |
| `~/.run/projects/<slug>/ports.log` | Append-only audit trail (optional) |

Override the user directory with `RUN_GLOBAL_STATE` if needed.

## This repo’s CLI

```bash
chmod +x run.sh   # once
./run.sh list      # all registered ports
./run.sh gc        # remove stale ~/.run/ports/* entries
./run.sh status    # this repo’s .run state
./run.sh lib-path  # path to lib/run-lib.sh
```

## Drop-in `run.sh` for any sibling project (`../*`)

Copy **[`examples/run.sh.example`](examples/run.sh.example)** to your app root as `run.sh` and `chmod +x run.sh`. It picks up **`runctl` on `PATH`**, then **`RUNCTL_HOME`**, then a default path—override with **`RUN_LIB`** if you need to.

- **`./run.sh dev`** — picks a free port (see table below), runs `<pm> run dev` in the background, writes `.run/ports.env`, registers `~/.run/ports/<port>`.
- **`./run.sh stop`** — stops PID files for this repo and clears those registry entries.
- **`./run.sh dev web auto -- --turbo`** — forwards extra args after `--` to `npm run dev` / `pnpm run dev`.

### Default base port (when second arg is `auto`)

| Detected dependency | Base port | Flags passed after `dev --` |
|---------------------|-----------|-----------------------------|
| `next` | 3000 | `-p <port>` |
| `nuxt` | 3000 | `--port <port>` |
| `astro` | 4321 | `--port <port>` |
| `vite` / `@vitejs/*` / Svelte plugin | 5173 | `--port <port> --strictPort` |
| `@remix-run/dev` (classic, no Vite) | 3000 | `--port <port>` |
| anything else | 3000 | none (relies on `PORT` + `HOST` in the environment) |

Detection uses `dependencies` + `devDependencies` in **`package.json`**. Remix + Vite templates usually list `vite` and are treated as **Vite** (correct for `vite` CLI).

### Monorepos (`apps/web`, packages, …)

Call **`run_project_init` with the package directory** that contains the `package.json` you want to run, not always the git root:

```bash
run_project_init "$ROOT/apps/web"
```

### Vite: read `PORT` from config

If `vite` does not see CLI args (custom `dev` script), bind the server to the env written by this library:

```ts
// vite.config.ts
import { defineConfig } from "vite";

export default defineConfig({
  server: {
    port: Number(process.env.PORT) || 5173,
    strictPort: true,
  },
});
```

### Next.js, Nuxt, Astro

The library passes the usual CLI port flags; **`PORT` and `HOST` are also exported** for the child process. Set `HOST=0.0.0.0` before `./run.sh dev` if you need LAN access.

### Non-Node stacks

Skip `run_start_package_dev` and use the low-level helpers:

```bash
port="$(run_find_free_port 8000)"
pid="$(run_daemon_start api poetry run uvicorn app:app --host 127.0.0.1 --port "$port")"
run_port_register "$port" api "$pid"
```

## Low-level API (any project)

Use **bash** for `run.sh` (the library uses `shopt` and other bash-only features).

```bash
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_LIB="${RUN_LIB:-$HOME/Documents/Projects/Runner/lib/run-lib.sh}"
# shellcheck source=/dev/null
source "$RUN_LIB"
run_project_init "$ROOT"
```

**Contract**

1. After you know the real **port** and **pid**, call `run_port_register <port> <service> <pid>`.
2. On shutdown, call `run_stop_all` (or `run_stop_all_daemons` then `run_unregister_project_ports`).
3. Prefer stopping by **PID files**, not `kill-port` on shared ports.
4. Wrap multi-step start/stop in **`run_with_lock cmd …`** if two terminals might race.

## Optional: Honcho / Overmind

Use them for prefixed logs; use this library for **PID files** and **`~/.run` registration** (or call `run_port_register` once you know the child URL/port).

## Env vars, shared values, and Vercel

Vercel stores flat keys (no `${ALIAS}` in the UI). For **one value, many names** locally, use a gitignored **`env.manifest`** and expand to `.env.local`:

```bash
./run.sh expand-env env.manifest --out .env.local
runctl expand-env env.manifest --out .env.local
./run.sh expand-env env.manifest --check
```

See **[`docs/vercel-and-env.md`](docs/vercel-and-env.md)** and [`examples/env.manifest.example`](examples/env.manifest.example).
