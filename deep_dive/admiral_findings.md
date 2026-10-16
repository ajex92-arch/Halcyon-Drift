STATUS: 00:53 FINISHED. KEEP: lane, guard, drone, def, defs, sl (+ bayA optional). OPT-IN design change: mmid2 (normal matches end at ~24-25 min instead of never in 30). Not kept: def2, bayB, bayC, bayE, mmid. Code: deepdive\admiral_fixes_diff.md

# Admiral deep dive: findings (append-only; newest verdicts at the bottom)

Working copy SP\notate\dd_admiral (live), run snapshots dd_admiral_s<N>. Switch: Game.opt("afix") via
AdmiralPlan.afix("name") (comma list, default OFF = base game). Probe: tests/admiral_audit2.gd.
Run logs: SP\deepdive\runs\admiral\adm2_*.txt.

## Code facts established before measuring

- AD-9 rule (team_defense.gd:73-128, TeamDefense.update, once a second): every enemy ship of size
  >= LARGE that our team can see within DEFEND_RADIUS = 7,000 of OUR MOTHERSHIP HULL is "seen"; the
  closest is the lead; ships within 5,000 of the lead make the push; with >= 2 in the push the
  alarm goes on: defend_point set, defend_until = now + 12 s (renewed each second), and Step 5 sets
  ts.siege_lane = "" (unless our assault already has the enemy ms under 35% hull). AdmiralSiege.update
  Step 2 also refuses to START a siege while ts.defending(); AdmiralMothershipMover and the waypoint
  timer read defending() too, and PilotGoals Step 6 sends every big ship within 18,000 (small:
  12,000) to defend_point, overriding the siege goal. The 7,000 was tuned (comment in the file) for a
  mothership AT HOME (inner nodes 7,200 mid / 12,100 top+bot from the hull). From 20:00 the AI parks
  its mothership 35% up the lane (mid: ~11,760 from home), the two motherships end ~9,300 apart, and
  7,000 from either hull reaches the middle of the map: any 2 enemy big ships fighting in the centre
  trigger the alarm for the team whose mothership they are nearer to.
- AD-10 NEW (code + events): AdmiralSiege.update() Step 4 picks the siege lane by fewest enemy inner
  turrets (ties: top). The enemy mothership is parked on MID, so the first pick is usually "top" (or
  "bot"); in the SAME admiral think AdmiralMothershipMover.maybe_move() Step 3 reads ts.siege_lane
  and orders OUR mothership to 35% up that lane (from_home 13,423 on top: speed 80 u/s = ~170 s),
  and one second later _run_siege Step 3 re-aims the siege at mid (the lane the enemy ms is on).
  Evidence (adm_late runs, probe events): seed 7 t=1795 team 1 "siege top" + "ms_move lane top
  from_home 13423", t=1796 "siege_lane mid"; seed 11: t=2011 (team 0) and t=2100 (team 1) the same.
  3 of the 5 declared sieges in 2 late matches sent the mothership the wrong way.
  Fix switch "sl": declare the siege on the lane the enemy mothership is on once it is parked >2,500
  from its home.

## AD-7 CONFIRMED + ROOT CAUSE (22:58; probe adm2_late_base, 3 seeds, 25:00 start, 900 s, 6 team-matches)
Repair bays made 3-9 per team per late match; 23 died in the 3 base late runs. Killers (Events.unit_killed,
DamageInfo): 20 enemy MINIONS, 3 small enemy pilots, 0 turrets/big ships/mothership. Place: 22 of 23 at
frac 0.33 of the lane, offset 841-858 from the lane line (inside the corridor: lane half width 1,800;
minion aggro 1,000 / bomber 1,200 / corvette 1,350, structures are targets, minion_targeting.gd). At death
10-29 enemy minions within 2,500 of the bay and 0 (one case 9) of our own: the lane was lost and the wave
walked over the bay. 21 of 23 were anchored (not on the way). Lifetime 154-189 s average (28-493 range).
Lanes: top 10, bot 9, mid 4 (mid bay mostly survives longer). Fix tested: switches bayA (0.22 of the lane),
bayB (0.15), bayC (0.33, 1,800 off the line, corridor edge); see results below.
(bay_spot_probe.gd: beyond +-1,800 from the lane line most spots are inside rocks (60 radius) or the
route is 20-30% longer, so there is little room off the corridor.)

