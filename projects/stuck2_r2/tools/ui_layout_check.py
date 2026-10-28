"""Checks the HUD layout: no text on top of other text, nothing cut off.

WHAT THIS IS: a checker for the UI tour's layout dump. The tour
(tests/ui_tour.gd) runs the game's HUD through its screens and, with
--dump-layout, prints one "UIDUMP" line for every control that is showing
(its place, size, text and a few facts about how it was laid out). This
script reads those lines, one tour at one window size, and reports what a
player would call "screens on top of each other, impossible to read".

HOW TO RUN IT (from the remake folder; "godot" is the Godot console
program). One run per role and window size, then the checker on the files:
    godot --headless --path . --fixed-fps 60 -- --auto --role=pilot --bot=tour --force-hud --seed=7 --test=ui_tour --dump-layout --ui-size=1366x657 > pilot.txt
    godot --headless --path . --fixed-fps 60 -- --auto --role=admiral --bot=tour --force-hud --seed=7 --test=ui_tour --dump-layout --ui-size=1366x657 > admiral.txt
    python -B -I tools/ui_layout_check.py pilot.txt admiral.txt
Each file is named in the report by its file name without the ending (so
name them "pilot" and "admiral", or "pilot_1366x657"). Options:
    --tol N       how many pixels of overlap to ignore (default 2)
    --summary     also print a count per kind of problem and per step
    --groups      also print the problems grouped by kind and HUD widget
    --selftest    check the checker itself on a made-up dump, then stop
The script needs nothing but Python itself.

WHAT IT REPORTS: one line per problem, for each step of the tour:
    OVERLAP  text or a self-drawn widget (minimap, ship readout) sits
             on other text that belongs to a different part of the tree
             (not its own parent or child), by more than --tol pixels in
             both directions;
    COVERED  text sits under a later-drawn panel with a solid box (the
             alpha of its fill is at least 0.5), so the panel hides it;
    OFFSCREEN  a control that shows (text, panel, bar, picture, widget)
             reaches outside the window;
    CRAMPED  text that cannot fit its control: the control is smaller
             than the smallest size it asks for, lines of text do not fit
             and are hidden, the text is taller or wider than its box, or
             the text lies outside the panel it belongs to.
Each line has the step, the window size, the two controls (their path in
the HUD, their class and the start of their text) and the size of the
overlap or how far out it goes. The script exits 1 if there is any
problem, 0 if the layout is clean and 2 if a file holds no dump.

HOW IT DECIDES WHAT IS SEEN: a control counts when it shows (the dump only
lists controls that show) and its see-through amount, multiplied up the
tree, is at least 0.2. A scroll area (or any control that clips) cuts
what is inside it to its own box, so a card scrolled out of sight is not
a problem. When a full-window panel with a dark fill (the end screen, the
start screen) is drawn over the HUD, the HUD underneath is dimmed on
purpose and is left out of the checks. Drawing order is tree order: a
control drawn later sits on top of one drawn earlier.
"""
import argparse
import json
import os
import re
import sys
import tempfile

## Controls that show text. (A Button's whole box is its text area.)
TEXT_CLASSES = {"Label", "RichTextLabel", "Button", "CheckBox", "CheckButton", "OptionButton",
                "MenuButton", "LinkButton", "LineEdit", "TextEdit"}
## Controls with their own script that draw themselves (class name from the
## dump's "cls=" fact): their box counts like text, since they draw text.
DRAWN_CLASSES = {"Minimap", "ShipStatus"}
## A box with at least this much fill (alpha, 0..1) hides what is under it.
SOLID_ALPHA = 0.5
## A box with at least this much fill is seen at all.
SEEN_ALPHA = 0.1
## A control more see-through than this (multiplied up the tree) is not seen.
MIN_ALPHA = 0.2
## A full-window panel covering at least this share of the window is a
## "modal": everything drawn before it is dimmed on purpose.
MODAL_SHARE = 0.9

HEAD_RE = re.compile(r"^UIDUMP (\S+) (\d+) (\w+) (-?\d+),(-?\d+) (-?\d+)x(-?\d+) mouse=-?\d+ focus=-?\d+ mod=([0-9a-f]{8})(.*)$")
VIEW_RE = re.compile(r"^UIVIEW (\S+) (\d+)x(\d+)")
TEXT_RE = re.compile(r' text=("(?:[^"\\]|\\.)*")')
PANEL_RE = re.compile(r" panel=flat\(([0-9a-f]{8}),")
COLOR_RE = re.compile(r" color=([0-9a-f]{8})$")
ALIGN_RE = re.compile(r" align=(\d+)")


