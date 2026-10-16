# Fork brief: pacing_downtime (fork A)

Game: Halcyon Drift, a Godot 4.7 space MOBA (13 v 13: 12 pilots + 1 admiral per team, 3 lanes joined by a middle connector, a
jungle only small ships fit, a movable mothership). You work ONLY in `forks/pacing_downtime/` (a copy of `remake/` made for you).
Read first: `scripts/features/feature_registry.gd` (how a feature plugs in) and `scripts/features/escort_wing.gd` (a finished
example). Docs style: docs/CODE_STYLE.md (WHAT THIS IS / HOW IT WORKS / WHO USES IT header, a `##` note on every function,
variable and constant). Shared rules are repeated in section 4; README.md next to this file has the full set.

## 1. Goal and ingredients
Cut dead air (commute, idle, death waits) without making deaths cheap or the contested big-ship push fast. Keep the
Homeworld-scale speed order (heavier = slower; trips of 20-60 s are wanted, not removed).
- **S4 Low downtime (weight 12) is the target.** S4 = 0.4 x travel + 0.2 x dead + 0.2 x dead_late + 0.2 x rta_late. travel = share
  of pilot-seconds "alive, not engaged, no enemy within 2,500" (report it split into commute = speed >= 40% of f_max, and idle;
  100 pts at <= 0.30, 0 at >= 0.45). dead = dead share (best band 0.05-0.13). dead_late = dead + spooling pilot-seconds / all
  pilot-seconds after 30:00 (100 at <= 0.15). rta_late_s = median seconds from a death after 30:00 to that pilot's next engaged
  sample (100 at <= 150 s, 0 at >= 330). Baseline estimate: S4 about 75 (travel 0.38, dead 0.095, dead_late 0.19).
- Secondary: S5 ramp (engaged share, fight_p90_late) and S11 late_presence rise when pilots arrive sooner.
- Guards: S1 (median minutes not up by more than 4, ended_rate not lower), S6 pilot_kill_share (not down by more than 0.03). Risk:
  defenders also return faster, so sieges can stall.
- Context (AI deep dive, not your ideas): "always park on mid" is going into main (the mothership advances only up the mid lane
  from 20:00), so check that lane arc lengths and hyperspace targets still make sense for a moved mothership. Deep-dive option
  bayA (`bayA:on`, repair bays at 0.22 of the lane instead of 0.33, bays live 160 s -> 300 s) is not in the game; A2 depends on
  surviving bays, so screen `redeploy:on` with and without it only if baseline v2 lacks it (last, optional).

