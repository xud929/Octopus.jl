export write_machine, read_machine, machine_toml, parse_machine

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

[lattices.ESR.hooks.MOMENTS]              # in-line hooks: observers and actions with their schedules
type = "ScheduledObserver"
observer = { type = "MomentObserver", name = "electron", moments = ["x", "px", ...] }
schedule = { type = "EveryNSteps", start = 1, step = 10 }

[lattices.ESR.markers.IP]                 # collision markers with the solver on them
type = "StrongStrongCollision"
label = "ip"
poisson_solver = { type = "PICPoissonSolver", grid = [128, 128], slicing = { type = "LongitudinalSlicing", nslices = 15, ... }, ... }

[lattices.ESR.lines.ESR]                  # the top-level line and every nested line kept whole
members = [
  { ref = "QF", path = "ESR/QUADRUPOLE[1]" },
  { ref = "D", path = "ESR/DRIFT[1]", tags = ["cryostat"], overrides = { L = 0.7 } },
  { ref = "IP", path = "ESR/STRONGSTRONGCOLLISION[1]" },
  { ref = "MOMENTS", path = "ESR/SCHEDULEDOBSERVER[1]" },
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
  when it is not a bare TOML key; distinct spec objects are distinct tables
  and one object placed twice is one table referenced twice, so the identity
  the family queries rely on (`e.spec === qf`) survives the round trip.
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
  when it is a vector, and as `{ tuple = [...] }` when the metadata gives no
  hint; mixed `(number, expr)` tuples follow the same rule. `nothing` is the
  inline table `{ nothing = true }` (TOML has no null, and a stored `nothing`
  is not an absent key). A `Type` prints as its name (`numeric_type =
  "Float64"`) and is read through the allowlist of numeric types. A
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
  the type's keyword constructor; a type with no schema is refused by name.
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
  offsets) print beside `members`.
- **Knobs.** Every knob under every root of the machine (the lattices' roots
  and the shared ones), by dotted path as nested tables, sorted; independent
  knobs by value, dependent ones by expression, a declared type other than
  `Float64` explicit, an unset knob marked. The reader declares the file's
  independent knobs first and the dependent ones in the dependency order it
  derives from the expressions; a reference to a knob the file does not
  define is refused by name; a path that already exists in the process with
  the SAME definition (type, and value or expression) is accepted as it is,
  one that exists with a different definition is refused by name rather than
  rewired. Parsing an expression executes nothing: `Meta.parse` yields an
  AST and the knob builder accepts only its whitelisted calls, references and
  literals.
- **The emitter is deterministic**: tables in the order above, keys sorted
  within a table where the format does not fix them, elements in
  first-placement order, inline tables on one line, so two snapshots of one
  machine are byte-identical and two machines differ where their snapshots
  differ. The sidecar `<path without extension>.tables.h5` is written only
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
    error("write_machine: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
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
    error("machine_toml: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
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
    error("read_machine: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
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
    error("parse_machine: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
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
    error("_toml_store_table!: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
end
function _toml_table(ctx::_TomlContext, digest::AbstractString)
    error("_toml_table: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
end

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
    error("_toml_encode_value: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
end
function _toml_decode_value(x, hint, ctx::_TomlContext)
    error("_toml_decode_value: not implemented yet (stage 4 skeleton)")   # STUB (unit A)
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
    error("_toml_encode_object: not implemented yet (stage 4 skeleton)")   # STUB (unit A: dispatch + fallback refusal; unit B: the methods)
end

"""
    _toml_decode_object(tbl::AbstractDict, ctx)

Rebuild an object from a `type = "<name>"` table through `_TOML_OBJECT_TYPES`
and the type's keyword constructor or fields; unknown names and unknown keys
refused by name.
"""
function _toml_decode_object(tbl::AbstractDict, ctx::_TomlContext)
    error("_toml_decode_object: not implemented yet (stage 4 skeleton)")   # STUB (unit A: dispatch; unit B: the methods)
end

# STUBS (unit A), the core codec, each documented when filled:
#   _toml_encode_value(v, hint::Union{Nothing,ParamMeta}, ctx) / _toml_decode_value(x, hint, ctx)   the value rules
#   _toml_element_table(spec::ElementSpec, ctx) / _toml_decode_element(tbl, ctx)
#   _toml_line_table(line::ElementSpec{:line}, ids, ctx) / _toml_decode_line(tbl, objects, ctx)   members with ref/path/tags/overrides
#   _toml_lattice_tables(lattice, ctx) / _toml_decode_lattice(name, tbl, ctx)
#   _toml_knobs_table(roots) / _toml_declare_knobs!(tbl) -> (declared, existing)
#   _toml_reference_table(ref) / _toml_decode_reference(tbl)
#   _toml_tables_path(path) ; _toml_write_tables(path, tables) ; _toml_read_tables(path, digests)
#   _toml_ids(lattice) -> IdDict object => id   (first-placement order, names made unique)
#   the TOML.print conversion function and the inline-table set (deterministic emitter)
