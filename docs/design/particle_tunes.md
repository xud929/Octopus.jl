# Persistent particle tunes in a linear six-dimensional map

Design reviewed 2026-10-30 by the integrator and independent core/validation
reviewers before implementation. The [campaign record](../history/audit_particle_tunes_2026_10_30.md)
records implementation, measurements, review corrections and remaining
boundaries. This note records the agreed decisions; the record identifies
which checks actually executed.

## Experiment and decision

The experiment separates phase mixing from nonlinear driving terms. Replace a
nonlinear element's tune footprint by fixed particle labels
`(nux[i], nuy[i], nuz[i])`, while retaining a common linear normalizing basis.
A particle's coordinates evolve, but its assigned tunes do not change. A
coordinate function can preserve initial tune/action correlations; direct
arrays can preserve the correspondence of previously measured tunes to the
same particles. Sampling a histogram preserves the distribution and any
specified joint correlations, but does not itself preserve tune/action
correlations. This model does not reproduce nonlinear resonance driving terms,
a changing amplitude detuning, or the self-consistent response of a beam-beam
interaction. Comparing those models is a scientific study beyond proving this
implementation correct.

Reuse `Linear6DSpec` and `ElementSpec{:linear6d}`. Add the optional
`particle_tunes` input and compile its active form to `ParticleLinear6D`, a
runtime distinct from the existing `Linear6D`. Do not add another element kind,
tracking method, or execution policy. The ordinary form keeps its current
matrix construction, runtime, and tracking path. The active variant initially
supports Float32 and Float64, with both typed constructor spellings; other
numeric types are refused explicitly. The ordinary variant retains its
existing Number, complex-step, and automatic-differentiation behavior.

The active form supports the optics constructor. An explicit `matrix` together
with `particle_tunes` is rejected: a general symplectic matrix does not specify
a unique stable, labeled, normalized set of modes. A future matrix
factorization interface would require an explicit mode convention and is not
part of this change.

## Physics and coordinate conventions

For entrance and exit optics, define

$$
N_j=\begin{pmatrix}\sqrt{\beta_j}&0\\
-\alpha_j/\sqrt{\beta_j}&1/\sqrt{\beta_j}\end{pmatrix},\qquad
N=\operatorname{diag}(N_x,N_y,N_z),
$$

$$
A_{\rm in/out}=M_\zeta(\zeta_{1/2})\,
M_\eta(\eta_{1/2})\,C(R_{1/2})\,N_{1/2}.
$$

`M_zeta`, `M_eta`, and `C` are the existing canonical transformations in
`src/elements/linear6d.jl`, in exactly that order. `C` retains the current
transverse coupling convention. The Twiss normalization and ordered canonical
dispersion transformations are derived in
[the optics theory](../theory/twiss_dispersion.md), equations (T17) and
(D2)–(D8). The dispersion inputs are the canonical coefficients, not the
physical graph slopes `eta/h`.

For each particle,

$$
R(\nu_i)=\operatorname{diag}(R_2(2\pi\nu_{x,i}),
 R_2(2\pi\nu_{y,i}),R_2(2\pi\nu_{z,i})),\qquad
R_2(\mu)=\begin{pmatrix}\cos\mu&\sin\mu\\-\sin\mu&\cos\mu\end{pmatrix},
$$

$$
X'_i=A_{\rm out}R(\nu_i)A_{\rm in}^{-1}X_i. \tag{1}
$$

The periodic case uses one shared `A` and its inverse. Distinct entrance/exit
optics remain supported; it is incorrect to use the entrance basis twice.
Tunes are signed absolute phase advances in cycles per passage, not shifts
from `dmu`; stored values are not silently folded into `[0,1)`. Cached
trigonometry may reduce the finite tune modulo one before multiplying by
`2pi`, avoiding overflow for a large finite tune without changing its phase.
This preserves the
existing signed longitudinal phase convention. Omitted planes use
`dmu[k]/(2pi)`, assigned and frozen with the other labels.

Equation (1) is canonical symplectic for each fixed tune triple. Source
initialization is ensemble preparation, outside that map. In particular,
differentiating through an initial coordinate-dependent source is not the
symplecticity test of the subsequent fixed-label map. The runtime therefore
uses the existing `Symplectic6DMap`; tests freeze the labels when perturbing
coordinates.

## Source interface

Proposed public constructors and examples:

