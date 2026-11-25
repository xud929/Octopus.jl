export write_machine, read_machine, machine_toml, parse_machine

using InteractiveUtils: subtypes

"""
    write_machine(path, machine::Machine) -> path
    write_machine(path, lattice::Lattice) -> path

Write the machine's snapshot, the data form of the machine description
(design note `docs/design/machine_description.md`, decision D13), as a TOML
file at `path`, with bulk tables in a sidecar beside it. A `Lattice` is
written as the implicit one-lattice machine (`Machine(lattice)`). The text is
`machine_toml(machine)`; [`read_machine`](@ref) reads it back into an equal
machine, and the registry-derived round trip is pinned per kind by the suite.

# The format

The file states what it is, never infers it from how a number is spelled:

```toml
format = 1

[machine]
name = "EIC"
knob_roots = ["ip"]                       # the shared roots (may be empty)
lattices = ["ESR", "HSR"]                 # declaration order: the machine's keys

[knobs.ip]                                # every knob under every root of the machine, by dotted path
half_crossing_angle = 0.0125              # an independent Float64 knob: its value
[knobs.esr]
qf_k1 = { expr = "ip.half_crossing_angle * 2.0" }     # a dependent knob: its expression, never its value
n_cells = { type = "Int", value = 6 }                 # a declared type other than Float64 is explicit
pending = { type = "Float64", unset = true }          # declared and not yet assigned

[lattices.ESR]
eltype = "Float64"
knob_roots = ["esr", "ip"]
reference = { charge = -1.0, mc2 = 510998.95, E0 = 1.0e10 }   # absent when the lattice has none
line = "ESR"                              # the top-level line, one of [lattices.ESR.lines.*]

[lattices.ESR.elements.QF]                # one table per DISTINCT spec object placed, first-placement order
kind = "quadrupole"
L = 0.35
kn = [0.0, { expr = "esr.qf_k1" }, 0.0, 0.0]            # stored parameters, the folded form, keys sorted
numeric_type = "Float64"
[lattices.ESR.elements.D]
kind = "drift"
L = 0.6

[lattices.ESR.hooks.SCHEDULEDOBSERVER]    # in-line hooks: observers and actions with their schedules, ids = the line's labels
type = "ScheduledObserver"
observer = { type = "MomentObserver", name = "electron", moments = ["m100000", "m010000", ...] }   # the moments by their canonical names
schedule = { type = "EveryNSteps", start = 1, step = 10 }

[lattices.ESR.markers.STRONGSTRONGCOLLISION]   # collision markers with the solver on them
type = "StrongStrongCollision"
label = "ip"
poisson_solver = { type = "PICPoissonSolver", grid = [128, 128], slicing = { type = "LongitudinalSlicing", nslices = 15, ... }, ... }

[lattices.ESR.lines.ESR]                  # the top-level line and every nested line kept whole
members = [
  { ref = "QF", path = "ESR/QUADRUPOLE[1]" },
  { ref = "D", path = "ESR/DRIFT[1]", tags = ["cryostat"], overrides = { L = 0.7 } },
  { ref = "STRONGSTRONGCOLLISION", path = "ESR/STRONGSTRONGCOLLISION[1]" },
  { ref = "SCHEDULEDOBSERVER", path = "ESR/SCHEDULEDOBSERVER[1]" },
]
numeric_type = "Float64"                  # the line's own parameters, when it has any beside name and entries
```

Rules, each derived from one source so the writer and the reader cannot
disagree:

- **Elements** are written by their STORED parameters (`params`, the folded
  form the friendly constructors produce: `kn`, not `k1`; `h` and `b0`, not
  `angle`), under `kind`, keys sorted, and read back through the flexible form
  `ElementSpec{kind}(params)`; the suite's per-kind round trip (friendly
  constructor to object to file to object) pins that friendly folding and
  flexible storage agree. A key the kind's `ElementMeta` does not declare is
  refused by name with the kind's declared keys; an unknown kind is refused
  listing the registered kinds. The table's id is the spec's `name`, made
  unique among the lattice's distinct specs with `#2`, `#3`, ... and quoted
  when it is not a bare TOML key; a hook's or a marker's id is the label the
  line gives it (`SCHEDULEDOBSERVER`, `STRONGSTRONGCOLLISION`, made unique the
  same way); distinct spec objects are distinct tables and one object placed
  twice is one table referenced twice, so the identity the family queries rely
  on (`e.spec === qf`) survives the round trip within a lattice. A marker one
  object serves in two lattices is one table per lattice and reloads as two
  equal, distinct markers, which the strong-strong task pairs by label and
  whose solvers it compares by configuration.
- **Values.** Numbers print as TOML numbers, integers as integers and floats
  as floats, so `nst = 4` and `L = 1.0` round-trip their types; a float of a
  narrower type (`Float32`) prints as its `Float64` value and is re-narrowed on
  reading by the element's stored `numeric_type`, exactly as the typed
  constructor form converts (`_as_numeric_type`). A knob expression is the
  inline table `{ expr = "..." }` holding the knob system's surface syntax
  (`string(e)`, parsed by `knob_expression`, a documented total round trip); a
  bare string where a number belongs is refused by name. A `Symbol` prints
  as a bare string when the kind's `ParamMeta` for that key has a `Symbol`
  default or alternative (`misalign_convention = "center"`) and as
  `{ symbol = "..." }` otherwise, and the reader coerces on the same
  evidence; a `String` is a string. A tuple prints as an array and is read
  back as a tuple when the key's `ParamMeta` default is a tuple, as a vector
  when it is a vector, and as `{ tuple = [...] }` or `{ vector = [...] }` when
  the metadata gives no hint or the value's class differs from the hint's; a
  matrix is `{ matrix = [[row], [row]] }`; mixed `(number, expr)` tuples follow
  the same rule. The kind's example value counts as class evidence beside the
  `ParamMeta` default and alternatives, so a bare string where the kind stores
  a number is refused by name even for a key whose default is `nothing`. `nothing` is the
  inline table `{ nothing = true }` (TOML has no null, and a stored `nothing`
  is not an absent key). A `Type` prints as its name (`numeric_type =
  "Float64"`) where the metadata expects a type and as `{ type_name = "..." }`
  elsewhere, and is read through the allowlist of numeric types (`Float64`,
  `Float32`, `Float16`, `BigFloat`, `Int`); a `BigFloat` VALUE is refused at
  write as lossy. A
  `tracking_method` singleton prints as `{ type = "Symplectic6DMap" }` and is
  read through the registry of methods; an `@enum` value as `{ enum =
  "XYCouplingMode", value = "..." }`; a nested `ElementSpec` (the strong
  beam's `thin`) as an inline table with its own `kind`. Unsigned integers
  (`rng_id`) print as decimal integers and are read back by the field's
  type. A function-valued parameter (a `TuneFunction`, a predicate schedule,
  an aperture callback, a spectral shape) cannot be snapshotted and is
  refused by name at write time with the parameter's path.
- **Hooks, markers and solvers** (D6: they stay in the lines) print by their
  option schemas, the three metadata sources that exist and are swept by
  `validate_configuration_metadata()`: `observer_option_schema`,
  `schedule_option_schema`, `solver_option_schema` (requested values only,
  never the `resolved_*` entries), nested option objects (a
  `LongitudinalSlicing`, a schedule, a virtual drift, a launch configuration)
  recursively by theirs, each under `type = "<TypeName>"`, and are rebuilt by
  the type's keyword constructor in the LATTICE's numeric type (the tables
  carry none of their own, so a solver or rule of another numeric type than
  its lattice's is refused by name at write); a key the schema does not
  declare is refused listing the schema's, a key the table omits takes the
  constructor's default; a type with no schema is refused by name. A
  `MomentObserver` prints its resolved moments by their canonical names
  (`m100000`) and is rebuilt through its `moments` keyword.
  Turn rules (`WhiteNoise`, `PinkNoise`) print their fields; a `TurnTable`'s
  offsets go to the sidecar by reference, `{ type = "TurnTable", name =
  "...", length = n, sha256 = "<hex>" }`, and the reader verifies the digest
  of what it loads; a `SpectralNoise` holds a function and is refused.
- **Lines** print every placement as a member `{ ref, path, tags, overrides }`
  (tags and overrides only when present; override values by the element
  rules) referencing an element, hook, marker or kept-whole nested line of
  the lattice by id, with the placement's provenance path verbatim, and are
  rebuilt through the keyword form `BeamLine(; name, entries, ...)`, which
  keeps the paths as written; the line's own parameters (its `numeric_type`,
  offsets) print beside `members`, and its `name` only when it differs from
  the table's id.
- **Knobs.** Every knob under every root of the machine (the lattices' roots
  and the shared ones), by dotted path as nested tables, sorted; independent
  knobs by value, dependent ones by expression, a declared type other than
  `Float64` explicit, an unset knob marked (a knob whose last segment is one
  of the marker words `expr`, `type`, `value`, `unset` cannot be written and
  is refused by name). The reader declares the file's
  independent knobs first and the dependent ones in the dependency order it
  derives from the expressions; a reference to a knob the file does not
  define is refused by name; a path that already exists in the process with
  the SAME definition (type, and value or expression) is accepted as it is,
  one that exists with a different definition is refused by name rather than
  rewired. A reloaded root is a namespace in the registry and not a constant
  bound in any module: `knob_value`, `set_knob!` and `@knob_expr` read and
  write it, while the plain assignment spelling `root.path = v` needs one
  `@knob` declaration under that root in the session. Parsing an expression
  executes nothing: `Meta.parse` yields an
  AST and the knob builder accepts only its whitelisted calls, references and
  literals.
- **The emitter is deterministic** and Octopus's own (`_toml_emit`; the
  standard library's printer renders an array of tables as an array of
  tables, `[[members]]`, not as the one-line inline members the format
  fixes): tables in the order above, keys sorted within a table where the
  format does not fix them, elements in first-placement order, inline tables
  on one line, so two snapshots of one machine are byte-identical and two
  machines differ where their snapshots differ. The sidecar `<path without extension>.tables.h5` is written only
  when the machine holds a table and holds one dataset per table under its
  digest.
- **Refused by name** at write: a value class the rules above do not cover;
  at read: an unknown `format`, a missing `[machine]` or lattice table, an
  unknown key in any table (the kind's or the type's declared keys listed),
  an unknown kind or type, a bare string where a number belongs, an undefined
  or conflicting knob, a member `ref` that names nothing, a sidecar digest
  that does not match.

What the snapshot is not: a resolved lattice (no value beside an expression,
since a number next to a formula is a stale hand copy), an exchange format
for other codes (D17 reads those through tables of their own), or a Julia
program. The run artifact embeds the text (D14): see `read(out, :machine)`.
"""
function write_machine(path::AbstractString, machine::Machine)
    tables = Dict{String,Any}()
    text = machine_toml(machine, tables)
    write(String(path), text)
    isempty(tables) || _toml_write_tables(_toml_tables_path(path), tables)
    return path
