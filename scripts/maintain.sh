#!/usr/bin/env bash
# Maintainer-only: npm publish, release, promote, release-check, whoami.
# Invoked via ./run.sh <command> or directly: scripts/maintain.sh <command>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

die() {
  echo "maintain: $*" >&2
  exit 1
}

export RUNCTL_PROJECT_ROOT="$ROOT"
# shellcheck source=../lib/repo-env.sh
source "$ROOT/lib/repo-env.sh"
runctl_load_repo_env "$ROOT"

in_repo() {
  (cd "$ROOT" && "$@")
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
      echo "maintain publish: unsupported dist-tag '$1'. Use: latest or next." >&2
      return 1
      ;;
  esac
}

release_commit_and_push_if_needed() {
  local dist_tag="$1"
  local pkg_name="$2"
  local pkg_version="$3"
  if ! command -v git >/dev/null 2>&1; then
    echo "maintain release: git not found; skipping commit/push step" >&2
    return 0
  fi
  if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "maintain release: not in a git worktree; skipping commit/push step" >&2
    return 0
  fi
  if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    local branch
    branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [[ -n "$branch" && "$branch" != "HEAD" ]] || die "release commit/push requires a branch checkout (not detached HEAD)"
    git -C "$ROOT" add -A
    git -C "$ROOT" commit -m "release: publish ${pkg_name}@${pkg_version} (${dist_tag})"
    git -C "$ROOT" push -u origin "$branch"
    echo "maintain release: committed and pushed release changes on $branch"
  else
    echo "maintain release: no local git changes; skipping commit/push"
  fi
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

publish_failed_hint() {
  local op="$1"
  echo "maintain ${op}: publish failed." >&2
  echo "  If ./run.sh npm-whoami works: check scoped write / maintainer on npm." >&2
  echo "  Run ./run.sh release-check before publish." >&2
}

maint_release_check() {
  echo "maintain release-check: runctl doctor..."
  "$ROOT/bin/runctl" doctor "$ROOT" || die "doctor failed"
  echo "maintain release-check: pack --dry-run..."
  if command -v pnpm >/dev/null 2>&1; then
    in_repo pnpm pack --dry-run >/dev/null || die "pnpm pack --dry-run failed"
  elif command -v npm >/dev/null 2>&1; then
    in_repo npm pack --dry-run >/dev/null || die "npm pack --dry-run failed"
  else
    die "install pnpm or npm for release-check"
  fi
  local tok _rc _ec
  tok="$(npm_publish_token)"
  if [[ -n "$tok" ]]; then
    echo "maintain release-check: npm whoami..."
    _rc="$(runctl_npm_userconfig_from_token "$tok")" || die "could not write temp npmrc"
    NPM_CONFIG_USERCONFIG="$_rc" npm whoami || {
      _ec=$?
      rm -f "$_rc"
      die "npm whoami failed (exit $_ec)"
    }
    rm -f "$_rc"
  else
    echo "maintain release-check: skip npm whoami (no NPM_TOKEN / npm_token in .env)" >&2
  fi
  echo "maintain release-check: ok"
}

maint_publish_or_release() {
  local cmd="$1"
  shift
  if [[ "${1:-}" == "all" ]]; then
    shift
  fi
  local dist_tag="${1:-latest}"
  validate_dist_tag "$dist_tag" || exit 1
  if [[ $# -gt 0 ]]; then
    shift
  fi
  local token pkg_name pkg_version remote_version
  token="$(npm_publish_token)"
  [[ -n "$token" ]] || die "missing npm token — set NPM_TOKEN in .env (or NODE_AUTH_TOKEN / npm_token)"
  export NODE_AUTH_TOKEN="$token"
  export PUBLISH_OK=1
  pkg_name="$(package_field name)"
  pkg_version="$(package_field version)"
  remote_version="$(npm view "${pkg_name}@${pkg_version}" version 2>/dev/null || true)"

  local is_dry_run=0 arg
  for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
      is_dry_run=1
      break
    fi
  done

  if [[ -n "$remote_version" && "$is_dry_run" -eq 0 ]]; then
    echo "maintain ${cmd}: ${pkg_name}@${pkg_version} already exists; bumping patch version..."
    if command -v pnpm >/dev/null 2>&1; then
      in_repo pnpm version patch --no-git-tag-version || die "pnpm version patch failed"
    else
      in_repo npm version patch --no-git-tag-version || die "npm version patch failed"
    fi
    pkg_version="$(package_field version)"
    echo "maintain ${cmd}: publishing ${pkg_name}@${pkg_version} with dist-tag '${dist_tag}'"
  elif [[ -n "$remote_version" ]]; then
    echo "maintain ${cmd}: ${pkg_name}@${pkg_version} already exists; not bumping during --dry-run"
  fi

  local npmrc _pub_ok=0
  npmrc="$(runctl_npm_userconfig_from_token "$token")" || exit 1

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
    publish_failed_hint "$cmd"
    exit 1
  fi
  if [[ "$cmd" == "release" && "$is_dry_run" -eq 0 ]]; then
    release_commit_and_push_if_needed "$dist_tag" "$pkg_name" "$pkg_version"
  fi
}

maint_promote() {
  local tok npmrc name ver
  tok="$(npm_publish_token)"
  [[ -n "$tok" ]] || die "set NPM_TOKEN (or npm_token) in .env for promote"
  name="$(package_field name)"
  ver="$(package_field version)"
  npmrc="$(runctl_npm_userconfig_from_token "$tok")" || exit 1
  echo "maintain promote: npm dist-tag add ${name}@${ver} latest"
  if NPM_CONFIG_USERCONFIG="$npmrc" npm dist-tag add "${name}@${ver}" latest; then
    rm -f "$npmrc"
    echo "maintain promote: ok"
  else
    rm -f "$npmrc"
    die "dist-tag add failed (is ${name}@${ver} published?)"
  fi
}

maint_npm_whoami() {
  local _tok _rc _ec
  command -v npm >/dev/null 2>&1 || die "npm not found"
  _tok="$(npm_publish_token)"
  [[ -n "$_tok" ]] || die "set NPM_TOKEN or NODE_AUTH_TOKEN or npm_token in .env"
  _rc="$(runctl_npm_userconfig_from_token "$_tok")" || exit 1
  NPM_CONFIG_USERCONFIG="$_rc" npm whoami
  _ec=$?
  rm -f "$_rc"
  exit "$_ec"
}

maint_usage() {
  cat <<'EOF'
Maintainer commands (scripts/maintain.sh):

  release-check     Preflight: doctor + pack --dry-run + optional npm whoami
  publish [all] [tag]   Publish package to npm
  release [all] [tag]   Publish, then commit+push if needed
  promote            npm dist-tag add <pkg>@<version> latest
  npm-whoami         npm whoami using token from .env

Also available via: ./run.sh <same command>
EOF
}

main() {
  [[ $# -eq 0 ]] && set -- help
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    release-check)
      maint_release_check
      ;;
    publish | release)
      maint_publish_or_release "$cmd" "$@"
      ;;
    promote)
      maint_promote
      ;;
    npm-whoami)
      maint_npm_whoami
      ;;
    help | -h | --help)
      maint_usage
      ;;
    *)
      echo "maintain: unknown command: $cmd" >&2
      echo "" >&2
      maint_usage >&2
      exit 1
      ;;
  esac
}

main "$@"