class Node:
    """One control of one step: where it is, what it shows, how it was laid out."""

    def __init__(self, idx, depth, cls, x, y, w, h, alpha, rest):
        self.idx = idx
        self.depth = depth
        self.cls = cls
        self.x, self.y, self.w, self.h = float(x), float(y), float(w), float(h)
        self.alpha = alpha
        self.parent = -1
        self.text = None
        self.align = 0
        self.bg = None
        self.ext = {}
        main, _, ext = rest.partition(" |L| ")
        m = TEXT_RE.search(main)
        if m:
            try:
                self.text = json.loads(m.group(1))
            except ValueError:
                self.text = m.group(1)
        m = ALIGN_RE.search(main)
        if m:
            self.align = int(m.group(1))
        m = PANEL_RE.search(main)
        if m:
            self.bg = alpha_of(m.group(1))
        elif cls == "ColorRect":
            m = COLOR_RE.search(main)
            if m:
                self.bg = alpha_of(m.group(1))
        for word in ext.split():
            k, _, v = word.partition("=")
            self.ext[k] = v
        if "bg" in self.ext:
            self.bg = alpha_of(self.ext["bg"])

    def rect(self):
        return (self.x, self.y, self.x + self.w, self.y + self.h)

    def size_fact(self, key):
        """A fact written WxH (min, ink) as a pair of numbers, or None."""
        v = self.ext.get(key)
        if not v:
            return None
        a, _, b = v.partition("x")
        return float(a), float(b)

    def name(self):
        return self.ext.get("path", "#%d" % self.idx)

    def describe(self):
        cls = self.ext.get("cls", self.cls)
        s = "%s %s" % (self.name(), cls)
        if self.text:
            t = self.text.replace("\n", " / ")
            s += ' "%s"' % (t if len(t) <= 34 else t[:33] + "...")
        return s


def alpha_of(hex8):
    """The alpha (0..1) of a colour written rrggbbaa."""
    return int(hex8[6:8], 16) / 255.0


def intersect(a, b):
    """The overlap of two rectangles (x1, y1, x2, y2), or None when they do not meet."""
    x1, y1, x2, y2 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    if x2 <= x1 or y2 <= y1:
        return None
    return (x1, y1, x2, y2)


def read_steps(path):
    """The tour in a file: a list of [step name, window size or None, list of Nodes].
    A step dumped at several window sizes (the tour's --ui-size=A,B,C) gives one entry per size."""
    steps = []
    view = None
    cur = None
    stack = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\r\n")
            m = VIEW_RE.match(line)
            if m:
                # A UIVIEW line starts a new dump: its UIDUMP lines follow.
                view = (int(m.group(2)), int(m.group(3)))
                cur = None
                continue
            m = HEAD_RE.match(line)
            if not m:
                continue
            step, depth = m.group(1), int(m.group(2))
            if cur is None or cur[0] != step:
                cur = [step, view, []]
                view = None
                steps.append(cur)
                stack = []
            node = Node(len(cur[2]), depth, m.group(3), m.group(4), m.group(5), m.group(6), m.group(7),
                        alpha_of(m.group(8)), m.group(9))
            while stack and stack[-1][0] >= depth:
                stack.pop()
            node.parent = stack[-1][1] if stack else -1
            stack.append((depth, node.idx))
            cur[2].append(node)
    for s in steps:
        if s[1] is None and s[2]:
            root = s[2][0]
            s[1] = (int(root.w), int(root.h))
    return steps


class Problem:
    """One thing wrong on one step."""

    def __init__(self, kind, step, size, a, b, detail):
        self.kind, self.step, self.size, self.a, self.b, self.detail = kind, step, size, a, b, detail

    def line(self, label):
        s = "%-9s %s:%s %dx%d  %s" % (self.kind, label, self.step, self.size[0], self.size[1], self.a.describe())
        if self.b is not None:
            s += "  <>  " + self.b.describe()
        return s + "  " + self.detail