end
write_machine(path::AbstractString, lattice::Lattice) = write_machine(path, Machine(lattice))

"""
    machine_toml(machine::Machine) -> String
    machine_toml(machine::Machine, tables::AbstractDict) -> String

The snapshot text of [`write_machine`](@ref) without writing a file: the
deterministic TOML document, byte-identical for equal machines. With the
`tables` dictionary given, every bulk table the machine holds is stored in it
under its SHA-256 hex digest (the writer's sidecar and the run artifact's
`/machine_tables` group both read from such a dictionary), so a caller that
embeds the text elsewhere has the tables to embed beside it.
"""
function machine_toml(machine::Machine, tables::AbstractDict=Dict{String,Any}())
    return sprint(_toml_emit, _toml_document(machine, tables))
end

"""
    read_machine(path; receipt=false) -> Machine
    read_machine(path; receipt=true) -> (machine, receipt)

Read a snapshot written by [`write_machine`](@ref): the file at `path` and
its sidecar of bulk tables when the text references one. The knobs the file
declares are installed in the process's knob registry before the lattices are
built (independent knobs first, then dependents in dependency order), under
the rules of the format: a path already present with the same definition is
kept, one present with a different definition is refused by name, a
reference to a knob the file does not define is refused by name. With
`receipt = true` the second value is a `NamedTuple` recording what was done:
`format`, `declared` (the knob paths this call installed), `existing` (the
paths already present with the same definition), `tables` (the digests
loaded) and `lattices` (the names built). Every refusal names the table, the
key and the remedy.
"""
function read_machine(path::AbstractString; receipt::Bool=false)
    isfile(path) || throw(ArgumentError("machine snapshot: no file at $(repr(String(path)))"))
    text = read(String(path), String)
    digests = _toml_referenced_digests(_toml_parse_document(text))
    tables = isempty(digests) ? nothing : _toml_read_tables(_toml_tables_path(path), digests)
    return parse_machine(text; tables=tables, receipt=receipt)
end

"""
    parse_machine(text::AbstractString; tables=nothing, receipt=false) -> Machine

[`read_machine`](@ref) for a snapshot held in memory: the TOML text, and the
bulk tables as a dictionary from SHA-256 hex digest to offsets vector when
the text references any (`nothing` otherwise; a reference with no table to
read is refused by name). The run artifact's embedded snapshot reads through
this (`read_machine(::TaskOutput)`).
"""
function parse_machine(text::AbstractString; tables=nothing, receipt::Bool=false)
    doc = _toml_parse_document(text)
    top = _TomlContext(Float64, tables, String[])
    for key in sort!(collect(String, keys(doc)))
        key in ("format", "machine", "knobs", "lattices") || _toml_refuse(top,
            "unknown top-level key $(repr(key)); a snapshot holds format, [machine], [knobs.*] and [lattices.*]")
    end
    haskey(doc, "format") || _toml_refuse(top, "the snapshot states no `format`; this reader reads format = 1")
    fmt = doc["format"]
    fmt == 1 || _toml_refuse(top, "unknown snapshot format $(repr(fmt)); this reader reads format = 1")
    haskey(doc, "machine") || _toml_refuse(top, "the snapshot has no [machine] table")
    mt = doc["machine"]
    mctx = _toml_at(top, "machine")
    mt isa AbstractDict || _toml_refuse(mctx, "[machine] must be a table; got $(repr(mt))")
    for key in sort!(collect(String, keys(mt)))
        key in ("name", "knob_roots", "lattices") || _toml_refuse(mctx, "unknown key $(repr(key)) in [machine]; its keys are name, knob_roots, lattices")
    end
    (haskey(mt, "name") && mt["name"] isa AbstractString) || _toml_refuse(mctx, "[machine] needs `name`, a string")
    names = get(mt, "lattices", nothing)
    (names isa AbstractVector && !isempty(names) && all(n -> n isa AbstractString, names)) || _toml_refuse(mctx,
        "[machine] needs `lattices`, a non-empty array of the lattice names in declaration order")
    roots = get(mt, "knob_roots", Any[])
    (roots isa AbstractVector && all(r -> r isa AbstractString, roots)) || _toml_refuse(_toml_at(mctx, "knob_roots"),
        "`knob_roots` must be an array of strings; got $(repr(roots))")
    knobs = get(doc, "knobs", Dict{String,Any}())
    knobs isa AbstractDict || _toml_refuse(_toml_at(top, "knobs"), "[knobs] must be a table; got $(repr(knobs))")
    declared, existing = _toml_declare_knobs!(knobs)
    lattice_tables = get(doc, "lattices", Dict{String,Any}())
    lattice_tables isa AbstractDict || _toml_refuse(_toml_at(top, "lattices"), "[lattices] must be a table of tables")
    for key in sort!(collect(String, keys(lattice_tables)))
        key in names || _toml_refuse(_toml_at(top, "lattices"),
            "the lattice table $(repr(key)) is not listed in [machine].lattices ($(join(names, ", ")))")
    end
    lattices = Lattice[]
    for name in names
        haskey(lattice_tables, name) || _toml_refuse(_toml_at(top, "lattices"),
            "[machine].lattices names $(repr(String(name))) but there is no [lattices.$(name)] table")
        lctx = _toml_at(_toml_at(top, "lattices"), name)
        t = lattice_tables[name]
        t isa AbstractDict || _toml_refuse(lctx, "a lattice table must be a table; got $(repr(t))")
        push!(lattices, _toml_decode_lattice(name, t, lctx))
    end
    machine = Machine(String(mt["name"]); lattices=Tuple(lattices),
                      knob_root=isempty(roots) ? nothing : Tuple(Symbol(r) for r in roots))
    receipt || return machine
    return machine, (format=Int(fmt), declared=declared, existing=existing,
                     tables=_toml_referenced_digests(doc), lattices=String[String(n) for n in names])
end

# ---------------------------------------------------------------------------
# The codec's extension points. Unit A fills the element, line, knob, reference,
# lattice and machine tables and the value rules; unit B registers the object
# types of the hooks, markers, solvers, schedules and turn rules in
# src/lattice/toml_hooks.jl (included after the tasks, whose types it names).
# ---------------------------------------------------------------------------

"""
    _TomlContext(numeric_type, tables, where)

What the codec carries while it walks: `numeric_type`, the lattice's numeric
type (`Float64` outside a lattice), which re-narrows floats on reading and
types the rules it rebuilds; `tables`, the dictionary from SHA-256 hex digest
to offsets vector that bulk data is stored in on writing and read from on
reading (`nothing` on reading when the text came with no tables, so a
reference refuses by name); `where`, the path of the value being coded for
the messages (`lattices.ESR.elements.QF.kn[2]`), extended by `_toml_at`.
"""
struct _TomlContext
    numeric_type::Type
    tables::Union{Nothing,AbstractDict}
    where::Vector{String}
end
_TomlContext(; numeric_type::Type=Float64, tables=Dict{String,Any}()) =
    _TomlContext(numeric_type, tables, String[])

"""
    _toml_at(ctx::_TomlContext, segment::AbstractString) -> _TomlContext

The context one level down, for the messages: the same numeric type and
tables, `where` extended by `segment`.
"""
_toml_at(ctx::_TomlContext, segment::AbstractString) =
    _TomlContext(ctx.numeric_type, ctx.tables, vcat(ctx.where, String(segment)))

"""
    _toml_refuse(ctx::_TomlContext, message::AbstractString)

Throw the codec's `ArgumentError`: `machine snapshot: at <where>: <message>`,
every refusal through one door so the messages share their form.
"""
_toml_refuse(ctx::_TomlContext, message::AbstractString) =
    throw(ArgumentError("machine snapshot: at " * (isempty(ctx.where) ? "the top level" : join(ctx.where, ".")) *
                        ": " * String(message)))

"""
    _toml_store_table!(ctx::_TomlContext, offsets::AbstractVector) -> String
    _toml_table(ctx::_TomlContext, digest::AbstractString) -> Vector

The bulk-table seam between the codec and its container. Storing puts the
offsets (as `Float64`) in `ctx.tables` under their SHA-256 hex digest and
returns the digest; reading returns the vector stored under `digest`, refusing
by name when the context has no tables or holds no such digest (the sidecar
is missing, or the text references a table its container never had), and
when the stored vector's digest is not `digest` (the sidecar was altered).
"""
function _toml_store_table!(ctx::_TomlContext, offsets::AbstractVector)
    ctx.tables === nothing && _toml_refuse(ctx,
        "a bulk table cannot be stored: the context carries no tables dictionary " *
        "(write through machine_toml(machine, tables) or write_machine)")
    data = Float64.(offsets)
    digest = _toml_digest(data)
    ctx.tables[digest] = data
    return digest
end
function _toml_table(ctx::_TomlContext, digest::AbstractString)
    ctx.tables === nothing && _toml_refuse(ctx,
        "the text references a bulk table (sha256 = $(repr(String(digest)))) but no tables were " *
        "given: read the snapshot with its sidecar through read_machine, or pass " *
        "parse_machine(text; tables = Dict(digest => offsets))")
    haskey(ctx.tables, digest) || _toml_refuse(ctx,
        "the text references a bulk table (sha256 = $(repr(String(digest)))) that the tables " *
        "given do not hold; the sidecar is missing it, or belongs to another snapshot " *
        "(held: $(isempty(ctx.tables) ? "none" : join(sort!(collect(String, keys(ctx.tables))), ", ")))")
    data = ctx.tables[digest]
    data isa AbstractVector || _toml_refuse(ctx,
        "the bulk table under sha256 = $(repr(String(digest))) is not a vector; got $(typeof(data))")
    actual = _toml_digest(Float64.(data))
    actual == digest || _toml_refuse(ctx,
        "the bulk table under sha256 = $(repr(String(digest))) hashes to $(actual): the sidecar " *
        "was altered after the snapshot was written")
    return Float64.(data)
end

"""
    _toml_digest(data::Vector{Float64}) -> String

The SHA-256 hex digest of a bulk table's bytes (`reinterpret(UInt8, data)`),
the key a table is stored and verified under.
"""
_toml_digest(data::Vector{Float64}) = bytes2hex(sha256(reinterpret(UInt8, data)))

