export TwissExternalReferenceContract

"""
    TwissExternalReferenceContract(; reference_dir=nothing, tolerance_scale=1.0)

The light suite contract of the stage 8 external twiss benchmarks (design note
`docs/design/twiss_dispersion_analysis.md`, staging item 8; the 2026-09-15
stage 8 sections of `docs/history/twiss_dispersion_analysis_history.md` and
the batch record `docs/history/twiss_external_benchmarks_2026_09_15.md`). It
re-runs, on committed numbers only, every CONVENTION row of the three
benchmark scripts whose two sides both sit in a committed table: the optics an
external code printed (MAD-X 5.03.06 `twiss`, PTC `ptc_twiss`, xtrack 0.112.0
`get_linear_normal_form` / `Line.twiss`) against `analyze` applied to a matrix
read from `validation/reference/` (the external one-turn map converted by the
stage 8 law, or the Octopus map xtrack was handed). No external tool runs and
no fixture is compiled: the twin rows, the nst ladders (TOL-E), the
rolled-family anchors and the recorded rows stay in the validation scripts.

Tables (newest version by numeric fields, the `PTCConsistencyContract` rule):
`twiss_madx_<v>.tsv`, `ptc_twiss_madx_<v>.tsv`, `xsuite_twiss_xtrack_<v>.tsv`
and the Octopus maps `twiss_benchmark_maps.tsv`, all under `reference_dir`
(default `validation/reference/` of this tree). A missing table gives
`ContractResult(:skipped, ...)` naming the generator that writes it.

The conversion law (the stage 8 history sections; `convert_map` of
`validation/twiss_benchmark_cells.jl` is the validation-side copy):
M_oct = Sh(u) J0 F M_ext F^-1 J0^-1 with Sh(u) = I except (5,6) = u;
MAD-X J0 = diag(1,1,1,1,beta0,1/beta0), F = I; xtrack J0 = I, F = I;
PTC time=false J0 = I, F = diag(1,1,1,1,-1,1); u = -C/gamma0^2 for the bare
target of a MAD-X or xtrack map, +C/gamma0^2 for the task target of a PTC map,
0 otherwise (a PTC map is the partner of the bare compile, a MAD-X map after
J0 and an xtrack map are partners of the task compile).

Tolerance classes are the scripts' (TOL-A 1e-12 relative, floored at |ext| = 1,
and 1e-13 absolute on cos mu, sin mu; TOL-B 1e-12 on beta0 DX; TOL-C 1e-9
relative and 1e-10 on cos mu for PTC; TOL-D 1e-7 on anything touching rows or
columns 5-6 of an xtrack finite-difference map; TOL-F 1e-10 absolute on the
degenerate rolled cells), each multiplied by `tolerance_scale`, plus `assert`
(an exact 1-vs-1 at tolerance 0 for the scripts' `assert_row` calls and the PTC
`table_rows_present` count), `witness` (the scripts' `witness_row` calls:
1e-12 absolute on the S0/S0_pt pins, the symplectic residuals and the T6 C
pin, 1e-13 on the form-1 twiss mu, 1e-10 on the W1 cavity law, 1e-7 relative
on the T6 longitudinal block) and `TOL-A-cond` (TOL-A widened to
10 kappa(U)^2 eps_mach on the manufactured dense maps). `metrics` carries
`rows`, `rows_<code>`, `failed`, `failed_<code>`, `worst_ratio`, `worst_row`,
`worst_<class>` (the class with `-` replaced by `_`: `worst_TOL_A`,
`worst_TOL_A_cond`, `worst_TOL_B`, `worst_TOL_C`, `worst_TOL_D`,
`worst_TOL_F`, `worst_assert`, `worst_witness`) and `table_<code>`;
`residual = worst_ratio`.
A code that contributes no row fails the contract (a silent pass is not a
pass). Validation twins: `validation/twiss_madx_benchmark.jl`,
`validation/twiss_ptc_benchmark.jl`, `validation/twiss_xsuite_benchmark.jl`.
"""
Base.@kwdef struct TwissExternalReferenceContract <: AbstractPhysicsContract
    reference_dir::Union{Nothing,String} = nothing
    tolerance_scale::Float64 = 1.0
end

description(::Type{TwissExternalReferenceContract}) =
    "Re-runs the convention rows of the MAD-X, PTC and xtrack twiss benchmarks on the committed reference tables: external optics against analyze of the converted external map, at the benchmarks' tolerance classes."

# ---------------------------------------------------------------------------
# Constants: the tolerance classes, the PTC table's expected fixtures and the
# inputs of the W1 cavity witness (`validation/twiss_benchmark_cells.jl`:
# BENCH_E_TOTAL_EV, PTC_INTERNAL_PROTON_MASS_GEV; decision D19).

const _EXTREF_TOL_A_REL = 1e-12
const _EXTREF_TOL_A_ABS = 1e-13
const _EXTREF_TOL_B_REL = 1e-12
const _EXTREF_TOL_C_REL = 1e-9
const _EXTREF_TOL_C_COS = 1e-10
const _EXTREF_TOL_D_REL = 1e-7
const _EXTREF_TOL_F_ABS = 1e-10
const _EXTREF_TOL_WITNESS = 1e-12
const _EXTREF_TOL_W1 = 1e-10
const _EXTREF_BENCH_E_TOTAL_EV = 3.0e9
const _EXTREF_PTC_INTERNAL_PROTON_MASS_GEV = 0.938272081358
const _EXTREF_PTC_EXPECTED_IDS = ("S0", "S0_pt", "W1", "U1", "U2", "K2", "B4", "B4K", "G6_2.0MV", "G6_0.2MV")

const _EXTREF_TABLES = (
    madx   = (prefix="twiss_madx_",          generator="validation/generate_madx_twiss_reference.jl"),
    ptc    = (prefix="ptc_twiss_madx_",      generator="validation/generate_ptc_twiss_reference.jl"),
    xtrack = (prefix="xsuite_twiss_xtrack_", generator="validation/generate_xsuite_twiss_reference.py"),
    maps   = (prefix="twiss_benchmark_maps", generator="validation/twiss_benchmark_cells.jl (write_benchmark_maps)"),
)

# ---------------------------------------------------------------------------
# Tables: the wide form (MAD-X, PTC, maps: one '#' header block, one column
# row, one run per row) and the long form (xtrack: layer, fixture, compile,
# quantity, value).

struct _ExtRefTable
    path::String
    header::Vector{String}
    columns::Vector{String}
    rows::Vector{Dict{String,String}}
end

"Reads a wide '#'-headed TSV table: header lines, one column row, one run per row."
function _extref_read_wide(path::AbstractString)
    header = String[]; columns = String[]; rows = Dict{String,String}[]
    for line in eachline(path)
        isempty(strip(line)) && continue
        if startswith(line, '#')
            push!(header, line); continue
        end
        fields = split(line, '\t'; keepempty=true)
        if isempty(columns)
            columns = String.(fields); continue
        end
        length(fields) == length(columns) ||
            throw(ArgumentError("_extref_read_wide: $(path) row with $(length(fields)) fields, $(length(columns)) columns"))
        push!(rows, Dict{String,String}(columns[i] => String(fields[i]) for i in eachindex(columns)))
    end
    isempty(columns) && throw(ArgumentError("_extref_read_wide: $(path) has no column row"))
    return _ExtRefTable(String(path), header, columns, rows)
end

"The Float64 in column `key` of a wide row."
_extref_float(row::Dict{String,String}, key::AbstractString) = parse(Float64, row[key])

"Rows of a wide table whose column `key` equals `value`."
_extref_select(tab::_ExtRefTable, key::AbstractString, value::AbstractString) =
    [r for r in tab.rows if r[key] == value]

"The n x n matrix in columns <prefix>ij<suffix> of a wide row (1-based i, j)."
function _extref_matrix(row::Dict{String,String}, prefix::AbstractString; suffix::AbstractString="", n::Int=6)
    M = zeros(n, n)
    for i in 1:n, j in 1:n
        M[i, j] = _extref_float(row, string(prefix, i, j, suffix))
    end
    return M
end

struct _ExtRefLongTable
    path::String
    header::Vector{String}
    values::Dict{NTuple{4,String},Float64}
end

"Reads the long xtrack table (layer, fixture, compile, quantity, value) into a keyed dictionary."
function _extref_read_long(path::AbstractString)
    header = String[]; values = Dict{NTuple{4,String},Float64}(); columns = String[]
    for line in eachline(path)
        isempty(strip(line)) && continue
        if startswith(line, '#')
            push!(header, line); continue
        end
        fields = split(line, '\t'; keepempty=true)
        if isempty(columns)
            columns = String.(fields)
            columns == ["layer", "fixture", "compile", "quantity", "value"] ||
                throw(ArgumentError("_extref_read_long: $(path) columns $(columns) are not layer, fixture, compile, quantity, value"))
            continue
        end
        length(fields) == 5 || throw(ArgumentError("_extref_read_long: $(path) row with $(length(fields)) fields"))
        values[(String(fields[1]), String(fields[2]), String(fields[3]), String(fields[4]))] = parse(Float64, fields[5])
    end
    return _ExtRefLongTable(String(path), header, values)
