export TwissDispersionIdentityContract

# Stage 6 of the Twiss and dispersion analysis (design note "Verification
# plan" 472-478 and Staging item 6): the PHYSICS identity contract of
# `TwissDispersionAnalysis`, the sibling of the implementation contract
# `AnalysisOptionEffectivenessContract` (contracts/analysis_effectiveness.jl).
# It runs manufactured and lattice fixtures through `analyze`, records the
# per-identity maxima of the theory note's tagged identities (Sections 3, 6,
# 8 and 9) in three layers (the reported residual triples re-judged on their
# VALUES; the kernel residuals the analysis computes but does not surface;
# identities recomputed in the caller's coordinates, scaling invariance among
# them), and fails both when an identity drifts and when an expected
# diagnostic stays silent. Included after contracts/analysis_effectiveness.jl
# (it reuses `_manufactured_symplectic_map`, `analyze`, `one_turn_matrix`,
# `compile_runtime` and the element specs) and before src/registry/Registry.jl
# (the registry discovers it; the snapshot gains one Contracts line).
# Validation twin: validation/twiss_dispersion_identities.jl. Example:
# examples/twiss_dispersion_dba_ring.jl. Helper prefix `_identity_contract_`.

"""
    _IDENTITY_CONTRACT_SLUGS

The identity rows of the contract, one ASCII slug each, in three layers
(stage 6 dossier H4). Layer 1 (`r_`): the `(name, value, tolerance)` triples
of `result.diagnostics.residuals`, re-judged on their values with the
contract's own multiplier. Layer 2 (`k_`): kernel residual fields the
analysis computes but does not surface (`CanonicalSeparation`,
`ProjectedOptics6D`, `NormalModeFrame4D`, `MaisRipkenSet`,
`MatchedCovariance6D`, `OhmiFactorization`, `CoastingStructure`,
`DispersionRoutes`). Layer 3 (`c_`): identities the contract recomputes in
the CALLER's coordinates from `result.matrix` and `result.physical`. Every
slug is a key of `_default_identity_multipliers()`, and `validate` records
`max_<slug>` (the largest value / tolerance ratio), `maxval_<slug>` (the
largest raw value) and `argmax_<slug>` (the fixture that attained it). A
slug that runs on no fixture FAILS the contract: a row that never runs is
not a pass.
"""
const _IDENTITY_CONTRACT_SLUGS = (
    # Layer 1: the reported triples (twiss_dispersion_analysis.jl `_analysis_diagnostics`)
    :r_frame_reconstruction_i1, :r_frame_symplecticity_e7, :r_separation_off_diagonal_k5,
    :r_triple_consistency_k7, :r_u6_reconstruction, :r_u6_symplecticity, :r_covariance_closure,
    :r_k14_zz_identity, :r_primary_route_invariance_i1,
    # Layer 2: kernel fields (canonical_separation.jl, eigenmodes_4d.jl, coupled_parameterizations.jl, dispersion_routes.jl)
    :k_separation_inverse, :k_separation_symplecticity, :k_transverse_block_symplecticity,
    :k_longitudinal_block_symplecticity, :k_k7_difference, :k_k8_residual, :k_u6_row_sums,
    :k_u6_column_sums, :k_kappa_sz_minus_h, :k_m5_residual_6d, :k_k13_residual,
    :k_frame_normalization, :k_frame_row_sums, :k_frame_column_sums, :k_frame_u_difference,
    :k_mais_ripken_m5, :k_covariance_decomposition, :k_covariance_symmetry, :k_covariance_psd,
    :k_ohmi_symplecticity, :k_ohmi_separated_off_diagonal, :k_ohmi_chart_change_off_diagonal,
    :k_ohmi_chart_change_block_symplecticity, :k_ohmi_graph_difference,
    :k_coasting_symplectic_consistency, :k_coasting_solve_residual, :k_route_agreement, :k_trace_cubic,
    # Layer 3: recomputed in the caller's coordinates
    :c_caller_symplecticity, :c_physical_normalizer_symplecticity, :c_e8_reconstruction_caller,
    :c_projector_sum, :c_projector_idempotence, :c_covariance_symmetry_caller, :c_d14_graph_invariance,
    :c_d8_round_trip, :c_d3_symplecticity, :c_d3_determinant, :c_k4_block_diagonality,
    :c_x2_graph_readout, :c_matched_covariance_accessor, :c_covariance_closure_caller,
    :c_normal_mode_kappa, :c_normal_mode_tunes, :c_tune_consistency, :c_line_equals_matrix,
    :c_scaling_invariance, :c_d24_coasting_caller,
)

"""
    _default_identity_multipliers() -> Dict{Symbol,Float64}

The contract-owned multiplier `c` of every identity row (tolerance
`c * eps() * kappa_row`, kappa per row in the stage 6 dossier H4 and in the
row helpers below). MEASURED, not chosen: each `c` is the power of two at
least `8` and at least ten times the largest value / (eps kappa) ratio over
the contract's fixtures in BOTH CPU arms (native, and
`OPENBLAS_CORETYPE=Haswell julia -C haswell`; docs/experiences.md "A
tolerance measured on one CPU is a hand-copy of that CPU's rounding"). The
measured multiplier-1 ratios and the fixture that attained each are recorded
beside every entry and in the stage 6 history section. A ratio above about
100 at multiplier 1 means a kappa that is not the conditioning of the
quantity compared, and is fixed in the kappa, never in `c`. A slug missing
here fails the contract by name; a key that is not a row fails it too.
"""
function _default_identity_multipliers()
    # Measured 2026-09-13 on the integrated main tree at multiplier 1.0 in both CPU arms (the tables are in the
    # stage 6 section of docs/history/twiss_dispersion_analysis_history.md): per row the multiplier-1 ratio
    # native | haswell | the argmax fixture; c = max(8, 2^ceil(log2(10 max))). Every ratio is below 100 (H15):
    # no kappa was grown into a c. The largest, c_d14_graph_invariance (52 | 67, dense map 12), shares its (I1)
    # normalization with the analysis's own primary-route row. The nine rows marked "(re-measured)" got their
    # kappa corrected by the stage 6 review (cond(U) on the completeness / (E7) / scaling rows; no condition
    # number on the (D24) residual rows) and were re-measured in both arms before their c was frozen.
    return Dict{Symbol,Float64}(
        :r_frame_reconstruction_i1 => 64,  # 4.429e+00 | 1.949e+00 | F8 coasting map
        :r_frame_symplecticity_e7 => 64,  # 3.486e+00 | 2.296e+00 | F6b dense 4x4 map 4
        :r_separation_off_diagonal_k5 => 128,  # 1.016e+01 | 1.202e+01 | F6a dense 6x6 map 12
        :r_triple_consistency_k7 => 8,  # 5.449e-02 | 4.111e-02 | F6a dense 6x6 map 17
        :r_u6_reconstruction => 64,  # 2.473e+00 | 3.303e+00 | F6a dense 6x6 map 12
        :r_u6_symplecticity => 32,  # 1.803e+00 | 1.486e+00 | F6a dense 6x6 map 16
        :r_covariance_closure => 8,  # 4.514e-01 | 3.531e-01 | F6a dense 6x6 map 19
        :r_k14_zz_identity => 8,  # 2.606e-02 | 5.212e-02 | F6a dense 6x6 map 14
        :r_primary_route_invariance_i1 => 1024,  # 4.397e+01 | 5.174e+01 | F6a dense 6x6 map 12
        :k_separation_inverse => 8,  # 2.209e-01 | 2.218e-01 | F6a dense 6x6 map 11
        :k_separation_symplecticity => 8,  # 2.158e-01 | 1.714e-01 | F6a dense 6x6 map 20
        :k_transverse_block_symplecticity => 16,  # 9.753e-01 | 9.533e-01 | F6a dense 6x6 map 10
        :k_longitudinal_block_symplecticity => 16,  # 1.516e+00 | 1.516e+00 | F6a dense 6x6 map 20
        :k_k7_difference => 64,  # 4.062e+00 | 4.646e+00 | F6a dense 6x6 map 12
        :k_k8_residual => 8,  # 6.647e-01 | 6.647e-01 | F6a dense 6x6 map 11
        :k_u6_row_sums => 8,  # 2.335e-01 | 2.708e-01 | F6a dense 6x6 map 11
        :k_u6_column_sums => 8,  # 4.285e-01 | 3.114e-01 | F6a dense 6x6 map 16 (re-measured: kappa ||U6||^2 cond(U6))
        :k_kappa_sz_minus_h => 8,  # 6.771e-02 | 1.168e-01 | F6a dense 6x6 map 18
        :k_m5_residual_6d => 8,  # 1.173e-01 | 2.368e-02 | F6a dense 6x6 map 12
        :k_k13_residual => 32,  # 2.281e+00 | 2.199e+00 | F6a dense 6x6 map 19
        :k_frame_normalization => 16,  # 6.611e-01 | 8.108e-01 | F6a dense 6x6 map 11
        :k_frame_row_sums => 8,  # 3.305e-01 | 4.054e-01 | F6a dense 6x6 map 11
        :k_frame_column_sums => 16,  # 6.048e-01 | 1.120e+00 | F6b dense 4x4 map 4 (re-measured: kappa ||U4||^2 cond(U4))
        :k_frame_u_difference => 8,  # 6.074e-01 | 3.765e-01 | F6a dense 6x6 map 20 (re-measured: kappa ||U4||^2 cond(U4))
        :k_mais_ripken_m5 => 8,  # 2.636e-02 | 6.710e-02 | F8 coasting map
        :k_covariance_decomposition => 16,  # 7.303e-01 | 8.142e-01 | F6a dense 6x6 map 18
        :k_covariance_symmetry => 8,  # 0.000e+00 | 0.000e+00 | F4 DBA + RF
        :k_covariance_psd => 8,  # 0.000e+00 | 0.000e+00 | F4 DBA + RF
        :k_ohmi_symplecticity => 8,  # 4.497e-01 | 3.075e-01 | F6a dense 6x6 map 6
        :k_ohmi_separated_off_diagonal => 512,  # 2.874e+01 | 3.465e+01 | F6a dense 6x6 map 12
        :k_ohmi_chart_change_off_diagonal => 8,  # 1.765e-01 | 1.424e-01 | F6a dense 6x6 map 15
        :k_ohmi_chart_change_block_symplecticity => 8,  # 5.346e-01 | 7.573e-01 | F6a dense 6x6 map 5
        :k_ohmi_graph_difference => 8,  # 4.734e-01 | 2.647e-01 | F6a dense 6x6 map 2
        :k_coasting_symplectic_consistency => 8,  # 2.171e-02 | 2.032e-02 | F8 coasting map
        :k_coasting_solve_residual => 8,  # 9.020e-02 | 6.378e-02 | F1 DBA cell (tuple) (re-measured: no condition number on the residual)
        :k_route_agreement => 32,  # 2.394e+00 | 2.900e+00 | F6a dense 6x6 map 9
        :k_trace_cubic => 512,  # 4.643e+01 | 4.643e+01 | F6a dense 6x6 map 11
        :c_caller_symplecticity => 8,  # 4.037e-01 | 5.258e-01 | F6b dense 4x4 map 5
        :c_physical_normalizer_symplecticity => 64,  # 3.306e+00 | 2.161e+00 | F6b dense 4x4 map 4 (re-measured: kappa ||U||^2 cond(U))
        :c_e8_reconstruction_caller => 32,  # 1.948e+00 | 1.815e+00 | F6a dense 6x6 map 19
        :c_projector_sum => 64,  # 5.109e+00 | 3.497e+00 | F6b dense 4x4 map 4 (re-measured: kappa ||U||^2 cond(U))
        :c_projector_idempotence => 8,  # 6.310e-01 | 4.280e-01 | F6b dense 4x4 map 4 (re-measured: kappa ||U||^4 cond(U))
        :c_covariance_symmetry_caller => 8,  # 4.917e-01 | 4.068e-01 | F8 coasting map
        :c_d14_graph_invariance => 1024,  # 5.213e+01 | 6.709e+01 | F6a dense 6x6 map 12
        :c_d8_round_trip => 8,  # 5.000e-01 | 5.000e-01 | F5 DBA + RF + crab
        :c_d3_symplecticity => 8,  # 2.206e-01 | 1.676e-01 | F6a dense 6x6 map 20
        :c_d3_determinant => 8,  # 3.523e-03 | 3.701e-03 | F6a dense 6x6 map 13
        :c_k4_block_diagonality => 512,  # 2.644e+01 | 2.768e+01 | F6a dense 6x6 map 17
        :c_x2_graph_readout => 8,  # 1.120e-01 | 9.286e-02 | F6a dense 6x6 map 14
        :c_matched_covariance_accessor => 8,  # 0.000e+00 | 0.000e+00 | F4 DBA + RF
        :c_covariance_closure_caller => 64,  # 4.988e+00 | 4.839e+00 | F6a dense 6x6 map 19
        :c_normal_mode_kappa => 8,  # 9.670e-02 | 6.580e-02 | F8 coasting map
        :c_normal_mode_tunes => 8,  # 0.000e+00 | 0.000e+00 | F1 DBA cell (tuple)
        :c_tune_consistency => 32,  # 2.199e+00 | 2.080e+00 | F6a dense 6x6 map 19
        :c_line_equals_matrix => 8,  # 0.000e+00 | 0.000e+00 | F2 DBA cell (BeamLine)
        :c_scaling_invariance => 8,  # 5.973e-01 | 5.028e-01 | F6b dense 4x4 map 1 (re-measured: kappa amax^2 ||U||^2 cond(U))
        :c_d24_coasting_caller => 8,  # 1.176e-01 | 1.276e-01 | F1 DBA cell (tuple) (re-measured: no condition number on the residual)
    )
