STATUS: 21:55. FINISHED. Everything is in this file (summary right below the title), dd_flight_fix is synced and compiles (--ff=ABDEIUMOX), diff in deepdive\flight_fixes_diff.md, tools in deepdive\tools_flight.

# Flight and pathing deep dive: findings (investigator 2)

## SUMMARY (final, 21:55)

Recommended switch string for the flight copy (notate\dd_flight_fix, all synced, compiles): --ff=ABDEIUMOX
(R optional, V rejected, H dropped). Full-set run, 6 seeds, 900 s, base = same probe without letters
(runs\fl ab_s5base vs ab_ffABDEIUMOXm), base > full set, seeds lower/higher, paired t:
  stuck episodes 209 > 64 (-69%, 6/0, t -10.1)      stuck seconds 3274 > 370 (-89%)       unstick fires -47% (6/0)
  ships trapped (5+ unsticks in 90 s) 24 > 7 (-71%, 6/0)   trapped ship-seconds 2172 > 1032 (-53%)   pinned seconds -78%
  rock contact 7425 > 2895 s (-61%)   while fighting 2994 > 1097 s (-63%)   crash events -40%   crash deaths 28 > 3 (-89%)
  occluded firing 4024 > 135 (-97%)   big ships hold-far-not-approaching 1413 > 356 (-75%)   waypoint orbits 88 > 23 (-74%)
  late game (3 seeds, 25:00 + 300 s): stuck episodes 69 > 25, rock contact 935 > 140 s, pilot deaths 83 > 55
  CAUTION: pilot deaths 447 > 524 (+17%, higher in 6 of 6 seeds), deaths to other pilots 306 > 391 (+28%), to turrets 11 > 25,
  to minions 95 > 99; retreat trips ending in death 408 > 497. The single fixes each moved this by 0-4% (A +4%, I +3%),
  the bundle by +28%: pilots that are no longer stuck, crashing or shooting rocks find each other more. This is a change of
  the match itself (more fighting), not noise; the lead should know the fun measurement is taken on a livelier AI.
Where the numbers come from: tests/fl_audit.gd (probe, superset of ab_audit), tests/escape_bench.gd, tests/wall_duel.gd
(micro benches; the first escape_bench numbers, with ships of the wrong team under enemy turrets, were invalid and are
not used), tools_flight\ (geo.py static map tools, paired.py, fl_report.py ...), code diff in deepdive\flight_fixes_diff.md.

Fixes and verdicts
  A  keep (UPGRADED): removes the gate/camp-approach crash and the lance-jungler trap (FL-A3); stuck seconds -56% (6/6).
  B  keep (modest): occluded firing -31%, crash deaths -46%, rock contact while fighting -26%.
  D  keep: hold far not approaching -74% (6/6).   E  keep: stuck episodes -33% (6/6), crash deaths -57%.
  H  DROP (FL-H1: jungle-route chase and arrival-park hover, rock contact while fighting x4.2).
  I  keep, replaces H: occluded firing -95%, rock contact while fighting -47%, crash deaths -50% (FL-I).
  U  keep: escape planner for ships stuck in notches (FL-T); V (crumb retrace) rejected (made trapping worse).
  M  keep: seal 464 rock gaps of 17.5-34 units, ships wedge between rocks that are 24-26 apart (FL-T2).
  O  keep (small): corner/gate speed limit (FL-G).    X keep (small): bomber waypoint reach (FL-B2).
  R  optional: route cost = flying time: orbits -91%, crash deaths -86%, home/retreat trip tails -22..-31%, but pilot deaths +8%.
Open (not fixed): big ships trapped beside their own mothership (flak frigates at (35266,12831) etc.), bombers in the south
rim, concave wall notches that no grid cell resolves, 53% -> 62% of retreating ships die (a behaviour matter).

Working copy: notate\dd_flight_fix (switch --ff=<letters>; A, B, D, E, H from the first round, new letters below).
Run snapshots (frozen copies so edits never change queued runs): notate\dd_flight_s1, s2, ...
Probe: tests/fl_audit.gd (superset of ab_audit, counters "x_*", trip lists in examples x_trips_*).
Instrumentation added to game code (changes nothing): PilotFlight.dbg, dbg_plans, dbg_unsticks.




## FL-H1 (major, PROVEN): why fix H scrapes rocks

