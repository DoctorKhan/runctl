#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/run-lib.sh
source "$ROOT/lib/run-lib.sh"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runctl-ps-test.XXXXXX")"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "expected output to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "expected output to NOT contain: $needle"
  fi
}

start_node_listener() {
  local port="$1"
  node -e '
    const http = require("http");
    const port = Number(process.argv[1]);
    const server = http.createServer((_, res) => res.end("ok"));
    server.listen(port, "127.0.0.1", () => {});
    setInterval(() => {}, 1000);
  ' "$port" >/dev/null 2>&1 &
  local pid=$!
  sleep 0.2
  printf '%s\n' "$pid"
}

test_run_global_list_running_counts_stale_and_lists_alive() {
  local state="$TEST_TMP_ROOT/lib-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE

  local alive_pid
  alive_pid="$(start_node_listener 3031)"

  cat >"$state/ports/3001" <<EOF
project_root=/tmp/project-alive
slug=alive
service=web
pid=$alive_pid
started=1
EOF

  cat >"$state/ports/3002" <<'EOF'
project_root=/tmp/project-stale
slug=stale
service=web
pid=999999
started=1
EOF

  run_pid_listens_on_port() {
    local pid="$1"
    local port="$2"
    [[ "$pid" == "$alive_pid" && "$port" == "3001" ]]
  }

  run_pid_program_name() {
    local pid="$1"
    if [[ "$pid" == "$alive_pid" ]]; then
      printf '%s\n' "sleep"
      return 0
    fi
    return 1
  }

  local out_file out
  out_file="$(mktemp "${TMPDIR:-/tmp}/runctl-ps-out.XXXXXX")"
  run_global_list_running >"$out_file"
  out="$(<"$out_file")"
  rm -f "$out_file"
  assert_contains "$out" "PID"
  assert_contains "$out" "3001"
  assert_contains "$out" "/tmp/project-alive"
  assert_not_contains "$out" "3002"
  [[ "${RUN_LAST_STALE_COUNT:-}" == "1" ]] || fail "expected RUN_LAST_STALE_COUNT=1"
  kill "$alive_pid" 2>/dev/null || true
}

test_runctl_ps_triggers_gc_and_refreshes() {
  local state="$TEST_TMP_ROOT/cli-state"
  mkdir -p "$state/ports"

  local dead_pid
  dead_pid="$(sh -c 'echo $$')"

  cat >"$state/ports/3010" <<EOF
project_root=/tmp/project-dead
slug=dead
service=web
pid=$dead_pid
started=1
EOF

  local out
  out="$(RUN_GLOBAL_STATE="$state" "$ROOT/bin/runctl" ps)"
  assert_contains "$out" "found 1 stale registry entry; cleaning..."
  assert_contains "$out" "refreshed"
  [[ ! -f "$state/ports/3010" ]] || fail "expected stale entry to be removed by gc"
}

test_runctl_ps_without_stale_does_not_refresh() {
  local state="$TEST_TMP_ROOT/cli-state-no-stale"
  mkdir -p "$state/ports"

  local alive_pid port
  port=3020
  alive_pid="$(start_node_listener "$port")"

  cat >"$state/ports/$port" <<EOF
project_root=/tmp/project-live
slug=live
service=web
pid=$alive_pid
started=1
EOF

  local out
  out="$(RUN_GLOBAL_STATE="$state" "$ROOT/bin/runctl" ps)"
  assert_not_contains "$out" "cleaning..."
  assert_contains "$out" "$port"
  kill "$alive_pid" 2>/dev/null || true
}

main() {
  test_run_global_list_running_counts_stale_and_lists_alive
  test_runctl_ps_triggers_gc_and_refreshes
  test_runctl_ps_without_stale_does_not_refresh
  echo "runctl ps tests: ok"
}

main "$@"