class Step:
    """One step of the tour, prepared for the checks (see check_step)."""

    def __init__(self, name, size, nodes):
        self.name, self.size, self.nodes = name, size, nodes
        n = len(nodes)
        # Who is whose ancestor, the see-through amount multiplied up the
        # tree, and the box each control is cut to by the clipping controls
        # above it (a scroll area cuts to its own box).
        self.anc = [set() for _ in range(n)]
        eff = [1.0] * n
        bound = [None] * n
        self.crect = [None] * n
        inf = (-1e9, -1e9, 1e9, 1e9)
        for nd in nodes:
            p = nd.parent
            if p >= 0:
                self.anc[nd.idx] = self.anc[p] | {p}
                eff[nd.idx] = eff[p] * nd.alpha
                parent_bound = bound[p]
            else:
                eff[nd.idx] = nd.alpha
                parent_bound = inf
            self.crect[nd.idx] = intersect(nd.rect(), parent_bound)
            clips = nd.ext.get("clip") == "1" or (nd.ext.get("clip") is None and nd.cls == "ScrollContainer")
            cut = intersect(parent_bound, nd.rect()) if clips else parent_bound
            bound[nd.idx] = cut if cut is not None else (0, 0, 0, 0)
        self.win = (0.0, 0.0, float(size[0]), float(size[1]))
        area = float(size[0] * size[1])
        # Panels that cover the whole window dim what was drawn before them;
        # that part of the HUD is left out.
        modals = [nd.idx for nd in nodes if nd.bg is not None and nd.bg >= 0.4 and nd.depth > 0
                  and nd.w * nd.h >= MODAL_SHARE * area]
        self.seen = [True] * n
        for nd in nodes:
            i = nd.idx
            if eff[i] < MIN_ALPHA or self.crect[i] is None:
                self.seen[i] = False
            elif any(m > i and m not in self.anc[i] and i not in self.anc[m] for m in modals):
                self.seen[i] = False
        # The kinds of control the checks need: text, self-drawn widgets,
        # solid panels (for COVERED), and everything that is seen (for
        # OFFSCREEN).
        self.texts, self.drawn, self.boxes, self.visual = [], [], [], []
        for nd in nodes:
            i = nd.idx
            if not self.seen[i]:
                continue
            has_text = nd.text is not None and nd.text.strip() != ""
            is_text = nd.cls in TEXT_CLASSES and (has_text or (nd.text is None and nd.cls in ("LineEdit", "TextEdit")))
            is_drawn = nd.ext.get("cls") in DRAWN_CLASSES
            if is_text:
                self.texts.append(i)
            if is_drawn:
                self.drawn.append(i)
            if nd.bg is not None and nd.bg >= SOLID_ALPHA and nd.w * nd.h < MODAL_SHARE * area:
                self.boxes.append(i)
            if is_text or is_drawn or nd.cls in ("Button", "ProgressBar", "TextureRect", "ColorRect") or (
                    nd.bg is not None and nd.bg >= SEEN_ALPHA):
                self.visual.append(i)

    def related(self, a, b):
        """Is one of the two controls an ancestor of the other?"""
        return a in self.anc[b] or b in self.anc[a]

    def hidden_by_panel_of(self, a, b, ink_a, tol):
        """Is `a` under a solid panel that is `b` or holds `b`, drawn after `a`?"""
        for x in [b] + sorted(self.anc[b]):
            if x in self.boxes and x > a and not self.related(a, x):
                o = intersect(ink_a, self.crect[x])
                if o is not None and o[2] - o[0] > tol and o[3] - o[1] > tol:
                    return True
        return False

    def problem(self, kind, a, b, detail):
        return Problem(kind, self.name, self.size, self.nodes[a], self.nodes[b] if b is not None else None, detail)


def ink_rect(nd, crect):
    """The part of a control's box that its text really takes, cut to what is visible."""
    x1, y1, x2, y2 = nd.rect()
    ink = nd.size_fact("ink") if nd.cls == "Label" else None
    if ink is not None:
        iw, ih = ink
        if 0 < iw < nd.w:
            if nd.align == 1:
                x1 += (nd.w - iw) / 2.0
            elif nd.align == 2:
                x1 += nd.w - iw
            x2 = x1 + iw
        valign = int(nd.ext.get("valign", "0"))
        if ih < nd.h:
            if valign == 1:
                y1 += (nd.h - ih) / 2.0
            elif valign == 2:
                y1 += nd.h - ih
            y2 = y1 + ih
    return intersect((x1, y1, x2, y2), crect)


