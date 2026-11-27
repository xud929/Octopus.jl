# core.jl: suite units moved from runtests.jl by test/move_testsets.jl

@testset "CUDA coverage status" begin
    # The files carrying CUDABackend code, DERIVED from the tree for the banner
    # below (2026-10-18 audit F-146/U28-1: the hand list said "Twelve" while
    # thirteen did, `Tasks.jl` missing; the list before it named only the
    # three *_cuda.jl solvers, 2026-08-05_b audit U17b-6). The scan is shown
    # to see the tree: every `*_cuda.jl` file is in it, in both branches.
    cuda_src_root = joinpath(pkgdir(Octopus), "src")
    cuda_src_files = [relpath(joinpath(root, f), cuda_src_root) for (root, _, files) in walkdir(cuda_src_root)
                      for f in files if endswith(f, ".jl")]
    cuda_files = sort!(filter(f -> occursin("CUDABackend", read(joinpath(cuda_src_root, f), String)), cuda_src_files))
    @test !isempty(cuda_files)
    @test all(f -> f in cuda_files, filter(endswith("_cuda.jl"), cuda_src_files))
    if CUDA_TESTS_ACTIVE
        # Implied by the branch: `CUDA_TESTS_ACTIVE` IS
        # `_HAS_CUDA && CUDA.functional()` (2026-08-05_b audit, U17b-5). It
        # exists so this visibility testset is non-empty on a GPU host rather
        # than reporting zero assertions, which would read as "not run".
        @test Octopus.CUDA.functional()
    else
        # No count here on purpose. This message said "Nine" while the real
        # number had grown past twenty, because a hand-maintained tally of a set
        # that grows with every new CUDA testset has nothing to keep it honest
        # (2026-08-05_b audit, U20-11). The skipped testsets now announce
        # themselves individually in the summary's Broken column, which is the
        # count that cannot drift.
        @info """
        NO CUDA DEVICE: the GPU half of this suite did NOT run.
        Every CUDA-gated testset was skipped, including all CPU/CUDA parity
        checks; each reports itself as Broken/skipped in the summary below.
        A green run here says nothing about ANY CUDA path. $(length(cuda_files)) source
        files carry CUDABackend code (derived from the tree, not a hand list):
        $(join(cuda_files, ", "))
        -- and none of it ran.
        Run on a GPU host before trusting a CUDA change."""
        @test_skip "CUDA device not available -- GPU half of the suite skipped"
    end
