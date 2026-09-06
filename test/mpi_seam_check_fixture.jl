# The lines, beams and signatures the multi-process checks compare across
# policies. A separate file because BOTH sides need them identically: the
# mpiexec child (`mpi_seam_check.jl`) under the multi-process policy, and the
# parent suite under `CPUThreadsExecutionPolicy` -- the comparison is only
# worth anything if neither side can drift from the other. Functions rather
# than constants so the parent can include this inside a `@testset` body.

import Logging   # the dropped-count logger below; the includers need not carry it

"""A short, fully deterministic line, built by formula so both sides get the
same one without sharing an RNG."""
_mpi_check_line() = (Octopus.CrabDispersionSpec{Float64}(zeta1=0.02, zeta3=-0.01),
                     Octopus.Linear6DSpec{Float64}(beta1=(1.0, 1.0, 1.0),
                                                   beta2=(1.0, 1.0, 1.0),
                                                   dmu=(0.31, 0.27, 0.02)))

_mpi_check_beam() = Octopus.Phase6DRep([1.0e-4 * sin(0.7i) for i in 1:64],
                                       [1.0e-5 * sin(0.7i + 0.3) for i in 1:64],
                                       [1.0e-4 * sin(0.7i + 0.9) for i in 1:64],
                                       [1.0e-5 * sin(0.7i + 1.2) for i in 1:64],
                                       [1.0e-3 * sin(0.7i + 2.1) for i in 1:64],
                                       [1.0e-4 * sin(0.7i + 2.5) for i in 1:64])

"""Every coordinate at full precision: the comparison is bitwise, so the
signature must not round."""
_mpi_check_signature(rep) =
    join((sprint(show, a) for a in Octopus.coordinate_arrays(rep)), " ")

# --- the sharded-tracking fixtures (step 3a) --------------------------------

"""The global macroparticle count every sharded check uses. Small, because the
comparison ships every coordinate through the child's stdout."""
_mpi_check_global_n() = 256

"""
A line that DRAWS PER PARTICLE. `LumpedRad` with excitation on keys its six
normal draws on the particle's index, so a shard that kept its own local
indices would track a different beam here while agreeing everywhere else --
which is precisely the failure this fixture exists to catch. No apertures and
no observers: those are step 3b, and a sharded run refuses them.
"""
_mpi_check_radiating_line() = (
    Octopus.Linear6DSpec{Float64}(beta1=(1.0, 1.0, 1.0), beta2=(1.0, 1.0, 1.0),
                                  dmu=(0.31, 0.27, 0.02)),
    Octopus.LumpedRadSpec{Float64}(damping_turns=(4000.0, 4000.0, 2000.0),
                                   beta=(1.0, 1.0, 1.0), alpha=(0.0, 0.0, 0.0),
                                   sigma=(1.0e-4, 1.0e-5, 1.0e-3),
                                   is_damping=true, is_excitation=true,
                                   rng_id=101),
)

"""The strong-beam element whose luminosity fold spans ranks."""
_mpi_check_strong_beam() = Octopus.compile_runtime(
    Octopus.GaussianStrongBeamSpec{Float64}(
        thin=Octopus.ThinStrongBeamSpec{Float64}(
            kbb=1.0e-4, klum=1.0, beta=(1.0, 1.0), sigma=(1.06e-4, 9.5e-6)),
        ns=5, sigz=1.0e-3, slice_method=:equal_area))

"""Build the beam the way a user would, under whichever policy is in force.
Under the multi-process policy this returns only this rank's shard."""
function _mpi_check_build_beam(policy)
    Octopus.set_global_rng!(seed=123456789, method=:philox)
    return Octopus.Beam(_mpi_check_global_n(), policy, Float64;
                        rng_id=1, beta=(1.0, 1.0, 1.0),
                        emit=(1.0e-9, 1.0e-9, 1.0e-6), cutoff=5.0)
end

"""One coordinate array as space-separated full-precision values. Compared by
string so the cross-rank concatenation involves no arithmetic at all, and a
bitwise claim stays bitwise."""
_mpi_check_values(a) = join((repr(v) for v in a), " ")

