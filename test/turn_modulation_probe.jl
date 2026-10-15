# The one-particle probe of docs/design/turn_modulation_record.md section 6.1
# (the owner's plan of 2026-10-15): a 3-harmonic thin crab cavity carrying a
# white or pink rule on ONE harmonic's phase and (independently drawn) on its
# strength, then on all three, tracked for 64 turns with a `MomentObserver`
# every turn and one particle at randomised `initial_offset`, each verification
# with its own seed. Three comparisons per verification:
#
#   1. recording on against recording off, same seed and rules: every moment
#      column bitwise, the `:turn_modulation` receipt identical;
#   2. the modulated run against the same line with every slot `nothing`: the
#      px and pz steps differ from turn 0, py bitwise equal;
#   3. the rows predicted from the RECORDED offsets and the recorded nominals,
#      formed exactly as `track_particle` forms the kick (`S0 (1 + d_n)`,
#      `phi0 + dphi_n`, the same operation order), against the observed rows:
#      bitwise (0 ulp) on CPU and MPI, within one state ulp plus 1e-14 of the
#      kick magnitude on CUDA (libdevice sin/cos, the FMA-contracted phase);
#      the recorded series bitwise equal to the hook's replay (plan 6.2).
#
# A separate file because THREE sides need it identically: the suite's testset
# "Turn modulation: the one-particle probe verifies the loop per harmonic" on
# CPU threads and CUDA, and the two-rank mpiexec child that testset launches,
# which runs THIS file as a script (the `main` guarded at the bottom, on the
# precedent of test/mpi_seam_check_fixture.jl: functions only, no top-level
# side effects, so the parent can `include` it inside the `@testset` body;
# nothing here is `const`, and no signature names an Octopus type, so the file
# loads before `using Octopus` does). Every name is `tm_probe_`-prefixed and
# every Octopus symbol is qualified. Phase A of the verification (the replay
# as the offsets' source, the run-twice form of comparison 1) ran from
# result/crab_noise/S1B/probe_schedule.jl, 24/24, 2026-10-15; the history
# record is docs/history/turn_modulation_record_2026_10_15.md.
import Random
import Printf

# --- the fixture -----------------------------------------------------------

tm_probe_frequency() = 197.0e6
tm_probe_nominal_sx() = (5.168e-4, -1.292e-4, 3.0e-5)   # three non-zero harmonics
tm_probe_nominal_sy() = (0.0, 0.0, 0.0)                  # zero: stays zero under d (the falsifier)
tm_probe_nominal_phase() = (0.0, 0.0, 0.0)
tm_probe_sigma_phase() = 1.0e-5          # rad
tm_probe_sigma_strength() = 1.0e-4       # the relative factor's rms
tm_probe_phase_id(i) = 100 + i           # explicit, distinct stream ids
tm_probe_strength_id(i) = 200 + i
tm_probe_turns() = 64
tm_probe_base_seed() = 0x5151202610150007
tm_probe_kinds() = (:white, :pink)

"""
    tm_probe_schedule(base_seed = tm_probe_base_seed()) -> Vector{NamedTuple}

H1, H2, H3 (one harmonic each), then ALL (three harmonics). Per verification
a fresh seed from the master stream and, from a `Xoshiro` seeded with it, the
six coordinates (x, y uniform in +-1 mm, px, py in +-1e-5, z in +-0.1 m, pz in
+-1e-3) and the rule kinds, drawn for the phase slot and independently for the
strength slot of every active harmonic. The default base seed was chosen so
the drawn kinds cover both rules on both slot types among H1-H3 and in ALL;
`tm_probe_coverage` states that and the testset requires it.
"""
function tm_probe_schedule(base_seed::Integer=tm_probe_base_seed())
    master = Random.Xoshiro(UInt64(base_seed))
    kinds = collect(tm_probe_kinds())
    function draw(label, harmonics)
        seed = rand(master, UInt64) >> 1
        rng = Random.Xoshiro(seed)
        u() = 2.0 * rand(rng) - 1.0
        coords = (u() * 1.0e-3, u() * 1.0e-5, u() * 1.0e-3, u() * 1.0e-5, u() * 0.1, u() * 1.0e-3)
        phase_kinds = [rand(rng, kinds) for _ in harmonics]
        strength_kinds = [rand(rng, kinds) for _ in harmonics]
        return (label=label, harmonics=harmonics, seed=seed, coords=coords,
                phase_kinds=phase_kinds, strength_kinds=strength_kinds)
    end
    return [draw("H1", [1]), draw("H2", [2]), draw("H3", [3]), draw("ALL", [1, 2, 3])]
