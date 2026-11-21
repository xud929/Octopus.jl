# Audit U1-1 reproduction: the particle-tune variant's normalizer ignores form1/form2.
# Expectation: with nonzero R1 and form1 = 2, the one-particle ParticleLinear6D map of a spec whose per-particle
# tunes equal the nominal dmu/2pi must equal the Linear6D matrix of the same optics (form 2). Unfixed: it equals the
# FORM-1 matrix instead.
using Octopus, LinearAlgebra, Printf
β = (0.8, 0.072, 90.9); α = (0.3, -0.2, 0.05); C = (0.05, 0.01, -0.02, 0.03); dmu = (0.7, 1.3, -0.06)
u = (1e-4, 2e-5, -3e-5, 4e-6, 0.01, -1e-4)
for form in (1, 2)
    plain = Linear6DSpec(; beta1 = β, alpha1 = α, R1 = C, form1 = form, dmu = dmu)
    pt = Linear6DSpec(; beta1 = β, alpha1 = α, R1 = C, form1 = form, dmu = dmu, particle_tunes = (nux = dmu[1] / 2pi, nuy = dmu[2] / 2pi, nuz = dmu[3] / 2pi))
    M = Matrix(Linear6D(plain))
    rt = compile_runtime(pt)
    A = Matrix{Float64}(undef, 6, 6); for i in 1:6, j in 1:6; A[i, j] = rt.A[(i - 1) * 6 + j]; end
    Aexp1 = Matrix{Float64}(undef, 6, 6); Aexp2 = similar(Aexp1)
    N = Octopus._particle_tune_normalizer(β, α, (0, 0, 0, 0), (0, 0, 0, 0), (0, 0, 0, 0), Float64)   # pure Twiss normalizer
    for i in 1:6, j in 1:6
        Aexp1[i, j] = Octopus._mmul66(Octopus._mR66(C, 1), N)[(i - 1) * 6 + j]
        Aexp2[i, j] = Octopus._mmul66(Octopus._mR66(C, 2), N)[(i - 1) * 6 + j]
    end
    @printf("form %d: |A - form1 expectation| = %.2e   |A - form2 expectation| = %.2e   -> normalizer built in form %d\n",
            form, norm(A - Aexp1), norm(A - Aexp2), norm(A - Aexp1) < norm(A - Aexp2) ? 1 : 2)
end
