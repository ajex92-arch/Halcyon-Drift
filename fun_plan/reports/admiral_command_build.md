STATUS: 12:28 FINISHED (budget). Checks 1-3 passed; combined late smoke passed (6 ideas, 0 script errors); the scripted probe and a normal-start weak/early smoke are still WAITING FOR A QUEUE SLOT (daytime limit 3), see "Pending" at the end

# admiral_command fork: build report

Fork folder: `FC\forks\admiral_command` (copy of `SP\notate\int3`). Manifest with every file, key, value and number:
`FC\forks\admiral_command\FORK_MANIFEST.md`. Logs: `SP\fun\logs\admiral_command\{det,smoke,probe}`.

## Ideas built (all default `off`; `--variant=<key>:<value>`)

| idea | key: values | what the AI admiral does with it | flag | counters |
|---|---|---|---|---|
| F1 Command assets | `assets`: `on` (Sweep + Supply), `full` (+ Barrage), `xray` (Sweep sees through rocks) | `AdmiralAssetsAI` (once a second, computer admirals only, never starves the next plan step): Barrage at a group of 3+ visible enemy ships within 500 of each other in 12,000 reach; Supply at the largest 3+ ship cluster under 60% average hull that is in a fight; Sweep during a siege (ahead of the front big ship), during the defend call (at the defend point) or at a hit turret that sees no enemy | `xray`: REQ-CHANGE "players cannot see through asteroids" | `assets_sweep`, `assets_supply`, `assets_barrage`, `assets_barrage_hits`, `assets_barrage_kills` |
| F2 Bounty orders | `orders`: `on` | every 60 s with treasury over 3,000, 10% (cap 1,000) on the weakest seen enemy turret on the push or siege lane; AI pilots count that turret as twice as near on their own lane (`push_weight_hooks`); flex and jungle pilots within 8,000 get a hold point next to it | none | `bounties_posted`, `bounties_claimed`, `bounties_expired`, `bounty_diverts` |
| F3 Fortify | `fortify`: `on` | uses it when the mothership lost 4% hull in 5 s, or an inner turret is under 30% hull with 2+ seen enemy big ships within 3,000; ready again when the first inner turret falls | none (gate: ms_duel, NOT run, see Pending) | `fortify_uses` |
| F4 Reactive AI admiral | `admiral_smart`: `on` | plan skips Reinforced Waves I-III and Escort Wing; with 3+ seen enemy big ships Platform Missiles + Ion Cannons first; with 8+ seen strike craft msFlak + Frigate Facility first (only steps that can start now); `comp_call` every 60 s steers the pilots' shopping lists (anti_capital / anti_strike); hyperspace untouched | none (AI only) | `comp_calls`, `plan_reorders` |
| F5 Mothership moves | `ms_move`: `early`, `flying`, `both` | `early`: unlock 1200 -> 720 s, the existing AI mover advances from 12:00; `flying`: tuned flag `mothership_move_needs_dock` = false (AI admirals never fly: usage 0 = "not screenable") | REQ-CHANGE "moved by a docked admiral ... starting at 20 minutes" | `early_moves`, `flying_moves` |
| F6 Home-field vision | `home_vision`: `on` | needs no AI change: it works through `World.vision_mods` (sight x1.25 at home, enemy pilot ships x0.75 there, enemy wards 0) | DESIGN (the research rejected it) | `home_vision_seconds` |
| F7 Mutiny | `mutiny`: `on` | computer pilots call the vote for a team without a human pilot (behind 5 min after 15:00, 8 of 12 seats); a human pilot presses M; swap for a human admiral = becomes a pilot in the richest seat, a computer admiral takes the chair; for a computer admiral the swap is only a fresh computer admiral (paper only) | REQ-CHANGE "A player should be able to choose to be admiral ... locked into not being the admiral" | `mutiny_votes`, `mutiny_yes`, `mutiny_swaps` |
| carry-over Sinks | `admiral_sinks`: `fleet` | builds Fleet Command when treasury >= cost + 2,000 (4,000) and refreshes a ward every 45 s above 3,000 (turret slots are already full: no turret re-queue) | none | `fleet_command_built`, `sink_wards` |
| weak admiral (test option) | `--admiral-ai=weak` (Cinder weak), `weak1`, `weak0` (Halcyon weak), `weakboth` | plan step every 90 s, turrets at inner nodes only, no bays/wards/sieges/moves, and none of the new orders | measurement only | n/a |