end

"""Both kinds on a phase slot and on a strength slot among the single-harmonic
verifications, and both kinds in the final check."""
function tm_probe_coverage(schedule)
    both = Set(tm_probe_kinds())
    singles = filter(v -> length(v.harmonics) == 1, schedule)
    alls = filter(v -> length(v.harmonics) == 3, schedule)
    return (single_phase=Set(k for v in singles for k in v.phase_kinds) == both,
            single_strength=Set(k for v in singles for k in v.strength_kinds) == both,
            all_both=!isempty(alls) &&
                     Set(vcat((vcat(v.phase_kinds, v.strength_kinds) for v in alls)...)) == both)
end

tm_probe_rule(kind::Symbol, sigma, id) =
    kind === :white ? Octopus.WhiteNoise(sigma; rng_id=id) :
    kind === :pink ? Octopus.PinkNoise(sigma; rng_id=id) :
    error("tm_probe_rule: unknown kind $(kind)")

"""The cavity spec of a verification: `modulated=false` is the same line with
every slot `nothing` (comparison 2's reference)."""
function tm_probe_spec(v; modulated::Bool)
    at(i) = findfirst(==(i), v.harmonics)
    pn = ntuple(i -> (modulated && at(i) !== nothing) ?
                     tm_probe_rule(v.phase_kinds[at(i)], tm_probe_sigma_phase(), tm_probe_phase_id(i)) :
                     nothing, 3)
    sn = ntuple(i -> (modulated && at(i) !== nothing) ?
                     tm_probe_rule(v.strength_kinds[at(i)], tm_probe_sigma_strength(), tm_probe_strength_id(i)) :
                     nothing, 3)
    return Octopus.ThinCrabCavitySpec{3}(tm_probe_frequency();
                                         strengthX=tm_probe_nominal_sx(), strengthY=tm_probe_nominal_sy(),
                                         phase=tm_probe_nominal_phase(), phase_noise=pn, strength_noise=sn)
end

# --- one run ---------------------------------------------------------------

"""The particle's six coordinates read from the representation before the run
(exact; the 1e-40 emittance adds draws a few ulps below the offsets, so the
offsets themselves are not the state). Under the multi-process policy the rank
holding the particle contributes its coordinates and the empty rank zeros
(`x + 0.0 == x`, exact), through `Main.MPI`, which the child has loaded."""
function tm_probe_initial_state(beam, policy)
    arrays = Octopus.coordinate_arrays(beam.rep)
    nlocal = length(arrays[1])
    vals = [nlocal == 1 ? Float64(Array(a)[1]) : 0.0 for a in arrays]
    if policy isa Octopus.MultiProcessExecutionPolicy
        MPI = Main.MPI
        MPI.Allreduce!(vals, +, MPI.COMM_WORLD)
        counts = collect(MPI.Allgather([nlocal], MPI.COMM_WORLD))
        return ntuple(i -> vals[i], 6), nlocal, counts
    end
    return ntuple(i -> vals[i], 6), nlocal, [nlocal]
end