end

"The value at (layer, fixture, compile, quantity) of a long table."
_extref_cell(t::_ExtRefLongTable, layer, fixture, compile, quantity) =
    t.values[(String(layer), String(fixture), String(compile), String(quantity))]

"The n x n matrix in quantities <prefix>ij of a long table (1-based i, j)."
function _extref_long_matrix(t::_ExtRefLongTable, layer, fixture, compile, prefix::AbstractString; n::Int=6)
    M = zeros(n, n)
    for i in 1:n, j in 1:n
        M[i, j] = _extref_cell(t, layer, fixture, compile, string(prefix, i, j))
    end
    return M
end

"The Octopus one-turn map of fixture `id` at `compile` (bare, task, matrix) from the maps table, with its C, beta0, gamma0."
function _extref_octopus_map(maps::_ExtRefTable, id::AbstractString, compile::AbstractString)
    rows = [r for r in maps.rows if r["id"] == id && r["compile"] == compile]
    length(rows) == 1 || throw(ArgumentError("_extref_octopus_map: $(length(rows)) maps rows for $(id) $(compile)"))
    r = first(rows)
    return (M=_extref_matrix(r, "m"), C=_extref_float(r, "C"), beta0=_extref_float(r, "beta0"), gamma0=_extref_float(r, "gamma0"))
end

# ---------------------------------------------------------------------------
# Location of the tables and the conversion law.

"`contract.reference_dir`, or `validation/reference/` of the tree this file sits in."
function _extref_reference_dir(contract::TwissExternalReferenceContract)
    contract.reference_dir !== nothing && return String(contract.reference_dir)
    # @__DIR__ rather than pkgdir, so the contract resolves whether Octopus was
    # loaded as a package or by include (the PTCConsistencyContract rule).
    return normpath(joinpath(@__DIR__, "..", "..", "validation", "reference"))
end

"Newest table `<prefix>*.tsv` under `dir` by NUMERIC version fields, or `nothing`."
function _extref_table_path(dir::AbstractString, prefix::AbstractString)
    isdir(dir) || return nothing
    files = filter(f -> startswith(f, prefix) && endswith(f, ".tsv"), readdir(dir))
    isempty(files) && return nothing
    natkey(f) = [something(tryparse(Int, m.match), 0) for m in eachmatch(r"\d+", f)]
    return joinpath(dir, last(sort(files; by=natkey)))
end

"Sh(u): the identity except (5,6) = u."
function _extref_shear(u::Real)
    S = Matrix{Float64}(I, 6, 6); S[5, 6] = Float64(u)
    return S
end

"""
    _extref_convert(code, M; beta0, gamma0, C, target=:bare) -> Matrix{Float64}

The stage 8 conversion law M_oct = Sh(u) J0 F M F^-1 J0^-1 for `code` in
(:madx, :ptc, :xtrack) at the Octopus compile `target` (:bare or :task); see
the contract docstring for J0, F and u per code.
"""
function _extref_convert(code::Symbol, M::AbstractMatrix; beta0::Real, gamma0::Real, C::Real, target::Symbol=:bare)
    size(M) == (6, 6) || throw(ArgumentError("_extref_convert: expected a 6x6 map, got $(size(M))"))
    target in (:bare, :task) || throw(ArgumentError("_extref_convert: target must be :bare or :task, got :$(target)"))
    Mf = Matrix{Float64}(M)
    if code === :madx || code === :xtrack
        J0 = code === :madx ? Diagonal([1.0, 1.0, 1.0, 1.0, Float64(beta0), 1.0 / Float64(beta0)]) : Diagonal(ones(6))
        u = target === :bare ? -Float64(C) / Float64(gamma0)^2 : 0.0
        return _extref_shear(u) * (J0 * Mf * inv(J0))
    elseif code === :ptc
        F = Diagonal([1.0, 1.0, 1.0, 1.0, -1.0, 1.0])
        u = target === :task ? Float64(C) / Float64(gamma0)^2 : 0.0
        return _extref_shear(u) * (F * Mf * F)
    end
    throw(ArgumentError("_extref_convert: code must be :madx, :ptc or :xtrack, got :$(code)"))
end

# ---------------------------------------------------------------------------
# The analysis (every read guarded by is_determined) and the rows.

"The value of a Determined, or `nothing` when it is undetermined (never unwrap blindly)."
_extref_dval(d) = is_determined(d) ? determined_value(d) : nothing

"""
    _extref_analyze(M; mu_s=nothing) -> NamedTuple

`analyze` with `TwissDispersionAnalysis(strict=false, scaling=:none)` (plus
`longitudinal_mode=mu_s` when given, the external code's own |mu3| in rad per
turn) and the reads the rows need: tunes (rad/turn, eigen order), the
presented form, form-1 R, lambda and mode Twiss, form-2 Twiss and lambda, the
physical normalizer, beta/alpha/gamma [mode, plane], graph, zeta, eta, h.
"""
function _extref_analyze(M::AbstractMatrix; mu_s=nothing)
    an = mu_s === nothing ? TwissDispersionAnalysis(strict=false, scaling=:none) :
                            TwissDispersionAnalysis(strict=false, scaling=:none, longitudinal_mode=Float64(mu_s))
    result = analyze(an, Matrix{Float64}(M))
    form = 0; R = nothing; twiss = nothing; lambda = NaN; twiss2 = nothing; lambda2 = NaN
    if is_determined(result.transverse)
        trv = determined_value(result.transverse)
        form = something(_extref_dval(trv.preferred_form), 0)
        if is_determined(trv.edwards_teng_normalizer)
            pair = determined_value(trv.edwards_teng_normalizer)
            R = _extref_dval(pair.form1.R); twiss = _extref_dval(pair.form1.twiss)
            lambda = something(_extref_dval(pair.form1.lambda), NaN)
            twiss2 = _extref_dval(pair.form2.twiss)
            lambda2 = something(_extref_dval(pair.form2.lambda), NaN)
        end
    end
    ph = result.physical
    return (result=result, status=result.status, tunes=copy(ph.tunes), form=form, R=R, twiss=twiss, lambda=lambda,
            twiss2=twiss2, lambda2=lambda2, U=_extref_dval(ph.normalizer), beta=_extref_dval(ph.beta),
            alpha=_extref_dval(ph.alpha), gamma=_extref_dval(ph.gamma), graph=_extref_dval(ph.graph),
            zeta=_extref_dval(ph.zeta), eta=_extref_dval(ph.eta), h=_extref_dval(ph.h))
end

const _ExtRefRow = NamedTuple{(:code, :fixture, :quantity, :octopus, :external, :diff, :bound, :class, :passed),
                              Tuple{Symbol,String,String,Float64,Float64,Float64,Float64,String,Bool}}

"""
    _extref_compare!(rows, contract, code, fixture, quantity, oct, ext, tol, class; rel=true) -> Bool

One gated row: |oct - ext| against `tol * max(|ext|, 1)` (rel) or `tol` (abs),
both scaled by `contract.tolerance_scale`; a non-finite Octopus value fails.
"""
function _extref_compare!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, code::Symbol,
                          fixture, quantity, oct::Real, ext::Real, tol::Real, class::AbstractString; rel::Bool=true)
    o = Float64(oct); e = Float64(ext)
    diff = abs(o - e)
    bound = contract.tolerance_scale * (rel ? Float64(tol) * max(abs(e), 1.0) : Float64(tol))
    passed = isfinite(diff) && diff <= bound
    push!(rows, (code=code, fixture=String(fixture), quantity=String(quantity), octopus=o, external=e,
                 diff=diff, bound=bound, class=String(class), passed=passed))
    return passed
end

"Index of the Octopus mode whose cos(tune) is closest to `c` (matched by eigenvalue, never by label)."
function _extref_match_mode(tunes::AbstractVector, c::Real)
    best = 1; bestd = Inf
    for (j, mu) in enumerate(tunes)
        d = abs(cos(mu) - c)
        d < bestd && (best = j; bestd = d)
    end
    return best
end

# ---------------------------------------------------------------------------
# The three code sections. Each mirrors the CONVENTION layer of its benchmark
# script row by row (same fixtures, same quantities, same tolerance class, same
# mode matching), on committed numbers only.

