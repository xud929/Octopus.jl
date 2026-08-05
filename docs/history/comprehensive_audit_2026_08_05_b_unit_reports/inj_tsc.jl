include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
const TS = "/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/ts_tsc.jl"
caught(label) = begin
    r = @testset NoThrowTestSet "inj" begin include(TS) end
    nothing
end
function runts(label)
    res = Test.DefaultTestSet("x")
    passed = try
        Test.@testset "$label" begin include(TS) end
        true
    catch e
        false
    end
    println(label, " => ", passed ? "PASSED (defect NOT caught)" : "FAILED (defect caught)")
end

println("--- baseline (no injection) ---")
runts("baseline")

println("--- injection 1: w3 = 1 - w1 - w2 (the recorded U2-3 defect) ---")
Octopus.eval(quote
    @inline function _cuda_pic_tsc_weights(u, n::Int32)
        if !(zero(u) <= u <= convert(typeof(u), n - Int32(1)))
            return Int32(1), zero(u), zero(u), zero(u)
        end
        f0 = floor(u); ix = Int32(f0); f = u - f0
        if f < typeof(u)(0.5)
            t = f * f
            w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t - f)
            w2 = typeof(u)(0.75) - t
            w3 = one(u) - w1 - w2                      # INJECTED DEFECT
            base = ix
        else
            fr = one(u) - f
            t = fr * fr
            w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t + fr)
            w2 = typeof(u)(0.75) - t
            w3 = one(u) - w1 - w2                      # INJECTED DEFECT
            base = ix + Int32(1)
        end
        return clamp(base, Int32(1), n - Int32(2)), w1, w2, w3
    end
end)
runts("inj1-complement")

println("--- injection 2: out-of-range returns base 0 instead of 1 ---")
Octopus.eval(quote
    @inline function _cuda_pic_tsc_weights(u, n::Int32)
        if !(zero(u) <= u <= convert(typeof(u), n - Int32(1)))
            return Int32(0), zero(u), zero(u), zero(u)   # INJECTED DEFECT
        end
        f0 = floor(u); ix = Int32(f0); f = u - f0
        if f < typeof(u)(0.5)
            t = f * f
            w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t - f)
            w2 = typeof(u)(0.75) - t
            w3 = typeof(u)(0.125) + typeof(u)(0.5) * (t + f)
            base = ix
        else
            fr = one(u) - f
            t = fr * fr
            w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t + fr)
            w2 = typeof(u)(0.75) - t
            w3 = typeof(u)(0.125) + typeof(u)(0.5) * (t - fr)
            base = ix + Int32(1)
        end
        return clamp(base, Int32(1), n - Int32(2)), w1, w2, w3
    end
end)
runts("inj2-out-of-range-base")

println("--- injection 3: clamp lower bound wrong (base clamped to 0) ---")
Octopus.eval(quote
    @inline function _cuda_pic_tsc_weights(u, n::Int32)
        if !(zero(u) <= u <= convert(typeof(u), n - Int32(1)))
            return Int32(1), zero(u), zero(u), zero(u)
        end
        f0 = floor(u); ix = Int32(f0); f = u - f0
        if f < typeof(u)(0.5)
            t = f * f
            w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t - f)
            w2 = typeof(u)(0.75) - t
            w3 = typeof(u)(0.125) + typeof(u)(0.5) * (t + f)
            base = ix
        else
            fr = one(u) - f
            t = fr * fr
            w1 = typeof(u)(0.125) + typeof(u)(0.5) * (t + fr)
            w2 = typeof(u)(0.75) - t
            w3 = typeof(u)(0.125) + typeof(u)(0.5) * (t - fr)
            base = ix + Int32(1)
        end
        return clamp(base, Int32(0), n - Int32(2)), w1, w2, w3   # INJECTED DEFECT
    end
end)
runts("inj3-clamp-lower")
