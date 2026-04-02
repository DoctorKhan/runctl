#!/usr/bin/env bash
# Global installer for @zendero/runctl.
#
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh | bash
#
# Modes:
#   --interactive  prompt for package manager + install source
#   --registry     install from npm only
#   --git          install from Git only
#   --auto         install from npm, then fall back to Git
#
# Flags:
#   --pm <pnpm|npm>
#   --ref <git-ref>
#   --help
#
# Optional env:
#   RUNCTL_PACKAGE   npm package name (default: @zendero/runctl)
#   RUNCTL_GIT_BASE  git URL without ref (default: git+https://github.com/DoctorKhan/runctl.git)
#   RUNCTL_GIT_REF   git ref for Git installs (default: main)
set -euo pipefail

PKG="${RUNCTL_PACKAGE:-@zendero/runctl}"
GIT_BASE="${RUNCTL_GIT_BASE:-git+https://github.com/DoctorKhan/runctl.git}"
DEFAULT_GIT_REF="${RUNCTL_GIT_REF:-main}"

MODE=""
PM=""
GIT_REF="$DEFAULT_GIT_REF"

say() {
  printf '%s\n' "$*"
}

usage() {
  cat <<'EOF'
Usage: install-global.sh [mode] [flags]

Modes:
  --interactive  Prompt for install options when a TTY is available.
  --registry     Install from the npm registry only.
  --git          Install from Git only.
  --auto         Install from the npm registry, then fall back to Git.

Flags:
  --pm <pnpm|npm>  Force a package manager.
  --ref <git-ref>  Git ref to use with --git or --auto fallback.
  --help           Show this help.

Default behavior:
  If no mode is provided, use --interactive when a TTY is available.
  Otherwise default to --auto.
EOF
}

has_tty() {
  [[ -t 1 ]] && [[ -r /dev/tty ]]
}

prompt_choice() {
  local prompt="$1"
  local default_value="$2"
  shift 2
  local options=("$@")
  local answer

  while true; do
    printf '%s ' "$prompt" > /dev/tty
    IFS= read -r answer < /dev/tty || answer=""
    answer="${answer:-$default_value}"

    for option in "${options[@]}"; do
      if [[ "$answer" == "$option" ]]; then
        printf '%s' "$answer"
        return 0
      fi
    done

    say "Please choose one of: ${options[*]}" > /dev/tty
  done
}

prompt_text() {
  local prompt="$1"
  local default_value="$2"
  local answer

  printf '%s ' "$prompt" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  printf '%s' "${answer:-$default_value}"
}

pick_package_manager() {
  if [[ -n "$PM" ]]; then
    if [[ "$PM" != "pnpm" && "$PM" != "npm" ]]; then
      say "runctl: unsupported package manager: $PM" >&2
      exit 1
    fi
    if ! command -v "$PM" >/dev/null 2>&1; then
      say "runctl: requested package manager not found on PATH: $PM" >&2
      exit 1
    fi
    printf '%s' "$PM"
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    if [[ "$MODE" == "interactive" ]]; then
      prompt_choice "Package manager? [pnpm/npm] (default: pnpm)" "pnpm" "pnpm" "npm"
    else
      printf 'pnpm'
    fi
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1; then
    printf 'pnpm'
    return 0
  fi

  if command -v npm >/dev/null 2>&1; then
    printf 'npm'
    return 0
  fi

  say "runctl: neither pnpm nor npm was found on PATH." >&2
  exit 1
}

run_install() {
  local manager="$1"
  local source_kind="$2"
  local target="$3"

  # A legacy package named "runctl" can shadow the same CLI binary.
  # Remove it before installing @zendero/runctl.
  if [[ "$PKG" == "@zendero/runctl" ]]; then
    if [[ "$manager" == "pnpm" ]]; then
      pnpm remove -g runctl >/dev/null 2>&1 || true
    else
      npm uninstall -g runctl >/dev/null 2>&1 || true
    fi
  fi

  if [[ "$manager" == "pnpm" ]]; then
    pnpm add -g --force "$target"
  else
    npm install -g --force "$target"
  fi

  say
  if [[ "$source_kind" == "git" ]]; then
    say "Installed @zendero/runctl from Git — run: runctl help"
  else
    say "Installed $PKG — run: runctl help"
  fi
}

fallback_install() {
  local manager="$1"
  local git_target="$2"

  say "runctl: registry install failed; trying Git ($git_target)..." >&2
  run_install "$manager" "git" "$git_target"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interactive)
        MODE="interactive"
        ;;
      --registry)
        MODE="registry"
        ;;
      --git)
        MODE="git"
        ;;
      --auto)
        MODE="auto"
        ;;
      --pm)
        [[ $# -ge 2 ]] || { say "runctl: --pm requires a value" >&2; exit 1; }
        PM="$2"
        shift
        ;;
      --ref)
        [[ $# -ge 2 ]] || { say "runctl: --ref requires a value" >&2; exit 1; }
        GIT_REF="$2"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        say "runctl: unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  local manager git_target

  parse_args "$@"

  if [[ -z "$MODE" ]]; then
    if has_tty && [[ "${CI:-}" != "1" ]]; then
      MODE="interactive"
    else
      MODE="auto"
    fi
  fi

  manager="$(pick_package_manager)"
  git_target="${GIT_BASE}#${GIT_REF}"

  if [[ "$MODE" == "interactive" ]] && (! has_tty || [[ "${CI:-}" == "1" ]]); then
    say "runctl: no interactive TTY detected; defaulting to --auto." >&2
    MODE="auto"
  fi

  case "$MODE" in
    interactive)
      say "runctl interactive installer"
      say
      say "This will install the global \`runctl\` CLI."
      say
      MODE="$(prompt_choice "Install source? [registry/git/auto] (default: auto)" "auto" "registry" "git" "auto")"
      if [[ "$MODE" == "git" || "$MODE" == "auto" ]]; then
        GIT_REF="$(prompt_text "Git ref to use? (default: ${GIT_REF})" "$GIT_REF")"
        git_target="${GIT_BASE}#${GIT_REF}"
      fi
      ;;
  esac

  case "$MODE" in
    registry)
      run_install "$manager" "registry" "$PKG"
      ;;
    git)
      say "runctl: installing from Git ($git_target)..." >&2
      run_install "$manager" "git" "$git_target"
      ;;
    auto)
      if run_install "$manager" "registry" "$PKG"; then
        return 0
      fi
      fallback_install "$manager" "$git_target"
      ;;
  esac
}

main "$@"