```julia
Linear6DSpec(; beta1, dmu, particle_tunes=nothing, rng_id=0, kwargs...)
Linear6DSpec{Float32}(; beta1, dmu, particle_tunes=nothing, rng_id=0, kwargs...)

# Any one, two, or three named planes; the remaining planes use dmu/(2pi).
Linear6DSpec(; beta1, dmu, particle_tunes=(nux=measured_nux,))
Linear6DSpec(; beta1, dmu,
    particle_tunes=(nuy=(x, px, y, py, z, pz) -> 0.31 + 0.02y^2,
                    nuz=-0.005))

# Independent one-dimensional distributions.
Linear6DSpec(; beta1, dmu, rng_id=stream,
    particle_tunes=(nux=TuneDistribution(dx), nuy=TuneDistribution(dy)))

# Joint source over a named subset; vector/tuple results follow this order.
Linear6DSpec(; beta1, dmu, rng_id=stream,
    particle_tunes=TuneDistribution(dxy; planes=(:nux, :nuy)))
Linear6DSpec(; beta1, dmu,
    particle_tunes=TuneFunction(f; planes=(:nux, :nuz)))

# Compose disjoint groups, for example a correlated pair and a fixed third.
Linear6DSpec(; beta1, dmu, rng_id=stream,
    particle_tunes=(TuneDistribution(dxy; planes=(:nux, :nuy)),
                    (nuz=-0.005,)))
```

All seven nonempty subsets of `(:nux, :nuy, :nuz)` are supported. A named
per-plane value is a finite real scalar, a one-dimensional array, a
six-argument Julia function, `TuneFunction(f)`, or `TuneDistribution(d)`.
Scalars are useful fixed overrides. `TuneFunction` makes callable structs
unambiguous and supplies the explicit plane list for a joint callback.
`TuneDistribution` supplies the explicit distribution protocol and plane list;
there is no heuristic that mistakes a callable density for a coordinate
function. In a per-plane NamedTuple, an omitted wrapper plane list is inferred
from the enclosing key. At top level wrappers require a nonempty plane tuple.
Explicit wrapper planes must agree with their enclosing key.

A tuple of declarations is canonicalized to disjoint source groups. Duplicate
or unknown plane names, overlapping groups, empty groups, an empty NamedTuple,
and unknown source types are errors. `nothing` is the only inactive spelling.
Source ordering does not change the assignment; named plane identity controls
RNG separation. Reusing a stochastic spec at two placements or tasks owns
independent tables but deliberately gives the same random realization when
seed, stream, epoch, global IDs and source masks coincide. Choose distinct
`rng_id` values for independent random realizations. Separate arrays in a NamedTuple can represent a correlated
joint sample: index correspondence, not a distribution wrapper, preserves
that correlation.

### Functions

A function is called as `f(x, px, y, py, z, pz)` using the physical stored
canonical coordinates at the actual element entrance, before multiplication
by `inv_A_in`. Positions are in metres and momenta have the framework's
reference-momentum normalization; these are not slopes, normalized actions,
or coordinates at the task's entrance. Upstream maps have already run.

For a single plane the result is a finite real scalar. For a joint group it
is a tuple or one-dimensional vector of the declared length, or a NamedTuple
whose keys exactly match the declared planes; NamedTuple values are selected
by name. Every result is checked before and after conversion to the runtime
numeric type. Reject complex values, Bool stand-ins, non-finite values,
wrong arity, wrong names, and conversion overflow. A custom function must be
deterministic and side-effect free, with no ambient random draws; stochastic
sources use the distribution protocol instead. External side effects in user
code cannot be rolled back.

Callbacks are evaluated once for each local particle when its placement
first initializes successfully. They run on host coordinate copies for a
CUDA beam; no callback enters device IR. This allows arbitrary ordinary Julia
code without requiring GPU-compatible closure captures. If any particle has
non-finite entrance coordinates and a coordinate source is present,
initialization is collectively refused before any callback or particle map
runs. The remedy is to place the element before the loss-producing section,
use coordinate-independent labels, or supply a finite initial ensemble. The
implementation does not invent a tune for a particle whose entrance point is
undefined.

### Direct arrays

An array has one value for every global macroparticle, including lost slots.
Its length must equal the resolved global particle count, checked when a beam
first binds. There is no `n_macro` argument on the element. Under MPI, a rank
copies the interval belonging to its stable global IDs; a rank-local array is
not guessed from its length. This version has no separate local-array mode.

Values are copied into owned tune storage before first tracking. Editing the
input array after successful binding cannot change assigned tunes. The source
is a preparation input, not a live knob: edits take effect only after an
explicit clear and reinitialization. Reusing measured arrays on a different
beam is scientifically meaningful only when the caller preserves the original
particle correspondence; equal lengths alone do not establish that fact.