Numbers: Sweep 250 cr / 60 s / radius 3,500 / 8 s; Supply 400 cr / 90 s / 4 drones at 900 u/s / heal radius 1,200 / 8 s;
Barrage 600 cr / 150 s / within 12,000 / red circle for both teams 3 s / 600 "pure" damage in 500 to every enemy unit (motherships
not hit, no pilot credit, so a non-pilot kill); Bounty 100-1,000 up front, 2 active, 180 s, 50% refund, split among pilots who
damaged it in 15 s or fly within 2,500; Fortify free, 150 s, x0.2 for 4 s. Every new action has: a news line (Events.feed),
a HUD tag (top bar), a minimap + map mark, a help line (Admiral page), a board button and map tool (Fleet tab, "Command orders").

Design notes / deviations from the brief (all mine, flagged):
- Barrage uses damage kind `pure` (a flat 600 to everything) instead of the shell row of the damage table; it never hits motherships.
- Fortify is free, so it is not a "treasury spend", but `fun_probe_economy` counts it as a decision (any ok order not in drone/waypoint/order).
- The 60 s cooldown of the Bounty order is my addition (the AI posts every 60 s anyway).
- Mutiny's "behind" number and the computer pilots' vote rule are my proposals (lead = turret difference + 0.5 x recent ship-loss difference, <= -3 for 5 min; a computer pilot votes yes if it died more than it killed or the treasury is >= 2,500).
- The weak admiral also skips the new orders so the A/B compares a plain weak admiral with a normal one.
- The sink variant cannot re-queue turrets (all slots are full), only wards.

## Files changed in shared code (one-liners and empty-by-default hooks)

See the manifest. Core: `rules.gd` (8 keys, 1 tunable), `feature_registry.gd` (7 lines), `world.gd` (`vision_sources`, `vision_mods`),
`world_visibility.gd` (uses them), `team_state.gd` (`comp_call`, `plan_hook`), `admiral_command.gd` (`orders`, `marks`, dock flag),
`admiral_plan.gd`, `pilot_shopping.gd`, `admiral_ai.gd` + `admiral_builder.gd` (weak option). UI (small): `admiral_board_fleet.gd`,
`command_overlay.gd`, `command_overlay_draw.gd`, `minimap.gd`, `hud_top_bar.gd`, `help_panel.gd`; test: `ui_tour.gd`.

## Checks

1. `run_checks.ps1`: CHECKS ALL OK (import, load_all 0 failures, bot_pilot 0, support_probe 0, ui_pilot done, ui_admiral done).
   Extra: the admiral UI tour with EVERY order switched on (`--variant=assets:full,orders:on,fortify:on,admiral_smart:on,ms_move:both,home_vision:on,mutiny:on,admiral_sinks:fleet`) pressed all five buttons
   (sweep, supply, barrage, bounty armed their map tools with the right hint and ring; fortify was given from its button), 0 script errors.
   It ran headless (a UI tour cannot go through run_batch, which forces a spectator), so there are no screenshots: take them windowed with `--shots=<dir>`.
2. `doc_check.ps1`: TOTAL 195 files, headers 195/195, funcs 1168/1168 documented, members 1614/1614 noted (fully documented).
3. Determinism with every key at default (seed 7, via run_batch): normal 900 s: all 181 hash lines equal to int3's
   (`endgame_closure\smoke\d_int3_n_seed7.txt`, END `749aa6eb`); `--late` 300 s: all 61 lines equal to int3's
   (`pacing_downtime\det\int3_late_seed7.txt`, END `4bccf106`). IDENTICAL.
4. Smoke (headless, via run_batch; seed 101, `--late --symmetric --secs=480`, variants `assets:full,orders:on,fortify:on,admiral_smart:on,home_vision:on,admiral_sinks:fleet`, 0 SCRIPT ERROR).
   The ideas were smoked TOGETHER in one match to spare the shared queue, so each counter below is that idea's own usage:

   | idea | usage counters in that run |
   |---|---|
   | F1 assets:full | assets_sweep 10, assets_supply 2, assets_barrage 4 (28 units hit, 10 killed) |
   | F2 orders | bounties_posted 2, bounties_expired 1, bounty_diverts 1 (claimed 0: the second was still running) |
   | F3 fortify | fortify_uses 1 |
   | F4 admiral_smart | comp_calls 3, plan_reorders 2 |
   | F6 home_vision | home_vision_seconds 3,935 |
   | sinks | fleet_command_built 2, sink_wards 5 |

   Same run, S10 pieces (one match, not a screen): late_spend_ratio 1.065, admiral_decisions_per_min_late 3.67 (above the 0.5-3 band: if it stays high, lengthen cooldowns or drop one order),
   treasury_float_late 1,885, asset_kill_share 0.323.

