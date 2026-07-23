# TODO

## Open

- None. The Lorentz crossing maps are now documented and validated as
  Hirata quasi-symplectic coordinate transformations. A future canonical
  reformulation would be a separate physics feature, not a bug fix.

## Completed

- Soft-Gaussian profiling and CUDA wavefront optimization.
- Finite-difference symplecticity validation script and tests.
- High-energy weak-strong limiting-case validation.
- Strong-strong example high-energy mode.
- Notebook updates for `virtual_drift`, `include_sigma_xy`,
  `longitudinal_kick`, and `batch_mode`.
- Entry-point documentation links to the longitudinal-kick note and new
  validations.
- Lorentz/reverse-Lorentz review: the implementation is an exact inverse pair;
  finite-difference validation checks determinants `sec(theta)^3` and
  `cos(theta)^3` rather than incorrectly requiring standalone canonical
  symplecticity. The reference is Hirata et al., Phys. Rev. Lett. 74, 2228
  (1995), which calls the map quasisymplectic and gives the same Jacobian.