### Distributions and histograms

The protocol is `rand(rng, d)`, where `rng` is an Octopus-provided,
per-particle `Random.AbstractRNG`. The result follows the same scalar/joint
shape rules as a function result. No `Distributions.jl` dependency is needed:
`Random` is already a dependency, and any distribution implementing that
method can participate. Unsupported sampler/RNG methods produce a named
initialization error; a sampler must consume only the supplied RNG and must
not reseed, retain, or share it. Document and exercise supported scalar
uniform, integer, normal, and bulk draws of the adapter; do not claim every
third-party sampler has been validated. The production tests include a custom
analytic distribution implementing this public protocol.

Provide `TuneHistogram(edges, weights)` as a dependency-free distribution.
A one-dimensional vector of edges and vector of weights is the concise 1D
form. The joint form takes a tuple of edge vectors and an array with size
`(length(edges[1])-1, ...)`. Edges are finite and strictly increasing;
weights are finite nonnegative bin masses with positive finite total mass.
Zero-mass bins are never selected. Choose a bin by its cumulative mass, then
sample uniformly within each of its coordinate intervals. Weights are masses,
not densities: unequal widths do not multiply them implicitly. Within-bin
sampling and the bin's joint weight preserve the specified piecewise-constant
joint density. Histogram dimensionality must match the named source group.
Copy input edges/weights so mutation cannot invalidate a prepared CDF.

Metropolis–Hastings is an external producer, not an implicit requirement of a
histogram. A custom distribution may implement it, or previously generated
samples may be passed as direct arrays. A chain's convergence is not certified
by the linear-map element.

## RNG key and preparation provenance

`rng_id=0` assigns a stream at spec construction only when at least one source
is stochastic, using the existing registry with a named `:particle_tunes`
consumer. An explicit nonzero ID is claimed under that consumer. Invalid
source structure is rejected before claiming. Nonzero `rng_id` with no
stochastic sources is refused as inactive; deterministic configurations do
not reserve streams. A raw stochastic `ElementSpec` must carry an explicitly resolved nonzero
`rng_id`; it refuses an unresolved zero rather than mutating the spec or
claiming a stream at compile time. Friendly construction claims once and
recompilation never allocates a fresh ID.

Capture the execution context's seed and RNG method on first successful
initialization, using existing `set_global_rng!` configuration. Bind those
values into the preparation receipt. Later changes to the global seed or
method do not alter existing tune tables. An explicit clear of initialized state advances the retained preparation
epoch and requests a fresh assignment under the then-current context. The
first epoch is zero; repeated clears before initialization do not advance it
again. Absolute tracking turn is not a sampling coordinate: two otherwise
identical fresh tasks starting at different turns produce the same labels.

The adapter keys each draw on `(seed, method, preparation_epoch, rng_id,
global_particle_id, source_plane_tag, draw_index)`. A source-plane tag is the
bit mask of its declared planes, so independent x/y/z streams differ and
reordering declaration groups does not reassign streams. Implement the last
two fields through checked injective packing in the existing counter RNG
component dimension:
`0x8000000000000000 | (UInt64(plane_mask) << 56) | draw_index`,
with zero-based `draw_index < 2^56`. The high bit separates this namespace
from current internal particle consumers; the three plane-mask bits separate
groups. The implementation declares this layout once, checks before draw-index
exhaustion or epoch overflow, and updates the RNG layout and registry census. A sampler
consuming a variable number of draws cannot consume another particle's or
another source group's stream. Distinct masks must be pinned to distinct
cells, along with the existing beam, radiation, BPM, and turn-rule neighbours.

CPU thread count, CUDA launch dimensions, MPI rank count, and partition size
do not enter the key. The same deterministic host source applied to the same
coordinates produces the same table; coordinate functions may reflect small
upstream CPU/CUDA arithmetic differences, which are assessed with physical
tolerances instead of a false bitwise promise. Arbitrary user state and
third-party distribution version changes are outside RNG reproducibility.

## Ownership, lifetime, and execution

`Linear6DSpec` carries source descriptions and physics parameters. It never
knows the beam size and never owns mutable binding state. `TrackingTask`
owns one persistent state per concrete placement, outside both runtime and
plan caches. Reusing one spec in two placements gives two bindings; reusing it
in two tasks gives two independent owners. A placement's structural identity,
not only its optional display name, keys the binding.

