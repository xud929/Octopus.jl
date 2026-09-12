export AnalysisOptionEffectivenessContract

# Stage 4b of the Twiss and dispersion analysis (design note "Execution API
# and option certification"; guides/configuration.md: every public option
# lands with a runtime consumer, schema metadata, invalid and inactive
# behaviour, and an effectiveness test at the consumer boundary). This file
# is the table-driven effectiveness probe of `TwissDispersionAnalysis`'s
# options, the sibling of `SolverOptionEffectivenessContract`. It is included
# after src/tasks/StrongStrong.jl (it calls `validate_configuration_metadata`)
# and before src/registry/Registry.jl (the registry discovers it; it needs
# `description`; the snapshot gains one Contracts line).

"""
    _default_analysis_option_alternatives() -> Dict{Symbol,Any}

One VALID NON-DEFAULT value per option of `analysis_option_schema(TwissDispersionAnalysis)`
on the contract's probe inputs (the dense 6D map, its `LinearizedMap`, the 4x4
map, the coasting map). An option missing here and not declared in
[`_default_analysis_inactive_options`](@ref) FAILS the contract.
"""
function _default_analysis_option_alternatives()
    return Dict{Symbol,Any}(
        :scaling => :none,
        :symplectic_rtol => 1e-6,
        :nonsymplectic => :flag,
        :closed_orbit => :warn,
        :closed_orbit_atol => 1e-9,
        :map_uncertainty => 1e-9,
        :resolution_chord => Inf,
        :clusters => [[1, 6], [2, 5], [3, 4]],
        :longitudinal_mode => _ANALYSIS_CONTRACT_LONGITUDINAL_INDEX,
        :preferred_form => 2,
        :dispersion_routes => (:eigenplane, :polynomial),
        :newton_max_iterations => 3,
        :emittances => (1e-6, 2e-6, 3e-6),
        :strict => false,
    )
end

"""
    _ANALYSIS_CONTRACT_LONGITUDINAL_INDEX

The certified `longitudinal_mode` alternative of the contract: the canonical
eigenvalue index of the dense 6D fixture's longitudinal mode. The fixture is
seeded (`_analysis_contract_fixtures(UInt64(20260911))`), so the index is a
property of the data; the contract's `validate` asserts that the `:analysis_labels`
receipt of the certified run selects this index, so a drift of the fixture
shows as a failed probe rather than a silent mis-selection. Measured by
`_analysis_contract_longitudinal_index()` on the fixture at construction of
the tables (see the report of stage 4b Part B).
"""
const _ANALYSIS_CONTRACT_LONGITUDINAL_INDEX = 2

"""
    _default_analysis_inactive_options() -> Dict{Tuple{Symbol,Symbol},String}

`(input_form, option) => reason` for every option that is INACTIVE on one of
the probe inputs (design: inactivity is a predicate on the branch taken):
`closed_orbit`, `closed_orbit_atol` on `:matrix` inputs; `longitudinal_mode`,
`dispersion_routes`, `newton_max_iterations` on `:matrix4` and on `:coasting`;
`newton_max_iterations` whenever `:newton` is not executed; `preferred_form`
when the transverse optics are unavailable; `emittances` when `nothing`. The
contract asserts the probe run's configuration report says
`:inactive_dependency` for each declared entry; a declared entry that the
report calls `:resolved` is a STALE exemption and FAILS.
"""
function _default_analysis_inactive_options()
    bare = "a bare matrix carries no closed-orbit information (no fixed-point residual)"
    no_longitudinal_4 = "a 4x4 map has no longitudinal plane; the dispersion pipeline does not run"
    coasting = "the coasting structure holds: every dispersion route is :coasting_structure and the longitudinal mode is not selected"
    newton = "the default dispersion_routes on this input do not execute :newton (or the pipeline does not run)"
    return Dict{Tuple{Symbol,Symbol},String}(
        (:matrix, :closed_orbit) => bare,
        (:matrix, :closed_orbit_atol) => bare,
        (:matrix4, :closed_orbit) => bare,
        (:matrix4, :closed_orbit_atol) => bare,
        (:coasting, :closed_orbit) => bare,
        (:coasting, :closed_orbit_atol) => bare,
        (:matrix4, :longitudinal_mode) => no_longitudinal_4,
        (:matrix4, :dispersion_routes) => no_longitudinal_4,
        (:matrix4, :newton_max_iterations) => newton,
        (:coasting, :longitudinal_mode) => coasting,
        (:coasting, :dispersion_routes) => coasting,
        (:coasting, :newton_max_iterations) => newton,
        (:matrix, :emittances) => "emittances = nothing: no matched covariance is requested",
        (:linearized, :emittances) => "emittances = nothing: no matched covariance is requested",
        (:matrix4, :emittances) => "emittances = nothing: no matched covariance is requested",
        (:coasting, :emittances) => "emittances = nothing: no matched covariance is requested",
    )
end

