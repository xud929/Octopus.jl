# P4 -- hypothesis (d): F17 bitwise verification.
#   (1) `curved = false` equals `h = 0` EXACTLY (bitwise) for the solenoid,
#       and for the LatticeMagnet family (U10-4's sibling claim).
#   (2) the straight solenoid body is real-arithmetic and BIT-IDENTICAL to its
#       complex predecessor.
using Octopus
const O = Octopus

bits(x) = reinterpret(UInt64, Float64(x))
same(a, b) = all(bits(a[i]) === bits(b[i]) for i in eachindex(a))

const PTS = [
    (1.3e-3, 4.1e-4, -8.7e-4, -2.3e-4, 6.5e-4, 1.7e-3),
    (7.0e-3, 2.0e-3, -5.0e-3, 1.5e-3, 3.0e-3, 5.0e-3),
    (-2.5e-2, -9.0e-3, 1.1e-2, 7.0e-3, -4.0e-3, -8.0e-3),
    (0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
    (1e-9, -1e-9, 1e-9, 1e-9, 0.0, 1e-9),
]

println("="^110)
println("P4 (1)  solenoid: curved=false with h != 0  MUST be bit-identical to the same element at h = 0")
println("="^110)
for (L, ks, h) in ((1.3, 1.7, 0.18), (1.3, 1.7, 1e-3), (0.5, -0.9, 2.5), (2.0, 0.35, 1e-300))
    for (name, kw) in (("pure", NamedTuple()),
                       ("k1=0.9", (k1=0.9,)),
                       ("k0s=0.05", (k0s=0.05,)),
                       ("k1=0.9,k2=4,k1s=0.4", (k1=0.9, k2=4.0, k1s=0.4)))
        a = Solenoid(SolenoidSpec(; L=L, ks=ks, h=h, curved=false, nst=4, kw...))
        b = Solenoid(SolenoidSpec(; L=L, ks=ks, h=0.0, nst=4, kw...))
        ok = all(same(collect(a(p...)), collect(b(p...))) for p in PTS)
        # also compare the stored field
        println(rpad("L=$L ks=$ks h=$h $name", 46),
                " bitwise-equal=", rpad(ok, 6),
                " stored h: curved=false -> ", a.h, "   h=0 -> ", b.h,
                "   type CURVED=", typeof(a).parameters[4], "/", typeof(b).parameters[4])
    end
end

println("\n" * "="^110)
println("P4 (1b) LatticeMagnet: curved=false with h != 0 MUST be bit-identical to the same element at h = 0")
println("="^110)
for h in (0.21, 1e-3, 2.5)
    for (name, spec_false, spec_zero) in (
        ("drift",
         DriftSpec(L=0.9, h=h, curved=false),
         DriftSpec(L=0.9, h=0.0)),
        ("quad k1=1.4",
         SBendSpec(L=0.9, h=h, b0=0.0, k1=1.4, curved=false, nst=3, bend_fringe=false),
         SBendSpec(L=0.9, h=0.0, b0=0.0, k1=1.4, nst=3, bend_fringe=false)),
        ("combined k1,k2,k1s",
         SBendSpec(L=0.9, h=h, b0=0.0, k1=1.4, k2=6.0, k1s=0.5, curved=false, nst=3, bend_fringe=false),
         SBendSpec(L=0.9, h=0.0, b0=0.0, k1=1.4, k2=6.0, k1s=0.5, nst=3, bend_fringe=false)),
        ("skew dipole k0s",
         SBendSpec(L=0.9, h=h, b0=0.0, kn=(0.0,), ks=(0.05,), curved=false, nst=3, bend_fringe=false),
         SBendSpec(L=0.9, h=0.0, b0=0.0, kn=(0.0,), ks=(0.05,), nst=3, bend_fringe=false)))
        a = compile_runtime(spec_false); b = compile_runtime(spec_zero)
        ok = all(same(collect(a(p...)), collect(b(p...))) for p in PTS)
        println(rpad("h=$h $name", 46), " bitwise-equal=", rpad(ok, 6),
                " stored h: ", a.h, " / ", b.h,
                "  NC(psi len)=", length(a.psi), "/", length(b.psi))
    end
end

println("\n" * "="^110)
println("P4 (2)  straight solenoid body: real transcription vs the complex predecessor, BITWISE")
println("="^110)
# The complex predecessor, transcribed verbatim from the pre-F17 source
# (git 6a3f39ab, src/elements/solenoid.jl `_solenoid_map`).
@inline function _solenoid_map_complex(ks::T, L::T, x, px, y, py, z, pz) where {T}
    k = ks / 2
    Px, Py = O._solenoid_edge(k, x, y, px, py)
    ps = sqrt((1 + pz)^2 - Px * Px - Py * Py)
    kappa = ks / ps
    half = cis(-kappa * L / 2)
    rot = half * half
    W0 = complex(Px, Py)
    w = complex(x, y) + (W0 / ps) * O._curv_sin(kappa / 2, L) * half
    W = W0 * rot
    xn, yn = real(w), imag(w)
    pxn, pyn = O._solenoid_edge(-k, xn, yn, real(W), imag(W))
    return xn, pxn, yn, pyn, z + L * (1 - (1 + pz) / ps), pz
end

nbad = 0; ntot = 0
for ks in (1.7, -1.7, 0.35, 0.0, 1e-8, 1e-14, 50.0), L in (1.3, 0.05, 3.7, 0.0, 1e-6)
    for p in PTS
        a = collect(O._solenoid_map(ks, L, p...))
        b = collect(_solenoid_map_complex(ks, L, p...))
        global ntot += 1
        if !same(a, b)
            global nbad += 1
            println("  MISMATCH ks=$ks L=$L p=$p")
            for i in 1:6
                bits(a[i]) === bits(b[i]) || println("    coord $i: real=", a[i], " (", repr(bits(a[i])),
                                                     ")  complex=", b[i], " (", repr(bits(b[i])), ")")
            end
        end
    end
end
println("  compared $ntot (ks, L, point) combinations; bitwise mismatches = ", nbad)

# random sweep, wide dynamic range
using Random
Random.seed!(20260805)
nbad2 = 0; ntot2 = 0
for _ in 1:200000
    ks = (rand() - 0.5) * 20
    L = (rand() - 0.5) * 8
    p = (randn() * 1e-2, randn() * 3e-3, randn() * 1e-2, randn() * 3e-3, randn() * 1e-2, randn() * 1e-2)
    a = collect(O._solenoid_map(ks, L, p...))
    b = collect(_solenoid_map_complex(ks, L, p...))
    global ntot2 += 1
    all(isfinite, a) || continue
    if !same(a, b)
        global nbad2 += 1
        nbad2 <= 3 && println("  RANDOM MISMATCH ks=$ks L=$L p=$p\n    real=$a\n    cplx=$b")
    end
end
println("  random sweep: $ntot2 draws, bitwise mismatches = ", nbad2)

println("\n" * "="^110)
println("P4 (2b) full compiled straight solenoid element vs the complex-body element, BITWISE")
println("="^110)
# Rebuild the whole Strang split around the complex body to check the element,
# not only the kernel.
function strang_complex(elem, x, px, y, py, z, pz)
    nst = elem.nst; d = elem.L / nst; dh = d / 2
    for _ in 1:nst
        x, px, y, py, z, pz = _solenoid_map_complex(elem.ks, dh, x, px, y, py, z, pz)
        x, px, y, py, z, pz = O._lattice_kick(elem.kn, elem.ksk, elem.h, d, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _solenoid_map_complex(elem.ks, dh, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end
for (name, sp) in (("pure", SolenoidSpec(L=1.3, ks=1.7)),
                   ("+k1 nst=4", SolenoidSpec(L=1.3, ks=1.7, k1=0.9, nst=4)),
                   ("+k1,k2,k1s nst=8", SolenoidSpec(L=1.3, ks=1.7, k1=0.9, k2=4.0, k1s=0.4, nst=8)))
    e = Solenoid(sp)
    ok = all(begin
        a = collect(e(p...))
        b = e isa Solenoid{<:Any,<:Any,0} ?
            collect(_solenoid_map_complex(e.ks, e.L, p...)) :
            collect(strang_complex(e, p...))
        same(a, b)
    end for p in PTS)
    println(rpad(name, 30), " bitwise-equal to complex predecessor = ", ok)
end
