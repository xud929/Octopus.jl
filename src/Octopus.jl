module Octopus

using LinearAlgebra
using Random
using JLD2
using HDF5
using FFTW
using NVTX

export AbstractExecutionBackend, CPUThreadsBackend, CUDABackend,
       AbstractPhaseRep, track!

abstract type AbstractExecutionBackend end
struct CPUThreadsBackend <: AbstractExecutionBackend end
struct CUDABackend <: AbstractExecutionBackend end

abstract type AbstractPhaseRep end

function track! end

# Include order is the dependency order. Keep this file as the only module
# boundary; source files should not create Octopus submodules.

# Architecture and metadata.
include("knowledge/Knowledge.jl")
include("knowledge/Methods.jl")

# Shared constants and math helpers.
include("constants/Constants.jl")
include("math/SpecialMath.jl")
include("math/counter_rng.jl")

# AST-based knob control: deferred parameter expressions resolved by
# compile_runtime. See docs/knob_control.md.
include("knobs/Knobs.jl")
include("knobs/symbolic.jl")

# Policies, validation, analysis, and example descriptors.
include("policies/Policies.jl")
include("contracts/Contracts.jl")
include("analysis/Analysis.jl")
include("examples/Examples.jl")

# Generic tracking interface.
include("track/Track.jl")

# Element specs, runtime maps, and element-local tracking implementations.
include("elements/Elements.jl")

# Particle/beam representations and backend tracking kernels.
include("beam/Beam.jl")

# The aperture is an element, but it is the only one that owns beam-scale
# storage: its loss record is sized by particle count and allocated on the
# beam's backend. So it loads after `Beam.jl` rather than with the other
# elements, which need nothing beyond the spec layer.
include("elements/aperture.jl")

include("track/phase6d_track.jl")
include("track/radiation_track.jl")
include("track/strong_beam_track.jl")

# Workflow composition, schedules, observers, and actions.
include("tasks/Tasks.jl")
include("tasks/BeamObservers.jl")
include("tasks/StrongStrong.jl")

# Generated registry/introspection helpers. Keep this last.
include("registry/Registry.jl")

end # module Octopus
