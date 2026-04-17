#!/usr/bin/env bash
# reconcile + stray kill: .run pidfiles vs live listeners / orphan PIDs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-runner.sh
source "$ROOT/tests/lib/test-runner.sh"
# shellcheck source=../lib/run-lib.sh
source "$ROOT/lib/run-lib.sh"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runctl-reconcile-stray.XXXXXX")"
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

register_pid() {
  local pid="$1"
  TEST_PIDS+=("$pid")
}

start_node_listener_in_dir() {
  local dir="$1"
  local port="$2"
  (
    cd "$dir" || exit 1
    node -e '
      const http = require("http");
      const port = Number(process.argv[1]);
      const server = http.createServer((_, res) => res.end("ok"));
      server.listen(port, "127.0.0.1", () => {});
      setInterval(() => {}, 1000);
    ' "$port" >/dev/null 2>&1 &
    echo $!
  )
}

wait_listener_pid() {
  local port="$1"
  local lip="" n=0
  while [[ -z "$lip" && "$n" -lt 80 ]]; do
    lip="$(lsof -iTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null | awk 'NR>1{print $2; exit}')"
    sleep 0.05
    n=$((n + 1))
  done
  printf '%s' "$lip"
}

alloc_port() {
  local base
  base="$((22000 + (RANDOM % 20000)))"
  run_find_free_port "$base" 200
}

test_reconcile_writes_pid_and_registry() {
  command -v lsof >/dev/null 2>&1 || {
    echo "skip test_reconcile_writes_pid_and_registry (no lsof)"
    return 0
  }
  local proj="$TEST_TMP_ROOT/recon-proj"
  local state="$TEST_TMP_ROOT/recon-state"
  mkdir -p "$proj/.run" "$state/ports"
  printf '%s\n' '{"name":"recon-test"}' >"$proj/package.json"

  local port
  port="$(alloc_port)"
  local bg
  bg="$(start_node_listener_in_dir "$proj" "$port")"
  register_pid "$bg"
  local lip
  lip="$(wait_listener_pid "$port")"
  [[ -n "$lip" ]] || fail "expected listener on $port"
  [[ "$lip" == "$bg" ]] || lip="$lip"

  cat >"$proj/.run/ports.env" <<EOF
PORT=$port
RUN_DEV_PORT=$port
RUN_DEV_SERVICE=web
HOST=127.0.0.1
EOF

  RUN_PROJECT_ROOT="$proj"
  RUN_GLOBAL_STATE="$state"
  export RUN_PROJECT_ROOT RUN_GLOBAL_STATE
  run_project_init "$proj"
  run_with_lock run_project_reconcile_pidfiles

  [[ -f "$proj/.run/pids/web.pid" ]] || fail "missing web.pid"
  assert_equals "$(tr -d '[:space:]' <"$proj/.run/pids/web.pid")" "$lip"
  [[ -f "$state/ports/$port" ]] || fail "missing global port file"
  grep -qx "$port" "$proj/.run/claimed-ports" || fail "port not in claimed-ports"
}

test_stray_kill_dry_run_counts_unprotected_node() {
  command -v lsof >/dev/null 2>&1 || {
    echo "skip test_stray_kill_dry_run_counts_unprotected_node (no lsof)"
    return 0
  }
  local proj="$TEST_TMP_ROOT/stray-proj"
  local gstate="$TEST_TMP_ROOT/stray-global"
  mkdir -p "$gstate/ports"
  export RUN_GLOBAL_STATE="$gstate"
  mkdir -p "$proj/.run/pids"
  printf '%s\n' '{"name":"stray-test"}' >"$proj/package.json"

  local port_a
  port_a="$(alloc_port)"
  local pa la
  pa="$(start_node_listener_in_dir "$proj" "$port_a")"
  register_pid "$pa"
  la="$(wait_listener_pid "$port_a")"
  [[ -n "$la" ]] || fail "listener"
  run_pid_alive "$la" || fail "listener not alive"

  RUN_PROJECT_ROOT="$proj"
  export RUN_PROJECT_ROOT
  run_project_init "$proj"

  if ! run_pid_is_stray_dev_candidate "$la"; then
    echo "skip test_stray_kill_dry_run_counts_unprotected_node (listener not visible as dev/cwd candidate; restricted environment?)"
    return 0
  fi

  # No pidfile yet → this node should be a stray candidate.
  RUN_STRAY_DRY_RUN=1 run_project_stray_kill
  local n="${RUN_LAST_STRAY_KILL_COUNT:-0}"
  if [[ "$n" -lt 1 ]]; then
    fail "expected dry-run picks with no pidfile, got $n"
    return 1
  fi

  printf '%s\n' "$la" >"$proj/.run/pids/web.pid"
  RUN_STRAY_DRY_RUN=1 run_project_stray_kill
  n="${RUN_LAST_STRAY_KILL_COUNT:-0}"
  if [[ "$n" -ne 0 ]]; then
    fail "expected no strays when pidfile matches listener, got $n"
    return 1
  fi
}

test_cli_reconcile_runs_under_lock() {
  command -v lsof >/dev/null 2>&1 || {
    echo "skip test_cli_reconcile_runs_under_lock (no lsof)"
    return 0
  }
  local proj="$TEST_TMP_ROOT/cli-recon"
  mkdir -p "$proj/.run"
  printf '%s\n' '{"name":"cli-recon"}' >"$proj/package.json"
  local port
  port="$(alloc_port)"
  local bg
  bg="$(start_node_listener_in_dir "$proj" "$port")"
  register_pid "$bg"
  local lip
  lip="$(wait_listener_pid "$port")"
  [[ -n "$lip" ]] || fail "listener"
  cat >"$proj/.run/ports.env" <<EOF
PORT=$port
RUN_DEV_SERVICE=web
HOST=127.0.0.1
EOF
  local state="$TEST_TMP_ROOT/cli-state"
  mkdir -p "$state/ports"
  local out
  out="$(RUN_GLOBAL_STATE="$state" "$ROOT/bin/runctl" reconcile "$proj" 2>&1)" || fail "reconcile exit"
  assert_contains "$out" "set web.pid=$lip"
}

main() {
  runner_init "tests/runctl-reconcile-stray.test.sh"

  runner_suite "reconcile + stray"
  runner_it "reconcile writes pid + registry from ports.env" test_reconcile_writes_pid_and_registry
  runner_it "stray kill dry-run sees unprotected sibling node" test_stray_kill_dry_run_counts_unprotected_node
  runner_it "runctl reconcile CLI updates pidfile" test_cli_reconcile_runs_under_lock

  runner_summary
}

main "$@"
