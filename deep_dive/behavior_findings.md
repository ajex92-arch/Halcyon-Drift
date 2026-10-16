STATUS: 21:15 verdicts: kit KEEP, rally KEEP (late runs confirm), jfocus KEEP-minor, routing KEEP-minor, flex DROP, retbig DROP (late: +26% trigger samples while retreating, no outcome change), hyper ~no-op (late: 137 spool samples in 3x300 s; long run pending), home/home2 DROP, jret DROP (0 jungler lane samples even in a 35 min match). Old bundle home-time x2.4 = noise. Running: late routing/kit/jfocus/flex, long_bhyper (2400 s). Next: commute probe runs (ab_cbase / ab_ckeep, beh_audit2, 6 seeds), original home 3 seeds, final write-up.

# Pilot behaviour deep dive: findings

Working copy: SP\notate\dd_behavior_fix (every fix behind `--bfix=<names>`, a comma list read once in
`PilotAI.bfix()`, scripts/ai/pilot_ai.gd; default OFF = the base game).
Probe: tests/beh_audit.gd (ab_audit unchanged + extras: home trips, junglers, lanes, energy, kits).
Runs: SP\deepdive\runs\ab\ab_b<switch>_seed<N>.txt; compare with
`python -I SP\deepdive\ab_compare.py --matrix SP\deepdive\runs\ab` (I widened its tag regex to allow digits, for
`ab_bhome2`) and SP\deepdive\beh\beh_compare.py (the extras).

## Switches

| switch  | fix                                                                                  | code |
|---------|--------------------------------------------------------------------------------------|------|
| home    | BE-home as salvaged: home-bound pilots take the retreat's opportunistic shots         | pilot_combat.gd steer() |
| home2   | same but only a target already inside a gun's firing arc (fixed: nose within 0.12-0.2 rad, turret: within its arc) | pilot_combat.gd steer(), in_firing_arc() |
| jret    | a jungle-role pilot in state "lane" goes back to "jungle" when a camp it would take is up | pilot_goals.gd think_lane(), _camp_waiting() |
| rally   | after 10:00 seats 4, 5, 6 (+ flex) rally to the waypoint instead of the odd seats      | pilot_goals.gd _pick_station() |
| flex    | the flex pilot stays on a lane until 90 s spent near its station                       | pilot_goals.gd _flex_lane() |
| retbig  | retreating big ships look for targets as far as their main guns reach                  | pilot_goals.gd think_home() |
| routing | energy to weapons only for a target we really fight (not home, not target_far)         | pilot_systems.gd |
| jfocus  | shield focus against the jungle monster that hit us                                    | pilot_systems.gd |
| kit     | repair-kit drones add the patient's velocity (follow a moving ship)                    | repair_drone.gd |
| hyper   | use the Hyperspace Module: jump to the bay nearest the lane front                      | pilot_ai.gd update_docked() |

## Mechanism of the "home" regression (task 2)

Code reading says the stated cause is NOT how BE-home works:
- The nose follows `controls.face_point` only: ShipFlight.fly() turns toward face_point (scripts/entities/ship_flight.gd:38-41).
  `aim_point` is read only by the gun mounts (ship.gd:396 -> weapon_mount.gd:147-163: a turret swings toward it, a fixed gun ignores it).
- In steer() the home branch (pilot_combat.gd:70-90) calls `travel()` first, which sets face_point to the route waypoint (pilot_flight.gd:152);
  BE-home then only sets `c.aim_point` and `c.fire`. face_point is never touched, so a home-bound small ship does not turn to fight.
- What firing can change: it pays weapon energy, and boost needs energy over 50% (pilot_flight.gd:158, ship_flight.gd:48).
  (To be measured from the hm_* counters: boost samples and mean energy on home trips, with and without the fix.)

(measurements follow)

## Verdicts (appended as they come)

### kit (BE-kit-lag): KEEP (clean, minimal reproduction, quick headless probe tests/kit_lag.gd)
Probe: five fighters at 30% hull each use one repair kit, then fly straight at a fixed speed for 11 s (hull regained, a full kit = 50):

| speed u/s | 0 | 150 | 300 | 450 | 640 |
|-----------|---|-----|-----|-----|-----|
| base      | 49.9 | 49.9 | 19.8 | 0.9 | 0.5 |
| --bfix=kit | 49.9 | 49.9 | 49.9 | 46.8 | 43.7 |

