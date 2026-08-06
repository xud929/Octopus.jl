# Beam Lines: Composition, Expansion, and Search

Octopus tracks a bare `Tuple` of specs. That has carried the element work, but
it cannot answer *which entry is the third CQS module in ARC1*, it has no notion
of `s`, and it gives Twiss nowhere to live — the one-turn machinery already
exists, in `validation/lattice_cells.jl`, because the architecture offers it no
home.

This note is about what to put there. It reads four production codes and one of
our own, and argues for less than any of them.

**Notation.** Throughout, `ARC1/CQS[3]` is a *selector*: `/` separates
assembly-path components and `[n]` is a 1-based ordinal among matches. It is
never spelled `CQS.3`, because a dot is a legal character in real element names
(`MQXA.1L5`) and would collide on the first imported MAD-X deck. The reasoning
is in §5a; the notation is used from here on so the note reads in one voice.

## 1. The finding that organises everything

**Every one of these codes separates the composition *language* from the
expanded *lattice*, and tracks only the expanded one.**

Nesting, reflection and repetition are all constructor syntax. They exist to let
a human write a ring without typing 3000 elements. None of them survives into
the object that gets tracked — that object is flat in all four codes.

| | composition | tracked object |
|---|---|---|
| MAD-X | `LINE` with `-`, `n*`, nesting; or `SEQUENCE` with `at=` | flat expanded sequence |
| Bmad | `line = (...)` with `-`, `--`, `n*`, nesting, slices | flat lattice, elements indexed from 0 |
| elegant | MAD-8 `LINE` syntax, shared lineage with MAD-X *(inherited, not separately verified)* | flat |
| AT | none — a Python/MATLAB list, composed with native `+` and `*` | `class Lattice(list)` |
| JuAcc | `*`, `-`, `^` on `Sequence`; nesting **retained** with a `Depth` field | partially expanded, caller's choice |

JuAcc is the outlier: it is the only one that keeps the tree alive in the tracked
object and offers partial expansion. That is the design decision to examine.

## 2. Reflection is not reversal, and the codes are emphatic about it

This is the single easiest thing to get wrong, and it is worth stating before
any syntax is chosen.

Bmad:

> It is important to keep in mind that line reflection is not the same as going
> backwards through elements. For example, if an `sbend` or `rbend` element is
> reflected, the face angle of the upstream edge is still specified by the `e1`
> attribute and not the `e2` attribute.

MAD-X, independently:

> A minus prefix causes reflection, i.e. all elements in the sub-line are taken
> in reverse order. **Physical elements are not reflected head-to-tail**, hence
> a negative repetition count for a single element is treated as positive.

So `-line` reverses **order only**. An `sbend` with `e1 = 0.1, e2 = 0` keeps
`e1 = 0.1` after reflection, and MAD-X's `-2*c` on a bare element expands to
`c, c` — the sign is simply discarded.

Going *backwards through* an element is a separate, much larger feature. Bmad
spells it `--`, gives reversed elements a local `z`-axis opposite to `s`,
requires a **reflection patch** between reversed and unreversed regions, and
warns that it "is generally only useful ... where there are multiple
intersecting lines with particle beams going in opposite directions". Bmad also
documents the cheap escape, which is what most users actually want:

```
b00:     bend, angle = 0.023, e1 = ...
b00_rev: b00, angle = -b00[angle], e1 = -b00[e2], e2 = -b00[e1]
```

**Recommendation.** Implement reflection (order only). Do not implement
orientation reversal. Say so in the docstring in one sentence, because a user
who reflects an arc containing asymmetric bends and expects the faces to swap
will otherwise be quietly wrong — and Octopus now has plenty of asymmetric
elements: `e1/e2`, `fint1/fint2`, `hgap1/hgap2`, `hface1/hface2`,
`kill_ent_fringe/kill_exi_fringe`, and entrance-referenced misalignments under
`misalign_convention = :madx`.

## 3. On `Depth`: over-design, and the reason is structural

JuAcc's `Sequence` carries `Depth`, auto-computed as one more than the deepest
sub-sequence, and `flatten(seq, dep)` expands only sub-sequences deeper than
`dep`. The question asked was whether this is over-design. It is, for three
reasons in increasing order of weight.

1. **No production code does it.** All four expand fully. Bmad keeps *line
   definitions* around so you can slice `line1[b:d]` later, but the lattice it
   tracks is flat and index-addressed.