## 2. Ideas to build (all keys default `off` in Rules.VARIANT_DEFAULTS; use `--variant=<key>:<value>`)
### A1 Lane Slipstream, size-scaled | `slipstream:on` | REQ-CHANGE: none
New world part `scripts/world/world_slipstream.gd`, ticking every 0.25 s. Per team and lane, s_front = the largest arc length
along `MapLayout.lane_points(lane, team)` (`Util.project_on_polyline`) over that team's alive minions on the lane and its alive
turrets at that lane's nodes (+1,500 for turrets). A pilot ship gets `Ship.slip = true` when it is within 1,600 of its lane
polyline, its projected s <= s_front - 1,500, it has neither taken nor dealt damage for 4 s (last_damage_time, aggro_time, the
profile's damage_done stamp), and no visible enemy pilot ship is within 2,500. While slipping ShipStats sets f_max = min(1,000,
2.0 x the hull's normal f_max) (fighter 1,000, bomber 800, corvettes 700-860, flak 500, ion 520, destroyer 350, battlecruiser
300), f_accel = max(f_accel, 0.8 x that speed), boost disabled. Any hit taken or dealt ends it at once (the soft cap bleeds the
extra speed in about 1 s). Works both ways, never inside the jungle. Visuals: glowing lane band base-to-front, a SLIPSTREAM tag in
the ship status panel.
AI: none needed (routes follow lanes). Usage: `slip_seconds` (pilot-seconds slipping, by hull class). Pass: S4 +8 (commute part of
travel down 30%+, engaged up); guards hold.
### A1b Slipstream with a FLAT speed | `slipstream:flat` | REQ-CHANGE: "slowly pushing across the map" (heavier ships travel slower; the brief's longer trips for heavier ships)
Same module, but every hull gets f_max = 1,100 u/s while slipping (a 150 u/s battlecruiser then crosses its half 7x faster). Usage
and pass bar as A1; ALSO report final_push_secs, siege_bite_rate and big-ship arrival spread so the council sees what flat speed
does to the push.
### A2 Forward Redeploy | `redeploy:on` | OWNS the hyperspace-timing lever | REQ-CHANGE: none
(1) `AdmiralPlan`: move `['f','hyperspace']` to directly after `['f','frigate']` (prerequisites are met by then; costs 1,200). (2)
`WorldHangar.hyperspace_launch` also accepts an anchored friendly RepairBay or an alive friendly Turret; the ship appears 300
units from it on the side toward its own mothership; HYPERSPACE_SPOOL 6 s -> 4 s. (3) `PilotAI.update_docked`, after shopping, if
the team has the module: pick a destination (siege stage or assault point for big ships and bombers during a siege; defend_point
while defending; else the lane station), then the friendly bay or turret nearest it that is >= 6,000 closer to it than the
mothership and has no visible enemy pilot within 2,500, and call `hyperspace_launch` instead of `launch` (today no AI pilot calls
it for this). (4) `AdmiralBuilder`: once hyperspace is done, its next bay goes at 0.5 of the push or siege lane instead of 0.33.
Usage: `hyperspace_launches` per team. Pass: rta_late down 40%+ (S4 +8), fight_p90_late up. Watch dead_late (spooling counts as
dead).
### A3 Recall | `recall:on` | REQ-CHANGE: none
Ship action `recall` (key T) channels 8 s (SMALL), 10 s (MEDIUM), 12 s (LARGE/CAPITAL); damage taken, firing, boosting or thrust
above 30% cancels. On completion the ship docks as `WorldHangar.try_dock` does, from any distance, with the normal full repair; 60
s cooldown after a completed or cancelled recall; both teams see a pulsing ring on the channelling ship; HUD bar. AI:
`PilotGoals.think_home` and the retreat state recall when the mothership is more than 9,000 away, no enemy pilot is within 3,000
and no damage was taken for 4 s; the ship holds still while channelling. Usage: `recalls_completed`. Pass: S4 +8 via travel and
rta_all; pilot_kill_share must not fall (fleeing ships stop dying).
### A4 Size-scaled respawn | `respawn:size` | REQ-CHANGE: none
`MatchRules.on_pilot_died` reads the size of the hull lost (before hull_id is cleared); respawn_time x SIZE_RESPAWN = [0.6, 0.85,
1.1, 1.3] (small, medium, large, capital); the cap is RESPAWN_MAX x the same factor; gear respawn_pct still applies; respawn
strain counting unchanged. A strike-craft death at 40:00 waits about 25 s instead of 42. AI: none needed. Usage: `size_respawns`.
Pass: S4 +8 through dead and dead_late; watch strain uptime and fights.
### A5 Respawn at a forward bay or the waypoint | `respawn_site:bay` / `respawn_site:waypoint` | REQ-CHANGE: "pilots have to buy personal repair kits at the mothership"
Instead of the mothership hangar, a dead pilot's replacement ship appears 300 units from the friendly anchored RepairBay (or the
admiral waypoint ring) nearest the pilot's lane station and farthest from enemy pilots; fall back to the mothership when none is
safe. The pilot skips the hangar, so it cannot buy kits or gear until it docks later; decide and document how the hull is provided
(suggestion: the last hull class flown if affordable, else a Fighter, normal price). `TeamState.note_respawn()` still counts, so
respawn strain is unchanged. AI: keeps its current go-home rule for shopping (no new skill threshold). Usage: `forward_respawns`,
`shopless_respawns`. Pass: S4 +8 (rta_all, travel) without a kit-buying collapse (report kit purchases per death).
### A6 Kits and gear sold at repair bays | `bay_shop:on` | REQ-CHANGE: "pilots have to buy personal repair kits at the mothership" (module swaps at bays already exist)
A pilot hovering within 600 of an anchored friendly bay with no enemy within 1,500 may buy kits and gear there (same prices,
hangar-style panel, refused while the bay is damaged). AI: `PilotShopping` runs its wish list at such a bay when it is >= 6,000
closer to the pilot than the mothership and the pilot holds enough credits. Usage: `bay_purchases`. Pass: S4 +8 (travel,
rta_late).
### A7 Steeper late respawn curve | `respawn_curve:steep` | DESIGN (the research rejected it: late dead share is already 16-25%)
Set tunables `respawn_base` 6 -> 8, `respawn_per_minute` 0.9 -> 1.8, `respawn_max` 50 -> 90 (LoL/Dota-like late waits). No AI use
needed; usage: `steep_respawns` (waits longer than the old 50 s cap). Longer deaths should widen push windows, so the target is
S2/S3 (final_push, decided_to_end, lead changes) +8 with FUN not falling; S4 will fall and counts inside FUN.

