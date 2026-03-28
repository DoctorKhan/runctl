#!/usr/bin/env sh
# Install @zendero/runctl globally from the npm registry only (no Git).
#
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global-npm.sh | bash
#
# Override package: RUNCTL_PACKAGE=@scope/pkg
set -eu

PKG="${RUNCTL_PACKAGE:-@zendero/runctl}"

if command -v pnpm >/dev/null 2>&1; then
  pnpm add -g "$PKG"
else
  npm install -g "$PKG"
fi

printf '\nInstalled %s — run: runctl help\n' "$PKG"
