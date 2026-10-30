# Focused particle-tune metadata/contract and unchanged-neighbour checks.
# Run sequentially after every other Julia probe has finished:
#   julia --startup-file=no --project=. --threads=4 docs/history/audit_particle_tunes_2026_10_30_unit_reports/U2_checks.jl
# This is a focused runner, not a fast/full suite. It evaluates selected
# existing suite testsets from the current repository source, preserving the
# original source filename and line numbers for __DIR__ and failure reports.
# No MPI is imported here: actual launcher tests remain a separate obligation.
using Octopus, Test, LinearAlgebra, Random, Logging, InteractiveUtils

const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
CUDA_TESTS_ACTIVE || error("this focused run requires active CUDA; no device checks may be silently skipped")
Threads.nthreads(:default) >= 4 || error("run this focused check with --threads=4")
const PT_METADATA_ROOT = pkgdir(Octopus)
const PT_METADATA_SUITE_PATH = joinpath(PT_METADATA_ROOT, "test", "runtests.jl")
const PT_METADATA_SUITE_TEXT = read(PT_METADATA_SUITE_PATH, String)
# Load the feature's actual independent oracle and Main fixture ops before the
# reflected type censuses, as the full suite does.
include(joinpath(PT_METADATA_ROOT, "test", "particle_tunes_probe.jl"))

function pt_run_suite_testset(title)
    marker = "@testset " * repr(title) * " begin"
    matches = findall(marker, PT_METADATA_SUITE_TEXT)
    length(matches) == 1 || error("expected exactly one suite testset named " * title)
    first_byte = first(only(matches))
    expression, after = Meta.parse(PT_METADATA_SUITE_TEXT, first_byte; raise=true)
    expression isa Expr && expression.head === :macrocall || error("selected block is not a testset")
    prefix = SubString(PT_METADATA_SUITE_TEXT, firstindex(PT_METADATA_SUITE_TEXT), prevind(PT_METADATA_SUITE_TEXT, first_byte))
    line = count(==('\n'), prefix) + 1
    body = SubString(PT_METADATA_SUITE_TEXT, first_byte, prevind(PT_METADATA_SUITE_TEXT, after))
    println("FOCUSED-TESTSET begin title=", repr(title), " suite_line=", line)
    started = time()
    Base.include_string(Main, repeat("\n", line - 1) * body, PT_METADATA_SUITE_PATH)
    println("FOCUSED-TESTSET passed title=", repr(title), " seconds=", time() - started)
end

@testset "Particle-tune focused configuration and help" begin
    metadata = validate_element_metadata()
    @test metadata.passed
    @test metadata.default_pairs == metadata.defaults_checked
    @test metadata.runtime_variant_pairs == metadata.runtime_variants_checked
    @test validate_configuration_metadata()
    @test Set(runtime_variants(:linear6d, Symplectic6DMap)) == Set((Linear6D, ParticleLinear6D))
    @test Set(row.runtime for row in runtime_examples(:linear6d)) == Set((Linear6D, ParticleLinear6D))
    for query in (:linear6d, Linear6DSpec)
        io = IOBuffer()
        element_help(query; io=io)
        help = String(take!(io))
        @test occursin("particle_tunes", help)
        @test occursin("rng_id", help)
        @test occursin("ParticleLinear6D", help)
        @test occursin("Linear6D", help)
    end
    println("PARTICLE-TUNES-METADATA defaults=", metadata.defaults_checked,
            " variants=", metadata.runtime_variants_checked)
end

# Remove just the requested nuy group. The production helper's independent
# oracle must detect both the missing selected-plane effect and its receipt.
# All helper inputs are per-plane groups, so this deliberately preserves every
# other source and every other option rather than inducing a malformed input.
function pt_ignore_vertical_override(spec)
    source = getparam(spec, :particle_tunes, nothing)
    source === nothing && return spec
    any(g -> :nuy in g.planes, source.groups) || return spec
    kept = Tuple(g for g in source.groups if !(:nuy in g.planes))
    copied = copy(params(spec))
    copied[:particle_tunes] = isempty(kept) ? nothing : Octopus._ParticleTuneSources(kept)
    return ElementSpec{:linear6d}(copied)
end

