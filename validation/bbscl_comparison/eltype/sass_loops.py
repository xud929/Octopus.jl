#!/usr/bin/env python3
"""Find loops (backward branches) in an nvdisasm -c listing and report each loop body's size and mix.
Also reports the straight-line totals for context."""
import re, sys, collections
lines = open(sys.argv[1]).read().splitlines()
ins = []            # (idx, addr, pred, op, text)
label_at = {}       # label -> index of next instruction
pending = []
for ln in lines:
    m = re.match(r'\s*(\.L_[A-Za-z0-9_]+):', ln)
    if m: pending.append(m.group(1)); continue
    m = re.match(r'\s*/\*([0-9a-f]+)\*/\s+(@!?P\d+\s+|@!?PT\s+)?([A-Z0-9_.]+)(.*)', ln)
    if m:
        for p in pending: label_at[p] = len(ins)
        pending = []
        ins.append((len(ins), int(m.group(1), 16), (m.group(2) or '').strip(), m.group(3), m.group(4)))
print(f"instructions: {len(ins)}")
fp64 = ("DFMA","DMUL","DADD","DSETP","DMNMX","MUFU")
loops = []
for i, addr, pred, op, rest in ins:
    if op.startswith("BRA"):
        m = re.search(r'`\((\.L_[A-Za-z0-9_]+)\)', rest)
        if not m: continue
        t = label_at.get(m.group(1))
        if t is not None and t < i:
            body = ins[t:i+1]
            c = collections.Counter(o.split('.')[0] for _,_,_,o,_ in body)
            loops.append((i - t + 1, t, i, sum(c[k] for k in fp64), c["DFMA"], c["LDL"]+c["STL"], c["CALL"], c["BRA"], c["BSSY"], pred))
loops.sort(reverse=True)
print(f"{'body':>6s} {'from':>7s} {'to':>7s} {'FP64':>6s} {'DFMA':>5s} {'LDL+STL':>7s} {'CALL':>4s} {'BRA':>4s} {'BSSY':>4s} pred")
for L in loops[:25]:
    print(f"{L[0]:6d} {L[1]:7d} {L[2]:7d} {L[3]:6d} {L[4]:5d} {L[5]:7d} {L[6]:4d} {L[7]:4d} {L[8]:4d} {L[9]}")
print(f"loops found: {len(loops)}")