2. **It is a stored invariant that mutation can break.** `Sequence` is mutable
   and `setindex!` will happily place a deeper sub-sequence into a line without
   updating `Depth`. The constructor validates; assignment does not. Derived
   data with a maintenance obligation is a liability unless it buys speed, and
   `depth(seq) = 1 + maximum(depth, subs; init=0)` is cheap enough to compute on
   demand.

3. **It conflates two things that should be separate**: how a lattice is
   *written*, and what a group of elements *is*. See §3a — the second is a real
   requirement, and nesting is the wrong mechanism for it.

### 3a. Physical assemblies are the real requirement

An earlier draft of this note dismissed partial expansion as a display concern.
That was wrong, and the counter-example is decisive: a RHIC CQS module
(corrector–quadrupole–sextupole) or a cryomodule is a **physical assembly**. It
is aligned as a unit, surveyed as a unit, powered as a unit and replaced as a
unit. An engineer asks for `ARC1/CQS[12]`, not for a standalone quadrupole that
happens to sit inside one. Misalign the cryostat and every magnet in it moves
together. That is physics, not presentation, and any beam-line design that
cannot express it is inadequate.

The question is therefore not *whether* to support assemblies but *how*. All
three reference codes support them, and **none uses nesting**:

| code | mechanism | shape |
|---|---|---|
| Bmad | `girder`, a lord element: `g1: girder = {q1, s1, c1}` | a first-class element naming its slaves, with its own orientation and origin-shift transforms, so moving the girder moves the slaves |
| AT | `GS`/`GE` marker elements bracketing the group; `getMagGroupsFromGirderIndex` returns index ranges | flat lattice, group = contiguous index range |
| AT | `MagNum`, a tag shared by all slices of one physical magnet | flat lattice, group = equal tag |

Flat-plus-grouping beats nesting here for a reason that is an engineering fact
rather than a software preference: **real groupings cross-cut**. A RHIC magnet
belongs to a cryostat, a power-supply chain, a survey monument and a sector, and
those partitions do not nest inside one another. A tree gives you exactly one
hierarchy and forces every other grouping to be expressed some other way. Tags
give you as many as the machine has. Nor are all groups contiguous — a
power-supply chain generally is not — and a subsequence cannot express a
non-contiguous set at all.

There is a second, quieter cost to nesting: every consumer must decide what to
do about levels. A half-expanded lattice is one that some code paths must
re-expand and others must not, which is a branch in every function that touches
a line. Flat plus a query is uniform.

**But nesting is the right way to *write* a lattice**, and that should not be
lost. The synthesis is to keep the ergonomics and drop the structure:

> **Construct nested; expand flat; stamp provenance.**

Writing `cqs = BeamLine("CQS", [corr, quad, sext])` and then
`arc = BeamLine("ARC1", [cqs, dip, cqs, dip, ...])` is exactly how an engineer
thinks. Expansion flattens it, and each expanded entry records the assemblies it
came from, addressable as the path `ARC1/CQS[3]` (§5a). Then
`find_entries(line, sel"ARC1/CQS[3]")` returns that module's entries,
`find_entries(line, sel"ARC1")` the larger span, a misalignment applied to
an assembly applies to its members, and additional cross-cutting groups
(power supply, survey monument) are extra tags rather than a second, conflicting
tree. No `Depth`, no partial expansion, no half-expanded object.

What this gives up is replacing a whole module *in place* after expansion, which
a live tree makes a one-line substitution and a flat lattice makes a splice.
That is a construction-time operation; rebuild the line.

## 4. On the operator zoo: half over-design

Bmad and Tao carry a large query and manipulation vocabulary. Judged against
what a Julia package needs, most of it is Bmad solving a problem Julia does not
have: MAD-X and Bmad had to invent a lattice *language* because their input is a
text file. Julia's input is Julia. `vcat`, `reverse`, `repeat` and comprehensions
already exist and are already known to the user.

So the recommendation is to add almost nothing:

| operation | proposal | why |
|---|---|---|
| concatenate | `vcat` / `*` | already means this |
| reflect | `reverse` | already means this; **order only**, per §2 |
| repeat | `repeat` | already means this |
| nest | plain nesting in the constructor, expanded immediately | matches all four codes |

JuAcc's `^` for repetition with binary exponentiation is a good instinct applied
where it cannot pay: a lattice repeat count is small and the result is `O(n)`
elements regardless, so `repeat` is clearer at identical cost. And JuAcc's `*`
returns a bare `Vector` rather than a `Sequence`, silently dropping the name —
whatever operators are chosen, they must be closed over the type.