@testset "Particle-tune focused effectiveness and failing controls" begin
    for backend in (CPUThreadsBackend, CUDABackend)
        result = Octopus._particle_tune_effectiveness(backend)
        @test result.passed
        @test result.metrics[:subsets_checked] == 7
        @test result.metrics[:receipts_checked] == 9
        @test result.metrics[:max_coordinate_error] <= result.metrics[:coordinate_tolerance]
        println("PARTICLE-TUNES-EFFECT backend=", backend,
                " subsets=", result.metrics[:subsets_checked],
                " receipts=", result.metrics[:receipts_checked],
                " max_error=", result.metrics[:max_coordinate_error],
                " coordinate_bound=", result.metrics[:coordinate_tolerance],
                " source_movement=", result.metrics[:particle_tunes],
                " stream_movement=", result.metrics[:rng_id])
    end
    ignored = Octopus._particle_tune_effectiveness(CPUThreadsBackend;
        spec_transform=pt_ignore_vertical_override)
    @test !ignored.passed
    @test ignored.metrics[:subsets_checked] == 7
    @test occursin("did not reach every selected plane", ignored.message)
    @test ignored.metrics[:max_coordinate_error] > ignored.metrics[:coordinate_tolerance]
    println("PARTICLE-TUNES-NEGATIVE ignored_nuy verdict=", ignored.passed,
            " observed_error=", ignored.metrics[:max_coordinate_error], " reason=", ignored.message)
    receiptless = Octopus._particle_tune_effectiveness(CPUThreadsBackend;
        receipt_transform=receipts -> empty(receipts))
    @test !receiptless.passed
    @test receiptless.metrics[:subsets_checked] == 7
    @test receiptless.metrics[:receipts_checked] == 0
    @test occursin("missing unique particle-tune initialization receipt", receiptless.message)
    println("PARTICLE-TUNES-NEGATIVE dropped_receipts verdict=", receiptless.passed,
            " reason=", receiptless.message)
end

@testset "Particle-tune focused frozen-label symplecticity and variant coverage" begin
    result = validate(SymplecticityContract())
    @test result.passed
    @test result.metrics[:ParticleLinear6D_source_calls] == 1
    @test result.metrics[:runtime_variants_declaring_without_case] == 0
    @test result.metrics[:kinds_declaring_without_case] == 0
    println("PARTICLE-TUNES-SYMPLECTIC residual=", result.metrics[:ParticleLinear6D_residual],
            " source_calls=", result.metrics[:ParticleLinear6D_source_calls])
    # This is the same added-variant control committed in Contract coverage guards.
    meta = Octopus.ELEMENT_META_BY_KIND[:linear6d]
    saved = meta.runtime_variants[Symplectic6DMap]
    try
        meta.runtime_variants[Symplectic6DMap] = (saved..., Base.RefValue)
        failed = validate(SymplecticityContract())
        @test !failed.passed
        @test failed.metrics[:runtime_variants_declaring_without_case] == 1
        @test occursin("linear6d", failed.message)
        println("PARTICLE-TUNES-NEGATIVE uncovered_variant verdict=", failed.passed,
                " reason=", failed.message)
    finally
        meta.runtime_variants[Symplectic6DMap] = saved
    end
end

# These are the actual complete suite testsets, not copies of their assertions.
# Their helpers live inside the blocks. CUDA_TESTS_ACTIVE and the imports above
# supply the only surrounding suite bindings they require.
for title in (
    "Metadata queries and the validator check declarations, not themselves",
    "One rng_id policy: zero assigns a fresh stream everywhere, ids are UInt64, the registry warns on an explicit claim of an auto-assigned id and on cross-class sharing",
    "One precision rule: every element kind declares its beam type, a mismatched beam is refused by name on both backends, and every kind has a typed form",
    "Cross-backend rounding classes declared per kind and checked by measurement, and the marker completes the one precision rule",
    "No method grows a Core.Box outside the argued allowlist",
    "Every export is documented",
    "Every exported API name appears in the registry snapshot",
    "No docstring is detached by comment lines",
)
    pt_run_suite_testset(title)
end

println("PARTICLE-TUNES focused metadata checks passed cuda_active=", CUDA_TESTS_ACTIVE,
        " threads=", Threads.nthreads(:default))
println("FOCUSED-OWES: fast and full suites; generated snapshot equality; full PublicConfigurationEffectivenessContract and ElementParameterEffectivenessContract; actual MPI launchers; standalone symplecticity/backend/particle-tune validation scripts; long-line allocation neighbours; final-tree CUDA gate")