"""
    _extref_madx_rows!(rows, contract, tab::_ExtRefTable) -> Nothing

The MAD-X convention rows (benchmark A, layer A1 of
`validation/twiss_madx_benchmark.jl`, plus the gated detuned control of its
layer A3): for U1, U2, K1, K2 the optics of the `periodic` row are read against
`analyze` of the `initial` row's one-turn map converted by
`_extref_convert(:madx, ...)` with the row's beta0, gamma0, C. Rows, in the
script's order and classes: the analyze status (class `assert`, tol 0), cos mu
and sin mu of q1 and q2 (TOL-A absolute, the mode matched by eigenvalue), two
distinct modes matched (`assert`), the presented Edwards-Teng form 1 on the
coupled cells K1, K2 (`assert`), ET_betx/ET_alfx of the q1 mode and
ET_bety/ET_alfy of the q2 mode (TOL-A relative), the form-1 twiss mu against the
tunes (the script's witness row, 1e-13 absolute, class `witness`), MR_beta_x/MR_beta_y on the uncoupled cells only
(TOL-A relative), r11..r22 = form-1 R on the coupled cells only (TOL-A
relative), the form-1 lambda against 1/sqrt(1 + det R_madx) on the coupled
cells (TOL-A relative), and eta_dx..eta_dpy against beta0 * DX (TOL-B
relative). Rd_1e-3 contributes its status and cos/sin mu rows at TOL-F. Rows
the script only records (the rolled sentinels R_0.01, R_0.1, R_pi8, the
unstable R_pi4, Rd_1e-6, the presented form and R of the uncoupled cells),
the table-vs-map pin of MAD-X's own lambda, the A3 anchors of the exported
rolled maps against theory and the Rd_1e-3 periodic-tune-vs-exported-map rows
(MAD-X-internal, no Octopus side) are not compared.
"""
function _extref_madx_rows!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, tab::_ExtRefTable)
    for fixture in ("U1", "U2", "K1", "K2")
        _extref_madx_fixture!(rows, contract, tab, fixture; coupled=fixture in ("K1", "K2"),
                              tune_tol=_EXTREF_TOL_A_ABS, tune_class="TOL-A", full=true)
    end
    _extref_madx_fixture!(rows, contract, tab, "Rd_1e-3"; coupled=false,
                          tune_tol=_EXTREF_TOL_F_ABS, tune_class="TOL-F", full=false)
    return nothing
end

"The single (fixture, file) row of the MAD-X table."
function _extref_madx_row(tab::_ExtRefTable, fixture::AbstractString, file::AbstractString)
    found = [r for r in tab.rows if r["fixture"] == fixture && r["file"] == file]
    length(found) == 1 || throw(ArgumentError("_extref_madx_rows!: $(length(found)) rows for $(fixture) $(file)"))
    return first(found)
end

"cos mu and sin mu of the Octopus mode matched to MAD-X's q (rule T of the script); returns the mode index or 0."
function _extref_madx_tune_rows!(rows, contract, fixture, an, q::Float64, label::AbstractString, tol::Float64, class::AbstractString)
    c = cos(2pi * q); s = sin(2pi * q)
    if isempty(an.tunes)
        _extref_compare!(rows, contract, :madx, fixture, "cos_mu_$(label)", NaN, c, tol, class; rel=false)
        _extref_compare!(rows, contract, :madx, fixture, "sin_mu_$(label)", NaN, s, tol, class; rel=false)
        return 0
    end
    j = _extref_match_mode(an.tunes, c)
    mu = an.tunes[j]
    _extref_compare!(rows, contract, :madx, fixture, "cos_mu_$(label)", cos(mu), c, tol, class; rel=false)
    _extref_compare!(rows, contract, :madx, fixture, "sin_mu_$(label)", sin(mu), s, tol, class; rel=false)
    return j
end

"An assertion of the script as a row: 1 against 1 at tolerance 0 (class `assert`)."
_extref_madx_assert!(rows, contract, fixture, name::AbstractString, ok::Bool) =
    _extref_compare!(rows, contract, :madx, fixture, name, ok ? 1.0 : 0.0, 1.0, 0.0, "assert"; rel=false)

"The convention rows of one fixture: periodic optics against analyze of the converted initial-row map."
function _extref_madx_fixture!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, tab::_ExtRefTable,
                               fixture::AbstractString; coupled::Bool, tune_tol::Float64, tune_class::AbstractString, full::Bool)
    ip = _extref_madx_row(tab, fixture, "periodic")
    ia = _extref_madx_row(tab, fixture, "initial")
    beta0 = _extref_float(ip, "beta0"); gamma0 = _extref_float(ip, "gamma0"); C = _extref_float(ip, "C")
    M = _extref_convert(:madx, _extref_matrix(ia, "re"); beta0=_extref_float(ia, "beta0"),
                        gamma0=_extref_float(ia, "gamma0"), C=_extref_float(ia, "C"), target=:bare)
    an = _extref_analyze(M)
    q1 = _extref_float(ip, "q1"); q2 = _extref_float(ip, "q2")
    _extref_madx_assert!(rows, contract, fixture, "analyze_status_passed", an.status === :passed)
    j1 = _extref_madx_tune_rows!(rows, contract, fixture, an, q1, "q1", tune_tol, tune_class)
    j2 = _extref_madx_tune_rows!(rows, contract, fixture, an, q2, "q2", tune_tol, tune_class)
    full || return nothing
    _extref_madx_assert!(rows, contract, fixture, "two_distinct_modes_matched", j1 != 0 && j2 != 0 && j1 != j2)
    coupled && _extref_madx_assert!(rows, contract, fixture, "presented_ET_form_is_1", an.form == 1)
    betx = _extref_float(ip, "betx"); alfx = _extref_float(ip, "alfx")
    bety = _extref_float(ip, "bety"); alfy = _extref_float(ip, "alfy")
    if an.twiss === nothing || j1 == 0 || j2 == 0
        for (name, ext) in (("ET_betx", betx), ("ET_alfx", alfx), ("ET_bety", bety), ("ET_alfy", alfy))
            _extref_compare!(rows, contract, :madx, fixture, name, NaN, ext, _EXTREF_TOL_A_REL, "TOL-A")
        end
    else
        w1 = an.twiss[j1]; w2 = an.twiss[j2]
        _extref_compare!(rows, contract, :madx, fixture, "ET_betx", w1.beta, betx, _EXTREF_TOL_A_REL, "TOL-A")
        _extref_compare!(rows, contract, :madx, fixture, "ET_alfx", w1.alpha, alfx, _EXTREF_TOL_A_REL, "TOL-A")
        _extref_compare!(rows, contract, :madx, fixture, "ET_bety", w2.beta, bety, _EXTREF_TOL_A_REL, "TOL-A")
        _extref_compare!(rows, contract, :madx, fixture, "ET_alfy", w2.alpha, alfy, _EXTREF_TOL_A_REL, "TOL-A")
        _extref_compare!(rows, contract, :madx, fixture, "form1_twiss_mu_vs_tunes",
                         max(abs(w1.mu - an.tunes[j1]), abs(w2.mu - an.tunes[j2])), 0.0, _EXTREF_TOL_A_ABS, "witness"; rel=false)
        if an.beta !== nothing && !coupled
            _extref_compare!(rows, contract, :madx, fixture, "MR_beta_x", an.beta[j1, 1], betx, _EXTREF_TOL_A_REL, "TOL-A")
            _extref_compare!(rows, contract, :madx, fixture, "MR_beta_y", an.beta[j2, 2], bety, _EXTREF_TOL_A_REL, "TOL-A")
        end
    end
    if coupled
        # rule Z of the script: form-1 R and lambda are gated on the coupled cells only
        Rm = [_extref_float(ip, "r11") _extref_float(ip, "r12"); _extref_float(ip, "r21") _extref_float(ip, "r22")]
        for (k, name) in zip(((1, 1), (1, 2), (2, 1), (2, 2)), ("r11", "r12", "r21", "r22"))
            v = an.R === nothing ? NaN : an.R[k...]
            _extref_compare!(rows, contract, :madx, fixture, name, v, Rm[k...], _EXTREF_TOL_A_REL, "TOL-A")
        end
        lambda_madx = 1 / sqrt(1 + det(Rm))
        _extref_compare!(rows, contract, :madx, fixture, "octopus_form1_lambda_vs_madx_lambda", an.lambda, lambda_madx,
                         _EXTREF_TOL_A_REL, "TOL-A")
    end
    for (k, name) in enumerate(("dx", "dpx", "dy", "dpy"))
        v = an.eta === nothing ? NaN : an.eta[k]
        _extref_compare!(rows, contract, :madx, fixture, "eta_$(name)_vs_beta0*$(uppercase(name))", v,
                         beta0 * _extref_float(ip, name), _EXTREF_TOL_B_REL, "TOL-B")
    end
    return nothing
end

