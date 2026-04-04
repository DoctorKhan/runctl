# Runctl

Picks a **free port**, runs your **dev server in the background**, and keeps **PID + port** state in **`.run/`** and **`~/.run`** so projects don't collide.

**Needs Node.js 18+**, **bash**, and **`lsof`** (for free-port detection and `gc`; common on macOS, often `apt install lsof` on Linux).

**Platforms:** macOS / Linux / **WSL**. Not aimed at native Windows shells.

---

## Install

Published name on npm is **`@zendero/runctl`**; the CLI on your PATH is **`runctl`**.

| Goal | What to run |
|------|-------------|
| Use runctl **inside one repo** (recommended) | `pnpm add -D @zendero/runctl` — also `npm install -D` / `yarn add -D` |
| **`runctl` everywhere** (global) | `pnpm add -g @zendero/runctl` or the curl installer below |
| Track **main from GitHub** as a dev dependency | `pnpm add -D "github:DoctorKhan/runctl#main"` (still resolves as `@zendero/runctl`; reinstall to update) |

### Global install: package manager vs script

**Package manager** is the straightforward choice if you already use pnpm or npm:

```bash
pnpm add -g @zendero/runctl
```

From Git only:

```bash
pnpm add -g "github:DoctorKhan/runctl#main"
```

**[`scripts/install-global.sh`](scripts/install-global.sh)** is for “one command” setup, **CI**, or when you want **npm first, then Git** without writing two install lines yourself. It requires **bash**, **pnpm or npm** on `PATH`, and network access.

One-liner (same URL the script header documents):

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash
```

Pass script arguments after `bash` (stdin pipe has no argv). To pick a **mode** explicitly:

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --registry
```

### `install-global.sh` reference

If you do **not** pass **`--registry`**, **`--git`**, **`--auto`**, or **`--interactive`**: on an **interactive TTY** with **`CI` not `1`**, the script **prompts** for install source (and related choices). Otherwise it behaves like **`--auto`**: **global install from the npm registry** first; if that fails, **retry from Git** (same URL/ref as `--git`).

**Modes** — each mode picks *where* the global install comes from. Under the hood the script runs **`pnpm add -g …`** or **`npm install -g …`** once per successful path (auto can run **twice**: registry attempt, then Git if the first fails).

| Mode | What it does | When to use it |
|------|----------------|----------------|
| **`--registry`** | **Only** installs `RUNCTL_PACKAGE` (default `@zendero/runctl`) from the npm registry. **No** Git fallback. | You want the published package only—e.g. CI that must not clone Git, or you know npm is enough. |
| **`--git`** | **Only** installs from Git: `RUNCTL_GIT_BASE` + `#` + ref (default ref `main`, overridable with `--ref`). **No** registry attempt first. | You want `main`/a branch/tag from the repo, or the registry is unreachable. |
| **`--auto`** | Tries **`--registry`** first; on **failure**, runs the same Git install as **`--git`**. | Headless installs, pipes, CI: resilient default when you’re fine with either source. |
| **`--interactive`** | Prompts for **registry / git / auto**, optional **Git ref** when git/auto applies, and **pnpm vs npm** if both exist—**only** when a TTY is available. | You want to choose at install time instead of memorizing flags. |

If **`--interactive`** is requested but there is **no usable TTY** (or `CI=1`), the script **falls back to `--auto`** and prints a short notice.

**Flags**

| Flag | Meaning |
|------|---------|
| `--pm pnpm` \| `--pm npm` | Use that package manager (must exist on `PATH`) |
| `--ref <ref>` | Git ref for `--git` or for the Git step of `--auto` (default: `main`) |

**Environment variables** (optional)

| Variable | Purpose |
|----------|---------|
| `RUNCTL_PACKAGE` | npm package name (default: `@zendero/runctl`) |
| `RUNCTL_GIT_BASE` | Git URL without fragment (default: `git+https://github.com/DoctorKhan/runctl.git`) |
| `RUNCTL_GIT_REF` | Default ref when not overridden by `--ref` (default: `main`) |

**Examples**

Registry only (good for locked-down CI that should not hit Git):

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --registry
```

Explicit auto (same as non-interactive default, but spelled out):

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --auto
```

