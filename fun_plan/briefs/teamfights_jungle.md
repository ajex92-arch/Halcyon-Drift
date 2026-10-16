# Fork brief: teamfights_jungle (fork D)

Game: Halcyon Drift, a Godot 4.7 space MOBA (13 v 13: 12 pilots + 1 admiral per team, 3 lanes joined by a middle connector, a
jungle of asteroids and derelict camps that only small ships fit). Pilot seats per team: 0/4 top, 1/5 mid, 2/6 bot (a third laner
each on seats 8, 9, 10), 7 flex, 3 and 11 junglers. You work ONLY in `forks/teamfights_jungle/` (a copy of `remake/`). Read first:
`scripts/features/feature_registry.gd`, `scripts/features/escort_wing.gd`, `scripts/ai/pilot_goals.gd`, `scripts/data/jungle.gd`,
`scripts/world/jungle_director.gd`, `scripts/data/turret_data.gd`. Docs style: docs/CODE_STYLE.md. Shared rules repeated in
section 4; README.md has the full set.

## 1. Goal and ingredients
Make the late game a major engagement: pull the whole team, junglers included, into fights; give the jungle a late stake that
creates small-ship skirmishes at its edges; make lane objectives persist so node fights matter.
- **S5 Skirmish ramps into a major engagement (weight 11), the main target:** fight_p90_late (90th percentile of the largest
  pilot-vs-pilot fight after 25:00; 0 at <= 6, 100 at >= 14; a fight = 3+ ships of EACH team in a cluster within 2,500 with a
  pilot-sourced hit in the last 4 s), fight_ramp (late/early mean fight size; T 1.0/1.6/3.0/4.5), engaged share (T
  0.25/0.40/0.60/0.75), pk_ramp (pilot kills per pilot-minute after 25:00 / before 10:00; T 0.8/1.3/3.0/5.0). Baseline about 57
  (largest fights 8-14 of 24).
- **S11 Teamwork (weight 4):** assisted_kill_share (T 0.25/0.50/0.80/0.95), low_kp_pilots (pilots per team with
  (kills+assists)/team kills < 0.08; 100 at <= 1, 0 at >= 4), late_presence (share of pilot x 5-min windows after 25:00 in at
  least one fight; 0 at <= 0.30, 100 at >= 0.75). Baseline about 65. Junglers sit out: jungle share stays 15-16% of pilot samples
  through 60:00.
- Guards: S1 (median minutes up at most 4), S2 ms_big_damage_share >= 0.60, S6 pilot_kill_share_late not lower, comeback15 and
  even15 (longer locks can snowball), unattended_turret_loss_share (thinned lanes), CPU (`--profile`, bigger fights cost more).
- Context (AI deep dive): "always park on mid" is going into main, so after 20:00 the siege lane is mid; D1's push lane must read
  the real siege/push lane state, not assume a lane. A jungler wedged in rock at (13672, 8708) for 900 s on seed 101 (slot 11) is
  a known residual: if low_kp_pilots flags that seat on seed 101, check it before blaming an idea.

