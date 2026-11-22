# Dump the PTX of the case L fused kernel (81 elements) for ptxas -v and the static SASS count.
import CUDA
nst = get(ENV, "OCT_NST", "1"); order = get(ENV, "OCT_ORDER", "2")
dir = joinpath(@__DIR__, "..", "..", "..", "result", "bbscl_comparison", "eltype", "dump_L81_nst$(nst)o$(order)")
ENV["OCT_MODE"] = "track"; ENV["OCT_GPU"] = "1"; ENV["OCT_NCELL"] = "8"; ENV["OCT_N"] = "20480"
ENV["OCT_TURNS"] = "2"; ENV["OCT_WARMUP"] = "1"; ENV["OCT_MOMENTS_EVERY"] = "0"
ENV["OCT_OPTICS"] = joinpath(@__DIR__, "..", "..", "..", "validation", "bbscl_comparison", "lattice_optics.txt")
ENV["OCT_OUT"] = joinpath(dir, "dump_run.tsv")
mkpath(dir)
t0 = time()
io = open(joinpath(dir, "all.ptx"), "w")
CUDA.@device_code_ptx io=io dump_module=true include(joinpath(@__DIR__, "..", "..", "..", "validation", "bbscl_comparison", "octopus_lattice_bbscl.jl"))
close(io)
println("dump done in $(round(time() - t0, digits = 1)) s -> $dir")
for (k, v) in Main.Octopus._CUDA_FUSED_OCCUPANCY_CACHE
    println("occupancy: threads/block=", k[5], "  active blocks/SM=", v, "  resident warps/SM=", v * k[5] ÷ 32, "  (max 48)")
end