## AD-9 interim (22:58; adm2_late_base vs adm2_late_def = --afix=def (radius 4,000 while the ms is >2,500 from home); seeds 7/11/13)
  defending seconds (both teams, 3 seeds mean)      781 -> 313
  siege-ready-but-blocked-by-defend seconds         174 -> 66
  sieges declared 3.7 -> 3.3, but call-offs "defend" 2.3 -> 2.3 (unchanged), avg siege length 48 s -> 28 s,
  enemy ms hull lost during our assaults (sum of fractions) 0.5 -> 0.8, match end 1941/2293/2229 -> 1871/2047/1885
  => the smaller radius is NOT enough: our siege fleet GATHERS ~3,000 from our own mothership (staging point
  = 7,000 short of the enemy ms, which is parked 9,300 away), exactly where the enemy fleet meets it, so
  the alarm still fires inside any radius >= 2,500 and drops the siege (PilotGoals Step 6 also turns every
  big ship around to the defend point). New switch "defs": while a siege is on, only a push within 2,500 of
  OUR hull sounds the alarm / drops the siege. Runs adm2_late_def_defs and adm2_late_def_defs_sl queued.

## AD-9 + AD-10 RESULT (23:26; late runs, 25:00 start, 900 s, seeds 7/11/13; per match, both teams added, mean of 3)
Switches: def (radius 4,000 once the ms is >2,500 from home), defs (with a siege on, only a push within 2,500
of our hull sounds the alarm/drops it), sl (declare the siege on the lane the enemy ms is on).
                                          base      def    def+defs   def+defs+sl
  defending seconds (both teams)           781      313      341        320
  sieges declared                          3.7      3.3      3.3        5.3
  assault seconds (our siege in assault)   151      170      201        671
  assault-contact seconds (a big ship <3,000 from the enemy hull)  97   114   96   259
  average siege length (s)                 48       28       63         97
  siege call-offs by "defend" / by admiral 2.3/0.3  2.3/0    2.7/0.3    2.3/1.7
  enemy ms hull lost during our assaults   0.5      0.8      0.3        0.9   (of ~1.0 lost per match)
  ms seconds spent moving (both ms)        703      609      672        365
  match end (s; cap 2400)                  2154     1934     1978       2299 (7: 2202, 11: 2295, 13: not ended)
VERDICT: AD-9 is real but its cause is TWO things, and the radius alone (def) does nothing for the sieges:
 (1) "sl" (AD-10) is the big one: with it the siege is declared straight on the enemy ms' lane, our ms no longer
     sails 13,000 units up the wrong lane (170 s) in the same think, assault seconds 151 -> 671, contact seconds
     97 -> 259, all enemy-ms hull loss now happens during our assaults (0.5 -> 0.9), sieges run ~100 s instead of ~48 s.
 (2) def/defs: defending seconds 781 -> ~320 (-60%), siege-ready-but-blocked seconds 174 -> 107; but the remaining
     call-offs (2.3 per match) are real "enemy fleet at our hull" cases, mostly BOTH teams sieging at once
     (siege_off of both teams within the same second, e.g. seed 11 t=1732): the intended race rule.
 Matches did not end sooner (2154 -> 2299 mean; 13 hit the cap): sieges now do the damage, but one kill still needs
 more than the fleet delivers in ~100 s windows (stall check calls most off after 100-135 s with hull unchanged).
RECOMMEND: --afix=def,defs,sl (all three; sl is the one that matters, defs is cheap and safe, def is optional).
Risks: pilots keep sieging while the enemy fleet fights at 2,500-4,000 from our hull (defs); balance of the end game
changes (more sieges per match).

