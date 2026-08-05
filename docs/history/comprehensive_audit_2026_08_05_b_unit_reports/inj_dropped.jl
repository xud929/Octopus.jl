include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
const TS = "/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/ts_dropped.jl"
function runts(label)
    ok = try
        Test.@testset "$label" begin include(TS) end
        true
    catch e
        false
    end
    println(">>> ", label, " => ", ok ? "PASSED (defect NOT caught)" : "FAILED (defect caught)")
end
runts("D0-baseline")

# D1: per-AXIS counting (the recorded U5-6 defect)
Octopus.eval(quote
    function _pic_count_outside_box(xs, ys, xlo, xhi, ylo, yhi)
        c = 0
        for i in eachindex(xs, ys)
            @inbounds x = xs[i]; @inbounds y = ys[i]
            (isfinite(x) && xlo <= x <= xhi) || (c += 1)
            (isfinite(y) && ylo <= y <= yhi) || (c += 1)
        end
        return c
    end
end)
runts("D1-per-axis-count")

# restore
Octopus.eval(quote
    function _pic_count_outside_box(xs, ys, xlo, xhi, ylo, yhi)
        c = 0
        for i in eachindex(xs, ys)
            @inbounds x = xs[i]; @inbounds y = ys[i]
            (isfinite(x) && xlo <= x <= xhi &&
             isfinite(y) && ylo <= y <= yhi) || (c += 1)
        end
        return c
    end
end)

# D2: NaN treated as inside (the isfinite guard dropped)
Octopus.eval(quote
    function _pic_count_outside_box(xs, ys, xlo, xhi, ylo, yhi)
        c = 0
        for i in eachindex(xs, ys)
            @inbounds x = xs[i]; @inbounds y = ys[i]
            (xlo <= x <= xhi && ylo <= y <= yhi) || (c += 1)
        end
        return c
    end
end)
runts("D2-nan-blind")
Octopus.eval(quote
    function _pic_count_outside_box(xs, ys, xlo, xhi, ylo, yhi)
        c = 0
        for i in eachindex(xs, ys)
            @inbounds x = xs[i]; @inbounds y = ys[i]
            (isfinite(x) && xlo <= x <= xhi &&
             isfinite(y) && ylo <= y <= yhi) || (c += 1)
        end
        return c
    end
end)

# D3: drifted variant counts per PLANE (the recorded U5-5 defect)
Octopus.eval(quote
    function _pic_count_outside_box_drifted(xs, pxs, ys, pys, sL, sR, xlo, xhi, ylo, yhi)
        c = 0
        for i in eachindex(xs, pxs, ys, pys)
            @inbounds begin
                xl = xs[i] + pxs[i]*sL; yl = ys[i] + pys[i]*sL
                xr = xs[i] + pxs[i]*sR; yr = ys[i] + pys[i]*sR
            end
            (isfinite(xl) && xlo <= xl <= xhi && isfinite(yl) && ylo <= yl <= yhi) || (c += 1)
            (isfinite(xr) && xlo <= xr <= xhi && isfinite(yr) && ylo <= yr <= yhi) || (c += 1)
        end
        return c
    end
end)
runts("D3-drifted-per-plane")
Octopus.eval(quote
    function _pic_count_outside_box_drifted(xs, pxs, ys, pys, sL, sR, xlo, xhi, ylo, yhi)
        c = 0
        for i in eachindex(xs, pxs, ys, pys)
            @inbounds begin
                xl = xs[i] + pxs[i]*sL; yl = ys[i] + pys[i]*sL
                xr = xs[i] + pxs[i]*sR; yr = ys[i] + pys[i]*sR
            end
            (isfinite(xl) && xlo <= xl <= xhi && isfinite(yl) && ylo <= yl <= yhi &&
             isfinite(xr) && xlo <= xr <= xhi && isfinite(yr) && ylo <= yr <= yhi) || (c += 1)
        end
        return c
    end
end)

# D4: the drop counter is never incremented (silent again) -- patch the counters to 0
Octopus.eval(quote
    function _pic_count_outside_box(xs, ys, xlo, xhi, ylo, yhi); return 0; end
    function _pic_count_outside_box_drifted(xs, pxs, ys, pys, sL, sR, xlo, xhi, ylo, yhi); return 0; end
end)
runts("D4-counter-always-zero")
