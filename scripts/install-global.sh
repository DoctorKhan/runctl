#!/usr/bin/env sh
# Install @zendero/runctl globally: try npm registry, then GitHub if that fails.
#
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh | bash
#
# RUNCTL_PACKAGE — npm package (default @zendero/runctl)
# RUNCTL_GIT — git spec if registry fails (default git+https://github.com/DoctorKhan/runctl.git#main)
set -eu

PKG="${RUNCTL_PACKAGE:-@zendero/runctl}"
GIT="${RUNCTL_GIT:-git+https://github.com/DoctorKhan/runctl.git#main}"

install_from_git() {
  echo "runctl: registry install failed; trying Git ($GIT)..." >&2
  if command -v pnpm >/dev/null 2>&1; then
    pnpm add -g "$GIT"
  else
    npm install -g "$GIT"
  fi
  printf '\nInstalled @zendero/runctl from Git — run: runctl help\n'
}

if command -v pnpm >/dev/null 2>&1; then
  if pnpm add -g "$PKG"; then
    printf '\nInstalled %s — run: runctl help\n' "$PKG"
  else
    install_from_git
  fi
else
  if npm install -g "$PKG"; then
    printf '\nInstalled %s — run: runctl help\n' "$PKG"
  else
    install_from_git
  fi
fi
