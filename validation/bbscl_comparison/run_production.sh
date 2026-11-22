#!/bin/bash
# Sequential production arms of the BBSCL/Octopus comparison (GPU exclusive). Logs per arm in runs/<arm>/.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)          # validation/bbscl_comparison
OCT=$(cd "$HERE/../.." && pwd)                # the repository root
R=$OCT/result/bbscl_comparison; mkdir -p $R  # run output, git-ignored
SRC=$HERE
BB=${BBSCL_BUILD:-$R/bbscl_build}             # the out-of-tree BBSCL build holding collider_test and prmb_test
JL="julia --project=$OCT --startup-file=no --threads=4"
stamp() { echo "[$(date '+%F %T')] $*"; }
arm_begin() { mkdir -p "$1"; cd "$1"; uptime > load.txt; nvidia-smi --query-gpu=memory.used,utilization.gpu --format=csv,noheader >> load.txt; stamp "begin $1"; }
arm_end() { uptime >> load.txt; stamp "end $1"; }

# ---- S, PIC, 200 turns ----
D=$R/runs/S_pic_200; arm_begin $D
python3 $SRC/gen_bbscl_S.py --outdir $D --nturn 200 --itmon 10 --ne 2560000 --np 1024000 --solver BBPIC > gen.txt
/usr/bin/time -v $BB/collider_test bbscl_S > run.log 2> time.log; echo "exit=$?" >> time.log
arm_end $D
D=$R/runs/S_pic_200_octopus; arm_begin $D
OCT_GPU=1 OCT_NE=2560000 OCT_NP=1024000 OCT_TURNS=200 OCT_WARMUP=20 OCT_NS=15 OCT_GRID=128 OCT_SOLVER=pic OCT_MOMENTS_EVERY=0 OCT_OUT=$D/octopus_S_pic_timing.tsv $JL $SRC/octopus_strong_strong_bbscl.jl > timing.log 2>&1; echo "exit=$?" >> timing.log
OCT_GPU=1 OCT_NE=2560000 OCT_NP=1024000 OCT_TURNS=200 OCT_WARMUP=20 OCT_NS=15 OCT_GRID=128 OCT_SOLVER=pic OCT_MOMENTS_EVERY=1 OCT_OUT=$D/octopus_S_pic_moments.tsv $JL $SRC/octopus_strong_strong_bbscl.jl > moments.log 2>&1; echo "exit=$?" >> moments.log
arm_end $D

# ---- S, Gaussian, 200 turns ----
D=$R/runs/S_gau_200; arm_begin $D
python3 $SRC/gen_bbscl_S.py --outdir $D --nturn 200 --itmon 10 --ne 2560000 --np 1024000 --solver BBGAU > gen.txt
/usr/bin/time -v $BB/collider_test bbscl_S > run.log 2> time.log; echo "exit=$?" >> time.log
arm_end $D
D=$R/runs/S_gau_200_octopus; arm_begin $D
OCT_GPU=1 OCT_NE=2560000 OCT_NP=1024000 OCT_TURNS=200 OCT_WARMUP=20 OCT_NS=15 OCT_SOLVER=gaussian OCT_MOMENTS_EVERY=0 OCT_OUT=$D/octopus_S_gau_timing.tsv $JL $SRC/octopus_strong_strong_bbscl.jl > timing.log 2>&1; echo "exit=$?" >> timing.log
arm_end $D

# ---- W, weak-strong, 1,024,000, 200 turns ----
D=$R/runs/W_200; arm_begin $D
python3 $SRC/gen_bbscl_W.py --outdir $D --nturn 200 --itmon 10 --n 1024000 --nslice 7 > gen.txt
/usr/bin/time -v $BB/prmb_test bbscl_W > run.log 2> time.log; echo "exit=$?" >> time.log
arm_end $D
D=$R/runs/W_200_octopus; arm_begin $D
OCT_GPU=1 OCT_N=1024000 OCT_TURNS=200 OCT_WARMUP=20 OCT_NS=7 OCT_MOMENTS_EVERY=0 OCT_OUT=$D/octopus_W_timing.tsv $JL $SRC/octopus_weak_strong_bbscl.jl > timing.log 2>&1; echo "exit=$?" >> timing.log
OCT_GPU=1 OCT_N=1024000 OCT_TURNS=200 OCT_WARMUP=20 OCT_NS=7 OCT_MOMENTS_EVERY=1 OCT_OUT=$D/octopus_W_moments.tsv $JL $SRC/octopus_weak_strong_bbscl.jl > moments.log 2>&1; echo "exit=$?" >> moments.log
arm_end $D

# ---- repeats for spread: BBSCL S-PIC 60 turns and Octopus S-PIC 60 turns ----
D=$R/runs/S_pic_60_repeat; arm_begin $D
python3 $SRC/gen_bbscl_S.py --outdir $D --nturn 60 --itmon 10 --ne 2560000 --np 1024000 --solver BBPIC > gen.txt
/usr/bin/time -v $BB/collider_test bbscl_S > run.log 2> time.log; echo "exit=$?" >> time.log
OCT_GPU=1 OCT_NE=2560000 OCT_NP=1024000 OCT_TURNS=60 OCT_WARMUP=10 OCT_NS=15 OCT_GRID=128 OCT_SOLVER=pic OCT_MOMENTS_EVERY=0 OCT_OUT=$D/octopus_S_pic_repeat.tsv $JL $SRC/octopus_strong_strong_bbscl.jl > octopus.log 2>&1; echo "exit=$?" >> octopus.log
arm_end $D
stamp "ALL DONE"
