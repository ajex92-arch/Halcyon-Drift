import json, sys, glob, collections
for tag in ["ab_base", "ab_int1"]:
    st = collections.Counter(); hulls = collections.Counter(); n = 0; ex = []
    for f in sorted(glob.glob(sys.argv[1] + "\\" + tag + "_seed*.txt")):
        if "_err" in f: continue
        for line in open(f, encoding="utf-8", errors="replace"):
            if line.startswith("AUDIT_JSON "):
                j = json.loads(line[11:]); c = j["counters"]
                n += c.get("no_route_far", 0)
                for e in j["examples"].get("no_route_far", []):
                    st[e["state"]] += 1; hulls[e["hull"]] += 1
                    if len(ex) < 6: ex.append((f[-12:-4], e))
    print(tag, "no_route_far", n, "example states", dict(st), "hulls", dict(hulls))
    for s, e in ex: print("  ", s, e)