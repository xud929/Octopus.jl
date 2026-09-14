# Twiss / dispersion acceptance windows: the stage 4a measurement driver of the Twiss/dispersion campaign
# (Part D1, 2026-09-12), tracked 2026-09-14 so that the measurement behind every acceptance multiplier of
# src/analysis/dispersion_routes.jl is reproducible from the tree. Package mode, from the tree under test:
#   julia --startup-file=no --project=. --threads=4 validation/twiss_dispersion_acceptance_windows.jl [oracle_maps.tsv] [oracle_reference.tsv] [out.md]
# Defaults: validation/reference/twiss_oracle_maps.tsv, validation/reference/twiss_oracle_reference.tsv,
# result/twiss_dispersion_acceptance_windows.md. Sections of the table:
# (1) the ORACLE AGREEMENT TABLE: every route of `_dispersion_routes` on the 39 oracle maps of the
#     canonical-dispersion note against the note's own reference values (oracle_reference.tsv, dumped
#     once by dump_oracle_reference.py driving verify_dispersion.py's helpers) at the design's 2e-10;
# (2) every PROVISIONAL constant's window by the one-tenth / ten rule, fixture names DERIVED from the data;
# (3) the rejected side of every `c eps kappa` check family of the stage 4a testsets;
# (4) the paper cross-checks (trial-011 crab eta_+, the N15 / N17 controls, the DBA coasting eta).
# The fixture builders are the suite's own `_st3_` / `_st4_` helpers, extracted from test/runtests.jl
# by NAME at run time (never copied by hand); nothing here is a test lane.
using Octopus, LinearAlgebra, Random, Printf
using Octopus: determined_value, is_determined
const REPO = normpath(joinpath(@__DIR__, ".."))
const ORACLE_TSV = length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "reference", "twiss_oracle_maps.tsv")
const REF_TSV = length(ARGS) >= 2 ? ARGS[2] : joinpath(@__DIR__, "reference", "twiss_oracle_reference.tsv")
const OUT_MD = length(ARGS) >= 3 ? ARGS[3] : joinpath(REPO, "result", "twiss_dispersion_acceptance_windows.md")
relp(p) = startswith(abspath(p), REPO) ? relpath(abspath(p), REPO) : p   # header paths relative to the repository root, the same on every checkout
const EPS = eps(Float64)
e2(x) = x isa Bool ? string(x) : x isa Real ? @sprintf("%.3e", x) : string(x)
dv(d) = is_determined(d) ? determined_value(d) : nothing
st(d) = is_determined(d) ? "unique" : string(d.status, ":", d.reason)

# --- the suite's fixture helpers, extracted by name -------------------------------------------------
const RUNTESTS = readlines(joinpath(REPO, "test", "runtests.jl"))
"Lines of the top-level definition that starts at a line beginning with one of `starts` (a one-liner or a `function ... end` block)."
function definition_lines(starts...)
    i = findfirst(l -> any(s -> startswith(l, s), starts), RUNTESTS)
    i === nothing && error("definition not found in runtests.jl: $(starts)")
    startswith(RUNTESTS[i], "function ") || return RUNTESTS[i:i]
    j = findnext(==("end"), RUNTESTS, i)
    return RUNTESTS[i:j]
end
function fixture_prelude()
    pieces = String[]
    for name in ("const _ST3_J2 =", "_st3_rot(mu::Real)", "function _st3_block_diag(", "function _st3_crab_map(",
                 "_st3_crab_kc(;", "function _st3_defective_spectator(", "_st3_indefinite_6d() =", "_st3_definite_pair_6d() =")
        append!(pieces, definition_lines(name))
    end
    i = findfirst(l -> startswith(l, "const _ST4_SEED"), RUNTESTS)
    j = findnext(l -> startswith(l, "@testset \"Dispersion routes:"), RUNTESTS, i)
    append!(pieces, RUNTESTS[i:j-1])
    return join(pieces, "\n")
end
const PRELUDE = fixture_prelude()
include_string(Main, PRELUDE, "runtests_prelude")

# --- loaders --------------------------------------------------------------------------------------------
function load_oracle_maps(path)
    lines = readlines(path)
    hdr = split(lines[1], '\t')
    @assert hdr[1:3] == ["family", "index", "parameter"] "oracle TSV header moved: $(hdr[1:3])"
    return [(f = split(l, '\t');
             (family=String(f[1]), index=parse(Int, f[2]), parameter=String(f[3]),
              M=permutedims(reshape(parse.(Float64, f[4:39]), 6, 6))))
            for l in lines[2:end] if !isempty(l)]
end
function load_reference(path)
    lines = readlines(path)
    hdr = split(lines[1], '\t')
    @assert hdr[4] == "d11" && hdr[12] == "z1" && hdr[16] == "e1" && hdr[20] == "h" && hdr[21] == "map_matches" "reference TSV header moved"
    return [(f = split(l, '\t');
             (family=String(f[1]), index=parse(Int, f[2]),
              D=permutedims(reshape(parse.(Float64, f[4:11]), 2, 4)), zeta=parse.(Float64, f[12:15]),
              eta=parse.(Float64, f[16:19]), h=parse(Float64, f[20]), matches=f[21] == "1"))
            for l in lines[2:end] if !isempty(l)]
end
oname(o) = "$(o.family) oracle index $(o.index) (parameter $(o.parameter))"

# --- shared kernels ----------------------------------------------------------------------------------------
routes_of(M; kwargs...) = (cl = _st4_clusters(M); (cl=cl, rep=Octopus._dispersion_routes(M, cl; kwargs...)))
route(rep, name) = _st4_route(rep, name)
"Longitudinal mode vector of the report (the cluster's mode with the report's canonical index)."
function longitudinal_vector(cl, rep)
    rep.longitudinal == 0 && return nothing
    modes = dv(cl.clusters[rep.longitudinal_cluster].modes)
    modes === nothing && return nothing
    k = findfirst(m -> m.index == rep.longitudinal, modes)
    return k === nothing ? nothing : modes[k].vector
end
kappa_route(M, D) = max(1.0, norm(M)) * max(1.0, norm(D))^2
const RESULTS = Dict{String,Any}()
const LINES = String[]
pr(s...) = push!(LINES, string(s...))

# =====================================================================================================
# Section 1: the oracle agreement table (39 maps of the note against its own reference values).
# =====================================================================================================
const ROUTE_NAMES = collect(Octopus.DISPERSION_ROUTES)
short(s::Symbol) = s === :none ? "ok" : s === :coasting_structure ? "coast" : s === :cluster_unresolved ? "unres" :
                   s === :singular_coefficient ? "singcoef" : s === :singular_longitudinal_projection ? "singproj" :
                   s === :not_invariant ? "notinv" : s === :route_not_selected ? "notsel" : string(s)
condstr(r) = is_determined(r.coefficient_condition) ? e2(dv(r.coefficient_condition)) : short(r.coefficient_condition.reason)
"One oracle map through `_dispersion_routes` and against the reference triple; returns the row record."
function oracle_row(o, rf; longitudinal=nothing)
    cl, rep = longitudinal === nothing ? routes_of(o.M) : routes_of(o.M; longitudinal=longitudinal)
    rs = [route(rep, n) for n in ROUTE_NAMES]
    coast = rep.coasting.holds
    dzeta = Dict{Symbol,Float64}(); deta = Dict{Symbol,Float64}(); dh = Dict{Symbol,Float64}(); dD = Dict{Symbol,Float64}()
    if coast
        eta = dv(rep.coasting.eta)
        dzeta[:coasting] = 0.0; deta[:coasting] = norm(eta - rf.eta, Inf); dh[:coasting] = abs(1 - rf.h); dD[:coasting] = norm(hcat(zeros(4), eta) - rf.D, Inf)
    else
        for r in rs
            is_determined(r.zeta) || continue
            dzeta[r.route] = norm(dv(r.zeta) - rf.zeta, Inf); deta[r.route] = norm(dv(r.eta) - rf.eta, Inf)
            dh[r.route] = abs(dv(r.h) - rf.h); dD[r.route] = norm(dv(r.graph) - rf.D, Inf)
        end
    end
    prim = route(rep, :eigenplane)
    inv = is_determined(prim.invariance_residual) ? dv(prim.invariance_residual) : (normalized=NaN, raw=NaN)
    agree = isempty(rep.agreement) ? 0.0 : maximum(max(a.zeta, a.eta, a.h) for a in rep.agreement)
    nuniq = length(dzeta)
    worst = nuniq == 0 ? NaN : max(maximum(values(dzeta)), maximum(values(deta)), maximum(values(dh)))
    return (name=oname(o), family=o.family, index=o.index, M=o.M, cl=cl, rep=rep, ref=rf, coast=coast, statuses=[r.status for r in rs],
            dzeta=dzeta, deta=deta, dh=dh, dD=dD, agree=agree, nuniq=nuniq, worst=worst,
            inv_norm=inv.normalized, inv_raw=inv.raw,
            trace_res=is_determined(prim.trace_residual) ? dv(prim.trace_residual) : NaN,
            area=is_determined(prim.canonical_area) ? dv(prim.canonical_area) : NaN,
            conds=[condstr(r) for r in rs], iters=(route(rep, :newton).iterations, route(rep, :fixed_point).iterations),
            margin=rep.coasting.margin, cubic=rep.trace_cubic_residual, tunes=rep.tunes, longitudinal=rep.longitudinal,
            labels=rep.labels)
