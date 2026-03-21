# Runner

Lightweight **project `.run/`** + **user `~/.run/`** helpers: PID files, logs, a small **port → project** registry, and **optional `pnpm|yarn|npm run dev` wiring** for Vite, Next.js, Nuxt, Astro, Remix, or anything that only needs `PORT`. No daemon, no containers.

## Install once, use in every other repo

You **do not** copy `lib/`, `scripts/`, and `docs/` into each application. Keep **one** Runner checkout (or one linked package); each app only needs a **short** `run.sh` (see [`examples/run.sh.example`](examples/run.sh.example)) that points at that install.

**Ways to expose the toolkit:**

| Method | What you do | In each app’s `run.sh` |
|--------|-------------|-------------------------|
| **Global CLI** | From this directory: `pnpm link --global` (or add `bin/` to your `PATH`) | `source "$(runner lib-path)"` |
| **Env var** | In `~/.zshrc`: `export RUNNER_HOME="$HOME/Documents/Projects/Runner"` | `source "$RUNNER_HOME/lib/run-lib.sh"` |
| **Explicit path** | Nothing | `RUN_LIB=/path/to/Runner/lib/run-lib.sh` then `source "$RUN_LIB"` |
| **pnpm dependency** | In an app: `pnpm add -D runner@file:../Runner` (adjust path) | `source "$PWD/node_modules/runner/lib/run-lib.sh"` (or `pnpm exec runner lib-path`) |

The **`runner`** binary ([`bin/runner`](bin/runner)) resolves paths relative to the Runner install, so `runner expand-env …`, `runner list`, and `runner lib-path` work from any cwd after it is on `PATH`.

### How other developers get it (npm vs no install)

**npm / pnpm (per project)** — publish this repo under a **scoped** name you control (the unscoped name `runner` is likely taken on the public registry), then teammates run:

```bash
pnpm add -D @your-org/runner
# or, before publishing:
pnpm add -D runner@github:your-org/Runner#main
```

They get `node_modules/@your-org/runner/` with `lib/`, `bin/`, `scripts/`. Point `run.sh` at:

`source "$PWD/node_modules/@your-org/runner/lib/run-lib.sh"`

or put `node_modules/.bin` on `PATH` and use `pnpm exec runner lib-path`. To publish yourself: set `"private": false`, pick `"name": "@your-org/runner"`, `npm publish` / `pnpm publish`.

**npm global** — `npm install -g .` or `pnpm link --global` from a clone gives the `runner` command everywhere; no per-app `node_modules` entry.

**No package manager (bash-only)** — the **core** workflow (PIDs, `~/.run`, `run_start_package_dev`) only needs **`lib/run-lib.sh`**: copy that single file into a repo (e.g. `scripts/vendor/run-lib.sh`) or `curl` it from raw git, and `source` it. You **skip** `runner expand-env` unless you also vendor [`scripts/expand-env-manifest.mjs`](scripts/expand-env-manifest.mjs) (needs Node, no extra npm deps) or use another dotenv tool.

So: **npm install is optional**; it is mainly a convenient way to ship **`bin/runner` + lib + script** together and version them. A lone bash file is enough if you accept manual updates and optional features.

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
./run.sh status    # Runner’s own .run state
./run.sh lib-path  # path to lib/run-lib.sh
```

## Drop-in `run.sh` for any sibling project (`../*`)

Copy **[`examples/run.sh.example`](examples/run.sh.example)** to your app root as `run.sh` and `chmod +x run.sh`. It picks up **`runner` on `PATH`**, then **`RUNNER_HOME`**, then a default path—override with **`RUN_LIB`** if you need to.

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
./run.sh expand-env env.manifest --check
```

See **[`docs/vercel-and-env.md`](docs/vercel-and-env.md)** and [`examples/env.manifest.example`](examples/env.manifest.example).
