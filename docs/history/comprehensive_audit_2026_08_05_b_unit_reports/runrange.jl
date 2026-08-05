# U19 probe harness: run a chosen line range of test/runtests.jl in isolation.
# Usage: julia --project=. -t4 runrange.jl LO HI [LO2 HI2 ...]
using Test
using Octopus
using LinearAlgebra
using ForwardDiff
using Symbolics

const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
@info "CUDA_TESTS_ACTIVE" CUDA_TESTS_ACTIVE Threads.nthreads(:default)

const SRC = joinpath(dirname(dirname(pathof(Octopus))), "test", "runtests.jl")
const LINES = readlines(SRC)

# helper definitions that live OUTSIDE the audited region but are used inside it
for r in (4327:4332, 4401:4425, 4637:4663, 5035:5048)
    Core.eval(Main, Meta.parseall(join(LINES[r], "\n"); filename=SRC))
end

function runrange(lo, hi)
    src = join(LINES[lo:hi], "\n")
    ex = Meta.parseall(src; filename="$(SRC):$lo")
    Core.eval(Main, ex)
end

args = parse.(Int, ARGS)
for k in 1:2:length(args)
    lo, hi = args[k], args[k+1]
    @info "=== running lines $lo:$hi ==="
    runrange(lo, hi)
end
