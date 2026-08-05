# U26 probe 2: current_runtime.md + public_api.md residual claims
const REPO = "/cfs/ad/dxu/Library/Julia/Octopus"
include(joinpath(REPO, "src", "Octopus.jl"))
using .Octopus
const O = Octopus

exported = Set(string.(names(Octopus)))
function report(name)
    s = String(name); sym = Symbol(s)
    isdef = isdefined(O, sym)
    hasdoc = false
    if isdef
        try
            d = string(Base.Docs.doc(Base.Docs.Binding(O, sym)))
            hasdoc = !occursin("No documentation found", d)
        catch; end
    end
    println(rpad(s, 40), " defined=", rpad(string(isdef),5),
            " exported=", rpad(string(s in exported),5), " hasdoc=", hasdoc)
end

println("=== public_api symbols missed by probe1 regex ===")
for n in ("summarize_registry","build_registry","element_help","parameter_schema",
          "example_spec","construction_help","supported_tracking_methods",
          "write_registry_snapshot","validate_element_metadata","element_help",
          "collide!","track!","fusedTrack","physics_keywords","readings","BPMObserver",
          "PlaceholderPolicy","PlaceholderAnalysis","ThinRFCavitySpec","RBendSpec",
          "SolenoidSpec","PatchSpec","BeamLine","PTCConsistencyContract",
          "ElementParameterEffectivenessContract","SolverOptionEffectivenessContract",
          "MarkerSpec","reference_beta_gamma","convert_longitudinal","rf_strength",
          "Symplectic6DMap","NonSymplectic6DMap","Radiation6DMap","Damping6DMap",
          "Diffusion6DMap","CPUThreadsBackend","CUDABackend","GPUExecutionPolicy",
          "Linear6DSpec","Linear6D","LumpedRad","ChromaticityKickSpec","BeamParams",
          "total_length","s_positions","LorentzBoostSpec","RevLorentzBoostSpec",
          "gaussian_beambeam_kick","UnsafeVirtualDrift","collision_pair_batches",
          "loss_summary","ApertureSpec","ThinCrabCavitySpec")
    report(n)
end

println()
println("=== current_runtime.md structural claims ===")
println("TrackingContext isbits? ", isbitstype(O.TrackingContext))
println("TrackingContext fields: ", [(n, fieldtype(O.TrackingContext, n)) for n in fieldnames(O.TrackingContext)])
println("Phase6DRep fields: ", fieldnames(O.Phase6DRep))

# Lorentz boost tracking method
for T in (:LorentzBoostSpec, :RevLorentzBoostSpec)
    try
        f = getfield(O, T)
        sp = f(0.0125)
        println(T, " tracking_method = ", O.tracking_method(sp))
    catch e
        println(T, " ERR ", sprint(showerror, e))
    end
end

# PIC solver defaults quoted by current_runtime.md
p = O.PICPoissonSolver()
for f in (:green_cache, :batch_mode, :cuda_indexed_wavefront, :cuda_wavefront_fft,
          :cuda_batch_fft, :cuda_async, :longitudinal_kick, :deposit_method,
          :field_derivative, :green_type, :slice_pair_green_min_ratio,
          :slice_pair_green_growth, :luminosity_deposit_method, :luminosity_grid,
          :interaction_grid, :slice_interpolation, :grid_extent)
    if hasfield(typeof(p), f)
        println("PICPoissonSolver.", rpad(String(f), 28), " = ", getfield(p, f))
    else
        println("PICPoissonSolver.", rpad(String(f), 28), " = <NO SUCH FIELD>")
    end
end
g = O.GaussianPoissonSolver()
for f in (:batch_mode, :include_sigma_xy)
    println("GaussianPoissonSolver.", rpad(String(f), 22), " = ",
            hasfield(typeof(g), f) ? getfield(g, f) : "<NO SUCH FIELD>")
end
s = O.SpectralPoissonSolver()
for f in (:method, :longitudinal_kick, :grid)
    println("SpectralPoissonSolver.", rpad(String(f), 22), " = ",
            hasfield(typeof(s), f) ? getfield(s, f) : "<NO SUCH FIELD>")
end
println("CUDAExecutionPolicy default launch: ", O.CUDAExecutionPolicy().launch)
println("CPUThreadsExecutionPolicy default: ", O.CPUThreadsExecutionPolicy())

# registry: does thin_rf_cavity appear?
snap = read(joinpath(REPO, "docs", "registry_snapshot.md"), String)
for k in ("thin_rf_cavity", "solenoid", "beam_line", "patch", "aperture", "rbend")
    println("registry_snapshot mentions ", rpad(k, 16), " => ", occursin(k, snap))
end