end
@testset "Architecture integrity" begin
    metadata = validate_element_metadata(; throw_on_error=true)
    # Implied, not independent (2026-08-05_b audit, U17b-5):
    # `throw_on_error=true` already throws whenever `!passed`, so reaching this
    # line means it passed. Kept as documentation of intent; do not count it as
    # coverage.
    @test metadata.passed
    @test validate_configuration_metadata()
    # 2026-08-05_b audit, U12-3: the U3-4 repair totalized this validator's
    # solver and observer loops by walking the type tree, and stopped there --
    # execution policies and schedules kept hand-written tuples, so a new
    # concrete type was unchecked until someone edited an enumeration.
    # `PlaceholderPolicy` already sat outside the policy tuple, which showed the
    # omission was live rather than theoretical.
    #
    # The walk RECURSES, and that is the load-bearing part: the policy tree is
    # two deep (CUDAExecutionPolicy and GPUExecutionPolicy live under
    # AbstractGPUExecutionPolicy), so a one-level `subtypes` guard would have
    # walked past the two policies that matter most and still reported clean.
    let found = Octopus._concrete_octopus_subtypes(Octopus.AbstractExecutionPolicy)
        @test CUDAExecutionPolicy in found          # depth 2
        @test GPUExecutionPolicy in found           # depth 2
        @test CPUThreadsExecutionPolicy in found    # depth 1
    end
    @test !isempty(Octopus._concrete_octopus_subtypes(Octopus.AbstractSchedule))

    snapshot_path = joinpath(pkgdir(Octopus), "docs", "registry_snapshot.md")
    @test registry_snapshot_markdown() == read(snapshot_path, String)

    # Every document under docs/ is reachable from docs/README.md, by its own
    # file name or by its directory's (the audit unit-report folders are
    # indexed as folders). The rule "every new document is in docs/README.md"
    # had no tripwire, and the soft-Gaussian wavefront record of 2026-09-04
    # sat unindexed for a day until the next session's design review noticed
    # (2026-09-04). Hidden directories (editor checkpoints) are skipped.
    # The directory shortcut is DECLARED, not inferred (2026-09-07). It read
    # `occursin(basename(root) * "/", index)`, meaning "some file's parent
    # directory name appears somewhere in the index". `history/` appears in
    # every one of the ~70 per-file links below it AND in its own section
    # heading, so that clause was true for every file under `docs/history/` and
    # not one of them was ever checked individually -- the largest documentation
    # directory, and the one this testset's own comment says it exists to
    # police. Measured when this was fixed: 94 files were indexed by name and 48
    # relied on the shortcut, all 48 in the two audit unit-report bundles that
    # genuinely are covered wholesale.
    #
    # No substring rule can separate "the index declares this directory covered"
    # from "the index links a file that lives in it", so the exemption is an
    # explicit marker in README.md. And a marker for a directory that no longer
    # exists FAILS, so the exemption list cannot outlive its subject -- the same
    # stale-exemption discipline the solver-option contract uses.
    let docs = joinpath(pkgdir(Octopus), "docs"),
        index = read(joinpath(docs, "README.md"), String),
        unindexed = String[],
        stale = String[]
        wholesale = Set{String}(String(m.captures[1]) for m in
            eachmatch(r"<!--\s*indexed-wholesale:\s*(\S+?)/?\s*-->", index))
        for d in sort!(collect(wholesale))
            isdir(joinpath(docs, d)) || push!(stale, d)
        end
        # Every FILE of every type, matched by its WHOLE relative path against
        # the index's link targets, never by basename (2026-10-18 audit
        # F-149/U28-4, U52-13): `endswith(f, ".md") || continue` left the two
        # history records that are not markdown (a `.txt` capture, a `.tsv`
        # benchmark table) outside the rule, and `occursin(f, index)` waved a
        # file through whenever any link named ANOTHER file of the same
        # basename -- 27 basenames are duplicated across the audit bundles,
        # four files passed only through someone else's link, and a newcomer
        # `U1_report.md` in a fresh directory would have passed the same way.
        # A wholesale marker covers its directory and the directories nested
        # in it (the bundles carry `bin/` subdirectories of probe scripts).
        targets = Set{String}(replace(String(split(String(m.captures[1]), '#')[1]), r"^\./" => "") for m in
            eachmatch(r"\]\(([^)\s]+)\)", index))
        covered(dir) = any(w -> dir == w || startswith(dir, w * "/"), wholesale)
        for (root, dirs, files) in walkdir(docs)
            filter!(d -> !startswith(d, "."), dirs)
            for f in files
                f == "README.md" && root == docs && continue
                rel = relpath(joinpath(root, f), docs)
                (rel in targets || covered(relpath(root, docs))) || push!(unindexed, rel)
            end
        end
        @test isempty(unindexed)
        isempty(unindexed) || @info "documents missing from docs/README.md" unindexed
        # and the other direction: no link target names a file that is not there
        dangling = sort!([t for t in targets if !startswith(t, "http") && !ispath(joinpath(docs, t))])
        @test isempty(dangling)
        isempty(dangling) || @info "docs/README.md links naming no file" dangling
        @test isempty(stale)
        isempty(stale) || @info "indexed-wholesale markers naming no directory" stale
        # The exemption is narrow: it must not have swallowed `history/` again.
        @test !("history" in wholesale)
        @test !isempty(wholesale)          # and the marker syntax still parses

        # The rule shown failing, on a synthetic index rather than by writing
        # into docs/: an index that merely LINKS files inside a directory must
        # not thereby exempt that directory (the old directory clause's hole),
        # and a link to ANOTHER file of the same basename must not index this
        # one (the old name clause's hole, F-149). Both holes of the old rule
        # are shown open and both closed by the path rule.
        let fake = "see [`a.md`](history/a.md) and [`U1_report.md`](bundle_a/U1_report.md) (`history/`)\n" *
                   "<!-- indexed-wholesale: bundle_a -->\n",
            old_rule(f, dir, idx) = occursin(f, idx) || occursin(dir * "/", idx),
            marks(idx) = Set{String}(String(m.captures[1]) for m in
                eachmatch(r"<!--\s*indexed-wholesale:\s*(\S+?)/?\s*-->", idx)),
            links(idx) = Set{String}(String(m.captures[1]) for m in eachmatch(r"\]\(([^)\s]+)\)", idx)),
            path_rule(rel, dir, idx) = rel in links(idx) || any(w -> dir == w || startswith(dir, w * "/"), marks(idx))
            @test old_rule("b.md", "history", fake)                  # the directory hole: waved through
            @test !path_rule("history/b.md", "history", fake)         # caught
            @test path_rule("history/a.md", "history", fake)          # named files still pass
            @test old_rule("U1_report.md", "fresh", fake)             # the basename hole: another directory's file of the same name
            @test !path_rule("fresh/U1_report.md", "fresh", fake)     # caught by the whole path
            @test path_rule("bundle_a/U1_report.md", "bundle_a", fake)
            # a declared directory is exempt, its nested directories with it
            # (what the audit bundles rely on), and an undeclared one is not
            @test path_rule("bundle_a/bin/x.jl", "bundle_a/bin", fake)
            @test !path_rule("bundle_b/x.jl", "bundle_b", fake)
        end
    end

    # Every directory under src/ has an ownership bullet in AGENTS.md's source
    # map. The map once named 7 of 13 directories (2026-08-05_b audit, U26-12;
    # docs/history/comprehensive_audit_2026_08_05_b_unit_reports/U26_report.md);
    # a hand-maintained count rots, so this derives the list from the tree --
    # the WHOLE tree (2026-10-18 audit F-191/U27-9: the walk read the top
    # level only while AGENTS.md states the rule for every directory, and
    # `src/tasks/strongstrong/` went unchecked). A nested directory passes
    # with a bullet of its own or named, as `<name>/`, inside its parent's
    # bullet paragraph; hidden directories (editor checkpoints) and
    # directories holding no source are skipped.
    agents_md = read(joinpath(pkgdir(Octopus), "AGENTS.md"), String)
    src_root = joinpath(pkgdir(Octopus), "src")
    # The bullet paragraph for `src/<dir>/`: its first line and the indented
    # continuation lines, up to the next bullet or a blank line.
    source_map_bullet(text, dir) = begin
        m = match(Regex("^- `src/" * dir * "/`:.*?(?=\\n- |\\n\\n|\\z)", "ms"), text)
        m === nothing ? nothing : m.match
    end
    source_map_names(text, dir) = source_map_bullet(text, dir) !== nothing ||
        (occursin("/", dir) && (parent = source_map_bullet(text, dirname(dir));
                                parent !== nothing && occursin("`" * basename(dir) * "/`", parent)))
    walked = String[]
    for (root, dirs, files) in walkdir(src_root)
        filter!(d -> !startswith(d, "."), dirs)
        root == src_root && continue
        any(f -> endswith(f, ".jl"), files) || continue
        push!(walked, relpath(root, src_root))
    end
    for d in walked
        @testset let d = d
            @test source_map_names(agents_md, d)
        end
    end
    @test "tasks/strongstrong" in walked          # the nested directory that motivated the walk is reached
    # The rule shown failing on a synthetic map: the old top-level check is
    # satisfied while the nested directory goes unnamed; the new one catches
    # it, accepts either way of naming it, and does not accept a mention
    # outside the parent's bullet.
    let fake = "- `src/tasks/`: workflow composition and execution.\n- `src/track/`: tracking.\n"
        @test occursin("- `src/tasks/`:", fake)
        @test !source_map_names(fake, "tasks/strongstrong")
        @test source_map_names(fake * "- `src/tasks/strongstrong/`: solvers.\n", "tasks/strongstrong")
        @test source_map_names("- `src/tasks/`: composition; `strongstrong/` holds the\n  solvers.\n",
                               "tasks/strongstrong")
        @test !source_map_names("- `src/tasks/`: composition.\n\n`strongstrong/` elsewhere.\n",
                                "tasks/strongstrong")
    end

    # `summarize_registry()` lists every category's CONCRETE members, as
    # AGENTS.md says; the registry and the snapshot's sections keep the
    # abstract taxonomy nodes, each with a description (2026-10-18 audit
    # F-191/U27-10: the summary listed `AbstractGPUExecutionPolicy` among six
    # policies and three abstract contract nodes among nineteen contracts, so
    # a consumer counting members from it over-counted). Derived from the
    # registry the summary consumes: the summary is exactly its concrete part.
    let s = summarize_registry(), reg = build_registry()
        for section in (:tracking_methods, :solvers, :policies, :contracts, :analyses, :tasks)
            members = getproperty(reg, section)
            @test Set(getproperty(s, section)) == Set(Octopus.name.(filter(!isabstracttype, members)))
        end
        @test any(isabstracttype, reg.policies) && any(isabstracttype, reg.contracts)   # the walk still carries the taxonomy
        @test !(:AbstractGPUExecutionPolicy in s.policies) && !(:AbstractPhysicsContract in s.contracts)
        @test occursin("`AbstractGPUExecutionPolicy`", registry_snapshot_markdown(reg))  # and the snapshot still publishes it
    end
