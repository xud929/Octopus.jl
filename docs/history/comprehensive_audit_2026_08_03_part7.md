# Comprehensive Audit — 2026-08-03, part 7

> ## Start here
>
> **Nothing in this report is fixed, and almost nothing in it is verified by me.**
> It is a faithful record of what four sub-agents found in the last ~4,100
> unaudited lines, written at the point where the session ran out of room to keep
> verifying. Treat every entry as a **lead with a reproduction**, not a finding.
>
> | read | why |
> |---|---|
> | **§2** | the two items to take first — one is memory corruption, one is the consumer-side twin of a defect fixed in part 6 |
> | **§1** | the full list, by file |
> | **§4** | what "confirmed by an agent" has empirically meant in this series: ~60% survive verification |
>
> **Follow-up (2026-08-04):**
> [part 8](comprehensive_audit_2026_08_04_part8.md) verified and fixed
> **T1, T3, T4, T5, K1 and G1**. All six survived verification — but §2's
> "one root cause" framing below was wrong (it is two mechanisms: nested
> vectors for T3/T4, `LineEntry` for T1/T5), and G1 was narrower than the
> truth (*any* non-Float64 rep threw, not only mixed precision). The original
> text is kept unedited below, per this series' rule.

Seventh pass. Regions: `gaussian_pic.jl` (850), `gaussian_pic_cuda.jl` (1,182),
`Tasks.jl` (762) + `BPMObserver.jl` (240), `Knowledge.jl` (885) +
`Registry.jl` (209). Four agents, each with a hypothesis drawn from the defect
classes parts 1–6 established. **All four reported.** Between them: 26 claimed
findings, of which none has been independently verified by me.

**With this pass, every line of `src/` has been read by someone.** The ledger is
explicit that most of this one was read by agents rather than by me.

## 1. What was found, by file

### `Tasks.jl` — 11 confirmed by the agent, the largest single haul of the series

| # | severity claimed | finding |
|---|---|---|
| T1 | **Major** | **the knob epoch never fires for any task built from a `BeamLine`.** `_has_knob_parameters` has no `LineEntry` method and `LineEntry` is not an `ElementSpec`, so `knob_dependent = false` forever and the recompile gate short-circuits true. `set_knob!` then changes nothing while `knob_value` reports the new number. This is the **consumer-side twin of R4**, fixed in part 6 on the producer side. |
| T2 | Moderate | the loss record's `fits` test omits the backend, against its own docstring; reusing a task across CPU and CUDA reps gives a hard `KernelError` |
| T3 | **Major** | **a nested `AbstractVector` in a line makes the aperture walkers disagree**, so `counts` is undersized while ids are assigned for every aperture — an unchecked `@inbounds`/`CUDA.@atomic` write past the end. Reported symptom: heap word corruption *and* a collimator's kills reported as `unattributed`, i.e. the diagnostic meant to flag blow-ups fires on ordinary collimation |
| T4 | Moderate | the same nested vector silently zeroes aperture arc length, so every loss record after it reports the wrong `s` |
| T5 | Moderate | a task built from a `BeamLine` declares **no contracts and no analyses** — same root cause as T1/T3/T4 |
| T6 | Moderate | a failed `execute!` is not resumable: `next_turn` is correctly not advanced, but `rep` is mutated and observer state retained, so a resumed run produces duplicate turn labels. Also, the loss log is written outside the failure path, so a crashed run writes no loss file — the one artifact you want after a crash |
| T7 | Minor | one throwing finalizer strands the others; buffered observer measurements silently lost |
| T8 | Minor | BPM noise reads the live global RNG seed rather than the `TrackingContext` snapshot, falsifying its own docstring's purity claim |
| T9 | Minor | a BPM read twice in one turn draws **identical** noise — the counter key has no occurrence component, though `x_noise` is documented as "per-reading" |
| T10 | Minor (perf) | `_scheduled_turns(::EveryNSteps)` enumerates from `schedule.start`, so cost grows with absolute turn: 0.004 ms at `first_turn=0`, **29.5 ms at 1e8** — penalising exactly the chunked long run `first_turn` exists to serve |
| T11 | Minor | `rng_id` is read but absent from the BPM option schema, so `configuration_report` never shows the one field determining whether two BPMs share a noise stream |

### `gaussian_pic.jl`

