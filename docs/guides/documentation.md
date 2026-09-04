# Documentation and Public APIs

Route here from the `AGENTS.md` task table for changes to public docstrings,
the public API surface, generated registries, or anything under `docs/`.

## Source is the authority

Octopus prefers source code, docstrings, reflection, and curated examples over
external metadata hierarchies. Public architecture APIs need docstrings, and
detailed API guidance belongs in docstrings, not in markdown. Do not
duplicate large source explanations in markdown, and do not claim contracts,
analyses, policies, or keywords before the implementation exists.

## Generated and volatile documents

- `docs/registry_snapshot.md` is generated. Regenerate it with
  `write_registry_snapshot()` after public architecture objects change; the
  suite compares the committed snapshot with the generated one. Never
  hand-edit it.
- `docs/current_runtime.md` holds runtime-specific details that are expected
  to change (particle representation, kernel interface, backend behavior).
  Put such details there, not in `AGENTS.md` or in public docstrings.
- `docs/public_api.md` routes readers to the public docstrings and metadata
  queries; update it when an entry point is added or renamed.

## The `docs/` taxonomy

- `docs/theory/`: physics and method derivations (the Knowledge Layer) that
  implementing code links back to.
- `docs/design/`: architecture decision notes: which design was chosen among
  alternatives and why, citing the theory it builds on and the alternatives
  it rejected. Theory derives, design decides, source implements.
- `docs/guides/`: development guides, one per task class, routed from
  `AGENTS.md`.
- `docs/history/`: dated, frozen records of implemented work (optimization
  and benchmark histories, audits, the archived TODO ledger). Add; never
  rewrite.
- Top-level `docs/`: entry-point, generated, or volatile notes
  (`public_api.md`, `registry_snapshot.md`, `current_runtime.md`), the live
  plan (`todo.md`), the lessons file (`experiences.md`), the audit protocol
  (`comprehensive_audit.md`), and one grandfathered design note
  (`knob_control.md`, which predates `docs/design/`).

Add every new document to the `docs/README.md` index. Not-yet-done items go
in `todo.md`; when an item closes, move its record to `docs/history/` (rows
land in `history/todo_ledger_archive.md` under a dated note) and add any
reusable lesson to `experiences.md`.

## `AGENTS.md` itself

The root file is a dispatcher: mission, invariants, the source map, the task
routing table, authorization, the verification matrix, and the definition of
done. It states stable invariants only; dates, campaign identifiers, counts,
and incident narratives belong in generated registries, `experiences.md`, and
`docs/history/`. Procedures live in these guides. When a guide changes, check
that the routing row pointing at it still names the right reads and the right
gate.

## Finish

`write_registry_snapshot()` when a public object changed, the docs index
entry, and the full gate (`development_workflow.md`). Docs-only changes are a
full-gate class: the suite walks docstrings and indexes, and "it's only docs"
is a claim the gate checks.
