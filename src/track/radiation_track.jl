if _HAS_CUDA
	@eval begin
		# The asymmetry that routes a stochastic radiation element on CUDA: TRUE
		# in the contextless form, so the contextless policy `track!`
		# (src/track/phase6d_track.jl) builds a `TrackingContext` once and
		# advances its turn -- the counter RNG is keyed on the turn, and a
		# context built per launch replayed one draw for the whole run
		# (2026-08-05_b audit); FALSE with a context, so the element FUSES into
		# the one tracking kernel, whose `fusedTrack(ctx, elems, index_offset +
		# index, ...)` reaches the same `_track_lumped_rad_context` the CPU
		# route calls. A `Damping6DMap` element draws nothing and fuses in both
		# forms.
		#
		# Until 2026-10-22 this file also held a third copy of the grid-stride
		# loop, `cuda_track_lumped_rad_kernel!`, behind the deprecated
		# single-element `track!(rep, ::LumpedRad, turns, CUDABackend)` and a
		# policy twin recording `:cuda_radiation_compatibility_launch`: its own
		# context with no `index_offset`, and a hand-spelled
		# `min(cld(N, threads), 256)` block rule (2026-10-18 audit, F-104). Both
		# are gone. The deprecated entry now takes the one deprecated route of
		# phase6d_track.jl -- measured bitwise equal to the removed kernel on
		# 4096 particles over 3 turns (fix batch 4b, unit TR) -- and the suite
		# pins the symbol absent.
		_requires_cuda_elementwise(elem::LumpedRad) =
			elem.method isa Radiation6DMap || elem.method isa Diffusion6DMap
		_requires_cuda_elementwise(elem::LumpedRad, ctx::TrackingContext) = false
	end
end
