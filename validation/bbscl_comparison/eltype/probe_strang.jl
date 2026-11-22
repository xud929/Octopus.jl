# Variants of the thick-magnet Strang path, swapped in by @eval before the kernel compiles
# (A/B probe only). OCT_VARIANT: orig | nokick | directdrift | noloop | loopdirect_nokick
include(joinpath(@__DIR__, "..", "..", "..", "src", "Octopus.jl"))
using .Octopus
import CUDA
const VARIANT = lowercase(get(ENV, "OCT_VARIANT", "orig"))
body = Dict(
  "orig" => quote
        hstep = elem.L / elem.nst
        d = hstep / 2
        @inbounds for _ in 1:elem.nst
            x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, hstep, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
        end
    end,
  "nokick" => quote
        hstep = elem.L / elem.nst
        d = hstep / 2
        @inbounds for _ in 1:elem.nst
            x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
        end
    end,
  "directdrift" => quote
        hstep = elem.L / elem.nst
        d = hstep / 2
        @inbounds for _ in 1:elem.nst
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, hstep, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d, x, px, y, py, z, pz)
        end
    end,
  "noloop" => quote
        hstep = elem.L
        d = hstep / 2
        x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _step_kick(elem, hstep, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
    end,
  "loopdirect_nokick" => quote
        hstep = elem.L / elem.nst
        d = hstep / 2
        @inbounds for _ in 1:elem.nst
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d, x, px, y, py, z, pz)
        end
    end,
)[VARIANT]
Octopus.eval(quote
    @inline function track_particle(::Symplectic6DMap, elem::LatticeMagnet{M,T,N,2,F,MC,NC,C},
                                    x, px, y, py, z, pz) where {M,T,N,F,MC,NC,C}
        x, px, y, py, z, pz = _entrance(elem, x, px, y, py, z, pz)
        if N == 0 && NC == 0
            elem.L != 0 && ((x, px, y, py, z, pz) = _body_step(elem, elem.L, x, px, y, py, z, pz))
        elseif elem.L != 0
            $body
        end
        return _exit(elem, x, px, y, py, z, pz)
    end
end)
body4 = Dict(
  "orig" => quote
        hstep = elem.L / elem.nst
        d1 = T(_FR_D1) * hstep; d2 = T(_FR_D2) * hstep
        k1 = T(_FR_K1) * hstep; k2 = T(_FR_K2) * hstep
        @inbounds for _ in 1:elem.nst
            x, px, y, py, z, pz = _body_step(elem, d1, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, k1, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _body_step(elem, d2, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, k2, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _body_step(elem, d2, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, k1, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _body_step(elem, d1, x, px, y, py, z, pz)
        end
    end,
  "directdrift" => quote
        hstep = elem.L / elem.nst
        d1 = T(_FR_D1) * hstep; d2 = T(_FR_D2) * hstep
        k1 = T(_FR_K1) * hstep; k2 = T(_FR_K2) * hstep
        @inbounds for _ in 1:elem.nst
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d1, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, k1, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d2, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, k2, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d2, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _step_kick(elem, k1, x, px, y, py, z, pz)
            x, px, y, py, z, pz = _lattice_drift(Val(C), elem.h, d1, x, px, y, py, z, pz)
        end
    end,
)
if haskey(body4, VARIANT)
    b4 = body4[VARIANT]
    Octopus.eval(quote
        @inline function track_particle(::Symplectic6DMap, elem::LatticeMagnet{M,T,N,4,F,MC,NC,C},
                                        x, px, y, py, z, pz) where {M,T,N,F,MC,NC,C}
            x, px, y, py, z, pz = _entrance(elem, x, px, y, py, z, pz)
            if N == 0 && NC == 0
                elem.L != 0 && ((x, px, y, py, z, pz) = _body_step(elem, elem.L, x, px, y, py, z, pz))
            elseif elem.L != 0
                $b4
            end
            return _exit(elem, x, px, y, py, z, pz)
        end
    end)
end
println("strang variant: ", VARIANT)
const TARGET = lowercase(get(ENV, "OCT_PROBE_TARGET", "eltype"))
if TARGET == "lattice"
    include(joinpath(@__DIR__, "..", "..", "..", "validation", "bbscl_comparison", "octopus_lattice_bbscl.jl"))
else
    include(joinpath(@__DIR__, "octopus_eltype.jl"))
end
