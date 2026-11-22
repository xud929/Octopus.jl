#!/bin/bash
# PTX dump of the 81-element case L kernel at nst1o2 and nst4o4, then ptxas -v and nvdisasm counts.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); OCT=$(cd "$HERE/../../.." && pwd)
PTXAS=${PTXAS:-$(ls -d ~/.julia/artifacts/*/bin/ptxas | head -1)}   # a CUDA 13 ptxas from the CUDA.jl artifacts
NVDIS=${NVDISASM:-$(ls -d ~/.julia/artifacts/*/bin/nvdisasm | head -1)}
JL="julia --project=$OCT --startup-file=no --threads=4"
for cfg in "1 2" "4 4"; do
  set -- $cfg
  echo "[$(date '+%T')] dump nst$1 o$2"
  OCT_NST=$1 OCT_ORDER=$2 $JL $HERE/dump_L81.jl > $OCT/result/bbscl_comparison/eltype/dump_L81_nst$1o$2.log 2>&1; echo "exit=$?" >> $OCT/result/bbscl_comparison/eltype/dump_L81_nst$1o$2.log
  D=$OCT/result/bbscl_comparison/eltype/dump_L81_nst$1o$2
  tail -3 $OCT/result/bbscl_comparison/eltype/dump_L81_nst$1o$2.log
  $HERE/analyze_ptx.sh $D
done
echo "[$(date '+%T')] DUMP DONE"
