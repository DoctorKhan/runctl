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
# npm CLI uses NODE_AUTH_TOKEN; .env often has NPM_TOKEN or npm_token only.
if [[ -z "${NODE_AUTH_TOKEN:-}" ]]; then
  if [[ -n "${NPM_TOKEN:-}" ]]; then
    export NODE_AUTH_TOKEN="$NPM_TOKEN"
  elif [[ -n "${npm_token:-}" ]]; then
    export NODE_AUTH_TOKEN="$npm_token"
  fi
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
  publish [all] [tag]  Publish to npm (loads .env; NPM_TOKEN). Optional "all" matches monorepo habits.
  release [all] [tag]  Same as publish (default dist-tag: latest)
  npm-whoami       Run npm whoami (uses NPM_TOKEN → NODE_AUTH_TOKEN from .env)
  help
EOF
}

# Token for npm publish: NPM_TOKEN from .env (preferred), then NODE_AUTH_TOKEN, then npm_token.
npm_publish_token() {
  printf '%s' "${NPM_TOKEN:-${NODE_AUTH_TOKEN:-${npm_token:-}}}"
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

package_field() {
  local field="$1"
  node -e '
    const fs = require("fs");
    const path = require("path");
    const f = path.join(process.argv[1], "package.json");
    const pkg = JSON.parse(fs.readFileSync(f, "utf8"));
    const key = process.argv[2];
    if (!pkg[key]) process.exit(1);
    process.stdout.write(String(pkg[key]));
  ' "$ROOT" "$field"
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
    npm-whoami)
      command -v npm >/dev/null 2>&1 || {
        echo "run.sh npm-whoami: npm not found" >&2
        exit 1
      }
      if [[ -z "${NODE_AUTH_TOKEN:-}" ]]; then
        echo "run.sh npm-whoami: set NPM_TOKEN or NODE_AUTH_TOKEN in .env" >&2
        exit 1
      fi
      npm whoami
      ;;
    publish | release)
    # Optional "all" (elata-style): this repo has one package; "all" is ignored.
    if [[ "${1:-}" == "all" ]]; then
      shift
    fi
    local dist_tag="${1:-latest}"
    validate_dist_tag "$dist_tag" || exit 1
    if [[ $# -gt 0 ]]; then
      shift
    fi
    local token
    token="$(npm_publish_token)"
    if [[ -z "$token" ]]; then
      echo "run.sh ${cmd}: missing npm token. Set NPM_TOKEN in .env (or NODE_AUTH_TOKEN / npm_token)." >&2
      exit 1
    fi
    export NODE_AUTH_TOKEN="$token"
    export PUBLISH_OK=1
    local pkg_name pkg_version remote_version
    pkg_name="$(package_field name)"
    pkg_version="$(package_field version)"
    remote_version="$(npm view "${pkg_name}@${pkg_version}" version 2>/dev/null || true)"

    local is_dry_run=0
    local arg
    for arg in "$@"; do
      if [[ "$arg" == "--dry-run" ]]; then
        is_dry_run=1
        break
      fi
    done

    if [[ -n "$remote_version" && "$is_dry_run" -eq 0 ]]; then
      echo "run.sh ${cmd}: ${pkg_name}@${pkg_version} already exists; bumping patch version..."
      if command -v pnpm >/dev/null 2>&1; then
        (cd "$ROOT" && pnpm version patch --no-git-tag-version)
      else
        (cd "$ROOT" && npm version patch --no-git-tag-version)
      fi
      pkg_version="$(package_field version)"
      echo "run.sh ${cmd}: publishing ${pkg_name}@${pkg_version} with dist-tag '${dist_tag}'"
    elif [[ -n "$remote_version" ]]; then
      echo "run.sh ${cmd}: ${pkg_name}@${pkg_version} already exists; not bumping during --dry-run"
    fi

    _publish_hint() {
      echo "run.sh ${cmd}: publish failed." >&2
      echo "  For scoped packages (@scope/name), npm often reports 403/404 when the account or token cannot publish that scope — not a bad tarball." >&2
      echo "  Fix: npmjs.com → Access Tokens with read/write for @scope, or \`npm login\` as an owner of the package." >&2
    }
    if command -v pnpm >/dev/null 2>&1; then
      (cd "$ROOT" && pnpm publish --access public --tag "$dist_tag" --no-git-checks "$@") || {
        _publish_hint
        exit 1
      }
    elif command -v npm >/dev/null 2>&1; then
      (cd "$ROOT" && npm publish --access public --tag "$dist_tag" --no-git-checks "$@") || {
        _publish_hint
        exit 1
      }
    else
      echo "run.sh ${cmd}: install pnpm (preferred) or npm" >&2
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