So in the base game a repair kit used by a ship flying 450+ u/s (every retreating fighter, 500-1,100 u/s) heals about nothing: the kit drone (speed 520,
repair_drone.gd:134) trails its patient and never gets within `radius + 60` for the healing test (repair_drone.gd:124). The fix adds the patient's velocity to
the drone's wanted velocity. Note it also changes kits for human players (they heal what the kit is designed to: ~50 hp), so it is a game fix, not only AI.
(Full-match numbers: see the kit_* rows below once the runs are in.)

### home / home2: the "turns to fight, flies home slowly" mechanism is REFUTED (minimal reproduction tests/home_probe.gd)
One fighter on our mid lane, 12,000 out, brain in state "home", flying home at 400 u/s; a still enemy fighter 700 ahead on the nose (or 700 to the side);
10 s of flight, distance/speed/nose-error/trigger recorded once a second (same seed, so the runs are otherwise identical):

| target       | switch       | trigger ticks | distance to the mothership after 10 s | speed, nose error, energy per second |
|--------------|--------------|---------------|---------------------------------------|--------------------------------------|
| on the nose  | none (base)  | 0             | 2098                                  | (reference)                          |
| on the nose  | home         | 31            | 2098                                  | identical, energy 0.98 vs 1.00 once  |
| on the nose  | home2        | 30            | 2098                                  | identical                            |
| to the side  | none / home  | 0 / 0         | 1595 / 1595                           | identical (the arc test blocks the shot) |

