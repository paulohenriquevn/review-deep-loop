#!/bin/bash
# Tests for setup-review-loop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="$PLUGIN_ROOT/scripts/setup-review-loop.sh"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected='$expected', got='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$expected')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local desc="$1" path="$2"
  if [[ -d "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (dir not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Setup temp workspace
# ---------------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
TARGET_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR" "$TARGET_DIR"' EXIT
cd "$WORK_DIR"

echo "=== Setup Script Tests ==="

# ---------------------------------------------------------------------------
# Test 1: No arguments shows error
# ---------------------------------------------------------------------------
echo ""
echo "Test 1: No arguments shows error"
OUTPUT=$(bash "$SETUP_SCRIPT" 2>&1 || true)
assert_contains "error message shown" "Error: No target" "$OUTPUT"

# ---------------------------------------------------------------------------
# Test 2: --help shows usage
# ---------------------------------------------------------------------------
echo ""
echo "Test 2: --help shows usage"
OUTPUT=$(bash "$SETUP_SCRIPT" --help 2>&1 || true)
assert_contains "shows usage" "USAGE:" "$OUTPUT"
assert_contains "shows modes" "full|quick|security|architecture" "$OUTPUT"

# ---------------------------------------------------------------------------
# Test 3: Basic setup creates state file and output
# ---------------------------------------------------------------------------
echo ""
echo "Test 3: Basic setup creates state file and output directory"
bash "$SETUP_SCRIPT" "$TARGET_DIR" --output-dir "$WORK_DIR/test-output" > /dev/null 2>&1 || true
assert_file_exists "state file created" "$WORK_DIR/.claude/review-loop.local.md"
assert_dir_exists "output dir created" "$WORK_DIR/test-output"
assert_dir_exists "baseline dir" "$WORK_DIR/test-output/baseline"
assert_dir_exists "findings/completeness dir" "$WORK_DIR/test-output/findings/completeness"
assert_dir_exists "findings/security dir" "$WORK_DIR/test-output/findings/security"
assert_dir_exists "analysis/threat_models dir" "$WORK_DIR/test-output/analysis/threat_models"
assert_dir_exists "state/meetings dir" "$WORK_DIR/test-output/state/meetings"
assert_dir_exists "figures dir" "$WORK_DIR/test-output/figures"
assert_file_exists "database created" "$WORK_DIR/test-output/review.db"

# ---------------------------------------------------------------------------
# Test 4: State file has correct frontmatter
# ---------------------------------------------------------------------------
echo ""
echo "Test 4: State file has correct frontmatter"
STATE_CONTENT=$(cat "$WORK_DIR/.claude/review-loop.local.md")
assert_contains "has active field" "active: true" "$STATE_CONTENT"
assert_contains "has target field" "target:" "$STATE_CONTENT"
assert_contains "has phase 1" "current_phase: 1" "$STATE_CONTENT"
assert_contains "has phase name" 'phase_name: "baseline"' "$STATE_CONTENT"
assert_contains "has mode" 'mode: "full"' "$STATE_CONTENT"
assert_contains "has completion promise" "DEEP REVIEW COMPLETE" "$STATE_CONTENT"
assert_contains "has findings counters" "findings_total: 0" "$STATE_CONTENT"
assert_contains "has review cycles" "review_cycles: 0" "$STATE_CONTENT"

# ---------------------------------------------------------------------------
# Test 5: Invalid mode is rejected
# ---------------------------------------------------------------------------
echo ""
echo "Test 5: Invalid mode is rejected"
rm -f "$WORK_DIR/.claude/review-loop.local.md"
OUTPUT=$(bash "$SETUP_SCRIPT" "$TARGET_DIR" --mode invalid 2>&1 || true)
assert_contains "error for invalid mode" "Error: --mode must be one of" "$OUTPUT"

# ---------------------------------------------------------------------------
# Test 6: Security mode sets mode correctly
# ---------------------------------------------------------------------------
echo ""
echo "Test 6: Security mode"
rm -f "$WORK_DIR/.claude/review-loop.local.md"
rm -rf "$WORK_DIR/sec-output"
bash "$SETUP_SCRIPT" "$TARGET_DIR" --mode security --output-dir "$WORK_DIR/sec-output" > /dev/null 2>&1 || true
STATE_CONTENT=$(cat "$WORK_DIR/.claude/review-loop.local.md")
assert_contains "mode is security" 'mode: "security"' "$STATE_CONTENT"

# ---------------------------------------------------------------------------
# Test 7: Custom max-iterations
# ---------------------------------------------------------------------------
echo ""
echo "Test 7: Custom max-iterations"
rm -f "$WORK_DIR/.claude/review-loop.local.md"
rm -rf "$WORK_DIR/iter-output"
bash "$SETUP_SCRIPT" "$TARGET_DIR" --max-iterations 50 --output-dir "$WORK_DIR/iter-output" > /dev/null 2>&1 || true
STATE_CONTENT=$(cat "$WORK_DIR/.claude/review-loop.local.md")
assert_contains "max iterations is 50" "max_global_iterations: 50" "$STATE_CONTENT"

# ---------------------------------------------------------------------------
# Test 8: Invalid severity threshold is rejected
# ---------------------------------------------------------------------------
echo ""
echo "Test 8: Invalid severity threshold is rejected"
OUTPUT=$(bash "$SETUP_SCRIPT" "$TARGET_DIR" --severity-threshold extreme 2>&1 || true)
assert_contains "error for invalid severity" "Error: --severity-threshold" "$OUTPUT"

# ---------------------------------------------------------------------------
# Test 9: Non-existent target path is rejected
# ---------------------------------------------------------------------------
echo ""
echo "Test 9: Non-existent target path is rejected"
OUTPUT=$(bash "$SETUP_SCRIPT" "/nonexistent/path/to/project" 2>&1 || true)
assert_contains "error for missing target" "Error: Target path does not exist" "$OUTPUT"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==================================="
echo "Setup Script Tests: $PASS passed, $FAIL failed"
echo "==================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