Code (dd_flight_fix pilot_combat.gd fight(), pilot_flight.gd travel()):
    if brain.flight.ff("H") and brain.flight.target_line_blocked(ship, tp):
        brain.flight.travel(ship, tp, 300.0)      # no firing, no dogfight movement
travel() follows a route whenever `p.distance_to(to) > 2500.0 or not world.map.in_open_lane(p)`. A strike craft
fighting near the lane wall (a few dozen units outside the 200-unit open-lane grid, i.e. in the wall zone) is "not
in the open lane", so H sends it along the JUNGLE route graph toward the target (a ship across the wall), through
86-wide gates and rock fields at jungle speeds. The same travel() also has `arrive` = 300: once within 300 of the
target with the line still blocked, it brakes and hovers, never firing and never dogfighting, for as long as the
target stays hidden. Both together make long "episodes".
Measured with the new probe tests/fl_audit.gd (runs\fl, tags ab_ffH, seeds 7+13, 900 s, same matches as ab_ffH in
runs\ab: the AUDIT lines are identical):
- seed 7: mode fight_h_route = 3409 ship-s, of which 2229 s (65%) in rock contact, mean speed 59 u/s; 471 H
  episodes, but 21 lasting > 30 s hold 132,164 of 139,820 contact ticks (94.5%); 81% of H ticks are within 300 of
  the target at < 60 u/s. Contact by place: jungle 158k ticks (fight_h_route 132k), gate 8.6k, lane 5.7k. The H
  pilots are lane-state laners (goal_kind "station"). Example: Tamsin pinned 91.8 s at (16629,14879) (a notch just
  inside the mid-lane south wall), target 254 units away across the wall, flown 24 units.
- seed 13: fight_h_route 1120 s, 499 s (44.5%) in contact; 11 episodes > 30 s = 75% of the contact.
- the mode flips fight_dog <-> fight_h every ~0.25 s (the 4 Hz blocked cache), 220-250 flips per 900 s per kind.
- base (same seeds): rock contact while fighting 693 s per 2 seeds; H 2935 s (x4.2).
Controlled check (tests/wall_duel.gd, 37 one-on-one duels with a rock between, lane): H alone contact x6 (170 s vs
28), H+A (A routes in the open lane) fine (27 s vs 24; occluded firing 77 -> 1). So in the open lane the routing
idea works; in the wall zone and jungle it does not.
Fix: fix I below (hold fire + give up a target hidden for 3 s) replaces H.

## FL-A2 (answer to task 2): fix A does NOT lengthen home trips

Probe tests/fl_audit.gd, 900 s, seeds 7+13 (runs\fl): home trips, small ships, straight = hull distance minus
468 (the dock reach):
                       base (22 docked)       A (23 docked + 2 never docked)
  duration p50/p90/max  28.0 / 50.9 / 52.3     25.2 / 58.4 / 76.5
  dur / (straight/640)  p50 1.55, p90 2.06     p50 1.45, p90 2.13
The extra "home" samples (1257 -> 3591) are TWO ships trapped in rock notches for the rest of the match while in
state home: seed 7 (12402,7834) 480 s, 96 unsticks, 259 s in rock contact; seed 13 (16557,15765) 552 s, 106
unsticks, 325 s contact. Together 1033 s of the 1840 s A spent in "home". The same notches trap ships in the base
runs too (ab_base stuck examples: Brand 175 s at (23.3k,15.0k); Marlin, Lark ...): the victims differ with the
chaos of each match. Also, A's own mechanism is rare: mode "routeA" (a short hop routed only because the line is
blocked) = 67 ship-s in 2 x 900 s (0.15% of ship time), so most of A's differences in ab_audit counters are
chaos, not A. (See FL-T below for the notch traps.)

## VERDICTS for fixes A, B, D, E (6 seeds 7,11,13,17,19,23, 900 s, ab_audit, paired by seed; runs\ab)