end

"""
    _default_identity_absolute_pins() -> Dict{Symbol,Float64}

The design note's ABSOLUTE benchmark pins, recorded and judged beside the
`c eps kappa` rows: `:ohmi` (design row 465, (O2)-(O5) "identities to
1e-12", applied to the three `k_ohmi_*` residual maxima), `:rolled_tune`
(theory 13.10, the exact equal tune 0.0360896443733161 of the rolled FODO,
the stage 3 pin 1e-13 of test/runtests.jl) and `:rolled_gram` (its Gram
minimum 0.0838222432933016, pin 1e-12). `metrics[:absolute_pins_checked]`
counts them.
"""
_default_identity_absolute_pins() = Dict{Symbol,Float64}(:ohmi => 1.0e-12, :rolled_tune => 1.0e-13, :rolled_gram => 1.0e-12)

"""
    TwissDispersionIdentityContract(; seed=UInt64(20260911), dense_maps=20, dense_maps_4d=5,
                                    emittances=(1.0, 1.0, 1.0),
                                    multipliers=_default_identity_multipliers(),
                                    absolute_pins=_default_identity_absolute_pins())

The physics identity contract of [`TwissDispersionAnalysis`](@ref) (design
note "Verification plan": "a physics contract runs the manufactured fixtures
through `analyze`, records per-identity maxima, and fails both when an
identity drifts and when an expected diagnostic stays silent"). Its
implementation twin, the option probe table, is
[`AnalysisOptionEffectivenessContract`](@ref).

What runs (every fixture through `analyze` with `strict = false`, so a
failed result is inspected rather than thrown): the DBA cell of
`validation/lattice_cells.jl` as an element tuple and as a `BeamLine`
("line equals matrix"), the detuned FODO, DBA + RF and DBA + RF + thin crab
(bunched 6D, certified by the two-run recipe: the heuristic's selected
canonical eigenvalue passed back as `longitudinal_mode`), `dense_maps`
manufactured stable 6x6 maps and `dense_maps_4d` manufactured 4x4 maps
(`exp(S H)`, `seed`), the manufactured coasting map, and the metadata
`example` of every element kind that declares the analysis (the set is
derived from `supported_analyses`, never listed).

What is judged: the identity rows of [`_IDENTITY_CONTRACT_SLUGS`](@ref),
each against `c * eps() * kappa` with the contract-owned, two-arm-measured
`multipliers[slug]` (the analysis's own tolerances are read only to
re-derive its verdict and compare); the `absolute_pins`; the
silent-diagnostic table ([`_identity_contract_diagnostics`](@ref): a fixture
whose expected status or reason does not fire fails the contract); the kind
sweep (a declaring kind whose example neither analyzes nor refuses for the
documented closed-orbit reason, or analyzes to `:failed`, or has no metadata
example at all, fails the contract by name). Status is `:passed` or
`:failed`, never `:skipped` (no external
resource). `metrics` carries `max_<slug>`, `maxval_<slug>`,
`argmax_<slug>` per row and the counts named in `validate`. The covariance
rows use unit `emittances`: the closure and (K14) identities are
scale-invariant, and a physical class would make `max(1, ||Sigma||)`
meaningless. Validation twin: `validation/twiss_dispersion_identities.jl`.
"""
Base.@kwdef struct TwissDispersionIdentityContract <: AbstractPhysicsContract
    seed::UInt64 = UInt64(20260911)
    dense_maps::Int = 20
    dense_maps_4d::Int = 5
    emittances::NTuple{3,Float64} = (1.0, 1.0, 1.0)
    multipliers::Dict{Symbol,Float64} = _default_identity_multipliers()
    absolute_pins::Dict{Symbol,Float64} = _default_identity_absolute_pins()
end

description(::Type{TwissDispersionIdentityContract}) =
    "Checks the Twiss and dispersion identities of the theory note through analyze on manufactured and lattice fixtures, and that every expected diagnostic fires."

# ---------------------------------------------------------------------------
# Fixtures (dossier H3, H8, H10). Recipes are those of validation/lattice_cells.jl
# 68-87 and test/runtests.jl 4532-4545, 5352-5366; NST = 4, ORDER = 4.

"""
    _identity_contract_dba_cell() -> Tuple

The DBA cell kf = 1.5, kd = -1.1 (`Lb = 1.0`, angle 0.20; qd `L = 0.25`, qf
`L = 0.35`, drifts 0.6) as a tuple of compiled runtime elements: a coasting
map with dispersion (tunes 1.5744 / 1.5101 rad per turn, eta_x ~ 0.75).
"""
function _identity_contract_dba_cell()
    nst = 4; order = 4
    bend = compile_runtime(SBendSpec(L=1.0, h=0.2, b0=0.2, nst=nst, integrator_order=order))
    qf = compile_runtime(QuadrupoleSpec(L=0.35, kn=(0.0, 1.5), nst=nst, integrator_order=order))
    qd = compile_runtime(QuadrupoleSpec(L=0.25, kn=(0.0, -1.1), nst=nst, integrator_order=order))
    d = compile_runtime(DriftSpec(L=0.6))
    return (qd, d, bend, d, qf, d, bend, d, qd)
end

"""
    _identity_contract_dba_line() -> BeamLine

The same DBA cell as a `BeamLine("DBA", <specs>...)` of element SPECS (the
"line equals matrix" fixture, design row 455).
"""
function _identity_contract_dba_line()
    nst = 4; order = 4
    bend = SBendSpec(L=1.0, h=0.2, b0=0.2, nst=nst, integrator_order=order)
    qf = QuadrupoleSpec(L=0.35, kn=(0.0, 1.5), nst=nst, integrator_order=order)
    qd = QuadrupoleSpec(L=0.25, kn=(0.0, -1.1), nst=nst, integrator_order=order)
    d = DriftSpec(L=0.6)
    return BeamLine("DBA", qd, d, bend, d, qf, d, bend, d, qd)
end

"""
    _identity_contract_fodo(; detune=1e-3) -> Tuple

The FODO cell kq = 1.6 with the defocusing quadrupole detuned by
`(1 + detune)`: the resolved near-degenerate frame (tunes 0.6827 / 0.6849).
`detune = 0` gives the exact symmetric cell whose x and y tunes coincide
(the frame is `:cluster_unresolved`; diagnostic row D2).
"""
function _identity_contract_fodo(; detune::Real=1e-3)
    qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, 1.6), nst=4, integrator_order=4))
    qd = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, -1.6 * (1 + detune)), nst=4, integrator_order=4))
    dr = compile_runtime(DriftSpec(L=1.2))
    return (qf, dr, qd, dr)
end

"""
    _identity_contract_rf_pieces(; crab=0.0) -> Tuple

The thin RF cavity (400 MHz, strength 0.02, beta0/gamma0 from
`reference_beta_gamma(3.0e9, PMASS_EV)`) and, when `crab != 0`, the thin
crab cavity `ThinCrabCavitySpec{1}(400.0e6; strengthX=(-crab,))`, compiled;
appended to the DBA tuple they make the bunched 6D fixtures F4 and F5.
"""
function _identity_contract_rf_pieces(; crab::Real=0.0)
    b0, g0 = reference_beta_gamma(3.0e9, PMASS_EV)
    rf = compile_runtime(ThinRFCavitySpec(400.0e6; strength=0.02, beta0=b0, gamma0=g0))
    crab == 0 && return (rf,)
    return (rf, compile_runtime(ThinCrabCavitySpec{1}(400.0e6; strengthX=(-Float64(crab),))))
end

