#!/usr/bin/env bash
# Core tests: run-lib helpers + runctl CLI (version, logs, doctor, ports, errors).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-runner.sh
source "$ROOT/tests/lib/test-runner.sh"
# shellcheck source=../lib/run-lib.sh
source "$ROOT/lib/run-lib.sh"

TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runctl-core-test.XXXXXX")"
cleanup() {
  rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

pkg_version() {
  node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).version);' \
    "$ROOT/package.json"
}

# --- run_sanitize_service_name ---

test_sanitizes_empty_and_dashes() {
  assert_equals "$(run_sanitize_service_name '')" "web"
  assert_equals "$(run_sanitize_service_name '---')" "web"
}

test_sanitizes_special_characters() {
  assert_equals "$(run_sanitize_service_name 'my_api')" "my_api"
  assert_equals "$(run_sanitize_service_name 'a@b')" "a-b"
}

# --- run_default_service_name ---

test_default_name_honors_runctl_service() {
  local d="$TEST_TMP_ROOT/svc-env"
  mkdir -p "$d"
  RUN_PROJECT_ROOT="$d"
  export RUN_PROJECT_ROOT
  RUNCTL_SERVICE="my-custom-api"
  export RUNCTL_SERVICE
  assert_equals "$(run_default_service_name)" "my-custom-api"
  unset RUNCTL_SERVICE
}

test_default_name_reads_scoped_and_plain_package_names() {
  local d="$TEST_TMP_ROOT/pkg-scoped"
  mkdir -p "$d"
  printf '%s\n' '{"name":"@acme/foo-bar"}' >"$d/package.json"
  RUN_PROJECT_ROOT="$d"
  export RUN_PROJECT_ROOT
  unset RUNCTL_SERVICE
  assert_equals "$(run_default_service_name)" "foo-bar"

  d="$TEST_TMP_ROOT/pkg-plain"
  mkdir -p "$d"
  printf '%s\n' '{"name":"plain-app"}' >"$d/package.json"
  RUN_PROJECT_ROOT="$d"
  export RUN_PROJECT_ROOT
  assert_equals "$(run_default_service_name)" "plain-app"
}

test_default_name_falls_back_for_invalid_json() {
  local d="$TEST_TMP_ROOT/bad-json"
  mkdir -p "$d"
  printf '%s\n' 'not json' >"$d/package.json"
  RUN_PROJECT_ROOT="$d"
  export RUN_PROJECT_ROOT
  unset RUNCTL_SERVICE
  assert_equals "$(run_default_service_name)" "web"
}

test_default_name_falls_back_without_package_json() {
  local d="$TEST_TMP_ROOT/no-pkg"
  mkdir -p "$d"
  RUN_PROJECT_ROOT="$d"
  export RUN_PROJECT_ROOT
  unset RUNCTL_SERVICE
  assert_equals "$(run_default_service_name)" "web"
}

# --- run_slug ---

test_run_slug_produces_stable_non_empty_id() {
  local s
  s="$(run_slug "/tmp/some/project/path")"
  [[ -n "$s" ]] || fail "run_slug returned empty"
  assert_not_equals "$s" "unknown"
}

# --- run_project_init / ports.env ---

test_write_ports_env_records_port_and_service() {
  local d="$TEST_TMP_ROOT/ports-env"
  mkdir -p "$d"
  run_project_init "$d"
  run_write_ports_env 9876 "svc-test"
  assert_contains "$(cat "$d/.run/ports.env")" "PORT=9876"
  assert_contains "$(cat "$d/.run/ports.env")" "RUN_DEV_SERVICE=svc-test"
}

# --- run_package_has_script ---

test_package_has_script_detects_defined_scripts() {
  local d="$TEST_TMP_ROOT/scripts-pkg"
  mkdir -p "$d"
  printf '%s\n' '{"scripts":{"dev":"x","dev:server":"y"}}' >"$d/package.json"
  run_project_init "$d"
  run_package_has_script "dev:server" || fail "expected dev:server to exist"
  if run_package_has_script "missing"; then
    fail "expected missing script to be absent"
  fi
}

# --- run_js_framework_kind ---

test_framework_kind_and_base_port_for_vite_and_next() {
  local d="$TEST_TMP_ROOT/vite-proj"
  mkdir -p "$d"
  printf '%s\n' '{"dependencies":{"vite":"^5.0.0"}}' >"$d/package.json"
  run_project_init "$d"
  assert_equals "$(run_js_framework_kind)" "vite"
  assert_equals "$(run_infer_dev_base_port)" "5173"

  d="$TEST_TMP_ROOT/next-proj"
  mkdir -p "$d"
  printf '%s\n' '{"dependencies":{"next":"14.0.0"}}' >"$d/package.json"
  run_project_init "$d"
  assert_equals "$(run_js_framework_kind)" "next"
  assert_equals "$(run_infer_dev_base_port)" "3000"
}

# --- CLI ---

