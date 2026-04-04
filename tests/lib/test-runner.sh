#!/usr/bin/env bash
# Jest-style test runner for bash: suites, ✓/✗, summary, optional colors.
# Source from repo tests after setting ROOT if needed.
# Disable colors: NO_COLOR=1 or RUNCTL_TEST_NO_COLOR=1 or non-TTY stdout.

if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "test-runner.sh: requires bash" >&2
  return 1 2>/dev/null || exit 1
fi

if [[ -t 1 && -z "${NO_COLOR:-}" && -z "${RUNCTL_TEST_NO_COLOR:-}" ]]; then
  _T_RUN=$'\033[1;2m'
  _T_DIM=$'\033[2m'
  _T_SUITE=$'\033[1m'
  _T_PASS=$'\033[32m'
  _T_FAIL=$'\033[31m'
  _T_RESET=$'\033[0m'
else
  _T_RUN="" _T_DIM="" _T_SUITE="" _T_PASS="" _T_FAIL="" _T_RESET=""
fi

RUNNER_FILE=""
RUNNER_PASS=0
RUNNER_FAIL=0
RUNNER_T0="${SECONDS:-0}"

# --- Assertions (return 1 on failure; work with set -e inside test bodies) ---

fail() {
  echo "      ${_T_DIM}Error: $*${_T_RESET}" >&2
  return 1
}

assert_equals() {
  if [[ "$1" != "$2" ]]; then
    echo "      ${_T_DIM}AssertionError: expected [${2}], received [${1}]${_T_RESET}" >&2
    return 1
  fi
  return 0
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "      ${_T_DIM}AssertionError: expected output to contain: ${2}${_T_RESET}" >&2
    return 1
  fi
  return 0
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "      ${_T_DIM}AssertionError: expected output NOT to contain: ${2}${_T_RESET}" >&2
    return 1
  fi
  return 0
}

assert_not_equals() {
  if [[ "$1" == "$2" ]]; then
    echo "      ${_T_DIM}AssertionError: expected different values (both were [${2}])${_T_RESET}" >&2
    return 1
  fi
  return 0
}

# --- Runner API ---

runner_init() {
  RUNNER_FILE="$1"
  RUNNER_PASS=0
  RUNNER_FAIL=0
  RUNNER_T0="${SECONDS:-0}"
  # Jest prints the file path first; we show RUN (dim) then suites, then PASS/FAIL + stats.
  printf '%s %s%s%s\n' "${_T_RUN}RUN${_T_RESET}" "${_T_DIM}" "$RUNNER_FILE" "${_T_RESET}"
}

runner_suite() {
  printf '\n  %s%s%s\n' "${_T_SUITE}" "$1" "${_T_RESET}"
}

runner_it() {
  local title="$1"
  shift
  set +e
  "$@"
  local ec=$?
  set -e
  if [[ $ec -eq 0 ]]; then
    printf '    %s✓%s %s\n' "${_T_PASS}" "${_T_RESET}" "$title"
    RUNNER_PASS=$((RUNNER_PASS + 1))
  else
    printf '    %s✗%s %s\n' "${_T_FAIL}" "${_T_RESET}" "$title"
    RUNNER_FAIL=$((RUNNER_FAIL + 1))
  fi
}

runner_summary() {
  local total=$((RUNNER_PASS + RUNNER_FAIL))
  local elapsed=$((SECONDS - RUNNER_T0))
  echo ""
  if [[ $RUNNER_FAIL -eq 0 ]]; then
    printf '%sTests:%s  %s%d passed%s, %d total\n' "${_T_PASS}" "${_T_RESET}" "${_T_PASS}" "$RUNNER_PASS" "${_T_RESET}" "$total"
  else
    printf '%sTests:%s  %s%d failed%s, %s%d passed%s, %d total\n' \
      "${_T_FAIL}" "${_T_RESET}" "${_T_FAIL}" "$RUNNER_FAIL" "${_T_RESET}" "${_T_PASS}" "$RUNNER_PASS" "${_T_RESET}" "$total"
  fi
  printf '%sTime:%s   %ds\n' "${_T_DIM}" "${_T_RESET}" "$elapsed"
  if [[ $RUNNER_FAIL -eq 0 ]]; then
    printf '\n%s %s%s%s\n' "${_T_PASS}PASS${_T_RESET}" "${_T_DIM}" "$RUNNER_FILE" "${_T_RESET}"
  else
    printf '\n%s %s%s%s\n' "${_T_FAIL}FAIL${_T_RESET}" "${_T_DIM}" "$RUNNER_FILE" "${_T_RESET}"
  fi
  [[ $RUNNER_FAIL -eq 0 ]] && return 0 || return 1
}