def widget_of(nd):
    """The HUD widget a control belongs to: the first part of its path (MePanel, Feed, Hangar ...)."""
    return nd.name().split("/")[0]


def overlap_text(o):
    """An overlap rectangle as 'WxH px'."""
    return "by %dx%d px" % (round(o[2] - o[0]), round(o[3] - o[1]))


def check_step(name, size, nodes, tol):
    """Run every check on one step and return its problems."""
    st = Step(name, size, nodes)
    problems = []
    # Check 1: text (or a self-drawn widget) on other text. When the later
    # one sits inside a solid panel that also covers the earlier one, the
    # panel hiding it is the problem (check 2), so the pair is not listed.
    items = sorted(set(st.texts) | set(st.drawn))
    inks = {i: ink_rect(nodes[i], st.crect[i]) for i in items}
    for k, a in enumerate(items):
        if inks[a] is None:
            continue
        for b in items[k + 1:]:
            if inks[b] is None or st.related(a, b):
                continue
            o = intersect(inks[a], inks[b])
            if o is not None and o[2] - o[0] > tol and o[3] - o[1] > tol:
                if not st.hidden_by_panel_of(a, b, inks[a], tol):
                    problems.append(st.problem("OVERLAP", a, b, overlap_text(o)))
    # Check 2: text or a self-drawn widget under a later-drawn solid panel.
    for a in items:
        if inks[a] is None:
            continue
        for x in st.boxes:
            if x <= a or st.related(a, x):
                continue
            o = intersect(inks[a], st.crect[x])
            if o is not None and o[2] - o[0] > tol and o[3] - o[1] > tol:
                problems.append(st.problem("COVERED", a, x, overlap_text(o)))
    # Check 3: anything that shows but reaches outside the window. A control
    # inside one that is already out is not reported again.
    out = {}
    for i in st.visual:
        r = st.crect[i]
        sides = []
        for label, amount in (("left", st.win[0] - r[0]), ("top", st.win[1] - r[1]),
                              ("right", r[2] - st.win[2]), ("bottom", r[3] - st.win[3])):
            if amount > 1.0:
                sides.append("%s %dpx" % (label, round(amount)))
        if sides:
            out[i] = sides
    for i, sides in out.items():
        if not (st.anc[i] & set(out)):
            problems.append(st.problem("OFFSCREEN", i, None, "outside the window: " + ", ".join(sides)))
    # Check 4: text that cannot fit.
    for i in st.texts:
        why = cramped(st, i, tol)
        if why:
            problems.append(st.problem("CRAMPED", i, None, "; ".join(why)))
    return problems


def cramped(st, i, tol):
    """The reasons text control `i` cannot fit (an empty list when it fits)."""
    nd = st.nodes[i]
    why = []
    mn = nd.size_fact("min")
    if mn is not None and (mn[0] > nd.w + 1 or mn[1] > nd.h + 1):
        why.append("needs %dx%d but has %dx%d" % (round(mn[0]), round(mn[1]), round(nd.w), round(nd.h)))
    lines, vis = nd.ext.get("lines"), nd.ext.get("vis")
    if lines and vis and int(vis) < int(lines):
        why.append("%d of %s lines hidden" % (int(lines) - int(vis), lines))
    ink = nd.size_fact("ink")
    if ink is not None:
        if ink[1] > nd.h + 1:
            why.append("text %dpx tall in a %dpx box" % (round(ink[1]), round(nd.h)))
        if ink[0] > nd.w + 1:
            why.append("text %dpx wide in a %dpx box" % (round(ink[0]), round(nd.w)))
    panel = nearest_box(st.nodes, i)
    if panel is not None:
        pr, r = st.nodes[panel].rect(), st.crect[i]
        gaps = [("left", pr[0] - r[0]), ("top", pr[1] - r[1]), ("right", r[2] - pr[2]), ("bottom", r[3] - pr[3])]
        bad = ["%s %dpx" % (k, round(v)) for k, v in gaps if v > tol]
        if bad:
            why.append("outside its panel: " + ", ".join(bad))
    return why

def nearest_box(nodes, i):
    """The nearest ancestor with a seen box (a panel), or None."""
    p = nodes[i].parent
    while p >= 0:
        if nodes[p].bg is not None and nodes[p].bg >= SEEN_ALPHA:
            return p
        p = nodes[p].parent
    return None


