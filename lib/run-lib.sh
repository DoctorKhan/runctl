#!/usr/bin/env bash
# run-lib.sh — npm package `runctl`: project .run/ + user ~/.run registry.
# Requires bash. Port/dev automation requires Node.js >= 18 (see package.json engines).
# Intentionally no global `set -e` — this file is usually sourced.

if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "run-lib.sh: must be sourced or executed with bash (not zsh)" >&2
  return 1 2>/dev/null || exit 1
fi

run_lib_dir() {
  local _src="${BASH_SOURCE[0]:-$0}"
  cd "$(dirname "$_src")" && pwd
}

# Override with RUN_GLOBAL_STATE=... if needed.
: "${RUN_GLOBAL_STATE:=$HOME/.run}"

run_slug() {
  # Short stable id from absolute project path (no raw path in filenames).
  local h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -c1-16)"
  fi
  if [[ -z "$h" ]] && command -v sha256sum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | sha256sum 2>/dev/null | cut -c1-16)"
  fi
  if [[ -z "$h" ]] && command -v openssl >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | openssl dgst -sha256 2>/dev/null | awk '{print $2}' | cut -c1-16)"
  fi
  if [[ -z "$h" ]]; then
    h="$(printf '%s' "${1//\//_}" | cksum 2>/dev/null | awk '{print $1}')"
  fi
  printf '%s' "${h:-unknown}"
}

run_project_init() {
  RUN_PROJECT_ROOT="$(cd "${1:-.}" && pwd)"
  export RUN_PROJECT_ROOT
  RUN_LOCAL_STATE="$RUN_PROJECT_ROOT/.run"
  RUN_PROJECT_SLUG="$(run_slug "$RUN_PROJECT_ROOT")"
  export RUN_LOCAL_STATE RUN_PROJECT_SLUG RUN_GLOBAL_STATE
  mkdir -p "$RUN_LOCAL_STATE/pids" "$RUN_LOCAL_STATE/logs" \
    "$RUN_GLOBAL_STATE/ports" "$RUN_GLOBAL_STATE/projects"
  [[ -f "$RUN_LOCAL_STATE/claimed-ports" ]] || : >"$RUN_LOCAL_STATE/claimed-ports"
  _run_ensure_gitignore
}

_run_ensure_gitignore() {
  local gi="$RUN_PROJECT_ROOT/.gitignore"
  [[ -d "$RUN_PROJECT_ROOT/.git" ]] || return 0
  if [[ ! -f "$gi" ]]; then
    printf '# Runtime state (runctl)\n.run/\n' >"$gi"
    return 0
  fi
  if ! grep -qxF '.run/' "$gi" && ! grep -qxF '.run' "$gi"; then
    printf '\n# Runtime state (runctl)\n.run/\n' >>"$gi"
  fi
}

run_lock_acquire() {
  local lock="$RUN_LOCAL_STATE/lock"
  local wait="${1:-50}"
  local i=0
  while ! mkdir "$lock" 2>/dev/null; do
    sleep 0.05
    i=$((i + 1))
    if (( i > wait * 20 )); then
      echo "run-lib: could not acquire lock: $lock" >&2
      return 1
    fi
  done
}

run_lock_release() {
  rmdir "$RUN_LOCAL_STATE/lock" 2>/dev/null || true
}

run_with_lock() {
  run_lock_acquire 50
  trap 'run_lock_release' EXIT
  "$@"
  local _ec=$?
  trap - EXIT
  run_lock_release
  return "$_ec"
}

run_pid_alive() {
  kill -0 "$1" 2>/dev/null
}

run_port_listening() {
  local port="$1"
  command -v lsof >/dev/null 2>&1 || return 1
  lsof -iTCP:"$port" -sTCP:LISTEN -n -P >/dev/null 2>&1
}

run_find_free_port() {
  local p="${1:-3000}"
  local max="${2:-200}"
  local i=0
  while run_port_listening "$p" && (( i < max )); do
    p=$((p + 1))
    i=$((i + 1))
  done
  if run_port_listening "$p"; then
    echo "run-lib: no free port from base ${1:-3000} after $max tries" >&2
    return 1
  fi
  printf '%s' "$p"
}

# --- JS / Node dev servers (Vite, Next, Nuxt, Astro, etc.) -----------------

run_require_node() {
  command -v node >/dev/null 2>&1 || {
    echo "runctl: Node.js is required (install Node >= 18; see runctl package engines)." >&2
    return 1
  }
  node -e 'process.exit(parseInt(process.versions.node,10)>=18?0:1)' 2>/dev/null || {
    echo "runctl: Node.js >= 18 is required (got $(node -v 2>/dev/null || echo none))." >&2
    return 1
  }
}

