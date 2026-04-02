#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/run-lib.sh
source "$ROOT/lib/run-lib.sh"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runctl-ps-test.XXXXXX")"
declare -a TEST_PIDS=()
cleanup() {
  local pid
  for pid in "${TEST_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

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

assert_equals() {
  local got="$1"
  local want="$2"
  [[ "$got" == "$want" ]] || fail "expected [$want], got [$got]"
}

register_pid() {
  local pid="$1"
  TEST_PIDS+=("$pid")
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
  register_pid "$pid"
  printf '%s\n' "$pid"
}

alloc_test_port() {
  local base
  base="$((20000 + (RANDOM % 20000)))"
  run_find_free_port "$base" 200
}

write_registry_entry() {
  local state="$1"
  local port="$2"
  local project="$3"
  local service="$4"
  local pid="${5:-}"
  cat >"$state/ports/$port" <<EOF
project_root=$project
slug=test-$port
service=$service
pid=$pid
started=1
EOF
}

capture_run_global_list_running() {
  local out_file out
  out_file="$(mktemp "${TMPDIR:-/tmp}/runctl-ps-out.XXXXXX")"
  run_global_list_running >"$out_file"
  out="$(<"$out_file")"
  rm -f "$out_file"
  printf '%s\n' "$out"
}

run_and_capture_list_running() {
  local out_file
  out_file="$(mktemp "${TMPDIR:-/tmp}/runctl-ps-out.XXXXXX")"
  run_global_list_running >"$out_file"
  CAPTURED_OUTPUT="$(<"$out_file")"
  CAPTURED_STALE="${RUN_LAST_STALE_COUNT:-}"
  rm -f "$out_file"
}

test_list_running_header_and_empty_state() {
  local state="$TEST_TMP_ROOT/empty-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  run_and_capture_list_running
  assert_contains "$CAPTURED_OUTPUT" "PID"
  assert_contains "$CAPTURED_OUTPUT" "PROGRAM"
  assert_contains "$CAPTURED_OUTPUT" "(no running programs)"
  assert_equals "$CAPTURED_STALE" "0"
}

test_list_running_counts_missing_pid_as_stale() {
  local state="$TEST_TMP_ROOT/missing-pid-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  write_registry_entry "$state" "4101" "/tmp/missing-pid" "web" ""
  run_and_capture_list_running
  assert_contains "$CAPTURED_OUTPUT" "(no running programs)"
  assert_equals "$CAPTURED_STALE" "1"
}

test_list_running_ignores_invalid_port_filenames() {
  local state="$TEST_TMP_ROOT/invalid-port-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  cat >"$state/ports/not-a-port" <<'EOF'
project_root=/tmp/invalid
slug=invalid
service=web
pid=1234
started=1
EOF
  run_and_capture_list_running
  assert_contains "$CAPTURED_OUTPUT" "(no running programs)"
  assert_equals "$CAPTURED_STALE" "0"
}

test_list_running_counts_stale_and_lists_alive() {
  local state="$TEST_TMP_ROOT/lib-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  local alive_pid
  sleep 30 >/dev/null 2>&1 &
  alive_pid=$!
  register_pid "$alive_pid"
  write_registry_entry "$state" "4001" "/tmp/project-alive" "web" "$alive_pid"
  write_registry_entry "$state" "4002" "/tmp/project-stale" "web" "999999"

  local out stale
  out="$(
    run_pid_listens_on_port() {
      local pid="$1"
      local port="$2"
      [[ "$pid" == "$alive_pid" && "$port" == "4001" ]]
    }
    run_pid_program_name() {
      local pid="$1"
      if [[ "$pid" == "$alive_pid" ]]; then
        printf '%s\n' "sleep"
        return 0
      fi
      return 1
    }
    capture_run_global_list_running
    printf '\n__STALE__=%s\n' "${RUN_LAST_STALE_COUNT:-}"
  )"
  stale="$(printf '%s\n' "$out" | awk -F= '/^__STALE__=/{v=$2} END{print v}')"
  out="$(printf '%s\n' "$out" | awk '!/^__STALE__=/')"
  assert_contains "$out" "4001"
  assert_contains "$out" "/tmp/project-alive"
  assert_not_contains "$out" "4002"
  assert_equals "$stale" "1"
}

test_list_running_marks_wrong_listener_as_stale() {
  local state="$TEST_TMP_ROOT/wrong-listener-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  local alive_pid listener_port
  listener_port="$(alloc_test_port)"
  alive_pid="$(start_node_listener "$listener_port")"
  write_registry_entry "$state" "4042" "/tmp/project-mismatch" "web" "$alive_pid"
  local out
  run_and_capture_list_running
  out="$CAPTURED_OUTPUT"
  assert_contains "$out" "(no running programs)"
  assert_equals "$CAPTURED_STALE" "1"
}

test_list_running_uses_unknown_program_fallback() {
  local state="$TEST_TMP_ROOT/unknown-program-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  local alive_pid port
  port="$(alloc_test_port)"
  alive_pid="$(start_node_listener "$port")"
  write_registry_entry "$state" "$port" "/tmp/project-unknown-program" "web" "$alive_pid"
  local out
  out="$(
    run_pid_program_name() { return 1; }
    capture_run_global_list_running
  )"
  assert_contains "$out" "(unknown)"
}

test_global_gc_removes_stale_entries() {
  local state="$TEST_TMP_ROOT/gc-state"
  mkdir -p "$state/ports"
  RUN_GLOBAL_STATE="$state"
  export RUN_GLOBAL_STATE
  local alive_pid live_port
  live_port="$(alloc_test_port)"
  alive_pid="$(start_node_listener "$live_port")"
  write_registry_entry "$state" "$live_port" "/tmp/project-live" "web" "$alive_pid"
  write_registry_entry "$state" "4062" "/tmp/project-stale" "web" "999999"
  run_global_gc >/dev/null
  [[ -f "$state/ports/$live_port" ]] || fail "expected live entry to remain"
  [[ ! -f "$state/ports/4062" ]] || fail "expected stale entry to be removed"
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

test_runctl_ps_plural_cleanup_message() {
  local state="$TEST_TMP_ROOT/cli-state-plural"
  mkdir -p "$state/ports"
  write_registry_entry "$state" "3110" "/tmp/project-dead-a" "web" "999991"
  write_registry_entry "$state" "3111" "/tmp/project-dead-b" "web" "999992"
  local out
  out="$(RUN_GLOBAL_STATE="$state" "$ROOT/bin/runctl" ps)"
  assert_contains "$out" "found 2 stale registry entries; cleaning..."
  [[ ! -f "$state/ports/3110" ]] || fail "expected stale entry A removed"
  [[ ! -f "$state/ports/3111" ]] || fail "expected stale entry B removed"
}

test_runctl_ps_without_stale_does_not_refresh() {
  local state="$TEST_TMP_ROOT/cli-state-no-stale"
  mkdir -p "$state/ports"

  local alive_pid port
  port="$(alloc_test_port)"
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
}

main() {
  test_list_running_header_and_empty_state
  test_list_running_counts_missing_pid_as_stale
  test_list_running_ignores_invalid_port_filenames
  test_list_running_counts_stale_and_lists_alive
  test_list_running_marks_wrong_listener_as_stale
  test_list_running_uses_unknown_program_fallback
  test_global_gc_removes_stale_entries
  test_runctl_ps_triggers_gc_and_refreshes
  test_runctl_ps_plural_cleanup_message
  test_runctl_ps_without_stale_does_not_refresh
  echo "runctl ps tests: 10 passed"
}

main "$@"
