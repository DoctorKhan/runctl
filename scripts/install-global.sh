#!/usr/bin/env sh
# Install runctl globally (needs Node 18+ and npm or pnpm).
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh | bash
#
# Registry default: @zendero/runctl. Override: RUNCTL_PACKAGE=…
# If registry install fails, installs from GitHub. Override: RUNCTL_GIT=…
# Skip npm entirely: RUNCTL_FROM_GIT=1 curl -fsSL … | bash
set -eu

PKG="${RUNCTL_PACKAGE:-@zendero/runctl}"
GIT="${RUNCTL_GIT:-git+https://github.com/DoctorKhan/runctl.git#main}"

install_from_git() {
  if command -v pnpm >/dev/null 2>&1; then
    pnpm add -g "$GIT"
  else
    npm install -g "$GIT"
  fi
  printf '\nInstalled @zendero/runctl from Git — run: runctl help\n'
}

if [ "${RUNCTL_FROM_GIT:-}" = "1" ]; then
  echo "runctl install-global: installing from Git only ($GIT)..." >&2
  install_from_git
  exit 0
fi

if command -v pnpm >/dev/null 2>&1; then
  if pnpm add -g "$PKG"; then
    printf '\nInstalled %s — run: runctl help\n' "$PKG"
  else
    echo "runctl install-global: registry install failed; installing from Git ($GIT)..." >&2
    install_from_git
  fi
else
  if npm install -g "$PKG"; then
    printf '\nInstalled %s — run: runctl help\n' "$PKG"
  else
    echo "runctl install-global: registry install failed; installing from Git ($GIT)..." >&2
    install_from_git
  fi
fi
