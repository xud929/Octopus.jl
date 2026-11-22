#!/bin/bash
# Case L (8-cell FODO ring, 81 elements) arms, sequential, GPU exclusive. Logs per arm in runs/L_*/.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)          # validation/bbscl_comparison
OCT=$(cd "$HERE/../.." && pwd)                # the repository root
R=$OCT/result/bbscl_comparison; mkdir -p $R  # run output, git-ignored
SRC=$HERE
BB=${BBSCL_BUILD:-$R/bbscl_build}             # the out-of-tree BBSCL build holding collider_test and prmb_test
JL="julia --project=$OCT --startup-file=no --threads=4"
NC=8
stamp() { echo "[$(date '+%F %T')] $*"; }
arm_begin() { mkdir -p "$1"; cd "$1"; uptime > load.txt; nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader >> load.txt; stamp "begin $1"; }
arm_end() { uptime >> load.txt; stamp "end $1"; }

# ---- gauge: compile cost and sanity at 20480 particles, 20 turns ----
D=$R/runs/L_gauge; arm_begin $D
OCT_MODE=track OCT_GPU=1 OCT_NCELL=$NC OCT_N=20480 OCT_TURNS=20 OCT_WARMUP=5 OCT_MOMENTS_EVERY=0 OCT_OPTICS=$SRC/lattice_optics.txt OCT_OUT=$D/octopus_L_gauge.tsv $JL $SRC/octopus_lattice_bbscl.jl > octopus.log 2>&1; echo "exit=$?" >> octopus.log
python3 $SRC/gen_bbscl_L.py --outdir $D --optics $SRC/lattice_optics.txt --ncell $NC --n 20480 --nturn 20 --itmon 10 > gen.txt
/usr/bin/time -v $BB/prmb_test bbscl_L > run.log 2> time.log; echo "exit=$?" >> time.log
arm_end $D

# ---- tunes: 20480 particles, 1024 turns, centroid every turn ----
D=$R/runs/L_tunes; arm_begin $D
python3 $SRC/gen_bbscl_L.py --outdir $D --optics $SRC/lattice_optics.txt --ncell $NC --n 20480 --nturn 1024 --itmon 8 > gen.txt
/usr/bin/time -v $BB/prmb_test bbscl_L > run.log 2> time.log; echo "exit=$?" >> time.log
OCT_MODE=track OCT_GPU=1 OCT_NCELL=$NC OCT_N=20480 OCT_TURNS=1024 OCT_WARMUP=24 OCT_MOMENTS_EVERY=1 OCT_OPTICS=$SRC/lattice_optics.txt OCT_OUT=$D/octopus_L_tunes.tsv $JL $SRC/octopus_lattice_bbscl.jl > octopus.log 2>&1; echo "exit=$?" >> octopus.log
OCT_MODE=track OCT_GPU=1 OCT_NCELL=$NC OCT_N=20480 OCT_TURNS=1024 OCT_WARMUP=24 OCT_NST=4 OCT_ORDER=4 OCT_MOMENTS_EVERY=1 OCT_OPTICS=$SRC/lattice_optics.txt OCT_OUT=$D/octopus_L_tunes_nst4o4.tsv $JL $SRC/octopus_lattice_bbscl.jl > octopus_nst4o4.log 2>&1; echo "exit=$?" >> octopus_nst4o4.log
python3 $SRC/tunes.py bbscl $D/bbscl_L.f10 > tunes.txt 2>&1
python3 $SRC/tunes.py octopus $D/octopus_L_tunes_moments.tsv >> tunes.txt 2>&1
python3 $SRC/tunes.py octopus $D/octopus_L_tunes_nst4o4_moments.tsv >> tunes.txt 2>&1
arm_end $D

# ---- production: 1,048,576 particles, 200 turns ----
D=$R/runs/L_200; arm_begin $D
python3 $SRC/gen_bbscl_L.py --outdir $D --optics $SRC/lattice_optics.txt --ncell $NC --n 1048576 --nturn 200 --itmon 10 > gen.txt
/usr/bin/time -v $BB/prmb_test bbscl_L > run.log 2> time.log; echo "exit=$?" >> time.log
OCT_MODE=track OCT_GPU=1 OCT_NCELL=$NC OCT_N=1048576 OCT_TURNS=200 OCT_WARMUP=20 OCT_MOMENTS_EVERY=0 OCT_OPTICS=$SRC/lattice_optics.txt OCT_OUT=$D/octopus_L_200.tsv $JL $SRC/octopus_lattice_bbscl.jl > octopus.log 2>&1; echo "exit=$?" >> octopus.log
OCT_MODE=track OCT_GPU=1 OCT_NCELL=$NC OCT_N=1048576 OCT_TURNS=200 OCT_WARMUP=20 OCT_NST=4 OCT_ORDER=4 OCT_MOMENTS_EVERY=0 OCT_OPTICS=$SRC/lattice_optics.txt OCT_OUT=$D/octopus_L_200_nst4o4.tsv $JL $SRC/octopus_lattice_bbscl.jl > octopus_nst4o4.log 2>&1; echo "exit=$?" >> octopus_nst4o4.log
/usr/bin/time -v $BB/prmb_test bbscl_L > run_repeat.log 2> time_repeat.log; echo "exit=$?" >> time_repeat.log
arm_end $D
stamp "LATTICE DONE"