"""
    tm_probe_run(v, spec, policy, path; record) -> (init, nlocal, counts, receipt)

One `execute!` of the probe into `path`: the global seed set to the
verification's, the one-particle beam at the verification's offsets, the
cavity and a `MomentObserver` every turn, `RunArtifact(path; capacity=64,
record_turn_modulation=record)`, `tm_probe_turns()` turns under an execution
audit. `receipt` is the `:turn_modulation` receipt's values, `nothing` when the
run had none (the all-`nothing` line).
"""
function tm_probe_run(v, spec, policy, path; record::Bool)
    Octopus.set_global_rng!(seed=v.seed, method=:philox)
    beam = Octopus.Beam(1, policy, Float64;
        beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
        emit=(1.0e-40, 1.0e-40, 1.0e-40), cutoff=5.0, rng_id=1,
        charge=1.0, mc2=Octopus.PMASS_EV, E0=275.0e9, r0=Octopus.RE * Octopus.ME0 / Octopus.PMASS_EV,
        npart=1.0e11, zeta=(0.0, 0.0, 0.0, 0.0), eta=(0.0, 0.0, 0.0, 0.0), R=(0.0, 0.0, 0.0, 0.0),
        initial_offset=v.coords)
    init, nlocal, counts = tm_probe_initial_state(beam, policy)
    observer = Octopus.ScheduledObserver(Octopus.MomentObserver(; name="probe"),
                                         Octopus.EveryNSteps(start=0, step=1))
    task = Octopus.TrackingTask((spec, observer); policy=policy,
                                artifact=Octopus.RunArtifact(path; capacity=64, record_turn_modulation=record))
    audit = Octopus.with_execution_audit() do
        Octopus.execute!(task, beam; turns=tm_probe_turns())
    end
    receipts = filter(r -> r.consumer === :turn_modulation, Octopus.execution_receipts(audit))
    length(receipts) <= 1 || error("tm_probe_run: $(length(receipts)) :turn_modulation receipts")
    return (init=init, nlocal=nlocal, counts=counts,
            receipt=isempty(receipts) ? nothing : receipts[1].values)
end

"""The moment rows as plain vectors: turn, x, px, y, py, z, pz."""
function tm_probe_rows(path)
    m = read(Octopus.TaskOutput(path), :moments; name="probe")
    return (turn=collect(m.turn), x=collect(m.m100000), px=collect(m.m010000),
            y=collect(m.m001000), py=collect(m.m000100), z=collect(m.m000010),
            pz=collect(m.m000001))
end

tm_probe_columns_bitwise(a, b) =
    all(length(getfield(a, f)) == length(getfield(b, f)) &&
        all(getfield(a, f) .=== getfield(b, f)) for f in propertynames(a))
tm_probe_max_abs_gap(a, b) =
    maximum(maximum(abs.(getfield(a, f) .- getfield(b, f)); init=0.0) for f in propertynames(a))

# --- the offsets: the recorded series (comparison 3's source) ---------------

"""
    tm_probe_recorded(path; turns) -> NamedTuple

The recorded offsets of the one modulated element of `path`, read through the
public reader `turn_modulation_provenance`: `dphi` and `d` as `turns x 3`
matrices in harmonic order (an inactive harmonic, which the record does not
list, stays zero), `nominal` the slot groups' nominals, `labels` the active
slot labels in record order, and the window of the one ledger row
(`start_turn`, `turns`). `series_present` says whether every listed slot
carried a series (`false` is the record of a run with the option off) and
`same_as_read` that `read(TaskOutput(path), :turn_modulation)` returned the
same entries.
"""
function tm_probe_recorded(path; turns::Int=tm_probe_turns())
    prov = Octopus.turn_modulation_provenance(path)
    same = isempty(prov) || prov == read(Octopus.TaskOutput(path), :turn_modulation)
    ledger = read(Octopus.TaskOutput(path), :execution)
    dphi = zeros(turns, 3)
    d = zeros(turns, 3)
    labels = String[]
    nominal = Dict{String,Any}()
    present = true
    elements = 0
    if !isempty(prov)
        length(prov) == 1 || error("tm_probe_recorded: $(length(prov)) execution entries in $(path)")
        e = prov[1]
        elements = length(e.elements)
        elements == 1 || error("tm_probe_recorded: $(elements) modulated elements in $(path)")
        el = e.elements[1]
        el.element == "ThinCrabCavity" || error("tm_probe_recorded: element $(el.element)")
        for s in el.slots
            push!(labels, s.slot)
            nominal[s.slot] = s.nominal
            m = match(r"^(phase_noise|strength_noise)\[([123])\]$", s.slot)
            m === nothing && error("tm_probe_recorded: unexpected slot label $(s.slot)")
            if s.series === nothing
                present = false
                continue
            end
            length(s.series) == turns || error(
                "tm_probe_recorded: slot $(s.slot) carries $(length(s.series)) entries for $(turns) turns")
            (m[1] == "phase_noise" ? dphi : d)[:, parse(Int, m[2])] .= s.series
        end
    end
    return (dphi=dphi, d=d, labels=labels, nominal=nominal, series_present=present,
            elements=elements, same_as_read=same,
            start_turn=collect(ledger.start_turn), window_turns=collect(ledger.turns))
end

