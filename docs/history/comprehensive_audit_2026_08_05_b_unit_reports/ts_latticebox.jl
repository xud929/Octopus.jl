@testset "The lattice Green box is sized in physical units, not index units" begin
    # `_PIC_LATTICE_GREEN_MULT = 8` multiplied the padded extent on BOTH axes, which
    # is an index-unit criterion. The periodic box is `Mx*hx` by `My*hy`, so at
    # rho = hx/hy = 11 it was eleven times flatter than it was wide while the
    # separations it must cover are eleven times wider than tall in physical units.
    # Points far along x therefore saw their y-images. Measured end to end: at the
    # 11:1 production aspect ratio `:lattice` was 10.3x WORSE than the `:integrated`
    # default it exists to improve on (3.21e-2 vs 3.10e-3), and got worse with grid
    # refinement -- the signature of an error that is not discretization.

    # (a) the multiplier scales on the fine-spacing axis, symmetrically, and caps
    @test Octopus._pic_lattice_box_mult(1.0) == (8, 8)
    @test Octopus._pic_lattice_box_mult(5.0) == (8, 40)
    @test Octopus._pic_lattice_box_mult(0.2) == (40, 8)
    let (mx, my) = Octopus._pic_lattice_box_mult(25.0)
        @test mx == 8 && my == Octopus._PIC_LATTICE_GREEN_MULT_MAX   # the cap binds
    end
    # symmetric under rho -> 1/rho
    for rho in (2.0, 5.0, 11.0, 25.0)
        @test Octopus._pic_lattice_box_mult(rho) == reverse(Octopus._pic_lattice_box_mult(1 / rho))
    end

    # (b) the property the box controls: along the COARSE axis, where the physical
    # separation is large, the table must be -ln r + const. That is the part
    # box contamination destroys; the fine-axis deviation is the genuine
    # near-origin lattice correction and is expected to remain.
    nx = ny = 64
    for rho in (1.0, 5.0, 11.0, 25.0)
        tab = Octopus._pic_lattice_green_table(nx, ny, rho)
        at(m) = tab[m + 2nx + 1, 0 + 2ny + 1]
        C = -at(8) - log(8.0)
        worst = maximum(abs(at(m) + log(float(m)) + C) for m in (12, 16, 24, 32))
        # post-fix worst is 7.3e-4 (rho=1) to 5.1e-3 (rho=25, at the cap);
        # pre-fix it was 1.4e-1 at rho=11, so this bound is discriminating
        @test worst < 1.0e-2
    end

    # (c) rho = 1 is untouched, so every previously recorded isotropic result stands
    @test Octopus._pic_lattice_box_mult(1.0) == (8, 8)
    let tab = Octopus._pic_lattice_green_table(32, 32, 1.0)
        @test isapprox(abs(tab[1 + 2 * 32 + 1, 2 * 32 + 1]), pi / 2; rtol=1e-5)
    end
end
