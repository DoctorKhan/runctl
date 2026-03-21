#!/usr/bin/env bash
# Runctl — global ~/.run helpers and lib path (see package runctl / bin/runctl).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/run-lib.sh
source "$ROOT/lib/run-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./run.sh <command>

  list        Registered ports (~/.run/ports)
  gc          Drop stale registry entries (dead PID / nothing listening)
  status      This repo’s .run state (pids + claimed ports)
  lib-path    Print path to lib/run-lib.sh (source from other run.sh)
  expand-env  Run env manifest expander (pass args after expand-env)
  help

Other projects:

  export RUN_LIB="$(./run.sh lib-path)"   # or set a fixed path in each repo
  source "$RUN_LIB"
  run_project_init "$(pwd)"
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    list)
      run_global_list_ports
      ;;
    gc)
      run_global_gc
      ;;
    status)
      run_project_init "$ROOT"
      run_local_status
      ;;
    lib-path)
      printf '%s\n' "$ROOT/lib/run-lib.sh"
      ;;
    expand-env)
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
