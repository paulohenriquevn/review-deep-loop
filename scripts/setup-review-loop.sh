#!/bin/bash

# Review Deep Loop - Setup Script
# Creates state file and output directory for the deep review pipeline.

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET_PARTS=()
MODE="full"
MAX_ITERATIONS=80
OUTPUT_DIR="./review-output"
SEVERITY_THRESHOLD="low"
COMPLETION_PROMISE="DEEP REVIEW COMPLETE"
SCOPE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Review Deep Loop - Autonomous deep software review pipeline

USAGE:
  /review-loop [TARGET...] [OPTIONS]

ARGUMENTS:
  TARGET...    Path to the codebase or project to review

OPTIONS:
  --scope <description>          Focus review on a specific module, feature, or
                                 part of the codebase (e.g., "login", "payment
                                 module", "kafka cluster", "user registration")
  --mode <full|quick|security|architecture>
                                 Review mode (default: full)
  --max-iterations <n>           Max global iterations (default: 80)
  --output-dir <path>            Output directory (default: ./review-output)
  --severity-threshold <critical|high|medium|low>
                                 Minimum severity to report (default: low)
  --completion-promise '<text>'  Promise phrase (default: "DEEP REVIEW COMPLETE")
  -h, --help                     Show this help message

DESCRIPTION:
  Starts an autonomous deep software review pipeline that iterates through
  8 phases: baseline, completeness, architecture, code, infrastructure,
  security, validation, report.

  The agent maps the system, audits functional completeness, reviews
  architecture and code quality, examines infrastructure and security,
  validates with E2E flows and dogfooding, and produces a consolidated
  findings report with severity-ranked remediation plan.

  When --scope is provided, the review focuses exclusively on the specified
  module, feature, or subsystem. Only components, flows, and code related
  to the scope are analyzed. This produces a targeted, deeper review of
  that specific area rather than a broad system-wide audit.

MODES:
  full           Complete 8-phase deep review (default).
  quick          Fast review focused on code quality (phases 1,2,3,4,8).
  security       Security-focused audit (phases 1,5,6,8).
  architecture   Architecture-focused review (phases 1,2,3,8).

PHASES:
  1. Baseline       Map architecture, domains, flows, dependencies
  2. Completeness   Functional audit: promised vs implemented, dead code, gaps
  3. Architecture   Coupling, cohesion, cycles, patterns, responsibilities
  4. Code           Deep review: error handling, concurrency, contracts
  5. Infrastructure CI/CD, containers, IaC, data, persistence, supply chain
  6. Security       OWASP Top 10, threat modeling, identity, toxic combinations
  7. Validation     E2E flows, test quality, observability, dogfooding
  8. Report         Consolidation: findings, risk matrix, remediation plan

EXAMPLES:
  /review-loop ~/projects/my-app
  /review-loop ~/projects/my-api --mode security
  /review-loop ~/projects/my-service --mode quick --max-iterations 40
  /review-loop ~/projects/my-platform --severity-threshold high --output-dir ./audit
  /review-loop ~/projects/my-app --scope "login and authentication"
  /review-loop ~/projects/my-app --scope "payment module" --mode security
  /review-loop ~/projects/my-app --scope "kafka cluster configuration"

OUTPUT:
  review-output/
  ├── review.db                    SQLite database (source of truth)
  ├── baseline/
  │   ├── architecture_map.md
  │   ├── component_inventory.md
  │   ├── flow_diagrams.md
  │   └── risk_hypotheses.md
  ├── findings/
  │   ├── completeness/
  │   ├── architecture/
  │   ├── code/
  │   ├── infrastructure/
  │   ├── security/
  │   └── validation/
  ├── analysis/
  │   ├── threat_models/
  │   ├── dependency_graph.md
  │   └── invariants.md
  ├── state/
  │   └── meetings/
  └── figures/
HELP_EOF
      exit 0
      ;;
    --mode)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --mode requires an argument (full|quick|security|architecture)" >&2
        exit 1
      fi
      case "$2" in
        full|quick|security|architecture)
          MODE="$2"
          ;;
        *)
          echo "Error: --mode must be one of: full, quick, security, architecture (got: '$2')" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations requires a positive integer (got: '${2:-}')" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --output-dir)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --output-dir requires a path argument" >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --severity-threshold)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --severity-threshold requires an argument (critical|high|medium|low)" >&2
        exit 1
      fi
      case "$2" in
        critical|high|medium|low)
          SEVERITY_THRESHOLD="$2"
          ;;
        *)
          echo "Error: --severity-threshold must be one of: critical, high, medium, low (got: '$2')" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --completion-promise requires a text argument" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    --scope)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --scope requires a description of the module/feature to review" >&2
        echo "" >&2
        echo "   Examples:" >&2
        echo "     --scope 'login and authentication'" >&2
        echo "     --scope 'payment module'" >&2
        echo "     --scope 'kafka cluster'" >&2
        exit 1
      fi
      SCOPE="$2"
      shift 2
      ;;
    *)
      TARGET_PARTS+=("$1")
      shift
      ;;
  esac
