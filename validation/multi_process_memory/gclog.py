#!/usr/bin/env python3
"""Summarise Julia GC log lines (GC.enable_logging) from a run log: heap_size and heap_target after each
collection, sampled every k-th collection, plus the totals."""
import re, sys
path = sys.argv[1]; k = int(sys.argv[2]) if len(sys.argv) > 2 else 50
txt = open(path, errors="replace").read()
gcs = re.findall(r"GC: pause ([0-9.]+)ms\. collected ([0-9.]+)MB\. (\w+)\s*\n\s*Heap stats: bytes_mapped ([0-9.]+) MB, bytes_resident ([0-9.]+) MB,\s*\n\s*heap_size ([0-9.]+) MB, heap_target ([0-9.]+) MB, Fragmentation ([0-9.]+)", txt)
print(f"{path}: {len(gcs)} collections logged (rank 0)")
if not gcs: sys.exit(0)
print(f"{'#':>6s} {'pause_ms':>9s} {'collected_MB':>12s} {'kind':>5s} {'mapped_MB':>10s} {'resident_MB':>11s} {'heap_size_MB':>12s} {'heap_target_MB':>14s} {'frag':>6s}")
for i, g in enumerate(gcs):
    if i % k == 0 or i == len(gcs) - 1:
        print(f"{i:6d} {float(g[0]):9.1f} {float(g[1]):12.1f} {g[2]:>5s} {float(g[3]):10.0f} {float(g[4]):11.0f} {float(g[5]):12.0f} {float(g[6]):14.0f} {float(g[7]):6.3f}")
full = sum(1 for g in gcs if g[2].startswith("full")); tp = sum(float(g[0]) for g in gcs) / 1e3
print(f"full collections: {full} of {len(gcs)}; total pause {tp:.1f} s; collected total {sum(float(g[1]) for g in gcs)/1024:.1f} GB")
