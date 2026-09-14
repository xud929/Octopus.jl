"""
Twiss and dispersion identities of the theory note, checked through `analyze`
on manufactured and lattice fixtures; the expected diagnostics; the
declaring kinds' examples. This script is the validation twin of
`TwissDispersionIdentityContract` (src/contracts/twiss_dispersion_identity.jl):
it runs the contract ONCE and prints its identity table, so the suite's
contract and this record are one source of truth.

Reference model
---------------
The tagged identities of docs/theory/twiss_dispersion.md Sections 3, 6, 8
and 9 ((E7), (E8), (M2)-(M5), (D3), (D8), (D14), (D17), (D24), (K1), (K4),
(K5), (K7), (K8), (K12)-(K14), (O1)-(O5), (X2)) and the design note's
verification table (docs/design/twiss_dispersion_analysis.md, "Verification
plan"), each evaluated on the result of `analyze`: the reported residual
triples re-judged on their values, the kernel residuals the analysis computes
but does not surface, and the identities the contract recomputes in the
caller's coordinates (scaling invariance among them). No external code.

Error metric
------------
- per identity: the largest value / (c eps kappa) ratio over the fixtures it
  ran on, with kappa the conditioning of the quantity compared and c the
  contract's multiplier, measured in two CPU arms (native and
  `OPENBLAS_CORETYPE=Haswell julia -C haswell`) and frozen at a power of two
  at least ten times the larger measured ratio; a ratio above 1 fails. The
  multipliers are FROZEN on the contract's default fixture set: the lattice
  fixtures plus 20 dense 6x6 and 5 dense 4x4 maps at seed 20260911
  (`_default_identity_multipliers` and the struct defaults `dense_maps = 20`,
  `dense_maps_4d = 5` in src/contracts/twiss_dispersion_identity.jl), while
  this script runs 200 + 20 dense maps by default (`IDENT_MAPS`,
  `IDENT_MAPS4` below), so it reports ratios the freezing never saw, and a
  ratio above 1 on any of them fails the script at the gate line at the end
  of this file;
- the two normalizer metrics: the analysis's own `U_6 reconstruction` and
  `U_6 symplecticity` residuals at multiplier 1, value / rho_M1 and
  value / (rho_M1 cond(U_6)), the largest over the fixtures (contract
  `_identity_contract_reported_rows!`), which the suite pins below the
  multipliers of the `r_u6_reconstruction` and `r_u6_symplecticity` rows;
  printed and written here beside the identity rows, not gated;
- the silent-diagnostic arm: every fixture whose status or reason must fire
  (unstable spectrum, unresolved and indefinite clusters, the h = 0
  projection, the coasting structure, the uncertified heuristic, the
  non-symplectic must-reject map, the displaced closed orbit) is counted;
  a diagnostic that stays silent fails;
- the kind sweep: every element kind declaring the analysis analyzes its own
  metadata example or refuses it for the documented closed-orbit reason.

Fixtures
--------
The DBA cell (as an element tuple and as a `BeamLine`), the detuned FODO,
DBA + RF, DBA + RF + thin crab, manufactured dense 6x6 and 4x4 maps
(`exp(S H)`, seed below), the manufactured coasting map, the diagnostic
fixtures of the design's verification table, the declaring kinds' examples.

Outputs (under `result/`)
-------------------------
`twiss_dispersion_identities.tsv` -- one row per identity: slug, max ratio,
max value, multiplier, the fixture that attained the maximum; then the two
normalizer rows `normalizer_u6_reconstruction` and
`normalizer_u6_symplecticity` (the metric as max ratio, NaN as max value,
the suite's pin as multiplier, "analysis normalizer" as argmax).
Printed: one `TW-IDENT` line per identity in stable order, two
`TW-NORMALIZER` lines, `TW-DIAG`, `TW-KINDS`, and one `TW-DIGEST` line (the
profiling drivers' rotate-then-xor bitwise digest of the maxima vector of the
identity rows only), so two checkouts or two CPU arms can be diffed.

Run
---
    julia --project=. validation/twiss_dispersion_identities.jl

Environment
-----------
    OCTOPUS_TWISS_IDENTITY_SEED    seed of the manufactured maps (default 20260911)
    OCTOPUS_TWISS_IDENTITY_MAPS    dense 6x6 maps (default 200; the contract's suite default is 20)
    OCTOPUS_TWISS_IDENTITY_MAPS4   dense 4x4 maps (default 20; the contract's suite default is 5)
"""

# Guarded like every other script in `validation/`: without it this file
# cannot be `include`d after any sibling in one process (the audit harnesses
# drive them that way); `@__DIR__` rather than a cwd-relative path.
if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using LinearAlgebra
using Printf

