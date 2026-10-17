export RNG_PHILOX, RNG_SPLITMIX,
       set_global_rng!, global_rng_seed, global_rng_method, global_rng_method_code,
       next_rng_id!, claim_rng_id!, reset_rng_id_counter!,
       octopus_uint64, octopus_uniform01, octopus_normal_pair, octopus_normal,
       counter_philox4x32, counter_uint64, counter_uniform01, philox4x32_self_test,
       counter_normal_pair, counter_normal,
       splitmix_uint64, splitmix_uniform01, splitmix_normal_pair, splitmix_normal

"""Counter-RNG method code selecting the Philox4x32 generator (`:philox`)."""
const RNG_PHILOX = UInt8(1)

"""Counter-RNG method code selecting the SplitMix64-hash generator (`:splitmix`)."""
const RNG_SPLITMIX = UInt8(2)
const COUNTER_RNG_TWO_NEG_23 = 1.1920928955078125f-7
const COUNTER_RNG_TWO_NEG_52 = 2.220446049250313e-16
const COUNTER_RNG_TWO_PI = 6.283185307179586476925286766559
const PHILOX4X32_M0 = UInt32(0xD2511F53)
const PHILOX4X32_M1 = UInt32(0xCD9E8D57)
const PHILOX4X32_W0 = UInt32(0x9E3779B9)
const PHILOX4X32_W1 = UInt32(0xBB67AE85)
const PHILOX4X32_ROUNDS = 10

const _GLOBAL_RNG_SEED = Ref{UInt64}(0)
const _GLOBAL_RNG_METHOD = Ref{UInt8}(RNG_PHILOX)
const _GLOBAL_RNG_ID_COUNTER = Threads.Atomic{UInt64}(0)

"""
    set_global_rng!(; seed=global_rng_seed(), method=global_rng_method())

Set the Octopus global stochastic seed and counter-RNG method. This controls
Octopus-managed stochastic consumers such as counter-RNG beam initialization and
context-aware radiation tracking. `method` may be `:philox` or `:splitmix`.
"""
function set_global_rng!(; seed::Integer=global_rng_seed(), method=global_rng_method())
    _GLOBAL_RNG_SEED[] = UInt64(seed)
    _GLOBAL_RNG_METHOD[] = rng_method_code(method)
    return (_GLOBAL_RNG_SEED[], global_rng_method())
end

"""Return the current Octopus global stochastic seed."""
global_rng_seed() = _GLOBAL_RNG_SEED[]

"""Return the current Octopus global RNG method as a symbol."""
global_rng_method() = rng_method_symbol(_GLOBAL_RNG_METHOD[])

"""Return the current Octopus global RNG method as an isbits code."""
global_rng_method_code() = _GLOBAL_RNG_METHOD[]

"""One explicitly claimed id: the class of the automatic assignment that
preceded its first claim (`nothing` for none, `missing` for one outside the
class window) and the classes that have claimed it, in claim order."""
struct _RngIdClaim
    auto::Union{Nothing,Missing,Symbol}
    classes::Vector{Symbol}
end

"""
    _RNG_ID_REGISTRY

The stream-id registry beside the atomic counter of the automatic sequence
(owner policy 2026-10-16, crab-noise neighbour audit S1-6, todo rows 34 and
38; re-shaped by fix group F the same day, todo rows 31 and 40, when the
counter stopped being a high-water mark over explicit claims): the counter
alone could not see an explicit id chosen AFTER a fresh consumer had received
it, nor two consumer classes choosing one id. Three tables, all guarded by
`_RNG_ID_REGISTRY_LOCK`:

  * `explicit`: every explicitly claimed id, with the classes that claimed it
    and whether an automatic assignment preceded the first claim (`nothing`:
    none; a class symbol; `missing`: one whose class the window below no
    longer held). One entry per DISTINCT explicit id, each the user's own
    choice, so this table grows only with deliberate claims.
  * `classes`: a ring of class codes for the last `_RNG_ID_CLASS_WINDOW`
    automatic assignments (one byte each, `class_names` decoding the codes),
    the memory behind "already held by a beam consumer (auto-assigned at
    construction)". Automatic ids need no table of their own: `next_rng_id!`
    issues them consecutively from the counter, skipping the explicit ones, so
    every id in `(floor, counter]` that is not explicit WAS auto-assigned, by
    arithmetic; the ring only remembers by whom. Before fix group F the
    registry kept a `Dict` entry per automatic assignment (measured 132.6 B
    each, 13.3 MB per 100,000 consumers); now 64 kB fixed.
  * `floor`: the counter's value at the last `reset_rng_id_counter!` or at
    `__init__`. Ids at or below it are unknown to this process (what the
    precompile process claimed -- the `@element_spec` examples -- is not this
    process's; a reset may reissue them) and are never reported as held.
"""
mutable struct _RngIdRegistry
    floor::UInt64
    classes::Vector{UInt8}
    class_names::Vector{Symbol}
    explicit::Dict{UInt64,_RngIdClaim}