| # | severity claimed | finding |
|---|---|---|
| G1 | **Major** | hard `MethodError` on a mixed-precision beam (`Float32` rep with `Float64` params or explicit `kbb`), because the profile buffers use the promoted type while the scalars are converted with `eltype(source.x)`. Plain `PICPoissonSolver` survives all four cases; only the hybrid breaks |
| G2 | Minor | CPU and CUDA neutralise to different quantities (deposited grid charge vs particle count), so the docstring's "CPU/CUDA bit-parity" cannot hold for the default `neutralize=true`. Measured `4.44e-16` relative — the claim is the defect, not the number |
| G3 | Minor | `configuration_report` says the coupled subtraction is "CPU path only", contradicted by this file's own docstring and by the CUDA route that implements it |
| G4 | Minor | the docstring promises six options are "forwarded unchanged" that are in fact rejected — including the three it names explicitly as "the CUDA execution options" |

### `gaussian_pic_cuda.jl`

| # | severity claimed | finding |
|---|---|---|
| C1 | Minor | the CUDA uncoupled neutralisation amplitude drops the CPU's `sgx*sgy > 0` guard, so a degenerate profile yields `Inf` and poisons the charge plane. The **coupled** branch has the guard — the omission is specific to one branch |
| C2 | Minor | a non-commutative `choose` passed to `mapreduce`, which CUDA.jl assumes is commutative: the moment anchor is whichever element the reduction tree reaches first. Roundoff-only, but it falsifies a claimed bit-parity on two non-default routes |
| C3 | Minor | PIC timing and cache stats are silently inert on two of the three CUDA routes — a non-default diagnostics request accepted and dropped |

Also **clean**, and worth recording: every reduction in `gaussian_pic_cuda.jl` is
confined to an already live-filtered slice index set, so the mask that was
missing in `spectral_cuda.jl` is correctly *redundant* here rather than absent.
And part 5's S18 fix was verified working — the bare-`collide!` warning sits in
the single funnel all three Gaussian routes pass through.

### `Knowledge.jl` + `Registry.jl` — the hypothesis was "metadata that lies", and it landed

This layer exists so agents and users can trust it *without reading the source*
(`AGENTS.md`), which makes a false entry uniquely damaging. The agent injected 13
deliberate metadata defects and diffed the validator's output.

| # | severity claimed | finding |
|---|---|---|
| K1 | **Major** | **`RBendSpec` is exported, user-facing, and carries five PTC reference cases — and has no `ElementMeta`.** Every query swallows the miss and returns empty, so `required_contracts(RBendSpec) == []` and `element_help(RBendSpec)` prints a confident, well-formed report claiming no contracts, no tracking methods, and an invented kind `:RBendSpec` that does not exist. The *instance* resolves correctly, so the lie is specific to the type-level query. An agent asking "which contracts apply?" is told "none" about a PTC-validated element |
| K2 | Moderate | `:thin_dipole`, `:thin_quadrupole`, `:thin_sextupole` declare `PTCConsistencyContract` but have **no reference case**, so the claim is never exercised — and what a PTC comparison would catch is exactly their per-constructor keyword folding (`k0l→knl[1]` etc.) and a documented sign convention. The neighbouring kickers correctly omit the claim, so the codebase knows how |
| K3 | Moderate | metadata can advertise a tracking method the implementation cannot execute. The validator's check is **circular**: `supported_tracking_methods(T)` returns `meta.tracking_methods` (verified `===`), so it asks whether a list's elements are in itself, and `runtime_types` is auto-populated from that same list. Demonstrated with a throwaway spec that validates clean and then throws `MethodError` on `compile_runtime` |
| K4 | Minor | `ElementMeta.runtime_type` (singular) is stored and **never read** — dead storage that can silently disagree with `runtime_types` |
| K5 | Moderate | query functions return **live internal state**, not copies. `push!(required_contracts(ElementSpec{:sbend}), Int64)` permanently corrupted the registry in-process and validation still passed — inconsistent with the deliberate `copy` discipline 200 lines earlier |
| K6 | Minor | `Registry.jl` crashes on metadata the Knowledge layer explicitly permits (`friendly_constructor = nothing`), so snapshot generation and the CI assertion die rather than report |
| K7 | Minor | three registry sections are hand-written prose in a file whose docstring claims derivation "from Julia's type graph rather than edited as external metadata" |
| K8 | Moderate | `:line` advertises **no** tracking methods yet silently accepts every one, because `compile_runtime(spec::ElementSpec{:line}, args...)` discards the request — against `AGENTS.md`'s "Do not accept silently ignored non-default requests" |