# True if package.json defines scripts.<name> (Node required).
run_package_has_script() {
  local name="$1"
  [[ -f "$RUN_PROJECT_ROOT/package.json" ]] || return 1
  node -e '
    const fs = require("fs");
    const path = require("path");
    const root = process.argv[1];
    const s = process.argv[2];
    const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
    process.exit(pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, s) ? 0 : 1);
  ' "$RUN_PROJECT_ROOT" "$name" 2>/dev/null
}

run_detect_package_manager() {
  local dir="${1:-$RUN_PROJECT_ROOT}"
  [[ -d "$dir" ]] || {
    echo "run_detect_package_manager: bad directory: $dir" >&2
    return 1
  }
  if [[ -f "$dir/pnpm-lock.yaml" ]] && command -v pnpm >/dev/null 2>&1; then
    printf '%s\n' pnpm
    return 0
  fi
  if [[ -f "$dir/bun.lock" || -f "$dir/bun.lockb" ]] && command -v bun >/dev/null 2>&1; then
    printf '%s\n' bun
    return 0
  fi
  if [[ -f "$dir/yarn.lock" ]] && command -v yarn >/dev/null 2>&1; then
    printf '%s\n' yarn
    return 0
  fi
  if command -v npm >/dev/null 2>&1; then
    printf '%s\n' npm
    return 0
  fi
  echo "run-lib: install pnpm, yarn, or npm (prefer pnpm per repo lockfile)" >&2
  return 1
}

# Prints one of: next | nuxt | astro | vite | remix | generic
run_js_framework_kind() {
  local pkg="$RUN_PROJECT_ROOT/package.json"
  [[ -f "$pkg" ]] || {
    printf '%s\n' generic
    return 0
  }
  run_require_node || return 1
  node -e "
    const fs = require('fs');
    const f = process.argv[1];
    let pkg = {};
    try { pkg = JSON.parse(fs.readFileSync(f, 'utf8')); } catch { console.log('generic'); process.exit(0); }
    const d = { ...pkg.dependencies, ...pkg.devDependencies };
    const h = (n) => !!d[n];
    if (h('next')) console.log('next');
    else if (h('nuxt')) console.log('nuxt');
    else if (h('astro')) console.log('astro');
    else if (h('vite') || h('@vitejs/plugin-react') || h('@vitejs/plugin-vue') || h('@vitejs/plugin-svelte') || h('@sveltejs/vite-plugin-svelte'))
      console.log('vite');
    else if (h('@remix-run/dev')) console.log('remix');
    else console.log('generic');
  " "$pkg"
}

run_infer_dev_base_port() {
  local k
  k="$(run_js_framework_kind)" || return 1
  case "$k" in
    vite) printf '%s\n' 5173 ;;
    astro) printf '%s\n' 4321 ;;
    next | nuxt | remix | generic) printf '%s\n' 3000 ;;
    *) printf '%s\n' 3000 ;;
  esac
}

# Writes .run/ports.env for tooling and humans: source from repo root after start.
run_write_ports_env() {
  local port="$1"
  local svc="${2:-web}"
  mkdir -p "$RUN_LOCAL_STATE"
  local host="${HOST:-127.0.0.1}"
  umask 077
  cat >"$RUN_LOCAL_STATE/ports.env" <<EOF
# Generated by run-lib.sh — do not commit .run/
# From repo root: set -a; source .run/ports.env; set +a
PORT=$port
RUN_DEV_PORT=$port
RUN_DEV_SERVICE=$svc
HOST=$host
EOF
  umask 022
}

