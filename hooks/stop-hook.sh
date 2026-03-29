#!/bin/bash

# Review Deep Loop - Phase-Aware Stop Hook
# Extends Ralph Wiggum's stop hook with an 8-phase deep review pipeline.
# Phases: baseline → completeness → architecture → code → infrastructure → security → validation → report
# Key feature: LOOP-BACK mechanism from validation → completeness for re-review cycles.

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/review-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: safe SQLite query via Python with parameterized path
# ---------------------------------------------------------------------------
safe_db_count() {
  local db_file="$1"
  local sql_query="$2"
  if [[ ! -f "$db_file" ]]; then
    echo "0"
    return
  fi
  local result
  result=$(python3 -c "
import sqlite3, sys
try:
    db = sqlite3.connect(sys.argv[1])
    print(db.execute(sys.argv[2]).fetchone()[0])
    db.close()
except Exception as e:
    print('DB_ERROR:' + str(e), file=sys.stderr)
    print('-1')
" "$db_file" "$sql_query" 2>&1)

  if [[ "$result" == "-1" ]] || [[ -z "$result" ]]; then
    echo "-1"
  else
    echo "$result"
  fi
}

# ---------------------------------------------------------------------------
# Parse state file frontmatter
# ---------------------------------------------------------------------------
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

parse_field() {
  local field="$1"
  echo "$FRONTMATTER" | grep "^${field}:" | sed "s/${field}: *//" | sed 's/^"\(.*\)"$/\1/'
}

CURRENT_PHASE=$(parse_field "current_phase")
PHASE_NAME=$(parse_field "phase_name")
PHASE_ITERATION=$(parse_field "phase_iteration")
GLOBAL_ITERATION=$(parse_field "global_iteration")
MAX_GLOBAL_ITERATIONS=$(parse_field "max_global_iterations")
COMPLETION_PROMISE=$(parse_field "completion_promise")
TARGET=$(parse_field "target")
SCOPE=$(parse_field "scope")
OUTPUT_DIR=$(parse_field "output_dir")
MODE=$(parse_field "mode")
SEVERITY_THRESHOLD=$(parse_field "severity_threshold")
REVIEW_CYCLES=$(parse_field "review_cycles")
MAX_REVIEW_CYCLES=$(parse_field "max_review_cycles")
COMPONENTS_MAPPED=$(parse_field "components_mapped")
FLOWS_MAPPED=$(parse_field "flows_mapped")
FINDINGS_TOTAL=$(parse_field "findings_total")
FINDINGS_CRITICAL=$(parse_field "findings_critical")
FINDINGS_HIGH=$(parse_field "findings_high")

# Phase max iterations
declare -A PHASE_MAX_ITER
PHASE_MAX_ITER[1]=3   # baseline
PHASE_MAX_ITER[2]=3   # completeness
PHASE_MAX_ITER[3]=3   # architecture
PHASE_MAX_ITER[4]=4   # code
PHASE_MAX_ITER[5]=3   # infrastructure
PHASE_MAX_ITER[6]=3   # security
PHASE_MAX_ITER[7]=3   # validation
PHASE_MAX_ITER[8]=2   # report

# Phase names lookup
declare -A PHASE_NAMES
PHASE_NAMES[1]="baseline"
PHASE_NAMES[2]="completeness"
PHASE_NAMES[3]="architecture"
PHASE_NAMES[4]="code"
PHASE_NAMES[5]="infrastructure"
PHASE_NAMES[6]="security"
PHASE_NAMES[7]="validation"
PHASE_NAMES[8]="report"

# Quality gate: phases that require quality evaluation before advancing
declare -A PHASE_QUALITY_GATE
PHASE_QUALITY_GATE[1]=0   # baseline — no gate
PHASE_QUALITY_GATE[2]=1   # completeness — quality matters
PHASE_QUALITY_GATE[3]=1   # architecture — quality matters
PHASE_QUALITY_GATE[4]=1   # code — quality matters
PHASE_QUALITY_GATE[5]=1   # infrastructure — quality matters
PHASE_QUALITY_GATE[6]=1   # security — quality matters
PHASE_QUALITY_GATE[7]=1   # validation — quality matters
PHASE_QUALITY_GATE[8]=0   # report — final pass, no gate

# Mode-specific phase skipping
# quick: skip phases 5 (infrastructure), 6 (security), 7 (validation)
# security: skip phases 2 (completeness), 3 (architecture), 4 (code), 7 (validation)
# architecture: skip phases 4 (code), 5 (infrastructure), 6 (security), 7 (validation)
declare -A SKIP_PHASES
if [[ "$MODE" == "quick" ]]; then
  SKIP_PHASES[5]=1
  SKIP_PHASES[6]=1
  SKIP_PHASES[7]=1
elif [[ "$MODE" == "security" ]]; then
  SKIP_PHASES[2]=1
  SKIP_PHASES[3]=1
  SKIP_PHASES[4]=1
  SKIP_PHASES[7]=1
elif [[ "$MODE" == "architecture" ]]; then
  SKIP_PHASES[4]=1
  SKIP_PHASES[5]=1
  SKIP_PHASES[6]=1
  SKIP_PHASES[7]=1
fi

# ---------------------------------------------------------------------------
# Validate numeric fields
# ---------------------------------------------------------------------------
validate_numeric() {
  local field_name="$1"
  local field_value="$2"
  if [[ ! "$field_value" =~ ^[0-9]+$ ]]; then
    echo "⚠️  Review loop: State file corrupted" >&2
    echo "   File: $STATE_FILE" >&2
    echo "   Problem: '$field_name' is not a valid number (got: '$field_value')" >&2
    echo "   Review loop is stopping. Run /review-loop again to start fresh." >&2
    rm "$STATE_FILE"
    exit 0
  fi
}

validate_numeric "current_phase" "$CURRENT_PHASE"
validate_numeric "phase_iteration" "$PHASE_ITERATION"
validate_numeric "global_iteration" "$GLOBAL_ITERATION"
validate_numeric "max_global_iterations" "$MAX_GLOBAL_ITERATIONS"
validate_numeric "review_cycles" "$REVIEW_CYCLES"
validate_numeric "max_review_cycles" "$MAX_REVIEW_CYCLES"

# Validate bounds — current_phase must be 1-8
if [[ $CURRENT_PHASE -lt 1 ]] || [[ $CURRENT_PHASE -gt 8 ]]; then
  echo "⚠️  Review loop: State file corrupted — current_phase=$CURRENT_PHASE (must be 1-8)" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check global iteration limit
# ---------------------------------------------------------------------------
if [[ $MAX_GLOBAL_ITERATIONS -gt 0 ]] && [[ $GLOBAL_ITERATION -ge $MAX_GLOBAL_ITERATIONS ]]; then
  echo "🛑 Review loop: Max global iterations ($MAX_GLOBAL_ITERATIONS) reached."
  echo "   Target: $TARGET"
  echo "   Final phase: $CURRENT_PHASE ($PHASE_NAME)"
  echo "   Components: $COMPONENTS_MAPPED | Flows: $FLOWS_MAPPED"
  echo "   Findings: total=$FINDINGS_TOTAL critical=$FINDINGS_CRITICAL high=$FINDINGS_HIGH"
  echo "   Review cycles: $REVIEW_CYCLES/$MAX_REVIEW_CYCLES"
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Read transcript and extract last assistant output
# ---------------------------------------------------------------------------
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Review loop: Transcript file not found at $TRANSCRIPT_PATH" >&2
  rm "$STATE_FILE"
  exit 0
fi

if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  Review loop: No assistant messages found in transcript" >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
if [[ -z "$LAST_LINE" ]]; then
  echo "⚠️  Review loop: Failed to extract last assistant message" >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>&1)

