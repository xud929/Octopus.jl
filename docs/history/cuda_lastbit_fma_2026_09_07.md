# The CUDA last-bit divergence was FMA contraction — 2026-09-07

Two entries on the wobble ledger
([`docs/todo.md`](../todo.md), "Spectral rms CPU/CUDA lane-fold 1-ulp
counterexample") are closed by one line of arithmetic. Member 3, "CUDA in-suite
vs standalone last-bit divergence", carried twelve numbered observations and its
own investigation row. Member 1, the spectral `_masked_rms` counterexample, was
its first sighting. Both were the same thing, and it is not what the ledger
modelled.

## The measurement

The pinned `Random.Xoshiro(29)` 30,000-point vector, masked arm, on this box
(RTX 4500 Ada, CUDA 6.3.1, driver 13.3.0):

| | sigma |
|---|---|
| Octopus CPU (`_live_z_stats`) | `0.007009746250353312` |
| Octopus CUDA (`_cuda_live_z_stats`) | `0.007009746250353311` |
| host emulation of the lane fold, `acc + d*d` | `0.007009746250353312` |
| host emulation of the lane fold, `fma(d, d, acc)` | `0.007009746250353311` |

The emulations reproduce each backend EXACTLY. That is the whole mechanism: the
device contracts, the host did not.

Confirmed independently in the kernel's own PTX. `_cuda_lane_z_moment_kernel!`
at `Val(2)` compiles to **one `fma.rn.f64`, zero `mul.f64`, zero `add.f64`** —
the NVPTX backend fuses `acc += (zi - μ) * (zi - μ)` into a single
multiply-add, rounding once. Julia's host codegen does not contract, so the CPU
rounded twice. On inputs whose product sits on a rounding boundary the two
answers differ by 1 ulp.

## Why the mean never moved — the ledger's own sharpest clue, explained

`Val(1)` accumulates `acc += zi`: a bare add, no multiply, nothing to contract.
Its lane sums are uniquely determined under any legal compilation, which is why
`n_live`, `zmin`, `zmax` and `mean` were bitwise equal through every one of the
twelve observations while sigma alone moved. `Val(2)` is the only contractible
multiply-add on the whole statistic path.

The same reasoning covers the rest of the family: the centroid pin goes through
`_cuda_lane_indexed_sum_kernel!`, whose body is `acc += z[idx[k]]` — pure adds —
and it has never moved.

## The correction: there was never an in-suite/standalone divergence

The ledger's model was "the CUDA masked-sigma arithmetic in-suite differs from
standalone", resting on observation 11's claim that the same vector "is verified
bitwise equal on both backends standalone under `--check-bounds`". Measured
today, that is false:

- standalone, no `--check-bounds`: CPU `…312`, CUDA `…311`
- standalone, `--check-bounds=yes` (what `Pkg.test` uses): CPU `…312`, CUDA `…311`
- in-suite (the gate's discriminator): CPU `…312`, CUDA `…311`

and the 4096 lane partials are **byte-identical** between the two process
contexts. The CPU/GPU difference is present in every context; there is no
process-state effect to explain. The discriminator's own output was always
consistent with this — `recompute_matches_first_gpu = true` (the GPU value is
stable) and `recompute_matches_cpu = false` (it differs from the CPU) say
exactly "the GPU always contracts, the CPU never did".

What made it look context-dependent was a standalone check that did not
reproduce what the suite compared. Recorded rather than quietly dropped,
because three of the row's twelve observations were spent on a distinction that
was not there.

A second datum, free from the Manifest re-resolve the same day: the values are
unchanged across CUDA 6.2.1 → 6.3.1, CUDA_Runtime_jll 0.23.0 → 0.24.4 and
CUDA_Driver_jll 13.3.0 → 13.3.4. The contraction is not a quirk of one toolchain
version.

## The fix

`_lane_z_moment`'s `Val(2)` branch (`src/tasks/strongstrong/slicing.jl`) now
accumulates with `fma`:

```julia
if POW == 2
    d = z[i] - μ
    acc[lane] = fma(d, d, acc[lane])
else
    acc[lane] += z[i]
end
```

`POW` is a compile-time `Val`, so the branch costs nothing at runtime. The
direction — make the host contract, rather than stop the device — is the one
this repository already took for `_shifted_second_moment` and
`_shifted_cross_moment`, which are pinned to `fma` for the same reason; it is
also the more accurate of the two, since `fma` rounds once.

**One fix, two members.** `_masked_rms` (`spectral.jl`) calls the same
`_lane_z_moment(..., Val(2))`, so the spectral counterexample is closed by the
same line. That is why member 1's single failure was on the *unmasked* arm and
member 3's on the *masked* one: the arm never mattered, the `Val(2)` did.

## Verification

- CPU and CUDA sigma now agree bitwise on the pinned vector: both
  `0.007009746250353311`.
- The sigma assert is restored from the `<= 1 ulp` bound (owner decision
  2026-08-19, taken because the mechanism was unknown) to `sc.sigma ==
  sg.sigma`. The reason for the relaxation is gone.
- Full gate at CI settings, CUDA active: 215 testsets, 0 failed, 0 errored,
  zero lane skips. **The discriminator fired zero times**, where it had fired in
  every preceding gate — the in-suite comparison is now bitwise too.
- No pinned digest moved. The blast radius was real to check (sigma feeds slice
  boundaries, and `_masked_rms` sizes the spectral Dirichlet box every spectral
  kick is solved on) and turned out to be contained.

## What stays open — member 2, with its standing hypothesis killed

Member 2, the Gaussian-PIC A/B coin, is a different phenomenon and is NOT closed
by this. Contraction cannot produce it: a contraction decision is fixed for a
compiled kernel, not drawn per call, while member 2's signature is two
bit-identical profiles alternating between two calls WITHIN one process.

**The cuFFT plan-eviction account is impossible in this stack.** The row
proposed "a CUFFT-class handle (plan) evicted and recreated between the paired
calls picks the other of two algorithms", resting on CUDA.jl freeing cached
handles under memory pressure. cuFFT does hold a handle cache
(`cuFFT/…/src/wrappers.jl:138`, `const idle_handles = HandleCache{…}`), but it
**never registers it as reclaimable**: `grep -rn register_reclaimable
cuFFT/*/src/` is empty, while cuBLAS registers three caches
(`cuBLAS.jl:317-319`). `purge!` is reachable only through that registry, so
CUDA.jl's reclaim path cannot evict a cuFFT plan. A hypothesis that stood since
2026-08-19 is refuted by a grep.

**What the deposit actually does, measured.** The charge deposit is
`CUDA.@atomic charge[ix, iy, plane] += wx1 * wy1` (`pic_cuda.jl`) — a FLOAT
atomic add, and float addition is not associative, so the order concurrent
threads land in changes the last bits. Probed directly: 64 particles onto a
16×16 grid, 200 repetitions per geometry, one quiet process.

| launch geometry | distinct charge arrays over 200 reps |
|---|---|
| threads=32, **blocks=2** | **4** |
| threads=64, blocks=1 | 1 |
| threads=128, blocks=1 | 1 |
| threads=256, blocks=1 | 1 |
| threads=512, blocks=1 | 1 |

The four single-block geometries all produce the SAME array. So **within one
block the atomic ordering is repeatable; across blocks it is not**, because
block scheduling order varies between launches. A separate 2000-repetition run
at blocks=1 produced exactly one profile — which is why standalone probes came
back 20/20 bit-exact and the coin read as "frozen" outside the suite.

**The link to suite state, and what is still inference.** `_cuda_pic_threads`
returns a fixed 256 unless a task scope installs a `ResolvedCUDAPICLaunchConfig`
(`interface.jl:306-314`, installed at `:255`). The same deposit can therefore
run in one block outside a task and in several inside one — deterministic in the
first case, not in the second. That accounts for every feature the ledger
recorded: two states, each bit-identical across processes (an ordering, once
realised, is a deterministic function of that schedule), standalone stability,
and in-suite straddling.

READ vs INFERRED, kept apart: the atomic add, the geometry dependence and the
scope-dependent thread count are measured or quoted. That the specific
Gaussian-PIC fallback testset's contended cell actually spans more than one
block is NOT yet established. It is the one remaining step and it is a single
receipt away — `:cuda_pic_launch` already records the family and thread count.

### CORRECTION, same day: the lever is ALLOCATION LAYOUT, not block count

The paragraph above reasoned that the deposit "can run in one block outside a
task and in several inside one". That is wrong for this testset, and it is
corrected here rather than edited away.

The deposit launches `blocks = cld(length(x), deposit_threads)` (`pic_cuda.jl`),
and the failing route has 64 particles with `deposit_threads = 256`, so
`blocks = 1` — the geometry I had measured as deterministic. Block count cannot
be the lever here.

Measured at the REAL geometry instead (64 particles, `threads=256`, `blocks=1`),
varying only the CUDA memory-pool state between deposits — 400 deposits across
ten pool states:

| distinct charge arrays | occurrences |
|---|---|
| `2573bba8615ac3eb` | 242 |
| `77b494327a74b6f7` | 158 |

**Exactly two.** Same launch shape, same input, different allocation layout,
two bit-identical profiles each drawn a large fraction of the time. That is the
ledger's signature reproduced on demand in one quiet process: "exactly TWO
reproducible py-noise profiles exist for this route, and EACH collide call draws
one of them".

So the mechanism is: the deposit's atomic ordering depends on where its arrays
land, and the pool's layout differs between a quiet standalone process (same
addresses every run — hence 20 of 20 bit-exact, the coin looking "frozen") and a
late-suite process whose pool has grown and fragmented (addresses differ between
the paired PIC and Gaussian-PIC calls — hence straddling).

This also vindicates the testset's OWN original attribution, which the ledger
later talked itself out of. `test/runtests.jl` says the wobble is "the recorded
CUDA atomic-deposition nondeterminism, entering here through
allocation-layout-dependent scheduling". That was right. Observation 7's "refined
model" of a cuFFT plan handle evicted under memory pressure was the wrong turn —
and it is not merely unsupported but impossible, since cuFFT never registers its
handle cache as reclaimable.

Both the block-count framing and the plan-cache framing are recorded here beside
the measurement that replaced them, because the useful part of this row has
always been its wrong turns.

**Is it a defect? No.** Nondeterministic ordering is inherent to float atomic
deposition; the alternative is per-block partials and an ordered reduction,
which changes every PIC result to buy a reproducibility the physics does not
need. The owner's existing response — an atol derived from the measured wobble
norm, with the capture trap armed — is the right one. What changes is that the
tolerance now has a REASON rather than an empirical bound, and the row stops
waiting on a mechanism that cannot happen.

The family split the ledger already suspected turns out to be right, and now has
a reason: member 2 varies within a process because block scheduling does;
members 1 and 3 never varied within a process because compilation does not.
