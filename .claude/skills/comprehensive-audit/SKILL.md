---
name: comprehensive-audit
description: Run the repository's comprehensive scientific-software audit protocol (docs/comprehensive_audit.md) — a full or scoped verification/validation pass with a coverage ledger, briefed reading units, evidence rules, and the full-suite gate. Use for "audit", "verification pass", "repository-wide correctness review", or a scoped re-read of a subsystem.
---

# Comprehensive Audit

The protocol is the document, not this skill. **Read
`docs/comprehensive_audit.md` in full before doing anything else and treat
it as binding.** This skill exists so the protocol is one command away and
its entry conditions cannot be skipped; it deliberately does not duplicate
the protocol (Measured Lesson 4: hand copies drift).

**Arguments.** An optional scope — paths, subsystems, or `full`. Either
way, the protocol's Phase 0 requires the scope declared and recorded
before reading anything in depth.

**Before starting**, read (summaries and lessons, not front to back):

- `docs/history/comprehensive_audit_2026_08_05.md` §1a and §7 — the most
  recent full pass and its closed queue.
- `docs/comprehensive_audit.md` "Measured Lessons" — the rules previous
  sessions paid for.
- The archived per-unit reports under
  `docs/history/comprehensive_audit_2026_08_05_unit_reports/` when a lead
  touches a region they cover.

**Non-negotiables the protocol will restate (read it anyway):**

- Declare scope and budget first; keep the coverage ledger with per-region
  provenance (auditor vs agent).
- A sub-agent claim is a lead, not a finding (measured survival ~60%); the
  auditor reproduces every lead; no sub-agent ever fixes.
- Capture the behavioral fingerprint before the first source modification.
- Findings land with reproduction, fix, negative control, ledger, and
  `todo.md` updates in the same commit.
- Finish through the full-suite gate at CI settings; record which testsets
  actually ran.

**Reading units** are spawned with the checked-in `audit-reader` agent
definition (`.claude/agents/audit-reader.md`) so briefs and lead formats
stay uniform across sessions.