"""The hook's own replay of the offsets (`_turn_offset`, slot `i` for the phase
of harmonic `i`, `N + i` for its strength, the numbering `realize` hands it),
for the plan's 6.2 identity "the series equal to the hook's replay bitwise".
Not the source of the prediction: that is the record."""
function tm_probe_replay(spec, v; turns::Int=tm_probe_turns())
    pr = Octopus.param(spec, :phase_noise)
    sr = Octopus.param(spec, :strength_noise)
    dphi = zeros(turns, 3)
    d = zeros(turns, 3)
    for n in 0:turns-1
        ctx = Octopus.TrackingContext(turn=n, seed=v.seed, rng_method=:philox)
        for i in 1:3
            dphi[n + 1, i] = Octopus._turn_offset(pr[i], ctx, i, Float64)[1]
            d[n + 1, i] = Octopus._turn_offset(sr[i], ctx, 3 + i, Float64)[1]
        end
    end
    return (dphi=dphi, d=d)
end

"""The slot labels the record must list for `v`: the active harmonics' phase
and strength slots, phases first, as `_slot_rules` orders them."""
tm_probe_expected_labels(v) =
    vcat(["phase_noise[$(i)]" for i in v.harmonics], ["strength_noise[$(i)]" for i in v.harmonics])

# --- the prediction --------------------------------------------------------

"""The kick, formed exactly as `track_particle(::Symplectic6DMap, ::ThinCrabCavity, ...)`
forms it (same operation order, same accumulation) from the REALISED tuples;
also the per-turn magnitudes `sum_i |kick_i|` the CUDA pin is relative to."""
function tm_probe_kick(kcc, SX, SY, PH, x0, y0, z0)
    dpx = 0.0; dpy = 0.0; dpz = 0.0
    mag_px = 0.0; mag_pz = 0.0
    for i in 1:3
        ikcc = Float64(i) * kcc
        θ = ikcc * z0 + PH[i]
        s = sin(θ)
        c = cos(θ)
        sx = SX[i]
        sy = SY[i]
        dpx -= sx * s / ikcc
        dpy -= sy * s / ikcc
        dpz -= (sx * x0 + sy * y0) * c
        mag_px += abs(sx * s / ikcc)
        mag_pz += abs((sx * x0 + sy * y0) * c)
    end
    return dpx, dpy, dpz, mag_px, mag_pz
end

tm_probe_ulps(a::Float64, b::Float64) = a === b ? 0.0 : abs(a - b) / eps(max(abs(a), abs(b)))

"""
    tm_probe_predict(rows, init, nominal, dphi, d; turns) -> NamedTuple

Comparison 3 on one run's rows. `nominal` is `(kcc, strengthX, strengthY,
phase)` of the cavity the kick is formed from; `dphi`, `d` the offsets (zeros
for the all-`nothing` line). Each turn's predicted row is the PREVIOUS
OBSERVED row plus the kick (one rounding, as the kernel's `px0 + dpx`), so the
comparison is of one kick at a time: `px_ulp`/`pz_ulp` the largest gap in
ulps of the state, `px_excess`/`pz_excess` the largest gap beyond one state
ulp relative to `sum_i |kick_i|` (the CUDA pin's measure), `px_step_ulp`
the naive step-difference gap in ulps of the kick (dominated by the state's
rounding; information only), `chain_*` the free-running prediction's gap at
the last row. `py_const`: py bitwise equal to its initial value on every row.
"""
function tm_probe_predict(rows, init, nominal, dphi, d; turns::Int=tm_probe_turns())
    x0, px0, y0, py0, z0, pz0 = init
    px_ulp = pz_ulp = px_step_ulp = pz_step_ulp = px_excess = pz_excess = 0.0
    dpy_zero = true
    prev_px, prev_pz = px0, pz0
    chain_px, chain_pz = px0, pz0
    for n in 0:turns-1
        SX = ntuple(i -> nominal.strengthX[i] * (1.0 + d[n + 1, i]), 3)
        SY = ntuple(i -> nominal.strengthY[i] * (1.0 + d[n + 1, i]), 3)
        PH = ntuple(i -> nominal.phase[i] + dphi[n + 1, i], 3)
        dpx, dpy, dpz, mag_px, mag_pz = tm_probe_kick(nominal.kcc, SX, SY, PH, x0, y0, z0)
        dpy_zero &= dpy === 0.0
        pred_px = prev_px + dpx
        pred_pz = prev_pz + dpz
        obs_px = rows.px[n + 1]
        obs_pz = rows.pz[n + 1]
        px_ulp = max(px_ulp, tm_probe_ulps(obs_px, pred_px))
        pz_ulp = max(pz_ulp, tm_probe_ulps(obs_pz, pred_pz))
        px_step_ulp = max(px_step_ulp, tm_probe_ulps(obs_px - prev_px, dpx))
        pz_step_ulp = max(pz_step_ulp, tm_probe_ulps(obs_pz - prev_pz, dpz))
        px_excess = max(px_excess, max(0.0, abs(obs_px - pred_px) - eps(abs(obs_px))) / mag_px)
        pz_excess = max(pz_excess, max(0.0, abs(obs_pz - pred_pz) - eps(abs(obs_pz))) / mag_pz)
        prev_px, prev_pz = obs_px, obs_pz
        chain_px += dpx
        chain_pz += dpz
    end
    return (px_ulp=px_ulp, pz_ulp=pz_ulp, px_excess=px_excess, pz_excess=pz_excess,
            px_step_ulp=px_step_ulp, pz_step_ulp=pz_step_ulp,
            chain_px=abs(chain_px - rows.px[end]), chain_pz=abs(chain_pz - rows.pz[end]),
            py_const=all(rows.py .=== py0), dpy_zero=dpy_zero,
            xyz_const=all(rows.x .=== x0) && all(rows.y .=== y0) && all(rows.z .=== z0),
            turns_ok=rows.turn == collect(0:turns-1))
