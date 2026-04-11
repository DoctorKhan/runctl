#!/usr/bin/env bash
# Optional repo-root env for npm auth — sourced by bin/runctl and scripts/maintain.sh.
# Resolves root as: $1, else RUNCTL_PROJECT_ROOT, else PWD.
# Idempotent per shell (RUNCTL_REPO_ENV_LOADED).

runctl_load_repo_env() {
  [[ -n "${RUNCTL_REPO_ENV_LOADED:-}" ]] && return 0
  local root="${1:-${RUNCTL_PROJECT_ROOT:-$PWD}}"

  if [[ -z "${NPM_TOKEN:-}" ]] && [[ -f "$root/.env" ]]; then
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
      break
    done <"$root/.env"
  fi

  if [[ -f "$root/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$root/.env"
    set +a
  fi

  if [[ -z "${NODE_AUTH_TOKEN:-}" ]]; then
    if [[ -n "${NPM_TOKEN:-}" ]]; then
      export NODE_AUTH_TOKEN="$NPM_TOKEN"
    elif [[ -n "${npm_token:-}" ]]; then
      export NODE_AUTH_TOKEN="$npm_token"
    fi
  fi

  export RUNCTL_REPO_ENV_LOADED=1
}
