#!/usr/bin/env python3
"""
SQLite database for the Review Deep Loop plugin.

Stores components, flows, findings, evidence, invariants,
threat models, quality scores, and agent messages.

Usage:
    python3 review_database.py init --db-path review.db
    python3 review_database.py add-component --db-path review.db --component-json '{...}'
    python3 review_database.py add-flow --db-path review.db --flow-json '{...}'
    python3 review_database.py add-finding --db-path review.db --finding-json '{...}'
    python3 review_database.py add-evidence --db-path review.db --evidence-json '{...}'
    python3 review_database.py add-invariant --db-path review.db --invariant-json '{...}'
    python3 review_database.py add-threat --db-path review.db --threat-json '{...}'
    python3 review_database.py add-quality-score --db-path review.db --phase N --score 0.85 --details '{...}'
    python3 review_database.py add-message --db-path review.db --from-agent NAME --phase N --content "..."
    python3 review_database.py query-components --db-path review.db [--component-type service]
    python3 review_database.py query-flows --db-path review.db [--status mapped]
    python3 review_database.py query-findings --db-path review.db [--severity critical] [--phase N] [--category security]
    python3 review_database.py query-threats --db-path review.db [--flow-id ID]
    python3 review_database.py query-messages --db-path review.db --phase N
    python3 review_database.py update-finding --db-path review.db --finding-id ID --updates-json '{...}'
    python3 review_database.py update-invariant --db-path review.db --invariant-id ID --updates-json '{...}'
    python3 review_database.py stats --db-path review.db
"""

from __future__ import annotations

import argparse
import contextlib
import json
import sqlite3
import sys
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Valid enum values for validation at system boundaries
# ---------------------------------------------------------------------------
VALID_COMPONENT_TYPES = {
    "service", "module", "worker", "job", "queue", "database", "cache",
    "gateway", "proxy", "library", "cli", "ui", "config", "other",
}
VALID_FLOW_STATUSES = {"identified", "mapped", "reviewed", "validated"}
VALID_SEVERITIES = {"critical", "high", "medium", "low"}
VALID_FINDING_CATEGORIES = {
    "completeness", "architecture", "code", "infrastructure",
    "security", "data", "observability", "testing", "operational",
}
VALID_FINDING_STATUSES = {
    "open", "confirmed", "false_positive", "wont_fix", "remediated",
}
VALID_EVIDENCE_TYPES = {
    "code_snippet", "log_entry", "config_fragment", "test_result",
    "metric", "trace", "screenshot", "manifest", "pipeline",
    "query_result", "dependency", "other",
}
VALID_INVARIANT_STATUSES = {"defined", "validated", "violated", "untested"}
VALID_THREAT_LIKELIHOODS = {"high", "medium", "low"}
VALID_THREAT_IMPACTS = {"critical", "high", "medium", "low"}
VALID_MESSAGE_TYPES = {
    "finding", "instruction", "feedback", "question",
    "decision", "meeting_minutes",
}

