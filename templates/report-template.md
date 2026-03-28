# Deep Review Report — {{TARGET_PATH}}

## Executive Summary

[2-3 paragraph summary: system reviewed, methodology used, key findings count by severity, most critical issues found, overall system health assessment using C4 framework (Correto, Completo, Confiavel, Controlavel).]

**Overall Health Score:** [0-100] — [critical/poor/fair/good/excellent]

| Dimension | Score | Assessment |
|-----------|-------|------------|
| Correto | [0-100] | [Does the system do what it promises?] |
| Completo | [0-100] | [Is anything missing?] |
| Confiavel | [0-100] | [Does it fail well and recover?] |
| Controlavel | [0-100] | [Is it observable, operable, and secure?] |

---

## 1. System Overview

### 1.1 Architecture Map
[High-level architecture as discovered during baseline phase.]

### 1.2 Component Inventory

| Component | Type | Technology | Path | Dependencies |
|-----------|------|------------|------|-------------|
| ... | service/module/worker | ... | ... | ... |

### 1.3 Critical Flows

| Flow | Type | Components | Criticality | Status |
|------|------|-----------|-------------|--------|
| ... | user_facing/internal/deployment | ... | critical/high/medium | reviewed/validated |

### 1.4 Dependency Matrix
[Component dependency relationships and coupling analysis.]

---

## 2. Findings Summary

### 2.1 By Severity

| Severity | Count | Examples |
|----------|-------|---------|
| Critical | N | [Brief list] |
| High | N | [Brief list] |
| Medium | N | [Brief list] |
| Low | N | [Brief list] |

### 2.2 By Category

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Completeness | ... | ... | ... | ... | ... |
| Architecture | ... | ... | ... | ... | ... |
| Code | ... | ... | ... | ... | ... |
| Infrastructure | ... | ... | ... | ... | ... |
| Security | ... | ... | ... | ... | ... |
| Data | ... | ... | ... | ... | ... |
| Observability | ... | ... | ... | ... | ... |
| Testing | ... | ... | ... | ... | ... |
| Operational | ... | ... | ... | ... | ... |

### 2.3 By C4 Dimension

| Dimension | Critical | High | Medium | Low |
|-----------|----------|------|--------|-----|
| Correto | ... | ... | ... | ... |
| Completo | ... | ... | ... | ... |
| Confiavel | ... | ... | ... | ... |
| Controlavel | ... | ... | ... | ... |

![Findings by Severity](figures/findings_by_severity.svg)

---

## 3. Critical Findings

[For each critical finding, full detail:]

### 3.1 [Finding Title]

| Field | Value |
|-------|-------|
| **ID** | [finding_id] |
| **Severity** | Critical |
| **Category** | [category] |
| **C4 Dimension** | [correto/completo/confiavel/controlavel] |
| **Component** | [affected component] |
| **File** | [file_path:line_range] |

**Description:** [Detailed description of the issue]

**Evidence:**
```
[Code snippet, log entry, or configuration fragment]
```

**Root Cause:** [Why this issue exists]

**Impact:** [What happens if not fixed — be specific]

**Recommendation:** [How to fix — be actionable]

**Effort:** [low/medium/high]

---

## 4. High-Severity Findings

[Same format as critical, for each high-severity finding]

---

## 5. Medium & Low Findings

[Summary table with brief descriptions]

| ID | Title | Severity | Category | Component | Effort |
|----|-------|----------|----------|-----------|--------|
| ... | ... | medium/low | ... | ... | ... |

---

## 6. Architecture Assessment

### 6.1 Strengths
[What the architecture does well]

### 6.2 Weaknesses
[Structural problems found]

### 6.3 Coupling Analysis
[Where coupling is problematic]

### 6.4 Pattern Usage
[Patterns found — used correctly or incorrectly]

---

## 7. Security Assessment

### 7.1 Threat Model Summary

| Flow | Top Threat | Likelihood | Impact | Controls | Gaps |
|------|-----------|------------|--------|----------|------|
| ... | ... | ... | ... | ... | ... |

### 7.2 Toxic Combinations
[Findings that combine to create worse-than-individual risk]

### 7.3 Attack Surface
[Summary of exposed attack surface]

---

## 8. Operational Readiness

### 8.1 Observability
[Logs, metrics, traces assessment]

### 8.2 Failure Modes
[How the system fails and recovers]

### 8.3 Operational Gaps
[What's missing for production operation]

---

## 9. Test Quality Assessment

### 9.1 Coverage Analysis

| Area | Unit | Integration | E2E | Gaps |
|------|------|-------------|-----|------|
| ... | ... | ... | ... | ... |

### 9.2 Test Health
[Flaky tests, slow tests, missing tests]

---

## 10. Risk Matrix

| Risk | Severity | Probability | Impact | Detectability | Priority |
|------|----------|------------|--------|---------------|----------|
| ... | ... | high/medium/low | ... | ... | P1/P2/P3/P4 |

![Risk Matrix](figures/risk_matrix.svg)

---

## 11. Remediation Plan

### 11.1 Immediate Actions (P1 — this sprint)
[Critical findings that need immediate attention]

| # | Finding | Action | Owner | Effort |
|---|---------|--------|-------|--------|
| 1 | ... | ... | ... | ... |

### 11.2 Short-Term (P2 — next 2-4 weeks)
[High findings]

### 11.3 Medium-Term (P3 — next quarter)
[Medium findings with structural impact]

### 11.4 Long-Term (P4 — backlog)
[Low findings and improvements]

### 11.5 Definition of Done per Category
[Criteria for considering each category of finding resolved]

---

## 12. Invariants Defined

| Invariant | Category | Status | Evidence |
|-----------|----------|--------|----------|
| ... | data/security/operational/business | validated/violated/untested | ... |

---

## Appendix

### A. Methodology
[How the review was conducted: phases, tools used, time spent per phase]

### B. Evidence Catalog
[Full list of evidence collected, referenced by finding ID]

### C. Tools and Techniques Used
[Static analysis, dependency scanning, manual review areas]

### D. Database Reference
[How to query review.db for detailed findings]

### E. Glossary
[Terms used in this report]
