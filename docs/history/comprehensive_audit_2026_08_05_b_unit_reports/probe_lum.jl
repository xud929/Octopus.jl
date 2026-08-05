using Octopus, CUDA
const CUDABackend = Octopus.CUDABackend
using Octopus: _ACTIVE_PIC_LUMINOSITY_PAIR_SINK, Phase6DRep, coordinate_arrays
using Base.ScopedValues: with

const N = 4000
const NS = 5

function base_beams(T=Float64)
    b1 = Beam(N, CPUThreadsBackend, T;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=Octopus.EMASS_EV, E0=10e9, r0=Octopus.RE, npart=1.7203e11)
    b2 = Beam(N, CPUThreadsBackend, T;
        beta=(0.8, 0.072, 6e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(95e-6, 8.5e-6, 6e-2), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=Octopus.PMASS_EV, E0=275e9,
        r0=Octopus.RE * Octopus.ME0 / Octopus.PMASS_EV, npart=0.6881e11)
    return b1, b2
end
host(a) = copy(Array(a))
function to_backend(b, backend)
    rep = backend === CUDABackend ?
        Phase6DRep((CUDA.CuArray(host(a)) for a in coordinate_arrays(b.rep))...) :
        Phase6DRep((host(a) for a in coordinate_arrays(b.rep))...)
    return Beam{backend,typeof(b.params),typeof(rep)}(b.params, rep)
end
coords(b) = (host(b.rep.x), host(b.rep.px), host(b.rep.y), host(b.rep.py), host(b.rep.z), host(b.rep.pz))
maxdiff(a, b) = maximum(maximum(abs.(u .- v)) for (u, v) in zip(a, b))
scale(a) = maximum(maximum(abs.(u)) for u in a)

function run_case(; backend, turns=2, grid=(32,32), deposit_method=:CIC,
                  luminosity_deposit_method=nothing, luminosity_grid=nothing,
                  slice_interpolation=:linear, interaction_grid=:slice_pair,
                  batch_mode=:wavefront, cuda_async=true, cuda_batch_fft=true,
                  cuda_wavefront_fft=true, cuda_indexed_wavefront=true,
                  green_cache=:slice_pair, longitudinal_kick=true,
                  diagnostics=StrongStrongDiagnostics())
    b1o, b2o = base_beams()
    b1 = to_backend(b1o, backend); b2 = to_backend(b2o, backend)
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=NS, center_position=:centroid)
    kwargs = Dict{Symbol,Any}(:slicing=>slicing, :grid=>grid, :deposit_method=>deposit_method,
        :green_cache=>green_cache, :batch_mode=>batch_mode,
        :slice_interpolation=>slice_interpolation, :interaction_grid=>interaction_grid,
        :cuda_async=>cuda_async, :cuda_batch_fft=>cuda_batch_fft,
        :cuda_wavefront_fft=>cuda_wavefront_fft, :cuda_indexed_wavefront=>cuda_indexed_wavefront,
        :longitudinal_kick=>longitudinal_kick, :luminosity_schedule=>nothing)
    luminosity_deposit_method === nothing || (kwargs[:luminosity_deposit_method] = luminosity_deposit_method)
    luminosity_grid === nothing || (kwargs[:luminosity_grid] = luminosity_grid)
    solver = PICPoissonSolver(; kwargs...)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    mktempdir() do dir
        p = joinpath(dir, "lum")
        task = StrongStrongTask((ip,), (ip,); luminosity_path=p, diagnostics=diagnostics)
        sink = Any[]
        with(_ACTIVE_PIC_LUMINOSITY_PAIR_SINK => sink) do
            execute!(task, b1, b2; turns=turns)
        end
        backend === CUDABackend && CUDA.synchronize()
        series = [parse(Float64, last(split(l, '\t'))) for l in readlines(p)[2:end]]
        return (c1=coords(b1), c2=coords(b2), sink=length(sink), lum=series)
    end
end

function report(title, cases)
    println("\n", "=" ^ 78); println(title); println("=" ^ 78)
    res = Dict{String,Any}()
    for (name, kw) in cases
        try
            res[name] = run_case(; kw...)
        catch e
            println(rpad(name, 44), " THREW: ", first(sprint(showerror, e), 200)); continue
        end
    end
    haskey(res, "CPU") || return res
    ref = res["CPU"]; sc = max(scale(ref.c1), scale(ref.c2))
    for (name, _) in cases
        haskey(res, name) || continue
        d = max(maxdiff(ref.c1, res[name].c1), maxdiff(ref.c2, res[name].c2))
        dl = maximum(abs.(res[name].lum .- ref.lum) ./ abs.(ref.lum))
        println("  ", rpad(name, 42), " coord_rel=", d/sc, "  lum_rel=", dl, "  sink=", res[name].sink)
    end
    return res
end

report("TSC luminosity deposit (U5-8 full-extent overlap sum) across CUDA routes", [
  ("CPU",                        (backend=CPUThreadsBackend, luminosity_deposit_method=:TSC)),
  ("CUDA indexed wavefront",     (backend=CUDABackend, luminosity_deposit_method=:TSC)),
  ("CUDA gathered wavefront",    (backend=CUDABackend, luminosity_deposit_method=:TSC, cuda_indexed_wavefront=false)),
  ("CUDA per-pair batched",      (backend=CUDABackend, luminosity_deposit_method=:TSC, cuda_wavefront_fft=false)),
  ("CUDA async per-pair",        (backend=CUDABackend, luminosity_deposit_method=:TSC, cuda_batch_fft=false)),
  ("CUDA sequential",            (backend=CUDABackend, luminosity_deposit_method=:TSC, batch_mode=:sequential, cuda_async=false)),
  ("CUDA node indexed",          (backend=CUDABackend, luminosity_deposit_method=:TSC, interaction_grid=:node)),
])

report("TSC interaction deposit", [
  ("CPU",                        (backend=CPUThreadsBackend, deposit_method=:TSC)),
  ("CUDA indexed wavefront",     (backend=CUDABackend, deposit_method=:TSC)),
  ("CUDA gathered wavefront",    (backend=CUDABackend, deposit_method=:TSC, cuda_indexed_wavefront=false)),
  ("CUDA sequential",            (backend=CUDABackend, deposit_method=:TSC, batch_mode=:sequential, cuda_async=false)),
])

report("node longitudinal_kick=false, node reference", [
  ("CPU",                        (backend=CPUThreadsBackend, interaction_grid=:node, longitudinal_kick=false)),
  ("CUDA node indexed",          (backend=CUDABackend, interaction_grid=:node, longitudinal_kick=false)),
  ("CUDA node sequential",       (backend=CUDABackend, interaction_grid=:node, longitudinal_kick=false, batch_mode=:sequential, cuda_async=false)),
])

report("large luminosity grid + TSC (stresses overlap partials block count)", [
  ("CPU",                        (backend=CPUThreadsBackend, luminosity_deposit_method=:TSC, luminosity_grid=(129,129))),
  ("CUDA indexed wavefront",     (backend=CUDABackend, luminosity_deposit_method=:TSC, luminosity_grid=(129,129))),
  ("CUDA gathered wavefront",    (backend=CUDABackend, luminosity_deposit_method=:TSC, luminosity_grid=(129,129), cuda_indexed_wavefront=false)),
])