end
@testset "every public configuration schema is exported" begin
    # `strong_strong_task_option_schema` was the only one that was not, so the
    # metadata the U3-5 fix added was reachable only by knowing the internal
    # name -- undiscoverable through the API every other configuration surface
    # uses (2026-08-05_b audit, U5-11). Derived from the module's own names, so
    # a new schema added without an export fails here.
    schema_names = filter(names(Octopus; all = true)) do n
        s = String(n)
        # `names(...; all=true)` also lists each function's `#name` method-table
        # binding and any `_`-prefixed internal, neither of which is a surface.
        endswith(s, "_option_schema") && !startswith(s, "#") && !startswith(s, "_")
    end
    exported = Set(names(Octopus))
    @test length(schema_names) >= 8
    for n in schema_names
        @test n in exported
    end
    @test :strong_strong_task_option_schema in exported
    # (:luminosity_path, :luminosity_append) until 2026-08-17, when phase 2
    # of the unification retired the keywords; (:luminosity, :artifact)
    # through the run artifact's step 1; and (:artifact,) alone since step 4
    # retired the text observer (2026-08-18): the artifact IS the output.
    @test keys(strong_strong_task_option_schema()) == (:artifact,)
    # The TrackingTask twin (2026-09-07). Same shape as the line above: a new
    # public task option is invisible until it appears in the schema.
    # `artifact` and `loss_report` joined 2026-10-16 (neighbour audit S4-10:
    # both were public keywords with no schema entry).
    @test keys(tracking_task_option_schema()) ==
          (:record_turn_times, :luminosity_tracking, :artifact, :loss_report)
    # The tripwire the comment above promised (2026-10-18 audit F-212/U32-2:
    # `validate_configuration_metadata` checks schema ⊆ fields, the direction
    # that cannot see an undeclared keyword, and S4-10 found two by hand). The
    # constructor's keywords are derived from its methods; every one is a
    # schema entry or on the stated list of non-options -- composition
    # (`policy`, `seed`, `hooks`, `actions`, `observers`, `contracts`,
    # `analyses`) and the two retired spellings that throw by name (`loss_log`,
    # `luminosity`). A new keyword lands here red until it has a schema entry
    # or a stated reason.
    task_kwargs = Set(k for m in methods(TrackingTask) for k in Base.kwarg_decl(m))
    @test Set(keys(tracking_task_option_schema())) ⊆ task_kwargs
    @test setdiff(task_kwargs, keys(tracking_task_option_schema())) ==
          Set([:policy, :seed, :hooks, :actions, :observers, :contracts, :analyses, :loss_log, :luminosity])
