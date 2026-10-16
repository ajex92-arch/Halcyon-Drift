STATUS: 12:24 BUILT (all 7 keys, 9 mechanics). Checks: run_checks CHECKS ALL OK, doc_check fully documented, det normal 900 s IDENTICAL. QUEUED all-keys-on match finished clean (q_all below); STILL IN THE SHARED QUEUE (starved by long jobs of other builders since 10:17): the late det run of the fork and the rest of the queued smoke runs; finish with `& SP\cr_finish.ps1` (see "Open items").

# combat_roles build report (fork E)

Fork folder: `FC\forks\combat_roles` (copy of `SP\notate\int3`). Manifest: `FC\forks\combat_roles\FORK_MANIFEST.md` (every file added or changed, keys, values, defaults). All keys default `off`; with every key at its default no code runs, no random number is drawn, no unit is made.

## Ideas built (key: values, what the AI does, flag)

| idea | key: values | what it does | what the AI does with it | flag |
|---|---|---|---|---|
| E1 minions stop out-scaling pilots | `minion_cap: off/on` | `Combat.minion_scale_hook`: a minion's hit on a pilot ship uses `min(stat_scale / (1 + minion_buff), 1.15)`, never more than the minion really has; hull, turrets, bays, mothership, hits on minions untouched; `MINION_VS_SHIP_MULT` stays 0.6 | nothing needed (pilots just stop dying to old minions) | none |
| E2 escorts make big ships deadly | `escort_pd: off/on` | every 0.5 s each LARGE / CAPITAL ship gets support = friendly pilot ships within 2,500 + floor(friendly minions within 2,500 / 3), max 3; `pd_gun`, `flak_auto`, `flak_battery` fire at x(0.6 + 0.2 x support); support 0 also shield regen x0.7; status panel shows ESCORTED xN / ISOLATED | none (the ship rule; E3 reads it) | none |
| E3 the Lance hunts isolated big ships | `lance_role: off/on` | Lance beam x1.35 on a LARGE / CAPITAL pilot ship when the hit lands in its REAR shield zone (same zone test the game uses); no arc change | a Lance (lancer, junglers) with >= 60% hull and no other pilot target picks the nearest visible big enemy ship within 6,000 with support 0 (E2's state if `escort_pd` is on, else no friend within 2,500) as prey, flies to its tail, circles it at 450 from its hull boosting until it is in the rear zone, holds fire until then | none |
| E4 payoff for holding a routing | `routing_payoff: off/on` | hold Weapons / Shields / Thrusters 3 / 4 / 6 / 8 s (small / medium / large / capital) = charged, HUD pip (amber / blue / green) + OVERCHARGE timer. Weapons: first shot from a main gun opens 2 s of x1.4 damage; Shields: first hit adds 40% of the focused zone (Balanced focus: front), the part above normal size is dropped after 6 s; Thrusters: next boost free (energy paid back each tick) and +20% push for 1.5 s. Switch cooldowns unchanged | pilots that ALREADY route energy (the new part checks that the original skill > 0.55 rule asked for a routing; no new skill threshold) request Weapons when an enemy ship is 1.2-2 weapon ranges away (not when retreating / home / < 40% hull / asking for Shields) | none |
| E5 big ships in the jungle | `jungle_big: off/medium/all` | `medium`: MEDIUM ships may use the jungle; `all`: also LARGE and CAPITAL. Gate opening 86 -> 130 / 400, filler-free path half-width 150 -> 260 (`all` only); rocks drawn in the same order, so only rocks next to gates / paths differ (2,556 rocks vs 2,676). Route graph: big ships get the cheaper (flying time, jungle legs at 62% speed) of the lane-only and jungle-allowed route | big-ship pilots take the jungle route when it is faster (inter-lane trips, sieges, defend calls); small ships and junglers unchanged | **REQ-CHANGE: "a jungle ... that only small ships can travel through"** |
| E6 wider maximum zoom | `zoom_max: off/wide/xwide` | `CameraRig.zoom_limits()` follow-mode width x1.5 / x2.0 (5,200 -> 7,800 / 10,400 for a small ship) | none (the AI has no camera): **not screenable** | **REQ-CHANGE: "lock players to a max zoom that is close to their ship ... scales with ship size"** |
| carry-over: bomber seats | `bomber_role: seats` (also `both`) | seats 6 and 10 (striker temperament, both teams) wish list = Fighter only; seat 2 keeps the Bomber | the shopping part (`BomberRoleShopping`) | none |
| carry-over: torpedoes | `bomber_role: torp` (also `both`) | PILOT torpedoes do `torp_small_mult` = 0.6 (was 0.35) to small craft (new tunable); minion / turret torpedoes keep 0.35, so E1 stays the only lever on minion damage vs pilots | a lane Bomber that would otherwise have no target may fire at a small enemy PILOT ship (`BomberRoleTargeting`) | none |

E6 finding: no gameplay number reads the camera zoom. Only drawing code (ship / unit / effect / projectile sizes, minimap view box, command overlay) and `Sfx` (which sounds are loud enough) read it; vision and fog are computed from unit positions. So the only human-visible change is the view itself (fog still hides what the team cannot see), and a headless screen cannot show anything: hand it to the council as a human-playtest item.

Design decisions to know: (1) E1's cap only bites when `Minions.scaling(t)` exceeds 1.15, i.e. for minions born after 15:00 (1.21), or earlier when Reinforced Waves is researched; a 150 s normal match correctly shows 0. (2) The torpedo change is pilot-only (see above). (3) E4 "the next shot" = the first shot from a non-auto gun (a beam counts when it starts firing); the x1.4 covers all damage the ship deals during the 2 s. (4) E3: a big ship turns its nose toward its target, so the circling Lance often meets a turned hull; the rear zone is open only for stretches (arena: 302 rear hits in 60 s with 3 Lances vs a Flak Frigate).

## Usage counters (Game.usage, printed in FUN_JSON)

`capped_minion_hits` (E1) | `big_isolated_seconds`, `big_escorted_seconds` (E2) | `rear_lance_hits`, `lance_prey_picks` (E3) | `charges_spent`, `charges_weapons`, `charges_shields`, `charges_thrusters`, `routing_holds` (E4) | `big_jungle_seconds`, `big_jungle_routes`, `camp_kills_small`, `camp_kills_medium`, `camp_kills_big` (E5; the camp_kills give "who farms the camps" by size of the last-hit ship) | `zoom_wide_frames` (E6; 0 headless) | `bomber_seat_swaps`, `torpedo_small_hits` (carry-overs).

## Checks

1. `run_checks.ps1`: **CHECKS ALL OK** (import, load_all, bot_pilot, support_probe, ui_pilot, ui_admiral). The first run printed one FAIL for support_probe with empty output (the machine was busy); support_probe run alone passed ("0 failures", 14 s) and the whole run_checks run again passed.
2. `doc_check.ps1`: **TOTAL 198 files: headers 198/198, funcs 1119/1119 documented, members 1554/1554 noted**.
3. Determinism with every key at default, seed 7 (reference = int3 itself, reused/run from `SP\notate\int3`):
   - normal 900 s: **IDENTICAL over 180 hash lines** (fork `fun\logs\combat_roles\det\d_fork_n_seed7.txt` vs `fun\logs\endgame_closure\smoke\d_int3_n_seed7.txt`; last line `t=900 230 units, 749aa6eb` both).
   - late 300 s: the int3 reference finished (`det\d_int3_l_seed7.txt`, 60 lines, last `t=1800 226 units, 4bccf106`); the fork's run (`-Tag d_fork_l`) is still waiting for a queue slot (see Open items). It uses the same code paths the normal run proved (no feature installed; the shared edits return the old numbers).
4. Smoke runs, variant ON, seed 101, no SCRIPT ERROR in any of them. Run directly before the lead's "everything through the queue" rule (10:10-10:30); the queued repeats are listed in Open items.

| idea | run | usage counters |
|---|---|---|
| E2, E4, bomber seats | fun_probe `--late --secs=60 --skill-jitter`, keys minion_cap, escort_pd, lance_role, routing_payoff, bomber_role:both on together | `big_escorted_seconds` 673, `big_isolated_seconds` 25, `charges_spent` 16 (`charges_weapons` 12, `charges_thrusters` 4), `routing_holds` 4, `bomber_seat_swaps` 4 |
| E2 (queued) | fun_probe `--late --secs=90`, `escort_pd:on` | `big_escorted_seconds` 962, `big_isolated_seconds` 96 |
| E2 unit | roles_probe `--unit` | alone Battlecruiser: ISOLATED, shield regen 42.0 (normal 60.0), PD rate 4.20 (7.00); Flak Frigate with 2 Fighters: ESCORTED x2, regen 30.0 (30.0), PD rate 7.00 (7.00) |
| E1 unit | roles_probe `--unit` | minion hit (strength 1.35 x 1.1 research) on a pilot ship 6.000 -> 4.646 (ratio 0.774 = 1.15 / 1.485), on a minion 18.000 -> 18.000; `capped_minion_hits` 1 |
| E1 match | fun_probe normal `--secs=150`, `minion_cap:on` (queued) | 0, as designed (scaling is 1.0 at 2:30); a `--late` repeat is queued |
| E3 | roles_probe arena, 2 Lances vs 1 Flak Frigate, `lance_role:on,escort_pd:on` | `rear_lance_hits` 40, `lance_prey_picks` 9, `big_isolated_seconds` 26 (both Lances died in 26 s) |
| E3 | same, 3 Lances, 60 s | `rear_lance_hits` 302, `lance_prey_picks` 14, `big_isolated_seconds` 60; 3 Lances alive, Flak Frigate at 90% |
| E4 Shields | roles_probe `--unit4` | after a hit with a 3.6 s Shields hold: front zone 45.75 -> 65.75 (cap 50, +20 = 40%), back to 50 by 10 s; `charges_shields` 1 |
| E5 `all` | roles_probe travel: Flak Frigate from the mid lane to the camp tl_c at (16600, 9100) | reached 18 units from the camp in ~30 s through the gate; `big_jungle_routes` 1, `big_jungle_seconds` 81; with the key off the same ship cannot get there |
| E5 `all` | Battlecruiser from (12500, 13000) heading east on the mid lane | reached the camp in ~60 s, hull 100%; `big_jungle_routes` 6, `big_jungle_seconds` 81 (starting directly under the gate, which needs a U-turn, it circled and did not get in within 120 s: `big_jungle_routes` 8) |
| E5 `medium` | Logistics Corvette | reached the camp, `big_jungle_routes` 1, `big_jungle_seconds` 84; a Flak Frigate under `medium` correctly stays on the lanes (no jungle counters) |
| E6 | zoom_check (human Fighter, camera pushed to its limit) | width 5,200 (off) / 7,799 (`wide`) / 10,399 (`xwide`); `zoom_wide_frames` 150 over 2 s of human flying, none with the key off; in an all-AI match it stays 0 |
| all keys, real match (queued) | fun_probe `--late --secs=150 --skill-jitter`, seed 101, minion_cap, escort_pd, lance_role, routing_payoff, jungle_big:all, zoom_max:wide, bomber_role:both all on (`SP\fun\logs\combat_roles\smoke\q_all_seed101.txt`), 0 SCRIPT ERROR | `capped_minion_hits` 1348 (E1), `big_escorted_seconds` 1540 / `big_isolated_seconds` 238 (E2), `lance_prey_picks` 119 / `rear_lance_hits` 2 (E3; the Lances rarely get behind a turning hull in a real match), `charges_spent` 90 (72 Weapons, 18 Thrusters, 0 Shields) / `routing_holds` 60 (E4), `bomber_seat_swaps` 7, `torpedo_small_hits` 4 (carry-overs), `camp_kills_small` 11; **no `big_jungle_*` (E5) in these 150 s** (big ships did not take a jungle route in that window; the travel tests above show the mechanic works, longer screens will tell how often the AI picks it); E6 not countable headless |
| all keys | ui_tour pilot and admiral with all 7 keys on | "ui_tour: done", no SCRIPT ERROR (the HUD words / pip drew) |

Arena regressions (tests/arena.gd, one run each, off vs minion_cap, escort_pd, lance_role, routing_payoff, bomber_role:both all on): 3 Fighters vs 3 Lances: off A alive 0, B alive 2; on A 0, B 2 (the int3 baseline already loses this at the default seat skills, so it is not caused by this fork); 2 Bombers vs 1 Flak Frigate: off A alive 2, B 0 / on A 2, B 0; Ion vs Flak: off A alive 1, B 0 / on A 1, B 0. (A single sample each; `arena_matrix` not run: lead's screens.)

## Open items (the shared queue starved my jobs)

From 10:17 until 12:06 the three day-time slots were held by long jobs of other builders; my determinism run `d_fork_l` and the smoke driver `cr_smoke2.ps1` (tags `q_*`, in this order: q_all [DONE], q_e3_arena, q_b_torp, q_e5_all, q_e1, q_e4, q_e6_wide, q_e5_bc, q_e5_medium, q_b_seats, q_units, q_e4_shield) were still waiting for a slot when I stopped. Both are background tasks of this session and keep running while the session lives. To read their results at any time: `& "SP\cr_finish.ps1"` (prints `DET normal/late IDENTICAL or DIFFER` and each queued smoke's script-error count and usage counters from `SP\fun\logs\combat_roles\smoke\q_*`). If the session is gone, rerun:
`& SP\run_batch.ps1 -Project FC\forks\combat_roles -Seeds 7 -OutDir SP\fun\logs\combat_roles\det -Tag d_fork_l -Test det_hash -Extra "--late","--secs=300"` and compare its `hash` lines with `det\d_int3_l_seed7.txt` (cr_finish.ps1 does the comparison).

## Not built / not done

- The "ui_tour screenshot pair at both zooms": `tests/zoom_check.gd` saves `zoom_<value>.png` when run windowed with `--shots=<dir>` (command in its header), but I did not run it windowed (no screens, and the PC is in daytime use); the headless path is tested.
- `arena_matrix` (DUEL_JSON) for E2 / E3 / E4: not run (screens are the lead's job).
- E3 coordinates nothing between several Lances (each circles on its own), and a big ship that keeps its nose on the Lance gives a short rear window; if the screen shows `rear_lance_hits` high but no S8 gain, that is why.
- No requirement gate (wave 5/4/1, mothership constants, ms_duel) is touched by any key.

## Recommended screen commands

`$RUN = SP\run_batch.ps1`, `$FORK = FC\forks\combat_roles`, `$L = SP\fun\logs\combat_roles`. Order from the brief: E1, E2, E4, E3, E5, carry-overs; E6 needs no screen. Each idea alone, seeds 101-106:

```
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\e1_on     -Tag e1_on     -Extra "--secs=3600","--skill-jitter","--variant=minion_cap:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\e2_on     -Tag e2_on     -Extra "--secs=3600","--skill-jitter","--variant=escort_pd:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\e4_on     -Tag e4_on     -Extra "--secs=3600","--skill-jitter","--variant=routing_payoff:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\e3_on     -Tag e3_on     -Extra "--secs=3600","--skill-jitter","--variant=lance_role:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\e5_medium -Tag e5_medium -Extra "--secs=3600","--skill-jitter","--variant=jungle_big:medium"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\e5_all    -Tag e5_all    -Extra "--secs=3600","--skill-jitter","--variant=jungle_big:all"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\b_seats   -Tag b_seats   -Extra "--secs=3600","--skill-jitter","--variant=bomber_role:seats"
& $RUN -Project $FORK -Seeds (101..106) -OutDir $L\b_torp    -Tag b_torp    -Extra "--secs=3600","--skill-jitter","--variant=bomber_role:torp"
```
Cheap late screens for E1 / E2 / E3 / E5 (S6-late, big-ship effects): seeds 101..110, `-Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=<key>:<value>"` (E1 only bites late, so its 3600 s screen is the real test). Arena for S7 / S8 (E2, E3, E4, bomber_role:torp), one per idea:
```
& $RUN -Project $FORK -Seeds 1 -OutDir $L\arena_e2 -Tag arena_e2 -Test arena_matrix -Extra "--auto","--no-pilots","--no-jungle","--no-admiral-ai","--variant=escort_pd:on"
```
(same with `lance_role:on`, `routing_payoff:on`, `bomber_role:torp`; add `"--only=duel"` or `"--only=matrix"` to save time). Then `python tools/fun_score.py --dir $L\<tag> --vs <baseline v2 logs>`. For E5 also read `usage.camp_kills_*` (who farms the camps) and `ms_big_damage_share`; for E1 the pass test is `pilot_kill_share_late >= 0.55` with unattended-turret losses and minutes not worse; for E2 `big_pos_gap <= 0.5`, `big_flak_pd_kill_share` up, plus the arena "2 bombers beat a lone flak frigate" (held in my single run). Final combination run (seeds 101-120): all kept keys in one `--variant=a:on,b:on` string.