# Start \`pnpm|yarn|npm run <script>\` in the background with a free port and register it.
# Script name defaults to \`dev\`; set RUNCTL_PM_RUN_SCRIPT (e.g. dev:server) when \`dev\` is the runctl wrapper.
# Usage: run_start_package_dev [service_name=web] [base_port|auto=auto] [extra args after script --]
run_start_package_dev() {
  run_require_node || return 1
  [[ -f "$RUN_PROJECT_ROOT/package.json" ]] || {
    echo "run_start_package_dev: no package.json in $RUN_PROJECT_ROOT" >&2
    return 1
  }
  local svc="web"
  local base_raw="auto"
  if [[ $# -ge 1 ]]; then svc="$1"; shift; fi
  if [[ $# -ge 1 ]]; then base_raw="$1"; shift; fi

  local base_port
  if [[ "$base_raw" == "auto" ]]; then
    base_port="$(run_infer_dev_base_port)"
  else
    base_port="$base_raw"
  fi

  local port
  port="$(run_find_free_port "$base_port")" || return 1

  local pm kind
  pm="$(run_detect_package_manager)" || return 1
  kind="$(run_js_framework_kind)"

  local -a dev_extra=()
  case "$kind" in
    next) dev_extra=(-p "$port") ;;
    nuxt) dev_extra=(--port "$port") ;;
    astro) dev_extra=(--port "$port") ;;
    vite) dev_extra=(--port "$port" --strictPort) ;;
    remix) dev_extra=(--port "$port") ;;
    *) dev_extra=() ;;
  esac

  run_write_ports_env "$port" "$svc"

  local host="${HOST:-127.0.0.1}"
  local pm_script="${RUNCTL_PM_RUN_SCRIPT:-dev}"
  # Many repos pair "predev" with script "dev". Using dev:server skips predev because only
  # predev:server would run automatically. If predev exists but pre<pm_script> does not, run predev once.
  if [[ "${RUNCTL_SKIP_PREDEV:-}" != "1" && "$pm_script" != "dev" ]]; then
    if [[ "$pm_script" == dev:* || "$pm_script" == dev_* ]]; then
      local pre_for_script="pre${pm_script}"
      if ! run_package_has_script "$pre_for_script" && run_package_has_script "predev"; then
        echo "run-lib: running predev before $pm_script ($pre_for_script not defined)"
        (cd "$RUN_PROJECT_ROOT" && "$pm" run predev) || return 1
      fi
    fi
  fi
  echo "run-lib: [$kind] starting pm run $pm_script on PORT=$port (service=$svc, pm=$pm)"
  local pid
  pid="$(
    run_daemon_start "$svc" \
      bash -c 'cd "$1" && export PORT="$2" HOST="$3" && shift 3 && exec "$@"' \
      _ "$RUN_PROJECT_ROOT" "$port" "$host" \
      "$pm" run "$pm_script" -- "${dev_extra[@]}" "$@"
  )" || return 1

  run_port_register "$port" "$svc" "$pid"
  printf '%s\n' "$port"
}

