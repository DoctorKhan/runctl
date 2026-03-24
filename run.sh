#!/usr/bin/env bash
# Internal dev script for the runctl package itself.
# Not shipped to consumers (excluded from "files" in package.json).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/run-lib.sh
source "$ROOT/lib/run-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./run.sh <command>

  ports          Registered ports (~/.run/ports)
  ports-gc       Drop stale registry entries
  status         This repo's .run state
  lib-path       Print path to lib/run-lib.sh
  env-expand     Run env manifest expander (pass args after env-expand)
  publish        Publish package to npm (requires npm_token or NPM_TOKEN)
  help
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    ports)
      run_global_list_ports
      ;;
    ports-gc)
      run_global_gc
      ;;
    status)
      run_project_init "$ROOT"
      run_local_status
      ;;
    lib-path)
      printf '%s\n' "$ROOT/lib/run-lib.sh"
      ;;
    env-expand)
      exec node "$ROOT/scripts/expand-env-manifest.mjs" "$@"
      ;;
  publish)
    local token="${NPM_TOKEN:-${npm_token:-}}"
    if [[ -z "$token" ]]; then
      echo "run.sh publish: missing token. Set NPM_TOKEN or npm_token (for example in .env)." >&2
      exit 1
    fi
    export NODE_AUTH_TOKEN="$token"
    export PUBLISH_OK=1
    if command -v pnpm >/dev/null 2>&1; then
      (cd "$ROOT" && pnpm publish --access public --no-git-checks "$@")
    elif command -v npm >/dev/null 2>&1; then
      (cd "$ROOT" && npm publish --access public "$@")
    else
      echo "run.sh publish: install pnpm (preferred) or npm" >&2
      exit 1
    fi
    ;;
    help | -h | --help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