end

"""How many automatic assignments keep their consumer class in the registry
(`_RngIdRegistry.classes`); an explicit claim of an older automatic id still
warns, as auto-assigned, with its class reported as not retained."""
const _RNG_ID_CLASS_WINDOW = 1 << 16
const _RNG_ID_REGISTRY = _RngIdRegistry(UInt64(0), zeros(UInt8, _RNG_ID_CLASS_WINDOW), Symbol[],
                                        Dict{UInt64,_RngIdClaim}())
const _RNG_ID_REGISTRY_LOCK = ReentrantLock()

"""
    next_rng_id!(; consumer=:unspecified) -> UInt64

Return the next automatically assigned stochastic consumer stream id, recorded
in the registry as held by `consumer` (the class label a constructor passes:
`:beam`, `:lumped_radiation`, `:turn_rule`, `:bpm_observer`; the suite derives
the list from the call sites). This is what every consumer's `rng_id = 0`
resolves to, at construction: the one policy for the Beam, `LumpedRadSpec`,
the turn-modulation rules and `BPMObserver`. The sequence is the counter's
successor, SKIPPING every id claimed explicitly in this process (fix group F,
2026-10-16): before, `claim_rng_id!` raised the counter past its id, so an
explicit `typemax(UInt64)` left the next automatic consumer with nothing to
issue, and a claim of `1000` moved the sequence from 3 to 1001. Throws when
the counter itself is exhausted at `typemax(UInt64)` -- 2^64 assignments, or
a `reset_rng_id_counter!(value)` near the top -- rather than wrapping to 0,
the id every consumer reads as "fresh".
"""
function next_rng_id!(; consumer::Symbol=:unspecified)
    lock(_RNG_ID_REGISTRY_LOCK)
    try
        registry = _RNG_ID_REGISTRY
        id = _GLOBAL_RNG_ID_COUNTER[]
        while true
            id == typemax(UInt64) && throw(ArgumentError(
                "the automatic rng_id counter is exhausted: every stream id from the " *
                "counter's floor $(registry.floor) to typemax(UInt64) has been issued or " *
                "claimed in this process (the automatic sequence skips explicitly claimed " *
                "ids, so reaching the top takes 2^64 assignments, or a " *
                "reset_rng_id_counter!(value) near it). Call reset_rng_id_counter!(value) " *
                "in a session that no longer needs the ids above value."))
            id += UInt64(1)
            haskey(registry.explicit, id) || break
        end
        _GLOBAL_RNG_ID_COUNTER[] = id
        registry.classes[_rng_id_ring_slot(id)] = _rng_id_class_code!(registry, consumer)
        return id
    finally
        unlock(_RNG_ID_REGISTRY_LOCK)
    end
end

_rng_id_ring_slot(id::UInt64) = Int(id % UInt64(_RNG_ID_CLASS_WINDOW)) + 1

# The class code of `consumer`, assigned at its first appearance; code 0 is
# "no automatic assignment" (a ring slot never written since the last reset)
# and the last code stands for every class beyond the 254 the table names.
function _rng_id_class_code!(registry::_RngIdRegistry, consumer::Symbol)
    code = findfirst(==(consumer), registry.class_names)
    code === nothing || return UInt8(code)
    length(registry.class_names) < 254 || return UInt8(255)
    push!(registry.class_names, consumer)
    return UInt8(length(registry.class_names))
end

# The automatic holder of `uid`, read under the lock: `nothing` when the id was
# never auto-assigned since the floor, its class while the ring still holds
# it, `missing` once the ring has moved on. Every id in `(floor, counter]` is
# either explicit or auto-assigned (the sequence is consecutive), and an
# explicit id is answered from its own claim record, so the ring is read only
# for ids the sequence actually issued.
function _rng_id_auto_holder(registry::_RngIdRegistry, uid::UInt64)
    counter = _GLOBAL_RNG_ID_COUNTER[]
    (registry.floor < uid <= counter) || return nothing
    counter - uid < UInt64(_RNG_ID_CLASS_WINDOW) || return missing
    code = registry.classes[_rng_id_ring_slot(uid)]
    code == 0 && return missing
    code == 255 && return Symbol("a class beyond the 254 this registry names")
    return registry.class_names[code]
