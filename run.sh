#!/usr/bin/env bash
# Internal dev script for the runctl package itself.
# Not shipped to consumers (excluded from "files" in package.json).
# Patterns aligned with ../elata-bio-sdk/run.sh where sensible (single-package repo).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RUN_SH_TASK="${RUN_SH_TASK:-}"

die() {
  echo "run.sh${RUN_SH_TASK:+ ($RUN_SH_TASK)}: $*" >&2
  exit 1
}

# Load NPM_TOKEN from repo-root .env when not already set (no full shell eval).
# Handles export prefix, quotes, and CRLF — adapted from elata-bio-sdk/run.sh.
ensure_npm_token_from_dotenv() {
  if [[ -n "${NPM_TOKEN:-}" ]]; then
    return 0
  fi
  local env_file="$ROOT/.env"
  [[ -f "$env_file" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == export\ * ]]; then
      line="${line#export }"
    fi
    [[ "$line" == *"="* ]] || continue
    key="${line%%=*}"
    val="${line#*=}"
    if [[ "$key" != "NPM_TOKEN" && "$key" != "npm_token" ]]; then
      continue
    fi
    val="${val%$'\r'}"
    if [[ "$val" == \"*\" ]]; then
      val="${val#\"}"
      val="${val%\"}"
    elif [[ "$val" == \'*\' ]]; then
      val="${val#\'}"
      val="${val%\'}"
    fi
    export NPM_TOKEN="$val"
    return 0
  done <"$env_file"
}

ensure_npm_token_from_dotenv

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/.env"
  set +a
fi

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

  (no args)      Same as doctor (elata-style default)
  install        Install dependencies (pnpm preferred; npm fallback)
  ports          Registered ports (~/.run/ports)
  ps             Running programs with ports/projects
  ports-gc       Drop stale registry entries
  status         This repo's .run state
  doctor         Run runctl doctor (from repo root; optional [dir])
  test           Run repo tests
  release-check  Preflight: doctor + pnpm/npm pack --dry-run (no publish)
  lib-path       Print path to lib/run-lib.sh
  env-expand     Run env manifest expander (pass args after env-expand)
  publish [all] [tag]  Publish to npm (NPM_TOKEN in .env; temp npm userconfig)
  release [all] [tag]  Same as publish (default dist-tag: latest)
  promote        npm dist-tag add <pkg>@<version> latest (needs published version)
  npm-whoami     npm whoami via .env token (ignores stale ~/.npmrc)
  help
EOF
}

npm_publish_token() {
  printf '%s' "${NPM_TOKEN:-${NODE_AUTH_TOKEN:-${npm_token:-}}}"
}

runctl_npm_userconfig_from_token() {
  local tok="$1"
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/runctl-npm-auth.XXXXXX")" || return 1
  chmod 600 "$f" || true
  printf '//registry.npmjs.org/:_authToken=%s\n' "$tok" >"$f" || {
    rm -f "$f"
    return 1
  }
  printf '%s' "$f"
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
  local cmd="${1:-doctor}"
  shift || true
  case "$cmd" in
    ports)
      run_global_list_ports
      ;;
    ps)
      run_global_list_running
      ;;
    ports-gc)
      run_global_gc
      ;;
    status)
      run_project_init "$ROOT"
      run_local_status
      ;;
    doctor)
      RUN_SH_TASK="doctor"
      export RUN_SH_TASK
      (cd "$ROOT" && exec ./bin/runctl doctor "$@")
      ;;
    test)
      RUN_SH_TASK="test"
      export RUN_SH_TASK
      (cd "$ROOT" && exec pnpm test)
      ;;
    install)
      RUN_SH_TASK="install"
      export RUN_SH_TASK
      if command -v pnpm >/dev/null 2>&1; then
        (cd "$ROOT" && exec pnpm install)
      elif command -v npm >/dev/null 2>&1; then
        (cd "$ROOT" && exec npm install)
      else
        die "install pnpm (preferred) or npm"
      fi
      ;;
    release-check)
      RUN_SH_TASK="release-check"
      export RUN_SH_TASK
      echo "run.sh release-check: runctl doctor..."
      (cd "$ROOT" && ./bin/runctl doctor "$ROOT") || die "doctor failed"
      echo "run.sh release-check: pack --dry-run..."
      if command -v pnpm >/dev/null 2>&1; then
        (cd "$ROOT" && pnpm pack --dry-run >/dev/null) || die "pnpm pack --dry-run failed"
      elif command -v npm >/dev/null 2>&1; then
        (cd "$ROOT" && npm pack --dry-run >/dev/null) || die "npm pack --dry-run failed"
      else
        die "install pnpm or npm for release-check"
      fi
      local tok
      tok="$(npm_publish_token)"
      if [[ -n "$tok" ]]; then
        echo "run.sh release-check: npm whoami..."
        local _rc _ec
        _rc="$(runctl_npm_userconfig_from_token "$tok")" || die "could not write temp npmrc"
        NPM_CONFIG_USERCONFIG="$_rc" npm whoami || {
          _ec=$?
          rm -f "$_rc"
          die "npm whoami failed (exit $_ec)"
        }
        rm -f "$_rc"
      else
        echo "run.sh release-check: skip npm whoami (no NPM_TOKEN / npm_token in .env)" >&2
      fi
      echo "run.sh release-check: ok"
      ;;
    lib-path)
      printf '%s\n' "$ROOT/lib/run-lib.sh"
      ;;
    env-expand)
      exec node "$ROOT/scripts/expand-env-manifest.mjs" "$@"
      ;;
    npm-whoami)
      RUN_SH_TASK="npm-whoami"
      export RUN_SH_TASK
      local _tok _rc _ec
      command -v npm >/dev/null 2>&1 || die "npm not found"
      _tok="$(npm_publish_token)"
      [[ -n "$_tok" ]] || die "set NPM_TOKEN or NODE_AUTH_TOKEN or npm_token in .env"
      _rc="$(runctl_npm_userconfig_from_token "$_tok")" || exit 1
      NPM_CONFIG_USERCONFIG="$_rc" npm whoami
      _ec=$?
      rm -f "$_rc"
      exit "$_ec"
      ;;
    promote)
      RUN_SH_TASK="promote"
      export RUN_SH_TASK
      local tok npmrc name ver
      tok="$(npm_publish_token)"
      [[ -n "$tok" ]] || die "set NPM_TOKEN (or npm_token) in .env for promote"
      name="$(package_field name)"
      ver="$(package_field version)"
      npmrc="$(runctl_npm_userconfig_from_token "$tok")" || exit 1
      echo "run.sh promote: npm dist-tag add ${name}@${ver} latest"
      if NPM_CONFIG_USERCONFIG="$npmrc" npm dist-tag add "${name}@${ver}" latest; then
        rm -f "$npmrc"
        echo "run.sh promote: ok"
      else
        rm -f "$npmrc"
        die "dist-tag add failed (is ${name}@${ver} published?)"
      fi
      ;;
    publish | release)
      RUN_SH_TASK="$cmd"
      export RUN_SH_TASK
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
      [[ -n "$token" ]] || die "missing npm token — set NPM_TOKEN in .env (or NODE_AUTH_TOKEN / npm_token)"
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
          (cd "$ROOT" && pnpm version patch --no-git-tag-version) || die "pnpm version patch failed"
        else
          (cd "$ROOT" && npm version patch --no-git-tag-version) || die "npm version patch failed"
        fi
        pkg_version="$(package_field version)"
        echo "run.sh ${cmd}: publishing ${pkg_name}@${pkg_version} with dist-tag '${dist_tag}'"
      elif [[ -n "$remote_version" ]]; then
        echo "run.sh ${cmd}: ${pkg_name}@${pkg_version} already exists; not bumping during --dry-run"
      fi

      local npmrc
      npmrc="$(runctl_npm_userconfig_from_token "$token")" || exit 1

      _publish_hint() {
        echo "run.sh ${cmd}: publish failed." >&2
        echo "  If ./run.sh npm-whoami works: check scoped write / maintainer on npm." >&2
        echo "  Run ./run.sh release-check before publish." >&2
      }
      local _pub_ok=0
      if command -v pnpm >/dev/null 2>&1; then
        (cd "$ROOT" && NPM_CONFIG_USERCONFIG="$npmrc" pnpm publish --access public --tag "$dist_tag" --no-git-checks "$@") && _pub_ok=1
      elif command -v npm >/dev/null 2>&1; then
        (cd "$ROOT" && NPM_CONFIG_USERCONFIG="$npmrc" npm publish --access public --tag "$dist_tag" --no-git-checks "$@") && _pub_ok=1
      else
        rm -f "$npmrc"
        die "install pnpm (preferred) or npm"
      fi
      rm -f "$npmrc"
      if [[ "$_pub_ok" -ne 1 ]]; then
        _publish_hint
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