"""
    _identity_contract_rolled_fodo(theta) -> Matrix{Float64}

The rolled equal-tune FODO cell of theory 13.10 (2765-2776), 4x4: `L_q =
0.2`, `K_1 = +-1`, drifts of 1 m, `Ax = Dr QD Dr QF`, `Ay = Dr QF Dr QD`,
`M = Rt blockdiag(Ax, Ay) Rt'` with `Rt = kron([cos -sin; sin cos], I_2)`.
Exact tunes `Q1 = Q2 = 0.0360896443733161`; at `theta = pi/4` the Gram
minimum is `0.0838222432933016` (diagnostic row D3, `absolute_pins`).
Rebuilt here because the suite's helper is not reachable from `src/`.
"""
function _identity_contract_rolled_fodo(theta::Real)
    L = 0.2; k = 1.0; w = sqrt(abs(k)); a = w * L
    QF = [cos(a) sin(a)/w; -w*sin(a) cos(a)]
    QD = [cosh(a) sinh(a)/w; w*sinh(a) cosh(a)]
    Dr = [1.0 1.0; 0.0 1.0]
    Rt = kron([cos(theta) -sin(theta); sin(theta) cos(theta)], Matrix{Float64}(I, 2, 2))
    Ax = Dr * QD * Dr * QF
    Ay = Dr * QF * Dr * QD
    return Rt * _identity_contract_blockdiag(Ax, Ay) * transpose(Rt)
end

"""
    _identity_contract_rot(mu) -> Matrix
    _identity_contract_blockdiag(blocks...) -> Matrix
    _identity_contract_mcal(zeta, eta) -> Matrix

Small builders of the manufactured diagnostic fixtures: the 2x2 rotation
`R(mu) = [cos sin; -sin cos]` (eigenvalue `exp(-i mu)`), a block-diagonal
assembly, and the canonical transformation `M_cal = M_zeta M_eta` of theory
(D3) for a dispersion pair (test/runtests.jl 5305-5309, test-local there).
"""
_identity_contract_rot(mu::Real) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
function _identity_contract_blockdiag(blocks::AbstractMatrix...)
    n = sum(size(b, 1) for b in blocks)
    B = zeros(n, n)
    at = 0
    for b in blocks
        m = size(b, 1)
        size(b, 2) == m || throw(ArgumentError("_identity_contract_blockdiag: blocks must be square"))
        B[at+1:at+m, at+1:at+m] = b
        at += m
    end
    return B
end
function _identity_contract_mcal(zeta::AbstractVector, eta::AbstractVector)
    S4 = _symplectic_form(4)
    Meta = Matrix(1.0I, 6, 6); Meta[1:4, 6] = eta; Meta[5, 1:4] = transpose(eta) * S4
    Mzeta = Matrix(1.0I, 6, 6); Mzeta[1:4, 5] = zeta; Mzeta[6, 1:4] = -transpose(zeta) * S4
    return Mzeta * Meta
end

"""
    _identity_contract_coasting(seed; shear=0.37) -> (M, eta, A4)

The manufactured coasting map of the stage 4b contract
(analysis_effectiveness.jl 164-170): `W = Z(0) E(eta)`, `M = W diag(A4, [1
s; 0 1]) W^-1` with `eta = 0.2 randn(4)` and a stable random 4D block drawn
from `MersenneTwister(seed)` AFTER one 6x6 and one 4x4 dense draw (so the
numbers equal the 4b contract's). Fixture F8 and the base of the weak-cavity
map of diagnostic row D12.
"""
function _identity_contract_coasting(seed::UInt64; shear::Real=0.37)
    rng = MersenneTwister(seed)
    _manufactured_symplectic_map(rng, 6; stable=true)
    _manufactured_symplectic_map(rng, 4; stable=true)
    eta = 0.2 * randn(rng, 4)
    A4 = Matrix{Float64}(_manufactured_symplectic_map(rng, 4; scale=0.3, stable=true).M)
    Meta = _identity_contract_mcal(zeros(4), eta)
    B = _identity_contract_blockdiag(A4, [1.0 Float64(shear); 0.0 1.0])
    return (M=Meta * B * _symplectic_inverse(Meta), eta=eta, A4=A4)
end

"""
    _identity_contract_fixtures(contract) -> Vector{NamedTuple}

The identity fixtures F1-F6b and F8 of the stage 6 dossier (H3) as
`(name::String, input, analysis::TwissDispersionAnalysis, kind::Symbol)`
rows, `kind` in `(:coasting, :bunched, :matrix4, :line)`. Deterministic in
`contract.seed`; every 6x6 identity fixture carries
`emittances = contract.emittances`, every 4x4 one `(1.0, 1.0)`; bunched 6D
fixtures are NOT certified here (the probe certifies them by the two-run
recipe, `_identity_contract_certified`, and row D9 uses the default run).
Dense 6x6 maps: `contract.dense_maps` draws of
`_manufactured_symplectic_map(rng, 6; stable=true).M` from
`rng = MersenneTwister(contract.seed)` (the first equals the 4b contract's
dense fixture); dense 4x4 maps: `contract.dense_maps_4d` draws AFTER them
from the same `rng` (a draw whose frame is not unique is counted in
`metrics[:dense4_skipped]` by the probe and replaced by the next; at most
`4 * dense_maps_4d` draws).
"""
function _identity_contract_fixtures(contract::TwissDispersionIdentityContract)
    em6 = contract.emittances; em4 = (1.0, 1.0)
    a6 = TwissDispersionAnalysis(strict=false, emittances=em6)
    a4 = TwissDispersionAnalysis(strict=false, emittances=em4)
    fixtures = NamedTuple[]
    dba = _identity_contract_dba_cell()
    # `role = :dba_tuple` tags the partner of the "line equals matrix" pair (by tag, not by display name)
    push!(fixtures, (name="F1 DBA cell (tuple)", input=dba, analysis=a6, kind=:coasting, role=:dba_tuple))
    push!(fixtures, (name="F2 DBA cell (BeamLine)", input=_identity_contract_dba_line(), analysis=a6, kind=:line))
    push!(fixtures, (name="F3 detuned FODO", input=_identity_contract_fodo(), analysis=a6, kind=:coasting))
    push!(fixtures, (name="F4 DBA + RF", input=(dba..., _identity_contract_rf_pieces()...), analysis=a6, kind=:bunched))
    push!(fixtures, (name="F5 DBA + RF + crab", input=(dba..., _identity_contract_rf_pieces(crab=0.05)...), analysis=a6, kind=:bunched))
    rng = MersenneTwister(contract.seed)
    for i in 1:contract.dense_maps
        M = Matrix{Float64}(_manufactured_symplectic_map(rng, 6; stable=true).M)
        push!(fixtures, (name="F6a dense 6x6 map $(i)", input=M, analysis=a6, kind=:bunched))
    end
    for i in 1:contract.dense_maps_4d
        M = Matrix{Float64}(_manufactured_symplectic_map(rng, 4; stable=true).M)
        push!(fixtures, (name="F6b dense 4x4 map $(i)", input=M, analysis=a4, kind=:matrix4))
    end
    push!(fixtures, (name="F8 coasting map", input=_identity_contract_coasting(contract.seed).M, analysis=a6, kind=:coasting))
    return fixtures
end