end

"""
    _rng_id_held(id::Integer) -> Bool
    _unheld_rng_id(start::Integer) -> UInt64

Whether a stream id is held in this process -- claimed explicitly, or issued
automatically since the registry's floor (`_RNG_ID_REGISTRY`) -- and the
smallest id at or above `start` that nobody holds. Not a claim: the id is
free only until a consumer takes it. The suite's "fresh explicit id"
convention is `_unheld_rng_id(next_rng_id!() + 1_000_000)`: above the counter,
above every literal id of the suite and, since a claim no longer moves the
counter (fix group F, 2026-10-16), clear of the ids another test claimed from
the same band -- `next_rng_id!() + 1_000_000` alone collided once the counter
stopped jumping past claims (two testsets' ids met on a lumped_radiation /
turn_rule pair). An id a refused constructor was handed stays unheld, which
is how a test shows the refusal claimed nothing.
"""
function _rng_id_held(id::Integer)
    id >= 0 || return false
    uid = UInt64(id)
    lock(_RNG_ID_REGISTRY_LOCK)
    try
        registry = _RNG_ID_REGISTRY
        haskey(registry.explicit, uid) && return true
        return registry.floor < uid <= _GLOBAL_RNG_ID_COUNTER[]
    finally
        unlock(_RNG_ID_REGISTRY_LOCK)
    end
end
function _unheld_rng_id(start::Integer)
    id = UInt64(start)
    while _rng_id_held(id)
        id == typemax(UInt64) && throw(ArgumentError(
            "no unheld rng_id at or above $(start): every id up to typemax(UInt64) is held"))
        id += UInt64(1)
    end
    return id
end

"""
    claim_rng_id!(id; consumer=:unspecified) -> UInt64

Record an **explicitly chosen** stochastic stream id and return it as a
`UInt64`; the automatic sequence (`next_rng_id!`) skips it from now on, and
the claim warns -- never refuses -- when the id is already held in this
process by a consumer the claim would share a stream with.

Without the registry, an explicit id and an automatic one collide silently.
Measured (2026-08-05_b audit, U14-2): `Beam(...; rng_id = 1)` left the counter
at 0, an auto-assigned `LumpedRadSpec` in the same session then also received
id 1, and the two consumers drew **the same stream** -- beam initial
coordinates and radiation excitation correlating at 0.99988. That is the
worst possible correlation for an emittance-growth study, because the
excitation is aligned with the distribution it is supposed to diffuse.

Until fix group F (2026-10-16) the claim raised the atomic counter past its id
(a high-water mark), which kept the sequence clear of it but let one claim
move the sequence: `claim_rng_id!(1000)` sent the next fresh consumer to 1001,
and an explicit `typemax(UInt64)` left the next automatic consumer with
nothing to issue until a reset (todo row 31). Now the claim is recorded and
the sequence steps over every recorded id when it reaches it, so the counter
moves only by automatic assignments and `typemax(UInt64)` is as claimable as
any other id. The counter did not see the reverse order either -- an
explicit id chosen to match an auto-assignment that has already issued
(measured 2026-10-16, crab-noise neighbour audit S1-6: a Beam took auto id 7,
`LumpedRadSpec(rng_id = 7)` was accepted silently and their turn-0 cells were
equal) -- nor two consumer CLASSES choosing one id (S1-5: a `SpectralNoise`,
a `LumpedRadSpec` and a `BPMObserver` on id 5 built with no warning, the
spectral bin k's Rayleigh pair being radiation particle k's normals). The
registry (`_RNG_ID_REGISTRY`) sees both, and the policy (owner decision
2026-10-16) is:

  * an explicit claim of an id that was AUTO-ASSIGNED earlier in this process
    warns by name: the id, the holder's class (or that the class is no longer
    retained, beyond the last `_RNG_ID_CLASS_WINDOW` assignments), the
    claimant's class, and the remedy (an id above the registry's counter, or
    `rng_id = 0`);
  * an explicit claim of an id already claimed explicitly by a DIFFERENT class
    (beam, radiation, turn-modulation rule, BPM observer) warns, naming both
    classes;
  * explicit reuse of one id by the SAME class is silent: it is the user's
    reproducibility handle (the suite builds thousands of `Beam(...; rng_id =
    1)`), and two placements of one class sharing a stream in one task are
    caught by the task constructor's duplicate-stream warnings;
  * `id = 0` is refused: it is the request for a fresh stream, which every
    consumer resolves at construction through `next_rng_id!`, never a stream;
  * a negative `id` is refused by name (todo row 40; it used to die in the
    `UInt64` conversion with an `InexactError`, on `LumpedRadSpec`, `Beam` and
    `BPMObserver`; the rules refused it themselves).

Each `(id, class)` pair warns once; a warning is a shared stream, not a
refusal, because sharing is sometimes intended. Two consumers on one stream
draw identical normals wherever their key regions coincide (the key layout
above `_RULE_COMPONENT_BASE` in `src/elements/turn_modulated.jl` says which
classes do). `consumer` keeps its default so a call site that has not been
taught its class still compiles; the suite's tripwire requires every call site
in `src/` to pass one.
"""
function claim_rng_id!(id::Integer; consumer::Symbol=:unspecified)
    id >= 0 || throw(ArgumentError(
        "rng_id $(id) is negative: a counter-RNG stream id is a non-negative integer " *
        "(0 requests a fresh stream, assigned at construction; a positive id up to " *
        "typemax(UInt64) is claimed as the consumer's own stream); claimant: $(consumer)"))
    uid = UInt64(id)
    uid == 0 && throw(ArgumentError(
        "rng_id 0 is not a stream: it is the request for a fresh stream, which every " *
        "consumer resolves at construction with next_rng_id!(); claim_rng_id! records " *
        "an explicitly chosen positive id (claimant: $(consumer))"))
    message = _register_rng_id_claim!(uid, consumer)
    message === nothing || @warn message rng_id = uid claimant = consumer
    return uid