## AD-7 in a NORMAL match (23:50; adm2_base seed 7, 1800 s, bay deaths by Events.unit_killed)
Team 0 made 11 bays (8 died, life 93 s, alive on average 1.7), team 1 made 19 (16 died, life 81 s, alive 1.3).
Killers: 18 minions, 5 small pilots, 1 big pilot (of 24). 8 died on the way (state "flying", the route runs
along the lane they are sent to); many die 24-51 s after launch with 10-28 enemy minions near, even when 10-15
of ours are there too: the lane-front clash passes the 0.33 spot. Credits: team 1 (the poorer side, treasury
~850 on average, plan 36,000 of 39,900 reached) spent 8,550 on bays (13% of everything it spent), 9,000 on
drones (14%, 35 drones killed) and 2,700 on wards (32 of 36 died, 24 by minions): 30% of its spending went to
things that lived ~1-2 minutes; team 0 spent 8%/5%/2%. The weaker side is starved by its own replacement
spending (small snowball; the bays also never stay up to heal).
Late game (3 seeds x 2 teams): drones 5,800-17,000 credits per team per match (19-75 drones lost, 28-34 killed
by BIG enemy pilots at the Crossing / near the parked motherships, rest minions / ms guns); treasuries pile up
anyway (end 4,000-38,000, average 3,900-15,800 = AD-6, design question).
AD-11 (minor, numbers only): drone attrition late. WorldMining.best_node_for_drone scores the Crossing ~100 points
above the inner nodes; danger x45 only flips it after 2+ losses in 150 s. No fix tried (treasury is idle late).

## AD-13 NEW (23:50, normal match, seed 7): the two motherships park on DIFFERENT lanes
AdmiralMothershipMover advances 35% up "the lane we are pushing" (push_lane, biased to top/bot by AD-1) and then
only a siege may change lane. Seed 7: team 0 parked on top (61% of its away time), team 1 on bottom (39%): the
mothership gap averaged 30,100 units (vs 9,300-12,000 when both sit on mid), siege 2 x (87 s gather + 341 s
assault), contact 98 s, enemy hull lost 4% in the whole match. Switch "mmid" (park on mid unless sieging) and
"lane" (AD-1) are being measured in normal 1800 s runs (adm2_lgd, adm2_all, adm2_allmid).

## AD-1 + AD-8 (+AD-5) RESULT (23:57; normal 1800 s runs; base = adm_seed7/11 (same code, first probe) vs adm2_lgd = --afix=lane,guard,drone seeds 7/11/13)
  push lane share (both teams)   top 46%  mid 8.8%  bot 45%      ->  top 32%  mid 32%  bot 35%
  lane with the furthest minion as a FRACTION (the reference): mid 29.5% (base) vs 31.3% (fixed)
  push_lane() disagrees with that reference  21% of the time (15% / 26%)  ->  0.0% (all three seeds)
  waypoint on mid               13.5% (8.7% / 18%)  ->  31.5% (25 / 30 / 39)
  our pilots on mid (ships within 2,500 of a lane line)  27.6% (seed 7) -> 34.4%
  the mothership still parks where the push lane was at 20:00 (top 58%, bot 28%, mid 15%), one lane per
  team, so the two motherships stay ~30,000 apart (see AD-13).
VERDICT AD-1: CONFIRMED and FIXED by "lane" (compare fractions in AdmiralLanes.push_lane()); one line, no balance
  risk beyond "mid gets the waypoint/rally it should have had". KEEP.
AD-8 (guard): failed turret orders per match (both teams) 423 / 244 -> 0 in all 3 seeds. Pure noise removal
  (no cost either way). KEEP.
AD-5 (drone: recount before Step 4 + never order into a full queue): failed "queue is full" orders (late
  scenario) 18-48 per match -> 0; no change in drone count (avg 12.0-13.1 alive in both). KEEP (trivial).

(Correction 23:59 to the AD-5 line: failed 'queue is full' orders are 0 in the normal 1800 s runs in both base and fixed; in the LATE scenario the base has 18-48 per team per match (all 6 team-matches), and with the fix the 30 s smoke test showed 0 (confirmed by the adm2_late_all runs below). Alive drones unchanged: normal base 12.2 / 12.0, fixed 10.5-12.2.)