"""
    _identity_contract_diagnostics(contract) -> Vector{NamedTuple}

The silent-diagnostic table (dossier H8): rows `(name::String, input,
analysis::TwissDispersionAnalysis, expect::Function)` where `expect(result,
err)` returns `true` when the expected diagnostic FIRED (`err` is the
exception `analyze` threw, or `nothing`). A false predicate is a silent
diagnostic and fails the contract. Rows assert REASON SYMBOLS and statuses
(the vocabulary of the design note, "Availability"), never message texts.
Rows (17, every predicate probed before it was written; the probe outputs are
in the stage 6 history section): the unstable 4x4 map; the exact symmetric FODO
(`:cluster_unresolved`); the rolled equal-tune FODO (`:cluster_unresolved`
with the theory pins, run with `scaling = :none` because the Gram
eigenvalues are basis dependent and the pins are in the canonical basis);
the definite degenerate `diag(R(0.73), R(1.41), R(0.73))` (an ambiguity
set, interval `(-0.5, 0.5)` on `e_x`); the indefinite `diag(R(0.73),
R(1.41), R(-0.73))`; the `h = 0` map `M_cal(e_x, e_px) blockrot(0.73, 1.41,
-0.9) M_cal^-1` (design row 461: with the synchrotron mode named the
separation is `:singular_longitudinal_projection` and the mode is retained;
under the default heuristic the x betatron mode carries the whole z-area by
(K12) and the uncertified selection must stay `:degraded`); the coasting map
(`:coasting_structure`); the drift
(`:singular_coefficient`); the DBA + RF default run (the uncertified
heuristic) and, inside its predicate, the certified re-run; the perturbed
non-symplectic dense map under `nonsymplectic = :flag` (the must-reject
fixture: `:failed`) and under `strict = true` (throws
`OpticsAnalysisError`); the displaced closed orbit (`closed_orbit =
:require` throws, `:warn` degrades); the weak-cavity map whose
`:polynomial` route is `:not_invariant` with a coefficient condition above
1e3 (measured: the eigenplane primary route is `:not_invariant` too, so the
verdict is `:failed`); the identity map (`:singular_coefficient`, the
coasting branch); the negative-h map `M_cal(1.5 e_x, e_px) blockrot(0.73,
1.41, -0.9) M_cal^-1` (design row 465, second half: `h = -0.5` and the Ohmi
factor is `:form_inadmissible` while the separation stays unique). Not
reachable through `analyze` and therefore not rows: the isotropic graph
`diag(1, -1)` and the false polynomial graph of theory (N17) (both need a
formed graph, which `analyze` does not take). `M_cal` is symplectic with
determinant 1 for every `h` ((K1); the stage 6 review corrected an earlier
claim that it is singular at `h = 0`).
"""
function _identity_contract_diagnostics(contract::TwissDispersionIdentityContract)
    em = contract.emittances
    a6(; kw...) = TwissDispersionAnalysis(; strict=false, emittances=em, kw...)
    a4(; kw...) = TwissDispersionAnalysis(; strict=false, emittances=(1.0, 1.0), kw...)
    rot = _identity_contract_rot; bd = _identity_contract_blockdiag
    fr = _identity_contract_frame_reason; dr = _identity_contract_dispersion_reason; sr = _identity_contract_separation_reason
    isres(r, err) = err === nothing && r isa TwissDispersionResult
    rows = NamedTuple[]
    push!(rows, (name="D1 unstable 4x4 diag(2, 1/2, R(1.2))", input=bd([2.0 0.0; 0.0 0.5], rot(1.2)), analysis=a4(),
                 expect=(r, err) -> isres(r, err) && fr(r) === :unstable_spectrum && r.status !== :failed && isempty(r.physical.tunes)))
    push!(rows, (name="D2 exact symmetric FODO (equal tunes)", input=_identity_contract_fodo(detune=0.0), analysis=a6(),
                 expect=(r, err) -> isres(r, err) && fr(r) === :cluster_unresolved && r.status === :passed))
    # D3 runs with scaling = :none: the Gram eigenvalues are basis dependent, and the theory pins are in the
    # unscaled canonical basis (measured: :auto gives a Gram minimum 0.1946, :none the pinned 0.0838...).
    pins = contract.absolute_pins
    push!(rows, (name="D3 rolled equal-tune FODO theta = pi/4 (theory 13.10 pins)", input=_identity_contract_rolled_fodo(pi / 4), analysis=a4(scaling=:none),
                 pins=(:rolled_tune, :rolled_gram),
                 expect=(r, err) -> isres(r, err) && fr(r) === :cluster_unresolved && begin
                     i = findfirst(c -> length(c.members) == 4, r.clusters.clusters)
                     i !== nothing && all(abs.(r.clusters.clusters[i].tunes ./ (2pi) .- 0.0360896443733161) .<= pins[:rolled_tune]) &&
                         abs(minimum(r.clusters.clusters[i].gram_eigenvalues) - 0.0838222432933016) <= pins[:rolled_gram]
                 end))
    push!(rows, (name="D4 definite degenerate diag(R(0.73), R(1.41), R(0.73)) (ambiguity set)", input=bd(rot(0.73), rot(1.41), rot(0.73)), analysis=a6(),
                 expect=(r, err) -> isres(r, err) && is_ambiguous(r.dispersion.eta) && r.dispersion.eta.reason === :cluster_unresolved &&
                     r.status !== :failed && begin
                         lo, hi = dispersion_interval(r.dispersion.eta, [1.0, 0.0, 0.0, 0.0])
                         abs(lo + 0.5) <= 1e-12 && abs(hi - 0.5) <= 1e-12
                     end))
    push!(rows, (name="D5 indefinite degenerate diag(R(0.73), R(1.41), R(-0.73))", input=bd(rot(0.73), rot(1.41), rot(-0.73)), analysis=a6(),
                 expect=(r, err) -> isres(r, err) && :indefinite_cluster in (dr(r), sr(r), fr(r)) && !is_determined(r.physical.covariance) && r.status !== :failed))
    # D6 (design row 461): M_cal(e_x, e_px) is symplectic with det 1 for every h ((K1)), so the conjugation is a
    # similarity of blockrot(0.73, 1.41, -0.9) with h = 0. Probed through analyze (stage 6 fixer, both arms): naming
    # the synchrotron mode (tune 0.9) gives :singular_longitudinal_projection on the separation with the mode
    # retained; the default heuristic labels the x betatron mode longitudinal (its signed z-area is 1 - h = 1 by
    # (K12)) and must stay :degraded and uncertified.
    h0 = _identity_contract_mcal([1.0, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0])
    singular = h0 * bd(rot(0.73), rot(1.41), rot(-0.9)) * _symplectic_inverse(h0)
    push!(rows, (name="D6 h = 0 map M_cal(e_x, e_px) blockrot M_cal^-1 with the synchrotron mode named (singular projection, mode retained)",
                 input=singular, analysis=a6(longitudinal_mode=0.9),
                 expect=(r, err) -> isres(r, err) && sr(r) === :singular_longitudinal_projection && r.status === :degraded &&
                     r.clusters.degeneracy_status === :all_resolved && length(r.dispersion.tunes) == 3))
    push!(rows, (name="D6 h = 0 map under the default heuristic (the (K12) mislabel stays uncertified and :degraded)", input=singular, analysis=a6(),
                 expect=(r, err) -> isres(r, err) && r.status === :degraded && r.dispersion.longitudinal == 1 &&
                     is_determined(r.diagnostics.longitudinal_selection) && !determined_value(r.diagnostics.longitudinal_selection).certified))
    push!(rows, (name="D7 manufactured coasting map (shear 0.37)", input=_identity_contract_coasting(contract.seed).M, analysis=a6(),
                 expect=(r, err) -> isres(r, err) && r.coasting.holds && r.diagnostics.longitudinal_selection.reason === :coasting_structure &&
                     is_determined(r.physical.eta) && r.dispersion.longitudinal == 0))
    push!(rows, (name="D8 single drift (I - M_rr singular)", input=(compile_runtime(DriftSpec(L=0.5)),), analysis=a6(),
                 expect=(r, err) -> isres(r, err) && fr(r) === :singular_coefficient && r.status !== :failed && isempty(r.physical.tunes)))
    dba_rf = (_identity_contract_dba_cell()..., _identity_contract_rf_pieces()...)
    # D9: the default run is degraded by the uncertified heuristic; the certified re-run (through analyze, the
    # selected index passed back) is :passed with no degradation.
    push!(rows, (name="D9 DBA + RF default run (uncertified longitudinal heuristic) and certified re-run", input=dba_rf, analysis=a6(),
                 expect=(r, err) -> isres(r, err) && r.status === :degraded && r.dispersion.longitudinal != 0 &&
                     is_determined(r.diagnostics.longitudinal_selection) && !determined_value(r.diagnostics.longitudinal_selection).certified && begin
                         # (T) the analysis is built inline here, not through the local kwarg function `a6`:
                         # a local keyword function captured by a closure lowers to a Core.Box (the suite's sweep).
                         rc = analyze(TwissDispersionAnalysis(strict=false, emittances=em, longitudinal_mode=r.dispersion.longitudinal), dba_rf)
                         rc.status === :passed && isempty(rc.degradations) && determined_value(rc.diagnostics.longitudinal_selection).certified
                     end))
    M6 = Matrix{Float64}(_manufactured_symplectic_map(MersenneTwister(contract.seed), 6; stable=true).M)
    perturbed = M6 .+ 1e-6 .* randn(MersenneTwister(contract.seed + UInt64(7)), 6, 6)
    push!(rows, (name="D10 perturbed dense map under nonsymplectic = :flag (must-reject: :failed)", input=perturbed, analysis=a6(nonsymplectic=:flag, symplectic_rtol=1e-9),
                 expect=(r, err) -> isres(r, err) && r.status === :failed && !isempty(r.failures) && any(occursin("nonsymplectic = :flag", d) for d in r.degradations)))
    push!(rows, (name="D10 perturbed dense map under strict = true (throws OpticsAnalysisError)", input=perturbed,
                 analysis=TwissDispersionAnalysis(strict=true, emittances=em, nonsymplectic=:flag, symplectic_rtol=1e-9),
                 expect=(r, err) -> err isa OpticsAnalysisError))
    qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, 1.6), nst=4, integrator_order=4))
    qd = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, -1.6 * (1 + 1e-3)), nst=4, integrator_order=4))
    drf = compile_runtime(DriftSpec(L=1.2))
    sx = compile_runtime(SextupoleSpec(L=0.2, kn=(0.0, 0.0, 8.0), nst=4, integrator_order=4))
    displaced = one_turn_matrix((qf, drf, qd, drf, sx); point=(1e-3, 0.0, 0.0, 0.0, 0.0, 0.0))
    push!(rows, (name="D11 displaced FODO + sextupole under closed_orbit = :require (throws)", input=displaced, analysis=a6(),
                 expect=(r, err) -> err isa ArgumentError && occursin("closed_orbit", err.msg)))
    push!(rows, (name="D11 displaced FODO + sextupole under closed_orbit = :warn (degraded)", input=displaced, analysis=a6(closed_orbit=:warn),
                 expect=(r, err) -> isres(r, err) && r.status === :degraded && is_determined(r.closed_orbit) && determined_value(r.closed_orbit) > 0))
    co = _identity_contract_coasting(contract.seed)
    Mc = _identity_contract_mcal(zeros(4), co.eta)
    weak = Mc * bd(co.A4, [1.0 0.7; -1e-6 1 - 0.7e-6]) * _symplectic_inverse(Mc)
    # D12 as measured through analyze in BOTH CPU arms (the stage 6 history section records the probe): the :polynomial
    # route is :not_invariant with coefficient condition 2.3e6 (normalized residual 1.1e-10) in both arms; the
    # :eigenplane primary route sits at the edge of its own tolerance (normalized residual 2.0e-13 native ->
    # :not_invariant and a :failed verdict; 1.0e-13 haswell -> :none and a :degraded verdict), so the row asserts
    # the polynomial diagnostic and `status != :passed`, never the arm-dependent eigenplane verdict.
    push!(rows, (name="D12 weak-cavity coasting-like map (ill-conditioned Sylvester: the polynomial route reports its condition)", input=weak,
                 analysis=a6(dispersion_routes=(:eigenplane, :polynomial, :newton, :fixed_point)),
                 expect=(r, err) -> isres(r, err) && begin
                     poly = findfirst(x -> x.route === :polynomial, r.diagnostics.routes)
                     poly !== nothing && r.diagnostics.routes[poly].status === :not_invariant &&
                         r.diagnostics.routes[poly].coefficient_condition > 1e3 && r.status !== :passed
                 end))
    push!(rows, (name="D13 identity map (the marker's map)", input=Matrix(1.0I, 6, 6), analysis=a6(),
                 expect=(r, err) -> isres(r, err) && fr(r) === :singular_coefficient && r.status !== :failed && isempty(r.physical.tunes)))
    # D14 (design row 465, second half): h < 0 makes the Ohmi factor unavailable (:form_inadmissible) while the
    # separation and the covariance stay unique (probed through analyze: h = -0.5, status :degraded by the Newton
    # other-branch note only).
    hneg = _identity_contract_mcal([1.5, 0.0, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0])
    negative = hneg * bd(rot(0.73), rot(1.41), rot(-0.9)) * _symplectic_inverse(hneg)
    push!(rows, (name="D14 negative h map M_cal(1.5 e_x, e_px) blockrot M_cal^-1 (the Ohmi factor is :form_inadmissible)",
                 input=negative, analysis=a6(longitudinal_mode=0.9),
                 expect=(r, err) -> isres(r, err) && r.ohmi !== nothing && !is_determined(r.ohmi) && r.ohmi.reason === :form_inadmissible &&
                     r.separation !== nothing && is_determined(r.separation) && is_determined(r.physical.h) &&
                     determined_value(r.physical.h) < 0 && r.status !== :failed))
    return rows
end

# ---------------------------------------------------------------------------
# Running the analysis (never throws), certification, reason lookups.

"""
    _identity_contract_run(run, analysis, input) -> (result, error)

Runs `run(analysis, input)` under a fresh `ExecutionAudit` (so the contract's
runs leave no receipts in a caller's audit) and catches every exception;
returns `(result or nothing, exception or nothing)`. Locals written inside
the `do` block are `Ref`s: a local assigned in the closure and read outside
is a `Core.Box` (the suite's lowered-code sweep).
"""
function _identity_contract_run(run, analysis::TwissDispersionAnalysis, input)
    audit = ExecutionAudit()
    # Refs, not locals assigned inside the `do` block (the suite's Core.Box sweep).
    result = Ref{Any}(nothing)
    err = Ref{Any}(nothing)
    with_execution_audit(audit) do
        try
            result[] = run(analysis, input)
        catch e
            err[] = e
        end
    end
    return (result[], err[])
end

