---
description: "View current deep review loop status"
allowed-tools: ["Bash(test -f .claude/review-loop.local.md:*)", "Read(.claude/review-loop.local.md)", "Bash(ls:*)", "Bash(wc:*)", "Bash(cat:*)"]
hide-from-slash-command-tool: "true"
---

# Review Deep Loop Status

Check and display the current deep review loop status:

1. Check if `.claude/review-loop.local.md` exists: `test -f .claude/review-loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active deep review loop."

3. **If EXISTS**:
   - Read `.claude/review-loop.local.md` to get all state fields
   - Check the output directory for generated files
   - Display a formatted status report:

```
Deep Review Loop Status
=======================
Target:           [target]
Mode:             [mode]
Severity threshold: [severity_threshold]
Phase:            [N]/8 -- [phase_name]
Phase iteration:  [phase_iteration]
Global iteration: [global_iteration]/[max_global_iterations]
Started:          [started_at]

Metrics:
  Components mapped:  [components_mapped]
  Flows mapped:       [flows_mapped]
  Findings total:     [findings_total]
  Findings critical:  [findings_critical]
  Findings high:      [findings_high]

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

Quality gate history:
  [List QUALITY_SCORE and QUALITY_PASSED from state file]
```
