#!/bin/bash
# Case L (81 elements) with the directdrift variant of the thick-magnet body step, nst1o2 and nst4o4.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); OCT=$(cd "$HERE/../../.." && pwd)
JL="julia --project=$OCT --startup-file=no --threads=4"
stamp() { echo "[$(date '+%F %T')] $*"; }
R=$OCT/result/bbscl_comparison/eltype/runs_probe; mkdir -p $R; cd $R
for cfg in "1 2" "4 4"; do
  set -- $cfg; tag=L81_directdrift_nst$1o$2
  uptime > load_$tag.txt
  OCT_VARIANT=directdrift OCT_PROBE_TARGET=lattice OCT_MODE=track OCT_GPU=1 OCT_NCELL=8 OCT_N=1048576 OCT_TURNS=100 OCT_WARMUP=10 \
    OCT_NST=$1 OCT_ORDER=$2 OCT_MOMENTS_EVERY=0 OCT_OPTICS=$OCT/validation/bbscl_comparison/lattice_optics.txt OCT_OUT=$R/octopus_$tag.tsv \
    $JL $HERE/probe_strang.jl > octopus_$tag.log 2>&1; echo "exit=$?" >> octopus_$tag.log
  stamp "$tag: $(grep 'mean/turn' octopus_$tag.log | cut -c1-120) | $(grep 'mean final' octopus_$tag.log | cut -c1-80)"
done
stamp "PROBE LATTICE DONE"