"""
    _identity_contract_certified(run, analysis, input) -> (result, error, index)

The two-run certification recipe of the stage 4b tests: run once with
`analysis`, read `result.dispersion.longitudinal`; when it is nonzero and the
analysis's `longitudinal_mode` is a Symbol, run again with
`longitudinal_mode = <that Int>` and return that result; `index` is the
selected canonical eigenvalue (0 when nothing was selected: a coasting map
or a 4x4 input, where the first result is returned).
"""
function _identity_contract_certified(run, analysis::TwissDispersionAnalysis, input)
    r, err = _identity_contract_run(run, analysis, input)
    (r === nothing || err !== nothing) && return (r, err, 0)
    r isa TwissDispersionResult || return (r, err, 0)
    r.dispersion === nothing && return (r, err, 0)
    index = r.dispersion.longitudinal
    (index == 0 || !(analysis.longitudinal_mode isa Symbol)) && return (r, err, 0)
    # every option of `analysis` is carried by derivation over its fields (a hand-typed keyword list would reset a
    # future option to its default on every certified re-run); only `longitudinal_mode` is replaced
    kept = (f => getfield(analysis, f) for f in fieldnames(TwissDispersionAnalysis) if f !== :longitudinal_mode)
    certified = TwissDispersionAnalysis(; kept..., longitudinal_mode=index)
    r2, err2 = _identity_contract_run(run, certified, input)
    return (r2, err2, index)
end

"""
    _identity_contract_frame_reason(result) -> Symbol
    _identity_contract_dispersion_reason(result) -> Symbol
    _identity_contract_separation_reason(result) -> Symbol

The reason symbol that blocked the transverse frame (`result.transverse`,
then its `.frame`), the dispersion (`result.dispersion.eta`) and the
separation (`result.separation`); `:none` when the quantity is unique or
does not exist for the input dimension.
"""
function _identity_contract_frame_reason(result::TwissDispersionResult)
    is_determined(result.transverse) || return result.transverse.reason
    frame = determined_value(result.transverse).frame
    return is_determined(frame) ? :none : frame.reason
end
function _identity_contract_dispersion_reason(result::TwissDispersionResult)
    result.dispersion === nothing && return :none
    return is_determined(result.dispersion.eta) ? :none : result.dispersion.eta.reason
end
function _identity_contract_separation_reason(result::TwissDispersionResult)
    (result.separation === nothing || is_determined(result.separation)) && return :none
    return result.separation.reason
end

# ---------------------------------------------------------------------------
# Recording rows and the three identity layers (dossier H4).

"""
    _identity_contract_record!(metrics, slug, value, kappa, name, contract) -> Bool

Records identity row `slug` measured on fixture `name`: the ratio `value /
(c * eps() * kappa)` with `c = contract.multipliers[slug]` updates
`metrics[Symbol("max_", slug)]`, and when it is the new maximum
`metrics[Symbol("maxval_", slug)] = value` and `metrics[Symbol("argmax_", slug)]
= name` (the label travels with the number). `kappa` is floored at 1.
Returns `false` when the ratio exceeds 1 (the failure text "identity <slug>
on <name>: value <v> exceeds c eps kappa = <tol>" is pushed to
`metrics[:failure_texts]`, the probe's failure vector, created with `get!`
when the caller's Dict lacks it), when `value` is not
finite, or when `slug` has no multiplier (the failure text names the slug:
"no multiplier"). `metrics[Symbol("count_", slug)]` counts the fixtures the
row ran on. A slug that is not one of
`_IDENTITY_CONTRACT_SLUGS` is a programming error and throws.
"""
function _identity_contract_record!(metrics::Dict{Symbol,Any}, slug::Symbol, value::Real, kappa::Real,
                                    name::AbstractString, contract::TwissDispersionIdentityContract)
    slug in _IDENTITY_CONTRACT_SLUGS || throw(ArgumentError("_identity_contract_record!: $(slug) is not an identity row"))
    maxkey = Symbol("max_", slug); valkey = Symbol("maxval_", slug); argkey = Symbol("argmax_", slug)
    texts = get!(metrics, :failure_texts, String[])   # the probe aliases its failure vector here; a bare Dict gets its own
    ok = true
    if !haskey(contract.multipliers, slug)
        push!(texts, "identity $(slug) on $(name): no multiplier for this row")
        metrics[maxkey] = Inf
        metrics[valkey] = Float64(value)
        metrics[argkey] = String(name)
        return false
    end
    c = contract.multipliers[slug]
    tol = c * eps() * max(1.0, Float64(kappa))
    v = Float64(value)
    ratio = isfinite(v) ? v / tol : Inf
    metrics[Symbol("count_", slug)] = get(metrics, Symbol("count_", slug), 0) + 1
    if ratio > get(metrics, maxkey, -Inf)
        metrics[maxkey] = ratio
        metrics[valkey] = v
        metrics[argkey] = String(name)
    end
    if !isfinite(v)
        push!(texts, "identity $(slug) on $(name): value $(v) is not finite")
        ok = false
    elseif ratio > 1
        push!(texts, "identity $(slug) on $(name): value $(v) exceeds c eps kappa = $(tol)")
        ok = false
    end
    return ok
end

"""
    _identity_contract_reported_rows!(result, name, metrics, contract, failures) -> Nothing

Layer 1: every triple of `result.diagnostics.residuals` re-judged on its
VALUE through `_identity_contract_record!` with the contract's kappa (dossier
H4: `rho_M1 / eps` for the rho-scaled rows, `cond(U)` factors read from the
scaled normalizers, `kappa_sep = max(1, ||Ms||) ||T|| ||T^-1||`, the route
kappa `max(1, ||Ms||) max(1, opnorm(D))^2`), and the verdict re-derivation
V1: the names whose value exceeds the REPORTED tolerance among
`_VERDICT_RESIDUALS` must be exactly the names in `result.failures`
(`metrics[:verdicts_consistent]` / `[:verdicts_inconsistent]`, the latter a
failure naming the fixture). Also updates `metrics[:normalizer_ratio_u6_reconstruction]`
and `[:normalizer_ratio_u6_symplecticity]` with the analysis-multiplier-1
ratios (carry item 4 of the stage 5 record).
"""
function _identity_contract_reported_rows!(result::TwissDispersionResult, name::AbstractString, metrics::Dict{Symbol,Any},
                                           contract::TwissDispersionIdentityContract, failures::Vector{String})
    rho = result.clusters.rho_M1
    Ms = result.matrix_scaled
    frame_ok = is_determined(result.transverse) && is_determined(determined_value(result.transverse).frame)
    U4 = frame_ok ? determined_value(determined_value(result.transverse).frame).normalizer : nothing
    po_ok = result.projected_optics !== nothing && is_determined(result.projected_optics)
    U6 = po_ok ? determined_value(result.projected_optics).normalizer : nothing
    sep_ok = result.separation !== nothing && is_determined(result.separation)
    kappa_sep = sep_ok ? max(1.0, norm(Ms)) * norm(determined_value(result.separation).transformation) *
                         norm(determined_value(result.separation).inverse) : 1.0
    graph_ok = result.dispersion !== nothing && is_determined(result.dispersion.graph)
    kappa_route = graph_ok ? max(1.0, norm(Ms)) * max(1.0, opnorm(determined_value(result.dispersion.graph)))^2 : 1.0
    sigma_norm = is_determined(result.covariance) ? max(1.0, norm(determined_value(result.covariance))) : 1.0
    condU = U6 !== nothing ? cond(U6) : (U4 !== nothing ? cond(U4) : 1.0)
    k14_scale = po_ok ? max(1.0, maximum(abs(determined_value(result.projected_optics).covariances[j][5, 5]) for j in 1:2)) : 1.0
    rho_eps = max(1.0, rho / eps())
    for (rname, value, tolerance) in result.diagnostics.residuals
        if rname == "frame reconstruction (I1)"
            _identity_contract_record!(metrics, :r_frame_reconstruction_i1, value, rho_eps, name, contract)
        elseif rname == "frame symplecticity (E7)"
            _identity_contract_record!(metrics, :r_frame_symplecticity_e7, value, rho_eps * (U4 === nothing ? 1.0 : cond(U4)), name, contract)
        elseif rname == "separation off-diagonal (K5)"
            _identity_contract_record!(metrics, :r_separation_off_diagonal_k5, value, kappa_sep, name, contract)
        elseif rname == "triple consistency (K7)"
            _identity_contract_record!(metrics, :r_triple_consistency_k7, value, kappa_sep, name, contract)
        elseif rname == "U_6 reconstruction"
            _identity_contract_record!(metrics, :r_u6_reconstruction, value, rho_eps, name, contract)
            metrics[:normalizer_ratio_u6_reconstruction] = max(metrics[:normalizer_ratio_u6_reconstruction], value / rho)
        elseif rname == "U_6 symplecticity"
            cU6 = U6 === nothing ? 1.0 : cond(U6)
            _identity_contract_record!(metrics, :r_u6_symplecticity, value, rho_eps * cU6, name, contract)
            metrics[:normalizer_ratio_u6_symplecticity] = max(metrics[:normalizer_ratio_u6_symplecticity], value / (rho * cU6))
        elseif rname == "covariance closure"
            _identity_contract_record!(metrics, :r_covariance_closure, value, rho_eps * condU * sigma_norm, name, contract)
        elseif rname == "(K14) zz identity"
            _identity_contract_record!(metrics, :r_k14_zz_identity, value, rho_eps * (U6 === nothing ? 1.0 : cond(U6)) * k14_scale, name, contract)
        elseif rname == "primary route invariance (I1)"
            _identity_contract_record!(metrics, :r_primary_route_invariance_i1, value, kappa_route, name, contract)
        else
            push!(failures, "identity layer 1 on $(name): unknown residual triple \"$(rname)\"")
        end
    end
    # V1: the verdict re-derived from the triples with the REPORTED tolerances.
    recomputed = String[]
    for (rname, value, tolerance) in result.diagnostics.residuals
        rname in _VERDICT_RESIDUALS || continue
        (isfinite(value) && value <= tolerance) || push!(recomputed, rname)
    end
    reported = String[n for n in _VERDICT_RESIDUALS if any(startswith(f, n * " residual") for f in result.failures)]
    status_consistent = (result.status === :failed) == !isempty(result.failures)
    if sort(recomputed) == sort(reported) && status_consistent
        metrics[:verdicts_consistent] += 1
    else
        metrics[:verdicts_inconsistent] += 1
        push!(failures, "verdict on $(name): recomputed failing residuals $(recomputed) vs reported $(reported); status $(result.status) with $(length(result.failures)) failures")
    end
    return nothing
end

