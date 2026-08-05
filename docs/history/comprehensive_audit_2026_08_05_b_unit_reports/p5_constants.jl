## Independent CODATA-2022 / exact-math verification of src/constants/Constants.jl.
## Every stored Float64 is compared, in 256-bit BigFloat, against the value it
## claims to be; the deviation is reported in ulps of the stored Float64.

using Octopus
using Printf

setprecision(BigFloat, 256)

ulps(stored::Float64, exact::BigFloat) = Float64(abs(BigFloat(stored) - exact) / BigFloat(eps(stored)))

# --- CODATA 2022 recommended values, entered independently from the source ----
const CODATA = Dict{Symbol,BigFloat}(
    :c        => BigFloat("299792458"),                  # exact, SI definition
    :r_e      => BigFloat("2.8179403205e-15"),           # classical electron radius, m
    :mec2_MeV => BigFloat("0.51099895069"),              # electron mass energy equiv, MeV
    :mpc2_MeV => BigFloat("938.27208943"),               # proton mass energy equiv, MeV
    :alpha    => BigFloat("7.2973525643e-3"),            # fine-structure constant
    :lambdabar_C => BigFloat("3.8615926744e-13"),        # reduced Compton wavelength, m
    :a0       => BigFloat("5.29177210544e-11"),          # Bohr radius, m
    :mp_over_me => BigFloat("1836.152673426"),           # proton-electron mass ratio
)

rows = Tuple{String,Float64,BigFloat,String}[]
push!(rows, ("CLIGHT",   Octopus.CLIGHT,   CODATA[:c],                          "m/s (exact by SI definition)"))
push!(rows, ("RE",       Octopus.RE,       CODATA[:r_e],                        "m (CODATA-2022 r_e)"))
push!(rows, ("EMASS_EV", Octopus.EMASS_EV, CODATA[:mec2_MeV] * BigFloat(10)^6,  "eV (CODATA-2022 m_e c^2)"))
push!(rows, ("ME0",      Octopus.ME0,      CODATA[:mec2_MeV] * BigFloat(10)^6,  "eV (alias of EMASS_EV)"))
push!(rows, ("PMASS_EV", Octopus.PMASS_EV, CODATA[:mpc2_MeV] * BigFloat(10)^6,  "eV (CODATA-2022 m_p c^2)"))
push!(rows, ("TWOPI",    Octopus.TWOPI,    2 * BigFloat(pi),                    "dimensionless 2*pi"))
push!(rows, ("SQRT2PI",  Octopus.SQRT2PI,  sqrt(2 * BigFloat(pi)),              "dimensionless sqrt(2*pi)"))
push!(rows, ("SQRTPI",   Octopus.SQRTPI,   sqrt(BigFloat(pi)),                  "dimensionless sqrt(pi)"))
push!(rows, ("SQRT2",    Octopus.SQRT2,    sqrt(BigFloat(2)),                   "dimensionless sqrt(2)"))

@printf("%-9s %-26s %-26s %10s %14s  %s\n", "NAME", "STORED (Float64)", "REFERENCE (256-bit)",
        "ULPS", "REL.ERR", "UNIT CLAIM")
maxulp = 0.0
for (nm, stored, exact, unit) in rows
    u = ulps(stored, exact)
    global maxulp = max(maxulp, u)
    rel = Float64(abs(BigFloat(stored) - exact) / abs(exact))
    @printf("%-9s %-26.17g %-26s %10.4f %14.3e  %s\n", nm, stored,
            string(Float64(exact)), u, rel, unit)
end
@printf("\nmax deviation over all 9 constants: %.4f ulp\n", maxulp)

println("\n== is each stored Float64 the correctly rounded nearest double? ==")
for (nm, stored, exact, _) in rows
    nearest = Float64(exact)
    println("  ", rpad(nm, 9), stored === nearest ? "YES (bit-identical to round(exact))" :
            "NO  stored=$(stored) nearest=$(nearest)")
end

println("\n== independent cross-checks of RE and the mass ratio ==")
re_from_alpha  = CODATA[:alpha] * CODATA[:lambdabar_C]
re_from_bohr   = CODATA[:alpha]^2 * CODATA[:a0]
@printf("  r_e = alpha * lambdabar_C   = %.15e   (stored %.15e, rel %.2e)\n",
        Float64(re_from_alpha), Octopus.RE,
        Float64(abs(re_from_alpha - BigFloat(Octopus.RE)) / re_from_alpha))
@printf("  r_e = alpha^2 * a0          = %.15e   (stored %.15e, rel %.2e)\n",
        Float64(re_from_bohr), Octopus.RE,
        Float64(abs(re_from_bohr - BigFloat(Octopus.RE)) / re_from_bohr))
ratio = BigFloat(Octopus.PMASS_EV) / BigFloat(Octopus.EMASS_EV)
@printf("  PMASS_EV/EMASS_EV           = %.9f   (CODATA m_p/m_e %.9f, rel %.2e)\n",
        Float64(ratio), Float64(CODATA[:mp_over_me]),
        Float64(abs(ratio - CODATA[:mp_over_me]) / CODATA[:mp_over_me]))

println("\n== literal-digit audit (does the source literal carry >17 significant digits?) ==")
for (nm, lit) in (("TWOPI", "6.283185307179586476925286766559005768394338"),
                  ("SQRT2PI", "2.506628274631000502415765284811045253006964"),
                  ("SQRTPI", "1.772453850905516027298167483341145182797554"),
                  ("SQRT2", "1.414213562373095048801688724209698078569662"))
    println("  ", rpad(nm, 8), "digits=", count(isdigit, lit), "  parses to ",
            repr(parse(Float64, lit)))
end
