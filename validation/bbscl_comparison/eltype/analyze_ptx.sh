#!/bin/bash
# analyze_ptx.sh <dir-with-all.ptx>: split, ptxas -v (registers, spills, stack), nvdisasm counts.
set -u
D=$1
PTXAS=${PTXAS:-$(ls -d ~/.julia/artifacts/*/bin/ptxas | head -1)}   # a CUDA 13 ptxas from the CUDA.jl artifacts
NVDIS=${NVDISASM:-$(ls -d ~/.julia/artifacts/*/bin/nvdisasm | head -1)}
python3 $(dirname "$0")/split_ptx.py $D/all.ptx $D || exit 1
( time $PTXAS -v -O3 -arch=sm_89 $D/kernel.ptx -o $D/kernel.cubin ) > $D/ptxas_v.log 2>&1
grep -i "registers\|spill\|stack\|error" $D/ptxas_v.log | head -6; grep real $D/ptxas_v.log
$NVDIS -c $D/kernel.cubin > $D/kernel.sass 2> $D/nvdisasm.err
echo "static SASS instructions: $(grep -c '^\s*/\*[0-9a-f]*\*/' $D/kernel.sass)"
python3 - $D/kernel.sass <<'PY' > $D/opcode_hist.txt
import re, sys, collections
c = collections.Counter(); n = 0
for ln in open(sys.argv[1]):
    m = re.match(r'\s*/\*[0-9a-f]+\*/\s+(@!?P\d+\s+)?([A-Z0-9_]+)', ln)
    if m: c[m.group(2)] += 1; n += 1
fp64 = sum(c[o] for o in ("DFMA","DMUL","DADD","DSETP","DMNMX","MUFU"))
print(f"total {n}  FP64-class {fp64}  DFMA {c['DFMA']} DMUL {c['DMUL']} DADD {c['DADD']} MUFU {c['MUFU']} DSETP {c['DSETP']}  LDL+STL {c['LDL']+c['STL']}  LDG {c['LDG']} STG {c['STG']}  BRA {c['BRA']}  CALL {c['CALL']}")
for o, k in c.most_common(30): print(f"{k:8d} {o}")
PY
head -1 $D/opcode_hist.txt