Sums over 6 seeds, base > fix, then "seeds lower/higher" and a paired t over the 6 per-seed differences (|t| >= 2.6
is p < 0.05 for 5 degrees of freedom). Matches diverge chaotically, so counters dominated by a few long-trapped
ships (stuck seconds, home samples) are noisy; episode counts and deaths are steadier.
                              base   A           B           D           E
 stuck episodes               209    162 (3/3)   181 (3/2)   147 (5/1)   139 (6/0, t -3.3)
 stuck seconds               3274   1450 (6/0)  3498 (2/3)  2872 (4/2)  2748 (4/2)
 rock contact ship-s         7424   5924 (5/1)  6780 (4/2)  6568 (4/2)  6158 (5/1)
 rock contact while fighting 2993   2999 (3/3)  2205 (5/1)  2460 (3/3)  2540 (3/3)
 occluded fight samples     13652  13863 (2/4) 10712 (5/1) 13695 (2/4) 11578 (4/2)
 occluded while firing       4024   3955        2777 (5/1)  3958        3782
 hold far, not approaching   1413    911 (5/1)  1100 (5/1)   367 (6/0, t -5.2)  1092 (5/1)
 crash deaths                  28     16 (4/1)    15 (4/0)    21 (3/0)    12 (5/1, t -3.0)
 turret deaths                 11     13          20          21          24 (0/6, t 3.3)
 pilot deaths                 447    458         446         447         462
 samples in state home       5094   8592        6464        5407        5013
- D: KEEP. The only fix that changes its own target metric overwhelmingly (hold far not approaching -74%, 6 of 6
  seeds); also stuck episodes -30%, crash deaths -25%, rock contact while fighting -18%. No metric worse except the
  noise-level ones below.
- E: KEEP. stuck episodes -33% (6/6 seeds), crash deaths -57% (5/6), rock contact -17%, stuck seconds -16%.
- B: KEEP (modest). Occluded firing -31% (5/6), occluded samples -22%, rock contact while fighting -26% (5/6), crash
  deaths -46% (4/0), hold far not approaching -22%; stuck seconds +7% (n.s.). It only edits the route graph (check
  route_probe after: done by the earlier investigator).
- A: KEEP, low risk, but expect small effects. stuck seconds -56% (6/6 seeds), rock contact -20%, crash deaths -43%,
  hold far not approaching -36%. Its own mechanism ("routeA": a short hop routed only because the line is blocked) is
  active only 0.15% of ship time, so the benefit comes from a few deterministic traps (a station behind a wall
  piece, a stuck ship in base for 700 s) being routed once. The worse counters (home samples +69%, home target in
  reach 144 > 289) are explained by two ships trapped in notches in state home (see FL-A2); not caused by A.
- All four change the number of turret deaths upwards (11 > 13/20/21/24; base per seed 2,0,0,2,1,6) while pilot
  deaths stay equal (447 vs 446-462): ships that no longer get stuck or crash spend more time near turrets. Not a
  bug; E is 6/6 seeds higher, so watch it (small counts).
- H: DROP (see FL-H1). Replacement: fix I (below).



## FL-I (fix I, replaces H): hold fire at a hidden target, give it up after 3 s  [19:56]