end

# The locked part of `claim_rng_id!`: record the claim unless the same class
# already holds the id explicitly, and return the sharing message when another
# holder exists (emitted outside the lock).
function _register_rng_id_claim!(uid::UInt64, consumer::Symbol)
    lock(_RNG_ID_REGISTRY_LOCK)
    try
        registry = _RNG_ID_REGISTRY
        claim = get(registry.explicit, uid, nothing)
        if claim === nothing
            auto = _rng_id_auto_holder(registry, uid)
            registry.explicit[uid] = _RngIdClaim(auto, [consumer])
            return auto === nothing ? nothing : _rng_id_sharing_message(uid, consumer, auto, Symbol[])
        end
        consumer in claim.classes && return nothing
        others = copy(claim.classes)
        push!(claim.classes, consumer)
        return _rng_id_sharing_message(uid, consumer, claim.auto, others)
    finally
        unlock(_RNG_ID_REGISTRY_LOCK)
    end
end

function _rng_id_sharing_message(id::UInt64, consumer::Symbol, auto, explicit_classes)
    holders = String[]
    auto === nothing || push!(holders,
        auto === missing ?
            "an auto-assigned consumer (its class is no longer retained: the registry keeps " *
            "the class of the last $(_RNG_ID_CLASS_WINDOW) automatic assignments)" :
            "a $(auto) consumer (auto-assigned at construction)")
    for class in explicit_classes
        push!(holders, "a $(class) consumer (explicit)")
    end
    return "rng_id $(id), claimed explicitly by a $(consumer) consumer, is already held in " *
           "this process by $(join(holders, ", ")): two consumers on one counter-RNG stream " *
           "draw identical normals wherever their key regions coincide (the key layout above " *
           "_RULE_COMPONENT_BASE in src/elements/turn_modulated.jl says which classes do). " *
           "Give the new consumer an id above the registry's counter " *
           "($(_GLOBAL_RNG_ID_COUNTER[])), or leave rng_id = 0, which assigns a fresh stream " *
           "at construction. (One class reusing one id is the reproducibility handle and " *
           "stays silent; placements sharing a stream within one task are warned by the " *
           "task constructor.)"
end

