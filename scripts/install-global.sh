#!/usr/bin/env sh
# Install runctl globally (needs Node 18+ and npm or pnpm).
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global.sh | bash
#
# Registry default: @zendero/runctl. Override: RUNCTL_PACKAGE=…
# If registry install fails, installs from GitHub. Override: RUNCTL_GIT=…
set -eu

PKG="${RUNCTL_PACKAGE:-@zendero/runctl}"
GIT="${RUNCTL_GIT:-git+https://github.com/DoctorKhan/runctl.git#main}"

if command -v pnpm >/dev/null 2>&1; then
  if pnpm add -g "$PKG"; then
    printf '\nInstalled %s — run: runctl help\n' "$PKG"
  else
    echo "runctl install-global: registry install failed; installing from Git ($GIT)..." >&2
    pnpm add -g "$GIT"
    printf '\nInstalled @zendero/runctl from Git — run: runctl help\n'
  fi
else
  if npm install -g "$PKG"; then
    printf '\nInstalled %s — run: runctl help\n' "$PKG"
  else
    echo "runctl install-global: registry install failed; installing from Git ($GIT)..." >&2
    npm install -g "$GIT"
    printf '\nInstalled @zendero/runctl from Git — run: runctl help\n'
  fi
fi
