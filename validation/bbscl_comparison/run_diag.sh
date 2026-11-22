#!/bin/bash
# BBSCL strong-strong cost decomposition: vary the slice count and the particle count at 20 turns.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)          # validation/bbscl_comparison
OCT=$(cd "$HERE/../.." && pwd)                # the repository root
R=$OCT/result/bbscl_comparison; mkdir -p $R  # run output, git-ignored
SRC=$HERE
BB=${BBSCL_BUILD:-$R/bbscl_build}             # the out-of-tree BBSCL build holding collider_test and prmb_test
stamp() { echo "[$(date '+%F %T')] $*"; }
run() { D=$R/runs/$1; shift; mkdir -p $D; cd $D; uptime > load.txt; stamp "begin $D";
        python3 $SRC/gen_bbscl_S.py --outdir $D --nturn 20 --itmon 10 "$@" > gen.txt;
        /usr/bin/time -v $BB/collider_test bbscl_S > run.log 2> time.log; echo "exit=$?" >> time.log; uptime >> load.txt; stamp "end $D"; }
run S_diag_pic_ns1_full   --ne 2560000 --np 1024000 --solver BBPIC --nslice 1
run S_diag_pic_ns15_quarter --ne 640000 --np 256000 --solver BBPIC --nslice 15
run S_diag_gau_ns1_full   --ne 2560000 --np 1024000 --solver BBGAU --nslice 1
run S_diag_gau_ns15_quarter --ne 640000 --np 256000 --solver BBGAU --nslice 15
run S_diag_pic_ns15_nonano --ne 2560000 --np 1024000 --solver BBPIC --nslice 15 --nanobeam 0 --dy 1.8e-6
stamp "DIAG DONE"