"""
    _extref_ptc_rows!(rows, contract, tab::_ExtRefTable) -> Nothing

The PTC convention rows (benchmark B of `validation/twiss_ptc_benchmark.jl`),
on the committed `ptc_twiss_madx_<v>.tsv` alone. First the script's
`table_rows_present` row (TOL-C, tolerance 0): the count of the ten expected
fixtures S0, S0_pt, W1, U1, U2, K2, B4, B4K, G6_2.0MV, G6_0.2MV present in the
table against 10, the fixture column naming the missing ids (the generator's
abort path writes a 5D-only table). B0 witnesses: S0 (RE56 = 0, RE12 = C,
F RE F against the analytic 10 m drift) and S0_pt (RE12 = RE34 =
C/(1 + PT_start)), absolute at `_EXTREF_TOL_WITNESS` (times C or the expected
value where the script scales it), W1 (the cavity-strength law: the flipped
RE65 against strength k / PTC_BETA0^2 with strength = volt_MV 1e6 / 3.0e9,
k = 2 pi freq / c and PTC_BETA0 the beta0 of `reference_beta_gamma(3.0e9,
0.938272081358e9)`, PTC's internal proton mass, decision D19; 1e-10 absolute),
and the symplectic residual of F RE F of every icase=6 row (1e-12). A 5D row
whose `analyze` throws or yields fewer than two tunes is a failing
`analyze_threw` / `two_tunes_present` row (TOL-C), as in the script. B1, the icase=5 rows (layer `5d`: U1, U2, K2):
F RE F, the script's coasting completion, analyze with the default guard, the
completed map's symplectic residual (1e-12 abs), DISP1..4 against
physical.eta, BETA11/BETA22, ALFA11/ALFA22 and cos mu_1,2 at TOL-C, the modes
matched by eigenvalue over the permutations (a runner-up margin <= 1e-6 is a
failing `mode_matching_margin` row), and on the coupled row the BETA12/BETA21
index-order decision (j = plane, k = mode: BETA_jk = physical.beta[mode k,
plane j]). B2, the icase=6 rows (layer `6d`: B4, B4K, G6_2.0MV, G6_0.2MV):
F RE F analyzed with `nonsymplectic=:flag` and `longitudinal_mode = 2 pi |QS|`
as the script does, BETA_kk, ALFA_kk (ALFA33 with the PTC T-orientation sign
-1), cos mu_k for k = 1..3 and the off-diagonal BETA_pk in the (plane, mode)
order at TOL-C. Every twin row (an Octopus compile, including the two other
W1 rows), the recorded rows (6D DISP against graph[:, 2]) and the B4L ladder
stay in the script.
"""
function _extref_ptc_rows!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, tab::_ExtRefTable)
    # the script's guard against the generator's 5D-only abort table: fixture "table" when complete, else the missing ids
    missing_ids = [id for id in _EXTREF_PTC_EXPECTED_IDS if isempty(_extref_select(tab, "id", id))]
    _extref_compare!(rows, contract, :ptc, isempty(missing_ids) ? "table" : join(missing_ids, "+"), "table_rows_present",
                     Float64(length(_EXTREF_PTC_EXPECTED_IDS) - length(missing_ids)), Float64(length(_EXTREF_PTC_EXPECTED_IDS)),
                     0.0, "TOL-C"; rel=false)
    _extref_ptc_witness_rows!(rows, contract, tab)
    for row in _extref_select(tab, "layer", "5d")
        _extref_ptc_row_5d!(rows, contract, row)
    end
    for row in _extref_select(tab, "layer", "6d")
        _extref_ptc_row_6d!(rows, contract, row)
    end
    return nothing
end

const _EXTREF_PTC_TOL_SYMP = 1e-12
const _EXTREF_PTC_COUPLED_IDS = ("K2", "B4K")
# Sign applied to Octopus alpha[mode, plane k] before comparing with PTC's ALFA_kk: alfa_33 is odd under
# F = diag(1,1,1,1,-1,1) (PTC's T orientation of coordinate 5), alfa_11 and alfa_22 are even.
const _EXTREF_PTC_ALFA_SIGN = (1.0, 1.0, -1.0)

"The header beam and circumference of a PTC row."
_extref_ptc_beam(row::Dict{String,String}) =
    (beta0=_extref_float(row, "beta0_header"), gamma0=_extref_float(row, "gamma0_header"), C=_extref_float(row, "C"))

"F RE F of a PTC row (u = 0: the bare target)."
function _extref_ptc_converted(row::Dict{String,String})
    b = _extref_ptc_beam(row)
    return _extref_convert(:ptc, _extref_matrix(row, "RE"; suffix="_end"); b.beta0, b.gamma0, b.C, target=:bare)
end

"max |M' S M - S|."
function _extref_ptc_symplectic_residual(M::AbstractMatrix)
    S = _symplectic_form(size(M, 1))
    return maximum(abs, transpose(M) * S * M - S)
end

"""
Coasting completion of an icase=5 map (RE55 prints 0 there): the 4x4 block A
and column 6 (d) are trusted, row 6 is e6, row 5 follows from M' S M = S:
r = -A' S4 d, M55 = 1, M56 kept from the printed (flipped) map.
"""
function _extref_ptc_coasting_completion(RE::AbstractMatrix; m56::Real=RE[5, 6])
    A = Matrix{Float64}(RE[1:4, 1:4]); d = Vector{Float64}(RE[1:4, 6])
    S4 = _symplectic_form(4)
    M = zeros(6, 6)
    M[1:4, 1:4] = A; M[1:4, 6] = d
    M[5, 1:4] = -(A' * (S4 * d)); M[5, 5] = 1.0; M[5, 6] = Float64(m56)
    M[6, 6] = 1.0
    return M
end

"cos of a PTC tune printed in turns."
_extref_ptc_cos_turns(mu_turns::Real) = cos(2pi * mu_turns)

"""
Mode matching by eigenvalue over the permutations (the script's `match_modes`):
perm[k] = the Octopus mode matched to PTC mode k, chosen by the smallest total
|cos mu_oct - cos 2 pi MU_k|; margin = the runner-up permutation's mismatch.
"""
function _extref_ptc_match_modes(tunes::AbstractVector, mus_turns::AbstractVector)
    n = length(mus_turns)
    perms = n == 2 ? ([1, 2], [2, 1]) :
            n == 3 ? ([1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]) :
            throw(ArgumentError("_extref_ptc_match_modes: $(n) modes"))
    length(tunes) >= n || throw(ArgumentError("_extref_ptc_match_modes: $(length(tunes)) Octopus tunes for $(n) PTC modes"))
    mism(p) = sum(abs(cos(tunes[p[k]]) - _extref_ptc_cos_turns(mus_turns[k])) for k in 1:n)
    scores = sort([(mism(p), p) for p in perms]; by=first)
    return (perm=scores[1][2], mismatch=scores[1][1], margin=scores[2][1])
end

"""
The script's `analyze_converted` on a 6D row: `nonsymplectic=:flag` (PTC's
printed precision on the 6-cell ring exceeds the default row-ratio guard, which
would throw on G6_2.0MV) and `longitudinal_mode = mu_s`. Same reads as
`_extref_analyze`; a throw is reported as `nothing` (the caller fails the row).
"""
function _extref_ptc_analyze_6d(M::AbstractMatrix, mu_s::Real)
    an = TwissDispersionAnalysis(strict=false, scaling=:none, nonsymplectic=:flag, longitudinal_mode=Float64(mu_s))
    result = try
        analyze(an, Matrix{Float64}(M))
    catch
        return nothing
    end
    form = 0
    if is_determined(result.transverse)
        form = something(_extref_dval(determined_value(result.transverse).preferred_form), 0)
    end
    ph = result.physical
    return (result=result, tunes=copy(ph.tunes), form=form, beta=_extref_dval(ph.beta), alpha=_extref_dval(ph.alpha),
            eta=_extref_dval(ph.eta), graph=_extref_dval(ph.graph), h=_extref_dval(ph.h))
end

"The B0 witnesses reproducible from the table: S0, S0_pt, the W1 cavity law and the symplectic residual after F of every icase=6 row."
function _extref_ptc_witness_rows!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, tab::_ExtRefTable)
    s0s = _extref_select(tab, "id", "S0")
    if length(s0s) == 1
        s0 = first(s0s); b = _extref_ptc_beam(s0); RE = _extref_matrix(s0, "RE"; suffix="_end")
        _extref_compare!(rows, contract, :ptc, "S0", "RE56_zero", RE[5, 6], 0.0, _EXTREF_TOL_WITNESS, "witness"; rel=false)
        _extref_compare!(rows, contract, :ptc, "S0", "RE12_is_L", RE[1, 2], b.C, _EXTREF_TOL_WITNESS * b.C, "witness"; rel=false)
        M = _extref_ptc_converted(s0)
        D = Matrix{Float64}(I, 6, 6); D[1, 2] = b.C; D[3, 4] = b.C   # the analytic drift for :ptc (M56 = 0, time=false), F D F = D
        _extref_compare!(rows, contract, :ptc, "S0", "converted_vs_analytic_drift_max_entry", maximum(abs, M - D), 0.0,
                         _EXTREF_TOL_WITNESS, "witness"; rel=false)
    end
    s0ps = _extref_select(tab, "id", "S0_pt")
    if length(s0ps) == 1
        s0p = first(s0ps); bp = _extref_ptc_beam(s0p); REp = _extref_matrix(s0p, "RE"; suffix="_end")
        exp12 = bp.C / (1 + _extref_float(s0p, "PT_start"))
        _extref_compare!(rows, contract, :ptc, "S0_pt", "RE12_is_L_over_1+delta", REp[1, 2], exp12, _EXTREF_TOL_WITNESS * exp12, "witness"; rel=false)
        _extref_compare!(rows, contract, :ptc, "S0_pt", "RE34_is_L_over_1+delta", REp[3, 4], exp12, _EXTREF_TOL_WITNESS * exp12, "witness"; rel=false)
    end
    w1s = _extref_select(tab, "id", "W1")
    if length(w1s) == 1
        # stage 8 W1 witness (D19): (F RE F)[6,5] = strength k / beta0^2 at PTC's effective beam, V = strength E_total
        w1 = first(w1s); Mw = _extref_ptc_converted(w1)
        k = 2pi * _extref_float(w1, "freq_MHz") * 1e6 / CLIGHT
        strength = _extref_float(w1, "volt_MV") * 1e6 / _EXTREF_BENCH_E_TOTAL_EV
        ptc_beta0, _ = reference_beta_gamma(_EXTREF_BENCH_E_TOTAL_EV, _EXTREF_PTC_INTERNAL_PROTON_MASS_GEV * 1e9)
        _extref_compare!(rows, contract, :ptc, "W1", "M65_flipped_vs_strength_k_over_PTC_BETA0^2", Mw[6, 5],
                         strength * k / ptc_beta0^2, _EXTREF_TOL_W1, "witness"; rel=false)
    end
    for r in tab.rows
        _extref_float(r, "icase") == 6 || continue
        _extref_compare!(rows, contract, :ptc, r["id"], "symplectic_residual_after_F", _extref_ptc_symplectic_residual(_extref_ptc_converted(r)),
                         0.0, _EXTREF_PTC_TOL_SYMP, "witness"; rel=false)
    end
    return nothing