end
@testset "No method grows a Core.Box outside the argued allowlist" begin
    # The concurrency sweep (archived todo row): two of the three 2026-08-03
    # threading defects were one Julia trap -- a name assigned both in a `do`
    # block and its enclosing function is one shared Core.Box across every
    # worker. The sweep is on LOWERED code because a text sweep gave six
    # false positives and missed a real one. Every current box is serial
    # except one, argued below; a NEW box anywhere fails this test and must
    # either be fixed or argued onto the list.
    expr_has_box(x) = x isa GlobalRef ? (x.mod === Core && x.name === :Box) :
                      x isa Expr ? any(expr_has_box, x.args) : false
    clean_name(m) = begin
        s = String(m.name)
        startswith(s, "#") || return s
        parts = split(s, '#'; keepempty=false)
        isempty(parts) ? s : String(parts[1])
    end
    allowed = Set([
        # serial file I/O
        ("read_beam_coordinates", "Beam.jl"),
        # (`_initialize_moment_file!` left with the legacy moment observers on
        # 2026-08-11 and sat here unhit until the 2026-10-18 audit, F-214/U33-2;
        # the used-entry tripwire below retires the next one on the spot.)
        # serial contract validation helpers
        ("validate", "Contracts.jl"),
        ("_contract_default_initial_rep", "Contracts.jl"),
        # serial constructor (branch-reassigned locals captured by ntuple lambdas)
        ("GaussianStrongBeam", "strong_beam.jl"),
        # one-shot adapter activation; self-recursive local closures
        ("_activate_symbolics_adapter!", "symbolic.jl"),
        # `_spectral_collide_longitudinal!` was THE one concurrent-closure box
        # (the per-batch luminosity accumulator, read through typeof inside
        # the worker closure and written outside it, argued benign in audit
        # parts 1 and 6). It left this list 2026-09-04: the fold now runs after
        # the closures, by collision position, and the sweep finds no box.
    ])
    offenders = String[]
    hit = Set{Tuple{String,String}}()
    nmethods = 0
    seen = Set{Method}()
    # Enumerate over EVERY loaded module's bindings, not just Octopus's own
    # (2026-08-05_b audit, U18-1). `names(Octopus)` cannot reach a method
    # Octopus adds to a generic owned by another module -- the binding lives in
    # Base or Adapt, so `getfield(Octopus, name)` never yields the function even
    # though `m.module === Octopus` holds for the method. Measured: 2224
    # methods seen that way against 2494 with `m.module === Octopus`, a
    # 270-method blind spot covering `Base.show` (7), `Base.==` (5),
    # `Base.getindex` (5), `Base.hash` (5), the arithmetic operators (12), the
    # property interface (12), `Adapt.adapt_structure` (3) and more. None of
    # them carries a box today, so the sweep was blind rather than wrong -- but
    # a box added to `Base.show(io, ::Beam)` tomorrow would have been invisible
    # to the tripwire that exists to catch exactly that.
    scan_modules = Module[Octopus]
    for name in names(Main; all=true, imported=true)
        isdefined(Main, name) || continue
        v = try getfield(Main, name) catch; continue end
        v isa Module && !(v in scan_modules) && push!(scan_modules, v)
    end
    for M in (Base, Core, Main), name in names(M; all=true, imported=true)
        isdefined(M, name) || continue
        v = try getfield(M, name) catch; continue end
        v isa Module && !(v in scan_modules) && push!(scan_modules, v)
    end
    candidates = Any[]
    for M in scan_modules, name in names(M; all=true, imported=true)
        isdefined(M, name) || continue
        f = try getfield(M, name) catch; continue end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        push!(candidates, f)
    end
    for f in candidates
        ms = try
            methods(f)
        catch
            continue
        end
        for m in ms
            m.module === Octopus || continue
            m in seen && continue
            push!(seen, m)
            nmethods += 1
            ci = try
                Base.uncompressed_ir(m)
            catch
                continue
            end
            ci === nothing && continue
            any(expr_has_box, ci.code) || continue
            file = basename(String(m.file))
            file == "none" && continue          # @generated bodies: compile-time, serial
            if (clean_name(m), file) in allowed
                push!(hit, (clean_name(m), file))
                continue
            end
            push!(offenders, "$(m.name) @ $(file):$(m.line)")
        end
    end
    # Ratcheted to the structural count (U18-1): 2494 methods have
    # `m.module === Octopus`, against the 2224 the binding-based enumeration
    # could reach. `> 2000` tolerated losing the entire 270-method blind spot
    # without a word.
    @test nmethods >= 2450             # the sweep actually swept, and widely
    @test isempty(offenders)
    isempty(offenders) || foreach(o -> @info("new Core.Box: " * o), offenders)
    # Every allowlist entry was HIT (2026-10-18 audit F-214/U33-2): a box that
    # left the tree leaves the list, so an argued exemption cannot outlive its
    # box and blanket a future function of the same name.
    @testset let unused_allowlist_entries = sort!(collect(setdiff(allowed, hit)))
        @test isempty(unused_allowlist_entries)
    end
    # The detector itself, fed a known box and a known non-box in THIS process
    # (the same audit: `expr_has_box` had never been shown a defect): a local
    # assigned inside a closure AND outside it is one shared `Core.Box`; a
    # `Ref` written the same way is not.
    function corebox_positive(n)
        acc = 0
        f = () -> (acc += n)
        f(); acc += 1
        return acc
    end
    function corebox_negative(n)
        acc = Ref(0)
        f = () -> (acc[] += n)
        f(); acc[] += 1
        return acc[]
    end
    @test any(expr_has_box, Base.uncompressed_ir(only(methods(corebox_positive))).code)
    @test !any(expr_has_box, Base.uncompressed_ir(only(methods(corebox_negative))).code)
end
@testset "Every export is documented" begin
    # 76 of 335 exports lacked documentation when the 2026-08-05 audit swept
    # them (U13-5); the sweep also found ten exports whose complete
    # docstrings had silently DETACHED because a comment line sat between
    # the docstring and the definition — on this Julia that attaches the
    # docs to nothing, with no warning. This keeps both classes closed: a
    # new undocumented export and a docstring detached by a later comment
    # both land here by name.
    undocumented = [n for n in names(Octopus)
                    if n !== :Octopus && occursin("No documentation found",
                        string(Base.Docs.doc(Base.Docs.Binding(Octopus, n))))]
    @test isempty(undocumented)
