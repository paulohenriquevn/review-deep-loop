---
description: "Cancel active deep review loop"
allowed-tools: ["Bash(test -f .claude/review-loop.local.md:*)", "Bash(rm .claude/review-loop.local.md)", "Read(.claude/review-loop.local.md)"]
hide-from-slash-command-tool: "true"
---

# Cancel Deep Review Loop

To cancel the deep review loop:

1. Check if `.claude/review-loop.local.md` exists using Bash: `test -f .claude/review-loop.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active deep review loop found."

3. **If EXISTS**:
   - Read `.claude/review-loop.local.md` to get current state (phase, iteration, target, findings)
   - Remove the file using Bash: `rm .claude/review-loop.local.md`
   - Report: "Cancelled deep review loop for target '[TARGET]' (was at phase N/8: PHASE_NAME, global iteration M). Findings: total=X, critical=Y, high=Z. Output preserved in OUTPUT_DIR."