The compiled runtime contains shared `A_out`, `inv_A_in`, and references to
owned local tune arrays plus six cached sine/cosine arrays. It uses indexed
tracking context to select the local slot from the global particle ID and
known shard offset. There is no per-particle 6x6 matrix, per-turn trigonometry,
or host callback. On CPU these are ordinary host arrays; on CUDA they remain
on the device. Immutable matrix tuples and adapted device views form the
kernel argument. The task retains the owning arrays across runtime rebuilds.
The same runtime type may carry an unbound marker before first passage;
tracking it without a bound indexed task context fails explicitly.

Initialization is a segment at the actual placement. A task may contain
multiple particle-tune maps at arbitrary positions. Track the preceding
segment, stage and validate the new assignment, transfer it once if needed,
commit the binding, then apply the map. Subsequent passages use a bound segment and the existing tracking kernels;
the first version retains this segment boundary each turn. An uninitialized later map
must observe coordinates produced by all earlier maps, including an earlier
particle-tune map in the same turn. A zero-turn window does not initialize or
call user code.

The initial supported task is `TrackingTask` on CPU threads, CUDA, and the
existing CPU multi-process policy. A `StrongStrongTask` refuses this runtime
before tracking either beam until its independent line lifecycle is wired
and validated. The first version accepts ordinary direct or flattened line
placements. A particle-tune map hidden in a kept-whole `CompositeLine`, a
nontrivial `MisalignedElement`/`RefTilted` placement, or a turn-modulated
wrapper is refused before tracking: source evaluation at those nested body
entrances needs a recursive execution boundary, not a callback on the outer
line's coordinates. Zero placement defaults remain valid. These are explicit
support boundaries, not inherited restrictions on the ordinary `Linear6D`.

An atomic task-entry guard covers compilation, admission, tracking and cleanup.
Competing or recursive execution of the same task is refused before shared
state changes; the two explicit clear APIs acquire that same guard. Separate
tasks can execute independently.

Binding checks include all six coordinate-array identities and shapes,
numeric type, backend/device, global particle count, shard interval, and
placement/source configuration. Replacing storage or using a different
partition fails before any tracking, even when the local length happens to
match. There is no silent rebuilding or resampling. In-place coordinate
changes, including `PhaseSpaceResetSpec` restoration, keep the assignment.
The framework has stable slot identities, not a particle-ID array it can use
to detect arbitrary user permutations: reordering a live beam in place is
unsupported while bound. Arbitrary action hooks capable of replacing or
permuting storage are refused on this task until they can declare and uphold
an identity-preserving contract. Read-only observers remain supported.
Mutable coordinate arrays are identified through weak references. Immutable
array wrappers such as `SubArray` views and their parents are retained until
the corresponding owner is cleared or replaced: a weak reference to a
temporary wrapper box disappears at garbage collection while the beam is
still alive. The same ownership rule serves reset snapshots and both task
kinds' loss records.

Optics-only recompilation updates shared transforms while preserving labels.
Changing source structure or a nominal `dmu` used by an omitted plane is
refused while bound; explicitly clear first. A changed `dmu` in an overridden
plane is documented as inactive for its assigned tune. Other knob and plan
changes must not discard state. A closure's captured mutable state and source
array contents are not monitored each turn; sources are consumed only at
initialization and a caller must explicitly rearm to consume their edits.

Provide `clear_particle_tunes!(task)` to discard every tune binding and arm
initialization at each placement's next passage. It does not move coordinates,
clear the phase-space reset reference, rewind the turn, or reseed other
stochastic elements, and is refused during execution. Clearing initialized
state increments its retained preparation epoch once, so stochastic sources
draw a fresh, reproducible assignment at the next passage. A new task starts
at epoch zero; direct arrays remain the route to reuse identical labels. Clearing a reset
reference must likewise leave tune bindings intact. Provide a read-only
`particle_tune_tables(task)` accessor returning independent local copies,
placement identity, plane/source descriptors, global range/count, binding
status, initialization turn, seed/method/stream, and initialization epoch.
Copies may transfer from CUDA because the caller explicitly requested them;
tracking itself never does so per turn. Unbound entries are reported as such,
not as empty successful tables. The accessor provides data for distributions,
re-use and validation without exposing mutable runtime arrays.

Coordinate-independent sources assign finite tunes to every slot, including
particles already lost on first passage. Later loss does not compact arrays,
redraw labels, or change indices; loss bookkeeping follows the normal task.
A later reset can revive coordinates with their original labels. Coordinate
sources require a finite entrance ensemble as stated above.