"""
    _identity_contract_kernel_rows!(result, name, metrics, contract, failures) -> Nothing

Layer 2: the kernel residual fields of the unique `CanonicalSeparation`,
`ProjectedOptics6D`, `NormalModeFrame4D`, `MaisRipkenSet`,
`MatchedCovariance6D`, `OhmiFactorization`, `CoastingStructure` and
`DispersionRoutes` of `result` (scaled coordinates), each recorded under its
`k_` slug with the kappa of dossier H4 (norms of the scaled normalizers and
transformations; the Ohmi rows only when `result.ohmi` is unique, i.e.
`h > 0`; the coasting rows only when `result.coasting.holds`). The three
`k_ohmi_*` residual maxima are also judged against
`contract.absolute_pins[:ohmi]` (design row 465).
"""
function _identity_contract_kernel_rows!(result::TwissDispersionResult, name::AbstractString, metrics::Dict{Symbol,Any},
                                         contract::TwissDispersionIdentityContract, failures::Vector{String})
    Ms = result.matrix_scaled
    nMs = max(1.0, norm(Ms))
    rec(slug, value, kappa) = _identity_contract_record!(metrics, slug, value, kappa, name, contract)
    pin(slug, value) = begin
        push!(metrics[:_pins_seen], :ohmi)
        value <= contract.absolute_pins[:ohmi] || push!(failures, "absolute pin :ohmi on $(name): $(slug) = $(value) exceeds $(contract.absolute_pins[:ohmi])")
    end
    if result.separation !== nothing && is_determined(result.separation)
        s = determined_value(result.separation)
        nT = norm(s.transformation); nTi = norm(s.inverse)
        kappa_sep = nMs * nT * nTi
        rec(:k_separation_inverse, s.inverse_residual, nT * nTi)
        rec(:k_separation_symplecticity, s.symplecticity, nT^2)
        rec(:k_transverse_block_symplecticity, s.transverse_symplecticity, norm(s.transverse_map)^2)
        rec(:k_longitudinal_block_symplecticity, s.longitudinal_symplecticity, norm(s.longitudinal_map)^2)
        is_determined(s.k7_difference) && rec(:k_k7_difference, determined_value(s.k7_difference), kappa_sep * max(1.0, 1 / abs(s.h)))
        rec(:k_k8_residual, s.k8_residual, nMs^2)
    end
    if result.projected_optics !== nothing && is_determined(result.projected_optics)
        o = determined_value(result.projected_optics)
        nU6sq = norm(o.normalizer)^2
        rec(:k_u6_row_sums, maximum(abs(x - 1) for x in o.row_sums), nU6sq)
        # the column sums are the completeness relation of U_6 (theory (K12), an inverse of U_6): they carry the
        # frame's conditioning cond(U_6) that the row sums do not (stage 6 review; measured on dense map 16)
        rec(:k_u6_column_sums, maximum(abs(x - 1) for x in o.column_sums), nU6sq * cond(o.normalizer))
        rec(:k_kappa_sz_minus_h, abs(o.kappa_sz_minus_h), nU6sq)
        rec(:k_m5_residual_6d, o.m5_residual, nU6sq^2)
        rec(:k_k13_residual, o.k13_residual, nU6sq * nMs)
    end
    if is_determined(result.transverse)
        tr = determined_value(result.transverse)
        if is_determined(tr.frame)
            f = determined_value(tr.frame)
            nU4sq = norm(f.normalizer)^2
            rec(:k_frame_normalization, maximum(f.normalization_residuals), nU4sq)
            rec(:k_frame_row_sums, maximum(abs(x - 1) for x in f.signed_area_row_sums), nU4sq)
            # (M3) column sums and (M4) u difference are completeness relations (an inverse of U_4): cond(U_4)
            rec(:k_frame_column_sums, maximum(abs(x - 1) for x in f.signed_area_column_sums), nU4sq * cond(f.normalizer))
            rec(:k_frame_u_difference, f.u_difference, nU4sq * cond(f.normalizer))
            is_determined(tr.mais_ripken) && rec(:k_mais_ripken_m5, maximum(determined_value(tr.mais_ripken).m5_residuals), nU4sq^2)
        end
    end
    if result.covariance_6d !== nothing && is_determined(result.covariance_6d)
        c6 = determined_value(result.covariance_6d)
        nS = max(1.0, norm(c6.sigma))
        rec(:k_covariance_decomposition, c6.decomposition_residual, nS)
        rec(:k_covariance_symmetry, c6.symmetry_residual, nS)
        rec(:k_covariance_psd, max(0.0, -c6.min_eigenvalue), nS)
    end
    if result.ohmi !== nothing && is_determined(result.ohmi) && result.separation !== nothing && is_determined(result.separation)
        oh = determined_value(result.ohmi)
        h = determined_value(result.separation).h
        D = is_determined(result.dispersion.graph) ? determined_value(result.dispersion.graph) : zeros(4, 2)
        rec(:k_ohmi_symplecticity, oh.symplecticity, norm(oh.transformation)^2); pin(:k_ohmi_symplecticity, oh.symplecticity)
        rec(:k_ohmi_separated_off_diagonal, oh.separated_off_diagonal, nMs * cond(oh.transformation)); pin(:k_ohmi_separated_off_diagonal, oh.separated_off_diagonal)
        rec(:k_ohmi_chart_change_off_diagonal, oh.chart_change_off_diagonal, norm(oh.chart_change)^2); pin(:k_ohmi_chart_change_off_diagonal, oh.chart_change_off_diagonal)
        rec(:k_ohmi_chart_change_block_symplecticity, oh.chart_change_block_symplecticity, norm(oh.chart_change)^2)
        rec(:k_ohmi_graph_difference, oh.graph_difference, max(1.0, norm(D))^2 * max(1.0, 1 / abs(h)))
    end
    if result.coasting !== nothing && result.coasting.holds
        co = result.coasting
        rec(:k_coasting_symplectic_consistency, co.symplectic_consistency, nMs^2)
        # (D24): a solve RESIDUAL is bounded by eps ||A|| ||eta|| for a backward-stable solve; the coefficient
        # condition bounds the error of eta, not the residual, so it is not in the kappa (stage 6 review: with it
        # the row could not see a defect below 1e-11 on F8, cond(I - M_rr) = 2e5).
        if is_determined(co.solve_residual) && is_determined(co.eta)
            rec(:k_coasting_solve_residual, determined_value(co.solve_residual), nMs * max(1.0, norm(determined_value(co.eta))))
        end
    end
    if result.dispersion !== nothing
        dr = result.dispersion
        if is_determined(dr.graph) && !isempty(dr.agreement)
            # The routes agree to the conditioning of their solves: the largest reported coefficient condition
            # (measured multiplier-1 ratio 152 without it on the dense map 17; 2.7e-13 raw).
            cc = maximum((is_determined(rt.coefficient_condition) ? determined_value(rt.coefficient_condition) : 1.0) for rt in dr.routes; init=1.0)
            kappa_route = nMs * max(1.0, norm(determined_value(dr.graph)))^2 * max(1.0, cc)
            rec(:k_route_agreement, maximum(max(a.zeta, a.eta, a.h) for a in dr.agreement), kappa_route)
        end
        # (D17) needs three distinct mode traces: on a coasting map the unit eigenvalue is a double root of the
        # cubic and the residual is O(sqrt(eps)) by the root's conditioning (measured 1.1e-8 on F8), so the row
        # runs on the bunched 6D maps only.
        # The cubic's roots are conditioned by their separation (1 / |p'(tau_j)| ~ 1 / min gap); the coefficients
        # carry tr(M^3) ~ ||Ms||^3.
        if !dr.coasting.holds && length(dr.trace_cubic_roots) == 3
            taus = real.(dr.trace_cubic_roots)
            gap = minimum(abs(taus[j] - taus[k]) for j in 1:3 for k in j+1:3)
            rec(:k_trace_cubic, dr.trace_cubic_residual, nMs^3 * max(1.0, 1 / max(gap, eps())))
        end
    end
    return nothing
end

