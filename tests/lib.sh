#!/usr/bin/env bash
# tests/lib.sh — lightweight assertion helpers for inject-time-context test suite
# Sourced by individual test_*.sh files (or by run-tests.sh invocation context).
# No external dependencies beyond bash built-ins.

# Usage:
#   assert_contains  <haystack> <needle> <msg>
#   assert_not_contains <haystack> <needle> <msg>
#   assert_file_exists  <path> <msg>
#   assert_file_absent  <path> <msg>
#   assert_equal        <actual> <expected> <msg>

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "ASSERT FAILED: $msg" >&2
    echo "  Expected to contain: $needle" >&2
    echo "  Got: $haystack" >&2
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "ASSERT FAILED: $msg" >&2
    echo "  Expected NOT to contain: $needle" >&2
    echo "  Got: $haystack" >&2
    return 1
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [[ ! -f "$path" ]]; then
    echo "ASSERT FAILED: $msg" >&2
    echo "  Expected file to exist: $path" >&2
    return 1
  fi
}

assert_file_absent() {
  local path="$1" msg="$2"
  if [[ -f "$path" ]]; then
    echo "ASSERT FAILED: $msg" >&2
    echo "  Expected file to be absent: $path" >&2
    return 1
  fi
}

assert_equal() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "ASSERT FAILED: $msg" >&2
    echo "  Expected: $expected" >&2
    echo "  Got:      $actual" >&2
    return 1
  fi
}

# Invoke the hook with a given session_id and optional extra env vars.
# Usage: run_hook <session_id> [env_var=value ...]
# Prints hook stdout; returns hook exit code.
run_hook() {
  local sid="$1"; shift
  local hook="${REPO_ROOT}/hooks/inject-time-context.sh"
  local input_json
  input_json=$(printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit"}' "$sid")
  env "$@" bash "$hook" <<< "$input_json"
}
