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
