# Review Deep Loop

Autonomous deep software review laboratory for Claude Code. Give it a codebase, and it performs a systematic 8-phase audit covering architecture, completeness, code quality, infrastructure, security, and operational validation — producing a ranked findings report with evidence-backed remediation plan.

Combines four ideas:
- **[Ralph Wiggum](https://ghuntley.com/ralph/)** — self-referential AI loop via stop hook
- **[Autoresearch](https://github.com/karpathy/autoresearch)** (Karpathy) — autonomous experimentation: evaluate, keep/discard
- **Deep review methodology** — 12-dimension systemic audit with evidence at every layer
- **C4 framework** — Correto, Completo, Confiavel, Controlavel

## Installation

### Step 1: Add the marketplace

```
/plugin marketplace add paulohenriquevn/review-deep-loop
```

### Step 2: Install the plugin

```
/plugin install review-deep-loop@review-deep-loop
```

### Step 3: Reload plugins

```
/reload-plugins
```

## Quick Start

```bash
# Full review (default) — all 8 phases
/review-loop ~/projects/my-app

# Quick review — focus on code quality
/review-loop ~/projects/my-app --mode quick

# Security-focused review
/review-loop ~/projects/my-app --mode security

# Architecture-focused review
/review-loop ~/projects/my-app --mode architecture

# Scoped review — focus on a specific module or feature
/review-loop ~/projects/my-app --scope "login and authentication"
/review-loop ~/projects/my-app --scope "payment module" --mode security
/review-loop ~/projects/my-app --scope "kafka cluster configuration"

# Custom settings
/review-loop ~/projects/my-app --max-iterations 100 --severity-threshold high
```

## How It Works

```
/review-loop ~/projects/my-app
     |
     v
+--------------------------------------------------------------+
|  Phase 1: Baseline       (max 3 iter)                         |
|  Map architecture, domains, flows, dependencies, risk         |
+--------------------------------------------------------------+
|  Phase 2: Completeness   (max 3 iter)                         |
|  Functional audit: promised vs implemented, dead code, gaps   |
+--------------------------------------------------------------+
|  Phase 3: Architecture   (max 3 iter)                         |
|  Coupling, cohesion, cycles, patterns, responsibilities       |
+--------------------------------------------------------------+
|  Phase 4: Code           (max 4 iter)                         |
|  Deep review: error handling, concurrency, contracts          |
+--------------------------------------------------------------+
|  Phase 5: Infrastructure (max 3 iter)                         |
|  CI/CD, containers, IaC, data, persistence, supply chain      |
+--------------------------------------------------------------+
|  Phase 6: Security       (max 3 iter)                         |
|  OWASP Top 10, threat modeling, identity, toxic combinations  |
+--------------------------------------------------------------+
|  Phase 7: Validation     (max 3 iter)                         |
|  E2E flows, test quality, observability, dogfooding           |
+--------------------------------------------------------------+
|  Phase 8: Report         (max 2 iter)                         |
|  Consolidation: findings, risk matrix, remediation plan       |
+--------------------------------------------------------------+
     |                           ^
     |    +----------------------+
     |    | Loop-back (max 2 cycles)
     |    | When Phase 7 dogfooding
     |    | reveals gaps missed in
     v    | static review phases
```

## Review Modes

| Mode | Description | Phases |
|------|-------------|--------|
| **full** | Complete 8-phase deep review (default) | 1-8 |
| **quick** | Fast review focused on code quality | 1, 2, 3, 4, 8 |
| **security** | Security-focused audit | 1, 5, 6, 8 |
| **architecture** | Architecture-focused review | 1, 2, 3, 8 |

## The C4 Framework

Every finding is evaluated against four dimensions:

- **Correto** — Does the system do what it promises?
- **Completo** — Is anything missing?
- **Confiavel** — Does it fail well and recover?
- **Controlavel** — Is it observable, operable, and secure?

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
- `--scope <description>` — Focus review on a specific module/feature (e.g., "login", "payment module", "kafka cluster")
- `--mode <full|quick|security|architecture>` — Review mode (default: full)
- `--max-iterations <n>` — Max global iterations (default: 80)
- `--output-dir <path>` — Output directory (default: ./review-output)
- `--severity-threshold <critical|high|medium|low>` — Min severity to report (default: low)
- `--completion-promise <text>` — Custom promise (default: "DEEP REVIEW COMPLETE")

### /review-status

View current review loop status.

### /review-cancel

Cancel an active review loop. Output files are preserved.

### /review-help

Show help and available commands.

## Output Structure

```
review-output/
+-- review.db                      SQLite database (source of truth)
+-- baseline/
|   +-- architecture_map.md        Architecture map
|   +-- component_inventory.md     Component inventory
|   +-- flow_diagrams.md           Data and control flows
|   +-- risk_hypotheses.md         Initial risk hypotheses
+-- findings/
|   +-- completeness/              Completeness findings
|   +-- architecture/              Architecture findings
|   +-- code/                      Code findings
|   +-- infrastructure/            Infrastructure findings
|   +-- security/                  Security findings
|   +-- validation/                Validation findings
+-- analysis/
|   +-- threat_models/             Threat models per flow
|   +-- dependency_graph.md        Dependency graph
|   +-- invariants.md              System invariants
+-- state/
|   +-- meetings/                  Meeting minutes
+-- figures/
    +-- risk_matrix.svg            Risk matrix
    +-- findings_by_severity.svg   Findings by severity
    +-- dependency_graph.svg       Dependency graph
```

## Database

The plugin uses a SQLite database (`review.db`) as the source of truth, managed via `review_database.py`. It stores:
- System components with metadata and relationships
- Critical business flows with status
- Review findings with severity, evidence, and category
- Evidence records linked to findings
- System invariants and validation status
- Threat models per flow with controls and gaps
- Quality gate scores per phase
- Agent coordination messages

## Agents

| Role | Agent | Specialty |
|------|-------|-----------|
| **Chief Reviewer** | `chief-reviewer` | Leads meetings, strategic decisions, task assignment |
| **Architecture Analyst** | `architecture-analyst` | Architecture patterns, coupling, cohesion |
| **Code Reviewer** | `code-reviewer` | Deep code review, error handling, concurrency |
| **Completeness Auditor** | `completeness-auditor` | Functional completeness, dead code, stubs |
| **Security Auditor** | `security-auditor` | OWASP, SAST, secrets, vulnerabilities |
| **Infrastructure Reviewer** | `infrastructure-reviewer` | Containers, orchestration, IaC, runtime |
| **Data Reviewer** | `data-reviewer` | Database, migrations, transactions, consistency |
| **CI/CD Reviewer** | `cicd-reviewer` | Pipelines, supply chain, artifacts, reproducibility |
| **Flow Tracer** | `flow-tracer` | End-to-end flow analysis, sequence diagrams |
| **Observability Reviewer** | `observability-reviewer` | Logs, metrics, traces, alerts |
| **Test Auditor** | `test-auditor` | Test quality, coverage gaps, flaky tests |
| **Threat Modeler** | `threat-modeler` | Threat modeling per flow, attack surface |
| **Dogfood Tester** | `dogfood-tester` | Operational validation, failure simulation |
| **Dependency Analyzer** | `dependency-analyzer` | Dependency graph, cycles, SCA, licenses |
| **Quality Evaluator** | `quality-evaluator` | Quality gates (keep/discard pattern) |
| **Report Writer** | `report-writer` | Final consolidation report |
