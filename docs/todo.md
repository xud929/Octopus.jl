# TODO

## Soft-Gaussian Solver Follow-Up

- Profile the soft-Gaussian strong-strong solver on CPU and CUDA.
  - Measure isolated `collide!` timing and full `examples/strong_strong_tracking.jl`
    timing.
  - Separate solver time from task bookkeeping, diagnostics, luminosity output,
    slicing, and host-device synchronization.
  - Compare `batch_mode=:wavefront` and `batch_mode=:sequential`.
  - Compare `include_sigma_xy=false` and `include_sigma_xy=true`.

- Improve soft-Gaussian performance without degrading CPU or CUDA accuracy.
  - Use the profiling results to identify the real hot path before editing.
  - Preserve weak-strong consistency, virtual-drift behavior, longitudinal kick
    behavior, and CPU/CUDA parity.
  - Re-run solver-level and full-tracking benchmarks after each material change.

- Implement a finite-difference symplecticity validation for all elements that
  support `Symplectic6DMap`.
  - Cover `Linear6D`, `CrabDispersion`, `MomentumDispersion`, `XYCoupling`,
    `LorentzBoost`, `RevLorentzBoost`, `ThinCrabCavity`,
    `ChromaticityKick`, `ThinStrongBeam`, and `GaussianStrongBeam`.
  - Report the infinity norm of `J' * S * J - S`.
  - Keep stochastic or non-symplectic radiation maps out of this check.
  - Add a reusable validation script and focused tests.

- Add the high-energy weak-strong limiting-case validation.
  - Set the electron energy to an effectively infinite value, for example
    `1.0e100` GeV, while keeping the proton beam finite.
  - Compare PIC and soft-Gaussian strong-strong results against the weak-strong
    reference.
  - Check luminosity history and final centered beam sizes, not only coordinate
    deltas.
  - Document expected PIC versus soft-Gaussian differences from grid and
    Gaussian-slice modeling.

- Update examples and notebooks.
  - Update `examples/strong_strong_tracking.jl` with a documented high-energy
    weak-strong limit mode.
  - Update the strong-strong notebook to expose current Gaussian options:
    `virtual_drift`, `include_sigma_xy`, `longitudinal_kick`, and
    `batch_mode`.
  - Remove old `dynamic_drift_flag` references from CUDA tracking notebooks and
    replace them with the current `virtual_drift` interface.

- Review source and documentation consistency.
  - Confirm `docs/beam_beam_longitudinal_kick.md` matches the current
    weak-strong and soft-Gaussian implementations.
  - Confirm the `include_sigma_xy` documentation matches the source behavior,
    including the longitudinal derivative of the rotated covariance.
  - Make the longitudinal-kick note discoverable from the main entry points:
    `README.md`, `docs/current_runtime.md`, `docs/public_api.md`, and relevant
    notebook/example text.