# Start a background service: name, then command + args.
run_daemon_start() {
  local name="$1"
  shift
  [[ $# -ge 1 ]] || {
    echo "run_daemon_start: need name and command" >&2
    return 1
  }
  mkdir -p "$RUN_LOCAL_STATE/pids" "$RUN_LOCAL_STATE/logs"
  local pidf="$RUN_LOCAL_STATE/pids/${name}.pid"
  local logf="$RUN_LOCAL_STATE/logs/${name}.log"
  if [[ -f "$pidf" ]]; then
    local oldpid
    oldpid="$(cat "$pidf")"
    if run_pid_alive "$oldpid"; then
      echo "run_daemon_start: ${name} already running (pid $oldpid)" >&2
      return 1
    fi
    rm -f "$pidf"
    echo "run_daemon_start: cleared stale pid for ${name} (was $oldpid)" >&2
  fi
  nohup "$@" >>"$logf" 2>&1 &
  local pid=$!
  printf '%s\n' "$pid" >"$pidf"
  printf '%s\n' "$pid"
}

run_daemon_stop() {
  local name="$1"
  local pidf="$RUN_LOCAL_STATE/pids/${name}.pid"
  [[ -f "$pidf" ]] || return 0
  local pid
  pid="$(cat "$pidf")"
  if run_pid_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    local n=0
    while run_pid_alive "$pid" && (( n < 50 )); do
      sleep 0.1
      n=$((n + 1))
    done
    if run_pid_alive "$pid"; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidf"
}

run_stop_all_daemons() {
  local f base
  shopt -s nullglob
  for f in "$RUN_LOCAL_STATE/pids"/*.pid; do
    base="$(basename "$f" .pid)"
    run_daemon_stop "$base"
  done
  shopt -u nullglob
}

# Stop every local daemon and drop this project's port claims under ~/.run/ports/.
run_stop_all() {
  run_stop_all_daemons
  run_unregister_project_ports
}

# Register a TCP port in the user-wide registry (~/.run/ports/<port>).
run_port_register() {
  local port="$1"
  local service="${2:-app}"
  local pid="${3:-}"
  [[ -n "$port" ]] || return 1
  local reg="$RUN_GLOBAL_STATE/ports/$port"
  mkdir -p "$RUN_GLOBAL_STATE/ports"
  {
    echo "project_root=$RUN_PROJECT_ROOT"
    echo "slug=$RUN_PROJECT_SLUG"
    echo "service=$service"
    echo "pid=$pid"
    echo "started=$(date +%s)"
  } >"$reg"
  mkdir -p "$RUN_GLOBAL_STATE/projects/$RUN_PROJECT_SLUG"
  printf '%s %s %s\n' "$port" "$service" "${pid:-}" >>"$RUN_GLOBAL_STATE/projects/$RUN_PROJECT_SLUG/ports.log"
  # De-dup claimed-ports for this project
  if ! grep -qx "$port" "$RUN_LOCAL_STATE/claimed-ports" 2>/dev/null; then
    printf '%s\n' "$port" >>"$RUN_LOCAL_STATE/claimed-ports"
  fi
}

run_port_unregister() {
  local port="$1"
  local reg="$RUN_GLOBAL_STATE/ports/$port"
  [[ -f "$reg" ]] || return 0
  # Only remove if it still points at this project
  if grep -q "^project_root=$RUN_PROJECT_ROOT\$" "$reg" 2>/dev/null; then
    rm -f "$reg"
  fi
}

run_unregister_project_ports() {
  local port
  while IFS= read -r port; do
    [[ -z "$port" ]] && continue
    run_port_unregister "$port"
  done <"$RUN_LOCAL_STATE/claimed-ports"
  : >"$RUN_LOCAL_STATE/claimed-ports"
}

# Remove stale entries under ~/.run/ports (dead pid or wrong listener).
run_global_gc() {
  mkdir -p "$RUN_GLOBAL_STATE/ports"
  local f port pid proot _line _k _v stale
  shopt -s nullglob
  for f in "$RUN_GLOBAL_STATE/ports"/*; do
    [[ -f "$f" ]] || continue
    port="$(basename "$f")"
    [[ "$port" =~ ^[0-9]+$ ]] || continue
    pid=""
    proot=""
    while IFS= read -r _line; do
      [[ -z "$_line" ]] && continue
      _k="${_line%%=*}"
      _v="${_line#*=}"
      case "$_k" in
        pid) pid="$_v" ;;
        project_root) proot="$_v" ;;
      esac
    done <"$f"
    stale=0
    if [[ -n "$pid" ]] && ! run_pid_alive "$pid"; then
      stale=1
    fi
    if [[ "$stale" -eq 0 ]] && [[ -n "$pid" ]] && command -v lsof >/dev/null 2>&1; then
      if ! lsof -iTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null | awk 'NR>1 {print $2}' | sort -u | grep -qx "$pid"; then
        stale=1
      fi
    fi
    if [[ "$stale" -eq 1 ]]; then
      rm -f "$f"
      echo "run_global_gc: removed stale ~/.run/ports/$port"
    fi
  done
  shopt -u nullglob
}

run_global_list_ports() {
  mkdir -p "$RUN_GLOBAL_STATE/ports"
  local f port tmp pid svc proot _line _k _v
  tmp="$(mktemp "${TMPDIR:-/tmp}/runlib.XXXXXX")"
  shopt -s nullglob
  for f in "$RUN_GLOBAL_STATE/ports"/*; do
    [[ -f "$f" ]] || continue
    port="$(basename "$f")"
    [[ "$port" =~ ^[0-9]+$ ]] || continue
    pid="" svc="" proot=""
    while IFS= read -r _line; do
      [[ -z "$_line" ]] && continue
      _k="${_line%%=*}"
      _v="${_line#*=}"
      case "$_k" in
        pid) pid="$_v" ;;
        service) svc="$_v" ;;
        project_root) proot="$_v" ;;
      esac
    done <"$f"
    printf '%s\t%s\t%s\t%s\n' "${port}" "${pid:--}" "${svc:--}" "${proot:--}" >>"$tmp"
  done
  shopt -u nullglob
  printf '%-6s %-8s %-6s %s\n' "PORT" "PID" "SVC" "PROJECT"
  if [[ -s "$tmp" ]]; then
    sort -n "$tmp" | while IFS=$'\t' read -r port pid svc proot; do
      printf '%-6s %-8s %-6s %s\n' "$port" "$pid" "$svc" "$proot"
    done
  fi
  rm -f "$tmp"
}

run_local_status() {
  echo "Project: $RUN_PROJECT_ROOT"
  echo "Slug:    $RUN_PROJECT_SLUG"
  echo "Local:   $RUN_LOCAL_STATE"
  echo ""
  local f base pid
  shopt -s nullglob
  for f in "$RUN_LOCAL_STATE/pids"/*.pid; do
    base="$(basename "$f" .pid)"
    pid="$(cat "$f")"
    if run_pid_alive "$pid"; then
      echo "  $base  pid=$pid  (running)"
    else
      echo "  $base  pid=$pid  (stale)"
    fi
  done
  shopt -u nullglob
  if [[ -s "$RUN_LOCAL_STATE/claimed-ports" ]]; then
    echo ""
    echo "Claimed ports (registry):"
    cat "$RUN_LOCAL_STATE/claimed-ports" | sed 's/^/  /'
  fi
  if [[ -f "$RUN_LOCAL_STATE/ports.env" ]]; then
    echo ""
    echo "ports.env (last dev allocation):"
    sed 's/^/  /' "$RUN_LOCAL_STATE/ports.env"
  fi
}
