# Generate the MAD-X survey reference table that MADXSurveyConsistencyContract
# checks against.
#
# Reference model
# ---------------
# MAD-X `SURVEY` over LINE definitions expanded by `USE`: the `S` column is
# end-of-element arc length, the same summed-`L` arc the Octopus survey walker
# computes, and the expansion of nesting/repetition/reflection is MAD-X's own
# (`-half` reverses; sub-lines expand recursively). Each case below is the
# hand-written twin of a fixture in `_madx_survey_reference_lines()`
# (src/contracts/Contracts.jl); the twinning is by eye, and the contract's
# element-for-element comparison is what keeps the two honest.
#
# Conventions pinned by construction rather than compared:
# * bends state their ARC length (`SBEND, L=` is arc in MAD-X, as is
#   Octopus's `SBendSpec`);
# * rbend content is emitted as SBEND + explicit half-angle face angles,
#   because MAD-X's RBEND (default RBARC=true) treats the stated L as the
#   CHORD and surveys the computed arc (measured on 5.03.06: L=2, angle=0.5
#   surveys 2.020986251), while Octopus's RBendSpec takes L as the arc;
# * RFCAVITY carries its L as drift space in both codes; frequency is MHz in
#   MAD-X and Hz in Octopus, irrelevant to the survey.
#
# Error metric: none here — this script only RECORDS MAD-X's expansion. The
# comparison (atol 1e-12 on L, s_end, and total per element) lives in the
# contract.
#
# Inputs:  a `madx` binary on PATH.
# Outputs: validation/reference/survey_madx_<version>.tsv
# Run:     julia --project=. validation/generate_madx_survey_reference.jl

const DECKS = Dict{String,String}(
    "flat_fodo" => """
        qf: quadrupole, l = 0.45, k1 = 0.31;
        qd: quadrupole, l = 0.45, k1 = -0.29;
        d1: drift, l = 1.15;
        d2: drift, l = 0.35;
        sx: sextupole, l = 0.18, k2 = 1.1;
        b1: sbend, l = 2.2, angle = 0.12;
        flat_fodo: line = (qf, d2, sx, d1, b1, d1, qd, d2);
        """,
    "nested_reflected" => """
        qf: quadrupole, l = 0.45, k1 = 0.31;
        qd: quadrupole, l = 0.45, k1 = -0.29;
        d1: drift, l = 1.15;
        b1: sbend, l = 2.2, angle = 0.12;
        cell: line = (qf, d1, b1, d1, qd);
        half: line = (cell, cell, b1);
        nested_reflected: line = (half, -half);
        """,
    "curved_heavy" => """
        d1: drift, l = 1.15;
        d2: drift, l = 0.35;
        b7: sbend, l = 2.2, angle = 0.7;
        curved_heavy: line = (b7, d2, b7, d1, b7);
        """,
    "rbend_faces" => """
        d1: drift, l = 1.15;
        rbf: sbend, l = 2.0, angle = 0.5, e1 = 0.25, e2 = 0.25;
        rbend_faces: line = (d1, rbf, d1);
        """,
    "with_cavity" => """
        dc3: drift, l = 3.0;
        dc5: drift, l = 5.0;
        dc14: drift, l = 1.4;
        cv6: rfcavity, l = 0.6, volt = 1.0, freq = 2.99792458;
        cv0: rfcavity, l = 0, volt = 1.0, freq = 2.99792458;
        with_cavity: line = (dc3, cv6, dc5, cv0, dc14);
        """,
)

function parse_survey_tfs(path)
    rows = NamedTuple{(:name, :keyword, :s, :l),Tuple{String,String,Float64,Float64}}[]
    cols = String[]
    for line in eachline(path)
        startswith(line, "@") && continue
        if startswith(line, "*")
            cols = split(line)[2:end]
            continue
        end
        startswith(line, "\$") && continue
        f = split(line)
        isempty(f) && continue
        d = Dict(zip(cols, f))
        name = strip(d["NAME"], '"')
        (endswith(name, "\$START") || endswith(name, "\$END")) && continue
        push!(rows, (name=name, keyword=strip(d["KEYWORD"], '"'),
                     s=parse(Float64, d["S"]), l=parse(Float64, d["L"])))
    end
    return rows
end

function main()
    dir = mktempdir()
    version = "unknown"
    out = IOBuffer()
    for case in sort!(collect(keys(DECKS)))
        deck = joinpath(dir, "$case.madx")
        tfs = joinpath(dir, "$case.tfs")
        write(deck, DECKS[case] * """
            beam;
            use, period = $case;
            survey, file = "$tfs";
            stop;
            """)
        log = read(pipeline(`madx $deck`; stdin=devnull), String)
        m = match(r"MAD-X (\d+\.\d+\.\d+)", log)
        m === nothing || (version = m.captures[1])
        occursin("finished normally", log) ||
            error("MAD-X did not finish normally for $case:\n$(last(log, 2000))")
        for (i, r) in enumerate(parse_survey_tfs(tfs))
            println(out, join((case, i, r.name, r.keyword, r.l, r.s), '\t'))
        end
    end
    ref = normpath(joinpath(@__DIR__, "reference", "survey_madx_$(version).tsv"))
    open(ref, "w") do io
        println(io, "# MAD-X survey reference for MADXSurveyConsistencyContract")
        println(io, "# MAD-X version: $version")
        println(io, "# generated: $(basename(@__FILE__)), see its header for the model")
        println(io, "case\tidx\tname\tkeyword\tL\ts_end")
        write(io, take!(out))
    end
    println("wrote $ref")
end

main()