"""
    AnalysisOptionEffectivenessContract(; seed=UInt64(20260911), alternatives=..., inactive=...)

Implementation contract: every public option of every concrete
`AbstractAnalysis` with an `analysis_option_schema` reaches its declared
runtime consumer, moves (or, for `:execution` options, leaves fixed) the
observable its category demands, and is reported with a status from
`CONFIGURATION_STATUSES` by the run that read it (design "Certification";
campaign record stage 4b). `validate` first runs
`validate_configuration_metadata()` (the analysis block and the
`AbstractAnalysis` tree guard), then for EVERY schema option on the probe
inputs: if `(form, option)` is declared in `inactive`, the probe run's
configuration report must say `:inactive_dependency` (else the exemption is
stale and the contract FAILS); otherwise `analyze` runs under
`with_execution_audit` with the default and with `alternatives[option]`, the
receipt of the option's consumer must carry the alternative under the
option's own name, an `:execution` option must leave `zeta`, `eta`, `h` and
the tunes fixed within `c eps kappa`, a `:physics` or `:numerical` option
must move what it controls (the presented form, the executed routes, the
covariance presence, the failed-versus-thrown outcome, the forced
resolution of the repeated-betatron input, the partition the clusters
report groups by, the binding Newton cap, ...), and the report status must
be `:resolved`. Options whose alternative fires on no form of the dense map
have BRANCH probes on dedicated inputs (`_analysis_contract_branch_probe`:
the rtol value binds, `:flag` versus `:error`, `:warn` versus `:require`,
the atol accepts a displaced point). Every verdict is a metric: `checked`,
`inactive_declared`, `inactive_applied`, `stale_exemptions`,
`observables_moved`, `observables_fixed`, `receipts_checked`; a probe that
reaches no verdict FAILS. The schemas swept
are DERIVED from `_concrete_octopus_subtypes(AbstractAnalysis)` (every
concrete analysis whose schema is non-empty), never listed by hand.
"""
Base.@kwdef struct AnalysisOptionEffectivenessContract <: AbstractImplementationContract
    seed::UInt64 = UInt64(20260911)
    alternatives::Dict{Symbol,Any} = _default_analysis_option_alternatives()
    inactive::Dict{Tuple{Symbol,Symbol},String} = _default_analysis_inactive_options()
end

description(::Type{AnalysisOptionEffectivenessContract}) =
    "Checks that every declared analysis option reaches its runtime consumer and is reported honestly."

"""
    _analysis_contract_fixtures(seed) -> NamedTuple

The probe inputs, keyed by input form: `matrix` (a dense stable 6x6
symplectic map with three resolved modes, `_manufactured_symplectic_map(rng,
6; stable=true)`), `linearized` (the same matrix through `one_turn_matrix`
on a linear 6D element spec, so the provenance is exact and the fixed-point
residual zero), `matrix4` (a dense stable 4x4 map), `coasting` (a 6x6 map
with the coasting structure: `M[5, 6]` shear, unit longitudinal block,
`M[6, :]` and `M[:, 5]` trivial), and three inputs that are not forms of
`_ANALYSIS_CONTRACT_FORMS`: `failing` (the dense map plus a `1e-6` random
perturbation, the `strict` and `nonsymplectic` probes' input), `repeated`
(a repeated-betatron 6x6 map `W diag(R(0.72), R(0.72), R(-1.3)) W^-1`, the
only input on which `resolution_chord = Inf` FORCES a resolution: the
`resolution_chord` probe runs here, see `_ANALYSIS_CONTRACT_PROBE_FORMS`),
and `displaced` (the FODO cell with a thin sextupole linearized at the
displaced point `x = 1e-3`, whose fixed-point residual is not zero: the
`closed_orbit` / `closed_orbit_atol` branch probes' input). Deterministic in
`seed`.
"""
function _analysis_contract_fixtures(seed::UInt64)
    rng = MersenneTwister(seed)
    M6 = Matrix{Float64}(_manufactured_symplectic_map(rng, 6; stable=true).M)
    spec = Linear6DSpec(matrix=M6)
    linearized = one_turn_matrix((compile_runtime(spec),))
    M4 = Matrix{Float64}(_manufactured_symplectic_map(rng, 4; stable=true).M)
    # coasting: W = Z(0) E(eta), M = W diag(A4, [1 s; 0 1]) W^-1 (stage 4a row 5)
    S4 = _symplectic_form(4)
    eta = 0.2 * randn(rng, 4)
    A4 = Matrix{Float64}(_manufactured_symplectic_map(rng, 4; scale=0.3, stable=true).M)
    Meta = Matrix(1.0I, 6, 6); Meta[1:4, 6] = eta; Meta[5, 1:4] = transpose(eta) * S4
    B = zeros(6, 6); B[1:4, 1:4] = A4; B[5, 5] = 1.0; B[6, 6] = 1.0; B[5, 6] = 0.37
    coasting = Meta * B * _symplectic_inverse(Meta)
    failing = _analysis_contract_failing_fixture(seed, M6)
    W = Matrix{Float64}(_manufactured_symplectic_map(MersenneTwister(seed + UInt64(1000)), 6; scale=0.1).M)
    rot(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
    R3 = zeros(6, 6); R3[1:2, 1:2] = rot(0.72); R3[3:4, 3:4] = rot(0.72); R3[5:6, 5:6] = rot(-1.3)
    repeated = W * R3 * _symplectic_inverse(W)
    qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, 1.6), nst=4, integrator_order=4))
    qd = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, -1.6 * (1 + 1e-3)), nst=4, integrator_order=4))
    dr = compile_runtime(DriftSpec(L=1.2))
    sx = compile_runtime(SextupoleSpec(L=0.2, kn=(0.0, 0.0, 8.0), nst=4, integrator_order=4))
    displaced = one_turn_matrix((qf, dr, qd, dr, sx); point=(1e-3, 0.0, 0.0, 0.0, 0.0, 0.0))
    return (matrix=M6, linearized=linearized, matrix4=M4, coasting=coasting, failing=failing, repeated=repeated, displaced=displaced)