## 5. On search: needed, but one selector instead of many

JuAcc has `getIndexByName`, `getIndexByClass`, `getIndexByRegex`, each with
`first`/`last` keyword variants — six behaviours across three functions with
near-identical bodies. Bmad/Tao go further with a match language.

AT gets this right with **one** concept. `Refpts` accepts an index, a boolean
mask, an element type, a name pattern, or a callable, and every selection-taking
function accepts a `Refpts`. One idea, uniformly applied.

**Recommendation:** a single `find_entries(line, sel)` where `sel` dispatches on type —
`String` (exact name), `Regex` (pattern), `Type` (element class), `Function`
(predicate) — returning indices. Everything else composes from it with base
Julia: `first(find(...))`, `last(find(...))`, `line[find(...)]`. The `first`/`last`
keyword pairs disappear.

### 5a. A selector, in the XPath sense

`find_entries` is a selector, and the addressing problem of §3a is a path problem, so
the two should be one thing. The shape to borrow is **XPath's**, not CSS's:
`/` for hierarchy and `[n]` for a positional predicate is exactly
`ARC1/CQS[3]`. CSS's power lives in combinators over a genuinely attributed
tree; what we have is a provenance chain, which is what XPath addresses.

**`CQS[3]`, not `CQS.3`.** Real element names contain dots — `MQXA.1L5`,
`MB.A8R1` — so a dot as ordinal separator collides with the names of any lattice
imported from MAD-X. Brackets cannot collide. `[n]` is 1-based, matching XPath,
CSS `:nth-child`, and Julia.

**The idea worth borrowing is not the syntax.** It is that a selector is a
first-class *value*: written once, stored, passed around, reused, composed.
`arc_quads = sel"ARC1//QuadrupoleSpec"` should be a thing a user keeps in a
variable, not a string re-parsed at every call site. In Julia that argues for a
string macro over a runtime string — `sel"ARC1/CQS[3]"` parses once, at
expansion, with a real error message pointing at the offending character.

**Path and tag must coexist**, and this is the one place §3a and a path syntax
pull against each other. A path implies a single hierarchy; §3a argued that real
groupings cross-cut. Both are true and they describe different things:

- the **path** is construction provenance — the assembly nesting the lattice was
  written with, and there is exactly one of those;
- **tags** are everything else — power-supply chain, survey monument, sector —
  and there are as many as the machine has.

So the selector needs both, and they compose rather than compete:
`ARC1/CQS[3]` for provenance, something distinct such as `@ps7` for a tag, and
an intersection when both are given.

**Where the cliff is.** CSS earns its combinators (`>`, `+`, `~`), its
pseudo-classes and its attribute operators because it addresses documents
written by other people. A lattice is addressed by the person who wrote it. The
grammar that pays for itself here is small: a path separator, a descendant form,
an ordinal, a wildcard, and an element type. Attribute predicates
(`[k1>0]`) are the first thing to leave out and the first thing to add if
demand appears — a `Function` selector already covers it without grammar.

## 6. What actually justifies a container

Earlier discussion nearly concluded that names plus free functions over a tuple
would do, since `s` positions, one-turn maps and Twiss are all functions and
need no type. The `aperture_s` work reinforced it: that needed a function over
the tuple, nothing more.

AT settles the question. Its `Lattice` is `class Lattice(list)` — element access
is *just a list* — and what it adds is `name`, `energy`, `particle`,
`periodicity`, `harmonic_number`, `beam_current`. **The container exists for the
state that belongs to no element.**

That is the criterion, and Octopus meets it: a design momentum or reference
energy is a property of the line, not of any magnet in it, and today it has
nowhere to live. Note also `periodicity` — AT stores one cell and a repeat count
rather than expanding a 16-fold-symmetric ring, which is a cheaper representation
than nesting and worth remembering, though it interacts with tracking and should
not be in a first version.

## 7. Proposed design

```
BeamLine
  entries    flat Vector of specs and in-line hooks, fully expanded
  name       String
  assemblies provenance per entry: which named groups it belongs to
  <lattice-level properties, added as consumers appear>
```

- **Flat, expanded at construction.** Nesting, reflection and repetition are
  constructor arguments, resolved immediately. Nothing nested survives — but
  expansion **stamps each entry with the assemblies it came from** (§3a), so a
  CQS module or a cryomodule stays addressable as a unit, and cross-cutting
  groups that no tree could express are just further tags.