test_cli_version_aliases_match_package_and_root() {
  local v want
  want="$(pkg_version)"
  v="$("$ROOT/bin/runctl" version)"
  assert_contains "$v" "$want"
  v="$("$ROOT/bin/runctl" --version)"
  assert_contains "$v" "$want"
  v="$("$ROOT/bin/runctl" -v)"
  assert_contains "$v" "$want"
  assert_contains "$v" "$ROOT"
}

test_cli_lib_path_points_at_run_lib() {
  local p
  p="$("$ROOT/bin/runctl" lib-path)"
  assert_equals "$p" "$ROOT/lib/run-lib.sh"
  [[ -f "$p" ]] || fail "lib-path is not a file"
}

test_cli_unknown_command_exits_with_usage() {
  set +e
  local out ec
  out="$("$ROOT/bin/runctl" not-a-real-command-xyz 2>&1)"
  ec=$?
  set -e
  [[ "$ec" -eq 1 ]] || fail "expected exit code 1, got $ec"
  assert_contains "$out" "unknown command"
}

test_cli_logs_tails_file_inferred_from_package_name() {
  local d="$TEST_TMP_ROOT/logs-by-name"
  mkdir -p "$d/.run/logs"
  printf '%s\n' '{"name":"cool-dashboard"}' >"$d/package.json"
  printf '%s\n' "logline-unique-abc" >"$d/.run/logs/cool-dashboard.log"
  local out
  out="$(cd "$d" && "$ROOT/bin/runctl" logs)"
  assert_contains "$out" "logline-unique-abc"
  assert_contains "$out" "cool-dashboard.log"
}

test_cli_logs_prefers_runctl_service_over_package_name() {
  local d="$TEST_TMP_ROOT/logs-runctl-svc"
  mkdir -p "$d/.run/logs"
  printf '%s\n' '{"name":"ignored"}' >"$d/package.json"
  printf '%s\n' "from-override" >"$d/.run/logs/override-name.log"
  local out
  out="$(cd "$d" && RUNCTL_SERVICE=override-name "$ROOT/bin/runctl" logs)"
  assert_contains "$out" "from-override"
}

test_cli_doctor_fails_without_package_json() {
  local d="$TEST_TMP_ROOT/no-pkg-doctor"
  mkdir -p "$d"
  set +e
  local ec
  (cd "$d" && "$ROOT/bin/runctl" doctor >/dev/null 2>&1)
  ec=$?
  set -e
  [[ "$ec" -eq 1 ]] || fail "doctor should exit 1 without package.json (got $ec)"
}

test_cli_doctor_prints_child_env_hint() {
  local out
  out="$("$ROOT/bin/runctl" doctor 2>&1)"
  assert_contains "$out" "child env:"
  assert_contains "$out" "PORT"
}

test_cli_ports_shows_empty_registry() {
  local state="$TEST_TMP_ROOT/global-ports-empty"
  mkdir -p "$state/ports"
  local out
  out="$(RUN_GLOBAL_STATE="$state" "$ROOT/bin/runctl" ports)"
  assert_contains "$out" "PORT"
  assert_contains "$out" "(no claimed ports)"
}

test_cli_stop_is_idempotent_on_clean_tree() {
  local d="$TEST_TMP_ROOT/stop-clean"
  mkdir -p "$d"
  printf '%s\n' '{}' >"$d/package.json"
  local out
  out="$(cd "$d" && "$ROOT/bin/runctl" stop 2>&1)"
  assert_contains "$out" "stopped"
}

test_cli_status_prints_resolved_project_path() {
  mkdir -p "$TEST_TMP_ROOT/status-proj"
  local d
  d="$(cd "$TEST_TMP_ROOT/status-proj" && pwd)"
  printf '%s\n' '{"name":"x"}' >"$d/package.json"
  local out
  out="$(cd "$d" && "$ROOT/bin/runctl" status 2>&1)"
  assert_contains "$out" "project:"
  assert_contains "$out" "$d"
}

test_cli_help_lists_runctl() {
  local out
  out="$("$ROOT/bin/runctl" --help)"
  assert_contains "$out" "runctl"
  assert_contains "$out" "run-sh"
}

test_cli_run_sh_prints_example_file() {
  local got
  got="$("$ROOT/bin/runctl" run-sh)"
  assert_contains "$got" "Thin project runner"
  cmp -s <("$ROOT/bin/runctl" run-sh) "$ROOT/examples/run.sh.example" || fail "run-sh should match examples/run.sh.example"
  cmp -s <("$ROOT/bin/runctl" run-sh --print) <("$ROOT/bin/runctl" run-sh) || fail "run-sh --print should match default"
}

test_cli_run_sh_rejects_unknown_option() {
  set +e
  local ec out
  out="$("$ROOT/bin/runctl" run-sh --not-a-real-flag 2>&1)"
  ec=$?
  set -e
  [[ "$ec" -ne 0 ]] || fail "run-sh should reject unknown flags"
  assert_contains "$out" "unknown option"
}

