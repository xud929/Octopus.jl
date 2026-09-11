export one_turn_matrix, LinearizedMap, LinearizationProvenance,
       AbstractLinearizationMethod, ComplexStepLinearization,
       FiniteDifferenceLinearization, ForwardDiffLinearization

# The boundary between tracking and optics: a one-turn (or one-section)
# transfer matrix is the Jacobian of a compiled map at an expansion point.
# Three ways of taking it live here as TAG types dispatched through one
# internal function, `_linearize`, so that the ForwardDiff route can be ADDED
# by the package extension on a type core owns. The rule is the one
# ext/OctopusMPIExt.jl states: an extension adds methods, it never redefines
# one core already has. Core never imports ForwardDiff.
#
# Design: docs/design/twiss_dispersion_analysis.md, "Input boundary", items
# 2 and 3. Stage 1 of its Staging section lands this file; the analysis that
# consumes a `LinearizedMap` is a later stage and does not exist yet.
#
# This file replaces the complex-step closures the suite carried (the
# "Lattice magnets" and "Lattice cells track and stay symplectic" testsets);
# validation/lattice_cells.jl keeps its own copy until stage 7. The
# complex-step arithmetic below is operation for operation the closures',
# so the two Jacobians are bit-identical, and a suite test keeps one inline
# closure as an independent witness of that.

"""
    AbstractLinearizationMethod

Root of the linearization-method tags accepted by the `method` keyword of
[`one_turn_matrix`](@ref): [`ComplexStepLinearization`](@ref) (the default),
[`FiniteDifferenceLinearization`](@ref), and [`ForwardDiffLinearization`](@ref).
A tag says HOW the Jacobian is taken; the map and the expansion point say
what is differentiated. Each tag has a method of the internal `_linearize`;
a tag without one fails loudly rather than falling back to another method.
"""
abstract type AbstractLinearizationMethod end

"""
    ComplexStepLinearization()

Complex-step differentiation: every coordinate `j` in turn is perturbed by
`1e-30im`, the map is evaluated once in `ComplexF64`, and column `j` of the
Jacobian is `imag(map(u)) / 1e-30`. Exact to roundoff for any map written in
arithmetic that extends to complex numbers (no truncation error, no step to
choose), so its provenance declares a map uncertainty of zero. Maps that
compare a coordinate against a threshold (the strong-beam evaluators) cannot
be complex-stepped and raise a directed error naming the two alternatives.
"""
struct ComplexStepLinearization <: AbstractLinearizationMethod end

"""
    FiniteDifferenceLinearization(step=SymplecticityContract().step)

Central finite difference: column `j` is `(map(q + h e_j) - map(q - h e_j)) / 2h`
with `h = step * max(|q_j|, 1)`. Truncation error of order `step^2`; the
provenance declares a map uncertainty of `step^2 * ||J||_F`, the
truncation-order SCALE the design assigns (design note, "Input boundary" item
3), not a bound on the matrix error: a central difference also carries
roundoff of order `eps / (2h) * ||J||`, which dominates at the default step
(measured 2026-09-11 on the FODO cell: the matrix error is 2.1e3 times the
declared value at step 3e-7 and 0.84 times it at 1e-5). That is why an
analysis fed a finite-difference matrix must be told an explicit symplectic
tolerance (design note, "Types and availability"); whether the declared
formula gains a roundoff arm is a design-note decision left to the
measurement stage. The default `step` is the `SymplecticityContract` default,
read from that contract rather than copied, so the two cannot drift apart.
`step` must be positive and finite.
"""
struct FiniteDifferenceLinearization <: AbstractLinearizationMethod
    step::Float64
    function FiniteDifferenceLinearization(step::Real=_DEFAULT_FD_STEP)
        (isfinite(step) && step > 0) || throw(ArgumentError(
            "the finite-difference step must be positive and finite, got $(step)"))
        return new(Float64(step))
    end
end