if [[ $? -ne 0 ]] || [[ -z "$LAST_OUTPUT" ]]; then
  echo "⚠️  Review loop: Failed to parse assistant message" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check for completion promise
# ---------------------------------------------------------------------------
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "✅ Review loop complete: <promise>$COMPLETION_PROMISE</promise>"
    echo "   Target: $TARGET"
    echo "   Total iterations: $GLOBAL_ITERATION"
    echo "   Final phase: $CURRENT_PHASE ($PHASE_NAME)"
    echo "   Components: $COMPONENTS_MAPPED | Flows: $FLOWS_MAPPED"
    echo "   Findings: total=$FINDINGS_TOTAL critical=$FINDINGS_CRITICAL high=$FINDINGS_HIGH"
    echo "   Review cycles: $REVIEW_CYCLES/$MAX_REVIEW_CYCLES"
    echo "   Output: $OUTPUT_DIR/"
    rm "$STATE_FILE"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Detect phase completion markers and update counters from output
# ---------------------------------------------------------------------------
PHASE_ADVANCED=false
FORCED_ADVANCE=false

# Check for explicit phase completion marker: <!-- PHASE_N_COMPLETE -->
if echo "$LAST_OUTPUT" | grep -qE "<!--\s*PHASE_${CURRENT_PHASE}_COMPLETE\s*-->"; then
  PHASE_ADVANCED=true
