using Octopus, CUDA
const CUDABackend = Octopus.CUDABackend
using Octopus: _ACTIVE_PIC_LUMINOSITY_PAIR_SINK, Phase6DRep, coordinate_arrays
using Base.ScopedValues: with

const N = 4000
const NS = 5
const GRID = (32, 32)

function base_beams()
    b1 = Beam(N, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
        sigma=(106e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=Octopus.EMASS_EV, E0=10e9, r0=Octopus.RE, npart=1.7203e11)
    b2 = Beam(N, CPUThreadsBackend, Float64;
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

function make_task(; path, slice_interpolation=:linear, interaction_grid=:slice_pair,
                   batch_mode=:wavefront, cuda_async=true, cuda_batch_fft=true,
                   cuda_wavefront_fft=true, cuda_indexed_wavefront=true,
                   green_cache=:slice_pair, longitudinal_kick=true,
                   diagnostics=StrongStrongDiagnostics())
    slicing = LongitudinalSlicing(method=:normal_quantile, nslices=NS, center_position=:centroid)
    solver = PICPoissonSolver(
        slicing=slicing, grid=GRID, deposit_method=:CIC,
        green_cache=green_cache, batch_mode=batch_mode,
        slice_interpolation=slice_interpolation, interaction_grid=interaction_grid,
        cuda_async=cuda_async, cuda_batch_fft=cuda_batch_fft,
        cuda_wavefront_fft=cuda_wavefront_fft,
        cuda_indexed_wavefront=cuda_indexed_wavefront,
        longitudinal_kick=longitudinal_kick, luminosity_schedule=nothing)
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    return StrongStrongTask((ip,), (ip,); luminosity_path=path, diagnostics=diagnostics)
end

coords(b) = (host(b.rep.x), host(b.rep.px), host(b.rep.y), host(b.rep.py), host(b.rep.z), host(b.rep.pz))
maxdiff(a, b) = maximum(maximum(abs.(u .- v)) for (u, v) in zip(a, b))
scale(a) = maximum(maximum(abs.(u)) for u in a)

function run_case(; backend, turns=2, kw...)
    b1o, b2o = base_beams()
    b1 = to_backend(b1o, backend); b2 = to_backend(b2o, backend)
    mktempdir() do dir
        task = make_task(; path=joinpath(dir, "lum"), kw...)
        sink = Any[]
        lums = with(_ACTIVE_PIC_LUMINOSITY_PAIR_SINK => sink) do
            execute!(task, b1, b2; turns=turns)
            readlines(joinpath(dir, "lum"))
        end
        backend === CUDABackend && CUDA.synchronize()
        lastlum = parse(Float64, last(split(last(lums), '\t')))
        return (c1=coords(b1), c2=coords(b2), sink=length(sink), lum=lastlum)
    end
end

function report(title, cases)
    println("\n", "=" ^ 78); println(title); println("=" ^ 78)
    res = Dict{String,Any}()
    for (name, kw) in cases
        try
            res[name] = run_case(; kw...)
            println(rpad(name, 46), " sink=", res[name].sink, "  lum=", res[name].lum)
        catch e
            println(rpad(name, 46), " THREW: ", first(sprint(showerror, e), 200))
        end
    end
    haskey(res, "CPU") || return res
    ref = res["CPU"]; sc = max(scale(ref.c1), scale(ref.c2))
    println("\n  max|delta| vs CPU (scale=$(sc)):")
    for (name, _) in cases
        haskey(res, name) || continue
        d = max(maxdiff(ref.c1, res[name].c1), maxdiff(ref.c2, res[name].c2))
        dl = abs(res[name].lum - ref.lum) / abs(ref.lum)
        println("    ", rpad(name, 44), " coord_rel=", d / sc, "  lum_rel=", dl)
    end
    return res
end

report("QUADRATIC slice_interpolation across CUDA sub-routes", [
  ("CPU",                              (backend=CPUThreadsBackend, slice_interpolation=:quadratic)),
  ("CUDA quad indexed wavefront",      (backend=CUDABackend, slice_interpolation=:quadratic)),
  ("CUDA quad gathered wavefront",     (backend=CUDABackend, slice_interpolation=:quadratic, cuda_indexed_wavefront=false)),
  ("CUDA quad per-pair batched",       (backend=CUDABackend, slice_interpolation=:quadratic, cuda_wavefront_fft=false)),
  ("CUDA quad + pic_timing_detail",    (backend=CUDABackend, slice_interpolation=:quadratic, diagnostics=StrongStrongDiagnostics(pic_timing_detail=true))),
  ("CUDA quad sequential",             (backend=CUDABackend, slice_interpolation=:quadratic, batch_mode=:sequential, cuda_async=false)),
])

report("NODE interaction_grid across CUDA sub-routes", [
  ("CPU",                              (backend=CPUThreadsBackend, interaction_grid=:node)),
  ("CUDA node indexed wavefront",      (backend=CUDABackend, interaction_grid=:node)),
  ("CUDA node + pic_timing_detail",    (backend=CUDABackend, interaction_grid=:node, diagnostics=StrongStrongDiagnostics(pic_timing_detail=true))),
  ("CUDA node sequential",             (backend=CUDABackend, interaction_grid=:node, batch_mode=:sequential, cuda_async=false)),
])

report("QUADRATIC with longitudinal_kick=false (F10 regression check)", [
  ("CPU",                              (backend=CPUThreadsBackend, slice_interpolation=:quadratic, longitudinal_kick=false)),
  ("CUDA quad indexed, longkick=false",(backend=CUDABackend, slice_interpolation=:quadratic, longitudinal_kick=false)),
  ("CUDA quad gathered, longkick=false",(backend=CUDABackend, slice_interpolation=:quadratic, longitudinal_kick=false, cuda_indexed_wavefront=false)),
  ("CUDA node indexed, longkick=false",(backend=CUDABackend, interaction_grid=:node, longitudinal_kick=false)),
])

report("green_cache = :none vs :slice_pair (CUDA)", [
  ("CPU",                              (backend=CPUThreadsBackend, green_cache=:none)),
  ("CUDA green_cache=:none",           (backend=CUDABackend, green_cache=:none)),
  ("CUDA green_cache=:none gathered",  (backend=CUDABackend, green_cache=:none, cuda_indexed_wavefront=false)),
])