_mpi_check_shard_line(rep) =
    join((_mpi_check_values(a) for a in Octopus.coordinate_arrays(rep)), " | ")

# --- step 3b fixtures: the scalar diagnostics ------------------------------

"""The one output path every rank names, so "only rank 0 wrote it" is a
statement about one file rather than about P different ones."""
_mpi_check_artifact_path() = joinpath(tempdir(), "octopus_mpi_seam_check.h5")

"""A beam with four particles deliberately poisoned, so the loss accounting
has something to count and the moment reductions have something to mask."""
function _mpi_check_poisoned_beam(policy)
    beam = _mpi_check_build_beam(policy)
    # Global indices, chosen to fall in different ranks' shards at P = 2 and 4.
    offset = first(Octopus._mp_resolve_shard(length(beam.rep)))
    for g in (7, 70, 150, 249)
        local_i = g - offset
        1 <= local_i <= length(beam.rep) || continue
        for a in Octopus.coordinate_arrays(beam.rep)
            a[local_i] = NaN
        end
    end
    return beam
end

# --- step 3c fixtures: the per-particle output -----------------------------

"""A line with an aperture tight enough to kill a good fraction of the beam,
so the loss rows are worth gathering, plus a snapshot observer whose `npart`
counts the WHOLE beam."""
_mpi_check_walled_line() = (Octopus.ApertureSpec(shape=:ellipse,
                                                 x_limit=6.0e-5, y_limit=6.0e-5),)

"""Snapshot and loss identities as the file records them, sorted, so a
comparison is about WHICH particles were recorded and not about the order the
ranks happened to arrive in."""
function _mpi_check_perparticle_signature(path)
    out = Octopus.TaskOutput(path)
    snap = read(out, :snapshot)["snap"]
    losses = read(out, :losses)
    return (snapshot_ids=sort(Int.(snap.particle_id)),
            snapshot_turns=sort(unique(Int.(snap.turn))),
            loss_ids=sort(Int.(losses.particle_id)),
            summary=losses.summary)
end

# --- step 4a fixtures: the soft-Gaussian collide ---------------------------