done

TARGET="${TARGET_PARTS[*]}"

if [[ -z "$TARGET" ]]; then
  echo "Error: No target codebase path provided" >&2
  echo "" >&2
  echo "   Examples:" >&2
  echo "     /review-loop ~/projects/my-app" >&2
  echo "     /review-loop ~/projects/my-api --mode security" >&2
  echo "" >&2
  echo "   For all options: /review-loop --help" >&2
  exit 1
fi

# Resolve target path
TARGET_PATH="$(cd "$TARGET" 2>/dev/null && pwd)" || {
  echo "Error: Target path does not exist: $TARGET" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Resolve prompt template
# ---------------------------------------------------------------------------
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TEMPLATE="$PLUGIN_ROOT/templates/review-prompt.md"

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Error: Review prompt template not found at $PROMPT_TEMPLATE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build scope section (injected into prompt when --scope is provided)
# ---------------------------------------------------------------------------
SCOPE_SECTION=""
if [[ -n "$SCOPE" ]]; then
  SCOPE_SECTION=$(cat <<'SCOPE_EOF'
---

## SCOPED REVIEW — Focused Analysis

> **Scope: {{SCOPE_VALUE}}**

This review is **scoped** to a specific module, feature, or subsystem. All phases, agents, and analysis MUST focus exclusively on the specified scope.

### Scoped Review Rules

1. **Phase 1 (Baseline):** Map ONLY the components, flows, and dependencies that are part of or directly interact with the scoped area. Identify the scope boundary — what is inside vs outside. Still register components and flows in the DB, but only those relevant to the scope.

2. **Phases 2-7:** Analyze ONLY code, architecture, infrastructure, and security within the scope boundary. Findings outside the scope should only be registered if they directly impact the scoped area (e.g., a shared dependency with a vulnerability).

3. **Phase 8 (Report):** The final report covers only the scoped area. Title it clearly: "Deep Review: {{SCOPE_VALUE}}".

### How to Identify Scope Boundaries

- Search the codebase for files, directories, modules, classes, and functions related to the scope description
- Use keywords, naming conventions, and import graphs to identify what belongs to the scope
- Map the scope's external dependencies (what it calls) and dependents (what calls it)
- Document the scope boundary explicitly in `baseline/architecture_map.md`

### What "Scoped" Means in Practice

- If the scope is "login" → review auth controllers, auth services, session management, token handling, login UI, auth middleware, and their tests
- If the scope is "payment module" → review payment controllers, payment services, billing logic, payment gateway integrations, transaction handling, and their tests
- If the scope is "kafka cluster" → review Kafka producers, consumers, topic configurations, serialization, error handling, retry logic, and their tests
- Components outside the scope are noted as "external dependency" but not deeply reviewed

### Scope Context for Agents

When launching specialist agents, always include this context:
> "This is a SCOPED review focused on: **{{SCOPE_VALUE}}**. Only analyze code, architecture, and flows related to this scope. Flag external dependencies but do not deep-review them."
SCOPE_EOF
)
  SCOPE_SECTION=$(echo "$SCOPE_SECTION" | sed "s|{{SCOPE_VALUE}}|$SCOPE|g")
fi

# ---------------------------------------------------------------------------
# Replace placeholders in template
# ---------------------------------------------------------------------------
REVIEW_PROMPT=$(sed \
  -e "s|{{TARGET_PATH}}|$TARGET_PATH|g" \
  -e "s|{{OUTPUT_DIR}}|$OUTPUT_DIR|g" \
  -e "s|{{COMPLETION_PROMISE}}|$COMPLETION_PROMISE|g" \
  -e "s|{{PLUGIN_ROOT}}|$PLUGIN_ROOT|g" \
  -e "s|{{MODE}}|$MODE|g" \
  -e "s|{{SEVERITY_THRESHOLD}}|$SEVERITY_THRESHOLD|g" \
  "$PROMPT_TEMPLATE")

# Inject scope section (multi-line, cannot use sed -e for this)
if [[ -n "$SCOPE_SECTION" ]]; then
  REVIEW_PROMPT="${REVIEW_PROMPT//\{\{SCOPE_SECTION\}\}/$SCOPE_SECTION}"
else
  REVIEW_PROMPT="${REVIEW_PROMPT//\{\{SCOPE_SECTION\}\}/}"
fi

# ---------------------------------------------------------------------------
# Create output directory structure
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/baseline"
mkdir -p "$OUTPUT_DIR/findings/completeness"
mkdir -p "$OUTPUT_DIR/findings/architecture"
mkdir -p "$OUTPUT_DIR/findings/code"
mkdir -p "$OUTPUT_DIR/findings/infrastructure"
mkdir -p "$OUTPUT_DIR/findings/security"
mkdir -p "$OUTPUT_DIR/findings/validation"
mkdir -p "$OUTPUT_DIR/analysis/threat_models"
mkdir -p "$OUTPUT_DIR/state/meetings"
mkdir -p "$OUTPUT_DIR/figures"

# ---------------------------------------------------------------------------
# Initialize SQLite database
# ---------------------------------------------------------------------------
if [[ ! -f "$OUTPUT_DIR/review.db" ]]; then
  python3 "$PLUGIN_ROOT/scripts/review_database.py" init --db-path "$OUTPUT_DIR/review.db" > /dev/null
fi

# ---------------------------------------------------------------------------
# Create state file
# ---------------------------------------------------------------------------
mkdir -p .claude

cat > .claude/review-loop.local.md <<EOF
---
active: true
target: "$TARGET_PATH"
scope: "$SCOPE"
current_phase: 1
phase_name: "baseline"
phase_iteration: 1
global_iteration: 1
max_global_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
output_dir: "$OUTPUT_DIR"
mode: "$MODE"
severity_threshold: "$SEVERITY_THRESHOLD"
review_cycles: 0
max_review_cycles: 2
components_mapped: 0
flows_mapped: 0
findings_total: 0
findings_critical: 0
findings_high: 0
---

$REVIEW_PROMPT
EOF

# ---------------------------------------------------------------------------
# Output setup message
# ---------------------------------------------------------------------------
MODE_LABEL=""
case "$MODE" in
  full)          MODE_LABEL="Full (complete 8-phase deep review)" ;;
  quick)         MODE_LABEL="Quick (code quality focus: phases 1,2,3,4,8)" ;;
  security)      MODE_LABEL="Security (security audit: phases 1,5,6,8)" ;;
  architecture)  MODE_LABEL="Architecture (architecture focus: phases 1,2,3,8)" ;;