Git only, specific ref:

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --git --ref main
```

Use npm explicitly (e.g. no pnpm on the machine):

```bash
curl -fsSL "https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh" | bash -s -- --pm npm --registry
```

If `runctl --help` still looks old after install/update, remove the legacy package that can shadow this CLI and reinstall:

```bash
pnpm remove -g runctl
pnpm add -g @zendero/runctl@latest
hash -r
```

### `runctl update` and pnpm version messages

If pnpm nags about versions or **`pnpm self-update`** does nothing useful, **`runctl update --help`** explains why and lists concrete fixes (same text is summarized after a successful pnpm-based update unless **`CI`** or **`RUNCTL_UPDATE_SKIP_PNPM_HINT=1`**).

`--help` on the install script prints the same usage summary.

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

**Dashboard / API-only (split names):** Avoid `runctl start --script dev` when `dev` is the runctl wrapper — that loops. Use a dedicated script for the real server:

```json
{
  "scripts": {
    "dev": "runctl start --script dev:workbench",
    "dev:workbench": "node --env-file=.env src/dashboard/server.js",
    "dev:stop": "runctl stop"
  }
}
```

Listen on `process.env.PORT` (runctl sets it). Optional: `runctl start --script dev:workbench --open` to open the browser after start, or `runctl start … && runctl open .`.

---

## Commands

| Command | What it does |
|---------|-------------|
| `runctl start` \| `runctl dev` | Start dev server (same command; picks free port, backgrounds). Flags: `--script`, `--open` (open browser after a successful start) |
| `runctl stop [dir]` | Stop daemons & release ports |
| `runctl status [dir]` | Show `.run` state for this package |
| `runctl ps` | List running programs with PID, port, service, project |
| `runctl logs [dir] [service]` | Tail `.run/logs/<service>.log` (default service: **`RUNCTL_SERVICE`**, else `package.json` `name` basename, else `web`) |
| `runctl ports` | List user-wide port registry (`~/.run`) |
| `runctl ports gc` | Clean up stale port claims |
| `runctl env expand <manifest> [--out file]` | Generate `.env.local` from manifest |
| `runctl doctor [dir]` | Check Node 18+, `lsof`, package manager, `package.json`; reminds that child scripts get **`PORT`** / **`HOST`** (custom servers should `listen` on `process.env.PORT`) |
| `runctl update` | Refresh global CLI: default **`auto`** (npm `@latest`, then Git). **`runctl update npm`** / **`git`** / **`auto`** or flags **`--registry`** / **`--git`** / **`--auto`**; **`runctl update --help`**; env `RUNCTL_PACKAGE`, `RUNCTL_GIT_BASE`, `RUNCTL_GIT_REF` (aligned with [`install-global.sh`](scripts/install-global.sh)) |
| `runctl version` \| `runctl --version` \| `runctl -v` | Print package version and install path (supported interchangeably) |

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
| Custom Node entry (gateways, CLIs) | **Weak fit** — `PORT`/`HOST` are injected; bind with `server.listen(process.env.PORT)` (see `runctl doctor`). |

---

## Docs & examples

[`examples/consumer-package.json`](examples/consumer-package.json) · [`docs/vercel-and-env.md`](docs/vercel-and-env.md) · [`examples/env.manifest.example`](examples/env.manifest.example)

**CLI vs `run-lib.sh`:** Most apps only need the **`runctl`** binary and `package.json` scripts. For shell-heavy repos, [`examples/run.sh.example`](examples/run.sh.example) shows sourcing **`lib/run-lib.sh`** (same library the CLI uses). Resolve the installed path with **`runctl lib-path`**.

**CI:** Prefer **`pnpm add -D @zendero/runctl`** (or a global install) so `runctl` is on `PATH` with a stable version. **`pnpm dlx @zendero/runctl`** is fine for one-off recovery; avoid relying on it for every CI job (cold cache / latency).

**Roadmap (ideas):** `runctl exec` (one-off commands with the same port / `.run` contract as `start`); optional HTTP health gate before “ready”.

**Develop this repo:** `pnpm install` → `./run.sh` (default **doctor**, like `elata-bio-sdk/run.sh`) → `./run.sh ports` · **`pnpm test`** runs [`tests/run-all.sh`](tests/run-all.sh) (Jest-style output: suites, ✓/✗, `PASS`/`FAIL` per file, shared helpers in [`tests/lib/test-runner.sh`](tests/lib/test-runner.sh))

**Publish (maintainers)** — workflow similar to elata’s release preflight, scaled for one package:

| Step | Command |
|------|--------|
| Preflight | `./run.sh release-check` or `pnpm run release-check` |
| Publish | `./run.sh release latest` or `pnpm run release` (publishes, then commits + pushes release changes if any) |
| Promote dist-tag | After publishing under `next`, `./run.sh promote` sets **latest** for the version in `package.json` |

Put `NPM_TOKEN` in `.env`. `release` / `npm-whoami` use a **temporary `NPM_CONFIG_USERCONFIG`** so a stale `~/.npmrc` token does not override `.env` (npm 10+ / pnpm). Token lines can use `NPM_TOKEN=` or `npm_token=`; quoted values are supported without `source`-ing secrets as shell code first.