"""
    reset_rng_id_counter!(value=0) -> UInt64

Reset the automatic stochastic consumer stream-id counter to `value` and
forget every recorded holder (`_RNG_ID_REGISTRY`): ids at or below `value` may
be reissued, so the memory of who held them would be wrong. A test that
claims an extreme id or needs a known fresh sequence saves the counter
(`next_rng_id!()`) first and restores it through this.
"""
function reset_rng_id_counter!(value::Integer=0)
    lock(_RNG_ID_REGISTRY_LOCK)
    try
        _GLOBAL_RNG_ID_COUNTER[] = UInt64(value)
        _forget_rng_id_holders_locked!()
        return _GLOBAL_RNG_ID_COUNTER[]
    finally
        unlock(_RNG_ID_REGISTRY_LOCK)
    end
end

"""Empty the registry's holder memory (the counter is untouched, and becomes
the floor below which nothing is known); `__init__` and
`reset_rng_id_counter!` call it."""
function _forget_rng_id_holders!()
    lock(_RNG_ID_REGISTRY_LOCK)
    try
        _forget_rng_id_holders_locked!()
    finally
        unlock(_RNG_ID_REGISTRY_LOCK)
    end
    return nothing
end

function _forget_rng_id_holders_locked!()
    registry = _RNG_ID_REGISTRY
    registry.floor = _GLOBAL_RNG_ID_COUNTER[]
    fill!(registry.classes, UInt8(0))
    empty!(registry.class_names)
    empty!(registry.explicit)
    return nothing
end

rng_method_code(code::UInt8) = code
rng_method_code(method::Symbol) =
    method == :philox ? RNG_PHILOX :
    method == :splitmix ? RNG_SPLITMIX :
    throw(ArgumentError("unknown RNG method $(method); use :philox or :splitmix"))
rng_method_code(method::AbstractString) = rng_method_code(Symbol(lowercase(method)))

rng_method_symbol(code::UInt8) =
    code == RNG_PHILOX ? :philox :
    code == RNG_SPLITMIX ? :splitmix :
    throw(ArgumentError("unknown RNG method code $(code)"))

"""
    octopus_uint64(seed, method, turn, rng_id, particle_index, component)

Return a deterministic `UInt64` using the selected Octopus counter RNG method.
"""
@inline function octopus_uint64(seed, method_code::UInt8, turn, rng_id, particle_index, component)
    if method_code == RNG_PHILOX
        return counter_uint64(seed, turn, rng_id, particle_index, component)
    elseif method_code == RNG_SPLITMIX
        return splitmix_uint64(seed, turn, rng_id, particle_index, component)
    else
        # An unknown method code is a wiring bug, not a preference for
        # Philox: falling through silently produced valid-looking numbers
        # from the wrong stream (2026-08-05 audit, U15-4);
        # rng_method_symbol already throws for the same code.
        #
        # The message is STATIC because this runs inside CUDA kernels (every
        # stochastic element draws through here): interpolating the code
        # builds a heap string, which is invalid device IR — the U15-4 throw
        # as first written broke the fused-kernel compile for any line
        # containing a counter-RNG element, and no suite test tracked one on
        # the fused CUDA path to notice (caught by the U21-5 coverage
        # extension; pinned in the suite).
        throw(ArgumentError("unknown RNG method code; use RNG_PHILOX or RNG_SPLITMIX"))
    end
end

@inline octopus_uint64(seed, method, turn, rng_id, particle_index, component) =
    octopus_uint64(seed, rng_method_code(method), turn, rng_id, particle_index, component)

"""Method-selected version of `counter_uniform01`."""
@inline function octopus_uniform01(seed, method_code::UInt8, turn, rng_id, particle_index, component,
                                  ::Type{Float64})
    return _uniform_open01(
        octopus_uint64(seed, method_code, turn, rng_id, particle_index, component),
        Float64,
    )
end

@inline function octopus_uniform01(seed, method_code::UInt8, turn, rng_id, particle_index, component,
                                  ::Type{Float32})
    return _uniform_open01(
        octopus_uint64(seed, method_code, turn, rng_id, particle_index, component),
        Float32,
    )
end

@inline octopus_uniform01(seed, method, turn, rng_id, particle_index, component, ::Type{T}) where {T<:AbstractFloat} =
    octopus_uniform01(seed, rng_method_code(method), turn, rng_id, particle_index, component, T)

@inline octopus_uniform01(seed, method, turn, rng_id, particle_index, component) =
    octopus_uniform01(seed, method, turn, rng_id, particle_index, component, Float64)