esac

cat <<EOF
Review Deep Loop activated!

Mode: $MODE_LABEL
Target: $TARGET_PATH
$(if [[ -n "$SCOPE" ]]; then echo "Scope: $SCOPE"; fi)
Severity threshold: $SEVERITY_THRESHOLD
Output: $OUTPUT_DIR/
Max iterations: $MAX_ITERATIONS
Completion promise: $COMPLETION_PROMISE

Pipeline phases:
  1. Baseline       -- Map architecture, domains, flows, dependencies
  2. Completeness   -- Functional audit: promised vs implemented, gaps
  3. Architecture   -- Coupling, cohesion, cycles, patterns
  4. Code           -- Deep review: error handling, concurrency, contracts
  5. Infrastructure -- CI/CD, containers, IaC, data, supply chain
  6. Security       -- OWASP, threat modeling, identity, toxic combinations
  7. Validation     -- E2E flows, test quality, observability, dogfooding
  8. Report         -- Consolidation: findings, risk matrix, remediation plan

State: .claude/review-loop.local.md
Monitor: grep 'current_phase\|global_iteration\|findings_' .claude/review-loop.local.md

EOF

echo "==============================================================="
echo "CRITICAL -- Completion Promise"
echo "==============================================================="
echo ""
echo "To complete the review, output this EXACT text:"
echo "  <promise>$COMPLETION_PROMISE</promise>"
echo ""
echo "ONLY output this when the deep review is GENUINELY complete."
echo "Do NOT output false promises to exit the loop."
echo "==============================================================="
echo ""
echo "Starting Phase 1: Baseline..."
echo ""
echo "$REVIEW_PROMPT"