end

"""
    _analysis_contract_receipt_carries(receipts, consumer, name, value) -> Bool

The repo's matcher convention (Contracts.jl `_solver_contract_receipt_carries`):
some receipt with `r.consumer === consumer` has `name` among the keys of
`r.values` with a value `isequal` to `value`.
"""
function _analysis_contract_receipt_carries(receipts, consumer::Symbol, name::Symbol, value)
    for r in receipts
        r.consumer === consumer || continue
        haskey(r.values, name) || continue
        isequal(getproperty(r.values, name), value) && return true
    end
    return false
end

"""
    validate(contract::AnalysisOptionEffectivenessContract; kwargs...) -> ContractResult

See the type docstring. Rejects unknown keywords through
`_reject_unknown_validate_kwargs`. Returns `ContractResult(ok, message;
metrics)` with every counted verdict in `metrics`; never throws for a failed
probe (an `analyze` that throws where the probe expected a result is a
FAILED probe with the exception's message in `message`).
"""
function validate(contract::AnalysisOptionEffectivenessContract; kwargs...)
    _reject_unknown_validate_kwargs(contract, kwargs)
    metrics = Dict{Symbol,Any}(:checked => 0, :inactive_declared => length(contract.inactive),
                               :inactive_applied => 0, :stale_exemptions => 0, :observables_moved => 0,
                               :observables_fixed => 0, :receipts_checked => 0)
    try
        validate_configuration_metadata()
    catch err
        return ContractResult(false, "configuration metadata validation failed: " * sprint(showerror, err);
                              metrics=metrics)
    end
    fixtures = _analysis_contract_fixtures(contract.seed)
    return _analysis_contract_probe(contract, fixtures, analyze; metrics=metrics)
end

"""
    _ANALYSIS_CONTRACT_FORMS

The probe input forms in the order the contract tries them when it looks for
a form on which an option is active: `:matrix` (dense 6D), `:linearized`,
`:matrix4`, `:coasting`. The keys of `_analysis_contract_fixtures` minus the
`failing` fixture.
"""
const _ANALYSIS_CONTRACT_FORMS = (:matrix, :linearized, :matrix4, :coasting)

"""
    _ANALYSIS_CONTRACT_FIXED_MULTIPLIER

PROVISIONAL `c` of the `c eps kappa` tolerance under which an `:execution`
option must leave the PHYSICAL `zeta`, `eta`, `h` and the tunes fixed
(`scaling`: `:auto` versus `:none` on the dense 6D fixture; the other
`:execution` options are held to bit identity). `kappa = cond(M)` of the
input matrix, the scale `max(1, |value|)` per entry. Measured by stage 4b
Part D1 (measurement_table_4b.md, c_contract_fixed; 11 fixtures at `:auto`
and at the explicit tuple `(1.7, 0.4, 3.1)`): the largest accepted ratio
`|difference| / (eps kappa max(1, |value|))` is 88.4 (the zeta row of the
dense 6D seed 20260911 map under the explicit tuple; 84.8 for the
prescribed h = 0.05 map under `:auto`), the smallest rejected ratio (a
back-transformation row left in scaled coordinates, the eta row of the DBA
cell) is 1.93e14, so the one-tenth / ten window is [884, 1.9e13]; 1024 sits
inside it (Part B's 64 was below the window).
"""
const _ANALYSIS_CONTRACT_FIXED_MULTIPLIER = 1024.0

"""
    _analysis_contract_types() -> Tuple

Every concrete Octopus `AbstractAnalysis` whose `analysis_option_schema` is
non-empty, DERIVED from `_concrete_octopus_subtypes(AbstractAnalysis)`.
"""
function _analysis_contract_types()
    return Tuple(T for T in _concrete_octopus_subtypes(AbstractAnalysis) if !isempty(analysis_option_schema(T)))
end