SCHEMA_VERSION = 1

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS components (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    component_type TEXT NOT NULL,          -- "service" | "module" | "worker" | "job" | "queue" | "database" | ...
    description TEXT NOT NULL,
    path TEXT,                             -- file path or directory in the codebase
    technology TEXT,                       -- "python", "go", "postgresql", "redis", etc.
    dependencies TEXT,                     -- JSON array of component IDs this depends on
    api_surface TEXT,                      -- JSON: endpoints, interfaces, or contracts exposed
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS flows (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    flow_type TEXT,                        -- "user_facing" | "internal" | "background" | "deployment"
    components TEXT NOT NULL,              -- JSON array of component IDs involved
    steps TEXT,                            -- JSON array of ordered steps
    entry_point TEXT,                      -- where the flow starts (endpoint, trigger, etc.)
    exit_point TEXT,                       -- where the flow ends
    status TEXT NOT NULL DEFAULT 'identified',  -- "identified" | "mapped" | "reviewed" | "validated"
    criticality TEXT,                      -- "critical" | "high" | "medium" | "low"
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS findings (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    severity TEXT NOT NULL,                -- "critical" | "high" | "medium" | "low"
    category TEXT NOT NULL,               -- "completeness" | "architecture" | "code" | "infrastructure" | "security" | ...
    phase INTEGER NOT NULL,               -- phase number where finding was discovered (1-8)
    component_id TEXT REFERENCES components(id),
    flow_id TEXT REFERENCES flows(id),
    file_path TEXT,                        -- specific file where issue was found
    line_range TEXT,                       -- "100-120" or "45"
    code_snippet TEXT,                     -- relevant code fragment
    root_cause TEXT,                       -- why the issue exists
    impact TEXT,                           -- what happens if not fixed
    recommendation TEXT,                   -- how to fix
    effort TEXT,                           -- "low" | "medium" | "high"
    status TEXT NOT NULL DEFAULT 'open',   -- "open" | "confirmed" | "false_positive" | "wont_fix" | "remediated"
    c4_dimension TEXT,                     -- "correto" | "completo" | "confiavel" | "controlavel"
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS evidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    finding_id TEXT NOT NULL REFERENCES findings(id),
    evidence_type TEXT NOT NULL,           -- "code_snippet" | "log_entry" | "config_fragment" | "test_result" | ...
    source TEXT NOT NULL,                  -- file path, URL, or description of where evidence comes from
    content TEXT NOT NULL,                 -- the actual evidence content
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS invariants (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT,                         -- "data" | "security" | "operational" | "business"
    assertion TEXT NOT NULL,               -- formal statement of what should be true
    validation_method TEXT,                -- how to verify this invariant
    status TEXT NOT NULL DEFAULT 'defined', -- "defined" | "validated" | "violated" | "untested"
    violation_evidence TEXT,               -- if violated, what evidence was found
    component_ids TEXT,                    -- JSON array of related component IDs
    flow_ids TEXT,                         -- JSON array of related flow IDs
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS threat_models (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    flow_id TEXT NOT NULL REFERENCES flows(id),
    threat TEXT NOT NULL,                  -- description of the threat
    attacker TEXT,                         -- who could exploit this
    attack_vector TEXT,                    -- how they would exploit it
    asset TEXT,                            -- what is being protected
    likelihood TEXT NOT NULL,              -- "high" | "medium" | "low"
    impact TEXT NOT NULL,                  -- "critical" | "high" | "medium" | "low"
    existing_controls TEXT,               -- JSON array of controls already in place
    missing_controls TEXT,                -- JSON array of controls that should exist
    toxic_combinations TEXT,              -- JSON: other findings that combine to make this worse
    recommendation TEXT,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS quality_scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phase INTEGER NOT NULL,
    phase_name TEXT NOT NULL,
    iteration INTEGER NOT NULL,
    score REAL NOT NULL,
    passed INTEGER NOT NULL,
    threshold REAL NOT NULL,
    dimensions TEXT,                       -- JSON object {dimension: score}
    feedback TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS agent_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_agent TEXT NOT NULL,
    to_agent TEXT,                         -- NULL = broadcast
    phase INTEGER NOT NULL,
    iteration INTEGER NOT NULL,
    message_type TEXT NOT NULL,            -- 'finding', 'instruction', 'feedback', 'question', 'decision', 'meeting_minutes'
    content TEXT NOT NULL,
    metadata TEXT,                         -- JSON for structured data
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_components_type ON components(component_type);
CREATE INDEX IF NOT EXISTS idx_flows_status ON flows(status);
CREATE INDEX IF NOT EXISTS idx_findings_severity ON findings(severity);
CREATE INDEX IF NOT EXISTS idx_findings_category ON findings(category);
CREATE INDEX IF NOT EXISTS idx_findings_phase ON findings(phase);
CREATE INDEX IF NOT EXISTS idx_findings_status ON findings(status);
CREATE INDEX IF NOT EXISTS idx_findings_component ON findings(component_id);
CREATE INDEX IF NOT EXISTS idx_evidence_finding ON evidence(finding_id);
CREATE INDEX IF NOT EXISTS idx_invariants_status ON invariants(status);
CREATE INDEX IF NOT EXISTS idx_threats_flow ON threat_models(flow_id);
CREATE INDEX IF NOT EXISTS idx_quality_phase ON quality_scores(phase);
CREATE INDEX IF NOT EXISTS idx_messages_phase ON agent_messages(phase);
CREATE INDEX IF NOT EXISTS idx_messages_type ON agent_messages(message_type);
"""


@contextlib.contextmanager
def get_connection(db_path: str):
    """Context manager for database connections with WAL mode."""
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        conn.row_factory = sqlite3.Row
        yield conn
    finally:
        conn.close()


def _validate_enum(value, valid_set: set, field_name: str) -> None:
    """Validate that a value is in an allowed set. Raises ValueError if not."""
    if value is not None and value not in valid_set:
        raise ValueError(f"Invalid {field_name}: '{value}'. Must be one of: {sorted(valid_set)}")


def _validate_range(value: float, min_val: float, max_val: float, field_name: str) -> None:
    """Validate that a numeric value is within range."""
    if value < min_val or value > max_val:
        raise ValueError(f"Invalid {field_name}: {value}. Must be between {min_val} and {max_val}")


def _parse_json_arg(json_str: str, arg_name: str) -> dict:
    """Parse a JSON string argument, raising a clear error on failure."""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON for {arg_name}: {e}") from e


def init_db(db_path: str) -> None:
    """Initialize the database schema."""
    with get_connection(db_path) as conn:
        conn.executescript(SCHEMA_SQL)
        conn.execute(
            "INSERT OR REPLACE INTO schema_version (version) VALUES (?)",
            (SCHEMA_VERSION,),
        )
        conn.commit()


# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------
def add_component(db_path: str, component: dict) -> dict:
    """Add a component to the database."""
    comp_type = component.get("component_type", "other")
    _validate_enum(comp_type, VALID_COMPONENT_TYPES, "component_type")

    comp_id = component.get("id", "")
    with get_connection(db_path) as conn:
        existing = conn.execute("SELECT id FROM components WHERE id = ?", (comp_id,)).fetchone()
        if existing:
            return {"status": "duplicate", "existing_id": comp_id}

        conn.execute(
            """INSERT INTO components (id, name, component_type, description, path,
               technology, dependencies, api_surface, notes)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                comp_id,
                component.get("name", ""),
                comp_type,
                component.get("description", ""),
                component.get("path"),
                component.get("technology"),
                json.dumps(component.get("dependencies", [])),
                json.dumps(component.get("api_surface", {})),
                component.get("notes"),
            ),
        )
        conn.commit()
        return {"status": "added", "id": comp_id}


def query_components(db_path: str, component_type: Optional[str] = None) -> list[dict]:
    """Query components with optional type filter."""
    with get_connection(db_path) as conn:
        query = "SELECT * FROM components WHERE 1=1"
        params: list = []
        if component_type:
            query += " AND component_type = ?"
            params.append(component_type)
        query += " ORDER BY component_type, name"
        rows = conn.execute(query, params).fetchall()
        return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Flows
# ---------------------------------------------------------------------------
def add_flow(db_path: str, flow: dict) -> dict:
    """Add a flow to the database."""
    status = flow.get("status", "identified")
    _validate_enum(status, VALID_FLOW_STATUSES, "status")

    flow_id = flow.get("id", "")
    with get_connection(db_path) as conn:
        existing = conn.execute("SELECT id FROM flows WHERE id = ?", (flow_id,)).fetchone()
        if existing:
            return {"status": "duplicate", "existing_id": flow_id}

        conn.execute(
            """INSERT INTO flows (id, name, description, flow_type, components, steps,
               entry_point, exit_point, status, criticality, notes)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                flow_id,
                flow.get("name", ""),
                flow.get("description", ""),
                flow.get("flow_type"),
                json.dumps(flow.get("components", [])),
                json.dumps(flow.get("steps", [])),
                flow.get("entry_point"),
                flow.get("exit_point"),
                status,
                flow.get("criticality"),
                flow.get("notes"),
            ),
        )
        conn.commit()
        return {"status": "added", "id": flow_id}


def query_flows(db_path: str, status: Optional[str] = None) -> list[dict]:
    """Query flows with optional status filter."""
    with get_connection(db_path) as conn:
        query = "SELECT * FROM flows WHERE 1=1"
        params: list = []
        if status:
            query += " AND status = ?"
            params.append(status)
        query += " ORDER BY name"
        rows = conn.execute(query, params).fetchall()
        return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------
def add_finding(db_path: str, finding: dict) -> dict:
    """Add a finding to the database."""
    severity = finding.get("severity")
    category = finding.get("category")
    status = finding.get("status", "open")
    phase = finding.get("phase")

    _validate_enum(severity, VALID_SEVERITIES, "severity")
    _validate_enum(category, VALID_FINDING_CATEGORIES, "category")
    _validate_enum(status, VALID_FINDING_STATUSES, "status")

    if phase is not None:
        _validate_range(int(phase), 1, 8, "phase")

    finding_id = finding.get("id", "")
    with get_connection(db_path) as conn:
        existing = conn.execute("SELECT id FROM findings WHERE id = ?", (finding_id,)).fetchone()
        if existing:
            return {"status": "duplicate", "existing_id": finding_id}

        conn.execute(
            """INSERT INTO findings (id, title, description, severity, category, phase,
               component_id, flow_id, file_path, line_range, code_snippet,
               root_cause, impact, recommendation, effort, status, c4_dimension)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                finding_id,
                finding.get("title", ""),
                finding.get("description", ""),
                severity,
                category,
                phase,
                finding.get("component_id"),
                finding.get("flow_id"),
                finding.get("file_path"),
                finding.get("line_range"),
                finding.get("code_snippet"),
                finding.get("root_cause"),
                finding.get("impact"),
                finding.get("recommendation"),
                finding.get("effort"),
                status,
                finding.get("c4_dimension"),
            ),
        )
        conn.commit()
        return {"status": "added", "id": finding_id}


def update_finding(db_path: str, finding_id: str, updates: dict) -> dict:
    """Update specific fields of a finding."""
    if "severity" in updates:
        _validate_enum(updates["severity"], VALID_SEVERITIES, "severity")
    if "status" in updates:
        _validate_enum(updates["status"], VALID_FINDING_STATUSES, "status")

    allowed_fields = {
        "severity", "status", "root_cause", "impact", "recommendation",
        "effort", "c4_dimension", "description", "title",
    }
    set_clauses = []
    values = []
    for field, value in updates.items():
        if field in allowed_fields:
            set_clauses.append(f"{field} = ?")
            values.append(value)

    if not set_clauses:
        return {"status": "error", "message": "no valid fields to update"}

    values.append(finding_id)
    with get_connection(db_path) as conn:
        conn.execute(
            f"UPDATE findings SET {', '.join(set_clauses)} WHERE id = ?", values
        )
        conn.commit()
        return {"status": "updated", "id": finding_id}


def query_findings(db_path: str, severity: Optional[str] = None,
                   phase: Optional[int] = None,
                   category: Optional[str] = None,
                   status: Optional[str] = None) -> list[dict]:
    """Query findings with optional filters."""
    with get_connection(db_path) as conn:
        query = "SELECT * FROM findings WHERE 1=1"
        params: list = []
        if severity:
            query += " AND severity = ?"
            params.append(severity)
        if phase is not None:
            query += " AND phase = ?"
            params.append(phase)
        if category:
            query += " AND category = ?"
            params.append(category)
        if status:
            query += " AND status = ?"
            params.append(status)
        query += " ORDER BY CASE severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 END, category"
        rows = conn.execute(query, params).fetchall()
        return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Evidence
# ---------------------------------------------------------------------------
def add_evidence(db_path: str, ev: dict) -> dict:
    """Add evidence for a finding."""
    ev_type = ev.get("evidence_type")
    _validate_enum(ev_type, VALID_EVIDENCE_TYPES, "evidence_type")

    with get_connection(db_path) as conn:
        conn.execute(
            """INSERT INTO evidence (finding_id, evidence_type, source, content, notes)
               VALUES (?, ?, ?, ?, ?)""",
            (
                ev.get("finding_id", ""),
                ev_type,
                ev.get("source", ""),
                ev.get("content", ""),
                ev.get("notes"),
            ),
        )
        conn.commit()
        ev_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
        return {"status": "added", "id": ev_id}


# ---------------------------------------------------------------------------
# Invariants
# ---------------------------------------------------------------------------
def add_invariant(db_path: str, inv: dict) -> dict:
    """Add a system invariant."""
    status = inv.get("status", "defined")
    _validate_enum(status, VALID_INVARIANT_STATUSES, "status")

    inv_id = inv.get("id", "")
    with get_connection(db_path) as conn:
        existing = conn.execute("SELECT id FROM invariants WHERE id = ?", (inv_id,)).fetchone()
        if existing:
            return {"status": "duplicate", "existing_id": inv_id}

        conn.execute(
            """INSERT INTO invariants (id, name, description, category, assertion,
               validation_method, status, violation_evidence, component_ids, flow_ids, notes)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                inv_id,
                inv.get("name", ""),
                inv.get("description", ""),
                inv.get("category"),
                inv.get("assertion", ""),
                inv.get("validation_method"),
                status,
                inv.get("violation_evidence"),
                json.dumps(inv.get("component_ids", [])),
                json.dumps(inv.get("flow_ids", [])),
                inv.get("notes"),
            ),
        )
        conn.commit()
        return {"status": "added", "id": inv_id}


def update_invariant(db_path: str, inv_id: str, updates: dict) -> dict:
    """Update specific fields of an invariant."""
    if "status" in updates:
        _validate_enum(updates["status"], VALID_INVARIANT_STATUSES, "status")

    allowed_fields = {"status", "violation_evidence", "validation_method", "notes"}
    set_clauses = []
    values = []
    for field, value in updates.items():
        if field in allowed_fields:
            set_clauses.append(f"{field} = ?")
            values.append(value)

    if not set_clauses:
        return {"status": "error", "message": "no valid fields to update"}

    values.append(inv_id)
    with get_connection(db_path) as conn:
        conn.execute(
            f"UPDATE invariants SET {', '.join(set_clauses)} WHERE id = ?", values
        )
        conn.commit()
        return {"status": "updated", "id": inv_id}


# ---------------------------------------------------------------------------
# Threat Models
# ---------------------------------------------------------------------------
def add_threat(db_path: str, threat: dict) -> dict:
    """Add a threat model entry."""
    likelihood = threat.get("likelihood")
    impact = threat.get("impact")
    _validate_enum(likelihood, VALID_THREAT_LIKELIHOODS, "likelihood")
    _validate_enum(impact, VALID_THREAT_IMPACTS, "impact")

    with get_connection(db_path) as conn:
        conn.execute(
            """INSERT INTO threat_models (flow_id, threat, attacker, attack_vector, asset,
               likelihood, impact, existing_controls, missing_controls, toxic_combinations,
               recommendation, notes)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                threat.get("flow_id", ""),
                threat.get("threat", ""),
                threat.get("attacker"),
                threat.get("attack_vector"),
                threat.get("asset"),
                likelihood,
                impact,
                json.dumps(threat.get("existing_controls", [])),
                json.dumps(threat.get("missing_controls", [])),
                json.dumps(threat.get("toxic_combinations", {})),
                threat.get("recommendation"),
                threat.get("notes"),
            ),
        )
        conn.commit()
        threat_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
        return {"status": "added", "id": threat_id}


def query_threats(db_path: str, flow_id: Optional[str] = None) -> list[dict]:
    """Query threat models with optional flow filter."""
    with get_connection(db_path) as conn:
        query = "SELECT * FROM threat_models WHERE 1=1"
        params: list = []
        if flow_id:
            query += " AND flow_id = ?"
            params.append(flow_id)
        query += " ORDER BY CASE impact WHEN 'critical' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 END"
        rows = conn.execute(query, params).fetchall()
        return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Quality Scores
# ---------------------------------------------------------------------------
def add_quality_score(db_path: str, phase: int, score: float, details: dict) -> dict:
    """Record a quality gate evaluation."""
    _validate_range(phase, 1, 8, "phase")
    _validate_range(score, 0.0, 1.0, "score")

    threshold = 0.7
    passed = 1 if score >= threshold else 0

    with get_connection(db_path) as conn:
        conn.execute(
            """INSERT INTO quality_scores (phase, phase_name, iteration, score, passed,
               threshold, dimensions, feedback)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                phase,
                details.get("phase_name", ""),
                details.get("iteration", 1),
                score,
                passed,
                threshold,
                json.dumps(details.get("dimensions", {})),
                details.get("feedback", ""),
            ),
        )
        conn.commit()
        return {"status": "added", "score": score, "passed": bool(passed)}


# ---------------------------------------------------------------------------
# Agent Messages
# ---------------------------------------------------------------------------
def add_message(db_path: str, from_agent: str, phase: int, content: str,
                iteration: int = 1, message_type: str = "finding",
                to_agent: Optional[str] = None,
                metadata: Optional[dict] = None) -> dict:
    """Store an inter-agent message."""
    _validate_enum(message_type, VALID_MESSAGE_TYPES, "message_type")
    _validate_range(phase, 1, 8, "phase")

    with get_connection(db_path) as conn:
        conn.execute(
            """INSERT INTO agent_messages (from_agent, to_agent, phase, iteration,
               message_type, content, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                from_agent,
                to_agent,
                phase,
                iteration,
                message_type,
                content,
                json.dumps(metadata) if metadata else None,
            ),
        )
        conn.commit()
        msg_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
        return {"status": "added", "id": msg_id}


def query_messages(db_path: str, phase: Optional[int] = None,
                   message_type: Optional[str] = None,
                   from_agent: Optional[str] = None) -> list[dict]:
    """Query agent messages with optional filters."""
    with get_connection(db_path) as conn:
        query = "SELECT * FROM agent_messages WHERE 1=1"
        params: list = []
        if phase is not None:
            query += " AND phase = ?"
            params.append(phase)
        if message_type:
            query += " AND message_type = ?"
            params.append(message_type)
        if from_agent:
            query += " AND from_agent = ?"
            params.append(from_agent)
        query += " ORDER BY created_at"
        rows = conn.execute(query, params).fetchall()
        return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
def stats(db_path: str) -> dict:
    """Get database statistics."""
    with get_connection(db_path) as conn:
        result = {}
        result["components"] = conn.execute("SELECT COUNT(*) FROM components").fetchone()[0]
        result["components_by_type"] = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT component_type, COUNT(*) FROM components GROUP BY component_type"
            ).fetchall()
        }
        result["flows"] = conn.execute("SELECT COUNT(*) FROM flows").fetchone()[0]
        result["flows_by_status"] = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT status, COUNT(*) FROM flows GROUP BY status"
            ).fetchall()
        }
        result["findings"] = conn.execute("SELECT COUNT(*) FROM findings").fetchone()[0]
        result["findings_by_severity"] = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT severity, COUNT(*) FROM findings GROUP BY severity"
            ).fetchall()
        }
        result["findings_by_category"] = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT category, COUNT(*) FROM findings GROUP BY category"
            ).fetchall()
        }
        result["findings_by_phase"] = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT phase, COUNT(*) FROM findings GROUP BY phase"
            ).fetchall()
        }
        result["evidence"] = conn.execute("SELECT COUNT(*) FROM evidence").fetchone()[0]
        result["invariants"] = conn.execute("SELECT COUNT(*) FROM invariants").fetchone()[0]
        result["invariants_by_status"] = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT status, COUNT(*) FROM invariants GROUP BY status"
            ).fetchall()
        }
        result["threat_models"] = conn.execute("SELECT COUNT(*) FROM threat_models").fetchone()[0]
        result["quality_scores"] = conn.execute("SELECT COUNT(*) FROM quality_scores").fetchone()[0]
        result["agent_messages"] = conn.execute("SELECT COUNT(*) FROM agent_messages").fetchone()[0]
        return result


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Review Deep Loop database CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command")

    # init
    p_init = sub.add_parser("init", help="Initialize database schema")
    p_init.add_argument("--db-path", required=True)

    # add-component
    p_comp = sub.add_parser("add-component", help="Add a component")
    p_comp.add_argument("--db-path", required=True)
    p_comp.add_argument("--component-json", required=True)

    # add-flow
    p_flow = sub.add_parser("add-flow", help="Add a flow")
    p_flow.add_argument("--db-path", required=True)
    p_flow.add_argument("--flow-json", required=True)

    # add-finding
    p_find = sub.add_parser("add-finding", help="Add a finding")
    p_find.add_argument("--db-path", required=True)
    p_find.add_argument("--finding-json", required=True)

    # update-finding
    p_uf = sub.add_parser("update-finding", help="Update a finding")
    p_uf.add_argument("--db-path", required=True)
    p_uf.add_argument("--finding-id", required=True)
    p_uf.add_argument("--updates-json", required=True)

    # add-evidence
    p_ev = sub.add_parser("add-evidence", help="Add evidence for a finding")
    p_ev.add_argument("--db-path", required=True)
    p_ev.add_argument("--evidence-json", required=True)

    # add-invariant
    p_inv = sub.add_parser("add-invariant", help="Add a system invariant")
    p_inv.add_argument("--db-path", required=True)
    p_inv.add_argument("--invariant-json", required=True)

    # update-invariant
    p_ui = sub.add_parser("update-invariant", help="Update an invariant")
    p_ui.add_argument("--db-path", required=True)
    p_ui.add_argument("--invariant-id", required=True)
    p_ui.add_argument("--updates-json", required=True)

    # add-threat
    p_threat = sub.add_parser("add-threat", help="Add a threat model")
    p_threat.add_argument("--db-path", required=True)
    p_threat.add_argument("--threat-json", required=True)

    # add-quality-score
    p_qs = sub.add_parser("add-quality-score", help="Record quality gate score")
    p_qs.add_argument("--db-path", required=True)
    p_qs.add_argument("--phase", type=int, required=True)
    p_qs.add_argument("--score", type=float, required=True)
    p_qs.add_argument("--details", default="{}")

    # add-message
    p_msg = sub.add_parser("add-message", help="Store inter-agent message")
    p_msg.add_argument("--db-path", required=True)
    p_msg.add_argument("--from-agent", required=True)
    p_msg.add_argument("--phase", type=int, required=True)
    p_msg.add_argument("--content", required=True)
    p_msg.add_argument("--iteration", type=int, default=1)
    p_msg.add_argument("--message-type", default="finding")
    p_msg.add_argument("--to-agent", default=None)
    p_msg.add_argument("--metadata-json", default=None)

    # query-components
    p_qc = sub.add_parser("query-components", help="Query components")
    p_qc.add_argument("--db-path", required=True)
    p_qc.add_argument("--component-type", default=None)

    # query-flows
    p_qf = sub.add_parser("query-flows", help="Query flows")
    p_qf.add_argument("--db-path", required=True)
    p_qf.add_argument("--status", default=None)

    # query-findings
    p_qfind = sub.add_parser("query-findings", help="Query findings")
    p_qfind.add_argument("--db-path", required=True)
    p_qfind.add_argument("--severity", default=None)
    p_qfind.add_argument("--phase", type=int, default=None)
    p_qfind.add_argument("--category", default=None)
    p_qfind.add_argument("--status", default=None)

    # query-threats
    p_qt = sub.add_parser("query-threats", help="Query threat models")
    p_qt.add_argument("--db-path", required=True)
    p_qt.add_argument("--flow-id", default=None)

    # query-messages
    p_qm = sub.add_parser("query-messages", help="Query agent messages")
    p_qm.add_argument("--db-path", required=True)
    p_qm.add_argument("--phase", type=int, default=None)
    p_qm.add_argument("--message-type", default=None)
    p_qm.add_argument("--from-agent", default=None)

    # stats
    p_stats = sub.add_parser("stats", help="Print database statistics")
    p_stats.add_argument("--db-path", required=True)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    try:
        if args.command == "init":
            init_db(args.db_path)
            print(json.dumps({"status": "initialized", "db_path": args.db_path}))

        elif args.command == "add-component":
            data = _parse_json_arg(args.component_json, "--component-json")
            result = add_component(args.db_path, data)
            print(json.dumps(result))

        elif args.command == "add-flow":
            data = _parse_json_arg(args.flow_json, "--flow-json")
            result = add_flow(args.db_path, data)
            print(json.dumps(result))

        elif args.command == "add-finding":
            data = _parse_json_arg(args.finding_json, "--finding-json")
            result = add_finding(args.db_path, data)
            print(json.dumps(result))

        elif args.command == "update-finding":
            updates = _parse_json_arg(args.updates_json, "--updates-json")
            result = update_finding(args.db_path, args.finding_id, updates)
            print(json.dumps(result))

        elif args.command == "add-evidence":
            data = _parse_json_arg(args.evidence_json, "--evidence-json")
            result = add_evidence(args.db_path, data)
            print(json.dumps(result))

        elif args.command == "add-invariant":
            data = _parse_json_arg(args.invariant_json, "--invariant-json")
            result = add_invariant(args.db_path, data)
            print(json.dumps(result))

        elif args.command == "update-invariant":
            updates = _parse_json_arg(args.updates_json, "--updates-json")
            result = update_invariant(args.db_path, args.invariant_id, updates)
            print(json.dumps(result))

        elif args.command == "add-threat":
            data = _parse_json_arg(args.threat_json, "--threat-json")
            result = add_threat(args.db_path, data)
            print(json.dumps(result))

        elif args.command == "add-quality-score":
            details = _parse_json_arg(args.details, "--details")
            result = add_quality_score(args.db_path, args.phase, args.score, details)
            print(json.dumps(result))

        elif args.command == "add-message":
            metadata = _parse_json_arg(args.metadata_json, "--metadata-json") if args.metadata_json else None
            result = add_message(
                args.db_path, args.from_agent, args.phase, args.content,
                iteration=args.iteration, message_type=args.message_type,
                to_agent=args.to_agent, metadata=metadata,
            )
            print(json.dumps(result))

        elif args.command == "query-components":
            results = query_components(args.db_path, component_type=args.component_type)
            print(json.dumps(results, indent=2, default=str))

        elif args.command == "query-flows":
            results = query_flows(args.db_path, status=args.status)
            print(json.dumps(results, indent=2, default=str))

        elif args.command == "query-findings":
            results = query_findings(
                args.db_path, severity=args.severity, phase=args.phase,
                category=args.category, status=args.status,
            )
            print(json.dumps(results, indent=2, default=str))

        elif args.command == "query-threats":
            results = query_threats(args.db_path, flow_id=args.flow_id)
            print(json.dumps(results, indent=2, default=str))

        elif args.command == "query-messages":
            results = query_messages(
                args.db_path, phase=args.phase, message_type=args.message_type,
                from_agent=args.from_agent,
            )
            print(json.dumps(results, indent=2, default=str))

        elif args.command == "stats":
            result = stats(args.db_path)
            print(json.dumps(result, indent=2, default=str))

        return 0

    except ValueError as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        return 1
    except sqlite3.Error as e:
        print(json.dumps({"error": f"Database error: {e}"}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