- **Entries, not elements.** The tracking plan already accepts in-line
  `ScheduledObserver`s, and observers currently have no identity scheme. If the
  line names entries, element naming and observer naming are one problem.
- **Spec layer only.** `BeamLine` compiles to the same tuple
  `_build_tracking_plan` consumes today, exactly as `ElementSpec` compiles to a
  runtime object. Type stability, plan caching and the GPU path are untouched. A
  `BeamLine` iterated *during* tracking would be the failure mode to avoid.
- **`s` computed and cached**, extending `_aperture_s_positions` to all entries.
- **`find_entries(line, sel)`** as §5, with an assembly name as one more thing `sel`
  accepts — the engineer's `find_entries(line, sel"ARC1/CQS[12]")` and the physicist's
  `find(line, QuadrupoleSpec)` are the same call.
- **An assembly is a legitimate misalignment target.** This is what Bmad's
  girder buys and it is the point of naming assemblies at all: displacing a
  cryostat displaces its magnets together. Octopus already composes
  misalignments outside the element (`_misalignment_wrap`), so applying one to a
  span of entries needs no new element type — but the *survey* implication (a
  girder has its own orientation and origin) is the geometry layer again, and
  only the 1D part should be attempted first.
- **Twiss as the first real `Analysis`**, consuming a `BeamLine`. `Analysis` is
  one of the seven core objects in `AGENTS.md` and has only `PlaceholderAnalysis`
  behind it; this is the consumer that keeps the container from being
  speculative.

**A line is an `ElementSpec`, not a new core object.** `AGENTS.md` lists
*categories* — `ElementSpec`, `TrackingMethod`, `Contract`, … — not instances.
`QuadrupoleSpec` is `ElementSpec{:quadrupole}` and is not listed; a line is a
composite element and belongs in exactly the same place. Nothing is added to the
core-object list.

This is worth more than a documentation decision, because being an `ElementSpec`
means a line inherits the whole element apparatus for free:

- **Assembly misalignment is already implemented.** `_misalignment_wrap` wraps
  whatever `compile_runtime` produces, so a line with `x_offset` set is a frame
  change in, the whole assembly tracked, and a frame change out. That is Bmad's
  `girder`, at zero cost, using the machinery the misalignment work already
  validated against PTC.
- Metadata, `element_help`, the parameter-effectiveness contract and knob
  resolution all apply without new code.
- Nesting a line inside a line is just an element inside a line.

**The tension this creates, and it needs deciding before implementation.** §1
argued for flat expansion, and a line that is misaligned *as a unit* cannot be
flattened into independent placements — the wrap has to enclose the whole
composite. The two can coexist:

- a line with no line-level state expands flat, as §1 wants, and its entries
  keep their provenance tags;
- a line that carries a misalignment (a real cryostat) compiles to one composite
  runtime, wrapped once.

That is a defensible rule, but it means "is this line flattened?" has an answer
that depends on its parameters, and consumers that walk entries need to know
which they are looking at. Resolving this cleanly is the main open design task
left, and it should be settled on paper before code.

### 7a. A line holds placements, not specs

Assembly provenance cannot live on the spec, and the reason is ordinary Julia:

```julia
line = BeamLine("ARC1", [qf, d, qf, d])   # both entries are the SAME object
```

`qf` is one object appearing twice. Two occurrences of it belong to different
assemblies, sit at different `s`, and may be misaligned differently, so anything
per-occurrence stored in `qf.params` would immediately collide with itself. This
is not a Julia quirk — it is why Bmad separates element *definitions* from the
expanded lattice's `ele` array, and why MAD-X separates element definitions from
sequence occurrences. Both codes made the same split for the same reason.

So the line is a vector of **placements**, each holding a reference to a spec
plus what belongs to that occurrence:

```
LineEntry
  spec        reference; shared freely between placements
  path        assembly provenance, e.g. ARC1/CQS[3]
  tags        cross-cutting labels (§3a)
```

This also dissolves the invariant problem that prompted the immutability
question. Index ranges stored on the line — "CQS[3] is entries 41:43" — break
the moment anything is inserted. Provenance carried *by the placement* survives
any reordering, insertion or deletion, because each placement knows what it is
without reference to its neighbours. The line can then be an ordinary mutable
`Vector`, consistent with the rest of the codebase, with nothing to keep in sync.

It is the same choice AT makes with `MagNum` — a tag on the element rather than a
range held elsewhere — and the same one Bmad's `girder` makes by naming its
slaves rather than bracketing an index span.

### 7b. When two `qf`s should be one object, and when they must not be