# Test hook: when `Main.IDENT_DRY_RUN` is defined (a scratch driver defines
# it before `include`-ing this file), only the constants and the
# function definitions below are evaluated; the single `validate` call, the
# printing, the TSV and the gate at the end of the file are skipped, so the
# reporting code can be exercised on a fake result without the contract.
const IDENT_DRY_RUN = isdefined(Main, :IDENT_DRY_RUN)

const IDENT_SEED  = parse(Int, get(ENV, "OCTOPUS_TWISS_IDENTITY_SEED",  "20260911"))
const IDENT_MAPS  = parse(Int, get(ENV, "OCTOPUS_TWISS_IDENTITY_MAPS",  "200"))
const IDENT_MAPS4 = parse(Int, get(ENV, "OCTOPUS_TWISS_IDENTITY_MAPS4", "20"))

# The two normalizer metrics reported beside the identity rows: printed label,
# metric key (contract `_identity_contract_reported_rows!`: the analysis's
# U_6 residual at multiplier 1, value / rho_M1 and value / (rho_M1 cond(U_6)),
# the largest over the fixtures), and the identity row whose multiplier the
# suite pins the metric against (test/runtests.jl, the stage 6 testset). The
# contract records no raw value and no argmax for them.
const _IDENT_NORMALIZER_ROWS = (
    ("u6_reconstruction", :normalizer_ratio_u6_reconstruction, :r_u6_reconstruction),
    ("u6_symplecticity",  :normalizer_ratio_u6_symplecticity,  :r_u6_symplecticity),
)

"""
    identity_slugs(result, slugs) -> Vector{Symbol}

The identity slugs in STABLE order (sorted by string), each checked to own
its three metric keys of the H7 convention: `max_<slug>` (the largest
value / tolerance ratio), `maxval_<slug>` (the largest raw value) and
`argmax_<slug>` (the fixture that attained it). A slug without all three
keys is an error naming the key: a row the contract never wrote would
otherwise print as a blank and look green.
"""
function identity_slugs(result, slugs)
    ordered = sort!(Symbol[Symbol(s) for s in slugs]; by=string)
    for slug in ordered, prefix in ("max_", "maxval_", "argmax_")
        key = Symbol(prefix, slug)
        haskey(result.metrics, key) ||
            error("identity row $slug has no metric $key: the contract did not write the row")
    end
    return ordered
end

"""
    identity_digest(result, slugs) -> UInt64

The profiling drivers' order-sensitive rotate-then-xor digest
(profiling/benchmark_track_cpu.jl `coordinate_digest`) over the `maxval_`
values in slug order. Bitwise: two checkouts or two CPU arms that agree on
every maximum agree on the digest; a differing digest is a diff to look at,
not a failure (the TW-IDENT ratios carry the judgement).
"""
function identity_digest(result, slugs)
    h = UInt64(0)
    for slug in slugs
        v = result.metrics[Symbol("maxval_", slug)]
        h = (h << 1) | (h >> 63)
        h = xor(h, reinterpret(UInt64, Float64(v)))
    end
    return h
end