"""Two beams and a soft-Gaussian solver, built by formula so both sides get
the same ones. `:equal_area` because its boundaries come from a histogram of
the beam, which is the reduction that has to span the ranks."""
function _mpi_check_collide_beams(policy)
    mk() = begin
        Octopus.set_global_rng!(seed=1234, method=:philox)
        Octopus.Beam(4096, policy, Float64; rng_id=1, beta=(1.0, 1.0, 1.0),
                     emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    end
    return mk(), mk()
end

_mpi_check_gaussian_solver(; batch_mode=:wavefront) = Octopus.GaussianPoissonSolver(
    kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, batch_mode=batch_mode,
    slicing=Octopus.LongitudinalSlicing(nslices=5, method=:equal_area))

"""
A compact fingerprint of a collided beam: the kicks' extreme and their
root-mean-square, at full precision, over the WHOLE beam.

Compact because the comparison ships through a child's stdout, and sufficient
because the kick is what the collide does. Global because a shard's own
root-mean-square is not the beam's -- an early version of this compared local
ones and reported a 1.6% disagreement that was entirely the fingerprint's.
"""
function _mpi_check_collide_signature(rep)
    px, py, pz = Array(rep.px), Array(rep.py), Array(rep.pz)
    n = Octopus._mp_global_count(length(px))
    total(v) = Octopus._mp_global_sum(sum(abs2, v))
    peak = Octopus._mp_allminmax(maximum(abs, px), maximum(abs, px))[2]
    # `rmspz` is what sees the longitudinal kick: PIC's `longitudinal_kick`
    # writes pz and nothing else, so a fingerprint of px and py alone found
    # the transverse-only arm equal to the default (4c review).
    return (maxpx=peak, rmspx=sqrt(total(px) / n), rmspy=sqrt(total(py) / n),
            rmspz=sqrt(total(pz) / n))
end

# --- step 4b fixtures: the strong-strong task -------------------------------

"""The one output path the strong-strong check names on every rank."""
_mpi_check_ss_artifact_path() = joinpath(tempdir(), "octopus_mpi_seam_check_4b.h5")

"""
Two beams of DIFFERENT sizes, both chunk-alignable at one and two ranks
(64 | 256 and 64 | 192 whole chunks), because a run holding two beams is
where a single scoped shard went wrong: the second beam was handed the first
beam's offset. Built the way a user would, under whichever policy is in
force, so under the multi-process policy each is this rank's shard.
"""
function _mpi_check_ss_beams(policy)
    Octopus.set_global_rng!(seed=4242, method=:philox)
    b1 = Octopus.Beam(256, policy, Float64; rng_id=1, beta=(1.0, 1.0, 1.0),
                      emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    b2 = Octopus.Beam(192, policy, Float64; rng_id=2, beta=(1.0, 1.0, 1.0),
                      emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    return b1, b2
end

"""
One strong-strong line: a linear map, a radiating element that DRAWS PER
PARTICLE (keyed on the beam's GLOBAL index, so a line tracking under the
wrong beam's offset draws different noise), a line-placed moment observer
(a collective reduction, written by rank 0), the collision, and a second
linear map. `which` picks the beam's own radiation stream and observer name.
"""
_mpi_check_ss_line(which::Integer; solver=_mpi_check_gaussian_solver(),
                   observers::Bool=true) = (
    Octopus.Linear6DSpec{Float64}(beta1=(1.0, 1.0, 1.0), beta2=(1.0, 1.0, 1.0),
                                  dmu=(0.31, 0.27, 0.02)),
    Octopus.LumpedRadSpec{Float64}(damping_turns=(4000.0, 4000.0, 2000.0),
                                   beta=(1.0, 1.0, 1.0), alpha=(0.0, 0.0, 0.0),
                                   sigma=(1.0e-4, 1.0e-5, 1.0e-3),
                                   is_damping=true, is_excitation=true,
                                   rng_id=200 + which),
    (observers ? (Octopus.MomentObserver(name="m$(which)", orders=1:2),) : ())...,
    Octopus.StrongStrongCollision(:ip; poisson_solver=solver),
    Octopus.Linear6DSpec{Float64}(beta1=(1.0, 1.0, 1.0), beta2=(1.0, 1.0, 1.0),
                                  dmu=(0.11, 0.07, 0.01)),
)

_mpi_check_ss_task(policy, path; solver=_mpi_check_gaussian_solver(),
                   observers::Bool=true) =
    Octopus.StrongStrongTask(_mpi_check_ss_line(1; solver=solver, observers=observers),
                             _mpi_check_ss_line(2; solver=solver, observers=observers);
                             policy=policy, artifact=path)

# The fixture kick is deliberately unphysical: kbb = 1e-6 at sigma = 3.2e-5
# multiplies the rms momentum by ~500 in one collide, so three turns are one
# very strong nonlinear kick followed by nearly kick-free turns. Agreement
# across rank counts is as good at kbb = 1e-10 (measured during the 4b design
# review); the strong kick is kept because it makes any wrong shift origin or
# wrong radiation key unmistakable, not because it is a beam-beam regime.

"""
A pair sized so every rank's slices enter the CHUNKED moment and kick
branches at 1, 2 and 4 ranks: `_STRONG_STRONG_PARALLEL_MOMENT_MIN` and
`_STRONG_STRONG_PARALLEL_KICK_MIN` are 4096 members per slice, and the 256/192
pair above never reaches them -- the 4a segfault appeared only when a divided
run first met a slice big enough to chunk (64 x 1536 and 64 x 1280 particles,
three slices: 8192 and 6827 per slice on a rank at four ranks).
"""
function _mpi_check_ss_big_beams(policy)
    Octopus.set_global_rng!(seed=4243, method=:philox)
    b1 = Octopus.Beam(98304, policy, Float64; rng_id=1, beta=(1.0, 1.0, 1.0),
                      emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    b2 = Octopus.Beam(81920, policy, Float64; rng_id=2, beta=(1.0, 1.0, 1.0),
                      emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    return b1, b2
end

_mpi_check_ss_big_solver() = Octopus.GaussianPoissonSolver(
    kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
    slicing=Octopus.LongitudinalSlicing(nslices=3, method=:equal_area))

_mpi_check_ss_big_artifact_path() = joinpath(tempdir(), "octopus_mpi_seam_check_4b_big.h5")

"""
The spectral solver the step-4g checks run: a 16 x 16 mesh and three
equal-area slices, matching the PIC fixture so the two solvers' divided
arms see the same slicing.

This is also the solver the task-level arm runs where the undivided-solver
refusal used to fire: spectral was the last solver the campaign had not
divided, so what that arm asserts now is that it RUNS at every rank count.
"""
_mpi_check_spectral_solver(; kw...) = Octopus.SpectralPoissonSolver(
    kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(16, 16),
    slicing=Octopus.LongitudinalSlicing(nslices=3, method=:equal_area); kw...)

"""
The spectral arms, `(name, solver, threads, same_as)`.

`same_as` names an arm this one must equal bit for bit at the same rank count:
the two schedules of the 6D map agree by construction, and the thread count
changes no fold. The two routes are BOTH here because they divide by different
means -- the 6D map on the slice-aligned layout, the transverse-only map on the
home layout -- and each method is here because the payload a field member
evaluates differs (a solved mesh for `:grid`, folded mode sums for
`:grid_free`).
"""
_mpi_check_spectral_variants() = (
    (:spec, _mpi_check_spectral_solver(), 1, nothing),
    (:spec_seq, _mpi_check_spectral_solver(batch_mode=:sequential), 1, :spec),
    (:spec_threads, _mpi_check_spectral_solver(), 2, :spec),
    (:spec_free, _mpi_check_spectral_solver(method=:grid_free), 1, nothing),
    (:spec_skew, _mpi_check_spectral_solver(slicing=_mpi_check_pic_skewed_slicing()), 1, nothing),
    (:spec_trans, _mpi_check_spectral_solver(longitudinal_kick=false), 1, nothing),
    (:spec_trans_free, _mpi_check_spectral_solver(longitudinal_kick=false, method=:grid_free), 1, nothing),
    (:spec_trans_threads, _mpi_check_spectral_solver(longitudinal_kick=false), 2, :spec_trans),
)

"""
One divided spectral collide, reported the way the PIC one is: the signature
line, the luminosity every rank must agree on, whether `z` came home bit for
bit, and the receipts that say WHICH route ran (`exchange = :sliced` for the
6D map, `:order_free` for the transverse one) and how much of the work this
rank did.
"""
function _mpi_check_spectral_collide_line(policy, solver; beams=_mpi_check_ss_beams)
    b1, b2 = beams(policy)
    resolved = Octopus._resolve_execution_policy(policy, b1.rep)
    audit = Octopus.ExecutionAudit()
    # The collide never writes `z`, so `z` must come back to its home slot bit
    # for bit: the migration's own check, layout-independent.
    z1 = copy(Array(b1.rep.z)); z2 = copy(Array(b2.rep.z))
    return Octopus._with_execution_policy(resolved) do
        lum = Ref{Float64}(NaN)
        Octopus.with_execution_audit(audit) do
            lum[] = Octopus.collide!(solver, b1, b2, Octopus.CPUThreadsBackend)
        end
        sched = [r.values for r in Octopus.execution_receipts(audit)
                 if r.consumer === :spectral_pair_schedule]
        length(sched) == 1 ||
            error("expected one spectral pair-schedule receipt, got $(length(sched))")
        exch = [r.values for r in Octopus.execution_receipts(audit)
                if r.consumer === :spectral_slice_exchange]
        restored = Array(b1.rep.z) == z1 && Array(b2.rep.z) == z2
        Octopus._with_beam_shards(b1.rep, b2.rep) do
            s1 = _mpi_check_collide_signature(b1.rep)
            s2 = _mpi_check_collide_signature(b2.rep)
            (line=join((repr(v) for v in (lum[], s1.maxpx, s1.rmspx, s1.rmspy, s1.rmspz,
                                          s2.maxpx, s2.rmspx, s2.rmspy, s2.rmspz)), " "),
             lum=repr(lum[]),
             batch_mode=Symbol(sched[1].batch_mode),
             exchange=Symbol(sched[1].exchange),
             planes_solved=isempty(exch) ? 0 : Int(exch[1].planes_solved),
             pairs_coordinated=isempty(exch) ? 0 : Int(exch[1].pairs_coordinated),
             restored=restored)
        end
    end
end

# --- step 4c fixtures: the PIC collide ---------------------------------------

"""The PIC solver the divided-PIC checks run: a 16 x 16 mesh, three equal-area
slices, the slice-pair Green cache so its reuse decisions run divided too."""
_mpi_check_pic_solver(; kw...) = Octopus.PICPoissonSolver(
    kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(16, 16),
    green_cache=:slice_pair,
    slicing=Octopus.LongitudinalSlicing(nslices=3, method=:equal_area); kw...)

"""
The PIC option variants a divided run must honour, each with the route it
selects and the thread count its policy runs at: the node and source-slice
meshes (built from global extrema), the `:sigma` extent (a shared shift
origin), the quadratic interpolation (a third plane), TSC deposition, no Green
cache, a separate luminosity mesh, the fourth-order field derivative,
quantized meshes, the lattice Green function, the transverse-only map; then
the three arms the 4c review asked for -- `:sparse`, 64 equal-area slices on
these beams, so that at two ranks a rank holds NO member of a slice that is
globally populated (10 such (rank, slice) pairs on beam 1 and 9 on beam 2;
85 and 104 at four ranks) and the empty-shard branches of the pair are
reached rather than dead; `:lumscale`, the DEFAULT luminosity scale, whose
`npart / (n1 n2)` reads the beam's counts and is hidden by the explicit
`luminosity_scale = 1.0` of every other arm; and `:threads2`, a two-thread
policy, under which a divided run must force ONE pair worker (the pairs
issue collectives and MPI is `:funneled`) and hand the inner maps both
threads -- pinned from the schedule receipt, since at one thread the forcing
changes nothing and cannot be seen (under the batched exchange of the
performance phase the forcing applies to the node mesh alone, which still
runs the per-pair exchange, so `:node2` is the two-thread node arm). Each
tuple's fourth entry names the arm this one must EQUAL bit for bit at both
rank counts, or `nothing` when it must DIFFER from the default -- asserted
both ways, so a variant that changed nothing cannot pass by running the
default twice and a schedule arm cannot pass by changing the physics: the
two-thread policies equal their one-thread twins (the CPU PIC collide is
thread-count invariant by construction, and so must its divided form be),
and `:sequential` -- the per-pair exchange -- equals the default's batched
exchange, which is the claim that the batched exchange re-associates
nothing.
"""
_mpi_check_pic_variants() = (
    (:default, _mpi_check_pic_solver(), 1, nothing),
    (:node, _mpi_check_pic_solver(interaction_grid=:node), 1, nothing),
    (:source_slice, _mpi_check_pic_solver(interaction_grid=:source_slice), 1, nothing),
    (:sigma, _mpi_check_pic_solver(grid_extent=:sigma, grid_extent_sigma=4.0), 1, nothing),
    (:quadratic, _mpi_check_pic_solver(slice_interpolation=:quadratic), 1, nothing),
    (:tsc, _mpi_check_pic_solver(deposit_method=:TSC), 1, nothing),
    (:green_none, _mpi_check_pic_solver(green_cache=:none), 1, nothing),
    (:lumgrid, _mpi_check_pic_solver(luminosity_grid=(24, 24), luminosity_deposit_method=:TSC), 1, nothing),
    (:fourth, _mpi_check_pic_solver(field_derivative=:fourth), 1, nothing),
    (:quantize, _mpi_check_pic_solver(grid_quantize=0.125), 1, nothing),
    (:lattice, _mpi_check_pic_solver(green_type=:lattice), 1, nothing),
    (:transverse, _mpi_check_pic_solver(longitudinal_kick=false), 1, nothing),
    (:sparse, _mpi_check_pic_solver(slicing=_mpi_check_pic_sparse_slicing()), 1, nothing),
    (:lumscale, _mpi_check_pic_solver(luminosity_scale=nothing), 1, nothing),
    (:threads2, _mpi_check_pic_solver(), 2, :default),
    (:sequential, _mpi_check_pic_solver(batch_mode=:sequential), 1, :default),
    (:node2, _mpi_check_pic_solver(interaction_grid=:node), 2, :node),
    (:skewed, _mpi_check_pic_solver(slicing=_mpi_check_pic_skewed_slicing()), 1, nothing),
)

_mpi_check_pic_sparse_slicing() = Octopus.LongitudinalSlicing(nslices=64, method=:equal_area)

"""The slicing an arm's solver uses, whichever solver it is: Gaussian-PIC
carries the PIC solver its slicing belongs to."""
_mpi_check_arm_slicing(solver) = hasproperty(solver, :slicing1) ? solver.slicing1 :
                                 solver.pic.slicing1

"""
The Gaussian-PIC arms (step 4f). gpic is PIC with a control variate fitted
to the SOURCE SLICE, so what it adds to the divided collide is the slice's
moments, the mode they imply and the analytic add-back -- and the arms are
the routes those take: the default (the uncoupled subtraction), the coupled
one (`coupling_tol = 1e-3` resolves every slice of this fixture to
`:coupled`, measured), no Gaussian margin on the mesh, the un-neutralised
amplitude -- the one route whose subtraction does NOT read the folded grid
total, and so the one that would still be right if a rank subtracted its own
share -- and the sequential schedule, which must MATCH the default because
it is the same physics on the other loop. The mode's `:pic` fallback needs a
coupling that is requested and cannot be resolved, which these round beams
never produce; it is covered by the in-process arms rather than here.
"""
_mpi_check_gpic_solver(; kw...) = Octopus.GaussianPICPoissonSolver(
    kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(16, 16),
    green_cache=:slice_pair,
    slicing=Octopus.LongitudinalSlicing(nslices=3, method=:equal_area); kw...)

_mpi_check_gpic_variants() = (
    (:gpic, _mpi_check_gpic_solver(), 1, nothing),
    (:gpic_coupled, _mpi_check_gpic_solver(coupling_tol=1.0e-3), 1, nothing),
    (:gpic_nomargin, _mpi_check_gpic_solver(margin_sigma=0.0), 1, nothing),
    (:gpic_noneutral, _mpi_check_gpic_solver(neutralize=false), 1, nothing),
    (:gpic_seq, _mpi_check_gpic_solver(batch_mode=:sequential), 1, :gpic),
)

"""
The slice-aligned layout (step 4d) of `rep` under `slicing` at `nranks`
ranks, from the global slice counts and the layout rule alone -- what the
launcher child's ranks derive for themselves, recomputed here so the
parent's premises (which arm exercises which regime) and expectations (how
many partial planes a collide must move) come from the same rule.
"""
function _mpi_check_pic_layout(rep, slicing, nranks::Integer)
    slices = Octopus.longitudinal_slices(rep, slicing)
    return Octopus._pic_sliced_layout([length(idx) for idx in slices.indices], Int(nranks))
end

"""Group sizes per slice: 1 for a whole slice on one rank, more for a slice
split across a group, 0 for an empty slice."""
_mpi_check_pic_groups(rep, slicing, nranks::Integer) =
    [length(g) for g in _mpi_check_pic_layout(rep, slicing, nranks).groups]

"""The partial planes a collide of `solver` moves at `nranks` ranks: for every
pair with members on both sides, the planes per direction times the two
groups' sizes -- one interior per member per plane."""
function _mpi_check_pic_partials(b1, b2, solver, nranks::Integer)
    l1 = _mpi_check_pic_layout(b1.rep, solver.slicing1, nranks)
    l2 = _mpi_check_pic_layout(b2.rep, solver.slicing2, nranks)
    nplanes = solver.slice_interpolation === :quadratic ? 3 : 2
    total = 0
    for i in eachindex(l1.counts), j in eachindex(l2.counts)
        (l1.counts[i] == 0 || l2.counts[j] == 0) && continue
        total += nplanes * (length(l1.groups[i]) + length(l2.groups[j]))
    end
    return total
end

"""The smallest part of any slice on any rank at `nranks` ranks."""
function _mpi_check_pic_min_part(rep, slicing, nranks::Integer)
    layout = _mpi_check_pic_layout(rep, slicing, nranks)
    smallest = typemax(Int)
    for parts in layout.parts, part in parts
        smallest = min(smallest, length(part))
    end
    return smallest
end

_mpi_check_pic_artifact_path() = joinpath(tempdir(), "octopus_mpi_seam_check_4c.h5")

"""
A logger that keeps the mesh's dropped-particle count out of the warning the
collide raises (`_pic_report_dropped`: the BEAM's count, warned once by rank
0) and swallows everything else, so the child's stdout stays the lines the
parent parses.
"""
struct _MPICheckDroppedLogger <: Logging.AbstractLogger
    dropped::Base.RefValue{Int}
end
Logging.min_enabled_level(::_MPICheckDroppedLogger) = Logging.Info
Logging.shouldlog(::_MPICheckDroppedLogger, level, _module, group, id) = true
Logging.catch_exceptions(::_MPICheckDroppedLogger) = false
function Logging.handle_message(l::_MPICheckDroppedLogger, level, message, _module, group, id,
                                file, line; kwargs...)
    haskey(kwargs, :dropped) && (l.dropped[] += Int(kwargs[:dropped]))
    return nothing
end

"""
One PIC collide of a fresh beam pair, its luminosity and both beams'
whole-beam fingerprints as one line of full-precision values, plus what the
run recorded around it: the luminosity alone (every rank computes it
redundantly from the all-summed grids, and the child prints it from every
rank so the parent can hold them to the same bits), the dropped-particle
count (the beam's, from rank 0's warning), and the pair schedule's worker
split.
"""
function _mpi_check_pic_collide_line(policy, solver; beams=_mpi_check_ss_beams)
    b1, b2 = beams(policy)
    resolved = Octopus._resolve_execution_policy(policy, b1.rep)
    logger = _MPICheckDroppedLogger(Ref(0))
    audit = Octopus.ExecutionAudit()
    # The collide never writes `z`, so `z` must come back to its home slot
    # bit for bit: the migration's own check (step 4d), layout-independent.
    z1 = copy(Array(b1.rep.z)); z2 = copy(Array(b2.rep.z))
    # INSIDE the policy scope: a bare collide outside it sees a communicator of
    # one and collides this rank's shard alone as if it were the beam (the
    # first draft of this did exactly that, and its luminosity fell as 1/P^2).
    return Octopus._with_execution_policy(resolved) do
        # `with_execution_audit` returns the AUDIT, not the block's value.
        lum = Ref{Float64}(NaN)
        Logging.with_logger(logger) do
            Octopus.with_execution_audit(audit) do
                lum[] = Octopus.collide!(solver, b1, b2, Octopus.CPUThreadsBackend)
            end
        end
        lum = lum[]
        sched = [r.values for r in Octopus.execution_receipts(audit)
                 if r.consumer === :pic_pair_schedule]
        length(sched) == 1 || error("expected one PIC pair-schedule receipt, got $(length(sched))")
        restored = Array(b1.rep.z) == z1 && Array(b2.rep.z) == z2
        Octopus._with_beam_shards(b1.rep, b2.rep) do
            s1 = _mpi_check_collide_signature(b1.rep)
            s2 = _mpi_check_collide_signature(b2.rep)
            (line=join((repr(v) for v in (lum, s1.maxpx, s1.rmspx, s1.rmspy, s1.rmspz,
                                          s2.maxpx, s2.rmspx, s2.rmspy, s2.rmspz)), " "),
             lum=repr(lum), dropped=logger.dropped[],
             pair_workers=Int(sched[1].pair_workers),
             inner_workers=Int(sched[1].inner_workers),
             exchange=Symbol(sched[1].exchange),
             schedule=hasproperty(sched[1], :schedule) ? Symbol(sched[1].schedule) : :none,
             restored=restored)
        end
    end
end

"""
The beams of the `:big` arm: large enough that every rank's share of every
slice reaches the THREADED deposit (`_pic_deposit_parallel`: at least 4096
particles and 160 per cell, on the smallest mesh the solver accepts, 5 x 5)
at two ranks -- 32768 per beam, three slices, ~5461 per slice per rank. The
256/192-particle fixture is ~480x short of that path, so without this arm the
divided run only ever exercised the serial deposit.
"""
function _mpi_check_pic_big_beams(policy)
    Octopus.set_global_rng!(seed=4243, method=:philox)
    b1 = Octopus.Beam(32768, policy, Float64; rng_id=3, beta=(1.0, 1.0, 1.0),
                      emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    b2 = Octopus.Beam(32768, policy, Float64; rng_id=4, beta=(1.0, 1.0, 1.0),
                      emit=(1.0e-9, 1.0e-9, 1.0e-6), npart=1.0e11)
    return b1, b2
end

_mpi_check_pic_big_solver() = _mpi_check_pic_solver(grid=(5, 5))

_mpi_check_pic_big_line(policy) =
    _mpi_check_pic_collide_line(policy, _mpi_check_pic_big_solver(); beams=_mpi_check_pic_big_beams)

"""The smallest part of a slice any rank holds for the `:big` beams at
`nranks` ranks under the slice-aligned layout: the number that must clear
the threaded-deposit floor for the arm to test what it claims."""
function _mpi_check_pic_big_min_local_slice(nranks::Integer)
    b1, b2 = _mpi_check_pic_big_beams(Octopus.CPUThreadsExecutionPolicy(threads=1))
    solver = _mpi_check_pic_big_solver()
    return min(_mpi_check_pic_min_part(b1.rep, solver.slicing1, nranks),
               _mpi_check_pic_min_part(b2.rep, solver.slicing2, nranks))
end

"""The `:skewed` arm's slicing: boundaries at -1.5 and 1.5 sigma, so the
middle slice holds most of the beam and, at four ranks, is split over the
two ranks the end slices leave (each end slice needs one of its own) -- a
group beside whole slices, the two regimes of the sliced layout in one arm,
and the arm the child runs twice for fixed-rank repeatability."""
_mpi_check_pic_skewed_slicing() =
    Octopus.LongitudinalSlicing(nslices=3, method=:specified, positions=[-1.5, 1.5])

"""The strong-strong task with a line ACTION in line 1, the one thing left
that a divided run refuses."""
_mpi_check_ss_task_with_action(policy) = Octopus.StrongStrongTask(
    (Octopus.BeamSwapAction(identity), _mpi_check_ss_line(1)...),
    _mpi_check_ss_line(2); policy=policy)

"""Rank 0's view of what the strong-strong run recorded: the luminosity series
and both line observers' last rows, at full precision."""
function _mpi_check_ss_record(path)
    out = Octopus.TaskOutput(path)
    series = read(out, :luminosity; name="ip")
    m1 = read(Octopus.MomentOutput(path; name="m1"))
    m2 = read(Octopus.MomentOutput(path; name="m2"))
    return (turns=Int.(series.turn), values=Float64.(series.value),
            m1rows=size(m1, 1), m2rows=size(m2, 1),
            m1=Float64.(m1[end, :]), m2=Float64.(m2[end, :]))
end
