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

"""Return the next automatically assigned stochastic consumer stream id."""
function next_rng_id!()
    # Atomic: two beams or radiation specs constructed concurrently must not
    # draw the same stream id, which would mean identical noise (2026-08-05
    # audit, U15-5).
    return Threads.atomic_add!(_GLOBAL_RNG_ID_COUNTER, UInt64(1)) + UInt64(1)
end

"""
    claim_rng_id!(id) -> UInt64

Record an **explicitly chosen** stochastic stream id and return it, advancing
the auto-assign counter past it so `next_rng_id!` can never reissue it.

Without this, an explicit id and an automatic one collide silently. Measured
(2026-08-05_b audit, U14-2): `Beam(...; rng_id = 1)` left the counter at 0, an
auto-assigned `LumpedRadSpec` in the same session then also received id 1, and
the two consumers drew **the same stream** — beam initial coordinates and
radiation excitation correlating at 0.99988. That is the worst possible
correlation for an emittance-growth study, because the excitation is aligned
with the distribution it is supposed to diffuse.

A high-water mark rather than a registry: it is atomic, order-independent, and
costs one compare-and-swap per stochastic consumer at construction. It does not
catch the reverse order (an explicit id chosen to match one auto-assignment has
already issued); `_warn_duplicate_radiation_streams` covers part of that, and
the full registry is recorded in the audit queue rather than built here.
"""
function claim_rng_id!(id::Integer)
    id > 0 && Threads.atomic_max!(_GLOBAL_RNG_ID_COUNTER, UInt64(id))
    return UInt64(id)
end

"""Reset the automatic stochastic consumer stream-id counter."""
function reset_rng_id_counter!(value::Integer=0)
    _GLOBAL_RNG_ID_COUNTER[] = UInt64(value)
    return _GLOBAL_RNG_ID_COUNTER[]
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
