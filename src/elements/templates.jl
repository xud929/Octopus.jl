# ---------------------------------------------------------------------------
# The MAD-X class form and the flexible form's folds (R11 of
# docs/design/machine_description_followups.md, owner decision 2026-11-26).
#
# The class-form METHODS are installed by the registration itself
# (`_install_class_form!`, src/knowledge/Knowledge.jl), one per kind with a
# type as its friendly constructor, so include order cannot miss a kind; their
# body `_derive_spec` lives here, with the RBEND alias's own method and the
# flexible form's fold hook. Included LAST in Elements.jl: the hook is
# installed where `_FOLDED_NAMED_STRENGTHS` and `_sbend_params` exist and
# after every `@element_spec` example has been built unfolded.
# ---------------------------------------------------------------------------

"""
    QuadrupoleSpec(template::ElementSpec{:quadrupole}; name, kwargs...)   # every friendly constructor

The MAD-X class form (`Q: QUADRUPOLE, L = 1.0; QF: Q, K1 = 1.0;` R11 of
`docs/design/machine_description_followups.md`, 2026-11-26) on every kind's
friendly constructor, generated over the registry: a new spec derived from a
template of the SAME kind. Semantics: start from the template's stored
parameters; a keyword replaces its key; a named strength replaces its slot in
the stored tuple (`k1` sets `kn[2]`, `k2` `kn[3]`, `k1s` `ks[2]`; the thin
kinds' `knl`/`ksl`, the solenoid's `kn`/`kskew`), instead of the "both
spellings set" refusal, because overriding the template's value is the point;
a sector bend's `angle` resets the stored `h` and `b0` (the constructor folds
`angle` into them and stores no angle); `RBendSpec(template; ...)` reads the
template as the RBEND it derives (its stored faces as `given + angle/2` with
`angle = h L`, unfolded, then refolded at the new `angle`; a new `chord`
replaces the arc `L`; a template whose `h` and `b0` differ was not built as
an RBEND and is refused by name), while `SBendSpec(template; ...)` keeps the
faces as stored; the kind is fixed by the template
(a drift template on `quadrupole(...)` is refused by name); chains are
allowed (`QF2 = quadrupole(QF; k1 = 1.2)`); knob expressions are accepted as
values (design D10); a template whose stored `numeric_type` differs from the
one given is refused, not converted (a template without one takes the given
type; none given inherits the template's); `name` is required (the
`@elements` block supplies the binding name, rule 1; two specs of one name
would share a provenance path); the result is a new spec and the template is
never mutated; the snapshot stays flat (a derivation's provenance is not
recorded). The derived parameters are rebuilt THROUGH the kind's keyword
constructor, so every check it performs runs on the result.

    @elements begin
        QF = quadrupole(RHIC.Q; k1 =  1.0)      # QuadrupoleSpec(RHIC.Q; name = "QF", numeric_type = Float64, k1 = 1.0)
        QD = quadrupole(RHIC.Q; k1 = -1.0)
    end
"""
function _derive_spec(ctor, kind::Symbol, template::ElementSpec{K}, kwargs; rbend::Bool=false) where {K}
    who = string(nameof(ctor))
    if K !== kind
        tmeta = _element_meta_or_nothing(K)
        tctor = tmeta === nothing || tmeta.friendly_constructor === nothing ? nothing :
                string(nameof(tmeta.friendly_constructor))
        throw(ArgumentError(
            "$(who)(template; ...): the template is a $(K) spec, not a $(kind); the class form " *
            "derives an element from a template of its own kind (MAD-X's `QF: Q, K1 = 1.0`). " *
            (tctor === nothing ? "Build the $(kind) from its parameters instead" :
             "Use $(tctor)(template; ...) for a $(K), or build the $(kind) from its parameters")))
    end
    kw = Dict{Symbol,Any}(kwargs)
    haskey(kw, :name) || throw(ArgumentError(
        "$(who)(template; ...): `name` is required on the class form (an `@elements` block " *
        "supplies the binding name); two specs of one name would share a provenance path"))
    merged = copy(getfield(template, :params))
    stored_T = get(merged, :numeric_type, nothing)
    given_T = get(kw, :numeric_type, nothing)
    if given_T !== nothing && stored_T !== nothing && given_T !== stored_T
        throw(ArgumentError(
            "$(who)(template; ...): the template stores numeric_type = $(stored_T) and " *
            "numeric_type = $(given_T) was given; a template is derived in its own type, never " *
            "converted (build the template typed $(given_T), or derive without numeric_type to " *
            "inherit $(stored_T))"))
    end
    # A named strength replaces its slot in the stored tuple.
    named = get(_FOLDED_NAMED_STRENGTHS, kind, ())
    nkey, skey = get(_FOLDED_TUPLE_KEYS, kind, (:kn, :ks))
    for (nsym, ssym, order) in named, (sym, key) in ((nsym, nkey), (ssym, skey))
        haskey(kw, sym) || continue
        vec = Any[collect(get(merged, key, ()))...]
        while length(vec) < order + 1
            push!(vec, 0.0)
        end
        vec[order + 1] = pop!(kw, sym)
        merged[key] = Tuple(vec)
    end
    # The bend geometry. The sector bend's constructor folds `angle` into h
    # and b0 and stores no angle, so a new angle resets both (angle beside h/b0
    # is the constructor's own refusal). An RBEND is that same kind with
    # angle/2 folded into each face (`_rbend_params`), so the RBEND form reads
    # the template as one: faces unfolded by the stored half angle h L / 2,
    # the angle restored for the constructor to refold at the new value --
    # exactly where a face angle of zero was given, to roundoff otherwise.
    if kind === :sbend && rbend
        h = _float_or_expression(get(merged, :h, 0.0))
        b0 = _float_or_expression(get(merged, :b0, 0.0))
        h == b0 || throw(ArgumentError(
            "$(who)(template; ...): the template's h = $(h) and b0 = $(b0) differ, so it was " *
            "not built as an RBEND (RBendSpec sets h = b0 = angle / L); derive it through " *
            "SBendSpec(template; ...), which keeps the stored faces"))
        angle_old = _knob_arith(:*, h, _float_or_expression(merged[:L]))
        half_old = _knob_arith(:/, angle_old, 2)
        for face in (:e1, :e2)
            merged[face] = _knob_arith(:-, _float_or_expression(get(merged, face, 0.0)), half_old)
        end
        delete!(merged, :h)
        delete!(merged, :b0)
        haskey(kw, :angle) || (merged[:angle] = angle_old)
        haskey(kw, :chord) && delete!(merged, :L)
    elseif kind === :sbend && haskey(kw, :angle)
        delete!(merged, :h)
        delete!(merged, :b0)
    end
    for (k, v) in kw
        merged[k] = v
    end
    return ctor(; merged...)