## 2. Ideas to build (all keys default `off` in Rules.VARIANT_DEFAULTS; use `--variant=<key>:<value>`)
### D1 Late grouping on the push lane | `group_late:on` | REQ-CHANGE: none
In `PilotGoals`, after 25:00 the push lane P is the siege lane if there is one, otherwise AdmiralLanes' push lane. Seats on P
stay. On each other lane only the two lowest-numbered seats hold it. The third laner of those lanes (seat 8, 9 or 10) and the flex
pilot (seat 7) move to P, taking station 800 behind the centroid of friendly big ships on P, or behind the wave front if there are
none. This replaces the existing odd-seat waypoint rally while the variant is on. Junglers (3, 11) switch to the lane state on P
whenever a siege or defence is active; otherwise they jungle within 6,000 of P. Everyone reverts when P has had no friendly big
ship for 60 s. Usage: `grouped_seconds`. Pass: S5 +8 (fight_p90_late up to ~14, late_presence up); watch travel and unattended
turret losses on the thinned lanes.
### D2 Derelict Battleship and the carried Salvage Core | `salvage_core:on` | REQ-CHANGE: none (a permanent camp with a normal respawn, not a dynamic event zone)
In each quadrant the existing carrier camp nearest the connector becomes the Derelict Battleship (no new clearing, no map-builder
change; `JungleDirector` spawns the type at that camp id, 300 s respawn). Hull 4,000; 3 auto turrets (2/s x 12, range 1,000);
launches 3 snub fighters every 10 s while engaged. Reward 450 credits split by damage share (>= 10%) plus the usual 25% last-hit
bonus. The last-hitter carries a Salvage Core for 120 s: friendly minions within 2,500 of the carrier deal x1.4 to structures and
the mothership (after the minion multipliers; none vs ships) and get +20% hull; lost when the carrier dies (the killer earns
+150); the carrier glows gold. Use `world.combat.minion_scale_hook`. AI: junglers take the camp when 2+ friendly small ships are
within 3,000 or after 18:00; laners on the adjacent lane help when a friendly is engaging it and they are within 4,000. Usage:
`cores_carried`, `core_minion_seconds`. Pass: S5/S11 +8 (late_presence, low_kp_pilots); watch pilot_kill_share_late and
ms_big_damage_share.
### D3 A jungle that scales with the match | `jungle_scale:on` | REQ-CHANGE: none
Camp rewards x(1 + 0.08 per 5 min); derelict hull and turret damage x(1 + 0.05 per 5 min); carrier snub fighters scale the same.
After 20:00 AI junglers gank a lane whose enemy wave is past the middle node when a visible enemy pilot below 50% hull is within
5,000 of a jungle exit. Usage: `gank_attempts`. Pass: S11 +8 (low_kp_pilots, assisted share); the jungle must not become the best
late income (report play_income_share and jungle time share).
### D4 Persistent nodes | `node_persist:on` | OWNS the turret rebuild-lock lever | REQ-CHANGE: none
Tunable `rebuild_lock` (TurretData.REBUILD_LOCK) 60 -> 150 s. A rebuilt turret spawns at 50% hull and repairs 1% of hull_max per
second up to full. The AI's `AdmiralBuilder` rebuilds the node nearest its own mothership first. Backdoor protection and aggro
rules unchanged. Usage: `persist_rebuilds`. Pass: S5 or S2 +8 (turrets_destroyed per match down, ms_pressure_onset earlier, fight
presence at nodes up); watch comeback15, even15, unattended_turret_loss_share.
### D5 Timed epic neutral at the Crossing | `epic:dreadnought` and `epic:elder` | REQ-CHANGE: "Remove the dynamic event zones" (a timed spawn event)
dreadnought: a Derelict Dreadnought (hull 9,000; 4 auto turrets 3/s x 15, range 1,200; 4 snub fighters every 12 s while engaged)
spawns at the Crossing (middle of the connector) at 18:00 and 6 min after each death; report which hull classes can reach and
fight it. Killer team gets the "Dreadnought Boon" for 180 s (all its minions +25% hull and x1.4 to structures and the mothership,
none vs ships; via the minion hook) and 250 credits to each pilot within 3,000 of the kill. elder (restored late buff): same
Dreadnought, but the first one killed after 30:00 grants an "Elder Core" for 150 s instead: friendly pilot hits kill enemy turrets
below 25% hull outright and deal x1.25 to the enemy mothership below 50% hull (an execute meant to kill limbo). Banner and minimap
icon for both teams. AI: flex and jungler seats go when 3+ friendly small ships are within 6,000; laner seats within 5,000 join
when their lane wave is dead; no skill threshold. Usage: `epic_kills`, `boon_seconds`, `elder_cores`, `elder_executes`. Pass: S5
+8 (fight_p90_late, late_presence) with S2 ms_big_damage_share held.
### D6 Salvage beacons with a sensor-blackout reward | `beacons:on` | REQ-CHANGE: "Remove the dynamic event zones" (temporary sensor blackout) and the capture points that mining drones replaced
Two salvage beacons on the connector's flanks (positions chosen from MapLayout on open ground, stated in the report). A pilot ship
hovering within 700 for 20 s with no enemy pilot within 1,500 captures one (progress pauses when contested); it stays held until
the other team captures it. A held beacon pays 60 credits per 60 s to its team's pilots within 4,000 and every 90 s blacks out the
enemy for 15 s (its ward vision and minimap contacts in the lane half nearest the beacon go dark). AI: junglers and flex take the
nearest unheld beacon when 2+ friendly small ships are within 4,000. Usage: `beacon_captures`, `blackout_seconds`. Pass: S5/S11
+8.
### D7 A fourth jungle camp per quadrant | `camp4:on` | DESIGN (map-generation risk)
Under the variant only, add a fourth derelict camp per quadrant (midway between that quadrant's lane-side clearing and the
connector) through `MapLayout.CAMPS`, so the asteroid keep-outs and the jungle path graph (`map_builder_jungle.gd`) change ONLY
when the key is on (det_hash with it off must not move). Same camp type, reward and respawn as the existing medium camp. Verify
every camp is reachable by a 17-unit ship (load_all plus the escape planner) and that rock-gap sealing is unchanged. Usage:
`camp4_kills`. Pass: S11 +8 (low_kp_pilots); S5 late fights must not shrink.
### D8 Early feats of strength | `feats:on` | DESIGN (the research rejected it: an early snowball that fixes no late problem)
Three early feats, each claimable once per match and visible on the scoreboard: first pilot kill, first turret destroyed, first
derelict camp cleared. At 14:00 the team holding 2+ feats gets "Vanguard": 300 credits to each pilot and wave minions +10% hull
for 6 min. Banner at each feat; automatic for the AI. Usage: `feats_claimed`, `vanguards`. Pass: S5 +8 (engaged share, pk_ramp)
while fight_ramp and even15 are reported (an early snowball lowers both).