end

"""The backend's pin on a prediction: bitwise rows where the host arithmetic is
the kernel's (`exact`), the one-state-ulp-plus-1e-14-of-the-kick form on CUDA."""
tm_probe_within(p; exact::Bool) =
    exact ? (p.px_ulp == 0 && p.pz_ulp == 0) : (p.px_excess <= 1.0e-14 && p.pz_excess <= 1.0e-14)

"""The nominal the kick is formed from: the compiled cavity's own `kcc` and
tuples (the nominal element under the wrap), checked against the spec's."""
function tm_probe_nominal(spec)
    rt = Octopus.compile_runtime(spec)
    base = rt isa Octopus.TurnModulated ? rt.base : rt
    return (kcc=base.kcc, strengthX=base.strengthX, strengthY=base.strengthY, phase=base.phase)
end

# --- one verification ------------------------------------------------------

"""
    tm_probe_verify(v, policy, dir; exact, cpu_ref=nothing) -> NamedTuple

Runs A (`record_turn_modulation=true`), B (`false`) and N (every slot
`nothing`, recording on, which records nothing) into `dir`, then the three
comparisons; every verdict and number is a field, so the parent asserts each
and the child prints them. Under the multi-process policy only rank 0 holds
the artifact: the other ranks return `nothing` after the runs. `cpu_ref` names
a directory holding the CPU arm's artifacts of the same schedule; when given,
`ref_rows_bitwise` and `ref_series_bitwise` compare this backend's rows and
recorded series against them bitwise.
"""
function tm_probe_verify(v, policy, dir; exact::Bool, cpu_ref=nothing)
    turns = tm_probe_turns()
    spec_mod = tm_probe_spec(v; modulated=true)
    spec_nom = tm_probe_spec(v; modulated=false)
    p_a = joinpath(dir, "$(v.label)_mod_a.h5")
    p_b = joinpath(dir, "$(v.label)_mod_b.h5")
    p_n = joinpath(dir, "$(v.label)_nom.h5")
    ra = tm_probe_run(v, spec_mod, policy, p_a; record=true)
    rb = tm_probe_run(v, spec_mod, policy, p_b; record=false)
    rn = tm_probe_run(v, spec_nom, policy, p_n; record=true)
    holds_artifact = !(policy isa Octopus.MultiProcessExecutionPolicy) ||
                     Main.MPI.Comm_rank(Main.MPI.COMM_WORLD) == 0
    holds_artifact || return (label=v.label, counts=ra.counts, nlocal=ra.nlocal, root=false)
    same_start = ra.init == rb.init == rn.init
    init = ra.init
    rows_a = tm_probe_rows(p_a)
    rows_b = tm_probe_rows(p_b)
    rows_n = tm_probe_rows(p_n)
    nominal = tm_probe_nominal(spec_mod)
    nominal_plain = tm_probe_nominal(spec_nom)
    nominal_same = nominal == nominal_plain &&
                   nominal.strengthX == tm_probe_nominal_sx() && nominal.strengthY == tm_probe_nominal_sy() &&
                   nominal.phase == tm_probe_nominal_phase()

    # 1. recording on against off
    rec_a = tm_probe_recorded(p_a; turns=turns)
    rec_b = tm_probe_recorded(p_b; turns=turns)
    rec_n = tm_probe_recorded(p_n; turns=turns)
    c1 = (bitwise=tm_probe_columns_bitwise(rows_a, rows_b),
          max_abs=tm_probe_max_abs_gap(rows_a, rows_b),
          receipt_identical=ra.receipt !== nothing && ra.receipt == rb.receipt,
          series_on=rec_a.series_present && rec_a.labels == tm_probe_expected_labels(v),
          series_off=!rec_b.series_present && rec_b.labels == tm_probe_expected_labels(v) &&
                     all(==(0.0), rec_b.dphi) && all(==(0.0), rec_b.d),
          nothing_recorded_for_plain=rec_n.elements == 0 && rn.receipt === nothing)

    # 2. the modulated run against the all-`nothing` line
    steps(rows, col, p0) = diff(vcat(p0, getfield(rows, col)))
    px_diff = steps(rows_a, :px, init[2]) .!= steps(rows_n, :px, init[2])
    pz_diff = steps(rows_a, :pz, init[6]) .!= steps(rows_n, :pz, init[6])
    c2 = (px_all=all(px_diff), px_first=findfirst(px_diff), pz_all=all(pz_diff), pz_first=findfirst(pz_diff),
          py_equal=all(rows_a.py .=== rows_n.py),
          receipts=(ra.receipt === nothing ? 0 : 1, rb.receipt === nothing ? 0 : 1, rn.receipt === nothing ? 0 : 1),
          window_ok=ra.receipt !== nothing && ra.receipt.first_turn == 0 && ra.receipt.turns == turns)

    # 3. the prediction from the RECORD
    replay = tm_probe_replay(spec_mod, v; turns=turns)
    nominal_recorded = all(
        rec_a.nominal[l] == (phase=nominal.phase[i], strengthX=nominal.strengthX[i], strengthY=nominal.strengthY[i])
        for (l, i) in ((l, parse(Int, match(r"\[([123])\]", l)[1])) for l in rec_a.labels))
    pm = tm_probe_predict(rows_a, init, nominal, rec_a.dphi, rec_a.d; turns=turns)
    pn = tm_probe_predict(rows_n, init, nominal, zeros(turns, 3), zeros(turns, 3); turns=turns)
    active_nonzero = all(any(!=(0.0), rec_a.dphi[:, i]) && any(!=(0.0), rec_a.d[:, i]) for i in v.harmonics)
    inactive_zero = all(all(==(0.0), rec_a.dphi[:, i]) && all(==(0.0), rec_a.d[:, i])
                        for i in setdiff(1:3, v.harmonics))
    c3 = (series_eq_replay=rec_a.series_present &&
                           all(rec_a.dphi .=== replay.dphi) && all(rec_a.d .=== replay.d),
          same_as_read=rec_a.same_as_read, nominal_recorded=nominal_recorded,
          start_turn=rec_a.start_turn, window_turns=rec_a.window_turns,
          active_nonzero=active_nonzero, inactive_zero=inactive_zero,
          max_dphi=maximum(abs, rec_a.dphi), max_d=maximum(abs, rec_a.d),
          mod=pm, nom=pn, within=tm_probe_within(pm; exact=exact) && tm_probe_within(pn; exact=exact))

    ref = (rows_bitwise=nothing, rows_max_abs=nothing, series_bitwise=nothing)
    if cpu_ref !== nothing
        ref_a = tm_probe_rows(joinpath(cpu_ref, "$(v.label)_mod_a.h5"))
        ref_n = tm_probe_rows(joinpath(cpu_ref, "$(v.label)_nom.h5"))
        ref_rec = tm_probe_recorded(joinpath(cpu_ref, "$(v.label)_mod_a.h5"); turns=turns)
        ref = (rows_bitwise=tm_probe_columns_bitwise(rows_a, ref_a) && tm_probe_columns_bitwise(rows_n, ref_n),
               rows_max_abs=max(tm_probe_max_abs_gap(rows_a, ref_a), tm_probe_max_abs_gap(rows_n, ref_n)),
               series_bitwise=ref_rec.series_present && all(rec_a.dphi .=== ref_rec.dphi) && all(rec_a.d .=== ref_rec.d))
    end
    return (label=v.label, init=init, counts=ra.counts, nlocal=ra.nlocal, root=true,
            same_start=same_start, nominal_same=nominal_same, c1=c1, c2=c2, c3=c3, ref=ref, exact=exact)