end

# `RBendSpec(template::ElementSpec{:sbend}; name, kwargs...)`: the class form
# of the RBEND alias (`register_friendly_alias!`; an RBEND is an
# `ElementSpec{:sbend}` with `angle/2` folded into each face). The template is
# read as the RBEND being derived -- the rule is in `_derive_spec`'s docstring
# -- and the result is rebuilt through `RBendSpec(; ...)`, so `chord` is
# accepted and the faces are refolded at the new angle. Documented on
# `_derive_spec` rather than here: a docstring on a `(::Type{...})` method
# attaches to `Core.Type`, a foreign binding the suite's docstring sweep
# refuses.
(::Type{RBendSpec})(template::ElementSpec{K}; kwargs...) where {K} =
    _derive_spec(RBendSpec, :sbend, template, kwargs; rbend=true)

"""
    _fold_flexible_params!(kind, params)

The flexible form's folds (R11, the finding of section 4, probe 3): a named
strength handed to `ElementSpec{kind}(params)` -- and so to the snapshot
reader -- used to be stored as a declared key the compile never reads (`k1` on
a quadrupole compiled `kn = ()`, a silently ignored configuration). Now the
form folds as the friendly constructors do, through their own fold functions:
the named strengths of every kind in `_FOLDED_NAMED_STRENGTHS` into their
tuples (the "both spellings set" refusal included) and a sector bend's
`angle` into `h` and `b0` (`_sbend_params`; `chord` is the RBEND alias's
spelling, folded by `RBendSpec` alone, and no kind declares it). A typed
spec's folded values are re-narrowed to its `numeric_type`. A
dictionary with none of these keys -- every friendly constructor's output,
every snapshot the writer emits, every `resolve_knobs` rebuild -- is left
untouched. The writer stays flat: a hand-written `k1 = 1.0` reads as meant and
is written back as `kn`.
"""
function _fold_flexible_params!(kind::Symbol, params::Dict{Symbol,Any})
    named = get(_FOLDED_NAMED_STRENGTHS, kind, nothing)
    if named !== nothing && any(((n, s, _),) -> haskey(params, n) || haskey(params, s), named)
        nkey, skey = get(_FOLDED_TUPLE_KEYS, kind, (:kn, :ks))
        folded = _fold_named_strengths(named, params; nkey=nkey, skey=skey, kind=kind)
        T = get(params, :numeric_type, nothing)
        empty!(params)
        merge!(params, folded)
        if T !== nothing
            for key in (nkey, skey)
                haskey(params, key) && (params[key] = _as_numeric_type(T, params[key], key))
            end
        end
    end
    if kind === :sbend && haskey(params, :angle)
        folded = _sbend_params(params)
        T = get(params, :numeric_type, nothing)
        empty!(params)
        merge!(params, folded)
        if T !== nothing
            for key in (:h, :b0)
                haskey(params, key) && (params[key] = _as_numeric_type(T, params[key], key))
            end
        end
    end
    return params
end
_FLEXIBLE_FOLD_HOOK[] = _fold_flexible_params!