fi

# Update counters from output markers (if present)
NEW_COMPONENTS=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*COMPONENTS_MAPPED:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_FLOWS=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*FLOWS_MAPPED:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_FINDINGS_TOTAL=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*FINDINGS_TOTAL:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_FINDINGS_CRITICAL=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*FINDINGS_CRITICAL:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_FINDINGS_HIGH=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*FINDINGS_HIGH:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_REVIEW_CYCLE=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*REVIEW_CYCLE:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")

[[ -n "$NEW_COMPONENTS" ]] && COMPONENTS_MAPPED="$NEW_COMPONENTS"
[[ -n "$NEW_FLOWS" ]] && FLOWS_MAPPED="$NEW_FLOWS"
[[ -n "$NEW_FINDINGS_TOTAL" ]] && FINDINGS_TOTAL="$NEW_FINDINGS_TOTAL"
[[ -n "$NEW_FINDINGS_CRITICAL" ]] && FINDINGS_CRITICAL="$NEW_FINDINGS_CRITICAL"
[[ -n "$NEW_FINDINGS_HIGH" ]] && FINDINGS_HIGH="$NEW_FINDINGS_HIGH"
[[ -n "$NEW_REVIEW_CYCLE" ]] && REVIEW_CYCLES="$NEW_REVIEW_CYCLE"

# ---------------------------------------------------------------------------
# Quality gate: check if phase completion passed quality evaluation
# ---------------------------------------------------------------------------
QUALITY_FAILED=false

if [[ "$PHASE_ADVANCED" == "true" ]]; then
  HAS_GATE=${PHASE_QUALITY_GATE[$CURRENT_PHASE]:-0}

  if [[ "$HAS_GATE" == "1" ]]; then
    QUALITY_SCORE=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*QUALITY_SCORE:([\d.]+)\s*-->' | grep -oP '[\d.]+' | tail -1 || echo "")
    QUALITY_PASSED=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*QUALITY_PASSED:(\d)\s*-->' | grep -oP '\d' | tail -1 || echo "")

    if [[ -z "$QUALITY_PASSED" ]]; then
      PHASE_ADVANCED=false
      QUALITY_FAILED=true
    elif [[ "$QUALITY_PASSED" == "0" ]]; then
      PHASE_ADVANCED=false
      QUALITY_FAILED=true
    fi
  fi
fi

