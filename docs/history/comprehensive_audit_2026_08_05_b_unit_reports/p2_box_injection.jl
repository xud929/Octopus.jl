# U18 probe 2: injection test of the Core.Box sweep's discriminating power.
# Injects boxed closures into the LOADED Octopus module (no repository file is
# touched) and replays the sweep exactly as test/runtests.jl writes it.
using Octopus

const BOXY = """
function %NAME%(n)
    x = 0
    f = () -> (x += 1)
    for i in 1:n
        f()
    end
    return x
end
"""

# The sweep, verbatim from test/runtests.jl (2026-08-05 HEAD 7de4d81).
expr_has_box(x) = x isa GlobalRef ? (x.mod === Core && x.name === :Box) :
                  x isa Expr ? any(expr_has_box, x.args) : false
clean_name(m) = begin
    s = String(m.name)
    startswith(s, "#") || return s
    parts = split(s, '#'; keepempty=false)
    isempty(parts) ? s : String(parts[1])
end
const ALLOWED = Set([
    ("read_beam_coordinates", "Beam.jl"),
    ("_initialize_moment_file!", "BeamObservers.jl"),
    ("validate", "Contracts.jl"),
    ("_contract_default_initial_rep", "Contracts.jl"),
    ("GaussianStrongBeam", "strong_beam.jl"),
    ("_activate_symbolics_adapter!", "symbolic.jl"),
    ("_spectral_collide_longitudinal!", "spectral.jl"),
])
function run_sweep()
    offenders = String[]
    nmethods = 0
    seen = Set{Method}()
    for name in names(Octopus; all=true, imported=false)
        isdefined(Octopus, name) || continue
        f = try getfield(Octopus, name) catch; continue end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        ms = try methods(f) catch; continue end
        for m in ms
            m.module === Octopus || continue
            m in seen && continue
            push!(seen, m)
            nmethods += 1
            ci = try Base.uncompressed_ir(m) catch; continue end
            ci === nothing && continue
            any(expr_has_box, ci.code) || continue
            file = basename(String(m.file))
            file == "none" && continue
            (clean_name(m), file) in ALLOWED && continue
            push!(offenders, "$(m.name) @ $(file):$(m.line)")
        end
    end
    (nmethods, offenders)
end

base_n, base_off = run_sweep()
println("BASELINE  nmethods = $base_n   offenders = $(length(base_off))  $base_off")
println()

results = Tuple{String,Bool,String}[]

function inject(label, code, filename)
    before = Set(Base.invokelatest(run_sweep)[2])
    Base.include_string(Octopus, code, filename)
    after = Base.invokelatest(run_sweep)[2]
    new = setdiff(Set(after), before)
    caught = !isempty(new)
    push!(results, (label, caught, join(sort(collect(new)), ", ")))
    println(rpad(label, 62), caught ? "CAUGHT " : "MISSED ", join(sort(collect(new)), ", "))
end

# 1. ordinary Octopus-owned function, ordinary file -> must be caught
inject("1 plain function in a non-allowlisted file",
       replace(BOXY, "%NAME%" => "_u18_box_plain"), "pic_cpu.jl")

# 2. same box, but the method's NAME+FILE match an allowlist entry whose
#    argument covers only ONE specific method ("validate" @ Contracts.jl)
inject("2 new `validate` method in Contracts.jl (allowlist entry)",
       "function validate(::Val{:u18probe}, n)\n x = 0\n f = () -> (x += 1)\n for i in 1:n; f(); end\n return x\nend",
       "Contracts.jl")

# 3. a closure inside a function named `validate` in Contracts.jl
inject("3 closure inside a `validate` method in Contracts.jl",
       "function validate(::Val{:u18probe2}, n)\n x = 0\n f = () -> (x += 1)\n for i in 1:n; f(); end\n return x\nend",
       "Contracts.jl")

# 4. a method Octopus adds to a function owned by Base -> enumeration gap
inject("4 boxed method on Base.show (foreign generic)",
       "Base.show(io::IO, ::Val{:u18probe}) = begin\n x = 0\n f = () -> (x += 1)\n for i in 1:3; f(); end\n print(io, x)\nend",
       "spectral.jl")

# 5. a method Octopus adds to Base.:== (foreign generic)
inject("5 boxed method on Base.== (foreign generic)",
       "Base.:(==)(::Val{:u18probeA}, ::Val{:u18probeB}) = begin\n x = 0\n f = () -> (x += 1)\n for i in 1:3; f(); end\n x > 0\nend",
       "slicing.jl")

# 6. keyword-argument method (its body method IS Octopus-owned)
inject("6 boxed body of a keyword method",
       "function _u18_box_kw(n; scale = 1)\n x = 0\n f = () -> (x += scale)\n for i in 1:n; f(); end\n return x\nend",
       "pic_cpu.jl")

# 7. a box in an Octopus-owned function whose file is the allowlisted
#    Beam.jl but a DIFFERENT name -> must be caught (allowlist is name+file)
inject("7 different name, allowlisted file (Beam.jl)",
       replace(BOXY, "%NAME%" => "_u18_box_beamfile"), "Beam.jl")

println()
n_caught = count(r -> r[2], results)
println("INJECTION RESULT: $(n_caught) of $(length(results)) caught")
for (l, c, w) in results
    println("   ", c ? "caught" : "MISSED", "  ", l)
end