"""
    _analysis_contract_active_form(contract, name) -> Union{Nothing,Symbol}

The first form of `_ANALYSIS_CONTRACT_FORMS` on which `name` is NOT declared
inactive, or, when it is declared inactive everywhere (an option whose
default disables it, `emittances`), the first form on which the option's
alternative is expected to activate it (`:matrix`).
"""
function _analysis_contract_active_form(contract::AnalysisOptionEffectivenessContract, name::Symbol)
    for form in _ANALYSIS_CONTRACT_FORMS
        haskey(contract.inactive, (form, name)) || return form
    end
    return :matrix
end

"""
    _ANALYSIS_CONTRACT_PROBE_FORMS

Options whose alternative is probed on an input OTHER than the first active
form of `_ANALYSIS_CONTRACT_FORMS`, because the observable never fires on the
dense map: `resolution_chord` runs on `fixtures.repeated` (the repeated
betatron pair, which `Inf` forces and the default chord leaves unresolved;
on the dense map `Inf` forces nothing, so an ignored chord would pass). The
inactivity checks still run on the four forms.
"""
const _ANALYSIS_CONTRACT_PROBE_FORMS = Dict{Symbol,Symbol}(:resolution_chord => :repeated)

"""
    _analysis_contract_run(run, analysis, input) -> (result, receipts, error)

Runs `run(analysis, input)` under a fresh `ExecutionAudit`; returns the
result (or `nothing`), the receipts issued, and the exception (or
`nothing`). Never throws.
"""
function _analysis_contract_run(run, analysis, input)
    audit = ExecutionAudit()
    # Refs, not locals assigned inside the `do` block: a local written in the
    # closure and read outside is a Core.Box (the suite's lowered-code sweep).
    result = Ref{Any}(nothing)
    err = Ref{Any}(nothing)
    with_execution_audit(audit) do
        try
            result[] = run(analysis, input)
        catch e
            err[] = e
        end
    end
    return (result[], execution_receipts(audit), err[])
end

"""
    _analysis_contract_report_status(result, name) -> Union{Nothing,Symbol}

The status of option `name` in `result.configuration` (a vector of
`ConfigurationEntry`), or `nothing` when the report has no such entry.
"""
function _analysis_contract_report_status(result, name::Symbol)
    for entry in result.configuration
        entry.name === name && return entry.status
    end
    return nothing
end

"""
    _analysis_contract_physics(result) -> NamedTuple

The PHYSICAL observables an `:execution` option must leave fixed: `zeta`,
`eta`, `h` (each `nothing` when not unique) and the tunes, read from
`result.physical`.
"""
function _analysis_contract_physics(result)
    ph = result.physical
    pick(d) = d.status === :unique ? d.value : nothing
    return (zeta=pick(ph.zeta), eta=pick(ph.eta), h=pick(ph.h), tunes=collect(Float64, ph.tunes))
end

"""
    _analysis_contract_fixed(a, b; atol_scale) -> (ok::Bool, ratio::Float64)

`a` and `b` are `_analysis_contract_physics` tuples. `atol_scale = 0` demands
bit identity (`isequal`); otherwise every entry must agree within
`_ANALYSIS_CONTRACT_FIXED_MULTIPLIER * eps * atol_scale * max(1, |value|)`
(`atol_scale = cond(M)`); availability must agree exactly. `ratio` is the
largest observed `|difference| / (eps * atol_scale * max(1, |value|))`
(0 for bit identity), the number D1 measures.
"""
function _analysis_contract_fixed(a, b; atol_scale::Real)
    ratio = 0.0
    for name in (:zeta, :eta, :h, :tunes)
        x = getproperty(a, name); y = getproperty(b, name)
        (x === nothing) == (y === nothing) || return (false, Inf)
        x === nothing && continue
        atol_scale == 0 && (isequal(x, y) || return (false, Inf))
        atol_scale == 0 && continue
        length(x) == length(y) || return (false, Inf)
        for (xi, yi) in zip(x, y)
            ratio = max(ratio, abs(xi - yi) / (eps(Float64) * atol_scale * max(1.0, abs(xi))))
        end
    end
    return (ratio <= _ANALYSIS_CONTRACT_FIXED_MULTIPLIER, ratio)
end

"""
    _analysis_contract_failing_fixture(seed, matrix) -> (matrix, analysis)

The `strict` probe's failing input (F9, F13): the dense 6D matrix plus a
`1e-6` random perturbation (Frobenius defect about 1.2e-6), analysed under
`nonsymplectic = :flag` and `symplectic_rtol = 1e-9` so the defect is FLAGGED
(a `1e-3` tolerance would accept it), and the run FAILS through the (K5)
canonical separation (`:not_invariant`), not through the frame residual
(measured by Part A and the stage 4b reviews). `strict = true` (the default)
must throw `OpticsAnalysisError`; `strict = false` must return the `:failed`
result.
"""
function _analysis_contract_failing_fixture(seed::UInt64, M::AbstractMatrix{<:Real})
    rng = MersenneTwister(seed + UInt64(1))
    return Matrix{Float64}(M .+ 1e-6 .* randn(rng, size(M)...))
end