end

"""
The script's B3 decision on a coupled row: BETA12, BETA21 read both as
(mode, plane) and as (plane, mode) against beta[mode, plane]; the reading
within TOL-C is gated when the other misses by more than 1e-3 (the table
decides j = plane, k = mode); an undecided row produces no gated row.
jx, jy = the Octopus modes matched to PTC modes 1, 2.
"""
function _extref_ptc_index_order_rows!(rows, contract, id, row, bm, jx, jy)
    b12 = _extref_float(row, "BETA12_start"); b21 = _extref_float(row, "BETA21_start")
    miss_mp = max(abs(b12 - bm[jx, 2]) / max(1.0, abs(b12)), abs(b21 - bm[jy, 1]) / max(1.0, abs(b21)))
    miss_pm = max(abs(b12 - bm[jy, 1]) / max(1.0, abs(b12)), abs(b21 - bm[jx, 2]) / max(1.0, abs(b21)))
    if miss_mp <= _EXTREF_TOL_C_REL && miss_pm > 1e-3
        _extref_compare!(rows, contract, :ptc, id, "BETA12", bm[jx, 2], b12, _EXTREF_TOL_C_REL, "TOL-C")
        _extref_compare!(rows, contract, :ptc, id, "BETA21", bm[jy, 1], b21, _EXTREF_TOL_C_REL, "TOL-C")
    elseif miss_pm <= _EXTREF_TOL_C_REL && miss_mp > 1e-3
        _extref_compare!(rows, contract, :ptc, id, "BETA12", bm[jy, 1], b12, _EXTREF_TOL_C_REL, "TOL-C")
        _extref_compare!(rows, contract, :ptc, id, "BETA21", bm[jx, 2], b21, _EXTREF_TOL_C_REL, "TOL-C")
    end
    return nothing
end

"B1: one icase=5 row (F RE F, coasting completion, analyze with the default guard)."
function _extref_ptc_row_5d!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, row::Dict{String,String})
    id = row["id"]
    M = _extref_ptc_coasting_completion(_extref_ptc_converted(row))
    _extref_compare!(rows, contract, :ptc, id, "symplectic_residual_completed_map", _extref_ptc_symplectic_residual(M), 0.0,
                     _EXTREF_PTC_TOL_SYMP, "TOL-C"; rel=false)
    a = try
        _extref_analyze(M)
    catch
        _extref_compare!(rows, contract, :ptc, id, "analyze_threw", 1.0, 0.0, 0.0, "TOL-C"; rel=false)
        return nothing
    end
    if a.eta === nothing || a.beta === nothing || a.alpha === nothing
        _extref_compare!(rows, contract, :ptc, id, "analysis_determined", 0.0, 1.0, 0.0, "TOL-C"; rel=false)
        return nothing
    end
    if length(a.tunes) < 2
        _extref_compare!(rows, contract, :ptc, id, "two_tunes_present", Float64(length(a.tunes)), 2.0, 0.0, "TOL-C"; rel=false)
        return nothing
    end
    for k in 1:4
        _extref_compare!(rows, contract, :ptc, id, "DISP$(k)_vs_physical.eta[$(k)]", a.eta[k], _extref_float(row, "DISP$(k)_start"), _EXTREF_TOL_C_REL, "TOL-C")
    end
    mus = [_extref_float(row, "MU1_end"), _extref_float(row, "MU2_end")]
    mm = _extref_ptc_match_modes(a.tunes, mus)
    if mm.margin <= 1e-6
        _extref_compare!(rows, contract, :ptc, id, "mode_matching_margin", mm.margin, 1.0, 0.0, "TOL-C"; rel=false)
        return nothing
    end
    jx, jy = mm.perm
    _extref_compare!(rows, contract, :ptc, id, "BETA11", a.beta[jx, 1], _extref_float(row, "BETA11_start"), _EXTREF_TOL_C_REL, "TOL-C")
    _extref_compare!(rows, contract, :ptc, id, "BETA22", a.beta[jy, 2], _extref_float(row, "BETA22_start"), _EXTREF_TOL_C_REL, "TOL-C")
    _extref_compare!(rows, contract, :ptc, id, "ALFA11", a.alpha[jx, 1], _extref_float(row, "ALFA11_start"), _EXTREF_TOL_C_REL, "TOL-C")
    _extref_compare!(rows, contract, :ptc, id, "ALFA22", a.alpha[jy, 2], _extref_float(row, "ALFA22_start"), _EXTREF_TOL_C_REL, "TOL-C")
    _extref_compare!(rows, contract, :ptc, id, "cos_mu1", cos(a.tunes[jx]), _extref_ptc_cos_turns(mus[1]), _EXTREF_TOL_C_COS, "TOL-C"; rel=false)
    _extref_compare!(rows, contract, :ptc, id, "cos_mu2", cos(a.tunes[jy]), _extref_ptc_cos_turns(mus[2]), _EXTREF_TOL_C_COS, "TOL-C"; rel=false)
    if id in _EXTREF_PTC_COUPLED_IDS
        _extref_compare!(rows, contract, :ptc, id, "presented_edwards_teng_form_is_1", a.form, 1.0, 0.0, "witness"; rel=false)
        _extref_ptc_index_order_rows!(rows, contract, id, row, a.beta, jx, jy)
    end
    return nothing
end

