# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial plugin structure with 8-phase pipeline (Baseline, Completeness, Architecture, Code, Infrastructure, Security, Validation, Report)
- 16 specialized agents for deep software review and audit
- SQLite database with 9 tables for components, flows, findings, evidence, invariants, threat models, and agent coordination
- Ralph Wiggum loop via stop hook with quality gates and hard blocks
- 4 operation modes: full, quick, security, architecture
- Loop-back mechanism from Validation to Completeness (up to 2 re-review cycles)
- 4 severity levels for findings: critical, high, medium, low
- Setup script with argument parsing and output directory initialization
- 4 slash commands: /review-loop, /review-status, /review-cancel, /review-help
- Enum validation for all domain values in database (severity, category, status, component_type, flow_status, evidence_type, threat_likelihood, threat_impact, message_type)
- Phase data flow documentation in review-prompt.md (inputs/outputs per phase)
- Quality gate rubrics per phase with automatic fail conditions
- Hard blocks enforcing evidence requirements before phase advancement
- Test coverage: database operations, enum validation, stop hook logic, setup script
- Plugin configuration files (.claude-plugin/plugin.json, marketplace.json) for marketplace publishing
- .gitignore for Python artifacts, runtime output, and editor files
