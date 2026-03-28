#!/bin/bash
# Tests for stop-hook.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$PLUGIN_ROOT/hooks/stop-hook.sh"
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

# ---------------------------------------------------------------------------
# Setup temp workspace
# ---------------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

echo "=== Stop Hook Tests ==="

# ---------------------------------------------------------------------------
# Test 1: No state file — exits cleanly with code 0
# ---------------------------------------------------------------------------
echo ""
echo "Test 1: No state file exits cleanly"
OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1 || true)
EXIT_CODE=$?
assert_eq "exit code 0" "0" "$EXIT_CODE"

# ---------------------------------------------------------------------------
# Test 2: Corrupted current_phase — removes state and exits
# ---------------------------------------------------------------------------
echo ""
echo "Test 2: Corrupted state file is cleaned up"
mkdir -p .claude
cat > .claude/review-loop.local.md <<'EOF'
---
active: true
target: "/tmp/test"
current_phase: abc
phase_name: "baseline"
phase_iteration: 1
global_iteration: 1
max_global_iterations: 80
completion_promise: "DEEP REVIEW COMPLETE"
started_at: "2026-01-01T00:00:00Z"
output_dir: "./review-output"
mode: "full"
severity_threshold: "low"
review_cycles: 0
max_review_cycles: 2
components_mapped: 0
flows_mapped: 0
findings_total: 0
findings_critical: 0
findings_high: 0
---

Test prompt
EOF

OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1 || true)
assert_contains "corruption detected" "corrupted" "$OUTPUT"
if [[ ! -f .claude/review-loop.local.md ]]; then
  echo "  PASS: state file removed after corruption"
  PASS=$((PASS + 1))
else
  echo "  FAIL: state file should have been removed"
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Test 3: Phase out of bounds (9) — removes state
# ---------------------------------------------------------------------------
echo ""
echo "Test 3: Phase out of bounds is detected"
mkdir -p .claude
cat > .claude/review-loop.local.md <<'EOF'
---
active: true
target: "/tmp/test"
current_phase: 9
phase_name: "invalid"
phase_iteration: 1
global_iteration: 1
max_global_iterations: 80
completion_promise: "DEEP REVIEW COMPLETE"
started_at: "2026-01-01T00:00:00Z"
output_dir: "./review-output"
mode: "full"
severity_threshold: "low"
review_cycles: 0
max_review_cycles: 2
components_mapped: 0
flows_mapped: 0
findings_total: 0
findings_critical: 0
findings_high: 0
---

Test prompt
EOF

OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1 || true)
assert_contains "bounds violation detected" "corrupted" "$OUTPUT"

# ---------------------------------------------------------------------------
# Test 4: Max iterations reached — stops loop
# ---------------------------------------------------------------------------
echo ""
echo "Test 4: Max iterations reached stops loop"
mkdir -p .claude
cat > .claude/review-loop.local.md <<'EOF'
---
active: true
target: "/tmp/test"
current_phase: 3
phase_name: "architecture"
phase_iteration: 2
global_iteration: 80
max_global_iterations: 80
completion_promise: "DEEP REVIEW COMPLETE"
started_at: "2026-01-01T00:00:00Z"
output_dir: "./review-output"
mode: "full"
severity_threshold: "low"
review_cycles: 0
max_review_cycles: 2
components_mapped: 5
flows_mapped: 3
findings_total: 12
findings_critical: 1
findings_high: 3
---

Test prompt
EOF

# Create a transcript file for the hook to read
TRANSCRIPT=$(mktemp "$WORK_DIR/transcript.XXXXXX")
echo '{"role":"assistant","message":{"content":[{"type":"text","text":"Working on architecture review."}]}}' > "$TRANSCRIPT"
HOOK_INPUT=$(jq -n --arg path "$TRANSCRIPT" '{"transcript_path": $path}')

OUTPUT=$(echo "$HOOK_INPUT" | bash "$HOOK_SCRIPT" 2>&1 || true)
assert_contains "max iterations message" "Max global iterations" "$OUTPUT"
if [[ ! -f .claude/review-loop.local.md ]]; then
  echo "  PASS: state file removed after max iterations"
  PASS=$((PASS + 1))
else
  echo "  FAIL: state file should have been removed"
  FAIL=$((FAIL + 1))
fi
rm -f "$TRANSCRIPT"

# ---------------------------------------------------------------------------
# Test 5: Validate numeric rejects non-numeric review_cycles
# ---------------------------------------------------------------------------
echo ""
echo "Test 5: Non-numeric review_cycles detected"
mkdir -p .claude
cat > .claude/review-loop.local.md <<'EOF'
---
active: true
target: "/tmp/test"
current_phase: 2
phase_name: "completeness"
phase_iteration: 1
global_iteration: 5
max_global_iterations: 80
completion_promise: "DEEP REVIEW COMPLETE"
started_at: "2026-01-01T00:00:00Z"
output_dir: "./review-output"
mode: "full"
severity_threshold: "low"
review_cycles: abc
max_review_cycles: 2
components_mapped: 3
flows_mapped: 2
findings_total: 0
findings_critical: 0
findings_high: 0
---

Test prompt
EOF

OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1 || true)
assert_contains "numeric validation" "corrupted" "$OUTPUT"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==================================="
echo "Stop Hook Tests: $PASS passed, $FAIL failed"
echo "==================================="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
