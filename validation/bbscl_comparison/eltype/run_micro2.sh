#!/bin/bash
# After run_micro.sh: the Strang step written out as drift + thin quadrupole + drift, and the thin kick alone.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); OCT=$(cd "$HERE/../../.." && pwd)
JL="julia --project=$OCT --startup-file=no --threads=4"
stamp() { echo "[$(date '+%F %T')] $*"; }
while pgrep -f "[r]un_micro.sh" > /dev/null; do sleep 20; done
R=$OCT/result/bbscl_comparison/eltype/runs_micro
oct() {  # dir kind count nst order fringe tag [env...]
  mkdir -p "$1"; cd "$1"; uptime > load_$7.txt
  OCT_KIND=$2 OCT_COUNT=$3 OCT_NST=$4 OCT_ORDER=$5 OCT_BEND_FRINGE=$6 OCT_N=1048576 OCT_TURNS=60 OCT_WARMUP=10 \
    OCT_OUT="$1/octopus_$7.tsv" env "${@:8}" $JL $HERE/octopus_eltype.jl > octopus_$7.log 2>&1; echo "exit=$?" >> octopus_$7.log
  stamp "$(basename $1) $7: $(grep 'mean/turn' octopus_$7.log | cut -c1-110) | $(grep occupancy octopus_$7.log | cut -c1-80)"
}
oct $R/split16 split 16 1 2 1 base OCT_DUMP=$R/split16/dump
oct $R/thinq16 thinq 16 1 2 1 base
oct $R/quad16 quad 16 1 2 1 nst1o2_base OCT_DUMP=$R/quad16/dump_base
( $HERE/analyze_ptx.sh $R/split16/dump > $R/split16/dump/analyze.log 2>&1; $HERE/analyze_ptx.sh $R/quad16/dump_base > $R/quad16/dump_base/analyze.log 2>&1 ) &
wait
stamp "MICRO2 DONE"
