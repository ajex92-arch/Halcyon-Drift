STATUS: 10:53 BUILD DONE. All 12 keys built; checks 1-4 pass (details below); the last queued runs (waves_late:none smoke, ms_duel table) never got a slot and were cancelled, see "Not done".

# endgame_closure fork: build report

Fork folder: `FC\forks\endgame_closure` (copy of `SP\notate\int3`). Manifest with every file added or changed, the keys and
their defaults: `FC\forks\endgame_closure\FORK_MANIFEST.md`. Everything is a feature module under `scripts/features/`; shared
code was touched in 12 small places (listed in the manifest).

## Checks

| # | Check | Result |
|---|---|---|
| 1 | `run_checks.ps1` | `CHECKS ALL OK` (run twice: after the first code, and again after the last edit). |
| 2 | `doc_check.ps1` | `TOTAL 196 files: headers 196/196, funcs 1115/1115 documented, members 1612/1612 noted`. |
| 3 | `det_hash`, seed 7, no `--variant` | Normal 900 s: int3 and fork both `DET_HASH END t=900 230 units, 749aa6eb`, all 180 hash lines identical (logs `fun\logs\endgame_closure\smoke\d_int3_n_seed7.txt`, `d_fork_n_seed7.txt`). `--late` 300 s: fork `DET_HASH END t=1800 226 units, 4bccf106`, all 60 hash lines identical to the int3 late baseline that the pacing and teamfights forks produced (`fun\logs\pacing_downtime\det\int3_late_seed7.txt`, `fun\logs\teamfights_jungle\det\int3_l_seed7.txt`). My own int3-late run never got a queue slot in 45 minutes, so I reused those (same code, same machine). |
| 4 | Smoke per idea, variant ON, usage above 0, no SCRIPT ERROR | Done for every key (table below), except `waves_late:none` (see Not done). |

Not run (per the instruction): the screens.

## Ideas, keys, what the AI does, flags, smoke results

All keys default `off` (`retreat` keeps `systems_failure`). Use `--variant=<key>:<value>`.