## AD-7 FIX RESULT (00:11; late scenario 900 s; base = adm2_late_base seeds 7/11/13/17 vs bayA = bay at 0.22 of the lane (was 0.33), seeds 7/11/13)
                                   base (4 seeds)      bayA (3 seeds)
  bay lifetime, average (s)        160 (145-175)       300 (208-377)
  bays alive on average (max 3)    2.6                 2.8
  bays died per match (both teams) 6.5                 4.0
  bays made per match              12.2                9.7      (matches ran longer: end 2094 -> 2300 s)
  credits spent on bays per match  5,500               4,350    (-21%)
  killers of the 12 bays that died: 8 minions, 3 small pilots, 1 big pilot (same mix as base)
bayC (0.33 but 1,800 off the lane line): every candidate spot is refused (rock within 60 / no route), so NO bay was
  ever deployed (seed 7: 0 bays, treasury unspent): REJECTED. bayB (0.15) and bayE (only where our wave front is
  >= 0.1 of the lane past the spot) not measured in time (bayE queued: adm2_late_bayE).
VERDICT AD-7: bayA is a cheap improvement (one constant): the bay lives ~1.9x longer and costs 21% less; it cannot be
  made safe (minions pass anywhere in the corridor and the rocks beyond +-1,800 refuse bays). Not measured in a
  normal 30-min match (where the poorer side lost 8,550 credits to bays); expectation: same direction. Optional KEEP.

## AD-14 NEW (00:16): in a NORMAL match the two motherships chase each other across the map
Evidence: adm2_all seed 7 (normal 1800 s, --afix=def,defs,sl,lane,guard,drone; events from the probe):
  t=1201 team 0 declares a siege on BOT (enemy ms still home: fewest-turret lane) and the mover sends team 0's ms bot
  (from_home 13,423: ~170 s at 80 u/s); t=1310 team 1's ms goes TOP; t=1391 team 0's siege is re-aimed TOP (the enemy
  ms is there); t=1420 team 0's ms goes TOP; t=1630 team 1's ms goes BOT. They swap lanes and never meet: ms gap
  30,100 on average (same as base), assault seconds 713, contact seconds 46, enemy hull lost 0.00 in 1800 s,
  ms seconds moving 990 (base 694). Cause: both admirals follow "the lane the other ms is on" (siege lane) at the
  same time, plus AD-13 (the advance lane = push lane at 20:00 = different lanes). Fix candidates: "mmid" (park on
  mid unless a siege is on) and "mmid2" (always mid): all matches then meet on the shortest lane.
  adm2_allmid (mmid, seeds 7/11) and adm2_allmid2 (mmid2, seeds 7/11) queued; results below if they finish.
AD-3 (siege lane hops in the first seconds): same root as AD-10, fixed by "sl" (declared straight on the right lane
  when the enemy ms is away from home). AD-4 (stall check only 120 s after first contact): sieges that stalled were
  called off after 100-175 s with hull unchanged (adm2_late_def_defs_sl seeds 7/11: 131, 101, 135 s; hp0=hp1=1.0), so the
  check works; no run showed a siege that survived a long time without damage, so NOT worth touching.

## AD-7 more variants (00:30; late scenario)
bayE (only where our wave front is >= 0.1 lane past the spot; seeds 7/11 done): bays alive on average 1.5 (base 2.6,
bayA 2.8), bays died 1.5 per match, bays made 7.5, life 55 s (few bays, one seed none died): fewer losses but also
much less coverage, so NOT recommended. bayA stays the pick. bayC placed no bay at all (rejected).

## AD-6 numbers only (design question, no fix; adm2_base normal 1800 s, 3 seeds x 2 teams)
  average treasury 850-2,650 (mean ~1,700); end of match 1,200-16,200; time above 5,000: 0-396 s (the leading side 270-396 s
  in 3 of 6 team-matches; above 10,000: 45-133 s in 2); plan steps finished 38-44 of 46 at 30:00 (the plan is
  research-queue bound: one step every 20-60 s, so money waits, not the other way round, from ~12:00 on).
  Late scenario (everything researched at 25:00): treasuries 3,900-15,800 on average, 3,500-38,000 at the end (the plan
  is complete, drones/bays/turrets/wards are at their caps: nothing left to buy; Fleet Command is excluded by design).
  Sinks that DO consume it in the late game: replacement drones 5,800-17,000 per team per match (19-75 drones lost).