"""
    _TomlTable(pairs)   an inline table `{ k = v, ... }`, keys in the order given
    _TomlBlock(pairs)   a block table `[a.b]` whose scalar pairs print under its
                        header and whose `_TomlBlock` children print as their own
                        headed tables after it

The emitter's two ordered table forms (the stdlib printer takes dictionaries,
whose iteration order is not the format's). Everything the codec emits for a
value is a TOML scalar, a `Vector`, a `_TomlTable`, or a `Dict{String,Any}`
from `_toml_encode_object` (printed as an inline table, `type` first, the rest
sorted); the structural tables of the document are `_TomlBlock`s.
"""
struct _TomlTable
    pairs::Vector{Pair{String,Any}}
end
struct _TomlBlock
    pairs::Vector{Pair{String,Any}}
end
_TomlTable(pairs::Pair...) = _TomlTable(Pair{String,Any}[String(k) => v for (k, v) in pairs])
_TomlBlock(pairs::Pair...) = _TomlBlock(Pair{String,Any}[String(k) => v for (k, v) in pairs])

"""
    _TOML_TYPE_NAMES :: Dict{String,Type}

The allowlist of the types a snapshot names as strings (`eltype`, an element's
`numeric_type`, a knob's `type`): the numeric types the runtime compiles in.
`_toml_type_name` is the inverse (refusing a type outside the list by name).
"""
const _TOML_TYPE_NAMES = Dict{String,Type}(
    "Float64" => Float64, "Float32" => Float32, "Float16" => Float16,
    "BigFloat" => BigFloat, "Int" => Int,
)
function _toml_type_name(T::Type, ctx::_TomlContext)
    for (name, U) in _TOML_TYPE_NAMES
        U === T && return name
    end
    _toml_refuse(ctx, "the type $(T) cannot be named in a snapshot; the types a snapshot " *
                      "names are $(join(sort!(collect(keys(_TOML_TYPE_NAMES))), ", "))")
end
function _toml_type_from_name(name, ctx::_TomlContext)
    name isa AbstractString || _toml_refuse(ctx, "a type name must be a string; got $(repr(name))")
    haskey(_TOML_TYPE_NAMES, name) || _toml_refuse(ctx,
        "unknown type name $(repr(String(name))); the types a snapshot names are " *
        join(sort!(collect(keys(_TOML_TYPE_NAMES))), ", "))
    return _TOML_TYPE_NAMES[name]
end

# The hint's evidence (`ParamMeta`, or any object with `default` and
# `alternatives`, and `unit` when it has one): whether the key's metadata holds
# a value of class `T` anywhere in its default or alternatives, looking inside
# tuples and arrays, since `kn`'s default is a tuple of numbers and
# `numeric_type`'s alternatives are types.
_toml_hint_values(hint) = hint === nothing ? () : (hint.default, hint.alternatives...)
function _toml_value_holds(v, ::Type{T}) where {T}
    v isa T && return true
    v isa Union{Tuple,AbstractArray} && return any(x -> _toml_value_holds(x, T), v)
    return false
end
_toml_hint_holds(hint, ::Type{T}) where {T} = any(v -> _toml_value_holds(v, T), _toml_hint_values(hint))
_toml_is_number(v) = v isa Number && !(v isa Bool)
# Where a number belongs: the metadata's default or an alternative is a number
# (`Bool` excluded, it is its own TOML class), or the key carries a unit.
_toml_hint_numeric(hint) =
    any(v -> _toml_value_holds_number(v), _toml_hint_values(hint)) ||
    (hint !== nothing && hasproperty(hint, :unit) && !isempty(hint.unit))
function _toml_value_holds_number(v)
    _toml_is_number(v) && return true
    v isa Union{Tuple,AbstractArray} && return any(_toml_value_holds_number, v)
    return false
end
_toml_hint_tuple(hint) = hint !== nothing && hint.default isa Tuple

# The inline-table markers the value rules use; a dictionary parameter whose
# keys spell one of them would read back as the marked class, so the writer
# refuses it by name.
const _TOML_MARKER_KEYS = (
    Set(["expr"]), Set(["symbol"]), Set(["nothing"]), Set(["tuple"]), Set(["vector"]),
    Set(["matrix"]), Set(["type_name"]), Set(["enum", "value"]),
)

"""
    _toml_encode_value(v, hint, ctx::_TomlContext)
    _toml_decode_value(x, hint, ctx::_TomlContext)

The value rules of the format, in both directions: numbers, strings, symbols,
booleans, `nothing`, tuples, vectors, dictionaries, knob expressions, types,
tracking methods, enums, nested specs, and every object `_toml_encode_object`
handles. `hint` is the `ParamMeta` of the key being coded when the metadata
has one (`nothing` otherwise): it decides whether a symbol prints bare and
whether an array reads back as a tuple. Unit B's methods call these for every
option value they nest, so one rule set serves elements and objects alike.
"""
function _toml_encode_value(v, hint, ctx::_TomlContext)
    v isa Bool && return v
    if v isa Integer
        (typemin(Int64) <= v <= typemax(Int64)) || _toml_refuse(ctx,
            "the integer $(v)::$(typeof(v)) lies outside the TOML integer range (a signed 64-bit integer)")
        return Int64(v)
    end
    v isa Union{Float64,Float32,Float16} && return Float64(v)
    v isa AbstractFloat && _toml_refuse(ctx,
        "a $(typeof(v)) value cannot be written as a TOML float without loss (TOML floats are " *
        "binary64); the snapshot holds Float64, Float32 and Float16 values")
    v isa Number && _toml_refuse(ctx,
        "a $(typeof(v)) value is not a class the snapshot format covers (real numbers, strings, " *
        "symbols, booleans, nothing, tuples, vectors, matrices, dictionaries, knob expressions, " *
        "types, tracking methods, enums, nested element specs and the registered objects)")
    v isa AbstractString && return String(v)
    v isa Symbol && return _toml_hint_holds(hint, Symbol) ? String(v) : _TomlTable("symbol" => String(v))
    v === nothing && return _TomlTable("nothing" => true)
    v isa AbstractKnobExpression && return _TomlTable("expr" => string(v))
    if v isa Type
        name = _toml_type_name(v, ctx)
        return _toml_hint_holds(hint, Type) ? name : _TomlTable("type_name" => name)
    end
    v isa Function && _toml_refuse(ctx,
        "a function-valued parameter ($(v)) cannot be snapshotted: the snapshot is data, and a " *
        "function has no data form; remove it or replace it by a parameterized form")
    if v isa Tuple
        v isa NamedTuple && _toml_refuse(ctx, _toml_holds_function(v) ?
            "a function-valued parameter (a $(typeof(v))) cannot be snapshotted: the snapshot is data, and a " *
            "function has no data form; remove it or replace it by a parameterized form" :
            "a NamedTuple value is not a class the snapshot format covers; store a Dict or a Tuple")
        items = Any[_toml_encode_value(v[i], hint, _toml_at(ctx, "[$(i)]")) for i in eachindex(v)]
        return _toml_hint_tuple(hint) ? items : _TomlTable("tuple" => items)
    end
    if v isa AbstractVector
        items = Any[_toml_encode_value(v[i], hint, _toml_at(ctx, "[$(i)]")) for i in eachindex(v)]
        return _toml_hint_tuple(hint) ? _TomlTable("vector" => items) : items
    end
    if v isa AbstractMatrix
        rows = Any[Any[_toml_encode_value(v[i, j], hint, _toml_at(ctx, "[$(i),$(j)]")) for j in axes(v, 2)]
                   for i in axes(v, 1)]
        return _TomlTable("matrix" => rows)
    end
    v isa AbstractArray && _toml_refuse(ctx,
        "an array of $(ndims(v)) dimensions is not a class the snapshot format covers (vectors and matrices are)")
    if v isa AbstractDict
        ks = Set(String[string(k) for k in keys(v)])
        for marker in _TOML_MARKER_KEYS
            ks == marker && _toml_refuse(ctx,
                "a dictionary whose keys are exactly $(join(sort!(collect(marker)), ", ")) would read back " *
                "as the marked value class; rename its keys")
        end
        (haskey(v, "type") || haskey(v, :type) || haskey(v, "kind") || haskey(v, :kind)) && _toml_refuse(ctx,
            "a dictionary with a `type` or `kind` key would read back as an object or an element; rename the key")
        pairs = Pair{String,Any}[]
        for k in sort!(collect(keys(v)); by=string)
            push!(pairs, string(k) => _toml_encode_value(v[k], nothing, _toml_at(ctx, string(k))))
        end
        return _TomlTable(pairs)
    end
    v isa ElementSpec{:line} && _toml_refuse(ctx,
        "a beam line is not a parameter value; lines are written as [lattices.<name>.lines.*] tables")
    v isa ElementSpec && return _toml_element_table(v, ctx)
    if v isa Enum
        name = string(nameof(typeof(v)))
        get(_TOML_OBJECT_TYPES, name, nothing) === typeof(v) || _toml_refuse(ctx,
            "the enum type $(typeof(v)) is not registered in the snapshot's object types")
        return _TomlTable("enum" => name, "value" => string(v))
    end
    return _toml_encode_object(v, ctx)
