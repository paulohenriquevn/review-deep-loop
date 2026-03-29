---
description: "View current deep review loop status"
allowed-tools: ["Bash(test -f .claude/review-loop.local.md:*)", "Read(.claude/review-loop.local.md)", "Bash(ls:*)", "Bash(wc:*)", "Bash(cat:*)", "Bash(python3:*)"]
hide-from-slash-command-tool: "true"
---

# Review Deep Loop Status

Check and display the current deep review loop status:

1. Check if `.claude/review-loop.local.md` exists: `test -f .claude/review-loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active deep review loop."

3. **If EXISTS**:
   - Read `.claude/review-loop.local.md` to get all state fields
   - Check the output directory for generated files
   - **Query the database** for authoritative finding counts (state file counters may lag):
     ```bash
     python3 <PLUGIN_ROOT>/scripts/review_database.py stats --db-path <OUTPUT_DIR>/review.db
     ```
   - Display a formatted status report:

```
Deep Review Loop Status
=======================
Target:           [target]
Scope:            [scope or "entire codebase"]
Mode:             [mode]
Severity threshold: [severity_threshold]
Phase:            [N]/8 -- [phase_name]
Phase iteration:  [phase_iteration]
Global iteration: [global_iteration]/[max_global_iterations]
Started:          [started_at]

Metrics (from database):
  Components mapped:  [components from DB stats]
  Flows mapped:       [flows from DB stats]
  Findings total:     [findings from DB stats]
  Findings by severity: critical=[N] high=[N] medium=[N] low=[N]
  Threat models:      [threat_models from DB stats]
  Evidence records:   [evidence from DB stats]
  Quality scores:     [quality_scores from DB stats]

Review cycles: [review_cycles]/[max_review_cycles]

Output directory: [output_dir]
  baseline/              [N files]
  findings/completeness/ [N files]
  findings/architecture/ [N files]
  findings/code/         [N files]
  findings/infrastructure/ [N files]
  findings/security/     [N files]
  findings/validation/   [N files]
  analysis/threat_models/ [N files]
  figures/               [N files]
  review.db:             [exists/missing]
```