"""Method-selected version of `counter_normal_pair`."""
@inline function octopus_normal_pair(seed, method, turn, rng_id, particle_index, pair_id,
                                    ::Type{T}) where {T<:AbstractFloat}
    method_code = rng_method_code(method)
    u1 = octopus_uniform01(seed, method_code, turn, rng_id, particle_index, 2 * pair_id - 1, T)
    u2 = octopus_uniform01(seed, method_code, turn, rng_id, particle_index, 2 * pair_id, T)
    r = sqrt(T(-2) * log(u1))
    theta = T(COUNTER_RNG_TWO_PI) * u2
    return r * cos(theta), r * sin(theta)
end

@inline octopus_normal_pair(seed, method, turn, rng_id, particle_index, pair_id) =
    octopus_normal_pair(seed, method, turn, rng_id, particle_index, pair_id, Float64)

"""Method-selected standard normal sample for Octopus-managed stochastic consumers."""
@inline function octopus_normal(seed, method, turn, rng_id, particle_index, component,
                               ::Type{T}) where {T<:AbstractFloat}
    pair_id = (component + 1) ÷ 2
    n1, n2 = octopus_normal_pair(seed, method, turn, rng_id, particle_index, pair_id, T)
    return isodd(component) ? n1 : n2
end

@inline octopus_normal(seed, method, turn, rng_id, particle_index, component) =
    octopus_normal(seed, method, turn, rng_id, particle_index, component, Float64)

"""
    counter_philox4x32(seed, turn, rng_id, particle_index, component)

Return four deterministic `UInt32` pseudorandom values using Philox4x32-10.

`particle_index` and `turn` form the 128-bit Philox counter. `seed`,
`rng_id`, and `component` are mixed into the 64-bit Philox key. `rng_id`
separates independent stochastic elements or streams.
"""
@inline function counter_philox4x32(seed::Integer, turn::Integer, rng_id::Integer,
                                   particle_index::Integer, component::Integer)
    particle = UInt64(particle_index)
    turn64 = UInt64(turn)
    c0 = _counter_rng_low32(particle)
    c1 = _counter_rng_high32(particle)
    c2 = _counter_rng_low32(turn64)
    c3 = _counter_rng_high32(turn64)

    # Accepted limitation, recorded (2026-08-05 audit, U15-2): the XOR of
    # three splitmix hashes admits closed-form full-stream collisions — e.g.
    # the (seed, rng_id) pair swapped against (rng_id + G, seed − G) yields
    # an identical key. The colliding partners sit ~1e19 apart, unreachable
    # from the sequential ids this codebase assigns, so the mix is kept for
    # its speed; changing it would re-seed every recorded run.
    key = _counter_rng_splitmix64(UInt64(seed)) ⊻
          _counter_rng_splitmix64(UInt64(rng_id) + 0x9e3779b97f4a7c15) ⊻
          _counter_rng_splitmix64(UInt64(component) + 0xbf58476d1ce4e5b9)
    k0 = _counter_rng_low32(key)
    k1 = _counter_rng_high32(key)

    return _philox4x32_block(c0, c1, c2, c3, k0, k1)
end

"""
    _philox4x32_block(c0, c1, c2, c3, k0, k1)

Apply the full Philox4x32-`PHILOX4X32_ROUNDS` block function to a 128-bit
counter and 64-bit key, returning the four output words.

This is the round loop *and* the Weyl key schedule that
[`counter_philox4x32`](@ref) runs, factored out so that the known-answer test
can drive the production driver rather than a re-implementation of it. Keeping
it in one place is the point: the previous known-answer testset re-wrote this
loop locally, so it pinned `_philox4x32_round` and the constants but not the
schedule that actually consumes them (2026-08-05_b audit, U25-2).
"""
@inline function _philox4x32_block(c0::UInt32, c1::UInt32, c2::UInt32, c3::UInt32,
                                   k0::UInt32, k1::UInt32)
    for _ in 1:PHILOX4X32_ROUNDS
        c0, c1, c2, c3 = _philox4x32_round(c0, c1, c2, c3, k0, k1)
        k0 += PHILOX4X32_W0
        k1 += PHILOX4X32_W1
    end
    return c0, c1, c2, c3
end

