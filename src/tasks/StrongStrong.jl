# Strong-strong task and solver entry point.
# Keep this file as the public include target; implementation details live in
# focused files under src/tasks/strongstrong/.

include("strongstrong/interface.jl")
include("strongstrong/slicing.jl")
include("strongstrong/gaussian.jl")
include("strongstrong/spectral.jl")
include("strongstrong/pic_cpu.jl")
include("strongstrong/pic_cpu_sliced.jl")
include("strongstrong/spectral_sliced.jl")
include("strongstrong/gaussian_pic.jl")
include("strongstrong/pic_cuda.jl")
include("strongstrong/gaussian_pic_cuda.jl")
include("strongstrong/spectral_cuda.jl")
