include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
closed(f) = f < 0.5 ? (t = f*f; (0.125 + 0.5*(t-f), 0.75-t, 0.125+0.5*(t+f))) :
                      (fr = 1.0-f; t = fr*fr; (0.125+0.5*(t+fr), 0.75-t, 0.125+0.5*(t-fr)))
compl(f) = (w = closed(f); (w[1], w[2], 1.0 - w[1] - w[2]))
for f in (0.3, 0.1, 1/3, 0.7, 0.25, 0.125, 0.05859375)
    println("f = ", rpad(f, 20), " closed w3 = ", closed(f)[3],
            "  complement = ", compl(f)[3], "   differ = ", closed(f)[3] !== compl(f)[3])
end