## Failure and MPI collectives

Preflight all structural configuration, array lengths/values, support
boundaries, storage identity, and partition checks before tracking. Candidate
compilation or refused admission must preserve the last accepted state and
runtime cache. A callback or distribution can fail only after its actual
entrance is known. Stage all local tunes and cached coefficients, validate
them, agree success across ranks, and only then install the complete binding
and apply the map. A failing source leaves no partial table or receipt
claiming successful initialization. Previously bound placements stay bound.

This transaction is at the element boundary. Earlier elements in the same
turn may already have advanced the beam and produced observer/loss output.
The failure does not promise rollback of a whole turn, an artifact, or user
callback side effects. The exception identifies the placement and that no
map was applied there; continuation follows existing task error semantics,
and callers restore/restart the beam deliberately rather than blindly retrying
an already partially advanced turn.

All MPI preparation runs inside the activated policy scope. Resolve global
shards from the actual representation. Every rank, including an empty shard,
participates in the same validation and success collectives. Catch local
callback/conversion/sampler failures, all-reduce an integer verdict, and make
every rank throw or commit together. Never use a NaN-reduced bound to decide
which ranks throw. Mismatched storage/source metadata or non-finite callback
inputs receive the same collective treatment. The launcher test must include
four ranks with a failure on only one rank; two-rank mutual failures are
insufficient. Per-rank receipt files, not interleaved stdout, are the evidence.

Presence, placement, precision, shared optics, named source structure, omitted nominal tunes, stream and
preparation epoch are agreed before tracking. First stochastic initialization
also agrees the captured seed and RNG method. Arbitrary function captures and
distribution internals are opaque user code; callers must supply equivalent
sources on each rank. A later global RNG change is inert for already-bound
tables.

## Matrix queries, metadata, and integration

`Matrix(Linear6D)` and ordinary `one_turn_matrix`/Twiss calls stay unchanged.
An active particle-tune spec or runtime has no unique 6x6 matrix; contextless
`Matrix`, scalar tracking, one-turn linearization, and Twiss analysis refuse
by name without invoking sources or claiming initialization. No nominal,
first-particle, or averaged map is selected silently. Users can form an
ordinary `Linear6DSpec` with one selected stored triple and the same optics
to study that particle's fixed map. The `:linear6d` kind retains its existing
analysis declaration because the ordinary variant supports it; help text and
runtime guards state the instance-dependent restriction.

The existing `ElementMeta.runtime_types` maps one tracking method to one
runtime, so a specialized compile method alone would hide the second type
from reflection. Extend metadata with a declared per-method runtime-variant
collection and a corresponding representative-spec collection, keeping the
ordinary runtime as the existing type-level default. The instance-level
`runtime_type(spec, method)` selects from those declared variants.
`compile_runtime` retains its common knob resolution and placement wrappers.
Derive the registry's runtime census, ownership queries, numeric-type coverage,
rounding coverage, and metadata validation from that single declaration.
Validate and exercise every variant; do not satisfy the validator by compiling
only the default example. Regenerate the snapshot, never hand-edit it.

Add structured `ParamMeta` entries for `particle_tunes` and `rng_id`, with
inactive/invalid semantics and consumers. Document source constructors and the
task accessors in docstrings/public API; source wrappers are helper values,
not a new Knowledge Layer category. Consumer receipts distinguish requested
planes/source kinds from actually bound local/global counts and resolved RNG
configuration. An effectiveness check must observe changed tracked coordinates
for each plane and a changed distribution assignment under a different stream;
returning source configuration alone is not effectiveness.

Before implementing, enumerate neighbouring consumers of runtime metadata,
`compile_runtime`, scalar/context tracking, `one_turn_matrix`, recursive line
walkers, CUDA adaptation, task guards, losses, and state/cache invalidation.
The ordinary long heterogeneous line must not pay a per-turn walk or array
allocation for a feature it does not contain. Reuse literal-index unrolled
walks; ordinary iteration over a heterogeneous isbits tuple can copy the
whole line at each step. Keep the new guard predicates in the existing
per-walk allocation checks.

## Validation and completion criteria

The validation is independent where agreement could otherwise compare one
new helper to itself. Record every tolerance, fixture, negative control,
backend and resolved policy in the campaign record.

