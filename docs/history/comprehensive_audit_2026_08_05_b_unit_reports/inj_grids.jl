include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
const D = "/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/"
function runts(label, f)
    ok = try
        Test.@testset "$label" begin include(D * f) end
        true
    catch e
        false
    end
    println(">>> ", label, " => ", ok ? "PASSED (defect NOT caught)" : "FAILED (defect caught)")
end
runts("E0-baseline-equalextent", "ts_equalextent.jl")
runts("G0-baseline-greenalign",  "ts_greenalign.jl")
runts("L0-baseline-latticebox",  "ts_latticebox.jl")
runts("X0-baseline-gridextent",  "ts_gridextent.jl")

const ORIG_IG = quote
    function _pic_interaction_grids(solver::PICPoissonSolver, sxmin, sxmax, symin, symax,
                                    fxmin, fxmax, fymin, fymax)
        nx, ny = solver.grid
        T = promote_type(typeof(sxmin), typeof(fxmin), eltype(solver.min_transverse_extent))
        width, height = _pic_resolve_transverse_extent(
            solver, max(T(sxmax - sxmin), T(fxmax - fxmin)),
            max(T(symax - symin), T(fymax - fymin)), "PIC interaction grid")
        tx = width / (nx - 4); ty = height / (ny - 4)
        width += 3 * tx; height += 3 * ty
        q = T(solver.grid_quantize)
        if q > zero(T)
            width = _pic_quantize_extent(width, q); height = _pic_quantize_extent(height, q)
            hx = width / (nx - 1); hy = height / (ny - 1)
            sx0 = round((T(sxmin + sxmax)/2 - width/2)/hx)*hx
            sy0 = round((T(symin + symax)/2 - height/2)/hy)*hy
            fx0 = round((T(fxmin + fxmax)/2 - width/2)/hx)*hx
            fy0 = round((T(fymin + fymax)/2 - height/2)/hy)*hy
            sx0, fx0 = _pic_align_grid_origins(solver.green_type, sx0, fx0, hx)
            sy0, fy0 = _pic_align_grid_origins(solver.green_type, sy0, fy0, hy)
            return (x0=sx0, y0=sy0, width=width, height=height),
                   (x0=fx0, y0=fy0, width=width, height=height)
        end
        sx0 = T(sxmin) - T(1.5)*tx; sy0 = T(symin) - T(1.5)*ty
        fx0 = T(fxmin) - T(1.5)*tx; fy0 = T(fymin) - T(1.5)*ty
        sx0, fx0 = _pic_align_grid_origins(solver.green_type, sx0, fx0, tx)
        sy0, fy0 = _pic_align_grid_origins(solver.green_type, sy0, fy0, ty)
        return (x0=sx0, y0=sy0, width=width, height=height),
               (x0=fx0, y0=fy0, width=width, height=height)
    end
end

# E1: the field grid is sized from the FIELD beam's own span (the unstated
# invariant the testset exists to pin)
Octopus.eval(quote
    function _pic_interaction_grids(solver::PICPoissonSolver, sxmin, sxmax, symin, symax,
                                    fxmin, fxmax, fymin, fymax)
        nx, ny = solver.grid
        T = promote_type(typeof(sxmin), typeof(fxmin), eltype(solver.min_transverse_extent))
        sw, sh = _pic_resolve_transverse_extent(solver, T(sxmax - sxmin), T(symax - symin), "s")
        fw, fh = _pic_resolve_transverse_extent(solver, T(fxmax - fxmin), T(fymax - fymin), "f")
        stx = sw/(nx-4); sty = sh/(ny-4); ftx = fw/(nx-4); fty = fh/(ny-4)
        sw += 3*stx; sh += 3*sty; fw += 3*ftx; fh += 3*fty
        sx0 = T(sxmin) - T(1.5)*stx; sy0 = T(symin) - T(1.5)*sty
        fx0 = T(fxmin) - T(1.5)*ftx; fy0 = T(fymin) - T(1.5)*fty
        return (x0=sx0, y0=sy0, width=sw, height=sh),
               (x0=fx0, y0=fy0, width=fw, height=fh)
    end
end)
runts("E1-per-beam-sizing", "ts_equalextent.jl")
Octopus.eval(ORIG_IG)
runts("E0b-restored", "ts_equalextent.jl")

# G1: realignment is a no-op (the recorded pre-fix behaviour)
Octopus.eval(quote
    _pic_realign_expanded_grids(gt, sg, fg, nx, ny) = (sg, fg)
end)
runts("G1-realign-noop", "ts_greenalign.jl")

# L1: the lattice box multiplier ignores the aspect ratio (the recorded index-unit defect)
Octopus.eval(quote
    _pic_lattice_box_mult(rho) = (_PIC_LATTICE_GREEN_MULT, _PIC_LATTICE_GREEN_MULT)
end)
runts("L1-index-unit-box", "ts_latticebox.jl")