end
function _toml_decode_value(x, hint, ctx::_TomlContext)
    x isa Bool && return x
    if x isa Integer
        d = hint === nothing ? nothing : hint.default
        # Read back by the declared type where the metadata declares one
        # (`rng_id`'s default is an unsigned count); an `Int` default or none
        # keeps the TOML integer.
        d isa Integer && !(d isa Bool) && !(d isa Int) && return typeof(d)(x)
        return Int(x)
    end
    if x isa AbstractFloat
        T = ctx.numeric_type
        return T <: AbstractFloat ? _as_numeric_type(T, Float64(x)) : Float64(x)
    end
    if x isa AbstractString
        _toml_hint_holds(hint, Symbol) && return Symbol(x)
        _toml_hint_holds(hint, Type) && return _toml_type_from_name(x, ctx)
        _toml_hint_numeric(hint) && _toml_refuse(ctx,
            "a bare string $(repr(String(x))) where a number belongs; write the number as a TOML " *
            "number (0.6, not \"0.6\"), or a knob expression as { expr = \"...\" }")
        return String(x)
    end
    if x isa AbstractVector
        items = Any[_toml_decode_value(x[i], hint, _toml_at(ctx, "[$(i)]")) for i in eachindex(x)]
        return _toml_hint_tuple(hint) ? Tuple(items) : _toml_narrow_vector(items)
    end
    if x isa AbstractDict
        ks = Set(String[string(k) for k in keys(x)])
        if ks == Set(["expr"])
            return _toml_decode_knob_expression(x["expr"], ctx)
        elseif ks == Set(["nothing"])
            x["nothing"] === true || _toml_refuse(ctx, "{ nothing = ... } takes `true`; got $(repr(x["nothing"]))")
            return nothing
        elseif ks == Set(["symbol"])
            x["symbol"] isa AbstractString || _toml_refuse(ctx, "{ symbol = ... } takes a string; got $(repr(x["symbol"]))")
            return Symbol(x["symbol"])
        elseif ks == Set(["tuple"]) || ks == Set(["vector"])
            key = first(ks)
            arr = x[key]
            arr isa AbstractVector || _toml_refuse(ctx, "{ $(key) = ... } takes an array; got $(repr(arr))")
            items = Any[_toml_decode_value(arr[i], hint, _toml_at(ctx, "[$(i)]")) for i in eachindex(arr)]
            return key == "tuple" ? Tuple(items) : _toml_narrow_vector(items)
        elseif ks == Set(["matrix"])
            rows = x["matrix"]
            (rows isa AbstractVector && all(r -> r isa AbstractVector, rows)) || _toml_refuse(ctx,
                "{ matrix = ... } takes an array of row arrays; got $(repr(rows))")
            n = length(rows)
            m = n == 0 ? 0 : length(rows[1])
            all(r -> length(r) == m, rows) || _toml_refuse(ctx, "{ matrix = ... } rows differ in length")
            items = Any[_toml_decode_value(rows[i][j], hint, _toml_at(ctx, "[$(i),$(j)]")) for i in 1:n, j in 1:m]
            T = n * m == 0 ? Any : mapreduce(typeof, typejoin, items)
            return isconcretetype(T) ? Matrix{T}(items) : items
        elseif ks == Set(["type_name"])
            return _toml_type_from_name(x["type_name"], ctx)
        elseif ks == Set(["enum", "value"])
            return _toml_decode_enum(x["enum"], x["value"], ctx)
        elseif haskey(x, "type")
            return _toml_decode_object(x, ctx)
        elseif haskey(x, "kind")
            return _toml_decode_element(x, ctx)
        end
        d = hint === nothing ? nothing : hint.default
        out = d isa AbstractDict && keytype(d) === Symbol ? Dict{Symbol,Any}() : Dict{String,Any}()
        for k in sort!(collect(String, keys(x)))
            out[out isa Dict{Symbol,Any} ? Symbol(k) : k] = _toml_decode_value(x[k], nothing, _toml_at(ctx, k))
        end
        return out
    end
    _toml_refuse(ctx, "a TOML value of type $(typeof(x)) ($(repr(x))) is not a class the snapshot format reads")
end

# A decoded array narrowed to the one concrete element type its items share
# (`Vector{Float64}` for `[0.0, 1.0]`), `Vector{Any}` when they share none.
function _toml_narrow_vector(items::Vector{Any})
    isempty(items) && return items
    T = mapreduce(typeof, typejoin, items)
    return isconcretetype(T) ? Vector{T}(items) : items
end

"""
    _toml_decode_knob_expression(text, ctx) -> AbstractKnobExpression

`knob_expression(text)` with the codec's refusals: the text must be a string,
parse as Julia syntax, lower to the knob builder's whitelisted calls, references
and literals, and reference knobs the process knows (the file's knobs are
declared before any lattice is read, so an unknown reference here names a knob
the file does not define). Parsing executes nothing: `Meta.parse` yields an
AST and `knob_expression` lowers it.
"""
function _toml_decode_knob_expression(text, ctx::_TomlContext)
    text isa AbstractString || _toml_refuse(ctx, "{ expr = ... } takes a string; got $(repr(text))")
    try
        return knob_expression(String(text))
    catch err
        err isa Union{ArgumentError,Base.Meta.ParseError} || rethrow()
        _toml_refuse(ctx, "the knob expression $(repr(String(text))) cannot be read: $(sprint(showerror, err))")
    end
end

function _toml_decode_enum(name, value, ctx::_TomlContext)
    name isa AbstractString || _toml_refuse(ctx, "{ enum = ... } takes a type name string; got $(repr(name))")
    T = get(_TOML_OBJECT_TYPES, name, nothing)
    (T isa Type && T <: Enum) || _toml_refuse(ctx,
        "unknown enum type $(repr(String(name))); the registered enum types are " *
        join(sort!(String[k for (k, U) in _TOML_OBJECT_TYPES if U <: Enum]), ", "))
    for inst in instances(T)
        string(inst) == value && return inst
    end
    _toml_refuse(ctx, "unknown value $(repr(value)) of enum $(name); its values are " *
                      join(String[string(i) for i in instances(T)], ", "))
end

"""
    _TOML_OBJECT_TYPES :: Dict{String,Type}

The objects a snapshot may hold under `type = "<name>"`: observers, actions,
schedules, solvers and their nested option objects, turn rules, tracking
methods, enums. Registered by name (`nameof(T)`) by the files that know the
types; the reader resolves a name through this table and refuses one it does
not hold, listing the names it does. Derived, never hand-listed: the suite's
tripwire checks every concrete observer, schedule, solver and rule type the
registry knows is either registered here or in the documented refusal list.
"""
const _TOML_OBJECT_TYPES = Dict{String,Type}()

"""
    _toml_encode_object(x, ctx) -> Dict{String,Any}

Encode a non-element object (a hook, a marker, a solver, a schedule, a rule, a
tracking method, an enum value) as a TOML table with `type = "<name>"` and its
options or fields by the format's value rules; `ctx` carries the lattice's
numeric type, the tables dictionary for bulk data and the path for messages.
The fallback refuses by name: an object of a type nothing registered cannot be
snapshotted.
"""
function _toml_encode_object(x, ctx::_TomlContext)
    T = typeof(x)
    name = string(nameof(T))
    if get(_TOML_OBJECT_TYPES, name, nothing) === T && fieldcount(T) == 0 && isconcretetype(T)
        # A registered singleton (a tracking method): its name is its data.
        return Dict{String,Any}("type" => name)
    end
    _toml_holds_function(x) && _toml_refuse(ctx,
        "a function-valued parameter (a $(nameof(T)) holding a function) cannot be snapshotted: the snapshot " *
        "is data, and a function has no data form; remove it or replace it by a parameterized form")
    _toml_refuse(ctx,
        "an object of type $(T) cannot be snapshotted: no snapshot rule is registered for it" *
        (isempty(_TOML_OBJECT_TYPES) ? "" :
            " (the registered object types are $(join(sort!(collect(keys(_TOML_OBJECT_TYPES))), ", ")))"))
end

"""
    _toml_holds_function(x) -> Bool

Whether a value is or holds a function: a `Function`, or a struct, tuple,
named tuple, array or dictionary with one among its fields or items,
recursively (a `TuneFunction` holding its callable, a predicate schedule, a
spectral shape). The writer's refusal names such a parameter as
function-valued rather than as an object without a rule.
"""
function _toml_holds_function(x)
    x isa Function && return true
    x isa Union{Number,AbstractString,Symbol,Nothing,Type,AbstractKnobExpression} && return false
    x isa Union{Tuple,AbstractArray} && return any(_toml_holds_function, x)
    x isa AbstractDict && return any(_toml_holds_function, values(x))
    x isa Module && return false
    isprimitivetype(typeof(x)) && return false
    return any(f -> isdefined(x, f) && _toml_holds_function(getfield(x, f)), fieldnames(typeof(x)))
end

"""
    _toml_decode_object(tbl::AbstractDict, ctx)
    _toml_decode_object(::Type{T}, tbl::AbstractDict, ctx)

Rebuild an object from a `type = "<name>"` table: the two-argument form
resolves the name through `_TOML_OBJECT_TYPES` (an unregistered name refused
listing the registered ones) and dispatches to the three-argument form on the
resolved type, which the files that register a type define for it (the type's
keyword constructor or fields; unknown keys refused by name). The fallback of
the three-argument form rebuilds a registered field-less singleton (a tracking
method) from its name alone, refusing any other key, and refuses every other
type by name.
"""
function _toml_decode_object(tbl::AbstractDict, ctx::_TomlContext)
    haskey(tbl, "type") || _toml_refuse(ctx, "an object table needs `type`")
    name = tbl["type"]
    name isa AbstractString || _toml_refuse(ctx, "`type` must be a string naming the object type; got $(repr(name))")
    T = get(_TOML_OBJECT_TYPES, name, nothing)
    T === nothing && _toml_refuse(ctx,
        "unknown object type $(repr(String(name))); the registered object types are " *
        (isempty(_TOML_OBJECT_TYPES) ? "none" : join(sort!(collect(keys(_TOML_OBJECT_TYPES))), ", ")))
    return _toml_decode_object(T, tbl, ctx)
end
function _toml_decode_object(::Type{T}, tbl::AbstractDict, ctx::_TomlContext) where {T}
    if isconcretetype(T) && fieldcount(T) == 0 && !(T <: Enum)
        for key in keys(tbl)
            key == "type" || _toml_refuse(ctx, "unknown key $(repr(key)) for the object type $(nameof(T)), which has no options")
        end
        return T()
    end
    _toml_refuse(ctx, "the object type $(nameof(T)) is registered but has no snapshot reader; its table cannot be rebuilt")
end

# The object types this file knows: the tracking-method singletons and the
# enum types defined in the module, derived from the type tree at include time
# (every concrete `AbstractTrackingMethod`, every `Enum` whose parent module is
# this one); unit B's file registers the hooks, markers, solvers, schedules and
# rules after the tasks define them.
for T in subtypes(AbstractTrackingMethod)
    isconcretetype(T) && (_TOML_OBJECT_TYPES[string(nameof(T))] = T)
end
for T in subtypes(Enum)
    parentmodule(T) === (@__MODULE__) && (_TOML_OBJECT_TYPES[string(nameof(T))] = T)
end

"""
    _toml_element_hint(meta::ElementMeta, key::Symbol) -> Union{Nothing,ParamMeta}

The hint the element rules read for `key`: the kind's `ParamMeta` (the
placement parameters included), with the kind's example value for the key
appended to its `alternatives` as further evidence of the key's value class
(`L` of a drift is declared required with no default and no unit, and the
example's `L = 1.0` is what says a number belongs there). The writer and the
reader use the same hint, so the two cannot disagree.
"""
function _toml_element_hint(meta::ElementMeta, key::Symbol)
    pm = get(meta.parameters, key, nothing)
    pm === nothing && (pm = get(_PLACEMENT_PARAMS, key, nothing))
    pm === nothing && return nothing
    ex = meta.example
    (ex isa ElementSpec && haskey(getfield(ex, :params), key)) || return pm
    v = getfield(ex, :params)[key]
    return ParamMeta(pm.required, pm.unit, pm.default, pm.meaning, (pm.alternatives..., v))