Code (dev copy, behind --ff=I; 3 files): pilot_combat.gd fight(), strike craft branch (before the dogfight):
    hidden = brain.flight.target_hidden(ship, tp)          # segment_blocked for a bullet, cached 4 Hz, counts seconds
    if hidden and brain.flight.hidden_t > 3.0:
        brain.skip_id = target.get_instance_id(); brain.skip_until = world.time + 6.0
        brain.target = null; brain.lock_target = null
        brain.flight.travel(ship, brain.goal, 160.0); c.aim_point = c.face_point; return
    ... (normal dogfight / bomber movement) ... then  if hidden: c.fire = false (and the bomber's special)
pilot_targeting.gd pick_target(), prey(), push_target() and pilot_goals.gd think_jungle() skip the unit while
world.time < brain.skip_until (3 one-line guards; skip_id/skip_until are new fields in pilot_ai.gd). No routing at all,
so none of H's failure modes (jungle route chase, arrival-park hover) exists.
6 seeds (7,11,13,17,19,23; runs\ab ab_ffI, base = ab_base), base > fix, seeds lower/higher, paired t:
  occluded firing 4024 > 209 (-95%, 6/0, t -6.9)       occluded fight samples 13652 > 8350 (-39%, 5/1)
  rock contact while fighting 2993 > 1579 s (-47%)      all rock contact 7424 > 5493 s (-26%)
  crash deaths 28 > 14 (-50%, 5/0, t -2.5)              stuck episodes 209 > 167 (-20%)
  fight samples 99955 > 97440 (-3%)   pilot deaths 447 > 453 (+1%)   target switches +7%   turret deaths 11 > 14
Verdict: KEEP I (replaces H). It keeps H's good part (no shots into rocks: -95%) and does not scrape (H: x4.2, AH x2.9).
Not fixed by I: ships trapped in notches (home samples +54%, home target in reach 144 > 942: a few long-trapped ships,
see FL-T); that is what fix U is for.

## FL-T (major, PROVEN): ships get trapped in rock notches for the rest of the match  [20:17]

What happens: a strike craft ends up pressed into a notch of the lane wall or a rock cluster. The stuck timer
(pilot_flight.gd travel(), _stuck_t > 4.0) then reverses for 1 s and plans the SAME route again from the same place
(rain.path = PackedVector2Array(); brain.path_goal = Vector2.INF), which sends it back into the notch: 96-140 unsticks
and 260-650 s of rock contact per trapped ship. A* only joins the graph at the nearest dot "in sight" (route_graph.gd
nearest(): first of the 8 nearest dots with a clear line), which can lie on the far side of the wall; no local planner
exists between the ship and that dot.
Evidence (fl_audit, 900 s, seeds 7+13; trips that never finished):
  base seed 7: bomber retreating 496 s, 488 s in contact, 98 unsticks;  A seed 7: fighter 480 s / 259 s / 96;
  A seed 13: fighter 552 s / 325 s / 106;  I seed 13: fighter 700 s / 654 s / 140 (home state, (23328,20151));
  AH seed 7: 405 s / 405 s / 81. Roughly 1 ship in every 1-2 matches is trapped from minute 4-7 to the end of a 15
  minute run, so in a 40 minute match several pilots would be gone. These ships also explain the odd "home" numbers
  (home samples +69% for A, +54% for I, home target in reach 144 > 942): a trapped ship that happens to be in
  state home (shopping trip) or retreat.
Places repeat exactly (the map is the same every match): clustering the first stuck/pinned examples of 122 logs gives
  (23398,15032) 13 logs, (23234,15887) 21, (16771,15894) 12, (12529,7835) 10, (16660,7607) 11, (25125,11130) 11,
  (18257,19059) 16, (27471,7835) 20, (20640,1472) 16, ... (see tools_flight\trap_clusters.json).
  Static geometry (tools_flight\geo.py, tight_cavities.json): 398 rock pairs have a gap of 24-38 units (a fighter is
  24 across), and 26 of them (13 mirrored pairs) lead into a sealed pocket, e.g. rocks 311+1651 at (23295,15049),
  rocks 583+2009 (22.9 wide) at (23328,20151). Fighters and lances can squeeze in but cannot get out.
Fix U (dev copy, --ff=U; pilot_flight.gd _note_unstick / _plan_escape / _follow_escape / _retrace): when the stuck timer
fires a second time within 25 s and 300 units, lay a grid (cells about 1.2 ship radii, 1,400-2,200 square) over the
rocks, flood it from the ship's cell, and fly (slowly, 170 u/s) the pulled-tight path to the first cell that has a
clear line to one of the 8 nearest route dots; the route is then planned FROM that dot. If the ship is wedged so tight
that the grid sees no room, it backs out along its own last 24 crumbs (one per 80 units) and plans again from the free
spot. An escape that makes no progress for 2 s is aborted (no new one for 15 s). Cost 15-40 ms per plan.
Bench (tests/escape_bench.gd, ships put at 12 recorded trap spots with their home team, 60 s, seed 1):
  base: 8 of 12 reach a point 1.5-3.5 km away, 177 s rock contact, 52 unsticks;
  U:   11 of 12, 106 s contact, 23 unsticks (the notch at (23300,15050) and the 700 s pocket (23328,20151, reached at
       58 s) remain slow). Matches: see the bundle results below.
Fix M (--ff=M, asteroid_field.gd widen_tight_gaps, called from world_setup.gd after the rocks are built): shrinks both
rocks of the 13 mirrored pairs listed in TIGHT_GAPS so their gap becomes 60 (fighters pass, a corvette at 88 across
still cannot). 26 rocks change by 7-18 units of radius (5-12%), nothing else.

## FL-G (major, PROVEN in a bench, fix O): the first jungler crashes at the same gate wall every match; lances get trapped  [20:17]

Code: pilot_flight.gd travel(): the jungle speed limit applies only to ships NOT in the open lane (in_jungle), boost is
allowed on the lane (c.boost = ... and not in_jungle), and a route waypoint is flown at full speed (braking only on the
LAST leg). The route (map_builder_route.gd step 4) joins a lane dot on the lane centre line to a dot inside the jungle with
ONE straight link about 2 km long through the gate's 101-unit choke. A ship coming down the lane at boost speed (900-1,000
u/s, turning circle about 300) must turn about 100 degrees at the lane dot, and its velocity lags its nose for a second or
two (flight assist), so it swings 150-350 units wide of the 2 km axis and meets the wall beside the choke.
Evidence: every log shows the fighter jungler (Marlin; Lark on the other side) crashing at t = 13.0 s at (8259,18230) /
(31712,18239) in route mode (x_crash example, identical in all 122 logs: deterministic). Later the lance junglers are
trapped there: stuck/pinned examples at (8366,18234) in 62 logs and (31634,18234) in 70 of 122 (first 12 examples per
log only). The lance is 13 radius, so it wedges where the 12-radius fighter slides through.
Reproduction (escape_bench, ships launched from the mothership bow to the camp goal 5 times, 60 s, seed 1):
  fighter: 5 of 5 arrive in 17 s, 1 crash each (545 u/s), 3.2 s contact total
  lance:   3 of 5 arrive, 2 jammed (45 s and 35 s of contact, 9 unsticks each)
  bomber:  1 of 5 arrive.
