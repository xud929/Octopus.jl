# U18 probe 7: discriminating-power injections for three region testsets.
#   A) "CPU solver stack is thread-count invariant"  (worker-count-dependent
#      chunk partition = the pre-fix U5-1/2 defect class)
#   B) "Philox4x32-10 matches the Random123 known-answer vectors"
#      (3-round variant, Weyl bump removed)
#   C) "Every export is documented" (a new undocumented export)
# No repository file is modified; everything is injected into the loaded module.
using Octopus, Test

println("Threads.nthreads(:default) = ", Threads.nthreads(:default))

# ---------------------------------------------------------------- A
mkr(n) = begin
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
    Phase6DRep(s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9),
               s(1.0e-5, 1.2), z, s(1.0e-4, 2.5))
end
mkb(n) = begin
    rep = mkr(n)
    params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
    Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end
workers(f, k, rep) = Octopus._with_execution_policy(f,
    Octopus._resolve_execution_policy(CPUThreadsExecutionPolicy(threads=k), rep))
slc = LongitudinalSlicing(nslices=3, method=:equal_count)
solvers = (("pic", PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
                grid=(16, 16), green_cache=:none, slicing=slc)),
           ("gpic", GaussianPICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(16, 16), green_cache=:none, slicing=slc)),
           ("spectral_l", SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(32, 32), slicing=slc)))

function block2()
    counts = unique((1, 2, Threads.nthreads(:default)))
    report = String[]
    for (label, solver) in solvers
        outs = map(counts) do k
            b1, b2 = mkb(15000), mkb(15000)
            lum = workers(k, b1.rep) do
                collide!(solver, b1, b2, CPUThreadsBackend)
            end
            (lum, map(copy, coordinate_arrays(b1.rep)), map(copy, coordinate_arrays(b2.rep)))
        end
        for other in 2:length(outs)
            lum_eq = outs[1][1] == outs[other][1]
            c1 = all(a == b for (a, b) in zip(outs[1][2], outs[other][2]))
            c2 = all(a == b for (a, b) in zip(outs[1][3], outs[other][3]))
            dmax = maximum(maximum(abs, a .- b) for (a, b) in zip(outs[1][2], outs[other][2]))
            push!(report, "$label  workers $(counts[1]) vs $(counts[other]): " *
                          "lum_eq=$lum_eq coords_eq=$(c1 && c2) maxdiff=$dmax " *
                          "lumdiff=$(outs[1][1] - outs[other][1])")
        end
    end
    report
end

println("\n--- A1: baseline (unmodified code) ---")
foreach(println, block2())

println("\n--- A2: injected worker-count-dependent chunk partition ---")
Octopus.eval(quote
    function _chunk_bounds(n::Int, nchunks::Int, chunk::Int)
        d = min(_cpu_worker_count() - 1, max(0, fld(n, 4 * max(nchunks, 1))))
        first_i = fld((chunk - 1) * n, nchunks) + 1 + (chunk == 1 ? 0 : d)
        last_i = fld(chunk * n, nchunks) + (chunk == nchunks ? 0 : d)
        return first_i, last_i
    end
end)
foreach(println, Base.invokelatest(block2))

# ---------------------------------------------------------------- B
println("\n--- B: Philox KAT discriminating power ---")
kat = ((0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
        (0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8)),
       (0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
        (0x408f276d, 0x41c83b0e, 0xa20bc7c6, 0x6d5451fd)),
       (0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344, 0xa4093822, 0x299f31d0,
        (0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1)))
function philox(c0, c1, c2, c3, k0, k1; rounds=Octopus.PHILOX4X32_ROUNDS, weyl=true)
    for _ in 1:rounds
        c0, c1, c2, c3 = Octopus._philox4x32_round(c0, c1, c2, c3, k0, k1)
        if weyl
            k0 += Octopus.PHILOX4X32_W0
            k1 += Octopus.PHILOX4X32_W1
        end
    end
    (c0, c1, c2, c3)
end
for (name, kw) in (("as shipped", (;)), ("3 rounds", (rounds=3,)),
                   ("no Weyl bump", (weyl=false,)))
    ok = all(philox(v[1:6]...; kw...) == v[7] for v in kat)
    println("  ", rpad(name, 14), ok ? "PASSES the KAT block" : "FAILS the KAT block")
end
println("  PHILOX4X32_ROUNDS == 10 assertion also pins the round count: ",
        Octopus.PHILOX4X32_ROUNDS)

# ---------------------------------------------------------------- C
println("\n--- C: `Every export is documented` detector ---")
undoc() = [n for n in names(Octopus)
           if n !== :Octopus && occursin("No documentation found",
               string(Base.Docs.doc(Base.Docs.Binding(Octopus, n))))]
println("  baseline undocumented exports: ", undoc())
Base.include_string(Octopus, "u18_no_doc_export(x) = x\nexport u18_no_doc_export", "misc.jl")
println("  after exporting an undocumented binding: ", Base.invokelatest(undoc))
Base.include_string(Octopus, """
# a comment between the docstring and the definition detaches the docs
\"\"\"
    u18_detached_export(x)

Documented, but the docstring is detached by the comment below.
\"\"\"
# an innocent comment
u18_detached_export(x) = x
export u18_detached_export
""", "misc.jl")
println("  after adding a DETACHED docstring export: ", Base.invokelatest(undoc))