end

"""
    _toml_element_table(spec::ElementSpec, ctx) -> _TomlTable
    _toml_decode_element(tbl::AbstractDict, ctx) -> ElementSpec

The element rules of the format. Writing: the spec's STORED parameters (the
folded form) under `kind`, keys sorted, each value by the value rules with the
kind's hint for its key; a stored key the kind's `ElementMeta` does not declare
is refused by name (the reader would refuse it). Reading: `kind` resolved
through the registry (unknown kinds refused listing the registered ones), every
key checked against the kind's declared keys (the placement parameters
included; unknown keys refused listing them), the element's own `numeric_type`
read first so the other values re-narrow by it, then the flexible form
`ElementSpec{kind}(params)`.
"""
function _toml_element_table(spec::ElementSpec, ctx::_TomlContext)
    k = kind(spec)
    meta = _element_meta_or_nothing(k)
    meta === nothing && _toml_refuse(ctx, "the element kind $(repr(k)) is not registered; the snapshot writes registered kinds only")
    stored = getfield(spec, :params)
    declared = _toml_declared_keys(meta)
    pairs = Pair{String,Any}["kind" => String(k)]
    for key in sort!(collect(keys(stored)); by=string)
        key in declared || _toml_refuse(_toml_at(ctx, string(key)),
            "the stored parameter $(key) is not declared by the kind $(repr(k)) (its declared keys are " *
            "$(join(sort!(map(string, collect(declared))), ", "))); the reader would refuse it, so the writer does")
        push!(pairs, string(key) => _toml_encode_value(stored[key], _toml_element_hint(meta, key), _toml_at(ctx, string(key))))
    end
    return _TomlTable(pairs)
end
_toml_declared_keys(meta::ElementMeta) =
    Set{Symbol}((keys(meta.parameters)..., _PLACEMENT_PARAM_KEYS..., :name, :numeric_type))
function _toml_decode_element(tbl::AbstractDict, ctx::_TomlContext)
    haskey(tbl, "kind") || _toml_refuse(ctx, "an element table needs `kind`")
    kname = tbl["kind"]
    kname isa AbstractString || _toml_refuse(ctx, "`kind` must be a string; got $(repr(kname))")
    k = Symbol(kname)
    meta = _element_meta_or_nothing(k)
    (meta === nothing || k === :line) && _toml_refuse(ctx,
        "unknown element kind $(repr(String(kname))); the registered kinds are " *
        join(sort!(String[string(q) for q in keys(ELEMENT_META_BY_KIND) if q !== :line]), ", "))
    declared = _toml_declared_keys(meta)
    for key in sort!(collect(String, keys(tbl)))
        key == "kind" && continue
        Symbol(key) in declared || _toml_refuse(_toml_at(ctx, key),
            "unknown key $(repr(key)) for the kind $(repr(String(kname))); its declared keys are " *
            join(sort!(map(string, collect(declared))), ", "))
    end
    ectx = ctx
    if haskey(tbl, "numeric_type")
        T = _toml_decode_value(tbl["numeric_type"], _toml_element_hint(meta, :numeric_type), _toml_at(ctx, "numeric_type"))
        T isa Type || _toml_refuse(_toml_at(ctx, "numeric_type"), "numeric_type must name a type; got $(repr(T))")
        ectx = _TomlContext(T, ctx.tables, ctx.where)
    end
    params = Dict{Symbol,Any}()
    for key in sort!(collect(String, keys(tbl)))
        key == "kind" && continue
        sym = Symbol(key)
        params[sym] = _toml_decode_value(tbl[key], _toml_element_hint(meta, sym), _toml_at(ectx, key))
    end
    return ElementSpec{k}(params)
end

"""
    _toml_placed_objects(line::ElementSpec{:line}) -> Vector{Any}

The distinct objects a lattice's line places, in first-placement order: the
line itself first, then each placement's object the first time it appears, a
kept-whole nested line followed by its own interior (depth first), so one spec
placed twice is listed once and the identity the family queries rely on
survives as one table referenced twice.
"""
function _toml_placed_objects(line::ElementSpec{:line})
    out = Any[]
    seen = IdDict{Any,Bool}()
    _toml_collect_objects!(out, seen, line)
    return out
end
function _toml_collect_objects!(out, seen, line::ElementSpec{:line})
    haskey(seen, line) && return out
    seen[line] = true
    push!(out, line)
    for e in line_entries(line)
        obj = getfield(e, :spec)
        if obj isa ElementSpec{:line}
            _toml_collect_objects!(out, seen, obj)
        elseif !haskey(seen, obj)
            seen[obj] = true
            push!(out, obj)
        end
    end
    return out
end

"""
    _toml_ids(lattice::Lattice) -> IdDict{Any,String}

The table id of every object the lattice places (`_toml_placed_objects`): its
line label (`_entry_label`: an element's `name` or its upper-cased kind, a
hook's or marker's upper-cased type name, a line's name), made unique among the
lattice's objects with `#2`, `#3`, ... in first-placement order. One id
namespace serves the elements, hooks, markers and lines, so a member `ref`
names exactly one object.
"""
function _toml_ids(lattice::Lattice)
    ids = IdDict{Any,String}()
    counts = Dict{String,Int}()
    for obj in _toml_placed_objects(getfield(lattice, :line))
        label = _entry_label(obj)
        n = _next_ordinal!(counts, label)
        ids[obj] = n == 1 ? label : "$(label)#$(n)"
    end
    return ids
end

"""
    _toml_object_group(obj) -> String

The lattice table an object is written under: `"lines"` for a kept-whole line,
`"elements"` for an element spec, `"markers"` for a collision marker (a
`StrongStrongCollision`, recognised by its type name so the lattice layer names
no task type), `"hooks"` for everything else a line holds (observers and
actions with their schedules).
"""
_toml_object_group(obj) =
    obj isa ElementSpec{:line} ? "lines" :
    obj isa ElementSpec ? "elements" :
    nameof(typeof(obj)) === :StrongStrongCollision ? "markers" : "hooks"

"""
    _toml_line_table(line::ElementSpec{:line}, ids::IdDict, ctx) -> _TomlTable
    _toml_decode_line(tbl::AbstractDict, id::AbstractString, objects::AbstractDict, ctx) -> ElementSpec{:line}

The line rules of the format. Writing: `members`, one `{ ref, path, tags,
overrides }` per placement (`ref` the object's id in `ids`, `path` the
provenance verbatim as `entry_path` prints it, `tags` sorted and `overrides` by
the element rules with the referenced kind's hints, both only when present),
then `name` when it differs from the table's id, then the line's own parameters
sorted (everything stored beside `name` and `entries`). A path segment holding
`/`, `[` or `]` cannot be printed unambiguously and is refused by name.
Reading: every member's `ref` resolved in `objects` (an id naming nothing
refused listing the ids), its path parsed back (`_toml_parse_path`), tags and
overrides rebuilt, the own parameters decoded with the line kind's hints
(unknown keys refused listing them), and the line rebuilt through the keyword
form `BeamLine(; name, entries, ...)`, which keeps the paths as written.
"""
function _toml_line_table(line::ElementSpec{:line}, ids::IdDict, ctx::_TomlContext)
    members = Any[]
    for (i, e) in enumerate(line_entries(line))
        obj = getfield(e, :spec)
        mctx = _toml_at(ctx, "members[$(i)]")
        haskey(ids, obj) || _toml_refuse(mctx, "the placement's object has no id (not a placed object of this lattice)")
        for (seg, _) in getfield(e, :path)
            any(c -> c in ('/', '[', ']'), seg) && _toml_refuse(mctx,
                "the path segment $(repr(seg)) holds a path delimiter (/, [ or ]) and cannot be printed " *
                "unambiguously; rename the element")
        end
        pairs = Pair{String,Any}["ref" => ids[obj], "path" => entry_path(e)]
        tags = getfield(e, :tags)
        isempty(tags) || push!(pairs, "tags" => Any[String(t) for t in sort!(collect(tags); by=string)])
        overrides = getfield(e, :overrides)
        if !isempty(overrides)
            meta = obj isa ElementSpec ? _element_meta_or_nothing(kind(obj)) : nothing
            opairs = Pair{String,Any}[]
            for key in sort!(collect(keys(overrides)); by=string)
                hint = meta === nothing ? nothing : _toml_element_hint(meta, key)
                push!(opairs, string(key) => _toml_encode_value(overrides[key], hint, _toml_at(mctx, "overrides.$(key)")))
            end
            push!(pairs, "overrides" => _TomlTable(opairs))
        end
        push!(members, _TomlTable(pairs))
    end
    pairs = Pair{String,Any}["members" => members]
    nm = line_name(line)
    nm == get(ids, line, nm) || push!(pairs, "name" => nm)
    meta = element_meta(:line)
    stored = getfield(line, :params)
    declared = _toml_declared_keys(meta)
    for key in sort!(collect(keys(stored)); by=string)
        (key === :name || key === :entries) && continue
        key in declared || _toml_refuse(_toml_at(ctx, string(key)),
            "the stored line parameter $(key) is not declared by the line kind (its declared keys are " *
            "$(join(sort!(map(string, collect(declared))), ", ")))")
        push!(pairs, string(key) => _toml_encode_value(stored[key], _toml_element_hint(meta, key), _toml_at(ctx, string(key))))
    end
    return _TomlTable(pairs)
end

const _TOML_MEMBER_KEYS = ("ref", "path", "tags", "overrides")