end
named_max(rows, f) = (v = [f(r) for r in rows]; k = argmax(replace(v, NaN => -Inf)); (rows[k].name, v[k]))
named_min(rows, f) = (v = [f(r) for r in rows]; k = argmin(replace(v, NaN => Inf)); (rows[k].name, v[k]))
function oracle_section(oracle, ref)
    rows = [oracle_row(o, ref[findfirst(r -> r.family == o.family && r.index == o.index, ref)]) for o in oracle]
    RESULTS["oracle_rows"] = rows
    pr("\n## 1. Oracle agreement table (39 maps of the canonical-dispersion note; reference = the note's own graph, zeta, eta, h)\n")
    pr("Reference values: dump_oracle_reference.py drives verify_dispersion.py's `check_map` (every note identity at its 2e-10) and `coefficients` once per map; the 36 map entries re-dumped there equal the stage 1 TSV bit for bit on $(count(r -> r.ref.matches, rows))/$(length(rows)) maps. Julia side: `_mode_clusters` with the default rho_M0 (roundoff arm), `_dispersion_routes` with the default rules. Differences are infinity norms against the reference; `worst` = max over the unique routes of |dzeta|, |deta|, |dh|; the design's acceptance is 2e-10. Statuses in DISPERSION_ROUTES order $(ROUTE_NAMES) (ok = :none, coast = :coasting_structure, unres = :cluster_unresolved, singcoef, singproj, notinv). Conditions in the same order (the coefficient condition of each route's solve).\n")
    pr("| map | coasting (margin) | statuses | unique | max dzeta | max deta | max dh | max dD | agreement | (I1) norm | (I1) raw | trace res | area | conditions | it N/FP | cubic res | <= 2e-10 |")
    pr("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows
        pr("| $(r.name) | $(r.coast) ($(e2(r.margin))) | $(join(short.(r.statuses), " ")) | $(r.nuniq) | $(e2(maximum(values(r.dzeta); init=0.0))) | $(e2(maximum(values(r.deta); init=0.0))) | $(e2(maximum(values(r.dh); init=0.0))) | $(e2(maximum(values(r.dD); init=0.0))) | $(e2(r.agree)) | $(e2(r.inv_norm)) | $(e2(r.inv_raw)) | $(e2(r.trace_res)) | $(e2(r.area)) | $(join(r.conds, " ")) | $(r.iters[1])/$(r.iters[2]) | $(e2(r.cubic)) | $(r.worst <= 2e-10) |")
    end
    # the route-agreement matrix: per route, the largest difference from the reference over the maps where it is unique
    pr("\n### 1a. Route-agreement matrix (max over the maps where the route is unique; count of such maps)\n")
    pr("| route | maps unique | max dzeta (map) | max deta (map) | max dh (map) | max dD (map) |")
    pr("|---|---|---|---|---|---|")
    for n in vcat(ROUTE_NAMES, :coasting)
        sub = [r for r in rows if haskey(r.dzeta, n)]
        isempty(sub) && (pr("| $(n) | 0 | - | - | - | - |"); continue)
        f(k) = (nm, v) = named_max(sub, r -> getfield(r, k)[n])
        pr("| $(n) | $(length(sub)) | $(e2(f(:dzeta)[2])) ($(f(:dzeta)[1])) | $(e2(f(:deta)[2])) ($(f(:deta)[1])) | $(e2(f(:dh)[2])) ($(f(:dh)[1])) | $(e2(f(:dD)[2])) ($(f(:dD)[1])) |")
    end
    pr("\n### 1b. Extremes named from the rows\n")
    npass = count(r -> r.worst <= 2e-10, rows)
    pr("- maps with every unique route within 2e-10 of the note: $(npass)/$(length(rows)); worst overall $(e2(named_max(rows, r -> r.worst)[2])) at \"$(named_max(rows, r -> r.worst)[1])\".")
    for (lab, f) in (("agreement entry", r -> r.agree), ("(I1) normalized residual of the primary", r -> r.inv_norm), ("(I1) raw residual", r -> r.inv_raw),
                     ("|trace residual|", r -> abs(r.trace_res)), ("cubic-root residual", r -> r.cubic), ("coasting margin (non-coasting maps)", r -> r.coast ? NaN : r.margin))
        nm, v = named_max(rows, f); pr("- largest $(lab): $(e2(v)) at \"$(nm)\".")
    end
    nm, v = named_min(rows, r -> r.coast ? NaN : abs(r.area)); pr("- smallest |canonical area| (bunched maps): $(e2(v)) at \"$(nm)\".")
    nm, v = named_max(rows, r -> r.coast ? r.margin : NaN); pr("- largest coasting margin among the coasting maps: $(e2(v)) at \"$(nm)\".")
    for fam in ("repeated", "defective", "coasting")
        sub = [r for r in rows if r.family == fam]
        pr("- $(fam) maps: statuses $(join(unique([join(short.(r.statuses), " ") for r in sub]), "; ")); worst difference $(e2(maximum(r.worst for r in sub))); degeneracy $(join(unique(string(r.cl.degeneracy_status) for r in sub), ", ")).")
    end
    return rows
end

"Reference synchrotron phase of an oracle family (the note's fixture loop: dense = the parameter, prescribed = -0.94, repeated / defective = -1.3)."
reference_mu_s(o) = o.family == "dense" ? parse(Float64, o.parameter) : o.family == "prescribed_h" ? -0.94 : -1.3
"Canonical index of the resolved mode whose eigenvalue is nearest exp(-i mu_s) (the certified longitudinal selection), or 0."
function certified_index(cl, mu_s)
    best = (Inf, 0)
    for c in cl.clusters
        modes = dv(c.modes); modes === nothing && continue
        for m in modes
            d = abs(m.eigenvalue - exp(-im * mu_s)); d < best[1] && (best = (d, m.index))
        end
    end
    return best[1] <= 1e-3 ? best[2] : 0     # no resolved mode near the phase (E9 clusters): fall back to the default rule
end
function certified_section(oracle, ref, rows)
    pr("\n### 1c. Longitudinal selection: the default z-area heuristic versus the certified index\n")
    pr("The default rule (E3/E9, fixer T1: an UNCERTIFIED heuristic) takes the resolved mode with the largest signed z-area; by (K12) kappa_sz = h, so a betatron mode carries more z-area when h < 1/2. The certified index here is the resolved mode whose eigenvalue is nearest exp(-i mu_s) for the note's own synchrotron phase (dense: the parameter, prescribed: -0.94, repeated / defective: -1.3), passed as `longitudinal`. Rows whose default selection differs from the certified one are re-run with it; kappa[j, z] lists the signed z-areas of the three labelled modes (label order) as the default rule saw them.\n")
    pr("| map | h (note) | default index | certified index | default selection's tune | kappa[:, z] (default labels) | statuses (certified) | max dzeta | max deta | max dh | agreement | <= 2e-10 |")
    pr("|---|---|---|---|---|---|---|---|---|---|---|---|")
    cert_rows = Any[]; n_differ = 0
    for (o, r) in zip(oracle, rows)
        r.coast && continue
        idx = certified_index(r.cl, reference_mu_s(o))
        idx == r.longitudinal && (push!(cert_rows, r); continue)
        n_differ += 1
        rc = oracle_row(o, r.ref; longitudinal=idx)
        push!(cert_rows, rc)
        lb = dv(r.labels); kz = lb === nothing ? "unavailable" : join(e2.(lb.signed_areas[:, 3]), " ")
        tune_default = lb === nothing ? NaN : r.tunes[end]
        pr("| $(r.name) | $(e2(r.ref.h)) | $(r.longitudinal) | $(idx) | $(e2(tune_default)) | $(kz) | $(join(short.(rc.statuses), " ")) | $(e2(maximum(values(rc.dzeta); init=0.0))) | $(e2(maximum(values(rc.deta); init=0.0))) | $(e2(maximum(values(rc.dh); init=0.0))) | $(e2(rc.agree)) | $(rc.worst <= 2e-10) |")
    end
    RESULTS["oracle_rows_certified"] = cert_rows
    npass = count(r -> r.coast || r.worst <= 2e-10, cert_rows) + count(r -> r.coast, rows)
    ntot = length(rows)
    pr("\n- default selection differs from the certified index on $(n_differ) of $(count(r -> !r.coast, rows)) bunched maps; with the certified index every unique route is within 2e-10 of the note on $(count(r -> r.worst <= 2e-10, cert_rows) + count(r -> r.coast, rows))/$(ntot) maps (default rule: $(count(r -> r.worst <= 2e-10, rows))/$(ntot)).")
    nm, v = named_max(cert_rows, r -> r.worst); pr("- worst difference with the certified selection: $(e2(v)) at \"$(nm)\".")
    nm, v = named_max(cert_rows, r -> r.agree); pr("- largest agreement entry with the certified selection: $(e2(v)) at \"$(nm)\".")
    fp = [r for r in rows if !r.coast && r.statuses[end] === :not_invariant]
    pr("- fixed point `:not_invariant` (E7 stall: a step that did not decrease the (I1) residual) on $(length(fp)) of $(count(r -> !r.coast, rows)) bunched maps by the default selection; the other four routes `:none` on every bunched map: $(all(r -> all(==(:none), r.statuses[1:4]), [r for r in rows if !r.coast])).")
    lbd = [dv(r.labels) for r in rows if !r.coast]
    pr("- labels detail on the bunched maps: $(join(unique([dv(r.labels) === nothing ? "unavailable" : r.labels.detail[1:min(60, end)] for r in rows if !r.coast]), " | "))...")
    return cert_rows
end

# =====================================================================================================
# Section 2: PROVISIONAL constants' windows (one-tenth / ten rule; names derived from the data).
# =====================================================================================================
const ACC = Dict{String,Dict{String,Float64}}(); const REJ = Dict{String,Dict{String,Float64}}(); const UNL = Dict{String,Dict{String,Float64}}()
acc!(c, name, v) = (get!(ACC, c, Dict{String,Float64}())[name] = v)
rej!(c, name, v) = (get!(REJ, c, Dict{String,Float64}())[name] = v)
unl!(c, name, v) = (get!(UNL, c, Dict{String,Float64}())[name] = v)
S4 = Octopus._symplectic_form(4)
sinv(W) = Octopus._symplectic_inverse(W)
"Repeated-betatron map k (fixture row 3): W scale 0.1, phases (0.72, 0.72, -1.3)."
function repeated_map(k)
    W = Octopus._manufactured_symplectic_map(MersenneTwister(_ST4_SEED + 300 + k), 6; scale=0.1).M
    (M=W * _st4_blockrot(0.72, 0.72, -1.3) * sinv(W), W=W, name="repeated betatron k=$(k) (phases 0.72, 0.72, -1.3)")
end
"Defective spectator map (row 4): the 4D Jordan block of `_st3_defective_spectator(0.72)` with R(-1.3), conjugated by W (scale 0.08)."
function defective_map()
    W = Octopus._manufactured_symplectic_map(MersenneTwister(_ST4_SEED + 400), 6; scale=0.08).M
    (M=W * _st4_block_diag(_st3_defective_spectator(0.72), _st3_rot(-1.3)) * sinv(W), W=W, name="defective spectator (Jordan 0.72, R(-1.3))")
end
"The bunched fixture set: (name, M, exact triple or nothing, certified longitudinal phase)."
function bunched_fixtures()
    fx = Any[]
    for k in 0:199
        f = _st4_dense(k); push!(fx, (name="dense k=$(k) (mu_s=$(round(f.mus[3]; digits=4)))", M=f.M, zeta=f.zeta, eta=f.eta, h=f.h, mu_s=f.mus[3], family="dense"))
    end
    for h in _st4_prescribed_h
        f = _st4_prescribed(h); push!(fx, (name="prescribed h=$(h)", M=f.M, zeta=f.zeta, eta=f.eta, h=f.h, mu_s=f.mus[3], family="prescribed"))
    end
    for k in 0:3
        f = repeated_map(k); D = f.W[1:4, 5:6] / f.W[5:6, 5:6]; z, e, h, _ = Octopus._graph_to_dispersion(D)
        push!(fx, (name=f.name, M=f.M, zeta=z, eta=e, h=h, mu_s=-1.3, family="repeated"))
    end
    f = defective_map(); D = f.W[1:4, 5:6] / f.W[5:6, 5:6]; z, e, h, _ = Octopus._graph_to_dispersion(D)
    push!(fx, (name=f.name, M=f.M, zeta=z, eta=e, h=h, mu_s=-1.3, family="defective"))
    kc = _st3_crab_kc()
    for e in (1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6)
        push!(fx, (name="trial-011 crab k=kc(1-$(e))", M=_st3_crab_map(kc * (1 - e)), zeta=nothing, eta=nothing, h=nothing, mu_s=-0.75, family="crab"))
    end
    fc = _st4_coasting(0.7); Mc = _st4_mcal(zeros(4), fc.eta)
    Mw = Mc * _st4_block_diag(fc.A, [1.0 0.7; -1e-6 1 - 0.7e-6]) * sinv(Mc)
    push!(fx, (name="weak cavity (M[6,5] = -1e-6 folded, shear 0.7)", M=Mw, zeta=nothing, eta=nothing, h=nothing, mu_s=nothing, family="weak"))
    return fx
end
"Coasting fixtures: the three coasting maps, the singular-coefficient coasting map, the DBA cell (matrix only)."
function coasting_fixtures()
    fx = Any[]
    for s in (-0.4, 0.0, 0.7)
        f = _st4_coasting(s); push!(fx, (name="coasting shear s=$(s)", M=f.M, eta=f.eta, family="coasting"))
    end
    fs = _st4_coasting(0.7); Mcs = _st4_mcal(zeros(4), fs.eta)
    Msing = Mcs * _st4_block_diag(_st4_block_diag(_st4_R(0.3), [1.0 0.2; 0.0 1.0]), [1.0 0.7; 0.0 1.0]) * sinv(Mcs)
    push!(fx, (name="coasting with a y-plane shear inside M_rr (singular (D24) coefficient)", M=Msing, eta=nothing, family="coasting_singular"))
    return fx
end
"The rejection fixtures of the route guards: singular projection (h = 0), the degenerate Md, its crab products, the N15 indefinite map."
function guard_fixtures()
    zeta = [1.0, 0, 0, 0]; eta = [0.0, 1, 0, 0]; Mc = _st4_mcal(zeta, eta)
    Ms = Mc * _st4_blockrot(0.73, 1.41, -0.9) * sinv(Mc)
    Md = _st4_blockrot(0.73, 1.41, 0.73)
    k = 0.3; Ck = Matrix(1.0I, 6, 6); Ck[2, 5] = -k; Ck[6, 1] = -k
    return (Ms=(name="singular projection zeta=e_x, eta=e_px (h=0) around R(0.73, 1.41, -0.9)", M=Ms),
            Md=(name="degenerate diag(R(0.73), R(1.41), R(0.73))", M=Md),
            Mk=(name="degenerate Md C_k (k=0.3)", M=Md * Ck), Mks=(name="crab similarity C_k Md C_k^-1 (k=0.3)", M=Ck * Md / Ck),
            N15=(name="N15 indefinite diag(R(0.73), R(1.41), R(-0.73))", M=_st3_indefinite_6d()),
            Dfalse=[1.0 0.0; 0.0 -0.5; 0.0 0.0; 0.0 0.0], Diso=[1.0 0.0; 0.0 -1.0; 0.0 0.0; 0.0 0.0], Ck=Ck, k=k)
end

const ITER = Dict{String,Any}()   # iteration data for _MAX_HALVINGS and _FIXED_POINT_MAX_ITERATIONS
"Route ratios at multiplier 1 for one bunched map (the report `rep` of `cl`); `tag` names the fixture."
function collect_route_ratios!(tag, M, cl, rep)
    rho = cl.rho_M1; eig = route(rep, :eigenplane); pol = route(rep, :polynomial); prj = route(rep, :projector)
    new = route(rep, :newton); fp = route(rep, :fixed_point)
    # c_coast: every bunched map is a rejected fixture of the coasting test (ratio = margin * c_coast)
    rej!("c_coast", tag, rep.coasting.margin * Octopus._COASTING_MULTIPLIER)
    # c_graph: sigma_min(U_ls) / (rho_M1 max(1, ||U_s||_2))
    u = longitudinal_vector(cl, rep)
    if u !== nothing && length(eig.singular_values) == 2
        Us = hcat(real(u), -imag(u)); r = eig.singular_values[end] / (rho * max(1.0, opnorm(Us)))
        eig.status === :singular_longitudinal_projection ? rej!("c_graph", tag, r) : acc!("c_graph", tag, r)
    end
    # c_iso: |area| / (rho_M1 max(1, ||D||_2^2)) for every formed graph
    for r in (eig, pol, prj, new, fp)
        is_determined(r.graph) || continue
        D = dv(r.graph); v = abs(dv(r.canonical_area)) / (rho * max(1.0, opnorm(D)^2))
        r.status === :graph_isotropic ? rej!("c_iso", "$(tag) [$(r.route)]", v) : acc!("c_iso", "$(tag) [$(r.route)]", v)
    end
    # c_coef: polynomial A_s (singular values reported), projector trace gaps, the (D15) Sylvester operator
    if length(pol.singular_values) == 4
        v = pol.singular_values[end] / (rho * max(1.0, pol.singular_values[1]))
        pol.status === :singular_coefficient ? rej!("c_coef", "$(tag) [polynomial A_s]", v) :
            is_determined(pol.graph) ? acc!("c_coef", "$(tag) [polynomial A_s]", v) : unl!("c_coef", "$(tag) [polynomial A_s, $(pol.status)]", v)
    end
    if is_determined(rep.tau_s) && prj.status !== :cluster_unresolved && rep.longitudinal_cluster > 0
        Z = M + sinv(M); taus = [Octopus._cluster_trace(c) for c in cl.clusters]
        # the repeated factor: a selected cluster with several pairs has an exactly vanishing trace gap inside it ((N16))
        gap = minimum(i == rep.longitudinal_cluster ? (length(cl.clusters[i].half_members) > 1 ? 0.0 : Inf) : abs(dv(rep.tau_s) - taus[i]) for i in eachindex(taus); init=Inf)
        if isfinite(gap)
            v = gap / (rho * max(1.0, opnorm(Z)))
            prj.status === :singular_coefficient ? rej!("c_coef", "$(tag) [projector trace gap]", v) :
                is_determined(prj.graph) ? acc!("c_coef", "$(tag) [projector trace gap]", v) : unl!("c_coef", "$(tag) [projector trace gap, $(prj.status)]", v)
        end
    end
    op = kron(Matrix(1.0I, 2, 2), M[1:4, 1:4]) - kron(transpose(M[5:6, 5:6]), Matrix(1.0I, 4, 4)); sv = svdvals(op)
    v = sv[end] / (rho * max(1.0, sv[1]))
    # the source guards the Sylvester operators by LAPACK failure only (no c_coef floor acts on them): unlabelled unless singular
    if new.status === :singular_coefficient
        rej!("c_coef", "$(tag) [(D15) Sylvester operator, LAPACK-singular]", v)
    elseif new.status !== :cluster_unresolved && new.status !== :coasting_structure
        unl!("c_coef", "$(tag) [(D15) Sylvester operator]", v)
    end
    # c_inv: normalized (I1) / (eps kappa_route); accepted = :none routes, rejected = :not_invariant graphs (stalled or other branch)
    for r in (eig, pol, prj, new, fp)
        is_determined(r.invariance_residual) || continue
        v = dv(r.invariance_residual).normalized / (EPS * kappa_route(M, dv(r.graph)))
        cr = is_determined(r.coefficient_condition) ? dv(r.coefficient_condition) : 1.0
        if r.status === :none
            acc!("c_inv", "$(tag) [$(r.route)]", v); acc!("c_inv_conditioned", "$(tag) [$(r.route)]", v / cr)
        elseif r.status === :not_invariant
            # a graph on ANOTHER branch is invariant (rejected by the trace check, not by (I1)): unlabelled for c_inv
            occursin("another branch", r.detail) ? unl!("c_inv", "$(tag) [$(r.route), other branch]", v) : rej!("c_inv", "$(tag) [$(r.route), $(r.iterations > 0 ? "stalled iterate" : "formed graph")]", v)
            occursin("another branch", r.detail) || rej!("c_inv_conditioned", "$(tag) [$(r.route)]", v / cr)
        end
    end
    # c_stop: converged iterates' final residual / (eps max(1, ||M||_F)) accepted; the iterate one step short rejected
    for r in (new, fp)
        (r.converged && is_determined(r.invariance_residual)) || continue
        unl!("c_stop", "$(tag) [$(r.route) final iterate]", dv(r.invariance_residual).normalized / (EPS * max(1.0, norm(M))))
    end
    if new.converged && new.iterations >= 2 && is_determined(rep.tau_s)
        short_run = Octopus._newton_route(M, dv(rep.tau_s); rho_M1=rho, max_iterations=new.iterations - 1)
        if is_determined(short_run.invariance_residual)
            v = dv(short_run.invariance_residual).normalized / (EPS * max(1.0, norm(M)))
            unl!("c_stop", "$(tag) [newton iterate $(new.iterations - 1) of $(new.iterations)]", v)
            unl!("c_inv", "$(tag) [newton iterate $(new.iterations - 1) of $(new.iterations)]", dv(short_run.invariance_residual).normalized / (EPS * kappa_route(M, dv(short_run.graph))))
        end
    end
    # c_tie: label margins / (eps kappa_frame) = margin / tie_tolerance * c_tie (clear labels are accepted fixtures)
    lb = dv(rep.labels)
    if lb !== nothing && lb.tie_tolerance > 0
        f = Octopus._LABEL_TIE_MULTIPLIER / lb.tie_tolerance
        for (what, m) in (("longitudinal margin", lb.longitudinal_margin), ("transverse margin", lb.transverse_margin))
            # a margin at or below the tie tolerance IS a tie (the rule declares it; the data names the fixture)
            abs(m) <= lb.tie_tolerance ? rej!("c_tie", "$(tag) [$(what), declared tie]", abs(m) * f) : acc!("c_tie", "$(tag) [$(what)]", abs(m) * f)
        end
    end
    ITER[tag] = (newton=(new.iterations, new.halvings, new.converged, new.status), fixed_point=(fp.iterations, fp.converged, fp.status))
    return nothing
end
"The (D24) coasting ratios: structure residual / (rho_M1 max(1, ||M||_F)) accepted, sigma_min(I - M_rr) coefficient ratio."
function collect_coasting_ratios!(tag, M, cl, rep)
    c = rep.coasting
    acc!("c_coast", tag, c.margin * Octopus._COASTING_MULTIPLIER)
    sv = svdvals(I - M[1:4, 1:4]); v = sv[end] / (cl.rho_M1 * max(1.0, sv[1]))
    is_determined(c.eta) ? acc!("c_coef", "$(tag) [(D24) I - M_rr]", v) : rej!("c_coef", "$(tag) [(D24) I - M_rr]", v)
    return nothing
end

"Run the routes on every fixture (certified longitudinal index where a phase is known) and collect the Part A ratios; returns the reports for Part B."
function part_a_collection()
    reports = Any[]
    for f in bunched_fixtures()
        cl = _st4_clusters(f.M)
        idx = f.mu_s === nothing ? 0 : certified_index(cl, f.mu_s)
        rep = idx == 0 ? Octopus._dispersion_routes(f.M, cl) : Octopus._dispersion_routes(f.M, cl; longitudinal=idx)
        collect_route_ratios!(f.name, f.M, cl, rep)
        push!(reports, (f=f, cl=cl, rep=rep))
    end
    for r in RESULTS["oracle_rows_certified"]
        r.coast ? collect_coasting_ratios!(r.name, r.M, r.cl, r.rep) : collect_route_ratios!(r.name, r.M, r.cl, r.rep)
    end
    for f in coasting_fixtures()
        cl = _st4_clusters(f.M); rep = Octopus._dispersion_routes(f.M, cl)
        rep.coasting.holds ? collect_coasting_ratios!(f.name, f.M, cl, rep) : collect_route_ratios!(f.name, f.M, cl, rep)
        push!(reports, (f=f, cl=cl, rep=rep))
    end
    g = guard_fixtures()
    for (fx, mu) in ((g.Ms, -0.9), (g.Md, nothing), (g.Mk, nothing), (g.Mks, nothing), (g.N15, -0.73))
        cl = _st4_clusters(fx.M); idx = mu === nothing ? 0 : certified_index(cl, mu)
        rep = idx == 0 ? Octopus._dispersion_routes(fx.M, cl) : Octopus._dispersion_routes(fx.M, cl; longitudinal=idx)
        collect_route_ratios!(fx.name, fx.M, cl, rep)
        RESULTS["guard " * fx.name] = (cl=cl, rep=rep)
    end
    # the isotropic graph and the false graph through the route acceptance (rho_M1 of Md's clusters)
    rho_d = RESULTS["guard " * g.Md.name].cl.rho_M1
    r = Octopus._route_from_graph(:eigenplane, g.Md.M, g.Diso, 2cos(0.73); rho_M1=rho_d)
    rej!("c_iso", "isotropic graph [e_x, -e_px] on $(g.Md.name)", abs(dv(r.canonical_area)) / (rho_d * max(1.0, opnorm(g.Diso)^2)))
    r = Octopus._route_from_graph(:polynomial, g.Md.M, g.Dfalse, 2cos(0.73); rho_M1=rho_d)
    rej!("c_inv", "false graph [diag(1, -0.5); 0] on $(g.Md.name) (theory 13.7)", dv(r.invariance_residual).normalized / (EPS * kappa_route(g.Md.M, g.Dfalse)))
    # the pseudoinverse (zero) graph on the crab similarity: raw residual sqrt(2) k sin 0.73 (design 0.28293)
    r0 = Octopus._route_residuals(g.Mks.M, zeros(4, 2), 2cos(0.73))
    RESULTS["zero graph raw residual on crab similarity"] = (raw=r0.invariance.raw, design=sqrt(2) * g.k * sin(0.73))
    rej!("c_inv", "zero (pseudoinverse) graph on $(g.Mks.name)", Octopus._graph_invariance_residual(g.Mks.M, zeros(4, 2)).normalized / (EPS * kappa_route(g.Mks.M, zeros(4, 2))))
    # label ties: the 45-degree rolls (x-y for the transverse margin, y-z for the longitudinal one)
    ux = ComplexF64[1, -im, 0, 0, 0, 0]; uy = ComplexF64[0, 0, 1, -im, 0, 0]; uz = ComplexF64[0, 0, 0, 0, 1, -im]
    lb = Octopus._mode_labels_6d([(ux + uy) / sqrt(2), (ux - uy) / sqrt(2), uz], [0.73, 0.73, 5.4])
    rej!("c_tie", "45-degree x-y roll of equal-tune betatron modes [transverse margin]", lb.transverse_margin / lb.tie_tolerance * Octopus._LABEL_TIE_MULTIPLIER)
    lb = Octopus._mode_labels_6d([ux, (uy + uz) / sqrt(2), (uy - uz) / sqrt(2)], [0.73, 1.41, 5.4])
    rej!("c_tie", "45-degree y-z roll (equal z-areas) [longitudinal margin]", lb.longitudinal_margin / lb.tie_tolerance * Octopus._LABEL_TIE_MULTIPLIER)
    # exact-graph floor of the (I1) residual (accepted side of c_stop) on the dense maps
    for rp in reports
        rp.f.family == "dense" || continue
        D = hcat(rp.f.zeta, rp.f.eta ./ rp.f.h)
        acc!("c_stop", "$(rp.f.name) [exact graph floor]", Octopus._graph_invariance_residual(rp.f.M, D).normalized / (EPS * max(1.0, norm(rp.f.M))))
    end
    RESULTS["reports"] = reports
    return reports
end
"Far-start Newton (D0 = D_exact + 100) on the dense maps: halved trials of the converged runs and the stalls at the cap."
function far_start_halvings(reports)
    conv = Dict{String,Int}(); stall = Dict{String,Int}(); maxstep = Dict{String,Int}()
    for rp in reports
        rp.f.family == "dense" || continue
        D0 = hcat(rp.f.zeta, rp.f.eta ./ rp.f.h) .+ 100.0
        r = Octopus._newton_route(rp.f.M, dv(rp.rep.tau_s); rho_M1=rp.cl.rho_M1, D0=D0, max_iterations=50)
        (r.converged ? conv : stall)[rp.f.name] = r.halvings
    end
    RESULTS["far_start"] = (conv=conv, stall=stall)
    return (conv=conv, stall=stall)
end

# --- Part B ratios: c_sep, c_triple, c_ell, c_ohmi ------------------------------------------------------------
triple_ratio(zeta, eta, h) = abs(dot(zeta, S4 * eta) - (1 - h)) / (EPS * max(1.0, norm(zeta) * norm(eta)))
ell_ratio(Mbar_s) = (2 - abs(tr(Mbar_s))) / (EPS * max(1.0, norm(Mbar_s)))
ohmi_ratio(zeta, eta, h) = h / (EPS * max(1.0, norm(zeta) * norm(eta)))
"Part B ratios on every report whose primary triple is unique, plus the synthetic rejection fixtures of the B docstrings."
function part_b_collection(reports)
    seps = Any[]
    for rp in reports
        rep = rp.rep; is_determined(rep.zeta) || continue
        rep.coasting.holds && continue
        tag = rp.f.name
        # the chain's thin method: ONE (D8) evaluation of the primary graph (the report's h is (D11) det U_ls, which differs from
        # the (D8) h by eps cond(U_ls): the report triple is recorded unlabelled, the (D8) triple is the accepted fixture)
        sep = Octopus._canonical_separation(rp.f.M, rep)
        zeta, eta, h = sep.zeta, sep.eta, sep.h
        acc!("c_triple", tag, triple_ratio(zeta, eta, h))
        unl!("c_triple", "$(tag) [report triple with the (D11) h = det U_ls]", triple_ratio(dv(rep.zeta), dv(rep.eta), dv(rep.h)))
        v_sep = sep.off_diagonal_residual / (EPS * _st4_kappa_sep(sep, rp.f.M))
        # a triple whose error is eps cond(U_ls) (the weak cavity: cond 8e2) is limited by the route's conditioning, which kappa_sep does not carry
        rp.f.family == "weak" ? unl!("c_sep", "$(tag) [triple at cond(U_ls) = $(e2(dv(route(rep, :eigenplane).coefficient_condition)))]", v_sep) : acc!("c_sep", tag, v_sep)
        acc!("c_ell", tag, ell_ratio(sep.longitudinal_map))
        h > 0 ? acc!("c_ohmi", tag, ohmi_ratio(zeta, eta, h)) : unl!("c_ohmi", "$(tag) [h < 0: form_inadmissible by sign, not by the floor]", ohmi_ratio(zeta, eta, h))
        push!(seps, (tag=tag, M=rp.f.M, sep=sep, zeta=zeta, eta=eta, h=h, family=rp.f.family))
        # rejected side of c_sep: the exact zeta perturbed by delta (1, -1, 0.5, 0.25), h re-derived so the triple stays consistent
        if rp.f.family == "dense" && rp.f.zeta !== nothing
            for delta in (1e-8, 1e-10, 1e-12, 1e-13, 1e-14)
                zp = rp.f.zeta + delta * [1.0, -1.0, 0.5, 0.25]; hp = 1 - dot(zp, S4 * rp.f.eta)
                sp = Octopus._canonical_separation(rp.f.M, zp, rp.f.eta, hp)
                v = sp.off_diagonal_residual / (EPS * _st4_kappa_sep(sp, rp.f.M))
                delta >= 1e-10 ? rej!("c_sep", "$(tag) [zeta + $(delta) (1, -1, 0.5, 0.25)]", v) : unl!("c_sep", "$(tag) [zeta + $(delta) (1, -1, 0.5, 0.25)]", v)
            end
            for dh in (1e-12, 1e-13, 1e-14)
                v = triple_ratio(rp.f.zeta, rp.f.eta, rp.f.h + dh)
                dh >= 1e-12 ? rej!("c_triple", "$(tag) [h + $(dh)]", v) : unl!("c_triple", "$(tag) [h + $(dh)]", v)
            end
        end
    end
    RESULTS["separations"] = seps
    # c_ell rejected: the shear (a coasting longitudinal block), rotations by phases at or below roundoff of tr = 2
    for s in (-0.4, 0.0, 0.7); rej!("c_ell", "shear [1 $(s); 0 1] (unit eigenvalue)", ell_ratio([1.0 s; 0.0 1.0])); end
    for mu in (1e-8, 3e-8); rej!("c_ell", "R($(mu)) (2 - tr within the roundoff 2 eps of tr itself)", ell_ratio(_st4_R(mu))); end
    for mu in (1e-7, 1e-6); unl!("c_ell", "R($(mu)) (boundary: elliptic, 2 - tr = $(e2(2 - 2cos(mu))))", ell_ratio(_st4_R(mu))); end
    rej!("c_ell", "hyperbolic diag(2, 1/2)", ell_ratio([2.0 0.0; 0.0 0.5]))
    # c_ohmi rejected: h = 0 and h at roundoff on the prescribed construction zeta = (1, 0.2, 0.1, 0), eta = (0, 1 - h, 0, 0)
    for h in (0.0, 1e-15, 1e-14, 2e-14)
        zeta = [1.0, 0.2, 0.1, 0.0]; eta = [0.0, 1 - h, 0.0, 0.0]
        h <= 1e-15 ? rej!("c_ohmi", "prescribed construction h=$(h) (h within a few eps of 0)", ohmi_ratio(zeta, eta, h)) : unl!("c_ohmi", "prescribed construction h=$(h) (boundary)", ohmi_ratio(zeta, eta, h))
    end
    return seps
end

# --- the one-tenth / ten rule ------------------------------------------------------------------------------------
const WINDOWS = Dict{String,Any}()
"Window lines for one constant: accepted ratios must stay below c / 10 (accepted_below) and rejected ones above 10 c, or the reverse."
function window_lines(key, title, formula, current; accepted_below::Bool=true)
    acc = get(ACC, key, Dict{String,Float64}()); rej = get(REJ, key, Dict{String,Float64}()); unl = get(UNL, key, Dict{String,Float64}())
    out = String["### $(title)", "", "- ratio at multiplier 1: $(formula)", "- source value: $(current); accepted $(length(acc)), rejected $(length(rej)), unlabelled $(length(unl)) fixture values"]
    if accepted_below
        ka = isempty(acc) ? nothing : argmax(acc); kr = isempty(rej) ? nothing : argmin(rej)
        ka === nothing || push!(out, "- largest accepted ratio (must stay below c / 10): $(e2(acc[ka])) at \"$(ka)\"")
        kr === nothing || push!(out, "- smallest rejected ratio (must exceed 10 c): $(e2(rej[kr])) at \"$(kr)\"")
        lo = ka === nothing ? 0.0 : 10 * acc[ka]; hi = kr === nothing ? Inf : rej[kr] / 10
        top_acc = sort(collect(acc); by=last, rev=true); top_rej = sort(collect(rej); by=last)
    else
        ka = isempty(acc) ? nothing : argmin(acc); kr = isempty(rej) ? nothing : argmax(rej)
        ka === nothing || push!(out, "- smallest accepted ratio (must exceed 10 c): $(e2(acc[ka])) at \"$(ka)\"")
        kr === nothing || push!(out, "- largest rejected ratio (must stay below c / 10): $(e2(rej[kr])) at \"$(kr)\"")
        lo = kr === nothing ? 0.0 : 10 * rej[kr]; hi = ka === nothing ? Inf : acc[ka] / 10
        top_acc = sort(collect(acc); by=last); top_rej = sort(collect(rej); by=last, rev=true)
    end
    empty = lo > hi
    inside = !empty && lo <= current <= hi
    push!(out, "- window [$(e2(lo)), $(e2(hi))]" * (empty ? " is EMPTY (the fixtures on both sides are closer than a factor 100)" : "; source value inside: $(inside)") *
               (isempty(rej) ? " (no rejected fixture: that edge is open)" : ""))
    for (k, v) in top_acc[1:min(4, length(top_acc))]; push!(out, "  - accepted \"$(k)\" $(e2(v))"); end
    for (k, v) in top_rej[1:min(4, length(top_rej))]; push!(out, "  - rejected \"$(k)\" $(e2(v))"); end
    if !isempty(unl)
        us = accepted_below ? sort(collect(unl); by=last) : sort(collect(unl); by=last, rev=true)
        for (k, v) in us[1:min(3, length(us))]; push!(out, "  - unlabelled \"$(k)\" $(e2(v))"); end
        length(us) > 3 && push!(out, "  - unlabelled extreme \"$(us[end][1])\" $(e2(us[end][2]))")
    end
    push!(out, "")
    WINDOWS[key] = (lo=lo, hi=hi, inside=inside, empty=empty, current=current, n_acc=length(acc), n_rej=length(rej), n_unl=length(unl),
                    acc_extreme=ka === nothing ? ("-", NaN) : (ka, acc[ka]), rej_extreme=kr === nothing ? ("-", NaN) : (kr, rej[kr]))
    return out
end
function multiplier_section(reports)
    pr("\n## 2. PROVISIONAL constants: windows by the one-tenth / ten rule (fixture names derived from the data)\n")
    pr("Every ratio is the guarded quantity divided by its floor at multiplier 1; `accepted` fixtures are ones the guard must pass (the ratio must exceed 10 c, or stay below c / 10 for a residual-type guard), `rejected` ones it must refuse; `unlabelled` values are reported but do not constrain the window (boundary cases named in the text). Fixtures: 200 dense maps, 7 prescribed-h maps, 4 repeated, 1 defective, the trial-011 ladder, the weak cavity, 39 oracle maps (certified longitudinal index), 3 coasting maps, the singular-coefficient coasting map, the guard fixtures (h = 0, Md, Md C_k, C_k Md C_k^-1, N15), the synthetic rejection fixtures of the constants' docstrings.\n")
    specs = [("c_graph", "c_graph (_GRAPH_SINGULARITY_MULTIPLIER)", "sigma_min(U_ls) / (rho_M1 max(1, ||U_s||_2)); accepted = regular eigenplane routes, rejected = :singular_longitudinal_projection", Octopus._GRAPH_SINGULARITY_MULTIPLIER, false),
             ("c_iso", "c_iso (_ISOTROPY_MULTIPLIER)", "|1 + D1' S_4 D2| / (rho_M1 max(1, ||D||_2^2)) of every formed graph; rejected = the isotropic graph", Octopus._ISOTROPY_MULTIPLIER, false),
             ("c_coef", "c_coef (_COEFFICIENT_CONDITION_MULTIPLIER)", "sigma_min / (rho_M1 max(1, sigma_max)) of A_s, the projector trace gap / (rho_M1 max(1, ||Z||_2)), sigma_min(I - M_rr) of (D24); rejected = :singular_coefficient; the (D15) operator is LAPACK-guarded only (unlabelled)", Octopus._COEFFICIENT_CONDITION_MULTIPLIER, false),
             ("c_inv", "c_inv (_ROUTE_INVARIANCE_MULTIPLIER)", "normalized (I1) / (eps kappa_route), kappa_route = max(1, ||M||_F) max(1, ||D||_F)^2; accepted = :none routes, rejected = :not_invariant graphs (stalled iterates, the false and zero graphs); other-branch graphs and short Newton iterates unlabelled", Octopus._ROUTE_INVARIANCE_MULTIPLIER, true),
             ("c_inv_conditioned", "INFORMATIONAL: c_inv with the route's coefficient condition folded into kappa", "normalized (I1) / (eps kappa_route cond_route), cond_route = the route's reported coefficient_condition (cond(U_ls), cond(A_s), the trace-gap or Sylvester condition); same labels as c_inv; not a source constant", Octopus._ROUTE_INVARIANCE_MULTIPLIER, true),
             ("c_stop", "c_stop (_ITERATION_STOP_MULTIPLIER)", "normalized (I1) / (eps max(1, ||M||_F)); accepted = the EXACT graph's roundoff floor (the iteration must be able to stop there); converged final iterates and the iterate one step short are unlabelled (the rule defines that boundary itself)", Octopus._ITERATION_STOP_MULTIPLIER, true),
             ("c_coast", "c_coast (_COASTING_MULTIPLIER)", "max structure residual / (rho_M1 max(1, ||M||_F)) = margin * c_coast; accepted = coasting maps, rejected = every bunched map and the weak cavity", Octopus._COASTING_MULTIPLIER, true),
             ("c_tie", "c_tie (_LABEL_TIE_MULTIPLIER)", "|margin| / (eps kappa_frame); accepted = clear labels, rejected = declared ties (the 45-degree rolls and every margin the data put at or below the tolerance)", Octopus._LABEL_TIE_MULTIPLIER, false),
             ("c_sep", "c_sep (_SEPARATION_RESIDUAL_MULTIPLIER)", "off-diagonal (K4) / (eps kappa_sep); accepted = the primary triple of every bunched fixture, rejected = zeta perturbed by delta (1, -1, 0.5, 0.25), delta >= 1e-12 (1e-13, 1e-14 unlabelled)", Octopus._SEPARATION_RESIDUAL_MULTIPLIER, true),
             ("c_triple", "c_triple (_TRIPLE_CONSISTENCY_MULTIPLIER)", "|zeta' S_4 eta - (1 - h)| / (eps max(1, ||zeta|| ||eta||)); rejected = h + 1e-12, h + 1e-13 (1e-14 unlabelled)", Octopus._TRIPLE_CONSISTENCY_MULTIPLIER, true),
             ("c_ell", "c_ell (_LONGITUDINAL_ELLIPTIC_MULTIPLIER)", "(2 - |tr Mbar_s|) / (eps max(1, ||Mbar_s||_F)); accepted = every separated longitudinal block, rejected = shears, R(mu <= 1e-7), a hyperbolic block (R(1e-6) unlabelled)", Octopus._LONGITUDINAL_ELLIPTIC_MULTIPLIER, false),
             ("c_ohmi", "c_ohmi (_OHMI_POSITIVITY_MULTIPLIER)", "h / (eps max(1, ||zeta|| ||eta||)); accepted = positive-h triples, rejected = h in (0, 1e-15, 1e-14) (2e-14 unlabelled; negative h is refused by sign)", Octopus._OHMI_POSITIVITY_MULTIPLIER, false)]
    for (key, title, formula, current, below) in specs
        for l in window_lines(key, title, formula, current; accepted_below=below); pr(l); end
    end
    pr("### Summary\n")
    pr("| constant | source | window low | window high | inside | accepted | rejected | unlabelled |")
    pr("|---|---|---|---|---|---|---|---|")
    for (key, _, _, _, _) in specs
        w = WINDOWS[key]; pr("| $(key) | $(w.current) | $(e2(w.lo)) | $(e2(w.hi)) | $(w.empty ? "EMPTY" : w.inside) | $(w.n_acc) | $(w.n_rej) | $(w.n_unl) |")
    end
    # the two integer caps (stopping rules): iteration data
    fs = far_start_halvings(reports)
    nconv = length(fs.conv); nstall = length(fs.stall)
    kc = isempty(fs.conv) ? ("-", 0) : (argmax(fs.conv), maximum(values(fs.conv)))
    pr("\n### _MAX_HALVINGS = $(Octopus._MAX_HALVINGS) and _FIXED_POINT_MAX_ITERATIONS = $(Octopus._FIXED_POINT_MAX_ITERATIONS) (integer caps: stopping rules, no tolerance window)\n")
    hv = Dict(k => v.newton[2] for (k, v) in ITER); kh = argmax(hv)
    pr("- from the (D15) start: halved trials over the whole run at most $(hv[kh]) at \"$(kh)\" over the $(length(ITER)) fixtures ($(count(==(0), values(hv))) fixtures never halve); Newton iterations at most $(maximum(v.newton[1] for v in values(ITER))) at \"$(argmax(Dict(k => v.newton[1] for (k, v) in ITER)))\".")
    pr("- far start D0 = D_exact + 100 on the 200 dense maps: $(nconv) converge (halved trials over the run up to $(kc[2]) at \"$(kc[1])\"), $(nstall) stall at the per-step cap ($(Octopus._MAX_HALVINGS) halved trials in the stalling step; accumulated over the run $(minimum(values(fs.stall); init=0)) .. $(maximum(values(fs.stall); init=0))).")
    fpi = Dict(k => v.fixed_point[1] for (k, v) in ITER if v.fixed_point[2]); kf = isempty(fpi) ? "-" : argmax(fpi)
    pr("- fixed point: converged on $(length(fpi)) fixtures, slowest $(isempty(fpi) ? 0 : fpi[kf]) iterations at \"$(kf)\"; `:not_invariant` (E7 stall) on $(count(v -> v.fixed_point[3] === :not_invariant, values(ITER))); cap $(Octopus._FIXED_POINT_MAX_ITERATIONS) reached on $(count(v -> v.fixed_point[1] >= Octopus._FIXED_POINT_MAX_ITERATIONS, values(ITER))).")
end

# =====================================================================================================
# Section 3: the rejected side of every `c eps kappa` check family of the stage 4a testsets.
# Each family: the check's ratio (residual / (eps kappa), the test's c beside it) on a legitimate
# fixture (green) and under one injected defect the check exists for (red once).
# =====================================================================================================
const FAMILIES = Any[]
fam!(name, c, kappa_text, legit_name, legit, defect_name, defect) = push!(FAMILIES, (name=name, c=c, kappa=kappa_text, legit_name=legit_name, legit=legit, defect_name=defect_name, defect=defect))
function rejected_side_section(reports)
    dense = [rp for rp in reports if rp.f.family == "dense"]
    rp = dense[1 + 66]; f = rp.f; M = f.M; rep = rp.rep; cl = rp.cl        # a dense map near the coincident-trace region (k = 66) and
    rq = dense[1 + 3]; fq = rq.f                                             # a well separated one (k = 3)
    eig = route(rep, :eigenplane); D = dv(eig.graph)
    # F1: route triple against the exact triple; defect: the (D12) sign of eta flipped
    kap = max(1, norm(M)) * max(1, norm(D))^2
    fam!("route triple vs exact triple (dense)", 1024, "max(1,||M||) max(1,||D||)^2", f.name, norm(dv(rep.eta) - f.eta, Inf) / (EPS * kap),
         "eta with the (D12) sign flipped", norm(-dv(rep.eta) - f.eta, Inf) / (EPS * kap))
    # F2: agreement entries; defect: a graph on another branch (the Newton graph of the prescribed h = -2 map with the certified index)
    pre = reports[findfirst(r -> r.f.name == "prescribed h=-2.0", reports)]
    a_ok = maximum(max(a.zeta, a.eta, a.h) for a in rep.agreement)
    kap_p = max(1, norm(pre.f.M)) * max(1, norm(dv(route(pre.rep, :eigenplane).graph)))^2
    other = dv(route(pre.rep, :newton).graph); z2, e2_, h2, _ = Octopus._graph_to_dispersion(other)
    fam!("route agreement entries", 2048, "max(1,||M||) max(1,||D||)^2", f.name, a_ok / (EPS * kap),
         "eigenplane vs the Newton graph on ANOTHER branch (prescribed h=-2, certified index)", max(norm(z2 - pre.f.zeta, Inf), norm(e2_ - pre.f.eta, Inf), abs(h2 - pre.f.h)) / (EPS * kap_p))
    # F3: cubic roots vs 2 cos mu_j; defect: a non-symplectic 1e-8 perturbation of M (the trace identities no longer hold on a symplectic spectrum)
    Mp = M + 1e-8 * randn(MersenneTwister(1), 6, 6)
    rts = Octopus._trace_cubic_roots(Mp); taus = sort(2cos.(rep.tunes))
    fam!("trace-cubic roots vs 2 cos mu_j", 64, "max(1,||M||)", f.name, rep.trace_cubic_residual / (EPS * max(1, norm(M))),
         "M + 1e-8 N (non-symplectic)", maximum(abs.(sort(real.(rts)) - taus)) / (EPS * max(1, norm(M))))
    # F4: (K4) off-diagonal; defect: the reversed factor order M_eta M_zeta (the dossier's NEVER)
    sep = Octopus._canonical_separation(M, rep); ks = _st4_kappa_sep(sep, M)
    fac = Octopus._dispersion_factors(sep.zeta, sep.eta); Mrev = fac.M_eta * fac.M_zeta
    Mbar_rev = sinv(Mrev) * M * Mrev; off_rev = sqrt(norm(Mbar_rev[1:4, 5:6])^2 + norm(Mbar_rev[5:6, 1:4])^2)
    fam!("(K4) separation off-diagonal", Octopus._SEPARATION_RESIDUAL_MULTIPLIER, "max(1,||M||) ||M_cal|| ||M_cal^-1||", f.name, sep.off_diagonal_residual / (EPS * ks),
         "factor order reversed to M_eta M_zeta", off_rev / (EPS * ks))
    # F5: (K1) symplecticity of M_cal; defect: the pz row of M_zeta with the wrong sign
    Mz_bad = copy(fac.M_zeta); Mz_bad[6, 1:4] .= -Mz_bad[6, 1:4]; Mc_bad = Mz_bad * fac.M_eta
    fam!("(K1) M_cal symplecticity", 64, "||M_cal||^2", f.name, sep.symplecticity / (EPS * norm(sep.transformation)^2),
         "M_zeta pz-row sign flipped", Octopus._symplectic_defect(Mc_bad).frobenius / (EPS * norm(Mc_bad)^2))
    # F6: (K5) block symplecticity; defect: the non-symplectic M + 1e-8 N separated with the same triple
    sep_p = Octopus._canonical_separation(Mp, sep.zeta, sep.eta, sep.h)
    fam!("(K5) separated block symplecticity", 64, "||M||^2 ||M_cal||^2 ||M_cal^-1||^2", f.name, max(sep.transverse_symplecticity, sep.longitudinal_symplecticity) / (EPS * ks^2),
         "M + 1e-8 N (non-symplectic)", max(sep_p.transverse_symplecticity, sep_p.longitudinal_symplecticity) / (EPS * ks^2))
    # F7: (K9) U_6 reconstruction diag(R(mu_1), R(mu_2), R(mu_s)); defect: the two betatron tunes swapped
    ch = _st4_chain(M, sep.zeta, sep.eta, sep.h)
    kap_u = max(1, norm(M)) * norm(ch.optics.normalizer)^2
    bad = Octopus._full_normalizer_6d(sep, ch.frame.normalizer, ch.lon.normalizer, (ch.frame.tunes[2], ch.frame.tunes[1], ch.lon.tune))
    fam!("(K9) U_6 reconstruction (normalized)", 64, "max(1,||M||) ||U_6||^2", f.name, ch.optics.reconstruction.normalized / (EPS * kap_u),
         "betatron tunes swapped in the target rotation", bad.reconstruction.normalized / (EPS * kap_u))
    # F8: (K12) sums one and kappa_sz - h; defect: a vector scaled by 1.1 (normalization broken)
    kap_k = norm(ch.optics.normalizer)^2
    v = ch.optics.vectors; k11 = -imag(conj(1.1v[3][5]) * 1.1v[3][6])
    fam!("(K12) row/column sums and kappa_sz - h", 64, "||U_6||^2", f.name, max(maximum(abs, ch.optics.row_sums .- 1), maximum(abs, ch.optics.column_sums .- 1), abs(ch.optics.kappa_sz_minus_h)) / (EPS * kap_k),
         "longitudinal vector scaled by 1.1", abs(k11 - sep.h) / (EPS * kap_k))
    # F9: (M5) and (K13) are algebraic identities of ONE vector; the defect that can act is mixing modes: kappa of mode 2 with (beta, alpha, gamma) of mode 1
    u1 = v[1]; u2 = v[2]
    m5_bad = maximum(abs(abs2(u1[2a-1]) * abs2(u1[2a]) - real(conj(u1[2a-1]) * u1[2a])^2 - imag(conj(u2[2a-1]) * u2[2a])^2) for a in 1:3)
    fam!("(M5) beta gamma - alpha^2 - kappa^2 and (K13)", 64, "||U_6||^4", f.name, max(ch.optics.m5_residual, ch.optics.k13_residual) / (EPS * kap_k^2),
         "kappa of mode 2 combined with beta, alpha, gamma of mode 1", m5_bad / (EPS * kap_k^2))
    # F10: covariance closure M Sigma M' = Sigma; defect: the covariance of ANOTHER map (dense k = 3) closed under this M
    kap_c = max(1, norm(M))^2 * norm(ch.cov.sigma)
    chq = _st4_chain(fq.M, fq.zeta, fq.eta, fq.h)
    fam!("(K10) covariance closure", 64, "||M||^2 ||Sigma||", f.name, ch.cov.closure_residual / (EPS * kap_c),
         "Sigma of $(fq.name) under this M", norm(M * chq.cov.sigma * transpose(M) - chq.cov.sigma) / (EPS * kap_c))
    # F11: (K14) barred covariances; defect: eta with the sign flipped in the (K14) reassembly
    # (K14) is quadratic in eta (a sign flip is invisible): the defect that acts is eta scaled by 1.1
    cov_bad = Octopus._matched_covariance_6d(M, ch.optics, (1e-9, 2e-9, 3e-6), ch.frame.covariances, 1.1 * sep.eta)
    kap_14 = max(1, norm(ch.optics.normalizer))^2 * max(1, norm(sep.eta))^2
    fam!("(K14) barred covariance identity", 64, "max(1,||U_6||)^2 max(1,||eta||)^2", f.name, ch.cov.k14_residual / (EPS * kap_14), "eta scaled by 1.1 in (K14)", cov_bad.k14_residual / (EPS * kap_14))
    # F12: Ohmi (O2)-(O5); defect: h scaled by (1 + 1e-8) in the factor
    oh = dv(ch.ohmi); kap_o = max(1, norm(M)) * norm(oh.transformation)^2
    oh_bad = dv(Octopus._ohmi_factorization(M, sep.zeta, sep.eta, sep.h * (1 + 1e-8), sep.transformation, hcat(sep.zeta, sep.eta ./ sep.h)))
    fam!("Ohmi (O2)-(O5) identities", 64, "max(1,||M||) ||M_O||^2", f.name, max(oh.inverse_residual, oh.symplecticity, oh.separated_off_diagonal, oh.chart_change_off_diagonal, oh.graph_difference) / (EPS * kap_o),
         "h (1 + 1e-8) in (O2)", max(oh_bad.inverse_residual, oh_bad.symplecticity, oh_bad.separated_off_diagonal, oh_bad.chart_change_off_diagonal, oh_bad.graph_difference) / (EPS * kap_o))
    return nothing
end

function rejected_side_section_2(reports)
    # F13: coasting eta against the construction; defect: eta read off M[1:4, 6] without the (D24) solve
    fc = _st4_coasting(0.7); rc = reports[findfirst(r -> r.f.name == "coasting shear s=0.7", reports)]; c = rc.rep.coasting
    kap = max(1, norm(fc.M)) * max(1, norm(fc.eta))^2 * dv(c.coefficient_condition)
    fam!("coasting (D24) eta vs construction", 4, "max(1,||M||) max(1,||eta||)^2 cond(I - M_rr)", rc.f.name, norm(dv(c.eta) - fc.eta, Inf) / (EPS * kap),
         "eta = M[1:4, 6] (no (D24) solve)", norm(fc.M[1:4, 6] - fc.eta, Inf) / (EPS * kap))
    # F14: the shear (D25); defect: M[5, 6] alone taken as the shear
    fam!("coasting shear (D25)", 16, "max(1,||M||) max(1,||eta||)^2 cond", rc.f.name, abs(c.shear - fc.shear) / (EPS * kap), "shear = M[5, 6] alone", abs(fc.M[5, 6] - fc.shear) / (EPS * kap))
    # F15: trial-011 analytic eta_+; defect: the sign of k in the analytic formula
    kc = _st3_crab_kc(); k = kc * (1 - 1e-3); rk = reports[findfirst(r -> r.f.name == "trial-011 crab k=kc(1-0.001)", reports)]
    d = (cos(0.85) - cos(-0.75))^2 + k^2 * sin(0.85) * sin(-0.75); eta_plus = [0.0, -k * sin(-0.75), 0.0, 0.0] / (2sqrt(d))
    kap_d = max(1, norm(rk.f.M)) * max(1, norm(dv(rk.rep.graph)))^2 * (cos(0.85) - cos(-0.75))^2 / d
    fam!("trial-011 eta_+ analytic", 4096, "max(1,||M||) max(1,||D||)^2 (cos 0.85 - cos 0.75)^2 / d", rk.f.name, norm(dv(rk.rep.eta) - eta_plus, Inf) / (EPS * kap_d),
         "eta_+ with the sign of k flipped", norm(dv(rk.rep.eta) + eta_plus, Inf) / (EPS * kap_d))
    # F16: scaling back-transformation (E13) D_phys = C_r^-1 D C_l; defect: C_r D C_l^-1
    rp = reports[4]; f = rp.f; a = (2.0, 0.5, 4.0)
    Cr = Diagonal([a[1], 1 / a[1], a[2], 1 / a[2]]); Cl = Diagonal([a[3], 1 / a[3]]); C6 = Diagonal(vcat(diag(Cr), diag(Cl)))
    Ms = C6 * f.M * inv(C6); cls = _st4_clusters(Ms); reps = Octopus._dispersion_routes(Ms, cls; longitudinal=certified_index(cls, f.mu_s))
    Ds = dv(reps.graph); kap_s = max(1, norm(f.M)) * max(1, norm(f.zeta), norm(f.eta))^2 * cond(Matrix(C6))
    D_exact = hcat(f.zeta, f.eta ./ f.h)
    fam!("scaling back-transformation D_phys = C_r^-1 D C_l", 64, "max(1,||M||) max(1,||D||)^2 cond(C)", f.name * " scaled by (2, 0.5, 4)", norm(inv(Cr) * Ds * Cl - D_exact, Inf) / (EPS * kap_s),
         "C_r D C_l^-1 (exponents reversed)", norm(Cr * Ds * inv(Cl) - D_exact, Inf) / (EPS * kap_s))
    # F17: DBA coasting eta against the closed-orbit central difference (FD tolerance 4 step^2 + 1e-12 / step); defect: a one-sided difference
    NST = 4; ORDER = 4
    bend = compile_runtime(SBendSpec(L=1.0, h=0.2, b0=0.2, nst=NST, integrator_order=ORDER))
    qf = compile_runtime(QuadrupoleSpec(L=0.35, kn=(0.0, 1.5), nst=NST, integrator_order=ORDER))
    qd = compile_runtime(QuadrupoleSpec(L=0.25, kn=(0.0, -1.1), nst=NST, integrator_order=ORDER))
    dr = compile_runtime(DriftSpec(L=0.6)); cell = (qd, dr, bend, dr, qf, dr, bend, dr, qd)
    lin = one_turn_matrix(cell); Mdba = lin.matrix; cld = _st4_clusters(Mdba); repd = Octopus._dispersion_routes(Mdba, cld)
    function closed_orbit(delta)
        x = zeros(4); best = (Inf, x)
        for it in 1:12
            l = one_turn_matrix(cell; point=(x[1], x[2], x[3], x[4], 0.0, delta))
            r4 = collect(l.provenance.fixed_point_residual)[1:4]; rn = maximum(abs, r4)
            rn < best[1] && (best = (rn, copy(x))); rn == 0.0 && break
            x = x - (l.matrix[1:4, 1:4] - I) \ r4
        end
        return best
    end
    step = 1e-4; xp = closed_orbit(step); xm = closed_orbit(-step); x0 = closed_orbit(0.0)
    eta_fd = (xp[2] - xm[2]) / (2step); eta_one = (xp[2] - x0[2]) / step; tol = 4 * step^2 + 1e-12 / step
    eta_c = dv(repd.coasting.eta)
    RESULTS["dba"] = (holds=repd.coasting.holds, margin=repd.coasting.margin, eta=eta_c, eta_fd=eta_fd, eta_one=eta_one, tol=tol, step=step,
                      orbit_residuals=(xp[1], xm[1], x0[1]), diff=norm(eta_fd - eta_c, Inf), diff_one=norm(eta_one - eta_c, Inf), name="DBA cell dba_cell(1.5, -1.1) at delta = +-$(step)")
    fam!("DBA coasting eta vs closed-orbit central difference", 1, "FD tolerance 4 step^2 + 1e-12 / step = $(e2(tol)) (absolute)", RESULTS["dba"].name, norm(eta_fd - eta_c, Inf) / tol,
         "one-sided difference (x(+step) - x(0)) / step", norm(eta_one - eta_c, Inf) / tol)
    return nothing
end
function print_families()
    pr("\n## 3. The rejected side of every `c eps kappa` check family (ratio to eps kappa; the test's c beside it)\n")
    pr("| family | test c | kappa | legitimate fixture | ratio (green) | injected defect | ratio (red) | red > c |")
    pr("|---|---|---|---|---|---|---|---|")
    for fm in FAMILIES
        pr("| $(fm.name) | $(fm.c) | $(fm.kappa) | $(fm.legit_name) | $(e2(fm.legit)) | $(fm.defect_name) | $(e2(fm.defect)) | $(fm.defect > fm.c) |")
    end
    pr("\n- families whose legitimate ratio is below the test's c and whose defect ratio is above it: $(count(fm -> fm.legit <= fm.c && fm.defect > fm.c, FAMILIES))/$(length(FAMILIES)).")
end

# =====================================================================================================
# Section 4: paper cross-checks (trial-011 crab eta_+, the N15 / N17 controls, the DBA coasting eta).
# =====================================================================================================
function paper_section(reports)
    pr("\n## 4. Paper cross-checks\n")
    pr("### 4a. Trial-011 crab map M = diag(R(0.85), R(2.1), R(-0.75)) C_k, k = k_c (1 - eps), k_c = $(_st3_crab_kc())\n")
    pr("eta_+ = (0, -k sin(-0.75), 0, 0) / (2 sqrt d), d = (cos 0.85 - cos(-0.75))^2 + k^2 sin 0.85 sin(-0.75). kappa_d = max(1, ||M||) max(1, ||D||)^2 (cos 0.85 - cos 0.75)^2 / d. The (D12) sign: eta_x' > 0 both in the routes and in the formula (no flip).\n")
    pr("| eps | k | d | |eta - eta_+| / (eps kappa_d) | eta_x' (routes) | eta_x' (formula) | h | statuses | agreement / (eps kappa_d) | cond eigenplane | cond projector | fixed point |")
    pr("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for e in (1e-1, 1e-2, 1e-3, 1e-4, 1e-5, 1e-6)
        rp = reports[findfirst(r -> r.f.name == "trial-011 crab k=kc(1-$(e))", reports)]; rep = rp.rep; k = _st3_crab_kc() * (1 - e)
        d = (cos(0.85) - cos(-0.75))^2 + k^2 * sin(0.85) * sin(-0.75); eta_plus = [0.0, -k * sin(-0.75), 0.0, 0.0] / (2sqrt(d))
        kap = max(1, norm(rp.f.M)) * max(1, norm(dv(rep.graph)))^2 * (cos(0.85) - cos(-0.75))^2 / d
        ag = isempty(rep.agreement) ? 0.0 : maximum(max(a.zeta, a.eta, a.h) for a in rep.agreement)
        fp = route(rep, :fixed_point)
        pr("| $(e) | $(round(k; digits=10)) | $(e2(d)) | $(e2(norm(dv(rep.eta) - eta_plus, Inf) / (EPS * kap))) | $(e2(dv(rep.eta)[2])) | $(e2(eta_plus[2])) | $(e2(dv(rep.h))) | $(join(short.([r.status for r in rep.routes]), " ")) | $(e2(ag / (EPS * kap))) | $(condstr(route(rep, :eigenplane))) | $(condstr(route(rep, :projector))) | $(fp.iterations) it, $(occursin("contraction ratio", fp.detail) ? "ratio " * split(split(fp.detail, "sigma_min(op) = ")[2], ";")[1] : "-") |")
    end
    pr("\n### 4b. N15 indefinite control diag(R(0.73), R(1.41), R(-0.73)) (default rule)\n")
    g = RESULTS["guard N15 indefinite diag(R(0.73), R(1.41), R(-0.73))"]
    pr("- clusters: $(join([string(c.classification, " (", c.reason, ", pairs ", length(c.half_members), ")") for c in g.cl.clusters], "; ")); coasting holds: $(g.rep.coasting.holds) (margin $(e2(g.rep.coasting.margin))).")
    pr("- route statuses: $(join(string.([r.status for r in g.rep.routes]), ", ")); report eta: $(st(g.rep.eta)); labels: $(st(g.rep.labels)); longitudinal index $(g.rep.longitudinal) (cluster $(g.rep.longitudinal_cluster)).")
    pr("\n### 4c. N16 / N17 degeneracy rejection (theory 13.7): Md = diag(R(0.73), R(1.41), R(0.73)), the false graph, the crab products\n")
    gd = RESULTS["guard degenerate diag(R(0.73), R(1.41), R(0.73))"]; gf = guard_fixtures()
    poly = gd.rep.matrix * gd.rep.matrix - dv(gd.rep.tau_s) * gd.rep.matrix + I
    kern = norm(poly * vcat(gf.Dfalse, Matrix(1.0I, 2, 2))); rr = Octopus._route_residuals(gd.rep.matrix, gf.Dfalse, 2cos(0.73))
    pr("- Md route statuses: $(join(string.([r.status for r in gd.rep.routes]), ", ")); eta $(st(gd.rep.eta)) (an ambiguity set: $(gd.rep.eta.set === nothing ? "none" : string(typeof(gd.rep.eta.set)))); tau_s residual $(e2(abs(dv(gd.rep.tau_s) - 2cos(0.73)))); cubic residual $(e2(gd.rep.trace_cubic_residual)).")
    pr("- false graph [diag(1, -0.5); 0]: polynomial kernel residual ||(M^2 - tau M + I)[D; I]|| = $(e2(kern)) (zero), (I1) raw residual $(e2(rr.invariance.raw)) vs the theory's 1.5 sqrt(2) sin 0.73 = $(e2(1.5 * sqrt(2) * sin(0.73))); normalized $(e2(rr.invariance.normalized)).")
    z = RESULTS["zero graph raw residual on crab similarity"]
    pr("- zero (pseudoinverse) graph on C_k Md C_k^-1 (k = 0.3): raw residual $(e2(z.raw)) vs the design's sqrt(2) k sin 0.73 = $(e2(z.design)) (difference $(e2(abs(z.raw - z.design)))).")
    gk = RESULTS["guard degenerate Md C_k (k=0.3)"]; gks = RESULTS["guard crab similarity C_k Md C_k^-1 (k=0.3)"]
    pr("- Md C_k statuses: $(join(string.([r.status for r in gk.rep.routes]), ", ")); C_k Md C_k^-1 statuses: $(join(string.([r.status for r in gks.rep.routes]), ", ")); eta $(st(gks.rep.eta)).")
    pr("\n### 4d. DBA cell (benchmark 12.2-3): coasting eta against the closed-orbit central difference\n")
    d = RESULTS["dba"]
    pr("- $(d.name): coasting holds $(d.holds) (margin $(e2(d.margin))); eta_x = $(e2(d.eta[1])) (stage 1 record x_co / delta = 0.706); closed-orbit residuals at +step, -step, 0: $(join(e2.(d.orbit_residuals), ", ")).")
    pr("- central difference eta_fd,x = $(e2(d.eta_fd)); |eta_fd - eta_x| = $(e2(d.diff)); FD tolerance 4 step^2 + 1e-12 / step = $(e2(d.tol)) (step^2 truncation of the orbit's second derivative ~ 1 plus roundoff 1e-12 / step); ratio $(e2(d.diff / d.tol)). One-sided difference: |eta_one - eta_x| = $(e2(d.diff_one)) (ratio $(e2(d.diff_one / d.tol)), rejected).")
end

function main()
    oracle = load_oracle_maps(ORACLE_TSV); ref = load_reference(REF_TSV)
    dump_log = joinpath(@__DIR__, "reference", "twiss_oracle_reference_provenance.txt")   # the reference dump's log (seed, python / numpy / scipy, the helper's sha256, the check_map counts)
    pr("# Stage 4a measurement table (Part D1)\n")
    pr("Produced by $(basename(@__FILE__)) (package mode, main tree). Julia $(VERSION); threads $(Threads.nthreads()); seed $(_ST4_SEED); oracle TSV $(relp(ORACLE_TSV)); reference TSV $(relp(REF_TSV)).")
    isfile(dump_log) && pr("Reference dump: " * join(strip.(readlines(dump_log)[end-2:end]), " / "))
    pr("Source constants at run time: c_graph = $(Octopus._GRAPH_SINGULARITY_MULTIPLIER), c_iso = $(Octopus._ISOTROPY_MULTIPLIER), c_coef = $(Octopus._COEFFICIENT_CONDITION_MULTIPLIER), c_inv = $(Octopus._ROUTE_INVARIANCE_MULTIPLIER), c_stop = $(Octopus._ITERATION_STOP_MULTIPLIER), c_coast = $(Octopus._COASTING_MULTIPLIER), c_tie = $(Octopus._LABEL_TIE_MULTIPLIER), c_sep = $(Octopus._SEPARATION_RESIDUAL_MULTIPLIER), c_triple = $(Octopus._TRIPLE_CONSISTENCY_MULTIPLIER), c_ell = $(Octopus._LONGITUDINAL_ELLIPTIC_MULTIPLIER), c_ohmi = $(Octopus._OHMI_POSITIVITY_MULTIPLIER), _MAX_HALVINGS = $(Octopus._MAX_HALVINGS), _FIXED_POINT_MAX_ITERATIONS = $(Octopus._FIXED_POINT_MAX_ITERATIONS). Every fixture name in this file is produced by the code that built the fixture; none is typed into the text.")
    rows = oracle_section(oracle, ref); certified_section(oracle, ref, rows)
    reports = part_a_collection(); part_b_collection(reports)
    multiplier_section(reports)
    rejected_side_section(reports); rejected_side_section_2(reports); print_families()
    paper_section(reports)
    mkpath(dirname(abspath(OUT_MD)))
    open(OUT_MD, "w") do io; for l in LINES; println(io, l); end; end
    println("wrote $(OUT_MD): $(length(LINES)) lines")
    for (k, w) in sort(collect(WINDOWS); by=first); println("window $(k): [$(e2(w.lo)), $(e2(w.hi))] $(w.empty ? "EMPTY" : "inside " * string(w.inside)) (source $(w.current))"); end
end
main()
