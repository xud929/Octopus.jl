### U7 probe 9: the JLD2 observer's file-size growth law, and the seek-past-EOF
### hole in the binary observer, and the record_count-blind non-.h5 reader.
using Octopus, Printf
const OUT = @__DIR__
mkrep() = Phase6DRep([1.0e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
const LINE = (DriftSpec(L = 1.0),)

println("="^72)
println("A. JLD2BeamMomentObserver file size vs rows (capacity=1, the default)")
println("="^72)
ncol = length(Octopus._jld2_moment_column_names())
println("   columns=", ncol, "   useful bytes = 8*ncol*rows")
for n in (100, 200, 400, 800)
    p = joinpath(OUT, "g.jld2"); rm(p; force = true)
    t = TrackingTask(LINE; hooks = (ScheduledObserver(JLD2BeamMomentObserver(p)),))
    el = @elapsed execute!(t, mkrep(); turns = n)
    sz = filesize(p)
    useful = 8 * ncol * n
    @printf("   rows=%-5d  file=%10d B  useful=%8d B  blowup=%7.1fx  time=%6.3f s\n",
            n, sz, useful, sz / useful, el)
    rm(p; force = true)
end
println("   quadratic model  sum_{k=1..n} 8*ncol*k = 4*ncol*n*(n+1):")
for n in (100, 200, 400, 800)
    @printf("     n=%-5d model=%10d B\n", n, 4 * ncol * n * (n + 1))
end

println()
println("="^72)
println("B. capacity mitigates it only linearly")
println("="^72)
for cap in (1, 10, 100)
    p = joinpath(OUT, "g2.jld2"); rm(p; force = true)
    t = TrackingTask(LINE; hooks = (ScheduledObserver(JLD2BeamMomentObserver(p; capacity = cap)),))
    el = @elapsed execute!(t, mkrep(); turns = 800)
    @printf("   capacity=%-4d file=%10d B  time=%6.3f s\n", cap, filesize(p), el)
    rm(p; force = true)
end

println()
println("="^72)
println("C. binary observer: an externally shortened file makes the next flush")
println("   seek past EOF and write into a hole (count then covers zero rows)")
println("="^72)
p = joinpath(OUT, "hole.dat"); rm(p; force = true)
o = BeamMomentObserver(p; capacity = 2)
t = TrackingTask(LINE; hooks = (ScheduledObserver(o),))
execute!(t, mkrep(); turns = 4)
println("   after 4 turns: size=", filesize(p), "  observer.record_count=", o.record_count)
# a second writer on the same path reinitialises the file (header only)
o2 = BeamMomentObserver(p; capacity = 2)
t2 = TrackingTask(LINE; hooks = (ScheduledObserver(o2),))
execute!(t2, mkrep(); turns = 2)
println("   after a second observer wrote 2 turns: size=", filesize(p),
        "  reported_count=", open(io -> Int(read(io, Int32)), p, "r"))
execute!(t, mkrep(); turns = 2)     # the FIRST observer flushes again
sz = filesize(p)
turns = open(p, "r") do io
    n = Int(read(io, Int32)); fl = Int(read(io, Int32))
    s = String(read(io, fl)); nc = count(==(','), s) + 1
    [(seek(io, 8 + fl + (i - 1) * nc * 8); read(io, Float64)) for i in 1:n]
end
println("   after the FIRST observer flushed again: size=", sz)
println("   turn column read back = ", turns)
println("   (zeros are hole bytes: rows that were never written but are counted)")
rm(p; force = true)

println()
println("="^72)
println("D. MomentObserver on a non-.h5 path: the reader ignores /record_count")
println("="^72)
p = joinpath(OUT, "m.dat"); rm(p; force = true)
struct Boom <: Octopus.AbstractBeamAction; at::Int; end
Octopus.apply_action!(a::Boom, ctx, rep) = (ctx.turn == a.at && error("boom"); nothing)
o = MomentObserver(p; orders = 1, capacity = 1)
t = TrackingTask(LINE; hooks = (Boom(3), ScheduledObserver(o)))
try; execute!(t, mkrep(); turns = 8); catch; end
h5rows = Octopus.HDF5.h5open(f -> (size(f["data"], 1), Int(read(f["record_count"])[1])), p, "r")
println("   /data rows=", h5rows[1], "  /record_count=", h5rows[2])
println("   Octopus._is_hdf5_output(\"m.dat\") = ", Octopus._is_hdf5_output(p))
d = read(MomentOutputFile(p))
println("   read(MomentOutputFile) returned rows=", size(d, 1),
        "   turn column=", Int.(d[:, 1]))
println("   (an .h5 path would have returned ", h5rows[2], " rows)")
rm(p; force = true)
