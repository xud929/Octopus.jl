# Unit report U2: the compile walk, the flags and the streams (batch units U4, U5, U6)

Tree read: the cp1 worktree at the end of the batch. Probe logs:
`/tmp/claude-dxu/cp1/audit_probes3.log` (L3, L5),
`/tmp/claude-dxu/cp1/audit_probes_b.log` (the walkers). Every lead reproduced
by the auditor in a fresh process.

## Leads and dispositions

- **L3 (U4) Every walker over a line holding a collision marker.** The
  stage-5 audit's B-1 enumerated the walkers that meet a wrapped non-element
  child; the marker is such a child, so each was re-run on `BeamLine("LM", q,
  d, ip, qd, d)`: `total_length` 2.0 (the marker has no length),
  `find_entries` `[4]`, `entry_path` `LM/STRONGSTRONGCOLLISION`,
  `knob_report` over the line and over its `Lattice` (accepted),
  `machine_toml` and `parse_machine` (equal), `_has_accelerating_cavity`
  (false), `with_overrides` on the marker's placement (refused by name, the
  stage-5 guard), `one_turn_matrix` on the line and `analyze` on the lattice
  (accepted), `TrackingTask((lm,))` -- the whole line as ONE element -- tracks
  one turn (the batch's `_inert_in_single_beam` arm in the whole-line compile,
  `src/elements/beam_line.jl:893-907`). The survey walker
  (`src/elements/floor_plan.jl:171-244`) treats a zero-length entry as a
  point and was not changed. **Clean.**
- **L4 (U4) The strong-strong route.** `_inert_in_single_beam` is read by the
  single-beam compile only (`_append_runtime_line!` in `src/tasks/Tasks.jl`
  and the whole-line compile); the strong-strong task's own walk
  (`interface.jl`) still reads the marker as the pairing's solver, and its
  `_binding_report` names `collision_markers` beside the pairing. The parity
  driver's `ss` case (tuples against the machine route) passes with equal
  digests on CPU (`result/gates/cp1/parity_ss_cpu.log`). **Clean.**
- **L5 (U5) A placement override carrying an `rng_id` through compile and
  execution.** `lr[2].rng_id = <fresh>` on a `LumpedRadSpec` placement, then
  `execute!(TrackingTask(Lattice(...)))`: zero warnings (the override route
  claimed the id under `:lumped_radiation`; the compile's rebuild of the
  overridden spec through the flexible form re-passes the id the class now
  holds). **Clean.**
- **L6 (U5) The routes into the flexible form.** `ElementSpec{Kind}(params)`
  is the one inner constructor (`src/knowledge/Knowledge.jl:61`); the knob
  resolve (`src/knobs/Knobs.jl:1216`), `_with_numeric_type`
  (`Knowledge.jl:1040`), the snapshot reader (`src/lattice/toml.jl:907`) and
  the placement-override merge all pass through it, so one claim covers them;
  the three assignment routes (`setproperty!` on the spec, on the `LineEntry`,
  `with_overrides`) call `_claim_override_stream!` after their guards. The
  registry's `claim_rng_id!` policy is unchanged (the suite's rng-policy block
  passes extracted after the tripwire learned the one non-literal class, the
  metadata's). **Clean.**
- **L12 (U6) The accelerating-cavity flag's readers.** `_has_accelerating_cavity`
  is called once, at construction (`src/tasks/Tasks.jl:338`); the executor
  reads the field (the suite pins the text). The strong-strong task has no
  single-pass refusal of its own. The parity driver's `ws` case: the lattice
  and machine routes allocate 46426 bytes per turn against the tuple's 46422
  (4 bytes), where the stage-5 audit measured +416 bytes per `execute!` for
  the per-call survey (C-3). **Clean; the fix measured.**
- **L13 (U6) `EveryNSteps`'s `stop` and the readers of old snapshots.** A
  snapshot written by stage 4 carries `stop = 9223372036854775807`, which the
  reader still accepts (the hook's constructor takes it); a new snapshot omits
  it. The codec round-trip block passes extracted. **Clean.**

## Coverage

Read: `src/elements/beam_line.jl` (the whole-line compile, `setproperty!`,
`total_length`, `find_entries`), `src/tasks/Tasks.jl` (`_append_runtime_line!`,
`_collision_marker_count`, the binding, `_execute_tracking_window!`, the
constructor's flag), `src/tasks/strongstrong/interface.jl`
(`_inert_in_single_beam`, `_binding_report`), `src/knowledge/Knowledge.jl`
(the inner constructor, `_claim_spec_stream!`, `_claim_override_stream!`,
the validator tripwire), `src/math/counter_rng.jl` (`_rng_id_held_by`),
`src/lattice/overrides.jl`, `src/lattice/toml_hooks.jl`,
`src/tasks/BeamObservers.jl` (`_moment_power`). Not read: the CUDA kernels
(the batch touched no kernel; the CUDA fingerprints are within the
same-tree noise and the deterministic rows bitwise).