# Check for phase timeout (forced advancement)
CURRENT_PHASE_MAX=${PHASE_MAX_ITER[$CURRENT_PHASE]:-3}
if [[ "$PHASE_ADVANCED" != "true" ]] && [[ "$QUALITY_FAILED" != "true" ]] && [[ $PHASE_ITERATION -ge $CURRENT_PHASE_MAX ]]; then
  PHASE_ADVANCED=true
  FORCED_ADVANCE=true
fi

# ---------------------------------------------------------------------------
# HARD BLOCKS — verify mandatory work BEFORE allowing phase advancement
# ---------------------------------------------------------------------------
HARD_BLOCK=false
HARD_BLOCK_MSG=""

if [[ "$PHASE_ADVANCED" == "true" ]]; then
  if [[ "$OUTPUT_DIR" == ./* ]] || [[ "$OUTPUT_DIR" != /* ]]; then
    ABS_OUTPUT_DIR="$(pwd)/$OUTPUT_DIR"
  else
    ABS_OUTPUT_DIR="$OUTPUT_DIR"
  fi
  DB_PATH="$ABS_OUTPUT_DIR/review.db"

  # HARD BLOCK 1: Phase 1→2 — components AND flows must have entries
  if [[ $CURRENT_PHASE -eq 1 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    COMP_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM components")
    FLOW_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM flows")
    if [[ "$COMP_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 1 (DB: $DB_PATH)" >&2
      COMP_COUNT=0
    fi
    if [[ "$FLOW_COUNT" == "-1" ]]; then
      FLOW_COUNT=0
    fi
    if [[ "$COMP_COUNT" -eq 0 ]] || [[ "$FLOW_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 1 (baseline) cannot advance — components=$COMP_COUNT flows=$FLOW_COUNT (DB: $DB_PATH). You MUST map system components AND critical flows before advancing."
    fi
  fi

  # HARD BLOCK 2: Phase 2→3 — findings must have entries for phase 2
  if [[ $CURRENT_PHASE -eq 2 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    FINDING_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM findings WHERE phase=2")
    if [[ "$FINDING_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 2 (DB: $DB_PATH)" >&2
      FINDING_COUNT=0
    fi
    if [[ "$FINDING_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 2 (completeness) cannot advance — 0 findings registered for phase 2 (DB: $DB_PATH). You MUST audit functional completeness and register findings before advancing."
    fi
  fi

  # HARD BLOCK 3: Phase 3→4 — findings must have entries for phase 3
  if [[ $CURRENT_PHASE -eq 3 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    FINDING_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM findings WHERE phase=3")
    if [[ "$FINDING_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 3 (DB: $DB_PATH)" >&2
      FINDING_COUNT=0
    fi
    if [[ "$FINDING_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 3 (architecture) cannot advance — 0 findings registered for phase 3 (DB: $DB_PATH). You MUST review architecture and register findings before advancing."
    fi
  fi

  # HARD BLOCK 4: Phase 4→5 — findings must have entries for phase 4
  if [[ $CURRENT_PHASE -eq 4 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    FINDING_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM findings WHERE phase=4")
    if [[ "$FINDING_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 4 (DB: $DB_PATH)" >&2
      FINDING_COUNT=0
    fi
    if [[ "$FINDING_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 4 (code) cannot advance — 0 findings registered for phase 4 (DB: $DB_PATH). You MUST perform deep code review and register findings before advancing."
    fi
  fi

  # HARD BLOCK 5: Phase 5→6 — findings must have entries for phase 5
  if [[ $CURRENT_PHASE -eq 5 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    FINDING_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM findings WHERE phase=5")
    if [[ "$FINDING_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 5 (DB: $DB_PATH)" >&2
      FINDING_COUNT=0
    fi
    if [[ "$FINDING_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 5 (infrastructure) cannot advance — 0 findings registered for phase 5 (DB: $DB_PATH). You MUST review infrastructure and register findings before advancing."
    fi
  fi

  # HARD BLOCK 6: Phase 6→7 — threat_models must have entries
  if [[ $CURRENT_PHASE -eq 6 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    THREAT_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM threat_models")
    if [[ "$THREAT_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 6 (DB: $DB_PATH)" >&2
      THREAT_COUNT=0
    fi
    if [[ "$THREAT_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 6 (security) cannot advance — 0 threat models registered (DB: $DB_PATH). You MUST perform threat modeling and register threats before advancing."
    fi
  fi

  # HARD BLOCK 7: Phase 7→8 — findings must have entries for phase 7
  if [[ $CURRENT_PHASE -eq 7 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    FINDING_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM findings WHERE phase=7")
    if [[ "$FINDING_COUNT" == "-1" ]]; then
      echo "⚠️  Review loop: Database error checking hard block for phase 7 (DB: $DB_PATH)" >&2
      FINDING_COUNT=0
    fi
    if [[ "$FINDING_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 7 (validation) cannot advance — 0 findings registered for phase 7 (DB: $DB_PATH). You MUST validate E2E flows and register findings before advancing."
    fi
  fi

  if [[ "$HARD_BLOCK" == "true" ]]; then
    PHASE_ADVANCED=false
    FORCED_ADVANCE=false
    QUALITY_FAILED=false
    echo "🚫 HARD BLOCK ACTIVATED — Phase $CURRENT_PHASE cannot advance. DB: $DB_PATH" >&2
  fi
fi

# ---------------------------------------------------------------------------
# LOOP-BACK MECHANISM — validation → completeness for re-review cycles
# When Phase 7 (validation) outputs <!-- LOOP_BACK_TO_COMPLETENESS -->, loop back
# to Phase 2 (completeness) if review cycles remain.
# ---------------------------------------------------------------------------
LOOP_BACK=false

if [[ "$PHASE_ADVANCED" == "true" ]] && [[ $CURRENT_PHASE -eq 7 ]]; then
  if echo "$LAST_OUTPUT" | grep -qE "<!--\s*LOOP_BACK_TO_COMPLETENESS\s*-->"; then
    if [[ $REVIEW_CYCLES -lt $MAX_REVIEW_CYCLES ]]; then
      LOOP_BACK=true
      CURRENT_PHASE=2
      PHASE_NAME="completeness"
      PHASE_ITERATION=0
      REVIEW_CYCLES=$((REVIEW_CYCLES + 1))
      PHASE_ADVANCED=false
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Advance phase if needed
# ---------------------------------------------------------------------------
MAX_PHASE=8

if [[ "$PHASE_ADVANCED" == "true" ]]; then
  if [[ $CURRENT_PHASE -ge $MAX_PHASE ]]; then
    echo "🛑 Review loop: All $MAX_PHASE phases complete but no completion promise detected."
    echo "   Target: $TARGET"
    echo "   Findings: total=$FINDINGS_TOTAL critical=$FINDINGS_CRITICAL high=$FINDINGS_HIGH"
    echo "   Review cycles: $REVIEW_CYCLES/$MAX_REVIEW_CYCLES"
    echo "   Output should be in: $OUTPUT_DIR/"
    rm "$STATE_FILE"
    exit 0
  fi

  CURRENT_PHASE=$((CURRENT_PHASE + 1))
  PHASE_NAME="${PHASE_NAMES[$CURRENT_PHASE]}"
  PHASE_ITERATION=0

  # Skip phases based on mode
  while [[ ${SKIP_PHASES[$CURRENT_PHASE]:-0} -eq 1 ]] && [[ $CURRENT_PHASE -lt $MAX_PHASE ]]; do
    CURRENT_PHASE=$((CURRENT_PHASE + 1))
    PHASE_NAME="${PHASE_NAMES[$CURRENT_PHASE]}"
  done
fi

# ---------------------------------------------------------------------------
# Increment counters
# ---------------------------------------------------------------------------
NEXT_GLOBAL=$((GLOBAL_ITERATION + 1))
NEXT_PHASE_ITER=$((PHASE_ITERATION + 1))

# ---------------------------------------------------------------------------
# Extract prompt text (everything after second ---)
# ---------------------------------------------------------------------------
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  Review loop: No prompt text found in state file" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Update state file atomically
# ---------------------------------------------------------------------------
TEMP_FILE=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
cat > "$TEMP_FILE" <<EOF
---
active: true
target: "$TARGET"
scope: "$SCOPE"
current_phase: $CURRENT_PHASE
phase_name: "$PHASE_NAME"
phase_iteration: $NEXT_PHASE_ITER
global_iteration: $NEXT_GLOBAL
max_global_iterations: $MAX_GLOBAL_ITERATIONS
completion_promise: "$(echo "$COMPLETION_PROMISE" | sed 's/"/\\"/g')"
started_at: "$(parse_field "started_at")"
output_dir: "$OUTPUT_DIR"
mode: "$MODE"
severity_threshold: "$SEVERITY_THRESHOLD"
review_cycles: $REVIEW_CYCLES
max_review_cycles: $MAX_REVIEW_CYCLES
components_mapped: $COMPONENTS_MAPPED
flows_mapped: $FLOWS_MAPPED
findings_total: $FINDINGS_TOTAL
findings_critical: $FINDINGS_CRITICAL
findings_high: $FINDINGS_HIGH
---

$PROMPT_TEXT
EOF
mv "$TEMP_FILE" "$STATE_FILE"

# ---------------------------------------------------------------------------
# Build system message with phase context
# ---------------------------------------------------------------------------
PHASE_MAX_FOR_CURRENT=${PHASE_MAX_ITER[$CURRENT_PHASE]:-3}

SYSTEM_MSG="🔍 Review Loop | Phase $CURRENT_PHASE/$MAX_PHASE: $PHASE_NAME | Phase iter $NEXT_PHASE_ITER/$PHASE_MAX_FOR_CURRENT | Global iter $NEXT_GLOBAL"
SYSTEM_MSG="$SYSTEM_MSG | Mode: $MODE | Severity: $SEVERITY_THRESHOLD"
if [[ -n "$SCOPE" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | Scope: $SCOPE"
fi
SYSTEM_MSG="$SYSTEM_MSG | Components: $COMPONENTS_MAPPED | Flows: $FLOWS_MAPPED"
SYSTEM_MSG="$SYSTEM_MSG | Findings: total=$FINDINGS_TOTAL critical=$FINDINGS_CRITICAL high=$FINDINGS_HIGH"
SYSTEM_MSG="$SYSTEM_MSG | Review cycles: $REVIEW_CYCLES/$MAX_REVIEW_CYCLES"

if [[ "$FORCED_ADVANCE" == "true" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | ⚠️ Previous phase timed out — forced advancement to $PHASE_NAME"
fi

if [[ "$QUALITY_FAILED" == "true" ]]; then
  if [[ -n "${QUALITY_SCORE:-}" ]]; then
    SYSTEM_MSG="$SYSTEM_MSG | ❌ Quality gate FAILED (score: $QUALITY_SCORE) — repeating phase. Review evaluator feedback and improve output."
  else
    SYSTEM_MSG="$SYSTEM_MSG | ❌ Quality gate REQUIRED but no quality evaluation found — you MUST run the quality-evaluator agent and emit <!-- QUALITY_SCORE:X.XX --> <!-- QUALITY_PASSED:1 --> markers before this phase can advance."
  fi
fi

if [[ "$HARD_BLOCK" == "true" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | $HARD_BLOCK_MSG"
fi

if [[ "$LOOP_BACK" == "true" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | 🔄 LOOP-BACK: Returning to completeness phase for re-review cycle $REVIEW_CYCLES/$MAX_REVIEW_CYCLES"
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | To finish: <promise>$COMPLETION_PROMISE</promise> (ONLY when TRUE)"
fi

# ---------------------------------------------------------------------------
# Block exit and re-inject prompt
# ---------------------------------------------------------------------------
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