end

"""Every verdict of one verification folded into one Bool: what the child's
DONE line reports and the parent asserts beside the per-field assertions."""
function tm_probe_pass(r)
    (r === nothing || !r.root) && return false
    c1 = r.c1.bitwise && r.c1.receipt_identical && r.c1.series_on && r.c1.series_off && r.c1.nothing_recorded_for_plain
    c2 = r.c2.px_all && r.c2.pz_all && r.c2.py_equal && r.c2.receipts == (1, 1, 0) && r.c2.window_ok
    c3 = r.c3.series_eq_replay && r.c3.same_as_read && r.c3.nominal_recorded &&
         r.c3.start_turn == [0] && r.c3.window_turns == [tm_probe_turns()] &&
         r.c3.active_nonzero && r.c3.inactive_zero && r.c3.within &&
         r.c3.mod.py_const && r.c3.mod.dpy_zero && r.c3.mod.xyz_const && r.c3.mod.turns_ok &&
         r.c3.nom.py_const && r.c3.nom.xyz_const && r.c3.nom.turns_ok
    # Against the CPU reference: the recorded series (host-side draws) bitwise
    # on every backend; the rows bitwise where the arithmetic is the same
    # (CPU, MPI), within the CPU/CUDA identity testset's 1e-17 absolute on CUDA.
    ref = r.ref.series_bitwise === nothing ||
          (r.ref.series_bitwise && (r.exact ? r.ref.rows_bitwise : r.ref.rows_max_abs <= 1.0e-17))
    return r.same_start && r.nominal_same && c1 && c2 && c3 && ref
