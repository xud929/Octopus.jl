#!/bin/bash
# Octopus-only probes after the per-type chain: register caps (occupancy), nst scaling, case L capped.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); OCT=$(cd "$HERE/../../.." && pwd)
JL="julia --project=$OCT --startup-file=no --threads=4"
stamp() { echo "[$(date '+%F %T')] $*"; }
while pgrep -f "[r]un_eltype.sh" > /dev/null; do sleep 20; done
R=$OCT/result/bbscl_comparison/eltype/runs_micro
oct() {  # dir kind count nst order fringe tag [env...]
  mkdir -p "$1"; cd "$1"; uptime > load_$7.txt
  OCT_KIND=$2 OCT_COUNT=$3 OCT_NST=$4 OCT_ORDER=$5 OCT_BEND_FRINGE=$6 OCT_N=1048576 OCT_TURNS=60 OCT_WARMUP=10 \
    OCT_OUT="$1/octopus_$7.tsv" env "${@:8}" $JL $HERE/octopus_eltype.jl > octopus_$7.log 2>&1; echo "exit=$?" >> octopus_$7.log
  stamp "$(basename $1) $7: $(grep 'mean/turn' octopus_$7.log | cut -c1-110) | $(grep occupancy octopus_$7.log | cut -c1-80)"
}
lat() {  # dir nst order maxregs tag
  mkdir -p "$1"; cd "$1"; uptime > load_$5.txt
  OCT_MODE=track OCT_GPU=1 OCT_NCELL=8 OCT_N=1048576 OCT_TURNS=100 OCT_WARMUP=10 OCT_NST=$2 OCT_ORDER=$3 OCT_MOMENTS_EVERY=0 \
    OCT_OPTICS=$OCT/validation/bbscl_comparison/lattice_optics.txt OCT_OUT="$1/octopus_L_$5.tsv" OCT_MAXREGS=$4 \
    $JL $HERE/lattice_maxregs.jl > octopus_L_$5.log 2>&1; echo "exit=$?" >> octopus_L_$5.log
  stamp "L81 $5: $(grep 'mean/turn' octopus_L_$5.log | cut -c1-110) | $(grep occupancy octopus_L_$5.log | cut -c1-80)"
}
oct $R/quad16 quad 16 1 2 1 nst1o2_r128 OCT_MAXREGS=128
oct $R/quad16 quad 16 1 2 1 nst1o2_r96  OCT_MAXREGS=96
oct $R/quad16 quad 16 1 2 1 nst1o2_r64  OCT_MAXREGS=64
oct $R/quad16 quad 16 2 2 1 nst2o2
oct $R/drift32 drift 32 1 2 1 nst1o2_r64 OCT_MAXREGS=64
oct $R/sext16 sext 16 1 2 1 nst1o2_r128 OCT_MAXREGS=128
oct $R/bend16 bend 16 1 2 1 fr_r128 OCT_MAXREGS=128
lat $R/L81 1 2 128 nst1o2_r128
lat $R/L81 4 4 128 nst4o4_r128
stamp "MICRO DONE"