"""
    ForwardDiffLinearization()

Dual-number Jacobian through ForwardDiff. Core defines only this tag; the
method that implements it is added by the OctopusForwardDiffExt extension
(package mode: `using ForwardDiff` beside `using Octopus`) or by the
script-mode include of the shared rules file at the bottom of
`src/Octopus.jl` (ForwardDiff importable from the active project when
`src/Octopus.jl` is `include`d). With neither route active the tag throws a
directed error naming both; nothing falls back to another method silently.
"""
struct ForwardDiffLinearization <: AbstractLinearizationMethod end

# The complex-step perturbation of the suite closures and of
# validation/lattice_cells.jl. A single constant so the perturb and the
# read-out cannot disagree.
const _COMPLEX_STEP = 1.0e-30

# Derived from the contract, not copied from it: the symplecticity contract's
# step scan measured where central differences sit on the linear and the
# beam-beam maps (its docstring), and this helper inherits that choice.
const _DEFAULT_FD_STEP = SymplecticityContract().step

"""
    LinearizationProvenance

What [`one_turn_matrix`](@ref) differentiated and how. Fields:

- `source_kind`: `:callable` (a compiled runtime map or any user callable),
  `:runtime_tuple` (compiled runtime maps folded in order), or
  `:element_spec` (a spec, including a `BeamLine`, compiled through
  `compile_runtime` first).
- `source`: a short description of the map (its runtime type, or the spec
  type and name).
- `method`: the [`AbstractLinearizationMethod`](@ref) tag that was used.
- `step`: the finite-difference `step`; `0.0` for the exact methods.
- `point`: the expansion point in raw tracked coordinates `(x, px, y, py, z, pz)`.
- `map_uncertainty`: the declared map uncertainty, `0.0` for the exact
  methods and `step^2 * ||J||_F` for finite differences: the truncation-order
  scale of the design, which at the default step sits below the roundoff
  part of the actual matrix error (see [`FiniteDifferenceLinearization`](@ref)).
  The analysis folds it into its perturbation scale as one arm among several;
  it is not on its own an error bound.
- `fixed_point_residual`: `map(point) - point`, the six components in raw
  tracked coordinates. A periodic analysis needs a fixed point; it scales this
  vector and judges it against its own tolerance. This helper only records
  it and never finds a closed orbit. `maximum(abs, ...)` of it is the raw
  infinity norm.
"""
struct LinearizationProvenance
    source_kind::Symbol
    source::String
    method::AbstractLinearizationMethod
    step::Float64
    point::NTuple{6,Float64}
    map_uncertainty::Float64
    fixed_point_residual::NTuple{6,Float64}
end

"""
    LinearizedMap

The output of [`one_turn_matrix`](@ref): the `6x6` Jacobian in `matrix` and
its [`LinearizationProvenance`](@ref) in `provenance`. Iterates as the pair
`(matrix, provenance)`, so `M, prov = one_turn_matrix(cell)` destructures it;
`Matrix(lm)` copies the matrix. A later stage's `analyze` accepts it as an
input form. Runtime representation: the fields may change; the accessors and
the destructuring are the surface.
"""
struct LinearizedMap
    matrix::Matrix{Float64}
    provenance::LinearizationProvenance
end

Base.Matrix(lm::LinearizedMap) = copy(lm.matrix)
Base.iterate(lm::LinearizedMap) = (lm.matrix, 2)
Base.iterate(lm::LinearizedMap, state::Int) = state == 2 ? (lm.provenance, 3) : nothing
Base.length(::LinearizedMap) = 2

_describe_map(map) = string(nameof(typeof(map)))
_describe_map(maps::Tuple) = "tuple of $(length(maps)) runtime maps (" *
    join((string(nameof(typeof(m))) for m in maps), ", ") * ")"
function _describe_map(spec::AbstractElementSpec)
    name = getparam(spec, :name, nothing)
    return string(typeof(spec)) * (name === nothing || name == "" ? "" : " \"$(name)\"")
