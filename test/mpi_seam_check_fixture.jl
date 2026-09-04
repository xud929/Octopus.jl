# The lines, beams and signatures the multi-process checks compare across
# policies. A separate file because BOTH sides need them identically: the
# mpiexec child (`mpi_seam_check.jl`) under the multi-process policy, and the
# parent suite under `CPUThreadsExecutionPolicy` -- the comparison is only
# worth anything if neither side can drift from the other. Functions rather
# than constants so the parent can include this inside a `@testset` body.

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

_mpi_check_gaussian_solver() = Octopus.GaussianPoissonSolver(
    kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
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
    px, py = Array(rep.px), Array(rep.py)
    n = Octopus._mp_global_count(length(px))
    total(v) = Octopus._mp_global_sum(sum(abs2, v))
    peak = Octopus._mp_allminmax(maximum(abs, px), maximum(abs, px))[2]
    return (maxpx=peak, rmspx=sqrt(total(px) / n), rmspy=sqrt(total(py) / n))
end
