# Deep dive: preliminary findings salvaged from the stopped investigators

Written 2026-10-15 ~15:20 local, in the last 10% of the usage window. The
investigators (flight, behavior, targeting, minions; admiral never started)
were stopped before writing findings files. This file rebuilds what they had
from (1) the code they changed in their fix copies (salvage\<d>_diff.md),
(2) their transcripts (salvage\find_<d>_notes.md: tool-call log and last
thoughts), (3) their finished run logs (runs\<d>\). Nothing here is banked;
every fix lives only in SP\notate\dd_<d>_fix behind a switch.

STATUS of each item: "measured" = numbers exist; "code" = the bug is plain in
the code but its effect isn't measured yet; A/B runs for all switches are
queued (see the end).

## Flight and pathing (copy dd_flight_fix, switch --ff=<letters>)

- FL-A (major, code + lead's audit): PilotFlight.travel() follows a route only
  for goals over 2,500 away or when off the open lanes; a short hop in a lane
  flies straight even when the line hits rocks. Fix: also route when the
  straight line is blocked (segment_hit, cached ~4 times a second).
- FL-B (major?, code): the route graph's connector dots run THROUGH the ore
  node's rock field (The Crossing sits on the connector), so routes lead into
  rocks. Fix (map_builder_route.gd, connector loop): a dot inside a node's
  field becomes two dots, 1,050 either side. Changes the graph: check
  route_probe before/after.
- FL-D (major, measured by lead: 58% of big-ship "hold far" samples not
  approaching, 68% late game): PilotCombat.fight() big-ship branch calls
  travel(hold) and then overrides face_point with the target, so travel's
  thrust is wrong for a hold point behind/beside; the stuck timer then
  reverses the ship mid-fight. Fix: while > 500 from the hold point keep
  travel's facing (turrets still aim); the Ion Frigate turns to the target
  once in reach.
- FL-E (minor/major?, code): avoid_rocks() applies reverse thrust when the
  ship slides tail-first into a rock, pushing it further in. Fix: brake with
  the main engine in that case.
- FL-H (major, code + lead's audit: 11% of fight samples have the target
  behind rocks): strike craft dogfight straight at the target with only
  avoid_rocks. Fix: when the line to the target is blocked, travel() the
  route to it.

## Pilot behaviour (copy dd_behavior_fix, fixes always on)

- BE-home (major, measured by lead: 37 samples/25 min with a target in reach
  while flying home): PilotCombat.steer() only shoots while leaving
  (retreat/fallback), so "home" never fires back. Fix: also when state ==
  "home".
- BE-rally (major, code): after 10:00 the odd seats rally to the admiral's
  waypoint, but the odd seats are the whole mid trio (1, 5, 9), so mid is
  emptied. Fix (pilot_goals.gd): seats 4, 5, 6 (one per lane) + the flex.
- BE-flex (minor/major, code): the flex rotates lanes on the clock every 90 s,
  travel time included, so it spends much of its life flying. Fix: stay
  until 90 s spent near the station, then move on.
- BE-retreat-big (minor, code): retreating big ships look for targets within
  900 only, though their turrets reach further. Fix: max(900, main reach).
- BE-routing (major?, code): PilotSystems counts any target as "fighting"
  (also one passed on the way home, or a far push target), so energy goes
  to weapons when it should go to engines/shields. Fix: fighting = target
  and state != home and not target_far.
- BE-jungle-focus (minor, code): nearest_enemy() skips neutral units, so a
  jungler hit by a monster finds no threat and never angles its shields.
  Fix: use the monster we're fighting when it's within 1,600.
- BE-kit-lag (major for support?, probe kit_lag.gd, runs empty): repair kit
  drones steer at speed min(speed, d*4) toward a moving patient and trail
  it by speed/4, out of heal range. Fix (repair_drone.gd): add the patient's
  velocity (feed-forward).
- BE-hyperspace (major?, code): the AI never uses the Hyperspace Module
  facility. Fix (pilot_ai.gd): jump to the bay nearest the lane front when
  it saves more than the 6 s spool + 1,500.
- Lead's suspect "jungler stuck as laner after camps run out": NOT in the
  investigator's fixes; still open.

## Targeting and weapons (copy dd_targeting_fix, switch --ddfix=<names>;
## DDStat instrumentation in scripts/core/dd_stat.gd, probe dd_target_probe)

- TG-ion (major, code; lead's suspect): the Ion Frigate's FIXED burst beam
  (2 s on, 4 s off, a pull commits the burst) fires whenever in reach, nose
  unaligned. Fix: fire (and special) only when the nose is on the target.
- TG-beam (minor/major, code): beam weapons aim at the LEAD point although
  beams hit instantly. Fix: aim straight at the target for beams.
- TG-aim2 (major?, code): every turret of a big ship aims at one aim_point
  led with the main gun's round speed; guns with other round speeds miss.
  Fix: each turret leads with its own round speed (ship.gd, weapon_mount.gd
  lead_for(), ship_controls aim_unit/aim_err).
- TG-ovl (minor, code): the Lance doesn't use Overload while its beam is on
  a target. Fix: special while firing.
- TG-los (major, measured by lead 11% occluded): no line of sight in
  pick_target/prey; strike craft fire into rocks. Fix: +700 score for a
  target behind rocks; hold fire while the line is blocked.
- TG-bd (major?, code): pilots shoot turrets under backdoor protection
  (x0.3 damage, no friendly minion within 1,800). Fix: +1,500 score.
- TG-ms (TASTE, needs the user's OK): small non-bomber ships attack the
  enemy mothership (and push to it with 3+ minions there). Fix removes that.
  This changes how matches end: treat as an opt-in variant, not a bug fix.

## Minions (copy dd_minions_fix, switch --mfix=<names>; instrumentation in
## minion.gd/weapon_mount.gd/projectiles.gd/combat.gd, probe minion_audit)

- MN-lead (CRITICAL, measured, seeds 7 and 711, 900 s): fighter and bomber
  minions compute a lead point (aim) but MinionFlight faces the target
  itself, and their guns are FIXED. Fighter bolts: 91% fired within 0.05 rad
  of the target's centre; only 21-24% would hit as fired, 87-88% would if
  aimed at the lead; 64% expire, 24-28% hit a unit. Bomber torps: 9-10% vs
  68-70%; 71-73% expire, 13-15% hit rocks. Fix: face the aim point.
  RISK: fighters/bombers get ~3x deadlier: lanes, pilot deaths and pushing
  change a lot; probably needs a damage retune afterwards (design call).
- MN-gate (major, measured): fixed guns fire whenever in reach; 24% of bomber
  torps are fired >= 90 degrees off (during the peel-off). Fix: fire only
  when the nose is on the aim point.
- MN-route (minor?, code): minions spawned outside their lane's corridor
  (mothership parked up another lane) fly straight through the jungle. Fix
  (world_queries.gd lane path): route to the lane first.
- MN-los (minor/major, measured: target blocked 4.5-7.2% of fighter fight
  time, 5-6% bombers): minions keep and pick targets behind rocks (turrets
  don't). Fix: skip/drop blocked targets.

## Admiral: not started.

## A/B runs queued (no tokens; started 15:16 local)

SP\deepdive\ab_run.ps1 -Seq A and -Seq B, through run_batch (3 at once by
day, 6 after 18:00), seeds 7, 11, 13; logs SP\deepdive\runs\ab\<tag>_seed<N>.txt,
progress in runs\ab\progress.txt. Probe ab_audit = the lead's pilot_audit
(copied into each fix copy; the targeting copy's one calls DDStat.load_fix()).
- A: ab_base (dd_flight_fix, switches off = base), ab_flight (--ff=ABDEH),
  ab_beh (dd_behavior_fix), ab_targ (--ddfix=beam,ion,aim2,ovl,los,bd,ms),
  900 s each; then late_base/late_flight/late_beh/late_targ (--late, 300 s).
- B: mn_base / mn_fix (minion_audit, --mfix=lead,gate,route,los),
  tp_base / tp_fix (dd_target_probe, ddfix as above), 900 s.
Compare AUDIT_JSON counters (pilot_audit), summ.py (minions), ana.py
(targeting). Each switch set is tested as a bundle: attribute single fixes
afterwards only where a bundle helps or hurts.

## Added by the lead (main agent) ~15:40

- BE-jungle-return (major?, code confirmed): PilotGoals.think_jungle() sets
  state "lane" when no camp is alive (pilot_goals.gd:282-283), and only a
  retreat (pilot_ai.gd:285-286), a relaunch (_reset_after_launch) or a
  siege-interrupted home trip (pilot_ai.gd:298) set "jungle" again. Camps
  respawn, but the jungler keeps laning until it next retreats, docks or
  dies. Fix: in think_lane(), a jungle-role pilot with a live camp goes back
  to "jungle". Effect not measured yet (count role=jungle & state=lane &
  live camps > 0).

## Admiral (copy dd_admiral; probe tests/admiral_audit.gd, runs\admiral\)

Code read: admiral_ai/plan/builder/lanes/waypoint/siege/mothership_mover/
fleet_command + admiral_command. Suspects (the probe measures each):
- AD-1 push lane biased to the long lanes (major?): AdmiralLanes.push_lane()
  compares our furthest minion's distance ALONG each lane in world units,
  but top/bot are ~44,200 long and mid ~33,600 (map_layout.gd). Even waves
  meet at the lane midpoints (s ~22,100 on top/bot vs ~16,800 on mid), so
  push_lane() says top/bot almost always. Everything keyed on it follows:
  the waypoint (and the late rally of half the laners, see BE-rally), the
  mothership's advance lane, Fleet Command's lane. Fix: compare
  front_frac() (fraction of the lane), which the same file already has.
  Probe: push_<lane> shares vs fracfront_<lane>, push_ne_fracfront.
- AD-2 repair bay placement gives up after one spot (minor/major?):
  AdmiralBuilder.place_bay() tries mid, top, bot and RETURNS after the first
  uncovered open-lane spot whether or not deploy_bay() succeeds; deploy_bay
  refuses spots in asteroids (60 radius) or unreachable. If the mid spot is
  refused, no bay is ever tried on top/bot. Probe: fail_bay reasons,
  bays_made and their lanes.
- AD-3 siege lane ties go to "top" (minor?): AdmiralSiege picks the lane
  whose enemy inner node has the fewest turrets, ties to the first of
  top, mid, bot. Probe: siege events.
- AD-4 the stall check only covers the first 120 s after contact (minor?):
  _run_siege() calls an assault off if the enemy mothership lost < 15% in
  the 120 s after first contact; once it has lost 15% the siege can never
  stall again (contact_ms_hp is never re-based), so it runs until no big
  ship is left. Probe: siege durations and outcomes.
- AD-5 two drones per think (minor): Step 1 builds a drone and Step 4 can
  build another in the same think (drones isn't recounted).
- AD-6 treasury pile-up (known open design question, memory): spending
  sinks run out (drones max 14, turret slots, 3 bays, 6 wards, the plan
  ends with Hyperspace, which AI pilots never use: BE-hyperspace). Probe:
  tre_over_2000/5000/10000 seconds, plan_done_t.
## First A/B results (15:45 local; 900 s runs, paired seeds)

FLIGHT bundle --ff=ABDEH vs base, seeds 7 + 13 (ab_compare.py):
  stuck episodes 69 -> 17 (-75%), stuck seconds 1560 -> 316 (-80%)
  big ship hold far, not approaching 611 -> 143 (-77%)
  no route while far 15 -> 6; crash deaths 10 -> 3
  occluded while firing 1123 -> 13 (FL-H: routing craft don't fire), but
  occluded fight samples +79% (they spend longer with the target hidden)
  REGRESSION: rock contact while fighting 693 -> 3218 ship-s (x4.6), all
  rock contact +35%; turret deaths 2 -> 11; pilot deaths same (151/149).
  -> Next: run A, B, D, E, H one at a time to find the culprit (H, which
  routes strike craft toward a moving target, or E, the braking change, are
  the suspects). Keep the rest.

MINIONS bundle --mfix=lead,gate,route,los vs base, seeds 11 + 13 (summ.py):
  fighter bolts on a hitting line 19-22% -> 78-79%; hits 21-26% -> 59%;
  into rocks 8-24% -> 1.5-1.8%
  bomber torps on a hitting line 7.5-9% -> 47-48%; hits 13-14% -> 30%;
  into rocks 14-20% -> 5%; fired >= 90 deg off 23-25% -> 0.3-1%
  fighter time with the target behind rocks 5-20% -> 0.2-0.4% of fights
  minion damage to pilots +27..36%; minion-vs-minion damage unchanged;
  fights end sooner (fighter fight share 0.28-0.32 -> 0.20), fewer minion-
  seconds alive (-11%). Lane-front deaths: same shape. Verdict so far:
  a clear fix; its balance effect is mild and symmetric (pilots take ~30%
  more minion damage), so no retune needed before measuring further.

Still running/queued: ab_beh, ab_targ, late_*, tp_* (targeting probe),
ab_base seed 11 + mn_base seed 7 (reruns), admiral (adm, adm_late), P2
(p2 seed 102, p2_late 103). P2 seed 101 scored fine with fun_score.py.
## Admiral results (16:00 local; admiral_audit, seeds 7 + 11, 30 min each)
(python -I deepdive\ab_compare.py <any dir> deepdive\runs\admiral)
- AD-1 CONFIRMED (major): push_lane() picks mid 5-13% of the time, while
  the lane whose minions are furthest as a FRACTION is mid 14-36% of the
  time; they disagree 8-29% of the time. The waypoint sat on mid only
  4-20% of the time (top/bot 60-80% for the side pushing them). With
  BE-rally (all 3 mid laners + flex rally after 10:00) this empties mid.
- Sieges: 0-3 per team per 30-min match, all called off after 130-291 s of
  assault (one after 40 s of gather); the enemy mothership ended at
  0.96-1.00 hull in all four team-matches. The siege lane often hops in
  the first seconds (picked by fewest turrets, then re-aimed at the lane
  the enemy mothership is on, which can flip while it is moving).
  Late runs (adm_late) will show more.
- AD-2 REFUTED: bays are placed on mid, top and bot (only 2 failures, for
  money).
- AD-7 NEW (major?): repair bays die fast: 11-19 bays made per team per
  30 min with 1.3-1.9 alive on average (lifetime ~3 min): 5,000-8,500
  credits per match. Check where they die (spot 0.33 down the lane, 900
  off the line, may sit in the fights).
- AD-8 NEW (minor): guard_inner_nodes() retries a node whose turret just
  died every second during the 25-30 s rebuild lockout: 100-255 failed
  orders per team per match (no cost; it spams admiral_result).
- Treasury: the winning side averages ~2,100 with peaks 9.6k-16k (over
  5k for 270-384 s); the losing side ~900. Plan: 44/46 steps for the
  winner, 38-42 for the loser by 30:00.
- (Display bug in ab_compare.py: the push[] list also shows the push_flips
  and push_ne_fracfront keys.)
## Behaviour bundle A/B (16:05 local; dd_behavior_fix vs base, seeds 7, 11, 13)
  time in state "home" 1823 -> 4449 samples (+144%): REGRESSION. Likely
  BE-home: home-bound strike craft now set aim_point at a target, and a
  small ship's nose follows its aim, so they turn to fight and their trip
  home takes ~2.4x longer (more downtime, which the fun score measures).
  Fix idea: only shoot what is already within the arc, never steer for it.
  turret-targeted samples +85%, turret deaths 2 -> 9 (watch).
  crash deaths 14 -> 6; stuck seconds -25%; other counters within +-12%.
  -> Next: split the bundle (home / rally / flex / retreat-big / routing /
  jungle-focus / kit-lag / hyperspace) behind switches like the flight copy
  and test one at a time; BE-rally and AD-1 need the admiral probe's
  waypoint/lane counts plus per-lane pilot counts to show their effect.
## STEP 1 VERDICTS (17:35 local, all background runs read)
Tools: python -I deepdive\ab_compare.py --matrix deepdive\runs\ab (pilot audits,
paired seeds); ana.py on tp_*; ab_compare admiral part; fun_score.py.
CAUTION: matches diverge chaotically, so "paired" seeds are only loosely
paired; with 2-3 seeds, changes under ~+-30% in noisy counts (home samples,
turret deaths, base had only 2 turret deaths) may be chance. Big effects
below are real; small ones need the 6-seed runs queued tonight.

Flight singles (seeds 7+13 vs ab_base):
- FL-H is THE culprit: rock contact while fighting 693 -> 2935 (x4.2),
  occluded samples +90% (it stops firing while routing: occluded firing
  1123 -> 23). Rework or drop.
- FL-D: big ships failing to reach their spot 611 -> 129 (-79%), stuck
  episodes 69 -> 41, rock contact -32%: KEEP.
- FL-A: stuck seconds -51%, hold-far -52%, crashes 10 -> 4, but home-state
  samples 1257 -> 3591 (x2.9) and home-with-target 35 -> 176: suspicious
  (home trips much longer?), check with more seeds before keeping.
- FL-B: stuck s -35%, rock -27%, occluded -34%, hold-far -30%: KEEP (more
  seeds).  FL-E: stuck s -52%, crashes 10 -> 4, rock-while-fighting +25%:
  probably keep (more seeds).
- Late game (3 seeds) flight bundle: rock contact 935 -> 117, stuck 69 -> 25,
  hold-far -28%, pilot deaths 83 -> 63.
Targeting bundle (beam,ion,aim2,ovl,los,bd,ms; 3 seeds):
- Lance beam ticks on target 48.7% -> 87.6% (rock 13.4% -> 0.7%); Lance
  "nose on lead but off target" vs ships 76% -> 20%; Lance damage +61%.
- occluded rounds: fighters 8.9% -> 1.1%, bombers 17.8% -> 3.5%; bomber
  torps into rocks 24.5% -> 9.4%. Pilot audit: occluded firing 2216 -> 298,
  rock contact -38%, stuck -42%; pilot deaths +12% (fights deadlier).
- flak battery aimed at turrets 48% -> 19% (bd), hit rate 60% -> 45% (aim2?
  check). Ion: only 3 bursts in 45 min of base play: too rare to judge.
- "ms" is a behaviour/taste change (small craft stop sieging): REQ-CHANGE
  style opt-in, not for main without the user.
Minions (3 seeds now): as before, a clear win; KEEP all four.
Behaviour bundle: home-state time x2.4: SPLIT (step 2).
Admiral late (25:00 start, 2 seeds): both ended with a mothership kill
  (32:21, 38:13). Sieges were declared but called off after 10-28 s (one
  2 s): TeamState calls a siege off while our base is "defending", and with
  both motherships parked 0.35 up mid (~9,300 apart) both bases are
  "defending" 224-588 s of ~600-800 s. AD-9 NEW (major): sieges are
  effectively impossible late; the end comes from a mothership brawl in mid.
  Push-lane bias persists (top 77% vs fraction 74% one side; others 50/46).
  "Drone build queue is full" 18-48 failed orders (harmless).
P2: fun_score works: normal 58.5 (2 x 20-min, none ended), late 89.1
  (ended 33:43). READY TO BANK.