"""
    _identity_contract_recomputed_rows!(result, name, metrics, contract, failures) -> Nothing

Layer 3: identities recomputed by the contract in the CALLER's coordinates
from `result.matrix` and `result.physical` (dossier H4, the `c_` slugs
except `c_line_equals_matrix` and `c_scaling_invariance`, which need two
results): symplecticity of the caller's matrix and of the physical
normalizer; the (E8) reconstruction with `R(mu) = [cos sin; -sin cos]`
(eigenvalue `exp(-i mu)`); projector algebra and covariance symmetry; the
(D14) graph invariance in the (I1) normalization on the caller's blocks; the
(D8) round trip; the (D3) transformation's symplecticity, determinant and
(K4) block diagonality; the (X2) readout from the physical normalizer; the
`matched_covariance` accessor against `physical.covariance` and the closure
in caller coordinates; `normal_mode` against `physical` (the scaling
invariant `beta gamma - alpha^2` per plane, and the tunes); tune consistency
with the spectrum; (D24) on coasting fixtures.
"""
function _identity_contract_recomputed_rows!(result::TwissDispersionResult, name::AbstractString, metrics::Dict{Symbol,Any},
                                             contract::TwissDispersionIdentityContract, failures::Vector{String})
    M = result.matrix; d = size(M, 1); nM = max(1.0, norm(M))
    ph = result.physical
    rec(slug, value, kappa) = _identity_contract_record!(metrics, slug, value, kappa, name, contract)
    rec(:c_caller_symplecticity, norm(transpose(M) * _symplectic_form(d) * M - _symplectic_form(d)), nM^2)
    U = is_determined(ph.normalizer) ? determined_value(ph.normalizer) : nothing
    nU2 = U === nothing ? 1.0 : max(1.0, norm(U)^2)
    # (E7) and the projector algebra (completeness U diag U^-1) carry the frame's conditioning cond(U) (the analysis
    # judges (E7) with rho cond(U4) itself; stage 6 review: the rows without it were the outliers on dense map 16)
    cU = U === nothing ? 1.0 : cond(U)
    if U !== nothing
        dU = size(U, 1); SU = _symplectic_form(dU)
        rec(:c_physical_normalizer_symplecticity, norm(transpose(U) * SU * U - SU), nU2 * cU)
        MU = dU == d ? M : M[1:dU, 1:dU]
        if length(ph.tunes) == div(dU, 2)
            R = _identity_contract_blockdiag((_identity_contract_rot(mu) for mu in ph.tunes)...)
            rec(:c_e8_reconstruction_caller, norm(MU * U - U * R) / max(1.0, norm(MU * U), norm(U)), nU2)
        end
    end
    if is_determined(ph.projectors)
        P = determined_value(ph.projectors); n = size(P[1], 1)
        rec(:c_projector_sum, norm(sum(P) - I(n)), nU2 * cU)
        rec(:c_projector_idempotence, maximum(norm(P[j] * P[k] - (j == k ? P[j] : zero(P[j]))) for j in eachindex(P), k in eachindex(P)), nU2^2 * cU)
    end
    is_determined(ph.covariances) && rec(:c_covariance_symmetry_caller, maximum(norm(G - transpose(G)) for G in determined_value(ph.covariances)), nU2)
    if d == 6 && is_determined(ph.graph)
        D = determined_value(ph.graph); nD = max(1.0, norm(D))
        Mrr = M[1:4, 1:4]; Mrl = M[1:4, 5:6]; Mlr = M[5:6, 1:4]; Mll = M[5:6, 5:6]
        lhs = Mrr * D + Mrl; rhs = D * (Mlr * D + Mll)
        rec(:c_d14_graph_invariance, norm(lhs - rhs) / max(1.0, norm(Mrr * D), norm(Mrl), norm(rhs)), nD^2)
        if is_determined(ph.zeta) && is_determined(ph.eta) && is_determined(ph.h)
            zeta = determined_value(ph.zeta); eta = determined_value(ph.eta); h = determined_value(ph.h)
            S4 = _symplectic_form(4)
            hp = 1 / (1 + dot(D[:, 1], S4 * D[:, 2]))
            rec(:c_d8_round_trip, max(norm(D[:, 1] - zeta), norm(hp * D[:, 2] - eta), abs(hp - h)), nD^2 * max(1.0, 1 / abs(h)))
            Mcal = _identity_contract_mcal(zeta, eta); S6 = _symplectic_form(6); nMcal = max(1.0, norm(Mcal))
            rec(:c_d3_symplecticity, norm(transpose(Mcal) * S6 * Mcal - S6), nMcal^2)
            # (D3): M_cal is symplectic, so det M_cal = 1 exactly; the scalar h sits in its (6, 6) entry (the
            # dossier's |det - h| was a slip: measured |1 - h| = 0.507 on the dense map 17).
            rec(:c_d3_determinant, max(abs(det(Mcal) - 1), abs(Mcal[6, 6] - h)), nMcal^6)
            Mbar = _symplectic_inverse(Mcal) * M * Mcal
            rec(:c_k4_block_diagonality, max(norm(Mbar[1:4, 5:6]), norm(Mbar[5:6, 1:4])), nM * cond(Mcal))
        end
        if U !== nothing && size(U, 1) == 6
            Uls = U[5:6, 5:6]
            rec(:c_x2_graph_readout, norm(U[1:4, 5:6] * inv(Uls) - D), norm(U)^2 * cond(Uls))
        end
    end
    if is_determined(ph.covariance) && result.analysis.emittances !== nothing
        Sigma = determined_value(ph.covariance); nS = max(1.0, norm(Sigma))
        rec(:c_matched_covariance_accessor, norm(matched_covariance(result, result.analysis.emittances) - Sigma), nS)
        MS = size(Sigma, 1) == d ? M : M[1:size(Sigma, 1), 1:size(Sigma, 1)]
        rec(:c_covariance_closure_caller, norm(MS * Sigma * transpose(MS) - Sigma), nM^2 * nS)
    end
    if !isempty(ph.tunes) && is_determined(ph.beta) && is_determined(ph.alpha) && is_determined(ph.gamma)
        bga = determined_value(ph.beta) .* determined_value(ph.gamma) .- determined_value(ph.alpha) .^ 2
        kmax = 0.0; tmax = 0.0
        for j in 1:min(length(ph.tunes), size(bga, 1))
            nm = try normal_mode(result, j) catch e; e isa UndeterminedQuantityError ? nothing : rethrow() end
            nm === nothing && continue
            kmax = max(kmax, maximum(abs.(nm.beta .* nm.gamma .- nm.alpha .^ 2 .- bga[j, :])))
            tmax = max(tmax, abs(nm.tune - ph.tunes[j]))
        end
        rec(:c_normal_mode_kappa, kmax, nU2^2); rec(:c_normal_mode_tunes, tmax, 1.0)
    end
    if !isempty(ph.tunes)
        wrap(a, b) = abs(rem(a - b, 2pi, RoundNearest))
        ev = result.clusters.eigenvalues
        tc = maximum(minimum(wrap(t, mod(-angle(l), 2pi)) for l in ev) for t in ph.tunes)
        # dispersion.tunes are in the LABEL order of ModeLabels6D (a heuristic that can differ from the frame's
        # mode order: measured on the dense map 10, where modes 1 and 2 are swapped), so they are compared as a set.
        if d == 6 && result.dispersion !== nothing && length(result.dispersion.tunes) == length(ph.tunes)
            tc = max(tc, maximum(minimum(wrap(t, u) for u in result.dispersion.tunes) for t in ph.tunes))
        end
        if d == 6 && result.projected_optics !== nothing && is_determined(result.projected_optics) && length(ph.tunes) == 3
            tc = max(tc, maximum(wrap(ph.tunes[j], determined_value(result.projected_optics).tunes[j]) for j in 1:3))
        end
        rec(:c_tune_consistency, tc, nU2)
    end
    if d == 6 && result.coasting !== nothing && result.coasting.holds && is_determined(ph.eta)
        eta = determined_value(ph.eta); A = I(4) - M[1:4, 1:4]
        # (D24) residual: eps ||A|| ||eta|| with no condition number (see the kernel row)
        rec(:c_d24_coasting_caller, norm(A * eta - M[1:4, 6]), nM * max(1.0, norm(eta)))
    end
    return nothing
end

"""
    _identity_contract_pair_rows!(kind, results, name, metrics, contract, failures) -> Nothing

The two-result rows: `kind = :scaling` compares the `:auto` run with the
`scaling = :none` run and the explicit `(2.0, 0.5, 3.0)` (4x4: `(2.0, 0.5)`)
run of the same input (`c_scaling_invariance`: the largest relative
difference over tunes, `physical.beta/alpha/gamma`, `zeta`, `eta`, `h`,
`graph`, `projectors`, `covariances`, `covariance`; kappa
`max(a_i^2, a_i^-2)^2 max(1, ||U||^2)` over the largest factors among the
runs); `kind = :line` compares the `BeamLine` result with the tuple result
of the DBA (`c_line_equals_matrix`: the matrix, the tunes, the betas).
"""
function _identity_contract_pair_rows!(kind::Symbol, results, name::AbstractString, metrics::Dict{Symbol,Any},
                                       contract::TwissDispersionIdentityContract, failures::Vector{String})
    reldiff(a, b) = norm(a - b) / max(1.0, norm(a), norm(b))
    # A quantity unique in one run and not in the other is a mismatch (Inf), not a skipped comparison.
    detdiff(da, db) = (is_determined(da) && is_determined(db)) ? reldiff(determined_value(da), determined_value(db)) :
                      (is_determined(da) == is_determined(db) ? 0.0 : Inf)
    vecdiff(da, db) = (is_determined(da) && is_determined(db)) ?
                      (length(determined_value(da)) == length(determined_value(db)) ?
                       maximum(reldiff(x, y) for (x, y) in zip(determined_value(da), determined_value(db)); init=0.0) : Inf) :
                      (is_determined(da) == is_determined(db) ? 0.0 : Inf)
    tunediff(ra, rb) = length(ra.physical.tunes) == length(rb.physical.tunes) ?
                       maximum(abs.(ra.physical.tunes .- rb.physical.tunes); init=0.0) : Inf
    if kind === :scaling
        base = results[1]
        worst = 0.0
        for other in results[2:end]
            pa, pb = base.physical, other.physical
            worst = max(worst, tunediff(base, other),
                        detdiff(pa.beta, pb.beta), detdiff(pa.alpha, pb.alpha), detdiff(pa.gamma, pb.gamma),
                        detdiff(pa.zeta, pb.zeta), detdiff(pa.eta, pb.eta), detdiff(pa.h, pb.h), detdiff(pa.graph, pb.graph),
                        vecdiff(pa.projectors, pb.projectors), vecdiff(pa.covariances, pb.covariances),
                        detdiff(pa.covariance, pb.covariance))
        end
        amax = maximum(max(a^2, a^-2) for r in results for a in r.scaling.factors; init=1.0)
        # the compared optics are quadratic in the eigenvectors, whose sensitivity to the re-scaled decomposition is
        # the frame's conditioning: cond(U) (stage 6: without it the 200-map script's map 42, a 0.0011-rad mode with
        # cond(U6) = 60, reached multiplier-1 ratio 164 | 328, i.e. a wrong kappa by the H15 rule)
        Ub = is_determined(base.physical.normalizer) ? determined_value(base.physical.normalizer) : nothing
        nU2 = Ub === nothing ? 1.0 : max(1.0, norm(Ub)^2)
        cU = Ub === nothing ? 1.0 : cond(Ub)
        _identity_contract_record!(metrics, :c_scaling_invariance, worst, amax^2 * nU2 * cU, name, contract)
    elseif kind === :line
        rl, rt = results
        value = max(norm(rl.matrix - rt.matrix) / max(1.0, norm(rt.matrix)), tunediff(rl, rt), detdiff(rl.physical.beta, rt.physical.beta))
        _identity_contract_record!(metrics, :c_line_equals_matrix, value, 1.0, name, contract)
    else
        throw(ArgumentError("_identity_contract_pair_rows!: kind must be :scaling or :line, got :$(kind)"))
    end
    return nothing
end

# ---------------------------------------------------------------------------
# The kind sweep, the probe, validate.

"""
    _identity_contract_kind_sweep!(contract, run, metrics, failures) -> Nothing

Every element kind whose `supported_analyses` contain
`TwissDispersionAnalysis` (derived over `registered_element_specs()`, never
listed) with a metadata `example`: `run(TwissDispersionAnalysis(strict=false),
example)`; a result with status `:passed` or `:degraded` counts in
`metrics[:kinds_analyzed]` and its reported triples enter Layer 1 under the
kind's name; `:failed` counts in `[:kinds_failed_example]` and fails the
contract naming the kind; an `ArgumentError` whose message contains "not a
fixed point" is re-run with `closed_orbit = :warn` under a `NullLogger` and
must come back `:degraded` (`[:kinds_refused]`); anything else counts in
`[:kinds_declaring_without_result]` and fails the contract naming the kind
and the exception; a declaring kind whose `example` is `nothing` counts in
`[:kinds_without_example]` and fails the contract naming the kind (never a
silent skip). `[:kinds_declaring]` is the size of the derived set. The
suite's liar control registers a kind whose example `analyze` cannot take.
"""
function _identity_contract_kind_sweep!(contract::TwissDispersionIdentityContract, run, metrics::Dict{Symbol,Any},
                                        failures::Vector{String})
    kinds = Type[T for T in registered_element_specs() if TwissDispersionAnalysis in supported_analyses(T)]
    metrics[:kinds_declaring] = length(kinds)
    analysis = TwissDispersionAnalysis(strict=false)
    for T in kinds
        meta = _element_meta_or_nothing(T)
        example = meta === nothing ? nothing : meta.example
        if example === nothing
            # loud, not skipped: a declaring kind without an example is uncovered (the SymplecticityContract twin
            # fails on `kinds_declaring_without_case`); counted and failed by name
            metrics[:kinds_without_example] += 1
            push!(failures, "kind $(meta === nothing ? T : meta.kind): declares TwissDispersionAnalysis but has no metadata example")
            continue
        end
        kind = meta.kind
        label = "kind $(kind) example"
        r, err = _identity_contract_run(run, analysis, example)
        if err isa ArgumentError && occursin("not a fixed point", err.msg)
            warn = TwissDispersionAnalysis(strict=false, closed_orbit=:warn)
            r, err = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
                _identity_contract_run(run, warn, example)
            end
            if err === nothing && r isa TwissDispersionResult && r.status === :degraded
                metrics[:kinds_refused] += 1
                metrics[:fixtures] += 2
                _identity_contract_reported_rows!(r, label * " (closed_orbit = :warn)", metrics, contract, failures)
            else
                metrics[:kinds_declaring_without_result] += 1
                push!(failures, "kind $(kind): the example refused the closed orbit and did not come back :degraded under closed_orbit = :warn" *
                                (err === nothing ? " (status $(r === nothing ? "nothing" : r.status))" : ": " * sprint(showerror, err)))
            end
            continue
        end
        if err !== nothing || !(r isa TwissDispersionResult)
            metrics[:kinds_declaring_without_result] += 1
            push!(failures, "kind $(kind): analyze gave no result on its metadata example" *
                            (err === nothing ? " (got $(typeof(r)))" : ": " * sprint(showerror, err)))
            continue
        end
        metrics[:fixtures] += 1
        if r.status === :failed
            metrics[:kinds_failed_example] += 1
            push!(failures, "kind $(kind): the metadata example analyzes to :failed: $(join(r.failures, "; "))")
        else
            metrics[:kinds_analyzed] += 1
            _identity_contract_reported_rows!(r, label, metrics, contract, failures)
        end
    end
    return nothing