end

"""One line per verification: harmonics, kinds, seed, coordinates, the three
verdicts with their numbers. Built whole and written once by the caller."""
function tm_probe_line(backend, v, r)
    f(x) = Printf.@sprintf("%.6e", x)
    u(x) = x == 0 ? "0" : Printf.@sprintf("%.3g", x)
    (r === nothing || !r.root) && return "TM-PROBE $(backend) $(v.label): no artifact on this rank"
    x0, px0, y0, py0, z0, pz0 = r.init
    pm, pn = r.c3.mod, r.c3.nom
    return string(
        "TM-PROBE backend=", backend, " label=", v.label, " harmonics=", v.harmonics,
        " phase=", v.phase_kinds, " strength=", v.strength_kinds,
        Printf.@sprintf(" seed=0x%016x", v.seed),
        " x0=", f(x0), " px0=", f(px0), " y0=", f(y0), " py0=", f(py0), " z0=", f(z0), " pz0=", f(pz0),
        " shards=", r.counts,
        " | C1 bitwise=", r.c1.bitwise, " max_abs=", f(r.c1.max_abs), " receipt_identical=", r.c1.receipt_identical,
        " series_on=", r.c1.series_on, " series_off=", r.c1.series_off,
        " | C2 px_all=", r.c2.px_all, " first=", r.c2.px_first === nothing ? "none" : string(r.c2.px_first - 1),
        " pz_all=", r.c2.pz_all, " py_equal=", r.c2.py_equal, " receipts=", r.c2.receipts,
        " | C3 series_eq_replay=", r.c3.series_eq_replay, " nominal_recorded=", r.c3.nominal_recorded,
        " start_turn=", r.c3.start_turn, " px_ulp=", u(pm.px_ulp), " pz_ulp=", u(pm.pz_ulp),
        " px_excess=", f(pm.px_excess), " pz_excess=", f(pm.pz_excess),
        " step_ulp(px,pz)=", u(pm.px_step_ulp), ",", u(pm.pz_step_ulp),
        " chain(px,pz)=", f(pm.chain_px), ",", f(pm.chain_pz),
        " py_const=", pm.py_const, " dpy_zero=", pm.dpy_zero, " xyz_const=", pm.xyz_const,
        " nominal(px_ulp,pz_ulp,px_excess)=", u(pn.px_ulp), ",", u(pn.pz_ulp), ",", f(pn.px_excess),
        " max|dphi|=", f(r.c3.max_dphi), " max|d|=", f(r.c3.max_d),
        " pin=", r.exact ? "bitwise" : "excess<=1e-14",
        r.ref.series_bitwise === nothing ? "" :
            string(" | vs-cpu rows_bitwise=", r.ref.rows_bitwise, " rows_max_abs=", f(r.ref.rows_max_abs),
                   " series_bitwise=", r.ref.series_bitwise),
        " | verdict=", tm_probe_pass(r) ? "PASS" : "FAIL")