1. Build dense reference matrices from explicit 2x2 optics transport blocks
   and independently written dispersion/coupling matrices, or BigFloat
   arithmetic; do not use the new normalization helper in the oracle. Cover
   distinct known tunes in all planes, nonzero alpha, both dispersions,
   coupling, unequal entrance/exit optics, signed longitudinal tunes, and
   Float32/Float64. Constant tune arrays agree with the existing ordinary
   `Linear6D` within a stated forward-error bound; no bitwise identity is
   promised between different arithmetic factorizations.
2. Exercise all seven override subsets, fixed scalars, arrays, plain/wrapped
   functions, independent distributions, every joint subset, and disjoint
   composition. A known upstream map makes entrance coordinates differ from
   task coordinates and normalized coordinates. Count callback invocations to
   prove initialization exactly once, including multiple interior placements.
   Mutating source arrays after binding must not alter owned tables.
3. Check histogram unequal-width bin masses, zero bins, within-bin uniformity,
   means/covariances, and joint correlations against analytically derived
   moments. Set statistical bounds before measuring a fixed deterministic
   seed; include degenerate and invalid edge/weight/shape fixtures. A custom
   analytic sampler tests the generic `rand(rng, d)` route and varying numbers
   of consumed draws without coupling neighbouring sources or particles.
4. Compare one long execution with continuation chunks, optics/plan cache
   rebuilds, and the same run containing coordinate resets. Tune tables and
   callback counts persist; clears act independently. Check task and placement
   independence, global-seed changes after binding, explicit rearm, zero turns,
   array-size mismatch, same-sized replacement storage, re-sharding, all
   refusal paths, and a valid continuation after a refused admission.
5. With labels frozen, verify `M_i' J M_i = J` by an independent matrix or
   numerical Jacobian. On periodic optics, check normalized actions over many
   turns and recover known phase advances. Perturbing a callback's input to
   redraw labels is an explicit negative example of the wrong test.
6. Check phase mixing against the exact finite-ensemble response
   `G(n) = sum(exp(-im*2pi*nu[i]*n))/N` for a common normalized displacement.
   Then apply a prescribed common dipole-kick sequence and compare each
   particle with the independently summed rotated kicks. Compare centroid,
   central covariance/emittance, and normalized actions, including the
   zero-spread limit. This is an analytic noise-response oracle; a full noisy
   crab-cavity/beam-beam comparison is not substituted for it.
7. Run CPU threads 1/2/4, CUDA with multiple launch dimensions, and actual MPI
   at 1/2/4 ranks with uneven counts and empty shards. Assert active CUDA and
   loaded MPI extension/rank count, not merely requested policy. Compare
   global-ID assignments, local storage slices, table digests, and tracked
   physics with stated bounds. Record residency and separate one-time host
   initialization/transfers from steady tracking allocations/copies.
8. Exercise wrong arity/type/non-finite callback results, sampler exceptions,
   insufficient direct arrays, unsupported wrappers/task routes, invalid
   numeric conversion, inactive RNG, and ambiguous Matrix/Twiss queries.
   Show one-rank failure gives coherent multi-rank refusal with no installed
   partial table and no map at that boundary. Dead slots preserve array and
   distribution labels; a coordinate function with dead entrance is refused.
9. Run both `element_help` forms, `validate_element_metadata()`,
   `validate_configuration_metadata()`, public-configuration and element
   effectiveness checks, registry/snapshot and precision/rounding tripwires.
   Explicitly measure the new runtime variant, not only the default example.
   Run source `Core.Box`, detached-docstring, RNG-claim, and heterogeneous
   40-cavity allocation neighbours before the gate. Inject swapped particle
   labels, redraw-per-turn, an ignored plane, and a wrong normalization into
   isolated controls and show the intended assertions fail.
10. Finish with a targeted neighbour audit using the repository protocol,
    `validation/tracking_backend_consistency.jl`, the source/arity census,
    fast checkpoint, and the full four-thread gate with CUDA active on the
    final tree. Actual MPI checks complement that gate. Commit harnesses,
    measured receipts and tolerances, the new history record, docs index,
    generated snapshot, TODO closure and reusable lessons in the same batch.
    The final report names the lane, skipped or unavailable checks, and the
    remaining unsupported boundaries; commit and push only after that gate.

## Review outcome

The integrator and independent core and validation reviews accepted the map,
source protocol, lifetime and support boundaries. Clarifications incorporated
before implementation were explicit Float32/Float64 support, the high-bit RNG
namespace, fresh preparation epochs on deliberate clear, raw-spec RNG refusal,
retained tracking segments, source-mask rather than declaration-order keying,
and shared-stream correlation when one stochastic spec is reused. The
campaign record holds the implementation review and measured validation.