end

_source_kind(::Any) = :callable
_source_kind(::Tuple) = :runtime_tuple
_source_kind(::AbstractElementSpec) = :element_spec

# Anything compile_runtime accepts is linearized through its compiled map; a
# tuple of compiled maps is folded in order exactly as the suite and the
# validation scripts do (`foldl((c, e) -> e(c...), cell; init=u)`), which is
# what keeps the complex-step Jacobian bit-identical to their closures.
_linearizable(map) = map
_linearizable(spec::AbstractElementSpec) = compile_runtime(spec)
function _linearizable(maps::Tuple)
    isempty(maps) && throw(ArgumentError(
        "an empty tuple has no map to linearize; pass compiled runtime elements"))
    for (i, m) in enumerate(maps)
        m isa AbstractElementSpec && throw(ArgumentError(
            "entry $(i) of the tuple is an element spec ($(typeof(m))), not a compiled " *
            "runtime map. Compile each entry with compile_runtime, or pass one BeamLine spec."))
    end
    return (coords...) -> foldl((c, e) -> e(c...), maps; init=coords)
end

function _linearization_point(point)
    length(point) == 6 || throw(ArgumentError(
        "the expansion point must have six coordinates (x, px, y, py, z, pz), got $(length(point))"))
    all(x -> x isa Real && isfinite(x), point) || throw(ArgumentError(
        "the expansion point must be six finite real numbers, got $(point)"))
    return ntuple(i -> Float64(point[i]), 6)
end

# One check for every route: a map that does not return six coordinates is a
# usage error, never something to pad or truncate.
function _six_coordinates(out, what::AbstractString)
    length(out) == 6 || throw(ArgumentError(
        "the map must return six coordinates (x, px, y, py, z, pz), got $(length(out)) $(what)"))
    return out
end

"""
    _linearize(method, f, point) -> Matrix{Float64}

Jacobian of the callable `f(x, px, y, py, z, pz) -> 6-tuple` at `point` by
`method`. The generic fallback throws: a tag with no active implementation
must fail loudly and name how to activate one, never fall back to another
method silently. For [`ForwardDiffLinearization`](@ref) that names both
activation routes; the extension (or the script-mode rules include) ADDS the
method on that tag and this fallback is never reached while either is active.
"""
function _linearize(method::AbstractLinearizationMethod, f, point::NTuple{6,Float64})
    hint = method isa ForwardDiffLinearization ?
        "ForwardDiff is not active. Activate it by one of two routes: in package mode, " *
        "`using ForwardDiff` beside `using Octopus` loads the OctopusForwardDiffExt " *
        "extension; in script mode (include(\"src/Octopus.jl\")), ForwardDiff must be " *
        "importable from the active project when the file is included. " :
        "no `_linearize` method is defined for it. "
    throw(ArgumentError(
        "linearization method $(nameof(typeof(method))) has no active implementation: " * hint *
        "Alternatives: method=ComplexStepLinearization() (exact) or " *
        "method=FiniteDifferenceLinearization(step) (truncation of order step^2)."))
end

function _linearize(::ComplexStepLinearization, f, point::NTuple{6,Float64})
    J = zeros(6, 6)
    for j in 1:6
        u = ComplexF64[point...]
        u[j] += _COMPLEX_STEP * im
        J[:, j] = imag.(collect(_six_coordinates(f(u...), "under a complex step"))) ./ _COMPLEX_STEP
    end
    return J
end

function _linearize(method::FiniteDifferenceLinearization, f, point::NTuple{6,Float64})
    step = method.step
    q = collect(Float64, point)
    J = zeros(6, 6)
    for j in 1:6
        h = step * max(abs(q[j]), 1.0)
        dq = zeros(Float64, 6)
        dq[j] = h
        plus = collect(Float64, _six_coordinates(f((q .+ dq)...), "at the forward step"))
        minus = collect(Float64, _six_coordinates(f((q .- dq)...), "at the backward step"))
        J[:, j] = (plus .- minus) ./ (2h)
    end
    return J