Sharing is sometimes exactly right and sometimes exactly wrong, and the two cases
are not in tension once the question is asked properly:

- **Design parameters should share.** Matching wants `qf.k1` tuned once for all
  hundred QFs in the ring. That is a magnet family on one power supply, and it
  is the common case.
- **Error parameters must not share.** Every physical magnet has its own
  misalignment. Two occurrences with a common `x_offset` would be a fiction.

The reference codes split along exactly this line and always have. MAD-X keeps
one element *definition* and puts alignment errors in a separate error table
keyed by sequence occurrence — `EALIGN` never touches the definition. Bmad copies
each definition into an independent lattice element and re-establishes sharing
where it is wanted through `overlay`/`group` lord elements. AT keeps independent
objects and recovers family operations through `FamName` plus selection.

**Julia makes this easier than any of them, because object identity already says
what the user meant:**

```julia
line = BeamLine("ARC", [qf, d, qf, d])          # one magnet family, shared k1
line = BeamLine("ARC", [QuadrupoleSpec(...), d,
                        QuadrupoleSpec(...), d]) # two independent magnets
```

MAD-X and Bmad see the token `qf` twice in a text file and must adopt a *policy*
about what that means. Here there is no policy to adopt: the same object is the
same object. So the rule is one sentence.

> **A parameter may live on the spec or on the placement. Placement wins.**

That is the entire mechanism. It is deliberately *not* a classification of
parameters: `k1` is not forbidden on a placement, nor `x_offset` on a spec.
Which one you reach for is guidance, not a rule —

| you want | write | effect of a later `qf.params[:k1] = 1.9` |
|---|---|---|
| the whole family retunes together | share `qf` | moves every placement |
| one magnet is different, full stop | `line[3].k1 = …` | leaves `line[3]` behind |
| one magnet follows the family **plus** a trim | a knob expression | moves it, trim included |

The middle row is worth stating out loud because it surprises people: an
override **detaches** that placement from the family permanently. That is right
for an alignment error and wrong for a trim supply, which physically is main bus
*plus* trim — so the third row exists, and it needs nothing new. `@knob_expr`
already builds deferred parameter expressions that `resolve_knobs` evaluates
inside `compile_runtime`; a trim quad is `main + trim3` as an expression and
tracks the bus by construction. Giving overrides delta semantics would have
duplicated a mechanism the codebase already has, and guarded by
`KnobEffectivenessContract` at that.

**Ordering constraint for the implementation.** The placement-over-spec merge
must happen *before* `resolve_knobs`, so that an override may itself be a knob
expression. Merging after would silently reduce overrides to plain numbers and
break the third row. This is cheap to get right and expensive to discover late.

Everything else falls out rather than needing machinery:

- Matching works with what already exists. `qf.params[:k1] = ...` bumps
  `_SPEC_EPOCH`, and every task holding that line recompiles at the next
  `execute!`. No family registry, no controller element.
- The family is recoverable without naming it:
  `findall(e -> e.spec === qf, entries)` is the family, by identity.
- Misalignment normally moves from the spec to the placement, since every
  physical magnet has its own. `_misalignment_wrap` reads `x_offset` and friends
  through `getparam(spec, …)` today; it would read the merged parameters instead.
  `compile_runtime(spec)` keeps its present meaning and gains a
  `compile_runtime(entry)` sibling that does the merge, so nothing existing
  changes.
- Backward compatible: `QuadrupoleSpec(x_offset=1e-3)` still works and means
  "every placement of this spec is misaligned identically" — a fiction for a real
  machine, but exactly what the code does today, so no lattice breaks.

**Not covered, and deliberately:** the case where two placements are literally
the *same physical magnet* traversed twice — a recirculating linac, or an
interaction region shared by two rings. There even the errors are shared, because
there is one magnet. Bmad calls this `multipass` and treats it as a distinct
feature; so should we, later.

## 8. Deliberately deferred

- **Orientation reversal** (`--`). §2. Needs an orientation flag, a reversed
  local `z`, and reflection patches at every boundary. Wait for an
  interaction-region case.
- **Line slices** (`line1[b:d]`). Falls out of `find` plus ordinary indexing
  once names exist; no syntax needed.
- **Periodicity**, multipass, superposition. Each is a real feature of a mature
  code and none is needed to make Twiss work.
- **`SEQUENCE`-style `at=` positioning.** MAD-X supports both; the positional
  form mainly serves lattice files written by other tools. Importers can expand
  to the ordered form.
- **A lattice input language.** Julia is the input language.

