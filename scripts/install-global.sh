#!/usr/bin/env sh
# Install runctl globally (needs Node 18+ and npm or pnpm).
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/devport-kit/main/scripts/install-global.sh | bash
# Registry: RUNCTL_PACKAGE=runctl curl -fsSL … | bash
# Scoped: RUNCTL_PACKAGE=@your-org/runctl curl -fsSL … | bash
set -eu
PKG="${RUNCTL_PACKAGE:-github:DoctorKhan/devport-kit}"
if command -v pnpm >/dev/null 2>&1; then
  pnpm add -g "$PKG"
else
  npm install -g "$PKG"
fi
printf 'Installed %s — try: runctl help\n' "$PKG"
