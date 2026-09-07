# Closing the metadata-validator cluster — 2026-09-07

Three rows in `docs/todo.md` described the same weakness from three angles: a
declared fact that nothing checks. Closing them together was worth doing because
each one's *evidence* had aged differently, and two of the three turned out to be
wrong about their own subject in ways that mattered — one understated the defect,
one overstated it. Both corrections are stated here rather than quietly folded
into the fix.

The thread running through all three is this campaign's recurring shape: **a
check that cannot fail**, and its neighbour, **a fact that is asserted but never
compared to anything**.

## U4-18 — the observer schema-vs-report check, narrowed and then replaced

The row read: "the observer schema-vs-report check is an identity for derived
reports". Confirmed, and narrowed to exactly where it bites.

`validate_configuration_metadata` compares each observer's schema keys against
the entry names of its `configuration_report`. For `MomentObserver` and
`CoordinateSnapshotObserver` that is a real comparison: their reports are
hand-written and name their entry symbols literally, against separately written
schemas. For `BPMObserver` it is an **identity** — the accessor returns
`_BPM_OBSERVER_OPTION_SCHEMA` (`BPMObserver.jl:411-412`) and the report iterates
`pairs(_BPM_OBSERVER_OPTION_SCHEMA)` (`:416`). Both sides are `keys` of one
object. It cannot fail for any content.

The check is kept, because it is real for two of the three.

**The row was also stale.** It said "five observers whose reports are
hand-written". The 2026-08-11 legacy cut and the 2026-08-18/19 artifact sweep
took the concrete observer count from six to three, so the vacuous fraction went
from 1-in-6 to 1-in-3 — three times worse than the row claimed, from a change
that had nothing to do with observers.

### What replaces the missing coverage

Not a better version of the same comparison — a different one, and one the
docstring had been claiming all along: **schema keys must name public fields**.
Every sibling metadata family had this check; observers were the only one
without it.

It had been tried before and **reverted**, and the recorded reason was specific:
three observers declared `capacity` while storing `buffer_capacity`. That is
worth re-reading rather than trusting, because a reverted check is usually
reverted for a reason that is still true. It is not: those three observers were
deleted in the same legacy cut above, and `capacity = ConfigurationOptionMeta`
appears nowhere in `src/` today. The obstacle is gone, which is the only reason
this could be re-enabled.

Measured before enabling, so this is not "it passed, ship it": `MomentObserver`
2-of-2, `CoordinateSnapshotObserver` 2-of-2, `BPMObserver` 12-of-12 schema keys
are fields. Shown failing on an injected non-field key, pinned in
`test/runtests.jl`.

### What was NOT done, with the blocker measured rather than assumed

The sibling families also check that a **declared default matches what the
constructor builds**. Observers still cannot, and the reason is not laziness:

| observer | option | declares | constructor builds |
|---|---|---|---|
| `MomentObserver` | `moments` | `nothing` | the full 27-`Moment` tuple |
| `BPMObserver` | `rng_id` | `0` | `2` |

Both are legitimate **sentinel** meanings — `nothing` means "all moments", `0`
means "assign one". A naive `declared == built` check fails on a correct tree,
which is precisely why it must not simply be added. Ledgered as its own row: it
needs `ConfigurationOptionMeta` to carry a `default_provenance` saying which kind
of default it holds, defaulting to today's meaning so no existing call site
changes, and then an audit of every declared default across every family to
classify it. That audit is the work, and it is this same campaign continued.

## U12-6 — `unit` was free text, and the row understated why that mattered

The row grouped `ParamMeta.unit` with `physics_keywords` and `description` as
three unvalidated free-text channels, and rated the group **Low** on an explicit
premise: "`unit` is only ever concatenated into help output", and "no automated
consumer acts on them today".

**That premise is false, and it is the whole reason this row got fixed while its
two siblings did not.** `unit` has a behavioural consumer:

```julia
# src/contracts/Contracts.jl:2987
_perturb_is_physical(key, pmeta) =
    key in _PLACEMENT_PARAM_KEYS || (pmeta isa ParamMeta && pmeta.unit in ("m", "rad"))
```

Its answer is consumed at `:3019` to choose how the parameter-effectiveness
contract perturbs an integer-declared parameter: a physical `1.0e-3`, or an
enum-style step. So the row's own injection — `unit="furlong"` on a length — does
not merely print oddly. It **silently downgrades that parameter to a weaker
probe, and the contract goes on passing**. That is "a check that cannot fail" one
level out: the check still runs, still passes, and now tests something less than
it claims.

The fix is the shape the neighbouring `ALLOWED_PHYSICS_KEYWORDS` already had: a
controlled vocabulary, `ALLOWED_PARAM_UNITS`, checked in
`validate_element_metadata`.

Measured across all 255 `ParamMeta` declarations before enabling it — the whole
declared vocabulary, with no typos to fix:

| unit | declarations |
|---|---|
| `rad` | 9 |
| `m` | 7 |
| `Hz` | 3 |
| `""` | 3 |
| (unset) | 233 |

So it passes on today's tree and bites on the next one. Shown failing on
`unit="furlong"` — the row's own injection, now caught — pinned in
`test/runtests.jl`.

