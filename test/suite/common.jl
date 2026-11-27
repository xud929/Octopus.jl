# ---------------------------------------------------------------------------
# What every suite file may reach for (docs/design/testing_lanes.md, section 1).
#
# The suite is `test/runtests.jl` (the driver: the lanes, `only=`, the layout
# tripwire, the include list, the accounting banner) plus the files of this
# directory, included in the order `_SUITE_FILES` states. Every file is
# self-contained but for this one: the driver's tripwire fails a file that
# reaches for a helper another file defines, so that
# `Pkg.test(test_args=["only=<file>"])` runs a file in the state the full lane
# gives it. A helper two files need lives here and nowhere else; a helper one
# file needs lives in that file. `test/move_testsets.jl` moves either.
# ---------------------------------------------------------------------------

# The suite's files in include order. `core.jl` holds the structural sweeps
# every lane and every `only=` run executes (they test the tree, not a
# feature); each file after it is an area, selectable alone through
# `only=<name>` (the basename without `.jl`); `legacy.jl` is the body of the
# single-file suite as it stood on 2026-11-27, in its original order,
# regrouped into area files one peel at a time. The driver's tripwire holds
# this list equal to the directory's contents.
const _SUITE_FILES = ["core.jl", "legacy.jl", "artifact_observers.jl"]
_suite_dir() = joinpath(pkgdir(Octopus), "test", "suite")
# Every file of the suite by its package path -- the driver, this file, then
# `_SUITE_FILES` in order -- and the suite's text as one vector of lines: what
# the pins that audit the suite's own text read (the stage 6 pin tripwire
# `_st6_pin_lines`, the GPU-only block count, the seed-copy check, the
# declared-classes pin, the wrapper-walk pin). By package path, not
# `@__FILE__`, so an extract of such a testset still audits the suite.
_suite_files_all() = vcat(joinpath(pkgdir(Octopus), "test", "runtests.jl"),
                          joinpath(_suite_dir(), "common.jl"),
                          [joinpath(_suite_dir(), f) for f in _SUITE_FILES])
_suite_lines() = reduce(vcat, (readlines(f) for f in _suite_files_all()))
_suite_text() = join(_suite_lines(), "\n")

# Whether the CUDA half of this suite ran at all must be visible in the summary,
# not inferable only by noticing that some testsets printed fewer assertions.
#
# More than twenty testsets are gated behind `_HAS_CUDA && CUDA.functional()`
# (the 2026-08-05 audit counted 24+ in the back half alone and replaced the
# three `else @test true` green-lies with honest skips; gated sets without an
# else still vanish silently — prefer `else @test_skip` in new ones). CI
# (`.github/workflows/ci.yml`) runs on
# `ubuntu-latest` with no GPU, so on CI **every** CUDA test is skipped while the
# run still reports "Testing Octopus tests passed".
#
# That matters more than it looks. The correctness argument for `pic_cuda.jl`
# rests almost entirely on CPU/CUDA parity: the CPU side is independently
# verified (hand-derived kernels, analytic references), the CUDA plane layout has
# no CPU counterpart to be verified against, and the measured parity residual is
# ~1e-15 against a ~1e-5 signal for any plane-level error. Take the parity tests
# away and that argument evaporates -- silently. `AGENTS.md` states the rule for
# contracts ("do not report an unrun check as passed"); this is the same rule for
# the suite.
#
# Ordering caveat (2026-08-05 audit, U17-7): this file aborts at the first
# failing testset, and the tightest physics backstops -- the symplecticity
# validation, the 8% high-energy weak-strong limit, the Yokoya coherent-mode
# contract with its executed negative control -- run at the very END, after
# the whole CUDA block. An abort anywhere earlier silently drops the only
# tests with real discriminating power on absolute beam-beam physics, so a
# red run's summary says nothing about them: fix the first failure and rerun
# before drawing any physics conclusion from what did pass.
const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