function _toml_decode_line(tbl::AbstractDict, id::AbstractString, objects::AbstractDict, ctx::_TomlContext)
    haskey(tbl, "members") || _toml_refuse(ctx, "a line table needs `members`")
    members = tbl["members"]
    members isa AbstractVector || _toml_refuse(_toml_at(ctx, "members"), "`members` must be an array of inline tables; got $(repr(members))")
    meta = element_meta(:line)
    declared = _toml_declared_keys(meta)
    own = Dict{Symbol,Any}()
    lctx = ctx
    if haskey(tbl, "numeric_type")
        T = _toml_decode_value(tbl["numeric_type"], _toml_element_hint(meta, :numeric_type), _toml_at(ctx, "numeric_type"))
        T isa Type || _toml_refuse(_toml_at(ctx, "numeric_type"), "numeric_type must name a type; got $(repr(T))")
        lctx = _TomlContext(T, ctx.tables, ctx.where)
    end
    for key in sort!(collect(String, keys(tbl)))
        (key == "members" || key == "name") && continue
        sym = Symbol(key)
        (sym in declared && sym !== :entries) || _toml_refuse(_toml_at(ctx, key),
            "unknown key $(repr(key)) for a line table; its keys are members, name and the line's own " *
            "parameters $(join(sort!(map(string, collect(setdiff(declared, (:name, :entries))))), ", "))")
        own[sym] = _toml_decode_value(tbl[key], _toml_element_hint(meta, sym), _toml_at(lctx, key))
    end
    name = get(tbl, "name", id)
    name isa AbstractString || _toml_refuse(_toml_at(ctx, "name"), "`name` must be a string; got $(repr(name))")
    entries = LineEntry[]
    for (i, m) in enumerate(members)
        mctx = _toml_at(ctx, "members[$(i)]")
        m isa AbstractDict || _toml_refuse(mctx, "a member must be an inline table { ref, path, tags, overrides }; got $(repr(m))")
        for key in keys(m)
            key in _TOML_MEMBER_KEYS || _toml_refuse(mctx, "unknown member key $(repr(key)); the member keys are $(join(_TOML_MEMBER_KEYS, ", "))")
        end
        (haskey(m, "ref") && m["ref"] isa AbstractString) || _toml_refuse(mctx, "a member needs `ref`, the id of the object it places")
        (haskey(m, "path") && m["path"] isa AbstractString) || _toml_refuse(mctx, "a member needs `path`, its provenance path")
        ref = m["ref"]
        haskey(objects, ref) || _toml_refuse(mctx,
            "the member ref $(repr(String(ref))) names no element, hook, marker or line of this lattice; its ids are " *
            join(sort!(collect(String, keys(objects))), ", "))
        obj = objects[ref]
        tags = Set{Symbol}()
        if haskey(m, "tags")
            ts = m["tags"]
            (ts isa AbstractVector && all(t -> t isa AbstractString, ts)) || _toml_refuse(_toml_at(mctx, "tags"),
                "`tags` must be an array of strings; got $(repr(ts))")
            foreach(t -> push!(tags, Symbol(t)), ts)
        end
        overrides = Dict{Symbol,Any}()
        if haskey(m, "overrides")
            ov = m["overrides"]
            ov isa AbstractDict || _toml_refuse(_toml_at(mctx, "overrides"), "`overrides` must be an inline table; got $(repr(ov))")
            ometa = obj isa ElementSpec ? _element_meta_or_nothing(kind(obj)) : nothing
            octx = obj isa ElementSpec && haskey(getfield(obj, :params), :numeric_type) ?
                   _TomlContext(numeric_type(obj), ctx.tables, ctx.where) : lctx
            for key in sort!(collect(String, keys(ov)))
                sym = Symbol(key)
                if ometa !== nothing
                    sym in _toml_declared_keys(ometa) || _toml_refuse(_toml_at(mctx, "overrides.$(key)"),
                        "unknown override key $(repr(key)) for the kind $(repr(kind(obj))); its declared keys are " *
                        join(sort!(map(string, collect(_toml_declared_keys(ometa)))), ", "))
                end
                hint = ometa === nothing ? nothing : _toml_element_hint(ometa, sym)
                overrides[sym] = _toml_decode_value(ov[key], hint, _toml_at(octx, "overrides.$(key)"))
            end
        end
        push!(entries, LineEntry(obj, _toml_parse_path(m["path"], _toml_at(mctx, "path")), tags, overrides))
    end
    return BeamLine(; name=String(name), entries=entries, own...)
end

"""
    _toml_parse_path(text, ctx) -> Vector{Tuple{String,Int}}

The inverse of `entry_path`: `/`-separated segments, each `NAME` (ordinal 1)
or `NAME[n]` with `n >= 1`; anything else refused by name.
"""
function _toml_parse_path(text::AbstractString, ctx::_TomlContext)
    out = Tuple{String,Int}[]
    for part in split(text, '/')
        m = match(r"^([^\[\]]*)(?:\[(\d+)\])?$", part)
        m === nothing && _toml_refuse(ctx,
            "cannot parse the path segment $(repr(String(part))) of $(repr(String(text))); expected NAME or NAME[n]")
        ord = m.captures[2] === nothing ? 1 : parse(Int, m.captures[2])
        ord >= 1 || _toml_refuse(ctx, "ordinals are 1-based; got $(ord) in $(repr(String(text)))")
        push!(out, (String(m.captures[1]), ord))
    end
    return out
end

"""
    _toml_knobs_table(roots) -> _TomlBlock
    _toml_declare_knobs!(tbl::AbstractDict) -> (declared, existing)

The knob rules of the format. Writing: every knob under every root (the
lattices' roots and the machine's shared ones; `list_knobs` per root, sorted),
its definition read from the registry under the lock, as nested tables by
dotted path: an independent `Float64` knob by its value, a dependent knob by
`{ expr = string(expression) }`, a declared type other than `Float64` explicit
(`{ type = "Int", value = 6 }`, `{ type = "Float32", expr = "..." }`), an
unset knob `{ type = "...", unset = true }`. Refused by name: a knob type
outside `_TOML_TYPE_NAMES`, a value that cannot be written without loss, a
knob whose last path segment is one of the definition keys (`expr`, `type`,
`value`, `unset`), which would read back as a definition.

Reading: the nested tables flattened to dotted paths (a table holding `expr`,
`unset` or `value` is a definition, any other a namespace), every path's
segments checked as identifiers and against the knob system's reserved names,
expressions lowered through the knob builder (`_lower_knob`: whitelisted calls,
references and literals; nothing executes) and their references required to
be knobs of the FILE (a reference to a knob the file does not define is
refused by name, however the process is populated); then, under one lock,
independent and unset knobs installed first and dependent ones in the
dependency order derived from the expressions (a cycle refused by name). A
path already in the registry with the SAME definition (type, and value or
expression, or unset) is reported in `existing` and left as it is; one with a
different definition is refused by name, never rewired. Every refusal is
checked before anything is installed, so a refused file leaves the registry
untouched.

What a reloaded knob namespace supports: `knob_value`, `set_knob!`,
`knob_expression`, `@knob_expr(root.path)` and `knob_report`, since these read
the registry by path. What it does not: the plain-assignment spelling through
the root constant (`root.path = 2.0`), which `@knob` binds in the declaring
module (`_ensure_knob_root`) and which no function can bind in a caller's
module; declare the root with `@knob root.path` once to get it.
"""
function _toml_knobs_table(roots)
    paths = Symbol[]
    for r in sort!(unique!(Symbol[Symbol(r) for r in roots]); by=string)
        append!(paths, list_knobs(string(r)))
    end
    sort!(unique!(paths); by=string)
    block = _TomlBlock()
    lock(_KNOB_LOCK) do
        for path in paths
            entry = _KNOB_TABLE[path]
            segs = split(string(path), '.')
            kctx = _TomlContext(Float64, nothing, ["knobs", segs...])
            String(segs[end]) in ("expr", "type", "value", "unset") && _toml_refuse(kctx,
                "a knob named $(segs[end]) cannot be written: the name is one of the definition keys " *
                "(expr, type, value, unset) and would read back as a definition; rename the knob")
            tname = _toml_type_name(entry.type, kctx)
            value = if entry.expression !== nothing
                entry.type === Float64 ? _TomlTable("expr" => string(entry.expression)) :
                    _TomlTable("type" => tname, "expr" => string(entry.expression))
            elseif entry.value === nothing
                _TomlTable("type" => tname, "unset" => true)
            else
                v = _toml_encode_value(entry.value, nothing, kctx)
                v isa Union{Int64,Float64} || _toml_refuse(kctx, "a knob value must be a number; got $(repr(entry.value))")
                entry.type === Float64 ? v : _TomlTable("type" => tname, "value" => v)
            end
            parent = block
            for seg in segs[1:end-1]
                i = findfirst(p -> p.first == seg, parent.pairs)
                if i === nothing
                    child = _TomlBlock()
                    push!(parent.pairs, String(seg) => child)
                    parent = child
                else
                    parent = parent.pairs[i].second
                end
            end
            push!(parent.pairs, String(segs[end]) => value)
        end
    end
    return block
end

_toml_knob_is_definition(x) = x isa AbstractDict && (haskey(x, "expr") || haskey(x, "unset") || haskey(x, "value"))

function _toml_flatten_knobs!(out::Vector{Pair{String,Any}}, tbl::AbstractDict, prefix::String)
    for key in sort!(collect(String, keys(tbl)))
        path = isempty(prefix) ? key : prefix * "." * key
        v = tbl[key]
        if v isa AbstractDict && !_toml_knob_is_definition(v)
            _toml_flatten_knobs!(out, v, path)
        else
            push!(out, path => v)
        end
    end
    return out
end