end

# The provenance of each method: the recorded step and the declared map
# uncertainty. Exact methods declare zero; finite differences declare the
# design's truncation-order scale step^2 * ||J||_F (see the tag's docstring
# for what that scale does and does not cover).
_method_step(::AbstractLinearizationMethod) = 0.0
_method_step(method::FiniteDifferenceLinearization) = method.step
_map_uncertainty(::AbstractLinearizationMethod, J::AbstractMatrix) = 0.0
_map_uncertainty(method::FiniteDifferenceLinearization, J::AbstractMatrix) = method.step^2 * norm(J)

# The relabelling guard of the design note: a failure inside the map is
# attributed to the differentiation method ONLY when the error's argument
# types involve the method's perturbation number type. Anything else is the
# map's own defect and is rethrown unchanged. `_is_method_number` is the LEAF
# predicate on one value or one type: core knows the complex-step type; the
# ForwardDiff extension adds the leaf for its tag and its dual type. Finite
# differences run in real arithmetic and relabel nothing.
# `_involves_method_number` walks what an error argument can be: a value, a
# container of values (a Vector or Tuple of coordinates handed to a
# Float64-typed helper raises a MethodError on Vector{ComplexF64}), or a type
# whose parameters carry the perturbation type (Vector{ComplexF64},
# Tuple{ComplexF64,ComplexF64}); "involve" in the design means any of these.
_is_method_number(::ComplexStepLinearization, x) = x isa Complex || (x isa Type && x <: Complex)
_is_method_number(::AbstractLinearizationMethod, x) = false

function _involves_method_number(method::AbstractLinearizationMethod, x)
    _is_method_number(method, x) && return true
    if x isa Type
        T = Base.unwrap_unionall(x)
        if T isa Union
            return _involves_method_number(method, T.a) || _involves_method_number(method, T.b)
        end
        T isa DataType || return false
        return any(p -> p isa Type && _involves_method_number(method, p), T.parameters)
    elseif x isa AbstractArray
        return _involves_method_number(method, eltype(x)) ||
               any(v -> _involves_method_number(method, v), x)
    elseif x isa Tuple
        return any(v -> _involves_method_number(method, v), x)
    end
    return false
end

# Which error classes carry argument types, and where. On Julia 1.12 (the
# only series Project.toml admits) `InexactError` has fields (:func, :args)
# with args = (target type, value), `DomainError` has (:val, :msg) and
# `TypeError` has (..., :got); the suite pins the InexactError field so a
# Julia change here is loud rather than a FieldError inside the guard.
function _differentiation_limit(method::AbstractLinearizationMethod, err)
    if err isa MethodError || err isa InexactError
        return any(a -> _involves_method_number(method, a), err.args)
    elseif err isa DomainError
        return _involves_method_number(method, err.val)
    elseif err isa TypeError
        return _involves_method_number(method, err.got)
    end
    return false
end

# The alternatives a directed error names: every concrete tag except the one
# that failed, DERIVED from the type tree (AGENTS.md: never hand-copy a case
# list). `_concrete_octopus_subtypes` lives in src/tasks/strongstrong/
# interface.jl, included after this file; the call is made only inside an
# error path at run time, so the late binding is harmless.
function _alternative_method_names(method::AbstractLinearizationMethod)
    names = Symbol[nameof(T) for T in _concrete_octopus_subtypes(AbstractLinearizationMethod)]
    return filter(!=(nameof(typeof(method))), names)
end

"""
    _forward_diff_linearization_available() -> Bool

Whether a `_linearize` method for [`ForwardDiffLinearization`](@ref) is
loaded, i.e. whether the extension (package mode) or the script-mode rules
include supplied it. Read from the method table, so it reports the thing
itself and not a flag that might have been set without the method.
"""
function _forward_diff_linearization_available()
    for m in methods(_linearize)
        sig = Base.unwrap_unionall(m.sig)
        sig isa DataType && length(sig.parameters) >= 2 || continue
        sig.parameters[2] === ForwardDiffLinearization && return true
    end
    return false