end

# --- the mpiexec child -----------------------------------------------------

"""
    tm_probe_child_main()

The two-rank arm, run by the suite's testset as
`mpiexec -n 2 julia --startup-file=no --threads=2 test/turn_modulation_probe.jl`
with `OCTOPUS_TM_PROBE_DIR` (the directory for the artifacts and the per-rank
receipt files `rank_<r>.txt`, written per rank because the launcher's merged
stdout drops bytes under load: test/mpi_seam_check.jl, 2026-09-06) and
`OCTOPUS_TM_PROBE_CPU_REF` (the parent's CPU artifacts of the same schedule).
Rank 0 writes one `TM-PROBE` line per verification and the `TM-PROBE-DONE`
line; every rank writes its `TM-PROBE-SHARD` line. Exits non-zero on any
failure so a dying rank takes the launcher down rather than hanging a peer.
"""
function tm_probe_child_main()
    MPI = Main.MPI
    MPI.Initialized() || MPI.Init(threadlevel=:funneled)
    rank = MPI.Comm_rank(MPI.COMM_WORLD)
    nranks = MPI.Comm_size(MPI.COMM_WORLD)
    dir = get(ENV, "OCTOPUS_TM_PROBE_DIR", "")
    isempty(dir) && error("OCTOPUS_TM_PROBE_DIR must name the artifact and receipt directory")
    cpu_ref = get(ENV, "OCTOPUS_TM_PROBE_CPU_REF", "")
    rank == 0 && mkpath(dir)
    MPI.Barrier(MPI.COMM_WORLD)
    io = open(joinpath(dir, "rank_$(rank).txt"), "w")
    nranks == 2 || (println(io, "TM-PROBE-FAIL nranks=", nranks); close(io); error("the probe's MPI arm expects 2 ranks; got $(nranks)"))
    policy = Octopus.MultiProcessExecutionPolicy(ranks=2)
    schedule = tm_probe_schedule()
    cov = tm_probe_coverage(schedule)
    covered = cov.single_phase && cov.single_strength && cov.all_both
    results = Bool[]
    try
        for v in schedule
            r = tm_probe_verify(v, policy, dir; exact=true, cpu_ref=isempty(cpu_ref) ? nothing : cpu_ref)
            if rank == 0
                println(io, tm_probe_line("mpi2", v, r))
                push!(results, tm_probe_pass(r))
            end
            println(io, "TM-PROBE-SHARD rank=", rank, " nranks=", nranks, " label=", v.label,
                    " nlocal=", r.nlocal)
            flush(io)
        end
        if rank == 0
            println(io, "TM-PROBE-DONE backend=mpi2 ranks=", nranks, " verifications=", length(schedule),
                    " pass=", count(results), "/", length(schedule), " coverage=", covered,
                    " verdict=", (all(results) && covered) ? "PASS" : "FAIL")
        end
    catch err
        println(io, "TM-PROBE-FAIL rank=", rank, " ", sprint(showerror, err))
        flush(io)
        close(io)
        rethrow()
    end
    close(io)
    MPI.Barrier(MPI.COMM_WORLD)
    rank == 0 && !(all(results) && covered) && exit(1)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    # The child: Octopus and MPI as PACKAGES, so OctopusMPIExt attaches (an
    # included src/Octopus.jl gets no extension, and every rank would be its
    # own communicator of one).
    using Octopus, MPI
    tm_probe_child_main()
end