"B2: one icase=6 row (F RE F, nonsymplectic=:flag, longitudinal_mode = 2 pi |QS| from PTC)."
function _extref_ptc_row_6d!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract, row::Dict{String,String})
    id = row["id"]
    M = _extref_ptc_converted(row)
    qs = _extref_float(row, "QS"); mu_s = 2pi * abs(qs)
    a = _extref_ptc_analyze_6d(M, mu_s)
    if a === nothing || a.beta === nothing || a.alpha === nothing || size(a.beta, 1) != 3
        _extref_compare!(rows, contract, :ptc, id, "analysis_determined_6d", 0.0, 1.0, 0.0, "TOL-C"; rel=false)
        return nothing
    end
    mus = [_extref_float(row, "MU1_end"), _extref_float(row, "MU2_end"), qs]
    mm = _extref_ptc_match_modes(a.tunes, mus)
    if mm.margin <= 1e-6
        _extref_compare!(rows, contract, :ptc, id, "mode_matching_margin", mm.margin, 1.0, 0.0, "TOL-C"; rel=false)
        return nothing
    end
    for k in 1:3
        j = mm.perm[k]; s_k = _EXTREF_PTC_ALFA_SIGN[k]
        _extref_compare!(rows, contract, :ptc, id, "BETA$(k)$(k)", a.beta[j, k], _extref_float(row, "BETA$(k)$(k)_start"), _EXTREF_TOL_C_REL, "TOL-C")
        _extref_compare!(rows, contract, :ptc, id, "ALFA$(k)$(k)" * (s_k < 0 ? "_PTC_T_convention_sign" : ""), s_k * a.alpha[j, k],
                         _extref_float(row, "ALFA$(k)$(k)_start"), _EXTREF_TOL_C_REL, "TOL-C")
        _extref_compare!(rows, contract, :ptc, id, "cos_mu$(k)", cos(a.tunes[j]), _extref_ptc_cos_turns(mus[k]), _EXTREF_TOL_C_COS, "TOL-C"; rel=false)
    end
    if id in _EXTREF_PTC_COUPLED_IDS
        _extref_compare!(rows, contract, :ptc, id, "presented_edwards_teng_form_is_1", a.form, 1.0, 0.0, "witness"; rel=false)
        _extref_ptc_index_order_rows!(rows, contract, id, row, a.beta, mm.perm[1], mm.perm[2])
    end
    for p in 1:3, k in 1:3
        p == k && continue
        (p, k) in ((1, 2), (2, 1)) && id in _EXTREF_PTC_COUPLED_IDS && continue   # gated by the index-order decision
        _extref_compare!(rows, contract, :ptc, id, "BETA$(p)$(k)_as_(plane,mode)", a.beta[mm.perm[k], p],
                         _extref_float(row, "BETA$(p)$(k)_start"), _EXTREF_TOL_C_REL, "TOL-C")
    end
    return nothing
end

"""
    _extref_xtrack_rows!(rows, contract, tab::_ExtRefLongTable, maps::_ExtRefTable) -> Nothing

The xtrack convention rows (benchmark C of `validation/twiss_xsuite_benchmark.jl`):
layer C1 (xtrack's W, lattice functions and dispersion computed on the Octopus
map itself, read from the maps table at the row's compile: TOL-A on the
transverse quantities, TOL-D on anything touching rows or columns 5-6, TOL-F on
the degenerate rolled cells, the script's form-1/form-2 and mode-matching rules)
and layer C3 (the T6 line6d rows: the longitudinal block of the get_R_matrix
map at the task target against the Octopus task map, then `Line.twiss(method='6d')`
outputs against analyze of that task map, TOL-D). Layer C2 (lattice
twins and the nst ladder) stays in the script.

Mirrored one for one with the script's gated `compare_row` calls on committed
numbers: the D8 rows are analyzed as the 4x4 block of their maps-table row
(stored as blockdiag(M4, I2)); the manufactured dense maps widen TOL-A to
10 kappa(U)^2 eps_mach (class `TOL-A-cond`) as the script does; Rd_1e-6 and
every row the script only records stay out. The script's `assert_row` calls are
rows of class `assert` (1 against 1 at tolerance 0): on every gated C1 fixture
the analyze status not `:failed` and the matched modes distinct, the presented
Edwards-Teng form 1 on K1, K2, D6_1..3, D8_1..3, and on every 6x6 fixture the
coasting structure absent (bunched) or present (coasting); on T6 the status,
three distinct modes and the coasting structure absent. Its `witness_row`
calls are rows of class `witness`: the T6 C against the maps-table C (1e-12
absolute) and the longitudinal block of the converted get_R_matrix map
against the Octopus task map (1e-7 relative).
"""
function _extref_xtrack_rows!(rows::Vector{_ExtRefRow}, contract::TwissExternalReferenceContract,
                              tab::_ExtRefLongTable, maps::_ExtRefTable)
    _extref_xtrack_c1!(rows, contract, tab, maps)
    _extref_xtrack_c3!(rows, contract, tab, maps)
    return nothing
end

# fixture id, maps-table compile, matrix dimension (the script's C1_FIXTURES)
const _EXTREF_XT_C1_FIXTURES = (("U1", "bare", 6), ("U2", "bare", 6), ("K1", "bare", 6), ("K2", "bare", 6),
                                ("R_0.1", "bare", 6), ("R_pi4", "bare", 6), ("Rd_1e-3", "bare", 6), ("Rd_1e-6", "bare", 6),
                                ("B4", "bare", 6), ("B5", "bare", 6), ("T6", "task", 6),
                                ("D6_1", "matrix", 6), ("D6_2", "matrix", 6), ("D6_3", "matrix", 6),
                                ("D8_1", "matrix", 4), ("D8_2", "matrix", 4), ("D8_3", "matrix", 4))
const _EXTREF_XT_ROLLED = ("R_0.1", "R_pi4")
const _EXTREF_XT_DETUNED = ("Rd_1e-3", "Rd_1e-6")
const _EXTREF_XT_COUPLED_C1 = ("K1", "K2", "D6_1", "D6_2", "D6_3", "D8_1", "D8_2", "D8_3")   # the presented ET form is asserted 1 here
# xtrack's Mais-Ripken names by (mode, plane): mode 1 = (betx, bety1), mode 2 = (betx2, bety)
const _EXTREF_XT_MR_NAMES = Dict((1, 1) => ("betx", "alfx", "gamx"), (1, 2) => ("bety1", "alfy1", "gamy1"),
                                 (2, 1) => ("betx2", "alfx2", "gamx2"), (2, 2) => ("bety", "alfy", "gamy"))
const _EXTREF_XT_ET_NAMES = Dict(1 => ("betx_edw_teng", "alfx_edw_teng"), 2 => ("bety_edw_teng", "alfy_edw_teng"))
const _EXTREF_XT_DISP_NAMES = ("dx", "dpx", "dy", "dpy")

"xtrack's eigenvalue of mode j (the first of its pair) as a complex number."
_extref_xtrack_eig(tab::_ExtRefLongTable, layer, fixture, compile, j::Integer) =
    complex(_extref_cell(tab, layer, fixture, compile, "eig$(2j-1)_re"), _extref_cell(tab, layer, fixture, compile, "eig$(2j-1)_im"))

"Index of the Octopus mode whose cos(tune) is closest to the real part of the unit eigenvalue (by eigenvalue, never by label)."
function _extref_xtrack_match(tunes::AbstractVector, lam::Complex)
    isempty(tunes) && return 0
    return _extref_match_mode(tunes, real(lam) / abs(lam))
end