"""
    _analysis_contract_recorded(name, requested) -> Any

The value the consumer's receipt records under the option's name for a
requested value: the requested value itself for EVERY option (dossier F5:
the option's own name holds the value the consumer read; the `clusters`
receipt carries the explicit partition itself since the stage 4b fix, not a
`:explicit` marker, so an ignored partition is visible to the probe).
"""
_analysis_contract_recorded(name::Symbol, requested) = requested

"""
    _analysis_contract_receipt_field(receipts, consumer, field) -> Any

The value of `field` on the first receipt of `consumer` that carries it, or
`nothing`.
"""
function _analysis_contract_receipt_field(receipts, consumer::Symbol, field::Symbol)
    for r in receipts
        r.consumer === consumer && haskey(r.values, field) && return getproperty(r.values, field)
    end
    return nothing
end

"""
    _analysis_contract_observable(name, meta, default_probe, alternative_probe, alternative, M) -> (ok, verdict, detail)

The per-option observable of F9. `default_probe` and `alternative_probe` are
`(result, receipts)` pairs of the same input; `verdict` is `:fixed` for an
`:execution` option (the physics did not move) and `:moved` for a
`:numerical` or `:physics` option (what the option controls changed);
`ok = false` names the option in `detail`. An option this table does not
know is `(false, :none, ...)`: a new option lands with its observable here.
"""
function _analysis_contract_observable(name::Symbol, meta::ConfigurationOptionMeta, dp, ap, alternative, M)
    c = meta.consumer
    field(probe, f) = _analysis_contract_receipt_field(probe[2], c, f)
    if meta.category === :execution
        scale = name === :scaling ? cond(Matrix{Float64}(M)) : 0
        ok, ratio = _analysis_contract_fixed(_analysis_contract_physics(dp[1]), _analysis_contract_physics(ap[1]);
                                             atol_scale=scale)
        if name === :scaling && ok
            # the branch's own output: the scaled matrix IS the matrix under :none and the record says so
            # (a run that computes with :auto factors while echoing mode = :none is caught here)
            mode = alternative isa Symbol ? alternative : :explicit
            ok = ap[1].scaling.mode === mode && field(ap, :mode) === mode && dp[1].scaling.mode === :auto &&
                 isequal(Tuple(ap[1].scaling.factors), field(ap, :factors)) &&
                 (mode !== :none || ap[1].matrix_scaled == ap[1].matrix) && dp[1].matrix_scaled != dp[1].matrix
            ok || return (false, :fixed, "$(name): the scaling record or the scaled matrix does not match the requested mode $(mode)")
        end
        return (ok, :fixed, "$(name): physical zeta, eta, h, tunes ratio $(ratio) (bound $(_ANALYSIS_CONTRACT_FIXED_MULTIPLIER))")
    end
    moved = if name === :symplectic_rtol
        # the rule flips AND the value is the one compared (the receipt's defect is below the alternative);
        # the binding direction (a value below the defect throws) is `_analysis_contract_branch_probe`'s
        field(ap, :rule) === :frobenius && field(dp, :rule) === :row_ratio &&
            (df = field(ap, :defect); df !== nothing && df.frobenius <= alternative) && field(ap, :action) === :accepted
    elseif name === :closed_orbit_atol
        isequal(field(ap, :closed_orbit_atol), alternative) && field(dp, :closed_orbit_atol) === nothing
    elseif name === :map_uncertainty
        (r0 = field(dp, :rho_M0); r1 = field(ap, :rho_M0); r0 !== nothing && r1 !== nothing && r1 > r0)
    elseif name === :resolution_chord
        # probed on the repeated-betatron input, where Inf FORCES a resolution the default chord refuses
        isequal(field(ap, :resolution_chord), alternative) && field(ap, :forced) === true && field(dp, :forced) === false &&
            any(c.forced for c in ap[1].clusters.clusters) && !any(c.forced for c in dp[1].clusters.clusters)
    elseif name === :clusters
        # the partition the consumer read: the receipt carries it and the clusters report groups by it
        members(r) = Set(sort(c.members) for c in r.clusters.clusters)
        isequal(field(ap, :clusters), alternative) && field(dp, :clusters) === :auto &&
            ap[1].clusters.partition_source !== :auto && dp[1].clusters.partition_source === :auto &&
            members(ap[1]) == Set(sort(g) for g in alternative)
    elseif name === :longitudinal_mode
        sel = ap[1].diagnostics.longitudinal_selection
        field(ap, :certified) === true && isequal(field(ap, :selected), alternative) && field(dp, :certified) === false &&
            field(ap, :rule) === :explicit && field(dp, :rule) === :max_signed_z_area &&
            sel.status === :unique && sel.value.rule === :explicit && sel.value.certified
    elseif name === :preferred_form
        pf = ap[1].transverse.status === :unique ? ap[1].transverse.value.preferred_form : nothing
        pf !== nothing && pf.status === :unique && pf.value == alternative &&
            isequal(field(ap, :reported), alternative) && !isequal(field(dp, :reported), alternative)
    elseif name === :dispersion_routes
        isequal(Tuple(field(ap, :executed)), Tuple(alternative)) && !isequal(Tuple(field(dp, :executed)), Tuple(alternative))
    elseif name === :newton_max_iterations
        # the cap BINDS on the dense fixture: the default run needs more Newton iterations than the alternative allows
        (ua = field(ap, :used); ud = field(dp, :used);
         isequal(field(ap, :newton_max_iterations), alternative) && ua isa Integer && ud isa Integer &&
            ua <= alternative && ud > alternative && !isequal(field(dp, :newton_max_iterations), alternative))
    elseif name === :emittances
        ap[1].covariance.status === :unique && dp[1].covariance.status !== :unique
    else
        return (false, :none, "$(name): no observable is known to the analysis contract; add one")
    end
    return (moved, :moved, "$(name): the controlled observable " * (moved ? "moved" : "did NOT move"))