## 9. Decisions

All settled. Recorded here with the reasoning, since a later reader will want to
know what was rejected as much as what was chosen.

1. ~~Does `BeamLine` join the core-object list in `AGENTS.md`?~~ **No.**
   `AGENTS.md` lists categories, not instances, and `QuadrupoleSpec` is not
   listed either. A line is an `ElementSpec` — a composite element — and that
   framing earns more than it costs (§7): assembly misalignment becomes
   `_misalignment_wrap` around a composite runtime, which is Bmad's `girder` for
   free. The open work it creates is when a line stays composite and when it
   flattens; see §7.
2. ~~Which lattice-level properties are real *now*?~~ **Moot.** The question was
   whether a container could be justified on AT's criterion of state belonging to
   no element. Two things overtook it: the assembly registry of §3a is that
   state, and decision 1 makes a line an element rather than a new kind of
   object, so it needs no separate justification. Reference energy can arrive
   later as an ordinary parameter.
3. ~~Mutable or immutable?~~ **Settled: mutable, like everything else here.**
   An earlier draft recommended immutability to stop derived data drifting, which
   was the wrong tool and would have fought the codebase. `ElementSpec` is a
   `struct` wrapping a `Dict`, so it is only shallow-immutable, and in-place
   parameter mutation is *deliberately supported* — every mutation bumps
   `_SPEC_EPOCH` so tasks built from that spec recompile at the next `execute!`.
   Deep immutability is unreachable while a spec holds a `Dict`, and unwanted.

   The real requirement was never immutability but that **no stored value can
   silently disagree with its source**, and there are two better answers:

   - Cache nothing derivable. `s` is one pass summing `L`; `_aperture_s_positions`
     already computes on demand and nothing has complained. If a cache is ever
     needed, key it on `_spec_epoch()`, which is the pattern already in use.
   - Store what is *not* derivable — assembly provenance — so that it cannot go
     stale, which is §7a.
4. ~~Can an entry belong to more than one assembly at once?~~ **Yes.** A
   placement carries a *set* of tags, not one, which is what makes cryostat,
   power-supply chain, survey monument and sector all expressible at once —
   the thing no tree can do (§3a).
5. ~~Should assemblies nest in their names or stay flat labels?~~ **Settled:
   both, and they mean different things** (§5a). The path is construction
   provenance, of which there is one; tags are cross-cutting labels, of which
   there are as many as the machine has. The selector takes either and
   intersects when given both.
6. ~~How much selector grammar?~~ **As proposed in §5a and no more:** path
   separator, descendant, ordinal, wildcard, element type. No attribute
   predicates — a `Function` selector covers them with no parser and no
   semantics to document.
7. ~~String macro or runtime string?~~ **Macro.** `sel"ARC1/CQS[3]"` parses
   once, reports errors against the offending character, and makes a selector a
   value that can be stored and reused rather than a literal re-parsed at every
   call site.

## 10. Expansion is a task-level normalisation

Decision 1 leaves one question: when does a line stay a composite runtime, and
when is it flattened? It matters because a line misaligned as a unit *cannot*
flatten — the wrap has to enclose the whole assembly.

The answer is to stop treating it as a property of the line at all.

> **Every line compiles the same way. The task then dissolves any line that
> carries nothing of its own, and leaves intact any line that does.**

This is not a new mechanism: `_element_tuple` already flattens nested tuples on
the way into a task. A plain structural line — an arc, a cell — carries no
parameters of its own and dissolves, its entries keeping individual provenance
and `s`. A cryostat with `x_offset` survives as **one entry** with an `s`-span,
which is what it physically is.

What this buys is that no consumer ever has to ask whether something was
flattened. Everything walks the expanded entries; a girder is simply an element
that happens to be long, indistinguishable in kind from a thick magnet. The
half-expanded object that §3a warned about — the one some code paths must
re-expand and others must not — never exists.

Two consequences, both accepted:

- **No in-line hooks inside a composite assembly.** A BPM inside a cryostat
  cannot be a line-level `ScheduledObserver`, because the assembly is one entry.
  Place it outside the composite, which is where a real pickup sits.
- **The assembly's own survey stays 1D.** Misaligning a straight cryostat is
  exact today through `_misalignment_wrap`. One containing bends needs the 3D
  geometry layer to place its contents relative to the girder frame, and that
  remains the deferred item it has been throughout
  ([`misalignment_and_patch_maps.md`](misalignment_and_patch_maps.md) §8).

With this, the design is complete on paper.
