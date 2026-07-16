# Strong-strong task and solver entry point.
# Keep this file as the public include target; implementation details live in
# focused files under src/tasks/strongstrong/.

include("strongstrong/interface.jl")
include("strongstrong/slicing.jl")
include("strongstrong/gaussian.jl")
include("strongstrong/pic_cpu.jl")
include("strongstrong/pic_cuda.jl")
