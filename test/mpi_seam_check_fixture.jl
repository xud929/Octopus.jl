# The line, beam and signature the multi-process check compares across
# policies. A separate file because BOTH sides need them identically: the
# mpiexec child (`mpi_seam_check.jl`) under the MPI policy, and the parent
# suite under `CPUThreadsExecutionPolicy` -- the comparison is only worth
# anything if neither side can drift from the other. Functions rather than
# constants so the parent can include this inside a `@testset` body.

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
