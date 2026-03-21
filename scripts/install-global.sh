#!/usr/bin/env sh
# Install runctl globally (needs Node 18+ and npm or pnpm).
#   curl -fsSL …/install-global.sh | bash
# Scoped: RUNCTL_PACKAGE=@your-org/runctl curl -fsSL … | bash
set -eu
PKG="${RUNCTL_PACKAGE:-runctl}"
if command -v pnpm >/dev/null 2>&1; then
  pnpm add -g "$PKG"
else
  npm install -g "$PKG"
fi
printf 'Installed %s — try: runctl help\n' "$PKG"
