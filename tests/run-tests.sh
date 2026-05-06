#!/usr/bin/env bash
# run-tests.sh — master test runner for claude-context-tick
# Discovers all tests/test_*.sh files, runs each in a fresh sandboxed HOME,
# and reports pass/fail counts. Exits 0 only when all tests pass.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
FAILURES=()

# Collect and sort test files.
# Use a find-based approach for portability (avoids glob NOMATCH on empty dirs).
# Read loop instead of `mapfile` because macOS ships bash 3.2 (mapfile is bash 4+).
TEST_FILES=()
while IFS= read -r _t; do
  TEST_FILES+=("$_t")
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name 'test_*.sh' | sort)

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
  echo "WARNING: no test_*.sh files found in $SCRIPT_DIR" >&2
  exit 1
fi

echo "=== claude-context-tick test suite ==="
echo "Repo root: $REPO_ROOT"
echo "Tests found: ${#TEST_FILES[@]}"
echo ""

for test_file in "${TEST_FILES[@]}"; do
  test_name="$(basename "$test_file" .sh)"

  # Each test runs in a subprocess with a fresh sandboxed HOME.
  # We export _RUNNER_SANDBOX=1 so the test knows not to create its own sandbox.
  _SANDBOX_HOME=$(mktemp -d)
  RESULT_FILE=$(mktemp)

  set +e
  (
    export HOME="$_SANDBOX_HOME"
    export _RUNNER_SANDBOX=1
    export REPO_ROOT
    # Run the test; capture output; exit code signals pass/fail.
    bash "$test_file" 2>&1
  ) >"$RESULT_FILE" 2>&1
  EXIT_CODE=$?
  set -e

  OUTPUT=$(cat "$RESULT_FILE")
  rm -f "$RESULT_FILE"
  rm -rf "$_SANDBOX_HOME"

  if [[ $EXIT_CODE -eq 0 ]]; then
    echo "[PASS] $test_name"
    (( PASS++ )) || true
  else
    # Extract failure reason: last non-empty line of output.
    REASON=$(grep -v '^$' <<< "$OUTPUT" | tail -1 || echo "(no output)")
    echo "[FAIL] $test_name — $REASON"
    FAILURES+=("$test_name: $REASON")
    (( FAIL++ )) || true
  fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

exit 0
