include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
# Does the recorded U2-3 defect (w3 = 1 - w1 - w2) actually differ from the
# closed form, and does the testset's sample grid contain any input where it does?
closed(f) = begin
    if f < 0.5
        t = f * f
        (0.125 + 0.5*(t - f), 0.75 - t, 0.125 + 0.5*(t + f))
    else
        fr = 1.0 - f; t = fr*fr
        (0.125 + 0.5*(t + fr), 0.75 - t, 0.125 + 0.5*(t - fr))
    end
end
compl(f) = begin
    w1, w2, _ = closed(f)
    (w1, w2, 1.0 - w1 - w2)
end
# 1. the testset's own sample grid
function suite_scan()
    suite_hits = 0; suite_n = 0
    for n in (16, 33)
        for u in vcat(collect(range(0.0, n - 1.0; length=257)),
                      [0.5, 1.5, 7.25, 7.5, 7.75, n - 1.5, n - 1.0])
            (0.0 <= u <= n - 1.0) || continue
            f = u - floor(u)
            suite_n += 1
            closed(f)[3] === compl(f)[3] || (suite_hits += 1)
        end
    end
    return suite_n, suite_hits
end
let (sn, sh) = suite_scan()
    println("testset grid: ", sn, " in-range samples, ", sh, " expose the w3 = 1-w1-w2 defect")
end

# 2. how rare is the defect over a dense random sweep of the fractional part?
using Random
function randscan(N)
    rng = MersenneTwister(1); hits = 0
    for _ in 1:N
        f = rand(rng)
        closed(f)[3] === compl(f)[3] || (hits += 1)
    end
    hits
end
let N = 2_000_000, hits = randscan(N)
    println("random f in [0,1): ", hits, " of ", N, "  (", round(100*hits/N; digits=3), "%) differ")
end

# 3. a dense uniform grid: what fraction of f = k/2^m differ?
function gridscan(m)
    h = 0; tot = 0
    for k in 0:(2^m - 1)
        f = k / 2^m; tot += 1
        closed(f)[3] === compl(f)[3] || (h += 1)
    end
    (h, tot)
end
for m in (8, 10, 12)
    (h, tot) = gridscan(m)
    println("f = k/2^", m, ": ", h, " of ", tot, " differ")
end

# 4. Is the testset's grid special? its f values for n=16 are multiples of 15/256
function suitegrid()
    h = 0; tot = 0
    for k in 0:255
        f = mod(k * 15 / 256, 1.0); tot += 1
        closed(f)[3] === compl(f)[3] || (h += 1)
    end
    (h, tot)
end
let (h, tot) = suitegrid()
    println("f = mod(k*15/256,1): ", h, " of ", tot, " differ")
end