def selftest():
    """Run the checks on a small made-up dump: a clean one and one with each fault."""
    def line(step, depth, cls, x, y, w, h, extra="", ext=""):
        return "UIDUMP %s %d %s %d,%d %dx%d mouse=2 focus=0 mod=ffffffff%s%s" % (
            step, depth, cls, x, y, w, h, extra, (" |L| " + ext) if ext else "")
    t = ' text="%s" size=12 color=ffffffff align=0 wrap=0'
    panel = " panel=flat(112233cc,ffffffff,b1111,r4,m8/8/8/8)"
    good = [line("ok", 0, "Control", 0, 0, 800, 600, "", "path=. clip=0 min=0x0"),
            line("ok", 1, "Label", 10, 10, 100, 20, t % "alpha", "path=A clip=0 min=100x20 valign=0 lines=1 vis=1 ink=100x16"),
            line("ok", 1, "Label", 10, 40, 100, 20, t % "beta", "path=B clip=0 min=100x20 valign=0 lines=1 vis=1 ink=100x16")]
    bad = [line("bad", 0, "Control", 0, 0, 800, 600, "", "path=. clip=0 min=0x0"),
           line("bad", 1, "Label", 10, 10, 100, 20, t % "alpha", "path=A clip=0 min=100x20 valign=0 lines=1 vis=1 ink=100x16"),
           line("bad", 1, "Label", 50, 15, 100, 20, t % "beta", "path=B clip=0 min=100x20 valign=0 lines=1 vis=1 ink=100x16"),
           line("bad", 1, "PanelContainer", 5, 5, 300, 60, panel, "path=P clip=0 min=0x0 bg=112233cc"),
           line("bad", 1, "Label", 780, 580, 100, 30, t % "gamma", "path=C clip=0 min=100x50 valign=0 lines=3 vis=2 ink=100x48")]
    fd, tmp = tempfile.mkstemp(suffix=".txt")
    os.close(fd)
    ok = True
    try:
        for name, lines, want in (("good", good, set()),
                                  ("bad", bad, {"OVERLAP", "COVERED", "OFFSCREEN", "CRAMPED"})):
            with open(tmp, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
            got = set()
            for step in read_steps(tmp):
                got |= {p.kind for p in check_step(step[0], step[1], step[2], 2.0)}
            if got != want:
                print("selftest %s: wanted %s, got %s" % (name, sorted(want), sorted(got)))
                ok = False
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print("selftest " + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description="Check the HUD layout dump of the UI tour.")
    ap.add_argument("files", nargs="*", help="dump files (the output of the tour with --dump-layout)")
    ap.add_argument("--tol", type=float, default=2.0, help="pixels of overlap to ignore (default 2)")
    ap.add_argument("--summary", action="store_true", help="also print the count per kind and step")
    ap.add_argument("--groups", action="store_true", help="also print the problems grouped by kind and HUD widget")
    ap.add_argument("--selftest", action="store_true", help="check the checker on a made-up dump")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not args.files:
        ap.error("give at least one dump file")
    total = 0
    empty = False
    counts = {}
    groups = {}
    for path in args.files:
        label = os.path.splitext(os.path.basename(path))[0]
        steps = read_steps(path)
        if not steps:
            print("NO DUMP: %s holds no UIDUMP lines" % path)
            empty = True
            continue
        if not any("path" in nd.ext for nd in steps[0][2]):
            print("NOTE: %s has no layout facts (run the tour with --dump-layout); fewer checks apply" % label)
        for name, size, nodes in steps:
            for p in check_step(name, size, nodes, args.tol):
                print(p.line(label))
                total += 1
                key = (p.kind, label + ":" + name + " %dx%d" % size)
                counts[key] = counts.get(key, 0) + 1
                gkey = (p.kind, widget_of(p.a), widget_of(p.b) if p.b is not None else "")
                groups.setdefault(gkey, []).append(label + ":" + name)
    if args.summary:
        for (kind, where), k in sorted(counts.items(), key=lambda kv: (kv[0][1], kv[0][0])):
            print("  %-9s %-40s %d" % (kind, where, k))
    if args.groups:
        for (kind, wa, wb), where in sorted(groups.items()):
            steps = sorted(set(w.split(":", 1)[1] for w in where))
            print("  %-9s %-16s %-16s %3d problems; steps %s" % (kind, wa, wb, len(where), ",".join(steps)))
    if empty:
        return 2
    print("UI LAYOUT: " + ("%d problems" % total if total else "clean"))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