**The headline number: the element validator caught 1 of 13 injected defects.**
It does not check that a declared contract is a contract, that a declared
tracking method is one, that a declared default matches the constructor, or that
a declared parameter is read. `validate_configuration_metadata` is substantially
stronger — it *does* compare declared defaults against real values — but its gap
is enumeration: every type it inspects is a hardcoded literal, and a fabricated
`LyingSolver` with a wrong default and an invented consumer passed it.

Also found **sound**, and worth as much: every declared tracking method for all
30 registered kinds actually compiles (checked by running `compile_runtime` for
each); every declared contract is a real subtype with a runnable `validate`;
every declared analysis is `PlaceholderAnalysis`, exactly as `AGENTS.md`
requires; the physics-keyword vocabulary is genuinely enforced; and the snapshot
test is non-vacuous, deterministic, and does run in CI. The `:liar` scenario is
latent, not present.

## 2. Take these two first

**T3 — memory corruption.** An unchecked write past the end of a `Vector{Int32}`,
on both backends, reachable from an ordinary nested-vector line. Everything else
here is a wrong number or a wrong message; this one is undefined behaviour.

**T1 — the knob epoch never fires for `BeamLine` tasks.** Part 6 fixed the
producer side (a retype that did not bump the epoch). This is the consumer side,
and it is broader: for a whole class of task, *no* knob change ever recompiles.
`knob_value` reports the new number while tracking silently uses the old one.

T1, T3, T4 and T5 share one root cause — `LineEntry` is not an `ElementSpec`, and
five walkers over the runtime line handle that fact inconsistently. The agent
notes two of the five *do* carry `LineEntry` methods, so the case was known and
handled in some places and not others. Fixing the root cause plausibly closes
four findings at once, which is the first thing to check.

## 3. Verification status, stated plainly

I verified **none** of §1 independently. I attempted T1's reproduction and my
probe errored before producing a result; I did not get back to it.

That matters because of §4. Every entry carries the agent's own reproduction, and
most are the kind that can be re-run in minutes — that is what the next session
should do first, before changing any code.

The one thing I did check from this wave was C1's premise, and it held: the CPU
uncoupled path has `if neutralize && sgx * sgy > zero(T)` while the CUDA
uncoupled path divides unconditionally, and the CUDA *coupled* path has its own
`sg != 0` guard. That is an asymmetry in the source, whatever its reachability.

## 4. Why this is a queue and not a findings list

Across parts 4–7, agent claims have come out four different ways:

- **right as stated** — S18, S20, R1, R6;
- **right, with the stated reason wrong** — R3, where the failure is a load-mode
  asymmetry rather than a permanent one, and the reason is what determines the
  correct fix;
- **wrong** — R5, which one docstring dismissed; the "latent trap" that was
  identical on both backends by design; the missing dropped-particle accounting
  that cannot matter because the option is rejected on that backend;
- **narrower than the truth** — S19, reported as CUDA-only, actually reachable on
  CPU for a different reason.

Roughly 60% survive. A pass that fixed §1 on the agents' word would have written
several unnecessary changes into physics paths, and this series has the numbers
to say so rather than the intuition.

## 5. Handoff

1. **T3** — memory corruption; then check whether the `LineEntry` root cause also
   closes T1, T4, T5.
2. **T1** — verify with the reproduction, then fix.
3. **G1** — hard failure on a supported precision combination.
4. **K1** — `RBendSpec`'s missing `ElementMeta`. Small fix, and it stops the
   knowledge layer confidently misinforming an agent about a PTC-validated
   element. Then **K3/K5**, which are what let K1-shaped problems go unnoticed:
   a circular validator check and query functions handing out live state.
5. The remaining part 6 §5 items: R2, R7–R12, the Symbolics package extension,
   and a guard against method overwrites (part 6 §8.7).

### Coverage, finally

`src/` is 32,195 lines. With this pass every file has been read by someone.
Roughly 60% was read by me directly across parts 1–5; the rest, chiefly parts 6
and 7, by sub-agents against briefed hypotheses. The distinction is kept because
a coverage claim that hides its provenance is not checkable, and this series has
already had to correct its own ledger twice.
