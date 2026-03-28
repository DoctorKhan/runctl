#!/usr/bin/env sh
# Install @zendero/runctl globally from GitHub only (skips npmjs).
#
#   curl -fsSL https://raw.githubusercontent.com/DoctorKhan/runctl/main/scripts/install-global-git.sh | bash
#
# Override ref/URL: RUNCTL_GIT=git+https://github.com/DoctorKhan/runctl.git#my-branch
set -eu

GIT="${RUNCTL_GIT:-git+https://github.com/DoctorKhan/runctl.git#main}"

echo "runctl: installing from Git ($GIT)..." >&2

if command -v pnpm >/dev/null 2>&1; then
  pnpm add -g "$GIT"
else
  npm install -g "$GIT"
fi

printf '\nInstalled @zendero/runctl from Git — run: runctl help\n'
