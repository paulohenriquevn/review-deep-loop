#!/usr/bin/env python3
"""Tests for review_database.py — the Review Deep Loop database module."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# Add scripts directory to path
SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import review_database as db


@pytest.fixture
def tmp_db(tmp_path):
    """Create a temporary database for testing."""
    db_path = str(tmp_path / "test.db")
    db.init_db(db_path)
    return db_path


# ---------------------------------------------------------------------------
# Schema initialization
# ---------------------------------------------------------------------------
class TestInit:
    def test_init_creates_database(self, tmp_path):
        db_path = str(tmp_path / "new.db")
        db.init_db(db_path)
        assert os.path.exists(db_path)

    def test_init_creates_all_tables(self, tmp_db):
        with db.get_connection(tmp_db) as conn:
            tables = {
                row[0]
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()
            }
        expected = {
            "schema_version", "components", "flows", "findings", "evidence",
            "invariants", "threat_models", "quality_scores", "agent_messages",
        }
        assert expected.issubset(tables)

    def test_init_sets_schema_version(self, tmp_db):
        with db.get_connection(tmp_db) as conn:
            version = conn.execute("SELECT version FROM schema_version").fetchone()[0]
        assert version == 1

    def test_init_is_idempotent(self, tmp_db):
        db.init_db(tmp_db)  # second init should not fail
        with db.get_connection(tmp_db) as conn:
            version = conn.execute("SELECT version FROM schema_version").fetchone()[0]
        assert version == 1


# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------
class TestComponents:
    def test_add_component(self, tmp_db):
        result = db.add_component(tmp_db, {
            "id": "comp_api",
            "name": "API Service",
            "component_type": "service",
            "description": "REST API",
            "path": "src/api/",
            "technology": "python",
        })
        assert result["status"] == "added"
        assert result["id"] == "comp_api"

    def test_add_duplicate_component(self, tmp_db):
        db.add_component(tmp_db, {
            "id": "comp_api", "name": "API", "component_type": "service",
            "description": "API",
        })
        result = db.add_component(tmp_db, {
            "id": "comp_api", "name": "API 2", "component_type": "service",
            "description": "API 2",
        })
        assert result["status"] == "duplicate"

    def test_invalid_component_type(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid component_type"):
            db.add_component(tmp_db, {
                "id": "comp_x", "name": "X", "component_type": "invalid_type",
                "description": "X",
            })

    def test_query_components(self, tmp_db):
        db.add_component(tmp_db, {
            "id": "comp_a", "name": "A", "component_type": "service",
            "description": "A",
        })
        db.add_component(tmp_db, {
            "id": "comp_b", "name": "B", "component_type": "database",
            "description": "B",
        })
        all_comps = db.query_components(tmp_db)
        assert len(all_comps) == 2

        services = db.query_components(tmp_db, component_type="service")
        assert len(services) == 1
        assert services[0]["id"] == "comp_a"


# ---------------------------------------------------------------------------
# Flows
# ---------------------------------------------------------------------------
class TestFlows:
    def test_add_flow(self, tmp_db):
        result = db.add_flow(tmp_db, {
            "id": "flow_auth",
            "name": "Authentication",
            "description": "Login flow",
            "flow_type": "user_facing",
            "components": ["comp_api", "comp_db"],
            "criticality": "critical",
        })
        assert result["status"] == "added"

    def test_invalid_flow_status(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid status"):
            db.add_flow(tmp_db, {
                "id": "flow_x", "name": "X", "description": "X",
                "status": "nonexistent",
            })

    def test_query_flows(self, tmp_db):
        db.add_flow(tmp_db, {
            "id": "flow_a", "name": "A", "description": "A",
        })
        flows = db.query_flows(tmp_db)
        assert len(flows) == 1
        assert flows[0]["status"] == "identified"


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------
class TestFindings:
    def test_add_finding(self, tmp_db):
        result = db.add_finding(tmp_db, {
            "id": "find_001",
            "title": "Missing input validation",
            "description": "No validation on user input",
            "severity": "high",
            "category": "security",
            "phase": 6,
            "file_path": "src/api/handlers.py",
            "c4_dimension": "correto",
        })
        assert result["status"] == "added"

    def test_invalid_severity(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid severity"):
            db.add_finding(tmp_db, {
                "id": "find_x", "title": "X", "description": "X",
                "severity": "extreme", "category": "code", "phase": 4,
            })

    def test_invalid_category(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid category"):
            db.add_finding(tmp_db, {
                "id": "find_x", "title": "X", "description": "X",
                "severity": "high", "category": "nonexistent", "phase": 4,
            })

    def test_invalid_phase_range(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid phase"):
            db.add_finding(tmp_db, {
                "id": "find_x", "title": "X", "description": "X",
                "severity": "high", "category": "code", "phase": 9,
            })

    def test_query_findings_by_severity(self, tmp_db):
        db.add_finding(tmp_db, {
            "id": "find_c", "title": "Critical", "description": "D",
            "severity": "critical", "category": "security", "phase": 6,
        })
        db.add_finding(tmp_db, {
            "id": "find_l", "title": "Low", "description": "D",
            "severity": "low", "category": "code", "phase": 4,
        })
        critical = db.query_findings(tmp_db, severity="critical")
        assert len(critical) == 1
        assert critical[0]["id"] == "find_c"

    def test_query_findings_by_phase(self, tmp_db):
        db.add_finding(tmp_db, {
            "id": "find_a", "title": "A", "description": "D",
            "severity": "medium", "category": "code", "phase": 4,
        })
        db.add_finding(tmp_db, {
            "id": "find_b", "title": "B", "description": "D",
            "severity": "medium", "category": "architecture", "phase": 3,
        })
        phase4 = db.query_findings(tmp_db, phase=4)
        assert len(phase4) == 1

    def test_update_finding(self, tmp_db):
        db.add_finding(tmp_db, {
            "id": "find_u", "title": "U", "description": "D",
            "severity": "medium", "category": "code", "phase": 4,
        })
        result = db.update_finding(tmp_db, "find_u", {"status": "confirmed", "severity": "high"})
        assert result["status"] == "updated"

        findings = db.query_findings(tmp_db, severity="high")
        assert len(findings) == 1
        assert findings[0]["status"] == "confirmed"

    def test_findings_ordered_by_severity(self, tmp_db):
        db.add_finding(tmp_db, {
            "id": "f_low", "title": "Low", "description": "D",
            "severity": "low", "category": "code", "phase": 4,
        })
        db.add_finding(tmp_db, {
            "id": "f_crit", "title": "Critical", "description": "D",
            "severity": "critical", "category": "code", "phase": 4,
        })
        all_findings = db.query_findings(tmp_db)
        assert all_findings[0]["severity"] == "critical"
        assert all_findings[1]["severity"] == "low"


# ---------------------------------------------------------------------------
# Evidence
# ---------------------------------------------------------------------------
class TestEvidence:
    def test_add_evidence(self, tmp_db):
        db.add_finding(tmp_db, {
            "id": "find_ev", "title": "T", "description": "D",
            "severity": "medium", "category": "code", "phase": 4,
        })
        result = db.add_evidence(tmp_db, {
            "finding_id": "find_ev",
            "evidence_type": "code_snippet",
            "source": "src/main.py:42",
            "content": "except Exception:\n    pass",
        })
        assert result["status"] == "added"

    def test_invalid_evidence_type(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid evidence_type"):
            db.add_evidence(tmp_db, {
                "finding_id": "find_x",
                "evidence_type": "invalid_type",
                "source": "x",
                "content": "x",
            })


# ---------------------------------------------------------------------------
# Invariants
# ---------------------------------------------------------------------------
class TestInvariants:
    def test_add_invariant(self, tmp_db):
        result = db.add_invariant(tmp_db, {
            "id": "inv_tenant",
            "name": "Tenant Isolation",
            "description": "Tenants cannot access each other's data",
            "category": "security",
            "assertion": "All queries filter by tenant_id",
        })
        assert result["status"] == "added"

    def test_update_invariant(self, tmp_db):
        db.add_invariant(tmp_db, {
            "id": "inv_x", "name": "X", "description": "D",
            "assertion": "A",
        })
        result = db.update_invariant(tmp_db, "inv_x", {"status": "violated"})
        assert result["status"] == "updated"

    def test_invalid_invariant_status(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid status"):
            db.add_invariant(tmp_db, {
                "id": "inv_bad", "name": "X", "description": "D",
                "assertion": "A", "status": "broken",
            })


# ---------------------------------------------------------------------------
# Threat Models
# ---------------------------------------------------------------------------
class TestThreatModels:
    def test_add_threat(self, tmp_db):
        db.add_flow(tmp_db, {
            "id": "flow_auth", "name": "Auth", "description": "D",
        })
        result = db.add_threat(tmp_db, {
            "flow_id": "flow_auth",
            "threat": "Credential stuffing",
            "likelihood": "high",
            "impact": "critical",
            "existing_controls": ["bcrypt"],
            "missing_controls": ["rate limiting"],
        })
        assert result["status"] == "added"

    def test_invalid_likelihood(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid likelihood"):
            db.add_threat(tmp_db, {
                "flow_id": "flow_x",
                "threat": "X",
                "likelihood": "extreme",
                "impact": "high",
            })

    def test_invalid_impact(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid impact"):
            db.add_threat(tmp_db, {
                "flow_id": "flow_x",
                "threat": "X",
                "likelihood": "high",
                "impact": "catastrophic",
            })

    def test_query_threats(self, tmp_db):
        db.add_flow(tmp_db, {"id": "flow_a", "name": "A", "description": "D"})
        db.add_threat(tmp_db, {
            "flow_id": "flow_a", "threat": "T1",
            "likelihood": "high", "impact": "critical",
        })
        threats = db.query_threats(tmp_db, flow_id="flow_a")
        assert len(threats) == 1


# ---------------------------------------------------------------------------
# Quality Scores
# ---------------------------------------------------------------------------
class TestQualityScores:
    def test_add_quality_score(self, tmp_db):
        result = db.add_quality_score(tmp_db, phase=3, score=0.85, details={
            "phase_name": "architecture",
            "iteration": 2,
            "dimensions": {"coupling": 0.9, "cohesion": 0.8},
            "feedback": "Good analysis",
        })
        assert result["status"] == "added"
        assert result["passed"] is True

    def test_quality_score_failing(self, tmp_db):
        result = db.add_quality_score(tmp_db, phase=2, score=0.45, details={
            "phase_name": "completeness",
        })
        assert result["passed"] is False

    def test_invalid_phase_range(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid phase"):
            db.add_quality_score(tmp_db, phase=9, score=0.5, details={})

    def test_invalid_score_range(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid score"):
            db.add_quality_score(tmp_db, phase=3, score=1.5, details={})


# ---------------------------------------------------------------------------
# Agent Messages
# ---------------------------------------------------------------------------
class TestAgentMessages:
    def test_add_message(self, tmp_db):
        result = db.add_message(
            tmp_db, from_agent="chief-reviewer", phase=1,
            content="Meeting minutes", message_type="meeting_minutes",
        )
        assert result["status"] == "added"

    def test_invalid_message_type(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid message_type"):
            db.add_message(
                tmp_db, from_agent="x", phase=1,
                content="x", message_type="invalid",
            )

    def test_invalid_phase_in_message(self, tmp_db):
        with pytest.raises(ValueError, match="Invalid phase"):
            db.add_message(
                tmp_db, from_agent="x", phase=0,
                content="x", message_type="finding",
            )

    def test_query_messages(self, tmp_db):
        db.add_message(
            tmp_db, from_agent="code-reviewer", phase=4,
            content="Found issue", message_type="finding",
        )
        db.add_message(
            tmp_db, from_agent="chief-reviewer", phase=4,
            content="Meeting", message_type="meeting_minutes",
        )
        findings = db.query_messages(tmp_db, phase=4, message_type="finding")
        assert len(findings) == 1
        assert findings[0]["from_agent"] == "code-reviewer"


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
class TestStats:
    def test_stats_empty_db(self, tmp_db):
        result = db.stats(tmp_db)
        assert result["components"] == 0
        assert result["findings"] == 0
        assert result["threat_models"] == 0

    def test_stats_with_data(self, tmp_db):
        db.add_component(tmp_db, {
            "id": "c1", "name": "C1", "component_type": "service",
            "description": "D",
        })
        db.add_finding(tmp_db, {
            "id": "f1", "title": "F1", "description": "D",
            "severity": "critical", "category": "security", "phase": 6,
        })
        result = db.stats(tmp_db)
        assert result["components"] == 1
        assert result["findings"] == 1
        assert result["findings_by_severity"]["critical"] == 1


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
class TestCLI:
    def _run_cli(self, *args):
        cmd = [sys.executable, str(SCRIPTS_DIR / "review_database.py")] + list(args)
        return subprocess.run(cmd, capture_output=True, text=True)

    def test_cli_init(self, tmp_path):
        db_path = str(tmp_path / "cli.db")
        result = self._run_cli("init", "--db-path", db_path)
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["status"] == "initialized"

    def test_cli_add_component(self, tmp_path):
        db_path = str(tmp_path / "cli.db")
        self._run_cli("init", "--db-path", db_path)
        result = self._run_cli(
            "add-component", "--db-path", db_path,
            "--component-json", json.dumps({
                "id": "comp_cli", "name": "CLI Test",
                "component_type": "service", "description": "Test",
            }),
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["status"] == "added"

    def test_cli_invalid_json(self, tmp_path):
        db_path = str(tmp_path / "cli.db")
        self._run_cli("init", "--db-path", db_path)
        result = self._run_cli(
            "add-component", "--db-path", db_path,
            "--component-json", "not valid json",
        )
        assert result.returncode == 1

    def test_cli_stats(self, tmp_path):
        db_path = str(tmp_path / "cli.db")
        self._run_cli("init", "--db-path", db_path)
        result = self._run_cli("stats", "--db-path", db_path)
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert "components" in output
        assert "findings" in output

    def test_cli_add_finding(self, tmp_path):
        db_path = str(tmp_path / "cli.db")
        self._run_cli("init", "--db-path", db_path)
        result = self._run_cli(
            "add-finding", "--db-path", db_path,
            "--finding-json", json.dumps({
                "id": "f_cli", "title": "CLI Finding",
                "description": "Test", "severity": "high",
                "category": "code", "phase": 4,
            }),
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert output["status"] == "added"

    def test_cli_query_findings(self, tmp_path):
        db_path = str(tmp_path / "cli.db")
        self._run_cli("init", "--db-path", db_path)
        self._run_cli(
            "add-finding", "--db-path", db_path,
            "--finding-json", json.dumps({
                "id": "f1", "title": "F1", "description": "D",
                "severity": "critical", "category": "security", "phase": 6,
            }),
        )
        result = self._run_cli(
            "query-findings", "--db-path", db_path, "--severity", "critical",
        )
        assert result.returncode == 0
        output = json.loads(result.stdout)
        assert len(output) == 1
        assert output[0]["severity"] == "critical"

    def test_cli_no_command(self):
        result = self._run_cli()
        assert result.returncode == 1
