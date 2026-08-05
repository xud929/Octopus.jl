# U13 probe 4 — weak-dependency extension load modes.
# Run with a MODE env var: "pkg_none", "pkg_sym", "pkg_fd", "pkg_fd_first",
# "pkg_both", "script".
mode = get(ENV, "MODE", "pkg_none")

if mode == "script"
    include(joinpath("/cfs/ad/dxu/Library/Julia/Octopus", "src", "Octopus.jl"))
    using .Octopus
else
    mode == "pkg_fd_first" && @eval using ForwardDiff
    @eval using Octopus
    if mode in ("pkg_sym", "pkg_both"); @eval using Symbolics; end
    if mode in ("pkg_fd", "pkg_both");  @eval using ForwardDiff; end
end

O = mode == "script" ? Main.Octopus : Octopus
println("MODE = ", mode)
println("  knob_symbolics_available() = ", O.knob_symbolics_available())
println("  _HAS_SYMBOLICS_SCRIPT_MODE = ", O._HAS_SYMBOLICS_SCRIPT_MODE)
println("  _HAS_FORWARDDIFF_SCRIPT_MODE = ", O._HAS_FORWARDDIFF_SCRIPT_MODE)

# --- knob layer works regardless -------------------------------------------
O.reset_knobs!()
O._knob_define!(:kx, nothing, 0.3, nothing)
O._knob_define!(:ky, nothing, 1.7, nothing)
e = O._knob_expression_build(:(tan(kx) / sqrt(ky * 2.0)))
d = O.knob_derivative(e, :kx)
h = 1e-6
fd = (O.knob_value(O._knob_expression_build(:(tan(0.3 + $h) / sqrt(ky * 2.0)))) -
      O.knob_value(O._knob_expression_build(:(tan(0.3 - $h) / sqrt(ky * 2.0))))) / (2h)
println("  knob_derivative works: ", O.knob_value(d), " vs central diff ", fd,
        "  rel = ", abs(O.knob_value(d) - fd) / abs(fd))

# --- Symbolics adapter ------------------------------------------------------
if O.knob_symbolics_available()
    s = O.knob_symbolic(e)
    back = O.knob_from_symbolic(s)
    println("  knob_symbolic  = ", s)
    println("  round trip     = ", back)
    println("  value equal    = ", isapprox(O.knob_value(back), O.knob_value(e); rtol=1e-14))
else
    try
        O.knob_symbolic(e)
        println("  ERROR: knob_symbolic worked with no adapter!")
    catch err
        println("  knob_symbolic refused: ", first(sprint(showerror, err), 80), "...")
    end
end

# --- ForwardDiff rules ------------------------------------------------------
fd_loaded = isdefined(Main, :ForwardDiff) ||
            (mode == "script" && O._HAS_FORWARDDIFF_SCRIPT_MODE)
println("  ForwardDiff loaded: ", fd_loaded)
sig1, sig2, y0 = 2.0e-3, 1.0e-3, 3.0e-4
f(x) = O._elliptic_gaussian_kick_principal(sig1, sig2, x, y0)[1]
h2 = 1e-9
cd = (f(1.1e-3 + h2) - f(1.1e-3 - h2)) / (2h2)
if fd_loaded
    FD = mode == "script" ? O.ForwardDiff : Main.ForwardDiff
    ad = FD.derivative(f, 1.1e-3)
    println("  d(Kx)/dx  AD = ", ad, "  central = ", cd,
            "  rel = ", abs(ad - cd) / abs(cd))
    # the round (eta==0) path and the near-round path too
    g(x) = O._elliptic_gaussian_kick_principal(1.0e-3, 0.999999e-3, x, y0)[1]
    adn = FD.derivative(g, 1.1e-3)
    cdn = (g(1.1e-3 + h2) - g(1.1e-3 - h2)) / (2h2)
    println("  near-round  AD = ", adn, "  central = ", cdn,
            "  rel = ", abs(adn - cdn) / abs(cdn))
else
    println("  (skipped AD check; central difference = ", cd, ")")
end