end

"""
    _analysis_contract_probe(contract, fixtures, run; metrics=Dict{Symbol,Any}()) -> ContractResult

The probe loop of `validate(::AnalysisOptionEffectivenessContract)` with the
verb injected: `run(analysis, input)` is `analyze` in `validate` and a
scratch function in the plumbing tests. For every type of
`_analysis_contract_types()` (only `TwissDispersionAnalysis` has fixtures;
another type FAILS until it brings its own) and every schema option: every
`(form, option)` declared inactive is checked on the DEFAULT run of that form
(report `:inactive_dependency`, no receipt of the consumer carrying the
option; a `:resolved` report is a stale exemption and FAILS); then the option
is probed on `_analysis_contract_active_form`: the default run and the
alternative run must both return, the consumer's receipts must carry the
default and the alternative under the option's name, the alternative run's
report must say `:resolved`, and `_analysis_contract_observable` must hold.
`strict` is probed once more on the failing fixture (`strict = true` throws
`OpticsAnalysisError`, `strict = false` returns a `:failed` result). Every
verdict is counted in `metrics`; the first failure returns immediately.
"""
function _analysis_contract_probe(contract::AnalysisOptionEffectivenessContract, fixtures, run;
                                  metrics::Dict{Symbol,Any}=Dict{Symbol,Any}())
    for k in (:checked, :inactive_applied, :stale_exemptions, :observables_moved, :observables_fixed, :receipts_checked)
        get!(metrics, k, 0)
    end
    metrics[:inactive_declared] = length(contract.inactive)
    fail(msg) = ContractResult(false, msg; metrics=metrics)
    types = _analysis_contract_types()
    isempty(types) && return fail("no concrete analysis with a non-empty option schema was found")
    defaults = Dict{Symbol,Any}()
    for form in _ANALYSIS_CONTRACT_FORMS
        res, rec, err = _analysis_contract_run(run, TwissDispersionAnalysis(), getproperty(fixtures, form))
        err === nothing || return fail("default analysis on the $(form) fixture threw: " * sprint(showerror, err))
        defaults[form] = (res, rec)
    end
    seen = Set{Tuple{Symbol,Symbol}}()
    for T in types
        T === TwissDispersionAnalysis || return fail("$(T) has a non-empty option schema but the analysis " *
            "contract has no fixtures or observables for it; extend the contract")
        schema = analysis_option_schema(T)
        for (name, meta) in pairs(schema)
            haskey(contract.alternatives, name) || return fail("$(T).$(name) has no declared alternative")
            alternative = contract.alternatives[name]
            isequal(alternative, meta.default) && return fail("$(T).$(name): the alternative equals the default")
            for form in _ANALYSIS_CONTRACT_FORMS
                haskey(contract.inactive, (form, name)) || continue
                push!(seen, (form, name))
                res, rec = defaults[form]
                status = _analysis_contract_report_status(res, name)
                if status !== :inactive_dependency
                    metrics[:stale_exemptions] += 1
                    return fail("$(T).$(name) is declared inactive on the $(form) fixture but the report says " *
                                "$(status): stale exemption")
                end
                any(r -> r.consumer === meta.consumer && haskey(r.values, name), rec) &&
                    return fail("$(T).$(name) is inactive on the $(form) fixture yet $(meta.consumer) issued a receipt carrying it")
                metrics[:inactive_applied] += 1
            end
            form = _analysis_contract_active_form(contract, name)
            probe_form = get(_ANALYSIS_CONTRACT_PROBE_FORMS, name, form)
            if probe_form !== form
                hasproperty(fixtures, probe_form) || return fail("$(T).$(name) is probed on the $(probe_form) input, which the fixtures do not carry")
                res, rec, err = _analysis_contract_run(run, TwissDispersionAnalysis(), getproperty(fixtures, probe_form))
                err === nothing || return fail("default analysis on the $(probe_form) input threw: " * sprint(showerror, err))
                defaults[probe_form] = (res, rec)
            end
            form = probe_form
            dp = defaults[form]
            ares, arec, aerr = _analysis_contract_run(run, T(; name => alternative), getproperty(fixtures, form))
            aerr === nothing || return fail("$(T).$(name) = $(alternative) on the $(form) fixture threw: " * sprint(showerror, aerr))
            ap = (ares, arec)
            if !haskey(contract.inactive, (form, name))
                _analysis_contract_receipt_carries(dp[2], meta.consumer, name, _analysis_contract_recorded(name, meta.default)) ||
                    return fail("$(T).$(name): no $(meta.consumer) receipt carries the default $(meta.default) on the $(form) fixture")
                metrics[:receipts_checked] += 1
            end
            _analysis_contract_receipt_carries(arec, meta.consumer, name, _analysis_contract_recorded(name, alternative)) ||
                return fail("$(T).$(name): no $(meta.consumer) receipt carries the alternative $(alternative) on the $(form) fixture")
            metrics[:receipts_checked] += 1
            status = _analysis_contract_report_status(ares, name)
            status === :resolved || return fail("$(T).$(name) = $(alternative) reported $(status), expected :resolved")
            ok, verdict, detail = _analysis_contract_observable(name, meta, dp, ap, alternative, getproperty(fixtures, :matrix))
            ok || return fail("$(T).$(name): observable check failed: " * detail)
            verdict === :fixed && (metrics[:observables_fixed] += 1)
            verdict === :moved && (metrics[:observables_moved] += 1)
            metrics[:checked] += 1
        end
    end
    stale = setdiff(Set(keys(contract.inactive)), seen)
    if !isempty(stale)
        metrics[:stale_exemptions] += length(stale)
        return fail("inactive entries never reached (unknown form or option): " * join(sort!(string.(collect(stale))), ", "))
    end
    branch = _analysis_contract_branch_probe(contract, fixtures, run, metrics)
    branch.passed || return branch
    return _analysis_contract_strict_probe(contract, fixtures, run, metrics)