## 3. Levers and alternatives
You own **hyperspace timing** (A2). Do NOT change the turret rebuild lock (teamfights fork), siege AI (endgame fork) or the
admiral plan order beyond the one A2 line. No "at most one merges" group applies to this fork. No fork reads another fork's
variant keys.

## 4. Screening protocol and final report
Shared rules: each idea is a feature module `scripts/features/<name>.gd` + one line in `FeatureRegistry.FEATURES` + a default in
`Rules.VARIANT_DEFAULTS`; hooks only (`Rules.tune`, `unit.incoming_mults`, `world.tick_hooks`, Events, `Game.count_usage`); an off
feature runs no code and draws no random numbers; AI use may not add a skill threshold; game code never reads
`tests/lib/adv_index.gd`. Checks before any match: `load_all` 0 failures, `det_hash` (900 s normal + 300 s `--late`) identical to
main with every key at default, doc_check 100%, bot_pilot, support_probe, ui_tour. Matches ONLY through `RUN =
<SCRATCH>\run_batch.ps1`.
- Screen each idea alone on seeds 101-106: `& $RUN -Project <fork folder> -Seeds (101..106) -OutDir <logs>\<tag> -Tag
  <key>_<value> -Extra "--secs=3600","--skill-jitter","--variant=<key>:<value>"`, then `python tools/fun_score.py --dir
  <logs>\<tag> --vs <baseline v2 logs>`. A screen only REJECTS: keep an idea if S4 (or the stated target) rises 8+ points and FUN
  does not fall; usage near 0 = INVALID (fix the AI use, rerun), never negative.
- Order (drop from the end if the budget of about 60 match-equivalents, 20 of them for the final run, runs out): A1, A2, A4, A3,
  A1b, A5, A6, A7.
- Final: best combination on seeds 101-120 vs baseline v2. Acceptance: FUN +5 with a one-sided 90% paired-bootstrap lower bound >
  0 and no ingredient whose 80% CI is wholly below -15. Success targets: travel <= 0.30 (commute down 30%+), rta_late <= 150 s,
  engaged >= 0.42, dead 0.05-0.13, dead_late <= 0.15, fight_p90_late up 2+, median minutes up at most 4, S4 >= 85.
- **Final report must contain:** S1-S11 (median and IQR) baseline v2 vs the combination; FUN with 90% lower bound; the S4 pieces
  (travel split commute/idle, dead, dead_late, rta_late, rta_all, docked share); usage counters per idea; guard numbers (minutes,
  ended_rate, pilot_kill_share); gate list; keep/drop per idea with the reason; every REQ-CHANGE in plain words (A1b, A5, A6) and
  DESIGN note (A7); cost in lines and files touched.