end
@testset "Observer schema keys must name public fields" begin
    # U4-18, re-enabled 2026-09-07. `validate_configuration_metadata` compares
    # each observer's schema keys against its `configuration_report` entry
    # names. That is REAL for the two observers with hand-written reports and an
    # IDENTITY for `BPMObserver`, whose report is built by iterating the same
    # `_BPM_OBSERVER_OPTION_SCHEMA` const the schema accessor returns
    # (BPMObserver.jl:412 and :416) -- both sides are `keys` of one object, so
    # it passes for any schema, correct or not.
    #
    # The coverage that comparison cannot give a derived report is a FIELD
    # check, which was tried in 2026-08 and reverted because three observers
    # then exposed `capacity` while storing `buffer_capacity`. Those observers
    # were deleted and the option retired, so it is back -- and this is the
    # check being shown to fail, which is the whole point of the row.
    @test validate_configuration_metadata()
    try
        @eval Octopus observer_option_schema(::Type{BPMObserver}) =
            merge(_BPM_OBSERVER_OPTION_SCHEMA,
                  (not_a_field = ConfigurationOptionMeta(Int, 0, "injected probe"),))
        err = try
            validate_configuration_metadata()
            ""
        catch e
            sprint(showerror, e)
        end
        @test occursin("BPMObserver schema keys are not fields", err)
        @test occursin("not_a_field", err)
    finally
        @eval Octopus observer_option_schema(::Type{BPMObserver}) =
            _BPM_OBSERVER_OPTION_SCHEMA
    end
    @test validate_configuration_metadata()       # restored