| Idea | Key: values | What the AI does with it | Flag | Smoke result (usage counters) |
|---|---|---|---|---|
| B1 sieges that land | `siege_fix`: `gather3`, `full`, `stall` | The AI admiral's assault starts when min(3, big ships alive) are massed at the staging point (bomber = half a ship), or after 90 s with 2+ there, or after a 150 s hard cap (my addition: no endless gather). `full` adds formation (PilotFlight asks `throttle()`: a siege ship more than 2,500 ahead of the group centre and faster than 1.1 x the slowest ship within 6,000 of the lead stops thrusting; not within 4,500 of the enemy hull) and base race (early defend call for 2+ visible enemy big ships within 12,000 of our hull closing at more than 40 u/s, only while our team runs no siege). `stall` = stall check judged over 240 s / 10% (tunables). | none | Natural, late symmetric 300 s, seed 101: `gather3` assaults_launched 2, assault_gather_ships 6; `full` assaults_launched 1, assault_gather_ships 4, base_races 4, siege_throttles 0 naturally (6 in the forced `siege` scenario with a bomber 5,000 ahead); `stall`: natural run too short for a long siege (counter 0); forced `stall` scenario: siege_stall_saved 1 and the siege stays in assault (without the key it is called off at once). |
| B2 lane breach corvette | `breach`: `on`, `fulldmg` | Minions are the AI: the first escort corvette of each free wave on a breached lane (last inner-node turret destroyed) is a Breach Corvette (hull 960, shield 320, cannon +20% range, no new gun; stacks with `escort_wing:upgrade`) for 8 waves. `fulldmg` adds x1.0 vs the mothership (Combat.minion_scale_hook) and a 1,700-range siege shell (70 dmg every 2 s, x1.5 vs mothership from the damage table) as its first gun. The AI admiral's siege-lane choice (fewest inner turrets) naturally picks the breached lane. Feed line, HUD banner (20 s), minimap chevron for both teams. | `on` none; `fulldmg` REQ-CHANGE: "weak to attacks by large ships" | Forced `breach` scenario (Cinder's top inner turrets destroyed at 2 s, 58 s): `on`: breach_waves 2, 2 corvettes alive; `fulldmg`: breach_waves 2 (with `breach_extra` also on). No script error with the HUD on (human pilot, `--force-hud`). |
| B3 mothership damage-rate cap | `ms_cap`: `on`, `full` | While the mothership has lost more than 12% hull in 60 s and its shield is down, incoming x0.5 (`on`) / x0.1 (`full`) through `incoming_mults`; AdmiralSiege stall fraction goes 15% to 10% (tunable, unless another key set it). Feed line, banner, and PLATING HOLDING next to the hull bar. | `on` none; `full` REQ-CHANGE: "a lot of health" / "barely" tuning at risk | Forced `mscap` (540 hull/s of capital-ship hits, shield empty, 58 s): no key: mothership dead at about 50 s (0.057 at 49 s); `on`: 0.469 at 49 s, ms_cap_seconds 50; `full`: 0.798 at 49 s, ms_cap_seconds 50. |
| B4 fleet attrition | `attrition`: `on` | Rule only: from 40:00 damage taken by both motherships and all turrets x(1 + 0.04 per full minute, max 1.8), mothership shield refill x(1 - 0.1 per minute); feed warning at 38:00. | none | Natural with `--feature-time-shift=700` (test-only, moves the start earlier): attrition_seconds 50. |
| B5 Last Stand | `retreat`: `last_stand` | Once at 35% hull: shields refill, guns x1.5 for 45 s (cooldowns run 1.5 x faster), launch/respawn unchanged, then x1.25 incoming for the rest of the match. Does nothing for `none` and `systems_failure` (one-line change in `MothershipRetreat`: `!= "systems_failure"`). Feed line, banner. | none | Forced `laststand` (Cinder hull set to 30% at 2 s, 58 s): last_stands 1; after 47 s Cinder has the x1.25 entry. |
| B6 surrender vote | `surrender`: `vote` | From 20:00, one vote per team per 5 min, 30 s long; every AI seat votes by the same scoreboard rule when it opens (team has 6+ fewer turrets alive AND 15+ fewer pilot kills over 600 s); passes at 11 of 13 seats; a human gets a banner and F10/F11 (12 AI yes votes pass anyway: one human cannot veto). A pass ends the match as that team's loss (same end path as a mothership kill, `match_over` sent). FUN_JSON now has `ended_by` (`mothership`/`surrender`/`none`); for a surrendered match `final_push_secs`, `close_out_secs`, `ms_big_damage_share`, `ms_loser_big_dmg` and `ms_loser_hull_dmg` are null (flag: S2's mothership pieces are missing for those seeds; `ended` stays true, so S1 "surrender as not ended" needs post-processing on `ended_by`). | REQ-CHANGE: "only destroying the mothership should end the match" | Forced `surrender` (9 Cinder turrets destroyed, 16 fake Halcyon kills): vote opens at 1503, "The Cinder fleet surrendered." at 1534, `phase=end`, winner Halcyon; usage surrender_votes 1, surrenders 1, surrender_loser_cinder 1. In natural runs no team was far behind, no vote. |
| B7 extra siege minion | `breach_extra`: `on` | Same breach state as B2 (own tracker, independent key): while a lane is breached for 8 waves each free wave on it carries an 11th unit, a Super Minion (corvette copy, hull 1,400, shield 250, cannon +20%, normal multipliers). Banner and chevron as B2. | REQ-CHANGE: "wave of 10, with 5 fighters, 4 bombers, and 1 escort corvette" (gate 7 expected to fail) | Forced `breach`: super_minions 2 (2 alive). |
| B8 softer mothership | `ms_soft`: `hull`, `shield`, `mult` | Rule only. `hull` x0.75 hull_max (the base, so research builds on it), `shield` x0.5 shield_max, `mult` large/capital attackers x3.0 vs a mothership (new tunable `mothership_attacker_large`, read by CombatScaling). | REQ-CHANGE: "a lot of health", "weak to large ships", the (barely) win against frigates | Forced `mscap` 40 s (hull fraction at 9/19/29 s; baseline 0.811/0.623/0.434): `mult` 0.717/0.434/0.152 (dead at 40 s), `hull` 0.749/0.497/0.246, `shield` same as baseline (the scenario keeps the shield empty). ms_soft_hull_damage 23,193 (`mult`), 16,617 (`hull`), 16,618 (`shield`). |
| B9 fewer free waves late | `waves_late`: `slow`, `none` | Rule only. `slow`: from 30:00 `wave_interval` 35 to 70 s (tunable). `none`: from 35:00 no new free wave (director's next wave pushed out of reach); queued and live waves live on; Fleet Command untouched. | REQ-CHANGE: minions "spawn from the mothership regularly" | `slow`, natural with `--feature-time-shift=700`, 420 s: waves_skipped 3. `none`: NOT smoke-run (the queued run never got a slot, see Not done); it is 6 lines and shares its counter logic with `slow`. |
| carry-over lanespawn | `lanespawn`: `on` | Free-wave minions launch at the HOME launch point (same sideways spot, home facing, lane path planned again) once their mothership is more than 1,000 from home. | REQ-CHANGE: minions "spawn from the mothership regularly" | Natural 420 s: lanespawn_waves 6. |
| carry-over eff | `eff`: `on` | Every AI pilot's target score gets a term from the damage table of its main aimed gun against the target's size (+-500 max, 600 points per 1.0 below/above 1.0). | none | Natural: eff_picks 9,293 in 400 s (260 in 58 s). |
| carry-over ms:nosmall | `ms`: `nosmall` | Small non-bomber AI ships no longer pick the enemy mothership as a target nor push it with 3+ minions there. | REQ-CHANGE: "both should be needed to push lanes" | Natural 400 s: small_siege_skips 4. |

Natural runs: `fun\logs\endgame_closure\smoke\s*_seed101.txt` (fun_probe, `--late --symmetric --skill-jitter`), all with 0 script errors. In the
natural 300-400 s runs of `breach*`, `ms_cap` and `retreat:last_stand` no event happened (no inner node fell, no mothership reached 35%), so
those are shown by the forced `fc_smoke` test only. The new test `tests/fc_smoke.gd` (`--test=fc_smoke --scenario=breach|laststand|surrender|
mscap|siege|stall|race|idle`, prints `FC_SMOKE {...}` and the feed lines) forces the rare triggers.

Process note: the forced smokes (each under 60 game seconds, 20-45 s of wall time) and two `ui_tour` runs with 8 keys on (pilot and admiral:
`ui_tour: done`) were started directly BEFORE the lead's rule "all Godot through run_batch by day". After that message I started nothing
directly; everything since went through `run_batch.ps1`.

## Things I changed against the brief (the README lets forks adjust numbers but they must say so)

- B1: no `TeamState.siege_speed_cap` field; the cap lives in the feature object. A 150 s hard cap on gathering (otherwise a siege could wait
  forever once AdmiralSiege's own switch is parked out of reach). The base race never sounds while we run a siege (a defend call pulls siege
  ships home, PilotGoals step 6), so "never cancels our own siege" holds trivially.
- B3: factor applied only while the shield is down (so shields stay untouched); the hull bar "tick" is the words PLATING HOLDING.
- B5: x1.5 guns done by faster cooldowns (the fire multiplier is rewritten every tick by `MothershipGuns.fire`, a hook cannot change it).
- B6: AI seats vote when the vote opens (not when it closes), so a pass is decided by the state at the opening.
- `--feature-time-shift=N` (test-only; `attrition` and `waves_late` only) so a short late run can reach 30/35/40 min. Never use it for a screen.

## Not built / not done

- `waves_late:none` smoke: was queued through run_batch (together with repeats of the forced smokes) but waited 10+ minutes without a slot and I cancelled it. The `none`
  code is 6 lines (`director.next_wave = INF`); its counter logic is shared with `slow`, which ran. Command: `& SP\eg_lane.ps1 -Names w_none`
  (log `fun\logs\endgame_closure\smoke\w_none_seed7.txt`, look for `waves_skipped` in the `FC_SMOKE` line).
- `ms_duel` table (winners, % HP left) for ms_cap on/full, last_stand and ms_soft values: `eg_duel.ps1` waited for a slot for over 20 minutes; only
  `duel_base_H` finished (attackers destroyed after 92 s, mothership 38% hull, 27% of total HP left). The gate for `ms_cap:on` (same winners,
  upgraded win ends with at most 40% HP) is therefore UNCHECKED. Run in the background: `& SP\eg_duel.ps1 -Scenarios H,B,A,D -Configs base,cap_on,cap_full,laststand,soft_hull,soft_shield,soft_mult,sysfail`
  (tags `duel_<config>_<scenario>`, logs in `fun\logs\endgame_closure\duel`, read the `RESULT` lines).
- int3's own `--late` 300 s det_hash was not run by me (see check 3).
- Nothing from the brief is left unbuilt. The B3 "tick" on the hull bar is a label, not a mark on the bar.

## Recommended screen commands (the lead runs them)

```
$RUN = SP\run_batch.ps1 ; $FORK = FC\forks\endgame_closure
# each idea alone, 10 symmetric late runs, order B1,B2,B3,B5,B7,B6,B9,B8,B4, then the carry-overs:
& $RUN -Project $FORK -Seeds (101..110) -OutDir <logs>\<tag> -Tag <key>_<value> -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=<key>:<value>"
```
Keys and values to pass: `siege_fix:gather3`, `siege_fix:full`, `siege_fix:stall`, `breach:on`, `breach:fulldmg`, `ms_cap:on`, `ms_cap:full`,
`retreat:last_stand` (compare with `retreat:systems_failure` on the same seeds), `breach_extra:on`, `surrender:vote`, `waves_late:slow`,
`waves_late:none`, `ms_soft:hull`, `ms_soft:shield`, `ms_soft:mult`, `lanespawn:on`, `eff:on`, `ms:nosmall`.
Special cases:
- `attrition:on` starts at 40:00, so a 1200 s late run (25:00 to 45:00) sees only 5 minutes of it: screen it on full matches
  (`--secs=3600 --skill-jitter`, seeds 101-106, no `--late`) or late with `--secs=2400`.
- `surrender:vote`: read `ended_by` in FUN_JSON; S1 "both ways" = count surrendered seeds as ended (as scored) and as not ended (post-process
  on `ended_by`). A lopsided match is needed for a vote, so check `usage.surrender_votes` / `surrenders` summed over the seeds (0 = INVALID, not negative).
- `waves_late:slow` / `none` start at 30:00 / 35:00: late runs see 15 / 10 minutes of the effect (enough for S2 / S6 late).
- `breach*`, `ms_cap` and `retreat:last_stand` events may not occur in every seed (the natural 300-400 s smoke saw none): sum `usage.breach_waves`,
  `ms_cap_seconds`, `last_stands` over the 10 seeds before reading the score.
- Combinations after the singles: B1 `full` + B2 `on` + ONE of B3 or B5 (never both): `--variant=siege_fix:full,breach:on,ms_cap:on`.
- Mothership keys (B3, B5, B8): run the ms_duel table first (see Not done).
