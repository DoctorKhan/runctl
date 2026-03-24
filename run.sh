#!/usr/bin/env bash
# Internal dev script for the runctl package itself.
# Not shipped to consumers (excluded from "files" in package.json).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load local env file for commands like publish.
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/.env"
  set +a
fi
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
  publish [tag]  Publish package to npm (default tag: latest; supports: latest, next)
  help
EOF
}

validate_dist_tag() {
  case "${1:-latest}" in
    latest | next) return 0 ;;
    *)
      echo "run.sh publish: unsupported dist-tag '$1'. Use: latest or next." >&2
      return 1
      ;;
  esac
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
    local dist_tag="${1:-latest}"
    validate_dist_tag "$dist_tag" || exit 1
    if [[ $# -gt 0 ]]; then
      shift
    fi
    local token="${NPM_TOKEN:-${npm_token:-}}"
    if [[ -z "$token" ]]; then
      echo "run.sh publish: missing token. Set NPM_TOKEN or npm_token (for example in .env)." >&2
      exit 1
    fi
    export NODE_AUTH_TOKEN="$token"
    export PUBLISH_OK=1
    if command -v pnpm >/dev/null 2>&1; then
      (cd "$ROOT" && pnpm publish --access public --tag "$dist_tag" --no-git-checks "$@")
    elif command -v npm >/dev/null 2>&1; then
      (cd "$ROOT" && npm publish --access public --tag "$dist_tag" "$@")
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