function _toml_declare_knobs!(tbl::AbstractDict)
    flat = _toml_flatten_knobs!(Pair{String,Any}[], tbl, "")
    paths = Set{Symbol}(Symbol(p.first) for p in flat)
    # Every definition read and checked first; nothing installed yet.
    defs = NamedTuple{(:path, :type, :expr, :value, :unset),Tuple{Symbol,Type,Any,Any,Bool}}[]
    for (pathstr, v) in flat
        ctx = _TomlContext(Float64, nothing, ["knobs", split(pathstr, '.')...])
        for seg in split(pathstr, '.')
            Base.isidentifier(seg) || _toml_refuse(ctx, "the knob path segment $(repr(String(seg))) is not an identifier")
        end
        path = Symbol(pathstr)
        haskey(_KNOB_NAMED_CONSTANTS, path) && _toml_refuse(ctx,
            "cannot declare a knob named $(path): knob expressions read it as the literal constant " *
            "$(_KNOB_NAMED_CONSTANTS[path])")
        if v isa AbstractDict
            for key in keys(v)
                key in ("type", "expr", "value", "unset") || _toml_refuse(ctx,
                    "unknown key $(repr(key)) in a knob definition; its keys are type, expr, value, unset")
            end
            T = haskey(v, "type") ? _toml_type_from_name(v["type"], ctx) : Float64
            if haskey(v, "expr")
                (haskey(v, "value") || haskey(v, "unset")) && _toml_refuse(ctx, "a knob definition holds `expr`, or `value`, or `unset`; not two of them")
                T <: Real || _toml_refuse(ctx, "an expression-defined knob needs a Real type; got $(T)")
                v["expr"] isa AbstractString || _toml_refuse(ctx, "`expr` takes a string; got $(repr(v["expr"]))")
                node = try
                    _lower_knob(Meta.parse(String(v["expr"])))
                catch err
                    err isa Union{ArgumentError,Base.Meta.ParseError} || rethrow()
                    _toml_refuse(ctx, "the knob expression $(repr(String(v["expr"]))) cannot be read: $(sprint(showerror, err))")
                end
                for d in sort!(collect(_knob_direct_dependencies(node)); by=string)
                    d in paths || _toml_refuse(ctx,
                        "the expression $(repr(String(v["expr"]))) references the knob $(d), which the file does not " *
                        "define; a snapshot's knobs are self-contained (the knobs it defines: " *
                        "$(join(sort!(map(string, collect(paths))), ", ")))")
                end
                isempty(_knob_direct_dependencies(node)) && _toml_refuse(ctx,
                    "the expression $(repr(String(v["expr"]))) reads no knob; write the knob by its value")
                push!(defs, (path=path, type=T, expr=node, value=nothing, unset=false))
            elseif haskey(v, "unset")
                haskey(v, "value") && _toml_refuse(ctx, "a knob definition holds `value` or `unset`, not both")
                v["unset"] === true || _toml_refuse(ctx, "`unset` takes `true`; got $(repr(v["unset"]))")
                push!(defs, (path=path, type=T, expr=nothing, value=nothing, unset=true))
            else
                val = v["value"]
                _toml_is_number(val) || _toml_refuse(ctx, "a knob `value` must be a number; got $(repr(val))")
                push!(defs, (path=path, type=T, expr=nothing, value=val, unset=false))
            end
        else
            _toml_is_number(v) || _toml_refuse(ctx,
                "a knob is written by a number, or by an inline table { expr = ... } / { type = ..., value = ... } / " *
                "{ type = ..., unset = true }; got $(repr(v))")
            push!(defs, (path=path, type=Float64, expr=nothing, value=v, unset=false))
        end
    end
    # Dependency order: independents and unset knobs first, then the dependents
    # as their inputs become available (Kahn); what remains is a cycle.
    order = [d for d in defs if d.expr === nothing]
    pending = [d for d in defs if d.expr !== nothing]
    ready = Set{Symbol}(d.path for d in order)
    while !isempty(pending)
        progressed = false
        rest = similar(pending, 0)
        for d in pending
            if all(dep -> dep in ready, _knob_direct_dependencies(d.expr))
                push!(order, d); push!(ready, d.path); progressed = true
            else
                push!(rest, d)
            end
        end
        progressed || _toml_refuse(_TomlContext(Float64, nothing, ["knobs"]),
            "the knob expressions of $(join(sort!(String[string(d.path) for d in rest]), ", ")) form a dependency cycle")
        pending = rest
    end
    declared = Symbol[]
    existing = Symbol[]
    lock(_KNOB_LOCK) do
        # The conflict check over the whole file before the first install.
        for d in order
            entry = get(_KNOB_TABLE, d.path, nothing)
            entry === nothing && continue
            _toml_knob_same_definition(entry, d) || _toml_refuse(_TomlContext(Float64, nothing, ["knobs", split(string(d.path), '.')...]),
                "the knob $(d.path) already exists in this process with a different definition " *
                "($(_toml_knob_definition_string(entry.type, entry.expression, entry.value))) than the file's " *
                "($(_toml_knob_definition_string(d.type, d.expr, d.value))); a snapshot never rewires a live knob. " *
                "Reset or redefine the knob first, or read the snapshot in a fresh process")
        end
        for d in order
            if haskey(_KNOB_TABLE, d.path)
                push!(existing, d.path)
            elseif d.expr !== nothing
                _install_dependent_locked!(d.path, d.type, d.expr)
                push!(declared, d.path)
            elseif d.unset
                _check_namespace_collision_locked(d.path)
                _KNOB_TABLE[d.path] = _KnobEntry(d.path, d.type, nothing, nothing, Set{Symbol}())
                push!(declared, d.path)
            else
                _install_independent_locked!(d.path, d.type, d.value)
                push!(declared, d.path)
            end
        end
    end
    return (declared=sort!(declared; by=string), existing=sort!(existing; by=string))
end

function _toml_knob_same_definition(entry::_KnobEntry, d)
    entry.type === d.type || return false
    if d.expr !== nothing
        return entry.expression !== nothing && entry.expression == d.expr
    end
    entry.expression === nothing || return false
    d.unset && return entry.value === nothing
    entry.value === nothing && return false
    converted = try
        convert(d.type, d.value)
    catch
        return false
    end
    return isequal(entry.value, converted)
end
_toml_knob_definition_string(T, expr, value) =
    expr !== nothing ? "$(T), expression $(string(expr))" :
    value === nothing ? "$(T), unset" : "$(T), value $(repr(value))"

"""
    _toml_reference_table(ref::ReferenceParticle) -> _TomlTable
    _toml_decode_reference(tbl::AbstractDict, ctx) -> ReferenceParticle

The reference particle as `{ charge, mc2, E0 }` (its three stored fields, as
floats) and back through its keyword constructor; unknown or missing keys
refused by name.
"""
_toml_reference_table(ref::ReferenceParticle) =
    _TomlTable("charge" => Float64(ref.charge), "mc2" => Float64(ref.mc2), "E0" => Float64(ref.E0))
function _toml_decode_reference(tbl::AbstractDict, ctx::_TomlContext)
    for key in keys(tbl)
        key in ("charge", "mc2", "E0") || _toml_refuse(ctx, "unknown key $(repr(key)) in `reference`; its keys are charge, mc2, E0")
    end
    for key in ("charge", "mc2", "E0")
        haskey(tbl, key) || _toml_refuse(ctx, "`reference` needs `$(key)`")
        _toml_is_number(tbl[key]) || _toml_refuse(_toml_at(ctx, key), "`$(key)` must be a number; got $(repr(tbl[key]))")
    end
    return ReferenceParticle(; charge=Float64(tbl["charge"]), mc2=Float64(tbl["mc2"]), E0=Float64(tbl["E0"]))
end

"""
    _toml_lattice_tables(lattice::Lattice, ctx) -> _TomlBlock
    _toml_decode_lattice(name::AbstractString, tbl::AbstractDict, ctx) -> Lattice

The lattice rules of the format. Writing: `eltype`, `knob_roots`, `reference`
(absent when the lattice has none), `line` (the top-level line's id), then the
`elements`, `hooks`, `markers` and `lines` blocks, one table per distinct
object in first-placement order (`_toml_ids`), elements by the element rules,
hooks and markers by `_toml_encode_object`, lines by the line rules. Reading:
the keys checked (unknown refused by name), `eltype` through the type
allowlist and carried as the numeric type every value re-narrows by, the
objects of the three object blocks rebuilt into one id table (a duplicate id
refused by name), the lines rebuilt in reference order (a line referencing a
line decoded on demand, a cycle refused), the top-level line looked up by
`line`, and the `Lattice` constructed, which re-runs the knob-root and
numeric-type tripwires over what was read.
"""
function _toml_lattice_tables(lattice::Lattice, ctx::_TomlContext)
    ids = _toml_ids(lattice)
    objects = _toml_placed_objects(getfield(lattice, :line))
    pairs = Pair{String,Any}["eltype" => _toml_type_name(getfield(lattice, :eltype), _toml_at(ctx, "eltype"))]
    push!(pairs, "knob_roots" => Any[String(r) for r in getfield(lattice, :knob_roots)])
    ref = getfield(lattice, :reference)
    ref === nothing || push!(pairs, "reference" => _toml_reference_table(ref))
    push!(pairs, "line" => ids[getfield(lattice, :line)])
    groups = Dict{String,_TomlBlock}(g => _TomlBlock() for g in ("elements", "hooks", "markers", "lines"))
    for obj in objects
        group = _toml_object_group(obj)
        id = ids[obj]
        octx = _toml_at(_toml_at(ctx, group), id)
        table = if group == "lines"
            _toml_line_table(obj, ids, octx)
        elseif group == "elements"
            _toml_element_table(obj, octx)
        else
            _toml_object_pairs(_toml_encode_object(obj, octx), octx)
        end
        push!(groups[group].pairs, id => _TomlBlock(table.pairs))
    end
    for g in ("elements", "hooks", "markers", "lines")
        push!(pairs, g => groups[g])
    end
    return _TomlBlock(pairs)
end

# An object's encoded dictionary as an ordered inline table: `type` first, the
# other keys sorted (the emitter's rule for every `Dict` it is handed).
function _toml_object_pairs(d::AbstractDict, ctx::_TomlContext)
    haskey(d, "type") || _toml_refuse(ctx, "an encoded object must carry `type`; the encoder of $(join(collect(String, keys(d)), ", ")) did not")
    pairs = Pair{String,Any}["type" => d["type"]]
    for k in sort!(collect(String, keys(d)))
        k == "type" && continue
        push!(pairs, k => d[k])
    end
    return _TomlTable(pairs)
end
_toml_object_pairs(t::_TomlTable, ctx::_TomlContext) = t

const _TOML_LATTICE_KEYS = ("eltype", "knob_roots", "reference", "line", "elements", "hooks", "markers", "lines")

