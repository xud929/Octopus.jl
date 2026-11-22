#!/usr/bin/env python3
"""Basic-block view of an instruction range of an nvdisasm -c listing: blocks end at a branch/call/label."""
import re, sys
path, lo, hi = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
lines = open(path).read().splitlines()
ins = []; labels = {}
pend = []
for ln in lines:
    m = re.match(r'\s*(\.L_[A-Za-z0-9_]+):', ln)
    if m: pend.append(m.group(1)); continue
    m = re.match(r'\s*/\*([0-9a-f]+)\*/\s+(@!?P\d+\s+|@!?PT\s+)?([A-Z0-9_.]+)(.*)', ln)
    if m:
        for p in pend: labels[len(ins)] = p
        pend = []
        ins.append(((m.group(2) or '').strip(), m.group(3), m.group(4).strip()))
fp64 = ("DFMA","DMUL","DADD","DSETP","DMNMX","MUFU")
blocks = []; start = lo
def flush(end, reason):
    global start
    body = ins[start:end+1]
    n = len(body); f = sum(1 for p,o,r in body if o.split('.')[0] in fp64)
    tags = []
    if any(o.startswith("MUFU.RSQ64H") for _,o,_ in body): tags.append("sqrt")
    if any(o.startswith("MUFU.RCP64H") for _,o,_ in body): tags.append("div%d" % sum(1 for _,o,_ in body if o.startswith("MUFU.RCP64H")))
    calls = [re.sub(r'.*\$', '', re.sub(r'\).*', '', r)) for p,o,r in body if o.startswith("CALL")]
    if calls: tags.append("CALL:" + ",".join(c[:28] for c in calls))
    dsetp = [r[:40] for p,o,r in body if o.startswith("DSETP")]
    if dsetp: tags.append("DSETP:" + "|".join(dsetp[:2]))
    blocks.append((start, end, n, f, reason, " ".join(tags)))
    start = end + 1
for i in range(lo, hi + 1):
    p, o, r = ins[i]
    if (i + 1) in labels and i >= start: flush(i, f"fallthrough->{labels[i+1]}"); continue
    if o.startswith(("BRA", "CALL", "RET", "EXIT", "BSYNC")) and not o.startswith("BSSY"):
        flush(i, f"{p} {o} {r[:30]}")
if start <= hi: flush(hi, "end")
print(f"{'from':>6s} {'to':>6s} {'n':>5s} {'FP64':>5s}  end-reason / tags")
for b in blocks:
    if b[2] >= 2 or b[3] > 0:
        print(f"{b[0]:6d} {b[1]:6d} {b[2]:5d} {b[3]:5d}  {b[4][:48]:48s} {b[5][:70]}")
