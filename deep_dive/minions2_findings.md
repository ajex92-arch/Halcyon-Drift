STATUS: 02:28 DONE. MN2-1 retarget KEEP (switch rate 2.0-2.6 -> 6.6-9.8 per fight minute, all 3 seeds measured), MN2-2 numbers, MN2-3 lanespawn = design call (1 seed), MN2-4 bombers = design call; the rest measured clean.

# Minions round 2 (baseline = --mfix=lead,gate,route,los)

Working copy SP\notate\dd_minions_fix (runs from snapshots dd_minions_s1 / s2). New switch: "retarget".
Logs: SP\deepdive\runs\mn\mn2_<name>_seed<N>.txt; tools SP\deepdive\minions_tools\mn2_summ.py (new counters, "--sum tag::glob" adds up seeds) and summ.py.
All numbers: 900 s all-AI matches, seeds 7, 11, 13 summed or per seed. Runs are deterministic (mn2_base reproduces mn_fix exactly), so differences are the change.

## MN2-1  Minions never re-pick a target while it is still "valid" (stale targets)  [major, KEEP the fix]

Code: scripts/entities/minion_targeting.gd:39-44 (pick_target step 1)
    if m.target != null and is_instance_valid(m.target) and m.target.alive:
        ... if m.position.distance_to(tp) < m.aggro * 1.15 and m.target.visible_to(m.team) and tp.distance_to(anchor) < Minion.LEASH:
            return