function _toml_decode_lattice(name::AbstractString, tbl::AbstractDict, ctx::_TomlContext)
    for key in sort!(collect(String, keys(tbl)))
        key in _TOML_LATTICE_KEYS || _toml_refuse(ctx, "unknown key $(repr(key)) in a lattice table; its keys are $(join(_TOML_LATTICE_KEYS, ", "))")
    end
    haskey(tbl, "eltype") || _toml_refuse(ctx, "a lattice table needs `eltype`")
    haskey(tbl, "line") || _toml_refuse(ctx, "a lattice table needs `line`, the id of its top-level line")
    T = _toml_type_from_name(tbl["eltype"], _toml_at(ctx, "eltype"))
    lctx = _TomlContext(T, ctx.tables, ctx.where)
    roots = get(tbl, "knob_roots", Any[])
    (roots isa AbstractVector && all(r -> r isa AbstractString, roots)) || _toml_refuse(_toml_at(ctx, "knob_roots"),
        "`knob_roots` must be an array of strings; got $(repr(roots))")
    reference = haskey(tbl, "reference") ? begin
        r = tbl["reference"]
        r isa AbstractDict || _toml_refuse(_toml_at(ctx, "reference"), "`reference` must be an inline table { charge, mc2, E0 }; got $(repr(r))")
        _toml_decode_reference(r, _toml_at(ctx, "reference"))
    end : nothing
    objects = Dict{String,Any}()
    for group in ("elements", "hooks", "markers")
        block = get(tbl, group, Dict{String,Any}())
        block isa AbstractDict || _toml_refuse(_toml_at(ctx, group), "`$(group)` must be a table of tables; got $(repr(block))")
        for id in sort!(collect(String, keys(block)))
            octx = _toml_at(_toml_at(lctx, group), id)
            haskey(objects, id) && _toml_refuse(octx, "the id $(repr(id)) is used twice among the lattice's elements, hooks, markers and lines")
            t = block[id]
            t isa AbstractDict || _toml_refuse(octx, "an object table must be a table; got $(repr(t))")
            objects[id] = group == "elements" ? _toml_decode_element(t, octx) : _toml_decode_object(t, octx)
        end
    end
    lines = get(tbl, "lines", Dict{String,Any}())
    lines isa AbstractDict || _toml_refuse(_toml_at(ctx, "lines"), "`lines` must be a table of tables; got $(repr(lines))")
    for id in keys(lines)
        haskey(objects, id) && _toml_refuse(_toml_at(_toml_at(ctx, "lines"), id),
            "the id $(repr(id)) is used twice among the lattice's elements, hooks, markers and lines")
    end
    decoding = Set{String}()
    for id in sort!(collect(String, keys(lines)))
        _toml_decode_line_by_id!(objects, lines, id, decoding, _toml_at(lctx, "lines"))
    end
    top = tbl["line"]
    top isa AbstractString || _toml_refuse(_toml_at(ctx, "line"), "`line` must be a string id; got $(repr(top))")
    (haskey(lines, top) && objects[top] isa ElementSpec{:line}) || _toml_refuse(_toml_at(ctx, "line"),
        "the top-level line $(repr(String(top))) is not one of the lattice's lines " *
        "($(isempty(lines) ? "none" : join(sort!(collect(String, keys(lines))), ", ")))")
    return Lattice(String(name); line=objects[top], reference=reference,
                   knob_root=isempty(roots) ? nothing : Tuple(Symbol(r) for r in roots), eltype=T)
end

function _toml_decode_line_by_id!(objects, lines, id, decoding, ctx::_TomlContext)
    haskey(objects, id) && return objects[id]
    id in decoding && _toml_refuse(_toml_at(ctx, id), "the line $(repr(id)) contains itself (a reference cycle through the lines)")
    push!(decoding, id)
    t = lines[id]
    t isa AbstractDict || _toml_refuse(_toml_at(ctx, id), "a line table must be a table; got $(repr(t))")
    members = get(t, "members", Any[])
    if members isa AbstractVector
        for m in members
            m isa AbstractDict && haskey(m, "ref") && m["ref"] isa AbstractString && haskey(lines, m["ref"]) &&
                _toml_decode_line_by_id!(objects, lines, m["ref"], decoding, ctx)
        end
    end
    objects[id] = _toml_decode_line(t, id, objects, _toml_at(ctx, id))
    delete!(decoding, id)
    return objects[id]
end

"""
    _toml_emit(io::IO, doc::_TomlBlock) -> nothing

The deterministic emitter: the document's top-level scalars first (`format`),
then each block as a headed table in the order the document gives, a block's
scalar pairs under its header in their given order, its sub-blocks after it; a
block with no scalar pairs of its own prints no header (TOML defines a parent
table implicitly, and an empty group such as a lattice without hooks is
absent, which the reader takes as empty). Inline tables print on one line, `{ k = v, ... }`;
an array of inline tables prints one per line (the `members` form), any other
array on one line. Keys print bare when TOML allows (`[A-Za-z0-9_-]+`) and
quoted otherwise (`"QF#2"`); strings are basic strings with the TOML escapes.
Floats print as Julia prints a `Float64` (`1.0`, `1.0e-5`, `nan`, `inf`),
integers as decimal integers.
"""
function _toml_emit(io::IO, doc::_TomlBlock)
    _toml_emit_block(io, String[], doc, Ref(true))
    return nothing
end
function _toml_emit_block(io::IO, path::Vector{String}, blk::_TomlBlock, first::Ref{Bool})
    scalars = [p for p in blk.pairs if !(p.second isa _TomlBlock)]
    blocks = [p for p in blk.pairs if p.second isa _TomlBlock]
    if !isempty(path) && !isempty(scalars)
        first[] || println(io)
        first[] = false
        print(io, "[", join(map(_toml_key, path), "."), "]\n")
    elseif isempty(path) && !isempty(scalars)
        first[] = false
    end
    for (k, v) in scalars
        print(io, _toml_key(k), " = ")
        _toml_emit_value(io, v)
        print(io, "\n")
    end
    for (k, v) in blocks
        _toml_emit_block(io, vcat(path, k), v, first)
    end
    return nothing
end
_toml_key(k::AbstractString) = occursin(r"^[A-Za-z0-9_-]+$", k) ? String(k) : _toml_string(k)
function _toml_string(s::AbstractString)
    io = IOBuffer()
    print(io, '"')
    for c in s
        if c == '"'
            print(io, "\\\"")
        elseif c == '\\'
            print(io, "\\\\")
        elseif c == '\b'
            print(io, "\\b")
        elseif c == '\t'
            print(io, "\\t")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\f'
            print(io, "\\f")
        elseif c == '\r'
            print(io, "\\r")
        elseif c < ' ' || c == '\x7f'
            print(io, "\\u", string(UInt32(c); base=16, pad=4))
        else
            print(io, c)
        end
    end
    print(io, '"')
    return String(take!(io))
end
function _toml_emit_value(io::IO, v)
    if v isa Bool
        print(io, v ? "true" : "false")
    elseif v isa Integer
        print(io, Int64(v))
    elseif v isa AbstractFloat
        x = Float64(v)
        isnan(x) ? print(io, "nan") : isinf(x) ? print(io, x > 0 ? "inf" : "-inf") : print(io, x)
    elseif v isa AbstractString
        print(io, _toml_string(v))
    elseif v isa _TomlTable
        if isempty(v.pairs)
            print(io, "{}")
        else
            print(io, "{ ")
            for (i, (k, x)) in enumerate(v.pairs)
                i == 1 || print(io, ", ")
                print(io, _toml_key(k), " = ")
                _toml_emit_value(io, x)
            end
            print(io, " }")
        end
    elseif v isa AbstractDict
        _toml_emit_value(io, _toml_object_pairs(v, _TomlContext(; tables=nothing)))
    elseif v isa AbstractVector
        if !isempty(v) && all(x -> x isa Union{_TomlTable,AbstractDict}, v)
            print(io, "[\n")
            for x in v
                print(io, "  ")
                _toml_emit_value(io, x)
                print(io, ",\n")
            end
            print(io, "]")
        else
            print(io, "[")
            for (i, x) in enumerate(v)
                i == 1 || print(io, ", ")
                _toml_emit_value(io, x)
            end
            print(io, "]")
        end
    else
        throw(ArgumentError("machine snapshot: the emitter was handed a value of type $(typeof(v)) " *
                            "($(repr(v))); every value must go through _toml_encode_value first"))
    end
    return nothing
end

"""
    _toml_document(machine::Machine, tables) -> _TomlBlock

The snapshot document of a machine: `format = 1`, the `[machine]` table
(`name`, `knob_roots`, `lattices` in declaration order), the knobs of every
root of the machine (`_toml_knobs_table`), and one lattice block per lattice
(`_toml_lattice_tables`), every value going through the value rules with the
tables dictionary for bulk data.
"""
function _toml_document(machine::Machine, tables)
    roots = Symbol[]
    append!(roots, getfield(machine, :knob_roots))
    for l in getfield(machine, :lattices)
        append!(roots, getfield(l, :knob_roots))
    end
    lattices = _TomlBlock()
    for l in getfield(machine, :lattices)
        name = getfield(l, :name)
        ctx = _TomlContext(getfield(l, :eltype), tables, ["lattices", name])
        push!(lattices.pairs, name => _toml_lattice_tables(l, ctx))
    end
    machine_tbl = _TomlBlock("name" => getfield(machine, :name),
                             "knob_roots" => Any[String(r) for r in getfield(machine, :knob_roots)],
                             "lattices" => Any[getfield(l, :name) for l in getfield(machine, :lattices)])
    return _TomlBlock("format" => 1, "machine" => machine_tbl, "knobs" => _toml_knobs_table(roots),
                      "lattices" => lattices)
end

"""
    _toml_tables_path(path) -> String
    _toml_write_tables(path, tables) -> nothing
    _toml_read_tables(path, digests) -> Dict{String,Vector{Float64}}
    _toml_referenced_digests(doc) -> Vector{String}

The sidecar: `<path without extension>.tables.h5`, one dataset per table under
its digest, written through HDF5 only when the machine holds a table and read
only when the text references one (`_toml_referenced_digests` walks the parsed
document for `{ type = ..., sha256 = "..." }` tables); a referenced table whose
sidecar is missing is refused by name.
"""
_toml_tables_path(path::AbstractString) = first(splitext(String(path))) * ".tables.h5"
function _toml_write_tables(path::AbstractString, tables::AbstractDict)
    h5open(String(path), "w") do f
        for digest in sort!(collect(String, keys(tables)))
            f[digest] = Vector{Float64}(tables[digest])
        end
    end
    return nothing
end
function _toml_read_tables(path::AbstractString, digests::AbstractVector)
    isfile(path) || throw(ArgumentError(
        "machine snapshot: the text references $(length(digests)) bulk table(s) (sha256 " *
        "$(join(digests, ", "))) but the sidecar $(repr(String(path))) does not exist beside it; " *
        "copy the sidecar with the snapshot, or re-write the machine"))
    tables = Dict{String,Vector{Float64}}()
    h5open(String(path), "r") do f
        for digest in digests
            haskey(f, digest) || continue
            tables[String(digest)] = Vector{Float64}(read(f[digest]))
        end
    end
    return tables
end
function _toml_referenced_digests(doc)
    out = String[]
    _toml_collect_digests!(out, doc)
    return sort!(unique!(out))
end
function _toml_collect_digests!(out, x)
    if x isa AbstractDict
        haskey(x, "type") && haskey(x, "sha256") && x["sha256"] isa AbstractString && push!(out, String(x["sha256"]))
        foreach(v -> _toml_collect_digests!(out, v), values(x))
    elseif x isa AbstractVector
        foreach(v -> _toml_collect_digests!(out, v), x)
    end
    return out
end

"""
    _toml_parse_document(text) -> Dict{String,Any}

`TOML.parse` with the codec's refusal: text that is not TOML is refused naming
the parser's position and message.
"""
function _toml_parse_document(text::AbstractString)
    try
        return TOML.parse(String(text))
    catch err
        err isa TOML.ParserError || rethrow()
        throw(ArgumentError("machine snapshot: the text is not valid TOML: $(sprint(showerror, err))"))
    end
end
