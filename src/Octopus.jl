module Octopus

using LinearAlgebra
using Random
using JLD2
using HDF5
using FFTW
using NVTX

export AbstractExecutionBackend, CPUThreadsBackend, CUDABackend,
       AbstractPhaseRep, track!

"""
Root of the execution-backend TAG types. A backend tag names WHERE compute
runs and dispatches the kernel implementations; the policy types in
`src/policies/` say HOW (threads, launch shapes, devices).
"""
abstract type AbstractExecutionBackend end
"""CPU tag: multithreaded kernels over the Julia thread pool."""
struct CPUThreadsBackend <: AbstractExecutionBackend end
"""CUDA tag: device kernels; requires CUDA.jl and a functional device."""
struct CUDABackend <: AbstractExecutionBackend end

"""
Root of phase-space representations. `Phase6DRep` is the current concrete
one; runtime representations are implementation details (AGENTS.md) and may
change.
"""
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
# Longitudinal conventions and the exact conversions between them (theory note
# Section 2). Before the elements, because a map may be written in whichever
# pair makes it simplest and conjugated back into the tracking one.
include("track/longitudinal.jl")

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
include("tasks/BPMObserver.jl")
include("tasks/StrongStrong.jl")

# Generated registry/introspection helpers. Keep this last.
include("registry/Registry.jl")

# Script mode: a module built by `include("src/Octopus.jl")` never triggers
# the package-extension loader, so the ForwardDiff derivative rules (the
# OctopusForwardDiffExt weakdep extension, audit U7-1) are included here when
# ForwardDiff is importable from the active project — the same arrangement as
# the Symbolics adapter (src/knobs/symbolic.jl). Both routes include one
# shared rules file, so neither can drift from the other. In package mode
# this `import` throws (ForwardDiff is a weak, not strong, dependency) and
# the extension takes over.
const _HAS_FORWARDDIFF_SCRIPT_MODE = try
    @eval import ForwardDiff
    true
catch
    false
end
_HAS_FORWARDDIFF_SCRIPT_MODE && include("../ext/OctopusForwardDiffRules.jl")

end # module Octopus