One thing the docstring states explicitly, because the two ideas are easy to
conflate: **membership in the vocabulary is not the same as being physical.**
`Hz` is admitted and is not physical to the contract. Widening the vocabulary
does not change the perturbation policy; changing that policy is a separate
decision needing its own evidence.

The row's other two thirds stay open and stay Low, now for a stated reason rather
than a wrong one: keyword *accuracy* and `description` *accuracy* are semantic,
have no behavioural consumer, and need a curated cross-check or an agent pass.

## The hand-enumeration row — stale in every specific, with something real behind it

The row: `validate_configuration_metadata`'s hardcoded type enumeration leaves a
new solver or observer unchecked until someone edits a tuple, and `Contracts.jl`
carries a second hand-copy of the solver list.

Every specific in it was already closed by other rows:

| the row's claim | actual state |
|---|---|
| solver/observer loops are hand lists | totalized by U3-4 |
| policy/schedule loops are hand lists | totalized by U12-3 |
| `Contracts.jl` hand-copies the solver list | derived by U4-7 (`_solver_contract_types`), with a tripwire that **fails** the contract when a derived solver has no probe (`Contracts.jl:3669`) |
| `GaussianPICPoissonSolver` absent | covered |
| `BPMObserver` absent | covered |
| no task-level schema | `strong_strong_task_option_schema` exists, with its own key-completeness check |

Reading the code instead of the row is what showed this — and it is also what
found the part no row had noticed.

**What was actually left is the difference between those repairs.** Four tree
walks guard these families. Two recursed and two did not:

```julia
for T in subtypes(AbstractPoissonSolver)
    isabstracttype(T) && continue      # <- skips, instead of descending
```

`subtypes` returns direct children only, and the solver and observer loops
**skipped** abstract children rather than walking into them. A concrete solver or
observer sitting under an intermediate abstract type was therefore invisible to
the guard whose entire purpose is to notice it. That is the trap U12-3 had
already fixed for the policy tree — and which U4-7's own docstring names, for
this very type tree, one file away:

> `_concrete_octopus_subtypes` recurses, which `subtypes` does not: a future
> intermediate abstract solver type would otherwise hide every concrete leaf
> beneath it, the same trap U12-3 fixed for execution policies.

The knowledge was written down twice and applied in two places out of four. All
four walks now use the shared recursive helper, and the two duplicated comment
blocks are deleted rather than reworded: the reasoning they carried (parametric
types are `UnionAll`s; `Main`-defined suite subtypes must stay out) already lives
in the helper's own docstring, and hand-copying it a third time is the habit that
produced the divergence.

**Not live today, and asserted rather than assumed.** Neither tree has an
abstract intermediate, pinned as `all(!isabstracttype, subtypes(...))` — the
assertion that stops being true the day someone adds one, which is the day the
guard would otherwise have gone quiet.

### How it is shown to fail — and why in a child process

Two pins, because the honest one costs a subprocess:

- **In process, on real types.** The execution-policy tree is genuinely two deep,
  so no injection is needed to demonstrate the mechanism: a one-level walk over
  `AbstractExecutionPolicy` misses `CUDAExecutionPolicy` and `GPUExecutionPolicy`
  — the two policies that matter most — while the recursive walk finds them.
- **In a child process, end to end.** An abstract intermediate with a concrete
  leaf is injected into `Octopus`, the premise is asserted rather than assumed
  (the leaf really is absent from `subtypes`), and the validator is shown
  refusing it by name.

The child is not fastidiousness. **A type definition cannot be undone.** Injected
in process, the bogus solver would persist for the rest of the session and fail
every later `validate_configuration_metadata()` — the suite's own line 170 and
the public-configuration contract — turning one negative control into a
session-wide breakage. The subprocess exits and takes the type with it.

## A gate that reported success without running

Worth recording because the failure mode is invisible and the lesson is this
repository's own: *a check only counts while it executes.*

The gate was launched as

```
rm -f /tmp/octopus_mpi_seam_check*.h5 && julia --project=. ... > gate.log 2>&1; echo "EXIT=$?"
```

The shell is `zsh`, which **errors on a glob that matches nothing** rather than
passing it through as `bash` does. With the artifacts already cleared, `rm` never
ran, the `&&` chain aborted, and Julia was never invoked — but the trailing
`echo` still made the whole command exit 0, and the background task reported
**completed, exit code 0**. The only reason it was caught is that the log file it
should have written did not exist.

An exit code from a compound command is a statement about the last thing in it,
not about the thing you cared about. The artifact clear is now
`find /tmp -maxdepth 1 -name 'octopus_mpi_seam_check*.h5' -delete`, which is
silent on no matches, and the gate's result is read from its log rather than from
its exit status.

## An ambiguous gate, discarded rather than reported

A gate covering the U4-18 work was running when the U12-6 edit to
`src/knowledge/Knowledge.jl` landed. Whether the running suite had already loaded
the package or was still precompiling it could not be established after the fact,
so what that gate tested was unknown — it might have carried the unit check or
not.

It was killed by PID (not by a `pkill -f` pattern, which matches the killing
shell's own command line) and its result discarded, and every change was gated
once, together, at the end. A gate whose subject is uncertain certifies nothing,
and reporting it as a pass would have been the worse of the two available
mistakes.
