#!/bin/bash
# After run_micro3.sh: Strang-path variants on the 16-quadrupole line (order 2, nst 1).
set -u
HERE=$(cd "$(dirname "$0")" && pwd); OCT=$(cd "$HERE/../../.." && pwd)
JL="julia --project=$OCT --startup-file=no --threads=4"
stamp() { echo "[$(date '+%F %T')] $*"; }
while pgrep -f "[r]un_micro3.sh" > /dev/null; do sleep 20; done
R=$OCT/result/bbscl_comparison/eltype/runs_probe; mkdir -p $R; cd $R
for v in orig nokick directdrift noloop loopdirect_nokick; do
  uptime > load_$v.txt
  OCT_VARIANT=$v OCT_KIND=quad OCT_COUNT=16 OCT_NST=1 OCT_ORDER=2 OCT_BEND_FRINGE=1 OCT_N=1048576 OCT_TURNS=60 OCT_WARMUP=10 \
    OCT_OUT=$R/octopus_$v.tsv $JL $HERE/probe_strang.jl > octopus_$v.log 2>&1; echo "exit=$?" >> octopus_$v.log
  stamp "quad16 variant $v: $(grep 'mean/turn' octopus_$v.log | cut -c1-110) | $(grep 'rms final' octopus_$v.log | cut -c1-90)"
done
stamp "PROBE DONE"
