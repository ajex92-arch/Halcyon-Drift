# Salvage what the stopped deep-dive investigators learned:
#  1. from each agent transcript: a one-line log of every tool call and the
#     last assistant texts/thoughts  -> salvage/<label>_notes.md
#  2. the code they changed in their copies (dd_<d>, dd_<d>_fix) vs dd_base,
#     scripts/ only, as unified diffs -> salvage/<d>_diff.md
import difflib, json, os, re, sys

SP = sys.argv[1]
TR = sys.argv[2]
OUT = os.path.join(SP, "deepdive", "salvage")
os.makedirs(OUT, exist_ok=True)
index = []

for fn in sorted(os.listdir(TR)):
    if not (fn.startswith("agent-") and fn.endswith(".jsonl")):
        continue
    meta_p = os.path.join(TR, fn.replace(".jsonl", ".meta.json"))
    label = fn
    try:
        meta = json.load(open(meta_p, encoding="utf-8"))
        label = str(meta.get("label") or meta.get("description") or meta)
    except Exception:
        pass
    calls, thoughts = [], []
    for line in open(os.path.join(TR, fn), encoding="utf-8", errors="replace"):
        try:
            o = json.loads(line)
        except Exception:
            continue
        msg = o.get("message") or {}
        if o.get("type") != "assistant" or not isinstance(msg.get("content"), list):
            continue
        for b in msg["content"]:
            t = b.get("type")
            if t == "tool_use":
                inp = b.get("input") or {}
                s = inp.get("command") or inp.get("file_path") or inp.get("pattern") or json.dumps(inp)[:200]
                calls.append("%s: %s" % (b.get("name"), re.sub(r"\s+", " ", str(s))[:220]))
            elif t == "text" and b.get("text", "").strip():
                thoughts.append(("TEXT", b["text"].strip()))
            elif t == "thinking" and b.get("thinking", "").strip():
                thoughts.append(("THINK", b["thinking"].strip()))
    safe = re.sub(r"[^A-Za-z0-9_-]+", "_", label)[:40]
    p = os.path.join(OUT, safe + "_notes.md")
    with open(p, "w", encoding="utf-8") as f:
        f.write("# %s (%s)\n\n## Tool calls (%d, last 120)\n\n" % (label, fn, len(calls)))
        for c in calls[-120:]:
            f.write("- " + c + "\n")
        f.write("\n## Last texts/thoughts (of %d)\n\n" % len(thoughts))
        for kind, txt in thoughts[-14:]:
            f.write("### %s\n\n%s\n\n" % (kind, txt[:3000]))
    index.append("%-44s %7d bytes  calls=%d thoughts=%d" % (os.path.basename(p), os.path.getsize(p), len(calls), len(thoughts)))

base = os.path.join(SP, "dd_base")
for d in ["flight", "behavior", "targeting", "minions", "admiral"]:
    parts = []
    for copy in ["dd_" + d, "dd_" + d + "_fix"]:
        root = os.path.join(SP, "notate", copy)
        if not os.path.isdir(root):
            continue
        new_tests = []
        for dirpath, _, files in os.walk(root):
            for name in files:
                if not name.endswith((".gd", ".tscn", ".py")):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, root)
                other = os.path.join(base, rel)
                if rel.startswith("tests") or rel.startswith(".godot"):
                    if not os.path.exists(other) and rel.startswith("tests"):
                        new_tests.append(rel)
                    continue
                a = open(other, encoding="utf-8", errors="replace").read().splitlines() if os.path.exists(other) else []
                b = open(full, encoding="utf-8", errors="replace").read().splitlines()
                if a != b:
                    diff = list(difflib.unified_diff(a, b, "base/" + rel, copy + "/" + rel, n=2, lineterm=""))
                    parts.append("### %s : %s\n\n```diff\n%s\n```\n" % (copy, rel, "\n".join(diff)))
        if new_tests:
            parts.append("### %s : new test files\n\n%s\n" % (copy, "\n".join("- " + t for t in sorted(new_tests))))
    p = os.path.join(OUT, d + "_diff.md")
    with open(p, "w", encoding="utf-8") as f:
        f.write("# Code changes in the %s copies vs dd_base\n\n" % d + ("\n".join(parts) if parts else "(none)\n"))
    index.append("%-44s %7d bytes" % (os.path.basename(p), os.path.getsize(p)))

print("\n".join(index))

