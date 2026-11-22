#!/usr/bin/env python3
"""Split a CUDA.jl @device_code_ptx io= dump into modules and write the one holding
the fused tracking kernel (cuda_track_kernel) to <outdir>/kernel.ptx."""
import sys, re, os
src, outdir = sys.argv[1], sys.argv[2]
txt = open(src).read()
parts = re.split(r'(?m)^(?=// PTX CompilerJob of MethodInstance for )', txt)
hit = [p for p in parts if 'cuda_track_kernel' in p.split('\n', 1)[0]]
if not hit:
    hit = [p for p in parts if '.entry' in p and 'cuda_track_kernel' in p]
if not hit:
    sys.exit("no cuda_track_kernel module in " + src + f" ({len(parts)} modules)")
p = hit[-1]
body = p.split('\n', 1)[1] if p.startswith('//') else p
os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, 'kernel.ptx'), 'w').write(body)
ent = re.findall(r'\.entry\s+(\S+)\(', body)
print(f"modules={len(parts)} picked={len(hit)} entry={ent[:1]} lines={body.count(chr(10))}")
