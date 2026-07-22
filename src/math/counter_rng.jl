export RNG_PHILOX, RNG_SPLITMIX,
       set_global_rng!, global_rng_seed, global_rng_method, global_rng_method_code,
       next_rng_id!, reset_rng_id_counter!,
       octopus_uint64, octopus_uniform01, octopus_normal_pair, octopus_normal,
       counter_philox4x32, counter_uint64, counter_uniform01,
       counter_normal_pair, counter_normal,
       splitmix_uint64, splitmix_uniform01, splitmix_normal_pair, splitmix_normal

const RNG_PHILOX = UInt8(1)
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
const _GLOBAL_RNG_ID_COUNTER = Ref{UInt64}(0)

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
    _GLOBAL_RNG_ID_COUNTER[] += UInt64(1)
    return _GLOBAL_RNG_ID_COUNTER[]
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
        return counter_uint64(seed, turn, rng_id, particle_index, component)
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

    key = _counter_rng_splitmix64(UInt64(seed)) ⊻
          _counter_rng_splitmix64(UInt64(rng_id) + 0x9e3779b97f4a7c15) ⊻
          _counter_rng_splitmix64(UInt64(component) + 0xbf58476d1ce4e5b9)
    k0 = _counter_rng_low32(key)
    k1 = _counter_rng_high32(key)

    for _ in 1:PHILOX4X32_ROUNDS
        c0, c1, c2, c3 = _philox4x32_round(c0, c1, c2, c3, k0, k1)
        k0 += PHILOX4X32_W0
        k1 += PHILOX4X32_W1
    end
    return c0, c1, c2, c3
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
