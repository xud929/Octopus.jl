#!/bin/bash
# Per-element-type timing arms, sequential, GPU exclusive: BBSCL then Octopus per arm.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OCT=$(cd "$HERE/../../.." && pwd)
BB=${BBSCL_BUILD:-$OCT/result/bbscl_comparison/bbscl_build}
JL="julia --project=$OCT --startup-file=no --threads=4"
N=1048576; TURNS=60; WARMUP=10; BBTURNS=200
stamp() { echo "[$(date '+%F %T')] $*"; }
bb_arm() {  # dir kind count
  mkdir -p "$1"; cd "$1"; uptime > load.txt; nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader >> load.txt
  python3 $HERE/gen_bbscl_T.py --outdir "$1" --kind $2 --count $3 --n $N --nturn $BBTURNS --itmon $BBTURNS > gen.txt
  /usr/bin/time -v $BB/prmb_test bbscl_T > run.log 2> time.log; echo "exit=$?" >> time.log
  stamp "bbscl $2 x$3: $(grep gpu_time run.log)"
}
oct_arm() {  # dir kind count nst order bendfringe [extra env]
  mkdir -p "$1"; cd "$1"; uptime >> load.txt
  OCT_KIND=$2 OCT_COUNT=$3 OCT_NST=$4 OCT_ORDER=$5 OCT_BEND_FRINGE=$6 OCT_N=$N OCT_TURNS=$TURNS OCT_WARMUP=$WARMUP \
    OCT_OUT="$1/octopus_$7.tsv" env ${8:-} $JL $HERE/octopus_eltype.jl > octopus_$7.log 2>&1; echo "exit=$?" >> octopus_$7.log
  stamp "octopus $7: $(grep 'mean/turn' octopus_$7.log)"
  if [ -n "${8:-}" ]; then DD=${8#OCT_DUMP=}; ( $HERE/analyze_ptx.sh $DD > $DD/analyze.log 2>&1 ) & stamp "static analysis of $DD started in the background (CPU only)"; fi
}
R=$OCT/result/bbscl_comparison/eltype/runs
# baseline: the one-turn map alone
bb_arm $R/map map 0;            oct_arm $R/map map 0 1 2 1 map OCT_DUMP=$R/map/dump
# case L multiplicities: 32 drifts, 16 quads, 16 sexts, 16 bends
bb_arm $R/drift32 drift 32;     oct_arm $R/drift32 drift 32 1 2 1 nst1o2 OCT_DUMP=$R/drift32/dump
bb_arm $R/quad16 quad 16;       oct_arm $R/quad16 quad 16 1 2 1 nst1o2 OCT_DUMP=$R/quad16/dump_nst1o2;   oct_arm $R/quad16 quad 16 4 4 1 nst4o4 OCT_DUMP=$R/quad16/dump_nst4o4
bb_arm $R/sext16 sext 16;       oct_arm $R/sext16 sext 16 1 2 1 nst1o2 OCT_DUMP=$R/sext16/dump_nst1o2;   oct_arm $R/sext16 sext 16 4 4 1 nst4o4
bb_arm $R/bend16 bend 16;       oct_arm $R/bend16 bend 16 1 2 1 fr OCT_DUMP=$R/bend16/dump_fr;       oct_arm $R/bend16 bend 16 1 2 0 nofr OCT_DUMP=$R/bend16/dump_nofr
# code-size scaling: drifts x8 and x128
bb_arm $R/drift8 drift 8;       oct_arm $R/drift8 drift 8 1 2 1 nst1o2
bb_arm $R/drift128 drift 128;   oct_arm $R/drift128 drift 128 1 2 1 nst1o2
# BBSCL gpu_time = per-turn cost x turns + an end-of-run constant: two turn counts separate them
bb_turns() {  # dir input-file nturn itmon
  mkdir -p "$1"; cd "$1"; uptime > load.txt
  python3 - "$2" "$3" "$4" <<'PY' > gen.txt
import sys, re
src, nturn, itmon = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(src).read()
def fix(m):
    s = m.group(1).split(','); s[7] = ' ' + nturn; s[8] = ' ' + itmon; return 'Beam Gaussian=({' + ','.join(s) + '});'
out = re.sub(r'Beam Gaussian=\(\{(.*?)\}\);', fix, txt, count=1)
open('bbscl_X.in', 'w').write(out); print('turns', nturn, 'itmon', itmon, 'from', src)
PY
  /usr/bin/time -v $BB/prmb_test bbscl_X > run.log 2> time.log; echo "exit=$?" >> time.log
  stamp "bbscl $(basename $1): $(grep gpu_time run.log)"
}
IN=$OCT/validation/bbscl_comparison/inputs
bb_turns $R/const_map400 $R/map/bbscl_T.in 400 400
bb_turns $R/const_L200 $IN/bbscl_L.in 200 10
bb_turns $R/const_L400 $IN/bbscl_L.in 400 10
bb_turns $R/const_W200 $IN/bbscl_W.in 200 10
bb_turns $R/const_W400 $IN/bbscl_W.in 400 10
wait
stamp "ELTYPE DONE (static analyses finished too)"
