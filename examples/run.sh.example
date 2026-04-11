#!/usr/bin/env bash
# Thin project runner: sets RUNCTL_PROJECT_ROOT + PM/PORT, then delegates to bin/runctl.
# Maintainer npm flows: scripts/maintain.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export RUNCTL_PROJECT_ROOT="$ROOT"
export RUNCTL_PKG_ROOT="$ROOT"
export RUN_SH_TASK="${RUN_SH_TASK:-}"

PM="${PM:-pnpm}"
export PM
RUNCTL_DEV_SCRIPT="${RUNCTL_DEV_SCRIPT:-dev}"
PORT="${PORT:-3000}"

die() {
  echo "run.sh${RUN_SH_TASK:+ ($RUN_SH_TASK)}: $*" >&2
  exit 1
}

runctl_cmd() {
  if [[ -x "$ROOT/bin/runctl" ]]; then
    exec "$ROOT/bin/runctl" "$@"
  elif [[ -x "$ROOT/node_modules/.bin/runctl" ]]; then
    exec "$ROOT/node_modules/.bin/runctl" "$@"
  elif command -v pnpm >/dev/null 2>&1 && pnpm exec runctl version >/dev/null 2>&1; then
    exec pnpm exec runctl "$@"
  elif command -v runctl >/dev/null 2>&1; then
    exec runctl "$@"
  else
    die "runctl not found — install deps or add @zendero/runctl"
  fi
}

usage() {
  cat <<'EOF'
Usage: ./run.sh <command> [args]

  install | run | exec | test   → runctl (same as: runctl install|run|exec|test)
  dev | start                   → runctl start this repo (--script RUNCTL_DEV_SCRIPT)
  open | stop | status | doctor | ports | ps | logs | env | update | …
  env-expand | lib-path
  release-check | publish | release | promote | npm-whoami → scripts/maintain.sh

Environment:
  RUNCTL_PROJECT_ROOT  Set automatically to this script’s directory
  RUNCTL_DEV_SCRIPT    npm script for dev/start (default: dev)
  PORT                 Passed to dev/start
  PM                   package manager (default: pnpm)
EOF
  echo ""
  runctl_cmd help
}

main() {
  [[ $# -eq 0 ]] && set -- help
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    install | run | exec | test)
      RUN_SH_TASK="$cmd"
      export RUN_SH_TASK
      runctl_cmd "$cmd" "$@"
      ;;
    dev | start)
      export PORT
      runctl_cmd start "$ROOT" --script "$RUNCTL_DEV_SCRIPT" "$@"
      ;;
    release-check | publish | release | promote | npm-whoami)
      exec "$ROOT/scripts/maintain.sh" "$cmd" "$@"
      ;;
    ports-gc | gc)
      runctl_cmd ports gc "$@"
      ;;
    lib-path)
      runctl_cmd lib-path
      ;;
    env-expand | expand-env)
      runctl_cmd env expand "$@"
      ;;
    help | -h | --help)
      usage
      ;;
    *)
      runctl_cmd "$cmd" "$@"
      ;;
  esac
}

main "$@"
