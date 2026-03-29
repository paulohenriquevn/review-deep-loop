---
description: "Explain deep review loop and available commands"
---

# Deep Review Loop Help

Please explain the following to the user:

## What is the Review Deep Loop?

A Claude Code plugin that runs an autonomous deep software review pipeline using the Ralph Wiggum loop technique. You give it a codebase, and it iterates through 8 phases -- mapping the system, auditing completeness, reviewing architecture and code, examining infrastructure and security, validating with E2E flows and dogfooding, and producing a consolidated findings report with severity-ranked remediation plan.

**Inspired by:**
- **Ralph Wiggum** (Geoffrey Huntley) -- self-referential AI loop mechanism
- **Autoresearch** (Andrej Karpathy) -- autonomous AI experimentation pattern
- **Deep review methodology** -- 12-dimension systemic audit with evidence at every layer
- **C4 framework** -- Correto, Completo, Confiavel, Controlavel

## The C4 Framework

Every finding is evaluated against four dimensions:

| Dimension | Question |
|-----------|----------|
| **Correto** | Does the system do what it promises? |
| **Completo** | Is anything missing? |
| **Confiavel** | Does it fail well and recover? |
| **Controlavel** | Is it observable, operable, and secure? |

## The 8 Phases

| Phase | Name | What happens | Max iterations |
|-------|------|-------------|---------------|
| 1 | Baseline | Map architecture, domains, flows, dependencies | 3 |
| 2 | Completeness | Functional audit: promised vs implemented, dead code, gaps | 3 |
| 3 | Architecture | Coupling, cohesion, cycles, patterns, responsibilities | 3 |
| 4 | Code | Deep review: error handling, concurrency, contracts | 4 |
| 5 | Infrastructure | CI/CD, containers, IaC, data, supply chain | 3 |
| 6 | Security | OWASP Top 10, threat modeling, identity, toxic combinations | 3 |
| 7 | Validation | E2E flows, test quality, observability, dogfooding | 3 |
| 8 | Report | Consolidation: findings, risk matrix, remediation plan | 2 |

## Review Modes

| Mode | Description |
|------|-------------|
| **full** | Complete 8-phase deep review (default) |
| **quick** | Fast review focused on code quality (phases 1,2,3,4,8) |
| **security** | Security-focused audit (phases 1,5,6,8) |
| **architecture** | Architecture-focused review (phases 1,2,3,8) |

## Finding Severity

| Level | Description |
|-------|-------------|
| **Critical** | Compromises security, data, isolation, billing, availability |
| **High** | Compromises operation, integrity, rollback, recovery |
| **Medium** | Degrades maintenance, clarity, observability |
| **Low** | Structural improvement or hygiene |

## Available Commands

### /review-loop TARGET [OPTIONS]

Start a deep review loop.

```
/review-loop ~/projects/my-app
/review-loop ~/projects/my-api --mode security
/review-loop ~/projects/my-service --mode quick --max-iterations 40
/review-loop ~/projects/my-platform --severity-threshold high
/review-loop ~/projects/my-app --scope "login and authentication"
/review-loop ~/projects/my-app --scope "payment module" --mode security
```

**Options:**
- `--scope <description>` -- Focus review on a specific module/feature (e.g., "login", "payment module", "kafka cluster")
- `--mode <full|quick|security|architecture>` -- Review mode (default: full)
- `--max-iterations <n>` -- Max global iterations (default: 80)
- `--output-dir <path>` -- Output directory (default: ./review-output)
- `--severity-threshold <critical|high|medium|low>` -- Min severity to report (default: low)
- `--completion-promise <text>` -- Custom promise (default: "DEEP REVIEW COMPLETE")

### /review-status

View current review loop status: phase, iteration, finding counts, output files.

### /review-cancel

Cancel an active review loop. Output files are preserved.

## Output Structure

```
review-output/
├── review.db                      -- SQLite database (source of truth)
├── baseline/                      -- Architecture maps, component inventory
├── findings/                      -- Findings organized by category
│   ├── completeness/
│   ├── architecture/
│   ├── code/
│   ├── infrastructure/
│   ├── security/
│   └── validation/
├── analysis/                      -- Threat models, dependency graph, invariants
├── state/meetings/                -- Meeting minutes per iteration
└── figures/                       -- Generated visualizations
```

## How It Works

1. The stop hook intercepts Claude's exit after each iteration
2. Claude reads the state file to know its current phase
3. Each iteration advances the review within the current phase
4. Phase completion markers (`<!-- PHASE_N_COMPLETE -->`) trigger phase transitions
5. Quality gates enforce evidence requirements before advancing (phases 2-7)
6. Hard blocks require database evidence (findings, components, threat models)
7. If a phase exceeds its iteration limit, it forces advancement
8. The loop ends when Claude outputs `<promise>DEEP REVIEW COMPLETE</promise>`

## Database

The plugin uses a SQLite database (`review.db`) as the source of truth, managed via `review_database.py`. It stores:
- System components with metadata and relationships
- Critical business flows
- Review findings with severity, evidence, and category
- Evidence records linked to findings
- System invariants and validation status
- Threat models per flow
- Quality gate scores
- Agent coordination messages