"""
    philox4x32_self_test() -> Bool

Check the counter RNG's block function against the upstream Random123
`kat_vectors` for `philox4x32-10`, returning `true` when it reproduces all
three bit-for-bit.

This answers a question no amount of moment-and-correlation testing can. Those
statistics are satisfied by any generator with good low-order behaviour
whatever its round function: a Philox with the Weyl key bump removed, and a
3-round variant, both pass a mean/variance/correlation gate comfortably
(2026-08-05_b audit, U25-2, measured). Only a known-answer vector pins the
*implementation*. Both `test/runtests.jl` and
`validation/counter_rng_validation.jl` call this, so there is one copy of the
vectors and one driver under test.
"""
function philox4x32_self_test()
    PHILOX4X32_ROUNDS == 10 || return false
    return _philox4x32_block(0x00000000, 0x00000000, 0x00000000, 0x00000000,
                             0x00000000, 0x00000000) ==
           (0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8) &&
           _philox4x32_block(0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
                             0xffffffff, 0xffffffff) ==
           (0x408f276d, 0x41c83b0e, 0xa20bc7c6, 0x6d5451fd) &&
           _philox4x32_block(0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344,
                             0xa4093822, 0x299f31d0) ==
           (0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1)
end

"""
    counter_uint64(seed, turn, rng_id, particle_index, component)

Return a deterministic `UInt64` pseudorandom value from integer counters.

The generator is Philox4x32-10 and stateless: changing CUDA thread/block layout
or CPU thread count does not change the value for the same counter tuple.
"""
@inline function counter_uint64(seed::Integer, turn::Integer, rng_id::Integer,
                               particle_index::Integer, component::Integer)
    a, b, _, _ = counter_philox4x32(seed, turn, rng_id, particle_index, component)
    return (UInt64(a) << 32) | UInt64(b)
end

"""
    splitmix_uint64(seed, turn, rng_id, particle_index, component)

Return a deterministic `UInt64` pseudorandom value using a SplitMix64-style
counter hash. This is exposed for comparison and validation. Prefer the
Philox-backed `counter_uint64` for production stochastic tracking.
"""
@inline function splitmix_uint64(seed::Integer, turn::Integer, rng_id::Integer,
                                particle_index::Integer, component::Integer)
    x = UInt64(seed)
    x ⊻= _counter_rng_splitmix64(UInt64(turn) + 0x9e3779b97f4a7c15)
    x ⊻= _counter_rng_splitmix64(UInt64(rng_id) + 0xbf58476d1ce4e5b9)
    x ⊻= _counter_rng_splitmix64(UInt64(particle_index) + 0x94d049bb133111eb)
    x ⊻= _counter_rng_splitmix64(UInt64(component) + 0xD2B74407B1CE6E93)
    return _counter_rng_splitmix64(x)
end

"""
    counter_uniform01(seed, turn, rng_id, particle_index, component, T=Float64)

Return a deterministic uniform value in the open interval `(0, 1)`.

`T` may be `Float64` or `Float32`. The result is generated from high-order
counter RNG bits and is suitable for CPU and CUDA device code.
"""
@inline counter_uniform01(seed, turn, rng_id, particle_index, component) =
    counter_uniform01(seed, turn, rng_id, particle_index, component, Float64)

@inline function counter_uniform01(seed, turn, rng_id, particle_index, component,
                                   ::Type{Float64})
    return _uniform_open01(
        counter_uint64(seed, turn, rng_id, particle_index, component), Float64,
    )
end

@inline function counter_uniform01(seed, turn, rng_id, particle_index, component,
                                   ::Type{Float32})
    return _uniform_open01(
        counter_uint64(seed, turn, rng_id, particle_index, component), Float32,
    )
end

"""SplitMix64-backed version of [`counter_uniform01`](@ref)."""
@inline splitmix_uniform01(seed, turn, rng_id, particle_index, component) =
    splitmix_uniform01(seed, turn, rng_id, particle_index, component, Float64)

@inline function splitmix_uniform01(seed, turn, rng_id, particle_index, component,
                                    ::Type{Float64})
    return _uniform_open01(
        splitmix_uint64(seed, turn, rng_id, particle_index, component), Float64,
    )
end

@inline function splitmix_uniform01(seed, turn, rng_id, particle_index, component,
                                    ::Type{Float32})
    return _uniform_open01(
        splitmix_uint64(seed, turn, rng_id, particle_index, component), Float32,
    )
end

# Use one fewer source bit than the significand precision so adding the half-bin
# offset is exact. The resulting midpoint grids are strictly inside (0, 1) for
# every UInt64 input on both CPU and CUDA; using 53/24 bits can round the upper
# endpoint to exactly one.
@inline function _uniform_open01(value::UInt64, ::Type{Float64})
    bits = value >> 12
    return (Float64(bits) + 0.5) * COUNTER_RNG_TWO_NEG_52