Fix O (--ff=O, pilot_flight.gd end of travel(): "Fix O"): on a routed leg, if the turn at the waypoint is over 0.7 rad or
the waypoint after it is inside the jungle (a gate), cap the speed at 28-45% of top speed (38% in the last 1,000 units
before the jungle waypoint) and start braking in time (0.8 of the reverse thrust). Bench result with O:
  lance 5 of 5 arrive (18.6 s), contact 82 s -> 0.5 s;  fighter 5 of 5, contact 3.2 s -> 0.5 s;  bomber 3 of 5, mean time
  54 -> 33 s.  The fighters still touch the wall once (545 u/s at the notch) because the approach line is off the axis;
  a "mouth dot" in the route graph (tried as fix G: an extra dot 300 before the choke, reach 40) made it WORSE (fighters
  3 of 5, lances 4 of 5, more unsticks: ships cannot hit a 40-unit reach at speed and circle). G was removed again.
Also confirmed the same gate-corner pattern in the retreat crash deaths (x_crash examples of crash_death at
(23849,5601), (23853,5602), (19820,12606) ...: boost speed 500-900 at a gate or the Crossing ore field).

## BUNDLE I+U+M (snapshot s5, fl_audit, 6 seeds 7,11,13,17,19,23, 900 s; base = the same probe with no letters, which
## reproduces the lead's ab_base counters exactly)  [20:38]
 metric (6 seeds)                       base   I+U+M                    seeds lower/higher, paired t
 stuck episodes                          209    119 (-43%)               6/0  t -4.3
 ships trapped (>=5 unsticks in 90 s)     24     12 (-50%)               5/0  t -3.5
 trapped ship-seconds                   2172   1060 (-51%)               4/2
 rock contact ship-s                    7425   5392 (-27%)               6/0  t -2.9
 rock contact while fighting s          2994   1624 (-46%)               6/0  t -2.2
 occluded firing                        4024    187 (-95%)               6/0  t -7.1
 occluded fight samples                13652   7982 (-42%)               6/0  t -2.8
 hold far, not approaching              1413    804 (-43%)               6/0  t -2.3
 pinned seconds                         4980   3590 (-28%)               5/1  t -2.0
 crash deaths                             28     22 (-21%)               4/2
 pilot deaths                            447    456 (+2%)                2/4  (unchanged)
 fight samples                         99955  96515 (-3%)                5/1
 turret deaths                            11     27 (+145%)              0/5  t +3.5   <- see below
 orbit episodes (>=3 s near a waypoint)   88    109 (+24%)               2/4
U: 61 escapes planned, 421 plans that found nothing (before the crumb retrace was added, see FL-T); a 600 s seed-7 run
with the final U: 138 escapes, 10 failures (8 aborts, mostly bombers at gates), 3 ships trapped.
Turret deaths: every variant I ran has more than the base (A 13, B 20, D 21, E 24, I 14, I+U+M 27 vs base 11; per seed
base 2,0,0,2,1,6): ships that no longer sit stuck spend more time near enemy turrets; pilot deaths overall are equal
(447 vs 456) and deaths to pilots fell 4%. Not a defect of one fix; the base looks unusually low on this small count.