## AD-13/AD-14 RESULT (00:47; NORMAL matches, 1800 s, seeds 7/11 for the mid variants, base seeds 7/11/13)
                                  base (3)        def,defs,sl,lane,guard,drone    + mmid2 (always park on mid)
  mothership lanes (ms seconds)   top 43 / mid 16 / bot 41 %  (seed 7: top 61)    mid 100% (both teams, both seeds)
  ms seconds spent moving         953 (694-1153)  990 (seed 7)                     299 (292, 305)
  ms-to-ms distance (hull)        29,100          30,100                           29,700 (parked mid, but the avg includes the long sail from home)
  assault-contact seconds         86              46 (seed 7)                      95 / 62
  enemy ms hull lost / match      0.01            0.00                             1.00 / 0.95  -> the match END
  match end                       none in 1800 s (3 of 3)                          1504 s and 1436 s (Cinder ms destroyed both times)
  push lane on mid                8%              30%                              32% / 36%
  waypoint on mid                 11%             24%                              32% / 43%
  pilots on mid lane              29%             32%                              40% / 37%
  failed turret orders / match    275             0                                0
  mmid only (park mid unless a siege is on; seed 7): ended at 1687 s, ms on mid 56%; the 1201 s siege on the
  fewest-turret lane (enemy ms still home) still sent team 0's ms to bot first; mmid2 removes that.
VERDICT: in the base game the normal match does not end by a mothership kill in 30 minutes (3/3), because the two
  admirals park on different lanes and then chase each other's lane (AD-13/AD-14). Parking on mid ("mmid2") makes the
  siege lane = mid for both, the fleets meet, and the match ended at ~24-25 min in 2/2 seeds (Halcyon won both: only 2
  seeds, but note team 0 thinks first and declares first; check for a side bias before the fun runs).
  THIS CHANGES HOW MATCHES END: treat as a design decision (the code comment says the 35%-advance rule was chosen because it
  "ended the most matches"; with the lane mismatch it no longer does). Opt-in: --afix=mmid2.

## LATE-scenario bundle confirm (00:47): base = adm2_late_base, 6 seeds (7/11/13/17/19/23) vs adm2_late_all = def,defs,sl,lane,guard,drone, seeds 7/11/13
  per match, both teams                 base (6)      fixed (3)
  siege call-offs by "defend"           2.3           0.3
  assault seconds                       173           400
  assault-contact seconds               102           185
  defending seconds                     731           243
  ms seconds moving                     669           367
  enemy hull lost during our assaults   0.70          1.00 (all of the ms loss)
  failed drone orders (queue full)      45            0
  failed turret orders                  95            0
  push lane on mid / waypoint on mid    9.5% / 15%    26.7% / 53%
  match end (cap 2400)                  2130          2098 (seed 7 not ended; 11: 1905, 13: 1989)

(Correction to the table above: the 'ms-to-ms distance' row is the average over the whole match including the first 20 minutes with both motherships at home, so it says nothing about the parked distance; ignore it. Use ms lane share, moving seconds and contact seconds instead.)

## 6-SEED CONFIRM def,defs,sl vs base (00:52; late scenario, seeds 7/11/13/17/19/23 for both; per match, both teams)
                                   base        def,defs,sl
  sieges declared                  3.7         3.7
  call-offs by the defend alarm    2.3         1.7
  call-offs by the admiral         0.3         0.8
  assault seconds                  173         494   (x2.9)
  assault-contact seconds          102         230   (x2.3)
  defending seconds                731         277   (-62%)
  ms seconds moving                669         368
  enemy hull lost in our assaults  0.7         0.9   (of ~1.0 lost per match)
  average siege length (s)         40          68
  match end (s, cap 2400)          2130        2133  (no change; the kill now comes from assaults)
FINAL KEEP set (late scenario proven on 6 seeds, normal scenario on 3): lane, guard, drone, def, defs, sl. OPTIONAL: bayA.
OPT-IN design change: mmid2.