Both versions shoot a target that is already in front and change nothing else: face_point stays the route waypoint (pilot_flight.gd:152), and the nose only
follows face_point (ship_flight.gd:38-41). So the x2.4 in home time seen in the bundle is not BE-home. home2 differs from home only for big ships
(home accepts any target in reach for them; home2 needs it inside a gun's arc: a fixed ion cannon would otherwise fire a committed burst the wrong way).

### home / home2 (BE-home): first look
- home2 (3 seeds, 900 s, vs base): samples in state home 1823 > 2215 (+21%, within the noise), home with a target in reach 54 > 57, pilot deaths 221 > 216,
  stuck seconds 1952 > 1730. Over all 35 home trips of those 3 matches the trigger was pulled on only 15 samples (7.5 s) and a target was even
  present on 72 of ~2,300 trip samples (3%): pilots only start a shopping trip with no enemy within 2,500 (pilot_shopping.gd:171), so there is almost nothing
  to shoot on the way. BE-home cannot explain a x2.4 change in home time, and cannot change the match either way.


### jret (BE-jungle-return): DROP (the situation never happens)
Seeds 7, 11, 13, 900 s: with --bfix=jret every one of the 53 standard counters is IDENTICAL to the base run (bit-identical matches), because the new
branch never fires: junglers (role jungle) spent 0 samples in state "lane" in all three base matches (jr_lane absent; jr_jungle 6289/6186/6136 samples,
jr_retreat 322/497/505, jr_home 235/210/249). Camps never run out: on average 8.4 / 8.3 / 7.9 of the 12 camps are up (camps respawn after 80 s / 120 s,
jungle.gd:43-45; two junglers per team clear a camp about every 25 s). The code reading (think_jungle sets state "lane" when no camp is up,
pilot_goals.gd:308-309, and nothing sets it back) is right, but it is dead weight in 15-minute matches. Harmless to keep (it cannot flip-flop: _camp_waiting() repeats
think_jungle's own camp tests), but there is nothing to gain; drop unless a long match shows jr_lane > 0.


### rally (BE-rally): KEEP (the code contradicts its own comment; the fix removes a lopsided artifact)
pilot_goals.gd:162-164 (base): "Late game (after 10:00): half the laners (odd seats) and the flex gather on the admiral's waypoint" - but
`profile.slot % 2 == 1` selects seats 1, 3, 5, 7, 9, 11: the two junglers (3, 11) never stand in lane, 7 is the flex, so the "half the laners" are exactly the whole
mid trio 1, 5, 9 (heavy, ion frigate, heavy). Everything on mid walks off to the waypoint lane (top or bot, see AD-1).
Measured (beh_audit, pilots within 2,500 of a lane line, after 10:00, per team and sample; 3 seeds x 900 s, 2 teams):

| after 10:00 (base > rally)         | seed 7    | seed 11   | seed 13   |
|------------------------------------|-----------|-----------|-----------|
| mid lane with NO pilot (% samples) | 17 > 0    | 35 > 2    | 8 > 0     |
| pilots near mid (avg per team)     | 2.5 > 4.2 | 1.5 > 2.8 | 2.0 > 2.8 |
| pilots near top                    | 3.1 > 2.0 | 4.5 > 3.6 | 3.8 > 3.4 |
| pilots near bot                    | 3.7 > 3.3 | 2.7 > 1.9 | 3.1 > 3.2 |
| seats 1/9 at the waypoint (samples)| 298 > 31  | 414 > 0   | 963 > 0   |
| seats 4/6 at the waypoint (samples)| 108 > 353 | 56 > 833  | 215 > 559 |

Before 10:00 every counter is identical (the matches are the same up to 600 s). No regression in the standard counters: pilot deaths 221 > 225 (+2%),
by pilots 148 > 137, by minions 54 > 63, stuck seconds 1952 > 1946, home-state samples 1823 > 1186. One thing to watch: deaths to turrets 2 > 7 (3 seeds, all up:
2>3, 0>2, 0>2): small ships (lancer 4, bomber 6) now stand at the waypoint (55-66% down the lane = the enemy's inner node) instead of the heavy ships that shrug turret
fire. Tiny in absolute terms (+1.7 per match, 3% of deaths) but consistent; to be checked with turrets-destroyed counts (beh_audit2) on 6 seeds.

### jfocus (BE-jungle-focus): mechanism confirmed in a probe (tests/jfocus_probe.gd), outcome effect small - full-run numbers pending
Probe (seed 7): the high-skill jungler (seat 11, skill 0.93) at full health 450 from a gunship camp, 3 camps (one skipped, camp down):
shield focus angled on 0/50, 0/59, 0/28 of the ticks it had just been hit in the base, and on 35/50, 37/59, 25/56 with --bfix=jfocus; damage taken in the two
comparable camps identical (60 and 82 points), camp-kill times identical (10.8 s, 18.2 s). A jungler with skill <= 0.6 (seat 3, skill 0.50) never touches shield focus or
energy routing at all (pilot_systems.gd: `skill > 0.6` / `> 0.55`), so the fix only affects seat 11. In full matches (base, 3 seeds) junglers were hit by a
monster they were fighting on 1,118 samples (560 s) per match with the focus angled on 1.6% of them (jf_mon_focus_set).
(Process note: the lead asked that every match longer than a ~20-game-second smoke goes through run_batch.ps1; my kit_lag/home_probe/jfocus_probe/smoke runs before
19:15 were quick direct runs of 16-240 game seconds. From now on all probes go through run_batch.ps1 in the background.)


### Why "samples in state home" cannot be used (the bundle's x2.4)
Base (ab_base, 6 seeds, 900 s): 462, 566, 795, 1135, 1559, 577 samples (mean 849, sd ~440, i.e. a factor 3.4 between seeds). A home trip is a *shopping* trip: it starts when a
research or facility unlocks a hull the pilot wants (lance, bomber, flak, ion... ) and it has the money, so most trips happen in bursts right after an unlock, from wherever the pilot
stands at that moment. Trips are 8-15 per match whatever the variant (33 for the 3 base seeds; home2 35, rally 24, flex 38, routing 36), but their start distance differs a lot (a pilot
at the front 21,000-30,000 out takes 55-90 s; a jungler 9,000 out takes 25 s): flex 14,300 > 19,300 average start distance, so +68% home seconds with the same number of trips.
Every single fix moves the 3-seed total by tens of percent in either direction (home2 +22%, rally -35%, flex +68%, routing +52%); no single switch is the cause,
and the old bundle's seeds (1031, 1846, 1572 vs base 462, 566, 795) are 1.4 sd above the 6-seed base mean. Per-trip numbers (speed, boost share, nose error)
in home2 vs base are within 5%. To be re-checked by running the bundle on seeds 17, 19, 23 (queued).

### routing (BE-routing): KEEP (minor; the mechanism works, no measurable outcome change)
The code: PilotSystems counted any target as "fighting" (pilot_systems.gd:50 base), also a target passed on the way home or a push target >3,500 away that
PilotCombat flies to instead (pilot_combat.gd:68, target_far). Measured (3 seeds, 900 s): samples with the weapons routing while the pilot is flying to a FAR target
2,942 > 29 (-99%), weapons routing while home 66 > 5; thrusters-while-home samples follow the (noisy) home time. That is ~1,000 pilot-samples (500 s) per match, about
2.5% of flying time, moved from weapons (thrust x0.92) to thrusters (x1.12). Outcomes inside the noise: pilot deaths 221 > 230 (+4%), crash deaths 14 > 9,
minion deaths 54 > 36, pilot-caused deaths 148 > 176 (+19%, seeds 7/11/13: 49>54, 50>63, 49>59). The stuck seconds -45% (1952 > 1080) and home time +52% are chaos
(one stuck ship is 1,000 s of the base seed 7). Keep as a correctness fix; do not expect it to change a result.

### flex (BE-flex): DROP as is (rework if the flex matters)
Flex pilot near its station (within 2,500 of its goal) in 37 / 30 / 30 % of its flying samples (seeds 7/11/13) in the base; with the dwell logic 42 / 37 / 36 % (+6 points, all three
seeds up). The point of the fix, fewer lane changes, did not happen: goal-lane changes 110 > 135 over 3 seeds. Cause: after 10:00 the flex rallies to the waypoint lane
(pilot_goals.gd rally branch, `or profile.role == "flex"`), the admiral re-places the waypoint every 75 s (admiral_waypoint.gd) and may pick another lane, and `rally` overrides the flex dwell. The flex is a slow support
corvette (max 350-430 u/s) and spends ~60% of its life flying between lanes either way. Other counters: flex kills 7 > 11, deaths 19 > 23, pilot deaths 221 > 247 (+12%, chaos
level), home samples +68% (see above). Not worth a switch as is; a real fix would make the flex ignore the waypoint (stay on one lane) - a design call.



### kit (BE-kit-lag), full matches: KEEP (confirms the probe; no outcome change)
3 seeds x 900 s, kit drones (one per used kit): sampled healing (inside radius + 60 of the patient) 21% > 71% of the drone-samples (23>71, 22>72, 18>70), far from the patient
78% > 27%. The patients fly 630-650 u/s on average when a kit is used (retreating fighters). Standard counters inside the noise: pilot deaths 221 > 224, retreat deaths
194 > 184 of 363 > 325 retreat trips, crash deaths 14 > 7, minion deaths 54 > 54. Kits heal at most 50 hull points over 10 s, small next to the damage a retreating fighter is
taking, so the kit does not change who survives a retreat (half of the retreat deaths come within 1.5 s of the state flip, see the retreat note below); it just works as designed now. It also changes kits for
human players (the kit_lag probe): a design-visible fix, flagged for the lead. Turret-death counts are not a regression: base seeds 7/11/13 had a lucky 2; base seeds 17/19/23 have 9.

### retreat outcome (observation, not a fix): 53% of retreating pilots die before they dock
Base, 3 seeds x 900 s (beh_audit rt_*): 363 retreat trips: 194 died (53%), 134 docked (37%), 32 recovered in place (9%). Killed by pilots 63%, minions 27%, rocks 7%, turrets 1%.
Example list of the first 80 trips (seed 7): the deaths come a median 1.5 s after the state flipped to "retreat" (mean start hull 0.22); docked trips take a median 21 s
(mean start distance ~16,000). The trigger is `hull_frac() < 0.35` (pilot_ai.gd _think step 1) and hull is what is left AFTER the shield zone facing the enemy is gone, so the
state flips when the ship is about to die. Not a bug; a design/skill point worth knowing when reading kill/death numbers: a retreat is mostly a last-second reaction.
28 of the 28 crash deaths listed in the six base seeds are retreating fighters (a low-hull ship dies from a bump above 220 u/s), at repeating spots: (23,850, 5,601) four times
(seeds 7, 13, 13, 19), (18,310, 7,933) twice, (21,720, 7,944) twice, (20,280, 13,150) twice. That is the flight domain (FL-A/FL-E: route when blocked, brake) - retreat boosts at
800-900 u/s into rock corners.



### The old bundle on 4 fresh seeds: no home-time regression (task 2 closed)
All eight salvaged fixes together (`--bfix=home,rally,flex,retbig,routing,jfocus,kit,hyper`, ab_bbundle) on seeds 7, 17, 19, 23 (900 s) against ab_base:
samples in state home 3733 > 2783 (-25%; per seed 462>684, 1135>763, 1559>759, 577>577), pilot deaths 306 > 313 (+2%; by pilots 207 > 220, by minions 63 > 64, crash 20 > 13,
turret 11 > 13), stuck seconds 2498 > 1908, rock contact -23%, retreat samples -13%. The first bundle run (seeds 7/11/13: 462/566/795 > 1031/1846/1572) was one chaotic draw
around a low base. (This switch bundle is not bit-identical to the old always-on copy on seed 7: identical to 240 s, then it differs, because I capped the flex dwell
timer's time step at 1 s in _flex_lane(); the old code added the whole gap after a retreat.)
Conclusion: there is no behaviour-bundle regression in home time, BE-home is not a cause, and nothing here argues against the bundle on that count. What remains per fix is below.

### retbig (BE-retreat-big): DROP (no effect)
Seeds 7, 11, 13 (900 s): bit-identical to base in every counter (pilot deaths 221 > 221, retreat samples 10615 > 10615, ...). Only 429 big-ship retreat samples (215 s) in the three
matches, and only the ion frigate (main reach 1,700) and the capitals (heavy cannon 1,353, ion turret 1,600) reach past 900; the corvettes (735) and the flak frigate (720) do not.
Ion frigates are 0.8% of flying samples before 15:00 and seldom retreat, so pick_target() gets the same radius and finds the same target. It can only matter with
ion frigates / destroyers / battlecruisers in the late game: see the late runs.



### jfocus (BE-jungle-focus), full matches: KEEP (minor, correct)
3 seeds x 900 s: when a jungler is being hit and its target is a monster within 1,600 (jf_mon_samples, ~1,180 samples per match), the share with the shield focus angled goes
3.8% > 45% (2>47, 0>53, 2>45 per seed). Only seat 11 (skill 0.93) does it at all; seat 3 (skill 0.50) never routes or focuses (skill gates `> 0.55` / `> 0.6`). Effects, all small
and in the right direction: jungler deaths 5 > 2, monsters killed by junglers 157 > 183 (+17%), camps cleared 122 > 136 (+11%), jungler income +3%. The 3-seed standard counters are inside the noise
(pilot deaths 221 > 215). Probe (tests/jfocus_probe.gd, seat 11 at full health next to 3 camps): focus on 35/50, 37/59, 25/56 of the just-hit ticks vs 0/50, 0/59, 0/28 in the base.

### hyper (BE-hyperspace) in 15-minute matches: nothing to measure
Seeds 7, 11, 13: bit-identical to base (0 pilots ever spooled): the Hyperspace Module is the very last step of the admiral's plan (admiral_plan.gd:40, step 46 of 46) and is not
built in the first 15 minutes. Late and long runs (queued) decide this one.

## New findings from the base runs (beh_audit2, seeds 7/11/13, 900 s, no switches)

### N-1 What the fun meter's "travel" share is made of (42% of flying time)
Same buckets as fun_probe.gd (engaged = hurt or hit something in the last 4 s; near = enemy within 2,500; else travel), cross-tabbed by what the brain is doing
(119,102 flying pilot-samples): engaged 43.9%, near 13.7%, travel 42.4% (the doc's baseline: engaged 0.34-0.41, travel 0.36-0.41). The travel share splits:
lane state with the goal more than 5,000 away 18.5 points (the commute from the mothership to the station after every launch, plus lane changes), idle at the station
(lane state, goal within 1,500, nothing near) 8.3, lane state 1,500-5,000 from the goal 3.4, jungle trips to camps 6.1, retreat 5.0, home trips 1.0. Dead 4.3% and docked 0.8% of all
pilot time. So the commute is the single biggest slice: 3.1 deaths per pilot per 15 min x ~25 s per 20,000-unit run (a flak frigate at 250 u/s: 80 s; a battlecruiser at 150: 130 s).
A variant that changes map size, base position, respawn time or speed will move "travel" by more than any combat change; the Hyperspace Module (only buildable last in the plan,
see hyper) is the one AI-side cure and it is not available before ~30:00. Not a bug; read the travel number as "commute + idling".

### N-2 The Lance's Overload special is never used (confirms TG-ovl): 0 uses in 15,967 lance samples (special ready 100% of the time).
pilot_combat.gd sets c.special only for fighter (snap turn), scout (ping), bomber (focus) and the big ships; the dogfight branch has no lance case. Not touched here
(targeting domain); the number is the measure for that fix.

### N-3 Bombers die as often as fighters but almost never kill a pilot
Per 1,000 flying samples: bombers 2.1 deaths, fighters 2.0; pilot ships killed BY a bomber: 5 in 3 matches (41 bomber deaths) against 139 killed by fighters (152 fighter deaths).
Bombers are the whole bot lane (seats 2, 6, 10; 15% of all samples), idle 50% of their lane time, and the bot lane's pilot-kill/death over 3 matches is 23/60 = 0.38 vs 39/55 = 0.71
for top and 76/82 = 0.93 for mid (beh_audit fin_kills/fin_deaths by role). pick_target() adds 800 to small targets for a bomber and torpedoes do x0.35 to strike craft, yet the lane is mostly
fighters and minions. Looks like a role/tuning problem (the AI lays out its bombers as lane fighters), not a code bug; it does mean every "bot lane" statistic is a bomber statistic.



### Late-game runs (--late, 300 s from 25:00, 3 seeds, tag late_b<switch>, vs late_bbase)
- rally: same mechanism as in 15-minute matches (seats 1/9 at the waypoint 844 > 58 samples, seats 4/6 6 > 960 and 82 > 928); pilot deaths 83 > 67 (-19%), by pilots 52 > 43,
  by minions 24 > 16; mid is not empty late in either version (the motherships sit mid), the empties move from top (101% > 53% summed) to bot (47% > 90%).
- retbig: big ships retreating 919 samples (460 s) over the 3 matches, 639 > 798 of them with a target and 618 > 779 with the trigger pulled (+26%); pilot deaths 83 > 79, retreat trips 85 > 83:
  the mechanism works and is worth 80 s of extra shooting per three matches. DROP (negligible).
- hyper: 137 spool samples (about 11 jumps) over 900 s of late play (12, 58, 67 per seed); pilot deaths 83 > 72, dead samples 4458 > 3696: small. The mothership has usually moved up
  by then, so the jump (taken only when it saves more than speed x 6 s + 1,500 of flying) rarely pays.
- retreat in the late game: 85 retreat trips in the three base late runs, 69 of them end in death (81%), 13 docked: 13 of the trips are capital ships, 30 large (frigates), 16 medium; those (150-350 u/s) retreating 20,000 units from the front
  rarely get home. Same state trigger as in the early game; it is the slow ships that cannot use it. (Observation; a design call whether big ships should stay and fight.)



### N-1b The commute is long but the AI flies it efficiently (no AI fix to make)
beh_audit2 follows every launch until the pilot is within 2,500 of its goal or gets into a fight (3 seeds x 900 s, base): 458 launches (6.4 per pilot per 15 minutes: 3.1 deaths, ~1.9 retreat-dockings,
~0.5 shopping trips, the first launch), 331 arrive without a fight. Small ships: 19.8 s per commute (17.9 s when they arrive), 10,900 units in a straight line on average, mean speed
714 u/s against a top speed of 651 (boost and gear), boosting on 53% of samples, 98% of the samples on the open lane (721 u/s), 2% off it (335 u/s). Medium ships (corvettes): 61 s at 403
(90% of top), large (frigates): 121 s at 238 (88%). That is 10,000 pilot-seconds per match, 16.7 points of the 18.5 "lane, goal far" travel above. A retreat that docks costs more pilot time
than dying: dock trip ~21 s + dock + a new commute ~20 s = ~42 s, against ~12 s of respawn wait (6 s + 0.9 s per game minute) + the same commute = ~32 s (but the dead pilot loses its hull, and the enemy
gets the bounty).

### hyper (BE-hyperspace), long runs (2,400 s cap, seeds 7 and 11, tag long_b*): KEEP-minor (harmless, uses a facility the admiral paid for)
Base seed 7 runs the full 40 minutes, seed 11 ends at 34:37 (mothership killed); in both the Hyperspace Module gets built (last plan step) but the base AI never jumps (0 spool samples).
With --bfix=hyper: 650 spool samples in seed 7 (about 54 jumps in the last part of the match) and 130 in seed 11 (about 11 jumps; that match ended at 33:55); pilot deaths 198 > 191 and 202 > 191, dead samples
9125 > 8725 and 8915 > 8225 (-4% / -8%), shopping trips 33 > 27 and 28 > 27. Worth about 1% of pilot time in the late part of long matches; no other effect. Junglers in state "lane": 0 samples in all four long runs
(jret has nothing to do even in 35-40 minute matches). Hyperspace is the only AI-side shortcut for the commute, so it is kept for fidelity to what a human can do.
