import csv, sys

# Prints, for every sensor, how much it rose under each load against the phase before it.
C = sys.argv[1]
rows = list(csv.reader(open(f"{C}/samples.csv")))
head, data = rows[0], rows[1:]
phases = [(int(t), n) for t, n in (l.strip().split(",") for l in open(f"{C}/phases.csv") if l.strip())]
def window(name, tail):
    start = dict((n, t) for t, n in phases)[name]
    nxt = [t for t, n in phases if t > start]
    end = min(nxt) if nxt else start + 90
    return end - tail, end
def mean(col, a, b):
    v = [float(r[col]) for r in data if r[col] and a <= float(r[0]) < b]
    return sum(v) / len(v) if v else float("nan")
loads = [("pcores", "idle"), ("ecores", "cool1"), ("gpu", "cool2")]
res = []
for i, h in enumerate(head[1:], 1):
    if not h.startswith(("hid:", "smc:")): continue
    deltas = {}
    for load, before in loads:
        a0, b0 = window(before, 20); a1, b1 = window(load, 30)
        deltas[load] = mean(i, a1, b1) - mean(i, a0, b0)
    a, b = window("idle", 20)
    res.append((h, mean(i, a, b), deltas))
res = [r for r in res if r[1] == r[1] and 10 < r[1] < 130]
def cls(d):
    top = max(d, key=d.get)
    if d[top] < 2: return "flat"
    second = sorted(d.values())[-2]
    return top if d[top] - second >= 2 else top + "~"
print(f"{'sensor':28} {'idle':>6} {'+P':>6} {'+E':>6} {'+GPU':>6}  reacts to")
for h, idle, d in sorted(res, key=lambda r: (cls(r[2]), r[0])):
    print(f"{h:28} {idle:6.1f} {d['pcores']:6.1f} {d['ecores']:6.1f} {d['gpu']:6.1f}  {cls(d)}")
groups = [("HID tdie", lambda h: h.startswith("hid:") and "tdie" in h.lower()),
          ("SMC Tp*", lambda h: h.startswith("smc:Tp")), ("SMC Te*", lambda h: h.startswith("smc:Te")),
          ("SMC Tg*", lambda h: h.startswith("smc:Tg")), ("SMC TPDX", lambda h: h == "smc:TPDX")]
print()
print("peak of each group in the last 30 s of each load")
for load, _ in loads:
    a, b = window(load, 30)
    seg = [r for r in data if a <= float(r[0]) < b]
    parts = []
    for name, pred in groups:
        cols = [i for i, h in enumerate(head) if pred(h)]
        vals = [float(r[i]) for r in seg for i in cols if r[i] and 10 < float(r[i]) < 130]
        parts.append(f"{name} {max(vals):5.1f}" if vals else f"{name}   -  ")
    print(f"{load:7}: " + " | ".join(parts))