end

@inline function _uniform_open01(value::UInt64, ::Type{Float32})
    bits = value >> 41
    return (Float32(bits) + 0.5f0) * COUNTER_RNG_TWO_NEG_23
end

"""
    counter_normal_pair(seed, turn, rng_id, particle_index, pair_id, T=Float64)

Return two deterministic standard normal samples using the Box-Muller
transform. One pair consumes two counter-uniform values and discards no samples.
"""
@inline counter_normal_pair(seed, turn, rng_id, particle_index, pair_id) =
    counter_normal_pair(seed, turn, rng_id, particle_index, pair_id, Float64)

@inline function counter_normal_pair(seed, turn, rng_id, particle_index, pair_id,
                                     ::Type{T}) where {T<:AbstractFloat}
    u1 = counter_uniform01(seed, turn, rng_id, particle_index, 2 * pair_id - 1, T)
    u2 = counter_uniform01(seed, turn, rng_id, particle_index, 2 * pair_id, T)
    r = sqrt(T(-2) * log(u1))
    theta = T(COUNTER_RNG_TWO_PI) * u2
    return r * cos(theta), r * sin(theta)
end

"""SplitMix64-backed version of [`counter_normal_pair`](@ref)."""
@inline splitmix_normal_pair(seed, turn, rng_id, particle_index, pair_id) =
    splitmix_normal_pair(seed, turn, rng_id, particle_index, pair_id, Float64)

@inline function splitmix_normal_pair(seed, turn, rng_id, particle_index, pair_id,
                                     ::Type{T}) where {T<:AbstractFloat}
    u1 = splitmix_uniform01(seed, turn, rng_id, particle_index, 2 * pair_id - 1, T)
    u2 = splitmix_uniform01(seed, turn, rng_id, particle_index, 2 * pair_id, T)
    r = sqrt(T(-2) * log(u1))
    theta = T(COUNTER_RNG_TWO_PI) * u2
    return r * cos(theta), r * sin(theta)
end

"""
    counter_normal(seed, turn, rng_id, particle_index, component, T=Float64)

Return one deterministic standard normal sample. Odd/even components share one
Box-Muller pair, so components 1 and 2 are generated together, components 3 and
4 together, and so on.
"""
@inline counter_normal(seed, turn, rng_id, particle_index, component) =
    counter_normal(seed, turn, rng_id, particle_index, component, Float64)

@inline function counter_normal(seed, turn, rng_id, particle_index, component,
                                ::Type{T}) where {T<:AbstractFloat}
    pair_id = (component + 1) ÷ 2
    n1, n2 = counter_normal_pair(seed, turn, rng_id, particle_index, pair_id, T)
    return isodd(component) ? n1 : n2
end

"""SplitMix64-backed version of [`counter_normal`](@ref)."""
@inline splitmix_normal(seed, turn, rng_id, particle_index, component) =
    splitmix_normal(seed, turn, rng_id, particle_index, component, Float64)

@inline function splitmix_normal(seed, turn, rng_id, particle_index, component,
                                ::Type{T}) where {T<:AbstractFloat}
    pair_id = (component + 1) ÷ 2
    n1, n2 = splitmix_normal_pair(seed, turn, rng_id, particle_index, pair_id, T)
    return isodd(component) ? n1 : n2
end

@inline function _counter_rng_splitmix64(x::UInt64)
    z = x + 0x9e3779b97f4a7c15
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

@inline _counter_rng_low32(x::UInt64) = UInt32(x & 0x00000000ffffffff)
@inline _counter_rng_high32(x::UInt64) = UInt32(x >> 32)

@inline function _philox4x32_mulhilo(a::UInt32, b::UInt32)
    product = UInt64(a) * UInt64(b)
    return UInt32(product >> 32), UInt32(product & 0x00000000ffffffff)
end

@inline function _philox4x32_round(c0::UInt32, c1::UInt32,
                                  c2::UInt32, c3::UInt32,
                                  k0::UInt32, k1::UInt32)
    hi0, lo0 = _philox4x32_mulhilo(PHILOX4X32_M0, c0)
    hi1, lo1 = _philox4x32_mulhilo(PHILOX4X32_M1, c2)
    return hi1 ⊻ c1 ⊻ k0, lo1, hi0 ⊻ c3 ⊻ k1, lo0
end