## Pending (queued in run_batch, not started when I stopped at 12:27; the daytime limit of 3 slots was always full)

These are in the queue and will write their logs by themselves; read them before trusting the corresponding claims:
- `SP\fun\logs\admiral_command\probe\full2_seed7.txt`: the scripted probe `tests/admiral_fork_probe.gd` (human path through `CommandOrders.run`:
  sweep incl. rock blocking, supply, barrage, bounty claim + expiry, fortify, ms_move, mutiny vote + swap). Expect `admiral_fork_probe: 0 failures`.
  A first run (log `full_seed7.txt`) showed the sweep checks all PASS (including "a rock between hides the enemy") and four supply drones launched; it then hit a bug in
  my TEST (hull id `frigate` does not exist; fixed to `flak`) and I killed it. Re-run with `assets:xray` instead of `full` to check the see-through sweep.
- `SP\fun\logs\admiral_command\smoke\norm_weak_seed101.txt`: normal start, 840 s, `--admiral-ai=weak` (Cinder weak) with `ms_move:early,assets:on,orders:on,fortify:on,admiral_smart:on,home_vision:on`.
  Shows the weak-admiral option and `early_moves` (AI mover from 12:00) and that nothing errors in a normal start.
- NOT RUN: `ms_duel` for Fortify (the brief's F3 gate; ms_duel disables the AI admirals, so run it with `fortify:on` and WITHOUT `--no-admiral-ai`, scenarios B and H, both with and without the key);
  `assets:xray`, `ms_move:flying` and `mutiny` have no AI-driven smoke (xray and flying: AI admirals sit in the chair; mutiny: the probe covers the swap).
  Windowed ui_tour screenshots (the tour ran headless).

## Anything I could not build

Nothing from the brief is missing. Limits: mutiny's swap for a human admiral is world-level (the HUD follows `World.human_role` and the hangar opens, but I could not look at it windowed);
the sink variant cannot re-queue turrets (all slots are full); the see-through Sweep reuses the Scout Ping reveal circle (it also exposes stealth wards inside it).

## Recommended screen commands (`$RUN = SP\run_batch.ps1`, `$P` = `FC\forks\admiral_command`, logs under `SP\fun\logs\admiral_command\<tag>`)

Order from the brief; 10 symmetric late runs each (about 3.3 match-equivalents):

```
& $RUN -Project $P -Seeds (101..110) -OutDir $L\assets_on   -Tag assets_on   -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=assets:on"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\orders_on   -Tag orders_on   -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=orders:on"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\smart_on    -Tag smart_on    -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=admiral_smart:on"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\fortify_on  -Tag fortify_on  -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=fortify:on"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\assets_xray -Tag assets_xray -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=assets:xray"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\home_on     -Tag home_on     -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=home_vision:on"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\assets_full -Tag assets_full -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=assets:full"
& $RUN -Project $P -Seeds (101..110) -OutDir $L\sinks_fleet -Tag sinks_fleet -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=admiral_sinks:fleet"
```
`ms_move:early` needs NORMAL starts (a late start is already past 12:00): 6 seeds,
`& $RUN -Project $P -Seeds (101..106) -OutDir $L\ms_early -Tag ms_early -Extra "--secs=3600","--skill-jitter","--variant=ms_move:early"`.
`ms_move:flying` and `mutiny:on` need no screen (usage 0 in AI-only matches = "not screenable").
Read the S10 pieces from FUN_JSON (late_spend_ratio, admiral_decisions_per_min_late, asset_kill_share, treasury_float_late) by hand: LATE_SUBSET does not score S10.
Usage near 0 = INVALID, not negative: expected non-zero for every screened key (see the smoke table).

Final (best combination, at most 4 buttons, for example `assets:full` minus one order, or `assets:on,orders:on,fortify:on`):
`-Seeds (101..120) -Extra "--secs=3600","--skill-jitter","--variant=<combination>"` against baseline v2.
Weak-admiral A/B, 20 seeds with sides swapped (combination on both, the weak one has none of the orders): seeds 101-110 with `"--admiral-ai=weak"` (Cinder weak) and seeds 101-110 with `"--admiral-ai=weak0"` (Halcyon weak),
`"--secs=3600","--skill-jitter","--variant=<combination>"`; count the normal admiral's wins (target 60-90%).