end
@testset "The module precompiles without overwriting its own methods" begin
    # Part 6 §8.7: a same-signature method silently overwrote another, PASSED
    # the full suite (both methods behaved identically), and was caught only
    # by accident when an unrelated verification happened to load the package
    # in a fresh process. This guard makes that check deliberate. Two
    # subtleties bought by measurement: a plain runtime `include` is SILENT
    # about overwrites on this Julia, so the guard must force an actual
    # precompile (`Base.compilecache` is unconditional); and the driver can
    # exit 0 even when the worker reports the collision, so the assertion is
    # on the message, not the exit code. Costs one full precompile (~1 min).
    prog = "Base.compilecache(Base.identify_package(\"Octopus\"))"
    err = IOBuffer()
    p = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$(pkgdir(Octopus)) -e $prog`,
                     stderr=err, stdout=devnull); wait=false)
    wait(p)
    text = String(take!(err))
    @test success(p)
    @test !occursin("Method overwriting is not permitted", text)
    @test !occursin(r"Method definition .* overwritten", text)
end
@testset "Metadata queries and the validator check declarations, not themselves" begin
    # Audit part 7, K2/K3/K5/K6/K8.

    # K2: the three named-strength thin constructors build bit-identical
    # runtimes to the PTC-validated ThinMultipoleSpec spellings, which is what
    # justifies their PTCConsistencyContract declaration transitively -- the
    # PTC table exercises thin_multipole, and these are the same runtime.
    same(x, y) = typeof(x) == typeof(y) &&
        all(getfield(x, f) == getfield(y, f) for f in fieldnames(typeof(x)))
    let a = 0.037
        @test same(compile_runtime(ThinDipoleSpec(k0l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(a,))))
        @test same(compile_runtime(ThinDipoleSpec(k0sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(a,))))
        @test same(compile_runtime(ThinQuadrupoleSpec(k1l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(0.0, a))))
        @test same(compile_runtime(ThinQuadrupoleSpec(k1sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(0.0, a))))
        @test same(compile_runtime(ThinSextupoleSpec(k2l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(0.0, 0.0, a))))
        @test same(compile_runtime(ThinSextupoleSpec(k2sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(0.0, 0.0, a))))
    end

    # K5: list-returning queries hand out copies; mutating one must not
    # corrupt the registry.
    let c = required_contracts(ElementSpec{:sbend})
        push!(c, Int64)
        @test !(Int64 in required_contracts(ElementSpec{:sbend}))
        @test validate_element_metadata().passed
    end

    # K8: a line has no tracking method of its own; an explicit request is
    # rejected rather than silently discarded.
    let line = BeamLine("L", DriftSpec(L=1.0))
        @test compile_runtime(line) isa Octopus.CompositeLine
        @test_throws ArgumentError compile_runtime(line, Symplectic6DMap())
    end

    # K3/K6: probe metas registered temporarily, removed afterwards so the
    # snapshot test still sees only the real registry.
    try
        # K6: friendly_constructor = nothing is permitted metadata and must
        # be reported, not crash snapshot generation.
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:k6_probe, spec_type=ElementSpec{:k6_probe},
            friendly_constructor=nothing,
            example=ElementSpec{:k6_probe}(Dict{Symbol,Any}())))
        @test occursin("(no friendly constructor)", registry_snapshot_markdown())

        # K3: the injected-defect scenario that used to validate clean -- a
        # meta whose contract is not a contract, whose analysis is not an
        # analysis, and whose example cannot compile -- must now FAIL.
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:k3_liar, spec_type=ElementSpec{:k3_liar},
            tracking_methods=[Symplectic6DMap], runtime_type=Octopus.LatticeMagnet,
            contracts=[Int64], analyses=[String],
            example=ElementSpec{:k3_liar}(Dict{Symbol,Any}())))
        r = validate_element_metadata()
        @test !r.passed
        @test any(e -> occursin("k3_liar", e) && occursin("not an AbstractContract", e), r.errors)
        @test any(e -> occursin("k3_liar", e) && occursin("not an AbstractAnalysis", e), r.errors)
        @test any(e -> occursin("k3_liar", e) && occursin("does not compile", e), r.errors)
    finally
        for k in (:k6_probe, :k3_liar)
            delete!(Octopus.ELEMENT_META_BY_KIND, k)
            T = ElementSpec{k}
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
            filter!(t -> t !== T, Octopus.REGISTERED_ELEMENT_SPECS)
        end
    end
    @test validate_element_metadata().passed      # registry restored

    # U12-6, closed 2026-09-07: `ParamMeta.unit` was free text, and it is not
    # decoration -- `_perturb_is_physical` (Contracts.jl) reads
    # `pmeta.unit in ("m", "rad")` to choose whether the parameter-effectiveness
    # contract perturbs an integer-declared parameter physically or by an
    # enum-style step. A misspelt unit therefore downgrades a physical parameter
    # to a weaker probe SILENTLY, with the contract still passing. It now draws
    # from `ALLOWED_PARAM_UNITS`, and this is that check shown failing.
    try
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:u12_6_probe, spec_type=ElementSpec{:u12_6_probe},
            runtime_type=Octopus.LatticeMagnet,
            parameters=(bogus=Octopus.ParamMeta(; unit="furlong", meaning="probe"),),
            example=ElementSpec{:u12_6_probe}(Dict{Symbol,Any}())))
        r = validate_element_metadata()
        @test !r.passed
        @test any(e -> occursin("u12_6_probe", e) &&
                       occursin("unrecognised unit", e) &&
                       occursin("furlong", e), r.errors)
    finally
        delete!(Octopus.ELEMENT_META_BY_KIND, :u12_6_probe)
        let T = ElementSpec{:u12_6_probe}
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
            filter!(t -> t !== T, Octopus.REGISTERED_ELEMENT_SPECS)
        end
    end
    @test validate_element_metadata().passed      # registry restored

    # U12-8, repaired 2026-09-07. The three friendly-constructor checks
    # (schema, construction_help, example kind) were TAUTOLOGIES: every
    # accessor they used is `_element_meta_or_nothing(x)` followed by a field
    # read, and the spec type and the friendly constructor are registered to the
    # SAME `ElementMeta`, so each compared one field of one object with itself.
    # They could not fail for any content while claiming the friendly
    # constructor had been checked against the raw spec.
    #
    # The pair that replaced them must reject the defect the old three passed:
    # a friendly constructor whose table binding is perfectly consistent but
    # which BUILDS THE WRONG ELEMENT. `DriftSpec` builds `ElementSpec{:drift}`;
    # declaring it as the friendly constructor of another kind is exactly that.
    let saved = get(Octopus.ELEMENT_META_BY_FRIENDLY_TYPE, DriftSpec, nothing)
        try
            Octopus.register_element_meta!(Octopus.ElementMeta(;
                kind=:u12_8_probe, spec_type=ElementSpec{:u12_8_probe},
                runtime_type=Octopus.LatticeMagnet,
                friendly_constructor=DriftSpec,
                example=ElementSpec{:u12_8_probe}(Dict{Symbol,Any}(:L => 1.0))))
            r = validate_element_metadata()
            @test !r.passed
            # (2) what the constructor BUILDS -- the non-circular half.
            @test any(e -> occursin("u12_8_probe", e) &&
                           occursin("builds drift, not the declared", e), r.errors)
            # (1) the table binding: drift's own friendly type now resolves to
            # the probe's meta, which is the rebinding hazard stated honestly.
            @test any(e -> occursin("resolves to ElementMeta u12_8_probe", e), r.errors)
        finally
            delete!(Octopus.ELEMENT_META_BY_KIND, :u12_8_probe)
            T = ElementSpec{:u12_8_probe}
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
            filter!(t -> t !== T, Octopus.REGISTERED_ELEMENT_SPECS)
            # Restore drift's LEGITIMATE binding, which registering the probe
            # overwrote. A plain `delete!` here leaves the registry broken for
            # every later testset -- measured while writing this control.
            saved === nothing ?
                delete!(Octopus.ELEMENT_META_BY_FRIENDLY_TYPE, DriftSpec) :
                (Octopus.ELEMENT_META_BY_FRIENDLY_TYPE[DriftSpec] = saved)
            # And the drift's CLASS FORM, a method the registration `@eval`s
            # (`_install_class_form!`, since 2026-11-26) that no container
            # holds: registering the probe rebound `DriftSpec(template; ...)`
            # to derive a `u12_8_probe`, and this restore left it so until
            # 2026-11-27 (the testset after this one is the control).
            saved === nothing || Octopus._install_class_form!(saved)
        end
    end
    @test validate_element_metadata().passed      # registry restored again
end

# The U12-8 probe's restore, checked from OUTSIDE its block (the class form is
# a method the registration `@eval`s, so the same block would see its own
# world). Since 2026-11-26 `register_element_meta!` also installs the class
# form (`_install_class_form!`, R11 of the machine-description follow-ups):
# registering the probe with `DriftSpec` as its friendly constructor rebound
# `DriftSpec(template; ...)` to derive a `u12_8_probe`, a method no registry
# container holds and the probe's four-container restore never reinstalled.
# Unnoticed in the single-file suite, where every consumer of the drift's
# class form ran before the probe; red on 2026-11-27 when the split put this
# sweep first and "Machine description: the class form derives a spec from a
# template of its kind ..." walked the registry after it.
@testset "The U12-8 probe leaves the drift's class form as it found it" begin
    d = DriftSpec(DriftSpec(L=1.0); name="u12_8_after")
    @test Octopus.kind(d) === :drift && getparam(d, :name) == "u12_8_after"
    @test Octopus.ELEMENT_META_BY_FRIENDLY_TYPE[DriftSpec].kind === :drift
end
@testset "No docstring is detached by comment lines" begin
    # 2026-08-05_b audit, U12-9. On Julia 1.12 a string literal followed by
    # COMMENT lines and then a definition attaches to nothing, silently. The
    # "Every export is documented" tripwire closed this class for exports, but
    # it iterates `names(Octopus)` and therefore structurally cannot see a
    # non-exported one -- and both instances in the repo were non-exported:
    # `_compiled_matches_runtime` (inserted by the U13-4 FIX, in the very audit
    # that recorded the gotcha) and `_alloc_randn`.
    #
    # This scans the source for the pattern instead, so it sees what the
    # export-based check cannot. A docstring's explanation belongs INSIDE the
    # docstring; a comment between the two is the bug.
    #
    # Only the COMMENT shape is scanned, deliberately. The sibling mistake --
    # a docstring immediately followed by another docstring, so the first
    # documents the second -- is a hard precompile error ("cannot document the
    # following expression"), so Julia catches it before this file can run, and
    # a check here for it could never fire. Tried and reverted (2026-08-05_b
    # audit, U4-13); the silent shape is the one that needs a scan.
    # The scan is a function of the lines it is handed, so the planted shapes
    # below can be fed to it (2026-10-18 audit F-216/U34-4: the definition
    # test was blind to `Base.`-qualified and `where` short forms, to a block
    # docstring closing on its last text line and to a documented global
    # assignment -- Julia leaves all of them undocumented -- and the scanner
    # had never been shown a defect).
    is_definition(target) =
        occursin(r"^(function|const|macro|struct|abstract type|mutable struct|primitive type|@\w+)\b", target) ||
        occursin(r"^[A-Za-z_][A-Za-z0-9_!.]*(\{[^=]*\})?\(.*\)(\s+where\s*(\{.*\}|[A-Za-z_][A-Za-z0-9_]*))?\s*=", target) ||
        occursin(r"^[A-Za-z_][A-Za-z0-9_!]*\s*(::[^=]+)?=(?!=)", target)
    function detached_in(lines, label)
        out = String[]
        i = 1
        while i <= length(lines)
            stripped = strip(lines[i])
            # A one-line docstring, the bare closing line of a block docstring,
            # or a block docstring closing on its last text line.
            closes = (startswith(stripped, "\"\"\"") && endswith(stripped, "\"\"\"") && length(stripped) > 6) ||
                     stripped == "\"\"\"" ||
                     (endswith(stripped, "\"\"\"") && !startswith(stripped, "\"\"\"") && !occursin("= \"\"\"", stripped))
            if closes
                j = i + 1
                saw_comment = false
                while j <= length(lines)
                    nxt = strip(lines[j])
                    if isempty(nxt)
                        j += 1
                    elseif startswith(nxt, "#")
                        saw_comment = true
                        j += 1
                    else
                        break
                    end
                end
                # Only a definition would have been documented.
                if saw_comment && j <= length(lines) && is_definition(strip(lines[j]))
                    push!(out, "$(label):$(i) -> $(first(strip(lines[j]), 60))")
                end
                i = j
            else
                i += 1
            end
        end
        return out
    end
    detached = String[]
    for (root, _, files) in walkdir(joinpath(pkgdir(Octopus), "src")), f in files
        endswith(f, ".jl") || continue
        append!(detached, detached_in(readlines(joinpath(root, f)), f))
    end
    isempty(detached) || foreach(d -> @info("detached docstring: " * d), detached)
    @test isempty(detached)
    # The scanner shown its defects: each planted shape (a docstring, comment
    # lines, then a definition Julia would have documented) is reported once,
    # and the two sound shapes are not.
    planted = (
        ("function", "\"\"\"doc\"\"\"\n# why\nfunction f_planted end"),
        ("const", "\"\"\"doc\"\"\"\n# why\nconst X_PLANTED = 1"),
        ("qualified_shortform", "\"\"\"doc\"\"\"\n# why\nBase.show(io::IO, x::Planted) = print(io, 1)"),
        ("where_shortform", "\"\"\"doc\"\"\"\n# why\ng_planted(x::T) where {T} = x"),
        ("text_closing_line", "\"\"\"\ndoc\nmore.\"\"\"\n# why\nfunction h_planted end"),
        ("global_assignment", "\"\"\"doc\"\"\"\n# why\nY_PLANTED = 1"),
        ("macro_definition", "\"\"\"doc\"\"\"\n# why\n@inline k_planted(x) = x"),
    )
    sound = (
        ("adjacent", "\"\"\"doc\"\"\"\nfunction f_sound end"),
        ("not_a_definition", "\"\"\"doc\"\"\"\n# why\nf_sound(1) + 2"),
    )
    for (name, text) in planted
        @testset let shape = name
            @test length(detached_in(split(text, "\n"), name)) == 1
        end
    end
    for (name, text) in sound
        @testset let shape = name
            @test isempty(detached_in(split(text, "\n"), name))
        end
    end

    # The sibling shape (2026-10-13 neighbour audit, U6-1): a docstring that
    # attaches, but to a binding no `?Name` shows. A docstring above a
    # `function (::Type{Name{N}})(...)` constructor binds to `Core.Type` with
    # the method's signature, so `@doc Name` -- the abstract type's docstring --
    # never mentions what it explains; the crab cavity's `phase_noise`
    # paragraph sat there. Every binding documented from Octopus but owned by
    # another module must be a FUNCTION being extended (`Base.read`,
    # `Base.repeat`, `Base.reverse`, `Base.setproperty!` today; `?read` finds
    # those); a non-function foreign binding is that constructor shape.
    foreign = String[]
    for (binding, multidoc) in Base.Docs.meta(Octopus)
        binding.mod === Octopus && continue
        resolved = isdefined(binding.mod, binding.var) ? getfield(binding.mod, binding.var) : nothing
        resolved isa Function && continue
        push!(foreign, string(binding) * " <- " * join(string.(collect(keys(multidoc.docs))), "; "))
    end
    isempty(foreign) || foreach(f -> @info("docstring bound outside Octopus: " * f), foreign)
    @test isempty(foreign)
end
@testset "The documented configuration-status vocabulary is the real one" begin
    # 2026-08-05_b audit, U12-12. The public `configuration_report` docstring
    # listed six statuses in prose and two were wrong: `:library_managed` exists
    # nowhere in the codebase (the only "library-managed" text is a MEANING
    # string about cuFFT), and "inactive" is really two symbols,
    # `:inactive_backend` and `:inactive_dependency`, neither of them
    # `:inactive`. A hand-copied vocabulary with nothing checking it is the
    # drift Measured Lesson 4 names, so this derives the set from the source.
    declared = Set(Octopus.CONFIGURATION_STATUSES)
    @test :inactive_backend in declared && :inactive_dependency in declared
    @test :resolved in declared && :unresolved in declared
    @test :inherited in declared && :deprecated in declared
    @test length(declared) == 6

    # Both directions over LIVE reports (2026-10-18 audit F-215/U34-1: a regex
    # over the source stood here, blind to `:inherited` -- assigned through a
    # variable -- and the promised `declared ⊆ found` was never written). The
    # producers are chosen so that each declared status has one: `:inherited`
    # (a solver's `slicing1/2` taken from the shared slicing), `:inactive_dependency`
    # (`grid_extent_sigma` under `:extrema`), `:inactive_backend` (a CUDA-only
    # option reported for the CPU backend), `:unresolved` (a CUDA policy's
    # device before activation), `:deprecated` (`GPUExecutionPolicy`),
    # `:resolved` (everything else). A declared status nothing produces, or a
    # produced status the constant does not declare, fails by name.
    live = Dict{Symbol,Vector{String}}()
    producers = (CPUThreadsExecutionPolicy(), CUDAExecutionPolicy(), GPUExecutionPolicy(),
                 PICPoissonSolver(grid=(16, 16)), GaussianPoissonSolver(),
                 GaussianPICPoissonSolver(grid=(16, 16)), SpectralPoissonSolver(grid=(16, 16)))
    for obj in producers, e in configuration_report(obj)
        push!(get!(live, e.status, String[]), "$(nameof(typeof(obj))).$(e.name)")
    end
    for e in configuration_report(PICPoissonSolver(grid=(16, 16)); backend=CPUThreadsBackend)
        push!(get!(live, e.status, String[]), "PICPoissonSolver(CPU).$(e.name)")
    end
    @test :library_managed ∉ keys(live)     # the docstring's ghost
    @test :inactive ∉ keys(live)            # ...and its wrong spelling
    @testset let declared_not_produced = sort!(string.(collect(setdiff(declared, keys(live))))),
                 produced_not_declared = sort!(string.(collect(setdiff(keys(live), declared))))
        @test isempty(declared_not_produced)
        @test isempty(produced_not_declared)
    end
end
@testset "Every exported API name appears in the registry snapshot" begin
    # Source helpers and lifecycle/query functions are public objects too, but
    # are neither Core Objects nor tracking runtimes. The export-derived index
    # publishes them without inventing an architectural category for them.
    exported = Set(string(n) for n in names(Octopus) if n !== :Octopus)
    snapshot = registry_snapshot_markdown()
    tokens(text) = Set(String(m.captures[1]) for m in eachmatch(r"`([^`\r\n]+)`", text))
    missing(text) = setdiff(exported, tokens(text))
    @test occursin("## Exported API", snapshot)
    @test isempty(missing(snapshot))
    for name in (:TuneFunction, :TuneDistribution, :TuneHistogram,
                 :runtime_variants, :runtime_examples,
                 :clear_particle_tunes!, :particle_tune_tables)
        @test string(name) in exported
        @test string(name) in tokens(snapshot)
    end
    # Deleting every exact occurrence must be detected even if a name also
    # appears in another section (for example through an example catalogue).
    omitted = replace(snapshot, "`TuneFunction`" => "`removed-public-name`")
    @test missing(omitted) == Set(["TuneFunction"])
end
@testset "Every registry type describes itself" begin
    # 2026-08-05_b audit, U12-17. `description(T)` falls back to element
    # metadata, which is `nothing` for every non-element type, and then returns
    # "" rather than signalling -- so 15 of the 35 types the registry publishes
    # described themselves as the empty string to any agent that asked,
    # including all four Poisson solvers, both flagship task types and all three
    # example categories. `description`'s own docstring says these types "should
    # extend this method", and nothing checked. Contrast the 336/336
    # export-docstring tripwire, which does.
    bare = Octopus.registry_types_without_description()
    @test isempty(bare)
    isempty(bare) || @info("undescribed registry types: " *
                           join(("$(s).$(nameof(T))" for (s, T) in bare), ", "))

    # The tripwire must be able to fail, or it is decoration: a type planted
    # into a registry section with no `description` method must be reported,
    # by section and type (2026-10-18 audit F-216/U34-3: the line here compared
    # `isempty(x)` with itself).
    let reg = Octopus.build_registry(), fields = fieldnames(Octopus.OctopusRegistry)
        plant(f, v) = Octopus.OctopusRegistry((g === f ? v : getfield(reg, g) for g in fields)...)
        @test :solvers in fields
        planted = Octopus.registry_types_without_description(plant(:solvers, vcat(reg.solvers, Any[Int])))
        @test any(x -> x[2] === Int, planted)
        @test isempty(Octopus.registry_types_without_description(reg))
    end
    # ...and the ones this lead named must now be non-empty, by name.
    for T in (TrackingTask, StrongStrongTask, PICPoissonSolver,
              GaussianPoissonSolver, GaussianPICPoissonSolver,
              SpectralPoissonSolver, PTCConsistencyContract,
              ElementParameterEffectivenessContract)
        @test !isempty(Octopus.description(T))
    end
end
