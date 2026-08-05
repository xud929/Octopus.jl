# Package extension supplying Octopus's ForwardDiff derivative rules when the
# user loads ForwardDiff next to Octopus — the dual-number twin of
# OctopusSymbolicsExt, added for audit open-queue item U7-1 (the elliptical
# Bassetti-Erskine kick was un-differentiable). The rules themselves live in
# OctopusForwardDiffRules.jl, shared verbatim with the script-mode activation
# in src/Octopus.jl. Method definitions (unlike Ref mutations) survive
# precompilation, so no __init__ indirection is needed here.
module OctopusForwardDiffExt

using Octopus
using ForwardDiff

include(joinpath(@__DIR__, "OctopusForwardDiffRules.jl"))

end