end

"""
    one_turn_matrix(map; method=ComplexStepLinearization(), point=zeros(6)) -> LinearizedMap

The `6x6` Jacobian of a tracked map at the expansion `point`, with
[`LinearizationProvenance`](@ref). `map` is one of

- any callable `(x, px, y, py, z, pz) -> 6-tuple`, which every compiled
  runtime element and every compiled `:line` is;
- a `Tuple` of compiled runtime maps, applied in order (the cell convention
  of the suite and of `validation/lattice_cells.jl`);
- an element spec, including a `BeamLine`, compiled through `compile_runtime`.

`method` is a tag: [`ComplexStepLinearization`](@ref) (default, exact to
roundoff), [`FiniteDifferenceLinearization`](@ref) (central, truncation of
order `step^2`, declared in the provenance), or
[`ForwardDiffLinearization`](@ref) (needs ForwardDiff active, see its
docstring). `point` is any six finite reals; the default is the origin.

The map is evaluated at `point` in real arithmetic first. If that throws, the
error is the map's own and propagates unchanged; a non-finite result there
(an aperture that kills the particle, a lost coordinate) is an
`ArgumentError`. Only when the real evaluation succeeds and the
differentiating evaluation fails with an error whose argument types involve
the method's perturbation numbers (a complex step through a threshold
comparison, as in the strong-beam evaluators) is the failure attributed to
the method: then an `ArgumentError` names the alternative methods and carries
the original error as its cause. Any other error is rethrown unchanged, so a
bug in a user map is never relabelled as a differentiation limit. Nothing
falls back silently. `map(point) - point` is recorded in the provenance for
the periodic analysis to judge; this function does not find a closed orbit.
"""
function one_turn_matrix(map; method::AbstractLinearizationMethod=ComplexStepLinearization(),
                         point=ntuple(_ -> 0.0, 6))
    p = _linearization_point(point)
    f = _linearizable(map)
    # The map's own evaluation at the point. Anything thrown here is the
    # map's defect and is not caught: the differentiation has not started.
    real_out = collect(Float64, _six_coordinates(f(p...), "at the expansion point"))
    all(isfinite, real_out) || throw(ArgumentError(
        "the map $(_describe_map(map)) does not return finite coordinates at the expansion " *
        "point $(p): got $(Tuple(real_out)). An aperture that kills the particle there, or a " *
        "lost coordinate, has no Jacobian; move the expansion point or drop the element."))
    residual = ntuple(i -> real_out[i] - p[i], 6)
    J = try
        _linearize(method, f, p)
    catch err
        if _differentiation_limit(method, err)
            alternatives = join(("method=$(n)()" for n in _alternative_method_names(method)), " or ")
            throw(ArgumentError(
                "the map $(_describe_map(map)) evaluates at the expansion point in real " *
                "arithmetic but not under $(nameof(typeof(method))) " *
                "($(nameof(typeof(err))) involving its perturbation numbers): the method cannot " *
                "differentiate it. Use $(alternatives) " *
                "(a finite difference declares a truncation uncertainty of order step^2; " *
                "ForwardDiff needs the extension active). Original error: $(sprint(showerror, err))"))
        end
        rethrow()
    end
    size(J) == (6, 6) || throw(ArgumentError(
        "the linearization returned a $(size(J)) matrix; the map must return six coordinates"))
    all(isfinite, J) || throw(ArgumentError(
        "the linearized map $(_describe_map(map)) has non-finite entries at $(p)"))
    prov = LinearizationProvenance(_source_kind(map), _describe_map(map), method,
                                   _method_step(method), p, _map_uncertainty(method, J),
                                   residual)
    return LinearizedMap(J, prov)
end
