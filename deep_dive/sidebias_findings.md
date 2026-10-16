STATUS: 12:20 working. Evidence in old logs says Halcyon HEAVY ships die ~19% more (seats 1/5/9 K/D 0.66 vs 0.99, 30 matches, t about 2.5); static map/turret/mothership/arena symmetric; in-tick unit order gives a 1-tick edge to one team (sign depends on weapon). Waiting for queue slots (3 other long jobs hold all 3): crnc (CRN duels, 3 order conditions), minion_war (lane war, base vs reversed order).

# Side-bias investigation (Halcyon team 0 / west vs Cinder team 1 / east)

Working copies: SP\notate\bias (edits: test switch --bord=<letters>, tests/sym_audit.gd, arena_bias.gd, ms_sym.gd, early_probe.gd), SP\notate\bias_ref (frozen int3 copy).

## 1. Evidence so far (read from existing logs)
- endings logs (int3_base + int3, seeds 101-106): ended matches 6, all Cinder wins. But seed 105 ended at ~26.7 min in both builds (same early game, so the two builds are NOT independent), and 101/104/105 repeat across the two builds. Distinct early games: ~4-5, so p(all Cinder) is about 1/16-1/32, not 1/64.
- Older logs (all dirs, de-duplicated; matches that ended): Halcyon 5, Cinder 4 (fun_base 2H-1C, p2 1H, vs_test 2H-1C, v1 late 1C, endgame_closure 1C). Including the 6 new ones: 5H : 10C (p about 0.30 two-sided, binomial 15 trials).
- Who gets the first mothership strike (hull damage) in the 12 endings logs: Halcyon's mothership hit in 8, Cinder's in 4 (2 both).
- Kill totals (all 211 distinct early games): 3/5/10 min balanced (t -0.15 / -0.31 / -0.99, H-C kills per match); at 15/20/25 min Cinder +3.5..4.8 kills per match (t about -2.3, n 52-60, but many matches share seeds 7/11/13/17/19/23).

## 2. Static symmetry audit (tests/sym_audit.gd, direct run, 5 s)
World right after setup is an exact x-mirror (rocks 2676, nodes+slots+ore, 12 camps, 60 jungle paths, 347 route nodes+edges, route lengths from each mothership to mirrored targets (max diff 0.003 u), 20000 random asteroid segment queries and their mirrors: 0 mismatches, open-lane grid, lane_for). Only nits: vision-grid cells (22 of 4000 sample points differ at the lit/unlit edge, sub-cell), 5 rocks "unmirrored" = my rounding key only.

## 3. Arena duels with independent randomness (arena_bias, seed 11, 56 fights, identical squads, skill 0.7, Halcyon west and east alternately)
Halcyon 23 : Cinder 24 (9 draws, mostly lance+lance+flak); west 19 : east 28. No big team or side bias at this sample (z -0.15 / -1.31).

## 4. Mothership symmetry (tests/ms_sym.gd, scenario B, seed 3)
Same attacker fleet against the Halcyon mothership (from the east) and against the Cinder mothership (from the west): ms_left 0.644 vs 0.638, 70.3 s vs 70.6 s, attackers all dead both times. The mothership defence is symmetric to within noise.