end

"""
    _analysis_contract_branch_probe(contract, fixtures, run, metrics) -> ContractResult

The branch probes of the options whose alternative does not fire on the dense
map (stage 4b tests review: eight probes could not fail when the consumer
ignored the option). Each reads the branch's OWN outcome: (1)
`symplectic_rtol` BINDS: `symplectic_rtol = 1e-20` on the dense map (a value
below its roundoff defect) throws an ArgumentError naming the `:frobenius`
rule under the default `nonsymplectic = :error`; (2) `nonsymplectic`: on
`fixtures.failing` at `symplectic_rtol = 1e-9` the default `:error` throws an
ArgumentError while `:flag` returns a result whose `:analysis_symplectic_check`
receipt says `action = :flagged` and whose degradations name the flag; (3)
`closed_orbit`: on `fixtures.displaced` (a non-zero fixed-point residual) the
default `:require` throws an ArgumentError naming `closed_orbit` while
`:warn` returns a `:degraded` result whose `:analysis_closed_orbit` receipt
says `action = :warned`; (4) `closed_orbit_atol = 1.0` on the same input
returns with `action = :accepted` and no closed-orbit degradation. Each
probe counts one `checked`, one `observables_moved` and its receipts.
"""
function _analysis_contract_branch_probe(contract::AnalysisOptionEffectivenessContract, fixtures, run,
                                         metrics::Dict{Symbol,Any})
    fail(msg) = ContractResult(false, msg; metrics=metrics)
    for key in (:failing, :displaced)
        hasproperty(fixtures, key) || return fail("the probe fixtures carry no :$(key) input for the branch probes")
    end
    is_arg(err) = err isa ArgumentError || (run !== analyze && err !== nothing && !(hasproperty(err, :result)))
    # (1) the rtol value binds
    _, _, err = _analysis_contract_run(run, TwissDispersionAnalysis(symplectic_rtol=1e-20), fixtures.matrix)
    (is_arg(err) && occursin("frobenius", sprint(showerror, err))) ||
        return fail("symplectic_rtol = 1e-20 on the dense fixture did not throw the :frobenius ArgumentError " *
                    (err === nothing ? "(it returned a result)" : "(it threw " * sprint(showerror, err) * ")"))
    metrics[:observables_moved] += 1; metrics[:checked] += 1
    # (2) :error throws, :flag returns flagged
    _, _, err = _analysis_contract_run(run, TwissDispersionAnalysis(symplectic_rtol=1e-9, strict=false), fixtures.failing)
    is_arg(err) || return fail("nonsymplectic = :error on the failing fixture at symplectic_rtol = 1e-9 did not throw an ArgumentError")
    res, rec, err = _analysis_contract_run(run, TwissDispersionAnalysis(nonsymplectic=:flag, symplectic_rtol=1e-9, strict=false), fixtures.failing)
    err === nothing || return fail("nonsymplectic = :flag on the failing fixture threw: " * sprint(showerror, err))
    _analysis_contract_receipt_carries(rec, :analysis_symplectic_check, :action, :flagged) ||
        return fail("nonsymplectic = :flag: the :analysis_symplectic_check receipt does not carry action = :flagged")
    any(s -> occursin("nonsymplectic = :flag", s), res.degradations) ||
        return fail("nonsymplectic = :flag: no degradation names the flag")
    metrics[:receipts_checked] += 1; metrics[:observables_moved] += 1; metrics[:checked] += 1
    # (3) closed_orbit: :require throws, :warn degrades
    _, _, err = _analysis_contract_run(run, TwissDispersionAnalysis(), fixtures.displaced)
    (is_arg(err) && occursin("closed_orbit", sprint(showerror, err))) ||
        return fail("closed_orbit = :require on the displaced fixture did not throw an ArgumentError naming closed_orbit")
    # the :warn branch emits its one user-facing warning (the suite pins it with @test_logs); a contract run
    # is not the place for it, so the probe reads the receipt and the status under a null logger
    res, rec, err = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        _analysis_contract_run(run, TwissDispersionAnalysis(closed_orbit=:warn), fixtures.displaced)
    end
    err === nothing || return fail("closed_orbit = :warn on the displaced fixture threw: " * sprint(showerror, err))
    (res.status === :degraded && _analysis_contract_receipt_carries(rec, :analysis_closed_orbit, :action, :warned)) ||
        return fail("closed_orbit = :warn on the displaced fixture: status $(res.status), receipt action not :warned")
    metrics[:receipts_checked] += 1; metrics[:observables_moved] += 1; metrics[:checked] += 1
    # (4) closed_orbit_atol accepts the displaced point
    res, rec, err = _analysis_contract_run(run, TwissDispersionAnalysis(closed_orbit_atol=1.0), fixtures.displaced)
    err === nothing || return fail("closed_orbit_atol = 1.0 on the displaced fixture threw: " * sprint(showerror, err))
    (_analysis_contract_receipt_carries(rec, :analysis_closed_orbit, :action, :accepted) &&
     !any(s -> occursin("closed_orbit", s), res.degradations)) ||
        return fail("closed_orbit_atol = 1.0 on the displaced fixture: the receipt action is not :accepted or the orbit still degrades")
    metrics[:receipts_checked] += 1; metrics[:observables_moved] += 1; metrics[:checked] += 1
    return ContractResult(true, "branch probes passed"; metrics=metrics)