## 3. Levers and alternatives
You own the **turret rebuild lock** (D4). Do NOT change hyperspace timing (pacing fork), siege AI (endgame fork) or economy
numbers beyond the stated rewards. No "at most one merges" group for this fork. No fork reads another fork's variant keys; D1
reads only the live siege state.

## 4. Screening protocol and final report
Shared rules: each idea is a feature module `scripts/features/<name>.gd` + one line in `FeatureRegistry.FEATURES` + a default in
`Rules.VARIANT_DEFAULTS`; hooks only (`Rules.tune`, `world.combat.minion_scale_hook`, `world.push_weight_hooks`,
`world.tick_hooks`, Events, `Game.count_usage`); an off feature runs no code and draws no random numbers; AI use may not add a
skill threshold. Checks first: `load_all`, `det_hash` (900 s normal + 300 s `--late`) identical to main with every key at default,
doc_check 100%, bot_pilot, support_probe, ui_tour. Matches ONLY through `RUN =
<SCRATCH>\run_batch.ps1`.
- Screen each idea alone on seeds 101-106: `& $RUN -Project <fork folder> -Seeds (101..106) -OutDir <logs>\<tag> -Tag
  <key>_<value> -Extra "--secs=3600","--skill-jitter","--variant=<key>:<value>"`, then `python tools/fun_score.py --dir
  <logs>\<tag> --vs <baseline v2 logs>`. A screen only REJECTS: keep an idea if its target rises 8+ points and FUN does not fall;
  usage near 0 = INVALID, not negative.
- Order (about 6 match-equivalents each; ~60 total, 20 for the final, so about 6 screens fit): D1, D4, D2, D3, D5 (dreadnought),
  D5 (elder), D8, D6, D7; drop from the end.
- Final: best combination on seeds 101-120 vs baseline v2. Acceptance: FUN +5 with a one-sided 90% paired-bootstrap lower bound >
  0 and no ingredient whose 80% CI is wholly below -15. Targets: fight_p90_late >= 14 with a 16+ pilot fight after 25:00 in >= 70%
  of seeds, fight_ramp >= 1.6, late_presence >= 0.75, low_kp_pilots <= 1 per team, engaged >= 0.40, minutes up at most 4, S5 >=
  80, S11 >= 80.
- **Final report must contain:** S1-S11 median/IQR baseline v2 vs combination; FUN with 90% lower bound; every S5 and S11 piece;
  guard numbers (ms_big_damage_share, pilot_kill_share_late, unattended_turret_loss_share, comeback15, even15); `--profile` mean
  tick on 2 late seeds vs the DESIGN B5 budget; usage counters; gate list; keep/drop per idea; every REQ-CHANGE (D5, D6) and
  DESIGN note (D7, D8) in plain words.
