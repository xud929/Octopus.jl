# Unit reports of the 2026-10-16 neighbour audit (crab-cavity / RF-cavity noise campaign)

These are the verbatim reading-unit reports of the 2026-10-16 targeted neighbour audit of the crab-cavity / RF-cavity noise campaign, copied unchanged (same file names) from the units' scratch output; the audit report that reads them is `../audit_crab_cavity_noise_neighbours_2026_10_16.md`. Standing rule: the leads in these reports are the units' claims as written at the time of reading, not findings of the audit; only the report's section 3 records which leads were reproduced, which were fixed and how, and nothing in this directory supersedes it.

| Unit | Region (from the report header) | Leads (count by severity) | File |
|---|---|---|---|
| U1 | `src/elements/turn_modulated.jl` | 8: 1 high, 2 medium, 5 low | [U1_report.md](U1_report.md) |
| U2 | `src/elements/crab_cavity.jl` and `src/elements/rf_cavity.jl` | 4: 3 low, 1 info | [U2_report.md](U2_report.md) |
| U3 | `src/tasks/Tasks.jl` | 6: 5 low, 1 low-medium | [U3_report.md](U3_report.md) |
| U4 | the strong-strong turn loop and the turn-modulation recorder (`src/tasks/strongstrong/interface.jl`) | 2: 2 low | [U4_report.md](U4_report.md) |
| U5 | `src/tasks/RunArtifact.jl` | 10: 2 medium, 7 low, 1 info | [U5_report.md](U5_report.md) |
| U6 | Phase 9 test quality: the campaign's testsets in `test/runtests.jl` and `test/turn_modulation_probe.jl` | 7: 6 low, 1 information | [U6_report.md](U6_report.md) |
| U7 | the crab cavity noise example, harness, benchmark driver and validation study | 7: 1 low-medium, 5 low, 1 info | [U7_report.md](U7_report.md) |
| U8 | the campaign's documents (Phases 3 and 6) | 18: 14 low, 4 info | [U8_report.md](U8_report.md) |
| U9 | localisation of lead U1-3: the general turn loop's per-turn allocation (`src/tasks/Tasks.jl`) | 6: 2 medium, 4 low | [U9_report.md](U9_report.md) |
| S1 | seam pass: the counter-RNG key space | 9: 7 low, 2 info | [S1_report.md](S1_report.md) |
| S2 | seam pass: CPU/CUDA twin implementations and thread-count invariance | 3: 1 medium, 2 low | [S2_report.md](S2_report.md) |
| S3 | seam pass: the walkers over a compiled line | 3: 2 low, 1 info | [S3_report.md](S3_report.md) |
| S4 | seam pass: declared schemas and metadata versus the runtime that consumes them | 10: 2 medium-low, 8 low | [S4_report.md](S4_report.md) |
| S5 | seam pass: producer-consumer protocol pairs (epochs, windows, caches, seeds) | 7: 1 high, 1 medium, 5 low | [S5_report.md](S5_report.md) |

Severity labels are the units' own, as written in each `### LEAD` header: U3-2 and U7-1 are tagged `low-medium`, S4-1 and S4-2 `medium-low`, U7-5 and S1-4 `low (documentation)` and S1-9 `out of hypothesis, low` (the last three counted as low above). Totals equal `grep -c '^### LEAD'` on each file.