## 5. Common-random-number (CRN) mirrored duels: the first asymmetry
tests/arena_bias.gd --crn (Game.rr / Game.crn_mirror in game.gd; weapon_mount.gd, pilot_ai.gd draw their rolls by (team, seat, site), Cinder's strafe orbit and gun spread are mirrored): a Halcyon squad and a Cinder squad get the SAME random numbers and mirrored starting positions, so any difference is a code asymmetry. Flak frigate 1v1, seed 1: the pair stays an exact mirror (positions equal to 0.01 u) until 13.6 s, then Cinder's flak battery has fired ONE TICK (1/60 s) before Halcyon's (cd 0.514 vs 0.531) and Halcyon's front shield is down 1.9 first. Reversing the unit iteration order (--bord=u) swaps the order of firing (Halcyon cd 0.497 vs Cinder 0.514). Cause: World._physics_process walks `units` in creation order (world.gd:~449), Halcyon objects first; the team processed second sees the other's position already moved this tick, so at a range edge (closing 25 u/s = 0.4 u per tick) it is in range one tick earlier. Cinder won both CRN flak duels (swap and no swap).

## 6. Independent-RNG arena, 3 seeds (arena_base 11,12,13; 168 fights, 7 squad kinds, Halcyon west/east alternating)
Halcyon 71 : Cinder 72 (25 draws, almost all lance+lance+flak); West 71 : East 72. No team or side bias at the sensitivity of this test (about +-8 points). One-ship-vs-one-ship duels (flak, ion) also even: flak H11 C13, ion H11 C12.

## 7. Old logs, pooled (no new runs; 38 distinct non-late FUN_JSON matches, 217 distinct early-game progress logs)
- Per-seat pilot_table (30 matches with it): Halcyon pilots die more, mostly the heavy seats 1/5/9: kills H 489 : C 613, deaths H 737 : C 620 (heavy K/D 0.66 vs 0.99). Small seats (2,6,10,7,3,11) are even. In 12 of the 12 endings logs the heavy-death difference is H>C in 8, C>H in 3, even 1. Heavy fleet size is about equal (flying heavies at 25 min: H 4.3, C 4.7), so it is combat outcome, not purchases.
- All pilot deaths: H 2365 : C 2052 (t 2.5 per match, matches are correlated by seed so the true t is lower). Pilot kills H 1098 : C 1239.
- Early game is fair: kills at 3/5/10 min balanced (t -0.15/-0.31/-0.99), ore and treasury equal; the Cinder edge appears at 15-25 min (kills -3.5..-4.8 per match, t about -2.3).
- Mothership strikes in the 12 endings logs: Halcyon's mothership was hit in 8 matches, Cinder's in 4.

## 8. CRN (common random number) mirrored duels, 84 fights x 1 seed process (crnc_seed31; 7 squad kinds, 3 order conditions, Halcyon west/east alternating)
Same random numbers and mirrored starts for both teams; only code asymmetries can decide. Result (decisive fights): base order Halcyon 9 : Cinder 13 (z -0.85); --bord=u (unit list walked backwards) 9 : 11; --bfix2=alt (list walked alternately) 11 : 12. West/East 34 : 27 of 81 (not significant). So at duel level the order effect is small: the pair stays an exact mirror for 0.1-13 s and then a one-tick difference (who fires first, who sees whom first) tips fights either way. Where the first break comes from (examples): flak 1v1: Cinder fires 1 tick before Halcyon (13.6 s, unit-list order); fighters+lance: Halcyon team sees the new enemy 0.1 s before Cinder (vision refresh alternates H at ticks 0,12,.. and C at 6,18,..); minion waves: pairs break at spawn because Halcyon and Cinder minions of one wave always get opposite uid parity (Minion._skip = uid % 2 == 0: they act on opposite ticks of the two-tick cycle).

## 9. Minion lane war (no pilots, no admirals, tests/minion_war.gd), lane share (H-C)/(H+C) averaged over t>=210 s
base: seed1 top +0.31 mid +0.40 bot -0.22; seed2 top -0.18 mid +0.04 bot -0.21 (mean +0.02). --bord=u seed1: top -0.40 mid 0.00 bot +0.37. --bfix2=alt seed1: -0.16 -0.08 -0.21. Winner of a lane is chaotic (changes with seed and with order), not tied to one team: no systematic Halcyon or Cinder lane advantage found.

## 10. Other static / small checks
- Turret node assault (tests/turret_sym.gd, same attackers on hal_mid from the east vs cin_mid from the west): 121.6 s vs 121.4 s, same turrets lost.
- Route lengths from each mothership to mirrored jungle camps are identical (e.g. tl_b 17299.8 both).
- Early economy (tests/early_probe.gd, seed 1, 600 s): ore delivered, treasury, drones, facilities, research equal to within one delivery for most of the run; Cinder's admiral acts 0.5 s later (think_t 0.5 + 0.5*team), so its first purchase events are 0.5 s later; middle-node turrets: Cinder got c_top, Halcyon c_bot and c_mid.
- Sub-tick sources of asymmetry found in code (all small, none biased towards one team in a measured way): World._physics_process walks `units` in creation order (Halcyon objects first for anything made in the same tick: motherships, wave minions, start drones); WorldVisibility updates Halcyon at ticks 0,12,.. and Cinder at 6,18,..; AdmiralAI think_t 0.5 s (H) / 1.0 s (C); Minion act-phase by uid parity; Mothership.launch_point uses starboard_of(rotation) so Cinder's launch slot s sits at the mirror position of Halcyon's slot 4-s (pilot seats start up to 180 u apart from where the mirror would put them); PilotGoals._pick_station spreads lane stations to port/starboard of the direction of travel (point-reflection, not mirror: seat 0 stands on its right in both teams).