"The rank-2 projector of mode j of a normalizer: V V' with V = U[:, 2j-1:2j]."
_extref_xtrack_projector(U::AbstractMatrix, j::Integer) = (V = U[:, 2j-1:2j]; V * V')
"max |A_ij|."
_extref_xtrack_maxabs(A) = maximum(abs, A)

"cos mu and sin mu of Octopus mode k against xtrack's eigenvalue lam (absolute tolerance); k = 0 fails both rows."
function _extref_xtrack_tune_rows!(rows, contract, fixture, tunes, k::Integer, lam::Complex, label::AbstractString, tol::Real, class::AbstractString)
    c = real(lam) / abs(lam); s = imag(lam) / abs(lam)
    oc = k == 0 ? NaN : cos(tunes[k]); os = k == 0 ? NaN : sin(tunes[k])
    _extref_compare!(rows, contract, :xtrack, fixture, "cos_mu_$(label)", oc, c, tol, class; rel=false)
    _extref_compare!(rows, contract, :xtrack, fixture, "sin_mu_$(label)", os, s, tol, class; rel=false)
    return nothing
end

"An assertion of the script as a row: 1 against 1 at tolerance 0 (class `assert`)."
_extref_xtrack_assert!(rows, contract, fixture, name::AbstractString, ok::Bool) =
    _extref_compare!(rows, contract, :xtrack, fixture, name, ok ? 1.0 : 0.0, 1.0, 0.0, "assert"; rel=false)

"The rolled cells in C1: label-free cos mu of the 4x4 block against xtrack's two modes and the eigen modulus (TOL-F)."
function _extref_xtrack_c1_rolled!(rows, contract, tab, fixture, compile, M::AbstractMatrix)
    lam4 = eigvals(M[1:4, 1:4])
    coss = sort(unique(round.(real.(lam4) ./ abs.(lam4); digits=14)))
    for j in 1:2
        lam = _extref_xtrack_eig(tab, "C1", fixture, compile, j)
        c = real(lam) / abs(lam)
        k = argmin(abs.(coss .- c))
        _extref_compare!(rows, contract, :xtrack, fixture, "cos_mu_mode$(j)_vs_4x4_block_eigenvalue", coss[k], c, _EXTREF_TOL_F_ABS, "TOL-F"; rel=false)
        _extref_compare!(rows, contract, :xtrack, fixture, "eigen_modulus_mode$(j)", abs(lam), 1.0, _EXTREF_TOL_F_ABS, "TOL-F"; rel=false)
    end
    return nothing
end

"""
Transverse rows of one C1 fixture: cos/sin mu per xtrack mode (matched by
eigenvalue), the Mais-Ripken beta/alpha/gamma by (matched mode, plane), the
Edwards-Teng mode functions and lambda (gated on 4D/coasting maps only, the
form selected by xtrack's own (T15) lambda formula on Octopus's Mais-Ripken
functions), the rank-2 normalizer invariant. Returns the Octopus mode index of
each xtrack mode.
"""
function _extref_xtrack_c1_transverse!(rows, contract, tab, fixture, compile, an, W::AbstractMatrix, nmodes::Int,
                                       tol_rel, tol_abs, class)
    rel = class != "TOL-F"
    # :degraded is accepted (the values stay Determined and are gated below), as in the script
    _extref_xtrack_assert!(rows, contract, fixture, "analyze_status_not_failed", an.status !== :failed)
    ks = zeros(Int, nmodes)
    for j in 1:nmodes
        lam = _extref_xtrack_eig(tab, "C1", fixture, compile, j)
        ks[j] = _extref_xtrack_match(an.tunes, lam)
        _extref_xtrack_tune_rows!(rows, contract, fixture, an.tunes, ks[j], lam, "mode$(j)", tol_abs, class)
    end
    _extref_xtrack_assert!(rows, contract, fixture, "modes_matched_distinct", all(ks .> 0) && length(unique(ks)) == nmodes)
    fixture in _EXTREF_XT_COUPLED_C1 && _extref_xtrack_assert!(rows, contract, fixture, "presented_ET_form_is_1", an.form == 1)
    for j in 1:2, plane in 1:2
        names = _EXTREF_XT_MR_NAMES[(j, plane)]
        for (field, name) in zip((:beta, :alpha, :gamma), names)
            A = getfield(an, field)
            v = (A === nothing || ks[j] == 0) ? NaN : A[ks[j], plane]
            _extref_compare!(rows, contract, :xtrack, fixture, "MR_$(name)", v, _extref_cell(tab, "C1", fixture, compile, name), tol_rel, class; rel=rel)
        end
    end
    if nmodes == 2
        g = _extref_cell(tab, "C1", fixture, compile, "g_edw_teng")
        k1 = ks[1]
        lam_int = (k1 == 0 || any(A -> A === nothing, (an.beta, an.alpha, an.gamma))) ? NaN :
                  (an.beta[k1, 1] * an.gamma[k1, 1] - an.alpha[k1, 1]^2)^0.25
        use2 = isfinite(an.lambda2) && isfinite(lam_int) && abs(an.lambda2 - lam_int) < abs(an.lambda - lam_int)
        tw_et = use2 ? an.twiss2 : an.twiss
        lam_et = use2 ? an.lambda2 : an.lambda
        for j in 1:2
            bname, aname = _EXTREF_XT_ET_NAMES[j]
            tw = (tw_et === nothing || ks[j] == 0 || ks[j] > length(tw_et)) ? nothing : tw_et[ks[j]]
            for (name, v) in ((bname, tw === nothing ? NaN : tw.beta), (aname, tw === nothing ? NaN : tw.alpha))
                _extref_compare!(rows, contract, :xtrack, fixture, "ET_$(name)", v, _extref_cell(tab, "C1", fixture, compile, name), tol_rel, class; rel=rel)
            end
        end
        _extref_compare!(rows, contract, :xtrack, fixture, "ET_lambda_vs_g_edw_teng", lam_et, g, tol_rel, class; rel=rel)
    end
    if an.U === nothing
        _extref_compare!(rows, contract, :xtrack, fixture, "rank2_projector_maxabs_rel", NaN, 0.0, tol_rel, class; rel=false)
    else
        d = size(an.U, 1)
        for j in 1:nmodes
            P = _extref_xtrack_projector(W[1:d, 1:d], j)
            Q = ks[j] == 0 ? fill(NaN, d, d) : _extref_xtrack_projector(an.U, ks[j])
            _extref_compare!(rows, contract, :xtrack, fixture, "rank2_projector_mode$(j)_maxabs_rel",
                             _extref_xtrack_maxabs(P - Q) / _extref_xtrack_maxabs(Q), 0.0, tol_rel, class; rel=false)
        end
    end
    return ks
end

"""
Dispersion rows of one C1 fixture. Bunched 6x6 map: dx..dpy against
physical.graph[:,2], dx_zeta.. against physical.zeta, physical.h against
det(U_ls) of xtrack's own normalizer, physical.eta against h * dx. Coasting 6x6
map: physical.eta against xtrack's 4d route dx_4d.., physical.zeta against
dx_zeta_4d.. (0 against 0).
"""
function _extref_xtrack_c1_dispersion!(rows, contract, tab, fixture, compile, an, bunched::Bool, W::AbstractMatrix, tol_rel, class)
    rel = class != "TOL-F"
    cell(q) = _extref_cell(tab, "C1", fixture, compile, q)
    if bunched
        G = an.graph
        for (r, name) in enumerate(_EXTREF_XT_DISP_NAMES)
            _extref_compare!(rows, contract, :xtrack, fixture, "$(name)_vs_graph[:,2]", G === nothing ? NaN : G[r, 2], cell(name), tol_rel, class; rel=rel)
        end
        for (r, name) in enumerate(_EXTREF_XT_DISP_NAMES)
            _extref_compare!(rows, contract, :xtrack, fixture, "$(name)_zeta_vs_physical_zeta", an.zeta === nothing ? NaN : an.zeta[r], cell("$(name)_zeta"), tol_rel, class; rel=rel)
        end
        h = an.h === nothing ? NaN : an.h
        _extref_compare!(rows, contract, :xtrack, fixture, "physical_h_vs_det(U_ls)", h, W[5, 5] * W[6, 6] - W[5, 6] * W[6, 5], tol_rel, class; rel=rel)
        for (r, name) in enumerate(_EXTREF_XT_DISP_NAMES)
            eta_r = an.eta === nothing ? NaN : an.eta[r]
            _extref_compare!(rows, contract, :xtrack, fixture, "physical_eta_vs_h*$(name)", eta_r, h * cell(name), tol_rel, class; rel=rel)
        end
    else
        for (r, name) in enumerate(_EXTREF_XT_DISP_NAMES)
            _extref_compare!(rows, contract, :xtrack, fixture, "eta_$(name)_vs_xtrack_4d_route_$(name)_4d", an.eta === nothing ? NaN : an.eta[r], cell("$(name)_4d"), tol_rel, class; rel=rel)
        end
        for (r, name) in enumerate(_EXTREF_XT_DISP_NAMES)
            _extref_compare!(rows, contract, :xtrack, fixture, "zeta_$(name)_vs_xtrack_$(name)_zeta_4d(0_vs_0)", an.zeta === nothing ? NaN : an.zeta[r], cell("$(name)_zeta_4d"), tol_rel, class; rel=rel)
        end
    end
    return nothing
end

"Whether `analyze` found the coasting structure (the script's `coasting` read: `result.coasting` present and holding)."
_extref_xtrack_coasting(an) = an.result.coasting !== nothing && an.result.coasting.holds

"Layer C1: every fixture of the script's C1 list on its committed Octopus map."
function _extref_xtrack_c1!(rows, contract, tab::_ExtRefLongTable, maps::_ExtRefTable)
    for (fixture, compile, dim) in _EXTREF_XT_C1_FIXTURES
        fixture == "Rd_1e-6" && continue      # recorded only in the script (the (E7) gate refuses the frame)
        M6 = _extref_octopus_map(maps, fixture, compile).M
        M = dim == 4 ? M6[1:4, 1:4] : M6
        only4d = _extref_cell(tab, "C1", fixture, compile, "only_4d_block") == 1.0
        W = _extref_long_matrix(tab, "C1", fixture, compile, "W")
        bunched = dim == 6 && !only4d
        an = bunched ? _extref_analyze(M; mu_s=abs(_extref_cell(tab, "C1", fixture, compile, "mu3"))) : _extref_analyze(M)
        if fixture in _EXTREF_XT_ROLLED
            _extref_xtrack_c1_rolled!(rows, contract, tab, fixture, compile, M)
            continue
        end
        detuned = fixture in _EXTREF_XT_DETUNED
        tol_rel = detuned ? _EXTREF_TOL_F_ABS : _EXTREF_TOL_A_REL
        tol_abs = detuned ? _EXTREF_TOL_F_ABS : _EXTREF_TOL_A_ABS
        class = detuned ? "TOL-F" : "TOL-A"
        # the manufactured dense maps (D6_*, D8_*): TOL-A widened to 10 kappa(U)^2 eps_mach when that exceeds it
        kappa = an.U === nothing ? NaN : cond(an.U)
        if startswith(fixture, "D") && !detuned && isfinite(kappa) && 10 * kappa^2 * eps() > tol_rel
            tol_rel = 10 * kappa^2 * eps()
            class = "TOL-A-cond"
        end
        nmodes = only4d ? 2 : 3
        _extref_xtrack_c1_transverse!(rows, contract, tab, fixture, compile, an, W, nmodes, tol_rel, tol_abs, class)
        if dim == 6
            _extref_xtrack_assert!(rows, contract, fixture, "coasting_structure_$(bunched ? "absent" : "present")",
                                   _extref_xtrack_coasting(an) == !bunched)
            _extref_xtrack_c1_dispersion!(rows, contract, tab, fixture, compile, an, bunched, W, tol_rel, class)
        end
    end
    return nothing
end

"""
Layer C3 (T6, line6d): the longitudinal 2x2 witness of the converted
get_R_matrix map against the committed Octopus task map (TOL-D relative; the
converted map is the finite-difference one, not symplectic to `analyze`'s
gate, so, as in the script, the map analyzed is the Octopus task map the
witness ties to it), then analyze (`longitudinal_mode` = 2 pi |tw6_qs|) against the
`Line.twiss(method='6d')` outputs: Mais-Ripken betx, bety, alfx, alfy by matched
mode and physical.eta against h * tw6_dx.. at TOL-D.
"""
function _extref_xtrack_c3!(rows, contract, tab::_ExtRefLongTable, maps::_ExtRefTable)
    f = "T6"
    cell(q) = _extref_cell(tab, "C3", f, "line6d", q)
    R = _extref_long_matrix(tab, "C3", f, "line6d", "r")
    oct = _extref_octopus_map(maps, f, "task")
    _extref_compare!(rows, contract, :xtrack, f, "T6_C_vs_maps_table_C", cell("C"), oct.C, _EXTREF_TOL_WITNESS, "witness"; rel=false)
    Mconv = _extref_convert(:xtrack, R; beta0=oct.beta0, gamma0=oct.gamma0, C=cell("C"), target=:task)
    for (i, j) in ((5, 5), (5, 6), (6, 5), (6, 6))
        _extref_compare!(rows, contract, :xtrack, f, "T6_longitudinal_r$(i)$(j)_vs_task_m$(i)$(j)(TOL-D_rel)", Mconv[i, j], oct.M[i, j], _EXTREF_TOL_D_REL, "witness"; rel=true)
    end
    an = _extref_analyze(oct.M; mu_s=2pi * abs(cell("tw6_qs")))
    lam1 = complex(cell("tw6_cos_mux"), cell("tw6_sin_mux")); lam2 = complex(cell("tw6_cos_muy"), cell("tw6_sin_muy"))
    lam3 = complex(cos(2pi * cell("tw6_qs")), sin(2pi * cell("tw6_qs")))
    k1 = _extref_xtrack_match(an.tunes, lam1); k2 = _extref_xtrack_match(an.tunes, lam2); k3 = _extref_xtrack_match(an.tunes, lam3)
    _extref_xtrack_assert!(rows, contract, f, "T6_analyze_status_not_failed", an.status !== :failed)
    _extref_xtrack_assert!(rows, contract, f, "T6_three_modes_matched_distinct", k1 > 0 && k2 > 0 && k3 > 0 && length(unique((k1, k2, k3))) == 3)
    _extref_xtrack_assert!(rows, contract, f, "T6_coasting_structure_absent", !_extref_xtrack_coasting(an))
    row(q, o, e) = _extref_compare!(rows, contract, :xtrack, f, q, o, e, _EXTREF_TOL_D_REL, "TOL-D"; rel=true)
    if an.beta !== nothing && an.alpha !== nothing && k1 > 0 && k2 > 0
        row("MR_betx_vs_tw6_betx", an.beta[k1, 1], cell("tw6_betx"))
        row("MR_bety_vs_tw6_bety", an.beta[k2, 2], cell("tw6_bety"))
        row("MR_alfx_vs_tw6_alfx", an.alpha[k1, 1], cell("tw6_alfx"))
        row("MR_alfy_vs_tw6_alfy", an.alpha[k2, 2], cell("tw6_alfy"))
    else
        row("MR_betx_vs_tw6_betx", NaN, cell("tw6_betx"))
    end
    h = an.h === nothing ? NaN : an.h
    for (r, name) in enumerate(_EXTREF_XT_DISP_NAMES)
        row("physical_eta_vs_h*tw6_$(name)", an.eta === nothing ? NaN : an.eta[r], h * cell("tw6_$(name)"))
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Folding the rows and validate.

"Folds the rows into a ContractResult: counts per code, worst ratio per class, the failure texts, the no-row-fails rule."
function _extref_result(rows::Vector{_ExtRefRow}, paths::Dict{Symbol,String})
    metrics = Dict{Symbol,Any}()
    metrics[:rows] = length(rows)
    metrics[:failed] = count(r -> !r.passed, rows)
    for code in (:madx, :ptc, :xtrack)
        metrics[Symbol("rows_", code)] = count(r -> r.code === code, rows)
        metrics[Symbol("failed_", code)] = count(r -> r.code === code && !r.passed, rows)
    end
    worst = -Inf; worst_row = "none"
    for r in rows
        ratio = r.bound > 0 ? r.diff / r.bound : (r.diff == 0 ? 0.0 : Inf)
        key = Symbol("worst_", replace(r.class, "-" => "_"))
        metrics[key] = max(get(metrics, key, 0.0), ratio)
        if ratio > worst
            worst = ratio; worst_row = string(r.code, " ", r.fixture, " ", r.quantity)
        end
    end
    metrics[:worst_ratio] = worst == -Inf ? Inf : worst
    metrics[:worst_row] = worst_row
    for (code, p) in paths
        metrics[Symbol("table_", code)] = p
    end
    failures = [string(r.code, " ", r.fixture, " ", r.quantity, ": |", r.octopus, " - ", r.external, "| = ", r.diff,
                       " > ", r.bound, " (", r.class, ")") for r in rows if !r.passed]
    empty_codes = [code for code in (:madx, :ptc, :xtrack) if metrics[Symbol("rows_", code)] == 0]
    for code in empty_codes
        push!(failures, "no $(code) row was compared (a silent pass is not a pass)")
    end
    metrics[:failure_texts] = failures
    passed = isempty(failures)
    message = passed ?
        "external twiss references certified: $(metrics[:rows]) rows (madx $(metrics[:rows_madx]), ptc $(metrics[:rows_ptc]), xtrack $(metrics[:rows_xtrack])), worst ratio $(metrics[:worst_ratio]) ($(worst_row))" :
        "TwissExternalReferenceContract failed ($(length(failures)) findings): " * first(failures)
    return ContractResult(passed, message; residual=metrics[:worst_ratio], metrics=metrics)
end

"""
    validate(contract::TwissExternalReferenceContract) -> ContractResult

Locates the four tables (or returns `:skipped` naming the missing table and
its generator), reads them, runs the three code sections and folds the rows.
Takes no keywords; any keyword is an `ArgumentError`.
"""
function validate(contract::TwissExternalReferenceContract; kwargs...)
    isempty(kwargs) ||
        throw(ArgumentError("TwissExternalReferenceContract: unknown keyword(s) $(join(string.(keys(kwargs)), ", ")); validate takes no keywords"))
    dir = _extref_reference_dir(contract)
    paths = Dict{Symbol,String}()
    missing_tables = String[]
    for (code, spec) in pairs(_EXTREF_TABLES)
        p = _extref_table_path(dir, spec.prefix)
        p === nothing ? push!(missing_tables, "$(spec.prefix)*.tsv (written by $(spec.generator))") : (paths[code] = p)
    end
    if !isempty(missing_tables)
        return ContractResult(:skipped,
            "TwissExternalReferenceContract skipped: no table under $(dir) for " * join(missing_tables, "; ");
            metrics=Dict{Symbol,Any}(:reference_dir => dir, :missing => missing_tables))
    end
    madx = _extref_read_wide(paths[:madx])
    ptc = _extref_read_wide(paths[:ptc])
    maps = _extref_read_wide(paths[:maps])
    xt = _extref_read_long(paths[:xtrack])
    rows = _ExtRefRow[]
    _extref_madx_rows!(rows, contract, madx)
    _extref_ptc_rows!(rows, contract, ptc)
    _extref_xtrack_rows!(rows, contract, xt, maps)
    return _extref_result(rows, paths)
end