end

"""
    _analysis_contract_strict_probe(contract, fixtures, run, metrics) -> ContractResult

The second half of the `strict` probe (F9): on `fixtures.failing` (the
perturbed dense map) under `nonsymplectic = :flag`, `symplectic_rtol = 1e-9`
(the defect is flagged, and the verdict fails through the separation status),
`strict = true` must throw `OpticsAnalysisError` whose payload is `:failed`,
and `strict = false` must RETURN a result with `status === :failed` and an
`:analysis_strictness` receipt carrying `strict = false` and `outcome =
:failed`. Counted in `checked`, `receipts_checked`, `observables_moved`.
An injected `run` (plumbing tests) may throw any exception carrying `result`
and `failures` in place of `OpticsAnalysisError`.
"""
function _analysis_contract_strict_probe(contract::AnalysisOptionEffectivenessContract, fixtures, run,
                                         metrics::Dict{Symbol,Any})
    fail(msg) = ContractResult(false, msg; metrics=metrics)
    hasproperty(fixtures, :failing) || return fail("the probe fixtures carry no :failing input for the strict probe")
    M = fixtures.failing
    base = (nonsymplectic=:flag, symplectic_rtol=1e-9)
    res, rec, err = _analysis_contract_run(run, TwissDispersionAnalysis(; base..., strict=true), M)
    thrown = err isa OpticsAnalysisError ||
        (run !== analyze && err !== nothing && hasproperty(err, :result) && hasproperty(err, :failures))
    thrown || return fail("strict = true on the failing fixture did not throw OpticsAnalysisError " *
        (err === nothing ? "(it returned a result with status $(res.status))" : "(it threw " * sprint(showerror, err) * ")"))
    err.result.status === :failed || return fail("OpticsAnalysisError carries a result with status $(err.result.status), expected :failed")
    res, rec, err = _analysis_contract_run(run, TwissDispersionAnalysis(; base..., strict=false), M)
    err === nothing || return fail("strict = false on the failing fixture threw: " * sprint(showerror, err))
    res.status === :failed || return fail("strict = false on the failing fixture returned status $(res.status), expected :failed")
    _analysis_contract_receipt_carries(rec, :analysis_strictness, :strict, false) ||
        return fail("strict = false: no :analysis_strictness receipt carries strict = false on the failing fixture")
    _analysis_contract_receipt_carries(rec, :analysis_strictness, :outcome, :failed) ||
        return fail("strict = false: the :analysis_strictness receipt does not carry outcome = :failed")
    metrics[:receipts_checked] += 2
    metrics[:observables_moved] += 1
    metrics[:checked] += 1
    n = metrics[:checked]
    return ContractResult(true, "analysis options certified: $(n) probes, $(get(metrics, :inactive_applied, 0)) inactive " *
        "entries applied, $(metrics[:receipts_checked]) receipts checked, $(metrics[:observables_moved]) moved, " *
        "$(get(metrics, :observables_fixed, 0)) fixed"; metrics=metrics)
end