test_cli_run_sh_write_creates_executable_run_sh() {
  local d="$TEST_TMP_ROOT/run-sh-write-proj"
  rm -rf "$d"
  mkdir -p "$d"
  local out
  out="$(cd "$d" && "$ROOT/bin/runctl" run-sh --write 2>&1)"
  assert_contains "$out" "wrote"
  assert_contains "$out" "run.sh"
  [[ -x "$d/run.sh" ]] || fail "run.sh should be executable"
  cmp -s "$d/run.sh" "$ROOT/examples/run.sh.example" || fail "written run.sh should match examples/run.sh.example"
}

test_cli_run_sh_write_refuses_overwrite_without_force() {
  local d="$TEST_TMP_ROOT/run-sh-write-twice"
  rm -rf "$d"
  mkdir -p "$d"
  (cd "$d" && "$ROOT/bin/runctl" run-sh --write >/dev/null)
  set +e
  local ec out
  out="$(cd "$d" && "$ROOT/bin/runctl" run-sh --write 2>&1)"
  ec=$?
  set -e
  [[ "$ec" -ne 0 ]] || fail "run-sh --write should refuse overwrite without --force"
  assert_contains "$out" "already exists"
}

test_cli_open_fails_without_ports_env() {
  local d="$TEST_TMP_ROOT/open-no-state"
  mkdir -p "$d"
  set +e
  local ec out
  out="$(cd "$d" && "$ROOT/bin/runctl" open 2>&1)"
  ec=$?
  set -e
  [[ "$ec" -eq 1 ]] || fail "open should exit 1 without .run/ports.env (got $ec)"
  assert_contains "$out" "ports.env"
}

test_cli_logs_fails_when_default_log_file_missing() {
  local d="$TEST_TMP_ROOT/logs-missing"
  mkdir -p "$d/.run/logs"
  printf '%s\n' '{"name":"nope"}' >"$d/package.json"
  set +e
  local ec out
  out="$(cd "$d" && "$ROOT/bin/runctl" logs 2>&1)"
  ec=$?
  set -e
  [[ "$ec" -eq 1 ]] || fail "logs should exit 1 when default log missing (got $ec)"
  assert_contains "$out" "no file at"
}

main() {
  runner_init "tests/runctl-core.test.sh"

  runner_suite "run_sanitize_service_name"
  runner_it "maps empty string and dash-only input to web" test_sanitizes_empty_and_dashes
  runner_it "preserves underscores and normalizes special characters" test_sanitizes_special_characters

  runner_suite "run_default_service_name"
  runner_it "uses RUNCTL_SERVICE when set" test_default_name_honors_runctl_service
  runner_it "derives name from scoped and unscoped package.json" test_default_name_reads_scoped_and_plain_package_names
  runner_it "falls back to web for invalid JSON" test_default_name_falls_back_for_invalid_json
  runner_it "falls back to web when package.json is absent" test_default_name_falls_back_without_package_json

  runner_suite "run_slug"
  runner_it "returns a non-empty stable hash for a path" test_run_slug_produces_stable_non_empty_id

  runner_suite "run_project_init & run_write_ports_env"
  runner_it "writes PORT and RUN_DEV_SERVICE to .run/ports.env" test_write_ports_env_records_port_and_service

  runner_suite "run_package_has_script"
  runner_it "returns true only for defined script keys" test_package_has_script_detects_defined_scripts

  runner_suite "run_js_framework_kind & run_infer_dev_base_port"
  runner_it "infers vite (5173) and next (3000) from dependencies" test_framework_kind_and_base_port_for_vite_and_next

  runner_suite "CLI"
  runner_it "version, --version, and -v match package.json and show install root" test_cli_version_aliases_match_package_and_root
  runner_it "lib-path resolves to packaged run-lib.sh" test_cli_lib_path_points_at_run_lib
  runner_it "unknown command exits 1 and prints usage" test_cli_unknown_command_exits_with_usage
  runner_it "logs tails the file inferred from package name" test_cli_logs_tails_file_inferred_from_package_name
  runner_it "logs prefers RUNCTL_SERVICE when set" test_cli_logs_prefers_runctl_service_over_package_name
  runner_it "doctor exits 1 in a directory without package.json" test_cli_doctor_fails_without_package_json
  runner_it "doctor reminds that child processes receive PORT / HOST" test_cli_doctor_prints_child_env_hint
  runner_it "ports shows an empty registry message" test_cli_ports_shows_empty_registry
  runner_it "stop succeeds on a tree with no daemons" test_cli_stop_is_idempotent_on_clean_tree
  runner_it "status includes the resolved project path" test_cli_status_prints_resolved_project_path
  runner_it "--help mentions runctl" test_cli_help_lists_runctl
  runner_it "run-sh prints examples/run.sh.example" test_cli_run_sh_prints_example_file
  runner_it "run-sh rejects unknown options" test_cli_run_sh_rejects_unknown_option
  runner_it "run-sh --write creates executable run.sh" test_cli_run_sh_write_creates_executable_run_sh
  runner_it "run-sh --write refuses overwrite without --force" test_cli_run_sh_write_refuses_overwrite_without_force
  runner_it "open exits 1 when .run/ports.env is missing" test_cli_open_fails_without_ports_env
  runner_it "logs exits 1 when the inferred log file is missing" test_cli_logs_fails_when_default_log_file_missing

  runner_summary
}

main "$@"