The scores (enemy ship that just hurt our pilot -1200, minion 0, structure +600, drone/ward +900, other ship +1200) are only used when the
target is lost. minion.gd's own header says they "like, from most to least: an enemy ship that just hurt one of our ships nearby, enemy
minions, enemy structures, drones and wards, any other enemy ship". A minion that picked a pilot ship (+1200) because no minion was near
keeps chasing it when an enemy wave arrives; one that is shooting a minion ignores the pilot that is hurting our pilot.
Measured (probe: every fighting 0.25 s, compare the current target's score with the best enemy in aggro range, copy of the formula):
  baseline, 3 seeds: fight time on a target scoring >= 600 worse than the best available: fighters 13.6%, bombers 17.3%, corvettes 21.0%
  (>= 1200 worse: 6.3 / 9.8 / 11.6%). Biggest cases: current target is a pilot ship while an enemy minion is better (seed 7: fighters 868 s,
  bombers 747 s, corvettes 424 s of ~10,000 / 10,500 / 4,500 s of fighting), current target a minion while a pilot that just hurt ours is in
  reach (the "aggro ignored" counter: fighters 4.6%, bombers 7.8%, corvettes 7.5% of fight time).
  Mining drone / ward / bay held while a minion or turret is in reach: only 0.8-0.9% of fight time (not a problem on its own).
Fix (switch "retarget", minion_targeting.gd): at each think the minion also looks around when it already has a valid target and moves to the best
enemy only if that scores at least 600 lower than its current target (the old one is kept otherwise; a copy of the score formula, score_of(),
is used for the current target). ~15 lines, no new numbers except the margin 600.
Result (retarget on top of the fixed baseline, 3 seeds summed, base -> retarget):
  stale >= 600 fight time   fighters 13.6 -> 1.6%, bombers 17.3 -> 1.3%, corvettes 21.0 -> 1.5%
  fighter time on pilot ships 38.1 -> 31.9% (minions 54.7 -> 62.1%); bombers ships 32.6 -> 22.9%
  minion damage to pilot ships (per 900 s): 23,566 -> 16,982 (-28%); the unfixed game had ~16,400, so this undoes the +27..36% side effect of round 1
  pilot deaths by minions (3 seeds): 86 -> 49; all pilot deaths 275 -> 228; by other pilots 161 -> 151
  minion-vs-minion damage 212,745 -> 216,883 per run (+2%), minion deaths 4,099 -> 4,091; alive minions 124 -> 119 on average
  line of battle / wave outcomes unchanged in shape (pair loser team 0: 54% -> 44%, n=201/202 pairs, within noise)
Risks: more calls per think (a second pass over the units near each fighting minion, 4x a second); hysteresis 600 stops most flip-flop
  (switch counts to be checked in the next runs); changes the balance of minion vs pilot fights (less minion damage on pilots, as intended).
Switch rate (the cost): minions change target while the old one is still alive 2.0-2.3 times per fighting minute in the baseline (all 3 seeds, mn2_base2: fighters 2.1-2.6, bombers 2.0-2.1, corvettes 2.1-2.3)\nand 6.6-9.8 per minute with retarget (all 3 seeds, mn2_rt2) - about every 7 s instead of 28 s. It is mostly switching to a nearer minion or to the best category; shots do not\nsuffer (fighter bolt hit-a-unit rate 59.1% -> 60.1%, predicted-hit 78% -> 80% on seed 7) but a calmer variant (margin 1,000, or switch only when the KIND improves) was not tried.\nLate game (--late, seed 7, one match each): retarget is neutral there (minion damage to pilot ships 254 -> 217 per second, off-lane share unchanged).\nTried in copy: yes (mn2_rt_seed7/11/13 and mn2_rt2 = the same matches again with the extra counters; identical numbers, so the probe changes nothing).
## MN2-2  Round-1 side effect on pilots, measured, and how MN2-1 removes it  [design/balance note, numbers for the lead]

Three states, same seeds (7, 11, 13), 900 s, summed over the 3 matches (logs mn2_nofix / mn2_base / mn2_rt; the probe counts pilot-ship deaths by killer):
                                          no fixes    4 fixes (baseline)   4 fixes + retarget
  minion damage to pilot ships (per run)  16,383      23,566 (+44%)        16,982 (+4%)
  pilot deaths, all causes                221          275 (+24%)           228 (+3%)
  pilot deaths killed by minions          56           86 (+54%)            49 (-12%)
  pilot deaths killed by pilots           148          161                  151
  minions killed by pilots (last hit)     766          603 (-21%)           525 (-31%)
  minion-vs-minion damage (per run)       213,103      212,745              216,883
  all minion deaths                       3,992        4,099                4,091
So the "+27..36% minion damage to pilots" of round 1 is really +44% damage and +54% pilot deaths to minions on these three seeds; the lead-aim
fix makes every hit land, and the wave also keeps shooting pilots it should have dropped (MN2-1). With "retarget" the pilot-facing numbers go back
to the unfixed level. What does not come back: pilots land fewer last hits on minions (-31% vs unfixed, 255 -> 175 per run), because the waves
now kill each other sooner (the same number of minions dies in the end, since a wave is a fixed pool of 1,500 per run); if the pilots' minion income
matters for the fun measurement, that is the knob to look at (e.g. Rules.MINION_VS_MINION_MULT 1.8, or the bounty), not the aiming.
Tried in copy: numbers above (no new switch).
## MN2-3  After the mothership moves (AI admiral: from ~21:00), 25-37% of minion time is spent more than 1,800 from the lane  [design call, numbers]

Code: scripts/world/minion_director.gd:_spawn  (var slot := randi() % 5 ; return world.spawn_minion(team, type_id, lane, ms.launch_point(slot)))
 + scripts/world/world_queries.gd:lane_path_from (minions join the lane at the nearest lane point; with "route" they fly the big-ship route graph there).
DESIGN.md:386-388 says launches follow the moved mothership, so this is intended; what it does to the minions was never measured.
The AI admiral parks its mothership up the pushed lane (late seeds 7 and 11: team 0 at x=15,296 mid lane, team 1 at x=20,000 y=4,100 / 7,600 on the top lane
by 1,830-1,870 s). A wave of the other two lanes then starts 4,000-18,000 away from its lane (e.g. route_check: from (14334,3800) the bottom
lane is joined at its home end, a trip of ~25,000 = 75 s at 330/s; from (16315,13000) the top lane is joined at the crossing (20000,3800)).
Measured, late runs (25:00 start, matches ended by a mothership kill after 372 s and 331 s), seed 7 / seed 11, share of minion-seconds:
  more than 1,800 from the lane: fighters 25.5 / 27.5%, bombers 29.5 / 27.1%, corvettes 33.7 / 36.8%  (in the 900 s opening games: 0.2-0.5%)
  walking backwards along the lane: fighters 18.1 / 13.9% of walking time (opening: 0.9%); backtrack (goal >300 behind) 11-15% (opening 0.1%)
  fighter/bomber life 45-51 s (opening 72-77 s); 21 / 10 stuck episodes (all corvettes on long routes, 2 s each: negligible)
  first contact with a minion: travel_to_contact median 17-65 s per lane vs 45-61 s in the opening, and its 10th percentile is 5-6 s (fights at the launch point itself)
Effect on a measurement: after ~21:00 the "lane waves" are really "mothership waves": the lane the mothership sits on gets its wave at once, the other two
arrive 30-75 s late and from the side. Same for every variant that uses the same admiral, so it is a constant bias, not noise; it matters if the fun
metrics look at lane balance or wave timing after 20:00.
Fix tried for MN2-3 (switch "lanespawn", minion_director.gd:_spawn, ~6 lines): if the mothership has moved more than a lane's half width (1,800) away from the
lane, the lane's minions launch at the lane's home end (MapLayout.lane_points(lane, team)[0], keeping the launch spot's offset) instead of at the mothership.
Result, late seed 7, 500 s (one match each, so the game itself differs; the minion numbers are what counts), base -> lanespawn:
  more than 1,800 from the lane   fighters 25.5 -> 0.0%, bombers 29.5 -> 0.0%, corvettes 33.7 -> 0.0%
  walking backwards / backtrack   fighters 18.1 / 11.8% -> 0.8 / 0.0%
  top and bottom waves meet at    median 65 s after launch (like the 61 s of the opening) instead of 5-65 s; mid 28 s
  minion damage to turrets        45,083 -> 3,220 (the forward mothership's waves were sieging turrets directly); minion-vs-minion damage 116k -> 296k
  the match ran the full 500 s instead of ending at 372 s (mothership kill)
Risk: this removes the late-game value of moving the mothership forward (DESIGN.md:386-388: "Spawns, minion launches and docking follow it"), and the AI admiral's
"advance" plan (DESIGN.md C19) was chosen on matches that include it. So: DESIGN CALL for the user, not a bug. If the fun measurement should compare lane
play after 20:00 across variants, switch it on; if siege-by-forward-mothership is part of the game to be measured, leave it.

## MN2-4  Bombers do ~11% of minion damage with 40% of the bodies  [design call, numbers only]

Rules.gd:129 torp row: x0.35 against small craft; minions are small craft (hull class 0) and so is most of what a bomber meets; pilot ships take another x0.6
(MINION_VS_SHIP_MULT), minions x1.8. m_torp: 28 dmg, 480 u/s, 2.2 s; fired only when the nose is on the aim point (gate), so no waste from the peel-off any more.
Damage by weapon, retarget run, 3 seeds: to minions fighter bolts 358,757 (55%), corvette cannon 154,989 (24%), bomber torpedoes 74,055 (11%), corvette PD 62,849 (10%);
to pilot ships bolts 35.4k (69%), cannon 7.7k, PD 4.5k, torpedoes 3.3k (6.5%). Torpedo outcome (baseline): 31% hit a minion, 16% hit a pilot ship, 65-67% expire,
3-5% hit rocks. Bomber target time: 62% minions, 33% pilot ships, 2% turrets. Not a bug: bombers are the damage sponge and the only wave unit that hurts structures
and corvettes (x2.2 / x1.0), but they spend a third of their time chasing pilot ships they cannot hurt (retarget lowers it to 23%). Skipping small craft for bombers
(like the repair-drone rule in pick_target) would turn them into passive targets; not tried, it is balance.

## Measured clean (baseline = 4 fixes; 900 s, seeds 7/11/13) - no finding

  idle while walking: fighters/bombers 0.1-0.2% of walk time, corvettes 0.7-0.8%; stuck episodes 1-7 per match (corvettes only, 14 s at most)
  inside rocks (centre in a rock): fighters 0.1-0.3% of their time, bombers 0.1-0.2%, corvettes <0.1%; outside the lane by 1,800: 0.2-0.5%; in the jungle 0.1-0.4%
  walking backwards along the lane 0.8-1.0% (corvettes 1.1-1.2%); backtrack to an old waypoint 0.1%; past the leash 0.0%; chase of more than 400: fighters 1.4-1.6% of fight time
  gun/drone/ward/bay held while a minion or turret is in weapon reach: 0.6-1.2% of fight time; target time on mining drones 1-2.5%, wards 0.3%, bays 0.8-1.1%
  side bias: the wave wiped first (pairs launched together) is team 0's in 54.2% of 201 pairs (no fixes 42.6% of 190, retarget 44.1% of 202); the sign flips between
    seeds and builds, so no side bias. Line of battle (0.5 = middle of the lane): top 0.48, mid 0.52, bot 0.47 on average, per match 0.38-0.57, sd within a match 0.06-0.17;
    one lane often runs one way for a whole match (bot seed 7: 0.38, team 0 lost 86% of its pairs; bot seed 13: 0.56): pilots and the admiral decide that, not the minions
  lanes: alive per team per lane top 21.9 / bot 22.2 / mid 17.8 (mid is shorter: first contact at 45 s vs 61 s, identical in all seeds); 2.5-2.9 waves alive per lane
  wave timer: MinionDirector.tick() launches queue entries when world.time >= launch time, so a launch is at most one tick late; waves every 35 s, 1,500 minions per run per seed
  corvettes: first contact 52-53 s after launch, same as the fighters and bombers they travel with; they live 94-99 s against 74-79 s; stuck/parked 14 s per run at most
  turrets: minions are in an enemy turret's reach 1.1-2.2% of their time and are shot at for 17-36% of that; 60-73 of ~1,370 minion deaths are turret kills; minions
    deal 1.9-3.6k damage to turrets per 900 s (x0.35 rule) and every turret kill (1-3 per run) is a pilot's: the lanes are not sieged by minions alone (design)
  Fleet Command: the AI plan never builds it (admiral_fleet_command.gd header), so the free waves never stop in AI matches