## FL-T2 (root cause of the notch traps) and fix M2 (supersedes the 13-pair M above)  [20:53]

Why plain unstick/U cannot free some ships: every recorded trap position TOUCHES TWO ROCKS AT ONCE (tools_flight\overlap.py,
edge gap of the ship's 12-unit circle to the two nearest rock physics circles): (12529,7835) -0.6 / +0.3; (23328,20151)
-0.3 / +0.3; (16557,15765) -0.5 / +0.4; (21724,19057) +0.2 / +0.7; (23398,15032) -0.7 / +0.5; (23414,15046) -14 / +0.2.
So the ship has flown into a gap between two rocks that is 24-26 units wide (a fighter is 24 across, a lance 26) and sits
wedged: its free space is a line, thinner than any grid cell; reversing/strafing (unstick) or a grid search from there
cannot succeed, and the pilot code flies the straight line to its next waypoint, which leads through such gaps again.
The map has 398 gaps of 24-38 units (tools_flight\seal_sim.py: 413+ of them in the range 17.5-34).
Fix M2 (--ff=M, asteroid_field.gd seal_tight_gaps(), called from world_setup.gd after build()): grow both rocks of every
ordinary pair whose gap is 17.5-34 until the gap is 17 (a scout, 18 across, no longer fits), up to 4 sweeps (growing a
rock narrows its other gaps): 464 gaps sealed, about 720 rocks change by 6.5 units on average (25 at most), ore rocks are
not touched. Static check: 0 jungle route edges become impassable for radius 17, 0 gaps left in the range, gate choke
(101) untouched. Cost at startup about 0.1 s. Sealing, not widening, so no new passage appears in any wall.
Remaining trap types (not fixed): concave notches in walls that are open to the sky (U handles most); bombers at gates
(see FL-B2).

## FL-B2 (minor/major, PROVEN in the bench, fix X): bombers circle jungle waypoints and jam at gates  [20:59]

Code: pilot_flight.gd travel(): 
each = 110.0 for any waypoint in or next to the jungle ("Thread jungle gates precisely").
A bomber turns at 1.15 rad/s (ships.gd) and the jungle speed limit is 55% + 15%*skill of 400 = about 260 u/s, so its
turning circle is 226 units across: a 110-unit reach cannot be hit, the ship circles the waypoint, the stuck timer fires,
and so on. Evidence (fl_audit, orbit episodes = 3 s or more within 450 of the same route waypoint): base 6 seeds 88
episodes; of the stored examples 22 of 24 (base seeds 7+11) and 37 of 47 (I+U+M) are bombers, in the jungle and at gates
(e.g. Kestrel at (18435,18411) beside gate bl@18400,18400 trapped ~100 s; Coil at (28560,20119)).
Fix X (--ff=X, same function): a ship with f_turn < 2 (bomber) uses reach = clamp(f_max*0.65/f_turn, 110, 300) (226 for
a bomber). Bench (escape_bench, 8 lane-change trips mid lane -> other lanes through the jungle, 150 s):
  bomber: base 7 of 8 arrive (one jammed, 8 unsticks), mean 39.7 s;  X: 8 of 8, 37.7 s, 4 unsticks;
          O+X: 8 of 8, mean 33.6 s, 0 unsticks, 0.4 s contact.
  fighter + lance, 10 trips (8 lane changes + 2 base-to-camp): fighter 10/10, 20.3 -> 19.6 s, contact 2.0 -> 0.8 s;
          lance 8/10 -> 10/10, contact 170 s -> 0.4 s, unsticks 34 -> 0 (this is fix O, the lance jungler trap).
Tried and dropped: fix P (bombers use the lane-only graph from the open lane): a lane change then goes the long way,
only 1 of 5 trips arrived in 150 s in a 5-ship bench (an isolated bomber arrived at 62 s vs 46 s through the jungle).
Fix G (gate mouth dot) and fix W (reverse without sideways thrust in the unstick) also dropped (no gain).


## FL-R (route cost = flying time), fix R, 6 seeds  [21:09]

Code: route_graph.gd connect_nodes(): ar cost := pos[a].distance_to(pos[b]) for every link; A* then picks the shortest
distance. A jungle link is flown at 55-69% of top speed without boost, a lane link at up to 1.4 x top speed (crumbs: lane
1,050-1,250 u/s, jungle 100-550), so a jungle shortcut is only faster when it saves over half the way. Static check
(tools_flight, A* on the dumped graph): from the Cinder half of the top/bot lanes (fractions 0.6-0.8) to the Halcyon bow the
distance rule picks a 25-30k route with 15.3k in the jungle, estimated 50-62 s; the lane-only route is 34-47 s.
Fix R (--ff=R): cost *= 2.0 for small-only (jungle) links.
6 seeds (7,11,13,17,19,23), base > R:
  orbit episodes 88 > 8 (-91%, 6/0, t -4.4)        crash deaths 28 > 4 (-86%, 6/0, t -4.9)       crash events -17% (5/1)
  home trips docked p50 28.2 > 26.3 s, p90 57.0 > 39.5 s (-31%), trips over 40 s 23 > 8, dur/(straight/640) p50 1.42 > 0.90
  retreat trips docked p90 41.0 > 31.8 s, trips over 40 s 45 > 7
  stuck episodes 209 > 206 (-1%), trapped ships on the 4 valid seeds (11,17,19,23) 15 > 16 (neutral)
  but: pilot deaths 447 > 484 (+8%, 1/5 lower/higher, t 1.5), turret deaths 11 > 30, fights +5%: ships spend more time on
  the fronts instead of in slow jungle shortcuts, and more retreat trips end in death (408 > 467 of 751 > 792 trips).
Verdict: KEEP, with a caveat: it removes real waste (jungle orbits, retreat crashes, slow home trips) but it changes the pace
(a few percent more deaths): the lead should accept it knowingly. (seeds 7 and 13 were run with a probe that over-counted
"trapped" ships; those two numbers are not used.)

## V (crumb retrace in fix U): REJECTED  [21:09]
Same code but with the retrace (s6, IUMO seeds 7,13): trapped ship-seconds 895 and 653; without it (IUMOx): 146 and 13 (base
832 and 177); 480 escapes for 3 seeds. The retrace backs the ship out and the normal route walks it straight back in. The
code stays behind letter V (off), do not enable.

## FL-A3 (CORRECTION and upgrade of the A verdict): A removes the gate/camp-approach crash and the lance-jungler trap  [21:26]

Root cause of FL-G: pilot_flight.gd travel(): ar use_route := p.distance_to(to) > 2500.0 or not world.map.in_open_lane(p).
A jungler (or any ship) in the open lane within 2,500 of its goal flies STRAIGHT at it. For the first jungler trip the camp
is 3,200 from the base-side gate: the ship follows the route to the lane dot at the gate, drops under 2,500 from the camp
goal, abandons the route and flies the straight line to the camp, which clips the wall notch next to the gate (crash at
t = 13 s in every log, the lance wedges there and stays). Fix A routes when that straight line hits rocks.
Evidence, 6 seeds (7,11,13,17,19,23, runs\ab; stuck/pinned examples within 300 of the spot, first 12 per log):
                          base        A          B          D          E          I
  (8366,18234)  lance     5/6 logs   0/6        4/6        4/6        4/6        4/6
  (31634,18234) lance     4/6 logs   0/6        4/6        4/6        5/6        2/6
  (23398,15032) notch     2/6 logs   0/6        0/6        2/6        0/6        1/6
Bench (escape_bench, 7 trips from the mothership bow to the camp goals, 100 s):
  fighter: base 7 crashes, 3.6 s contact;   A: 0 crashes, 0.1 s;    lance: base 5/7 arrive, 130 s contact, 31 unsticks;  A: 7/7, 0 s, 0
  bomber: base 3/7 arrive, 37.5 s, 71 s contact;  A: 7/7, 28.5 s, 2.8 s;  A+O: 34.7 s, 0 crashes;  A+O+X: 27.7 s, 0 crashes.
So A's own mechanism is short in time (routeA = 0.15% of ship-seconds) but it sits exactly on the final approach of every
jungler and every gate trip; the old reading ("small effects") was wrong. A is the single most valuable flight fix; fixes O
and X are small additions on top of A (O: no boost-speed corner crashes, X: bombers do not circle waypoints).