"""
    report_identities(result, io; multipliers, slugs, seed, maps, maps4)

Print the contract's identity table from `result.metrics` (any object with
`.metrics`, `.status`, `.message` and `.residual`): one `TW-IDENT` line per
slug in stable order, then one `TW-NORMALIZER` line per entry of
`_IDENT_NORMALIZER_ROWS` (`ratio=` the metric, `c=` the suite's pin; NaN
when the result lacks the key), then `TW-DIAG`, `TW-KINDS`, `TW-DIGEST`, the
status and the message. `multipliers` is the contract's `c` per slug (the
contract owns it; the result does not carry it). Returns the digest, which
is over the identity rows only.
"""
function report_identities(result, io::IO; multipliers, slugs,
                           seed::Integer=IDENT_SEED, maps::Integer=IDENT_MAPS,
                           maps4::Integer=IDENT_MAPS4)
    ordered = identity_slugs(result, slugs)
    m = result.metrics
    for slug in ordered
        haskey(multipliers, slug) ||
            error("identity row $slug has no multiplier in the contract")
        @printf(io, "TW-IDENT %-40s max=%.6e ratio=%.6e c=%g argmax=%s\n",
                String(slug), Float64(m[Symbol("maxval_", slug)]),
                Float64(m[Symbol("max_", slug)]), Float64(multipliers[slug]),
                string(m[Symbol("argmax_", slug)]))
    end
    # The normalizer metrics are reported, not gated, and they are NOT inputs
    # of `identity_digest`: TW-DIGEST stays a digest of the identity rows only,
    # unchanged by this block. `get` with NaN: a result without the keys (a
    # fake one under IDENT_DRY_RUN) prints NaN rather than throwing.
    for (label, key, cslug) in _IDENT_NORMALIZER_ROWS
        @printf(io, "TW-NORMALIZER %-17s ratio=%.6e c=%g\n", label,
                Float64(get(m, key, NaN)), Float64(get(multipliers, cslug, NaN)))
    end
    silent_names = get(m, :diagnostics_silent_names, String[])
    @printf(io, "TW-DIAG expected=%d silent=%d [%s]\n",
            get(m, :diagnostics_expected, 0), get(m, :diagnostics_silent, 0),
            join(string.(silent_names), ", "))
    @printf(io, "TW-KINDS declaring=%d analyzed=%d refused=%d failed_example=%d without_result=%d without_example=%d\n",
            get(m, :kinds_declaring, 0), get(m, :kinds_analyzed, 0),
            get(m, :kinds_refused, 0), get(m, :kinds_failed_example, 0),
            get(m, :kinds_declaring_without_result, 0), get(m, :kinds_without_example, 0))
    digest = identity_digest(result, ordered)
    @printf(io, "TW-DIGEST 0x%016x  (%d identities, seed %d, maps %d + %d)\n",
            digest, length(ordered), seed, maps, maps4)
    println(io, "status = ", result.status)
    println(io, "message = ", result.message)
    return digest
end

"""
    write_identities_tsv(result, path; multipliers, slugs)

One row per identity slug in stable order under the header
`identity\\tmax_ratio\\tmax_value\\tmultiplier\\targmax`, plus the two
normalizer rows of `_IDENT_NORMALIZER_ROWS` after them (`identity` =
`normalizer_<label>`, `max_ratio` the metric, `max_value` NaN because the
contract records the ratio only, `multiplier` the suite's pin, `argmax`
"analysis normalizer" because the contract records no fixture for them).
Creates the directory of `path`. Returns the number of rows written
(identities plus normalizer rows).
"""
function write_identities_tsv(result, path::AbstractString; multipliers, slugs)
    ordered = identity_slugs(result, slugs)
    m = result.metrics
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "identity\tmax_ratio\tmax_value\tmultiplier\targmax")
        for slug in ordered
            @printf(io, "%s\t%.8e\t%.8e\t%g\t%s\n", String(slug),
                    Float64(m[Symbol("max_", slug)]), Float64(m[Symbol("maxval_", slug)]),
                    Float64(multipliers[slug]), string(m[Symbol("argmax_", slug)]))
        end
        for (label, key, cslug) in _IDENT_NORMALIZER_ROWS
            @printf(io, "normalizer_%s\t%.8e\t%.8e\t%g\t%s\n", label,
                    Float64(get(m, key, NaN)), NaN,
                    Float64(get(multipliers, cslug, NaN)), "analysis normalizer")
        end
    end
    return length(ordered) + length(_IDENT_NORMALIZER_ROWS)
end

# ---------------------------------------------------------------------------
# The run: ONE validate. The script prints the contract's metrics; it does not
# re-run fixtures (the contract and this record are one source of truth).
# Skipped under the IDENT_DRY_RUN test hook documented above.
# ---------------------------------------------------------------------------
if !IDENT_DRY_RUN
    contract = TwissDispersionIdentityContract(seed=UInt64(IDENT_SEED),
                                               dense_maps=IDENT_MAPS,
                                               dense_maps_4d=IDENT_MAPS4)
    slugs = Octopus._IDENTITY_CONTRACT_SLUGS
    result = validate(contract)

    report_identities(result, stdout; multipliers=contract.multipliers, slugs=slugs)

    resultdir = normpath(joinpath(@__DIR__, "..", "result"))
    mkpath(resultdir)
    tsv = joinpath(resultdir, "twiss_dispersion_identities.tsv")
    nrows = write_identities_tsv(result, tsv; multipliers=contract.multipliers, slugs=slugs)
    println("TSV written to result/twiss_dispersion_identities.tsv ($nrows rows: ",
            length(slugs), " identities + ", length(_IDENT_NORMALIZER_ROWS), " normalizer)")

    # Gate, not just print: a :failed contract must exit non-zero here (the
    # message names the first failing row, diagnostic or kind).
    result.status === :passed || error(result.message)
    println("twiss identities: ", result.metrics[:identities],
            " identities certified on ", result.metrics[:fixtures],
            " fixture runs; worst ratio ", result.metrics[:worst_ratio])
end