end

"""
    _identity_contract_probe_tail!(contract, run, metrics, failures) -> Nothing

The second half of [`_identity_contract_probe`](@ref): the silent-diagnostic
table (each row's `expect(result, err)` under a catch: a false predicate or a
predicate that throws is a silent diagnostic), the kind sweep, the
row-coverage guard (every slug ran on at least one fixture, `count_<slug>`),
and `metrics[:absolute_pins_checked]`.
"""
function _identity_contract_probe_tail!(contract::TwissDispersionIdentityContract, run, metrics::Dict{Symbol,Any},
                                        failures::Vector{String})
    rows = _identity_contract_diagnostics(contract)
    metrics[:diagnostics_expected] = length(rows)
    for row in rows
        r, err = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            _identity_contract_run(run, row.analysis, row.input)
        end
        metrics[:fixtures] += 1
        fired = try
            row.expect(r, err) === true
        catch e
            false
        end
        if fired
            # a row that carries `pins` (D3: the theory pins) marks them checked; by tag, not by display name
            union!(metrics[:_pins_seen], get(row, :pins, ()))
        else
            metrics[:diagnostics_silent] += 1
            push!(metrics[:diagnostics_silent_names], row.name)
            push!(failures, "expected diagnostic silent: $(row.name)" *
                            (err === nothing ? (r isa TwissDispersionResult ? " (status $(r.status))" : "") : " (analyze threw: " * first(sprint(showerror, err), 200) * ")"))
        end
    end
    _identity_contract_kind_sweep!(contract, run, metrics, failures)
    for slug in _IDENTITY_CONTRACT_SLUGS
        get(metrics, Symbol("count_", slug), 0) >= 1 || push!(failures, "identity row $(slug) ran on no fixture")
    end
    metrics[:absolute_pins_checked] = length(metrics[:_pins_seen])
    delete!(metrics, :_pins_seen)
    return nothing
end

"""
    _identity_contract_result(contract, metrics, failures) -> ContractResult

Folds the per-row maxima into `metrics[:worst_ratio]` / `[:worst_identity]`
and builds the `ContractResult` (dossier H7: the pass message with its counts,
or the first failure text; `residual = metrics[:worst_ratio]`).
"""
function _identity_contract_result(contract::TwissDispersionIdentityContract, metrics::Dict{Symbol,Any}, failures::Vector{String})
    worst = -Inf; worst_slug = :none
    for slug in _IDENTITY_CONTRACT_SLUGS
        ratio = get(metrics, Symbol("max_", slug), nothing)
        ratio === nothing && continue
        ratio > worst && (worst = ratio; worst_slug = slug)
    end
    metrics[:worst_ratio] = worst == -Inf ? Inf : worst
    metrics[:worst_identity] = worst_slug
    delete!(metrics, :failure_texts)
    passed = isempty(failures)
    message = passed ?
        "twiss identities certified: $(metrics[:identities]) identities on $(metrics[:fixtures]) fixture runs, worst ratio $(metrics[:worst_ratio]) ($(worst_slug)); $(metrics[:diagnostics_expected]) expected diagnostics fired; $(metrics[:kinds_analyzed]) kinds analyzed, $(metrics[:kinds_refused]) refused for the documented closed-orbit reason" :
        "TwissDispersionIdentityContract failed ($(length(failures)) findings): " * first(failures)
    return ContractResult(passed, message; residual=metrics[:worst_ratio], metrics=metrics)
end

"""
    _identity_contract_probe(contract, fixtures, run; metrics=Dict{Symbol,Any}()) -> ContractResult

The whole check with an injectable verb `run(analysis, input)` (the suite
injects runs that certify silently, perturb the input or throw, and proves
each red): initializes every count, runs every identity fixture (certifying
the bunched ones; the scaling and line pairs), the diagnostic table
(`metrics[:diagnostics_expected]`, `[:diagnostics_silent]`,
`[:diagnostics_silent_names]`), the kind sweep, checks that every slug ran
on at least one fixture and that every multiplier key is a slug, and
returns `ContractResult(passed, message; residual=metrics[:worst_ratio],
metrics)`; never throws for a failed row. The pass message: "twiss
identities certified: <identities> identities on <fixtures> fixture runs,
worst ratio <r> (<slug>); <n> expected diagnostics fired; <k> kinds
analyzed, <m> refused for the documented closed-orbit reason"; on failure
the first failure text.
"""
function _identity_contract_probe(contract::TwissDispersionIdentityContract, fixtures, run;
                                  metrics::Dict{Symbol,Any}=Dict{Symbol,Any}())
    failures = String[]
    metrics[:failure_texts] = failures
    for key in (:fixtures, :verdicts_consistent, :verdicts_inconsistent, :diagnostics_expected, :diagnostics_silent,
                :kinds_declaring, :kinds_analyzed, :kinds_refused, :kinds_failed_example, :kinds_declaring_without_result,
                :kinds_without_example, :dense6_unresolved, :dense4_skipped)
        metrics[key] = 0
    end
    metrics[:identities] = length(_IDENTITY_CONTRACT_SLUGS)
    metrics[:dense_maps] = contract.dense_maps; metrics[:dense_maps_4d] = contract.dense_maps_4d
    metrics[:diagnostics_silent_names] = String[]
    metrics[:normalizer_ratio_u6_reconstruction] = 0.0; metrics[:normalizer_ratio_u6_symplecticity] = 0.0
    metrics[:_pins_seen] = Set{Symbol}()
    for key in keys(contract.multipliers)
        key in _IDENTITY_CONTRACT_SLUGS || push!(failures, "multiplier key $(key) is not an identity row")
    end
    # The replacement rng for skipped 4x4 draws continues the fixture builder's stream (H3 F6b).
    rng = MersenneTwister(contract.seed)
    for _ in 1:contract.dense_maps; _manufactured_symplectic_map(rng, 6; stable=true); end
    for _ in 1:contract.dense_maps_4d; _manufactured_symplectic_map(rng, 4; stable=true); end
    draws_left = 3 * contract.dense_maps_4d
    frame_unique(r) = is_determined(r.transverse) && is_determined(determined_value(r.transverse).frame)
    tuple_result = Ref{Any}(nothing)
    queue = collect(fixtures)
    while !isempty(queue)
        fx = popfirst!(queue)
        if fx.kind === :bunched
            r, err, index = _identity_contract_certified(run, fx.analysis, fx.input)
            metrics[:fixtures] += index == 0 ? 1 : 2
        else
            r, err = _identity_contract_run(run, fx.analysis, fx.input); index = 0
            metrics[:fixtures] += 1
        end
        if err !== nothing || !(r isa TwissDispersionResult)
            push!(failures, "fixture $(fx.name): analyze gave no result" * (err === nothing ? "" : ": " * sprint(showerror, err)))
            continue
        end
        if fx.kind === :bunched && (index == 0 || !frame_unique(r))
            if startswith(fx.name, "F6a")
                metrics[:dense6_unresolved] += 1
            else
                push!(failures, "fixture $(fx.name): the bunched 6D map was not certified (selected $(index), frame $(_identity_contract_frame_reason(r)))")
            end
            continue
        end
        if fx.kind === :matrix4 && !frame_unique(r)
            metrics[:dense4_skipped] += 1
            if draws_left > 0
                draws_left -= 1
                M = Matrix{Float64}(_manufactured_symplectic_map(rng, 4; stable=true).M)
                push!(queue, (name=fx.name * " (replacement $(3 * contract.dense_maps_4d - draws_left))", input=M, analysis=fx.analysis, kind=:matrix4))
            else
                push!(failures, "fixture $(fx.name): no resolved 4x4 frame within 4 * dense_maps_4d draws")
            end
            continue
        end
        _identity_contract_reported_rows!(r, fx.name, metrics, contract, failures)
        _identity_contract_kernel_rows!(r, fx.name, metrics, contract, failures)
        _identity_contract_recomputed_rows!(r, fx.name, metrics, contract, failures)
        get(fx, :role, :none) === :dba_tuple && tuple_result[] === nothing && (tuple_result[] = r)
        if fx.kind === :line && tuple_result[] !== nothing
            _identity_contract_pair_rows!(:line, (r, tuple_result[]), fx.name, metrics, contract, failures)
        end
        a = fx.analysis
        lm = index == 0 ? a.longitudinal_mode : index
        alts = TwissDispersionResult[r]
        for sc in (:none, size(r.matrix, 1) == 4 ? (2.0, 0.5) : (2.0, 0.5, 3.0))
            alt = TwissDispersionAnalysis(scaling=sc, strict=false, emittances=a.emittances, longitudinal_mode=lm)
            ra, erra = _identity_contract_run(run, alt, fx.input)
            metrics[:fixtures] += 1
            (erra === nothing && ra isa TwissDispersionResult) ? push!(alts, ra) :
                push!(failures, "fixture $(fx.name) with scaling = $(sc): analyze gave no result" * (erra === nothing ? "" : ": " * sprint(showerror, erra)))
        end
        length(alts) == 3 && _identity_contract_pair_rows!(:scaling, alts, fx.name, metrics, contract, failures)
    end
    _identity_contract_probe_tail!(contract, run, metrics, failures)
    return _identity_contract_result(contract, metrics, failures)
end

"""
    validate(contract::TwissDispersionIdentityContract; kwargs...) -> ContractResult

See the type docstring. Rejects unknown keywords through
`_reject_unknown_validate_kwargs`, builds the fixtures and runs
[`_identity_contract_probe`](@ref) with `analyze`. Never throws for a failed
row, a silent diagnostic or an unanalyzable kind: each is a `:failed` result
whose message names it.
"""
function validate(contract::TwissDispersionIdentityContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    fixtures = _identity_contract_fixtures(contract)
    return _identity_contract_probe(contract, fixtures, analyze)
end
