# Fork brief: admiral_command (fork F)

Game: Halcyon Drift, a Godot 4.7 space MOBA (13 v 13: 12 pilots + 1 admiral per team; the admiral spends a team treasury on
drones, turrets, bays, wards, research and waypoints, and can move the mothership from 20:00; an AI admiral plays when no human
sits there). You work ONLY in `forks/admiral_command/` (a copy of `remake/`). Read first: `scripts/features/feature_registry.gd`,
`escort_wing.gd`, `scripts/ai/admiral_ai.gd` and its parts, `scripts/control/admiral_command.gd`, `scripts/team/team_state.gd`.
Docs style: docs/CODE_STYLE.md. Shared rules: section 4 and README.md.

## 1. Goal and ingredients
The admiral makes frequent, legible, high-impact decisions all match, especially after the tech tree is done, and those decisions
create objectives for pilots. The AI admiral plays competently and reacts to the enemy, while a weak admiral never leaves the team
helpless.
- **S10 The admiral seat matters (weight 5), the target:** late_spend_ratio (treasury spent after 30:00 / treasury income after
  30:00; 0 at <= 0.30, 100 at >= 0.75), admiral_decisions_per_min_late (`Events.admiral_result` with ok == true that spend
  treasury, except `drone`, plus mothership moves, at most one per action type per 30 s, per team-minute after 30:00; T
  0.1/0.5/3/6), asset_kill_share (pilot kills where the victim died within 2,000 of a killer-team turret, within 1,400 of a
  killer-team bay or ward, or inside the killer team's waypoint ring; T 0.10/0.30/0.70/0.90). Baseline about 55 (the AI plan
  finishes at 31-35 min, then treasuries pile up: late treasuries 17-89k in the first audit, 3.5-38k after the deep dive).
- Secondary: S9 treasury_float_late (<= 4,000), S2 (final_push, limbo), S3 (late lead changes from defender counter-pushes), S6
  pilot_kill_share_late, S5 fight_p90_late.
- Gate (not scored): the weak-admiral A/B, 20 seeds, sides swapped: the normal AI admiral must win 60-90%, so the seat matters but
  is not a single point of failure. `--admiral-ai=weak` (plan steps 90 s apart, turrets at inner nodes only, no bays, wards,
  sieges or moves) is NOT in main yet: if your copy lacks it, build it as a measurement option read only by AdmiralAI (det_hash
  unaffected) and say so in your report.
- Legibility rules: at most 4 admiral buttons in total (Sweep, Supply, Barrage, Bounty, Fortify all count: choose); every new
  action needs a feed line, a HUD tag, a minimap icon and a help line, and must be doable in 10 s or less (timed task test at
  merge).
- Context: "always park on mid" is going into main (the mothership only advances up the mid lane from 20:00). The AI plan never
  builds Fleet Command; a sink must not weaken the mothership after big spends (the user reversed that).

## 2. Ideas to build (all keys default `off` in Rules.VARIANT_DEFAULTS; use `--variant=<key>:<value>`)
### F1 Command assets | `assets:on` / `assets:full` / `assets:xray` | REQ-CHANGE: on, full = none; xray = "Make it so players cannot see through asteroids"
New `AdmiralCommand` orders with a treasury cost and a per-team cooldown, aimed at a point in friendly vision. Sensor Sweep (250
credits, 60 s): a vision source, radius 3,500, for 8 s, which respects asteroid occlusion like any vision. Supply Drop (400
credits, 90 s): 4 repair drones (the existing destroyable type, bounty 10) fly from the mothership at 900 u/s and heal friendly
pilot ships within 1,200 of the point for 8 s at bay-drone rates. `full` adds Mothership Barrage (600 credits, 150 s; point within
12,000 of the mothership): a red circle shown to BOTH teams for 3 s, then 600 shell damage in a 500 radius (kills credited to the
team as `admiral`); screen it last. `xray` (restored): the Sweep ignores asteroid occlusion (compare with `on`). AI (new
`AdmiralAssets` part): sweep when a siege or defence is active, or a lane turret is under attack with no enemy visible; supply the
largest friendly fight cluster whose average hull is below 60%; barrage when 3+ enemy ships are within 500 of a point in range.
Usage: `assets_sweep`, `assets_supply`, `assets_barrage`. Pass: S10 +8 (decisions 0.5-3, late_spend_ratio >= 0.75); watch
pilot_kill_share (barrage kills count as non-pilot) and TTK.
### F2 Bounty orders | `orders:on` | alternative to C2(b) of the economy fork | REQ-CHANGE: none
`AdmiralCommand.post_bounty(team, target, amount 100-1,000)` is paid up front from the treasury and placed on an enemy turret or
repair bay; at most 2 active, each lasts 180 s, an expired bounty refunds 50%. When the target dies the amount is split among the
team's pilots who damaged it in the last 15 s or are within 2,500. AI pilots: weight bounty targets x2 on their own lane through
`world.push_weight_hooks`; flex pilots and junglers within 8,000 divert. The AI admiral posts 10% of the treasury (cap 1,000) on
the weakest enemy turret on the push or siege lane every 60 s while the treasury is above 3,000. Gold marker on the target for
both teams. Usage: `bounties_posted`, `bounties_claimed`. Pass: S10 +8 (treasury_float_late down, asset_kill_share up) with
unattended_turret_loss_share down.
### F3 Fortify | `fortify:on` | alternative to B3 and B5 of the endgame fork | REQ-CHANGE: none (gated by ms_duel)
A free admiral button, 150 s cooldown, reset when the team's first inner turret dies. For 4 s all friendly turrets and the
mothership take x0.2 damage (`unit.incoming_mults`), shown to both teams as a shimmer. AI uses it when the mothership lost >= 4%
hull in the last 5 s, or when an inner turret is below 30% with 2+ enemy big ships within 3,000. Must pass the ms_duel gate (same
winners; upgraded wins end with <= 40% HP). Usage: `fortify_uses`. Pass: S2 +8 (final_push into 120-420 s) via screening on late
runs; watch ms_limbo and minutes.
### F4 Reactive AI admiral and fleet-composition calls | `admiral_smart:on` | REQ-CHANGE: none (AI-only; every tech stays available to a human)
`AdmiralPlan` becomes priority-ordered. If 3+ enemy big ships are alive, Platform Missiles, Ion Cannons and torpedo turrets move
forward; if 8+ enemy strike craft are alive, msFlak and the Frigate Facility move forward. The AI skips Reinforced Waves I-III and
Escort Wing and spends that money on its existing late plan. Every 60 s `TeamState.comp_call` ('anti_capital', 'anti_strike' or
'') is set from enemy hulls seen, and `PilotShopping.wish_list` reads it: anti_capital moves the strikers and the lancer to
bombers or lances, and one dogfighter to a bomber; anti_strike moves the dogfighters to flak frigates earlier (from 15:00). Do NOT
touch hyperspace timing (pacing fork owns it); read no other fork's variants. Usage: `comp_calls`, `plan_reorders`. Pass: S6
late/S10 +8 and the weak-admiral A/B stays within 60-90%.
### F5 Earlier or airborne mothership moves | `ms_move:early` / `ms_move:flying` | REQ-CHANGE: "moved by a docked admiral ... starting at 20 minutes"
early: tunable `mothership_move_unlock` 1200 -> 720 s (12:00); the AI mover (`AdmiralMothershipMover`, `Rules.move_unlock_time()`)
then advances from 12:00 on its normal gap. flying: an admiral flying their own ship may also order the move; AI admirals sit in
the chair, so this is probably paper-only in sims (usage 0 = "not screenable", not negative; test the human path with a scripted
bot test and ui_tour). Usage: `early_moves`, `flying_moves`. Pass for early: S2 or S3 +8 (earlier onset, lead changes).
### F6 Defenders' home-field vision | `home_vision:on` | DESIGN (the research rejected it: it makes sieges, the weakest link, harder)
Friendly vision radius x1.25 within 8,000 of the friendly mothership hull or within 3,500 of a friendly inner turret; enemy pilot
ships inside those zones see x0.75 and their wards give no vision there (a Dota high-ground analogue). The AI uses it
automatically through the vision lists. Usage: `home_vision_seconds` (enemy pilot-seconds inside a defended zone). Pass: S10
asset_kill_share +8 or S3 +8; report final_push, ms_limbo and minutes (stalemate risk).
### F7 Mutiny / admiral swap | `mutiny:on` | REQ-CHANGE: "A player should be able to choose to be admiral ... locked into not being the admiral"
After 15:00, when a team has been behind for 5 min (scoreboard numbers: turret and recent-kill difference, your own helper), any
pilot may call a vote; at 8 of 12 the chair passes to the pilot seat holding the most credits and the old admiral takes that seat.
Only meaningful with a human admiral: build the vote, banner and swap path (scripted test plus ui_tour screenshots) and judge it
on paper. Usage: `mutiny_votes`. No screen.
### Optional deep-dive carry-over (screen last)
`admiral_sinks:fleet`: the AI plan builds Fleet Command (and re-queues capped turrets and wards) whenever the treasury exceeds the
cost by 2,000. REQ-CHANGE: none. Usage `fleet_command_built`. Pass: S10/S9 +8.

## 3. Levers and alternatives
You own the **admiral command surface** (assets, orders, fortify, AI plan priorities). Do NOT change hyperspace timing (pacing
fork), siege AI (endgame fork), the turret rebuild lock (teamfights fork). **At most one of B3, B5 and F3 merges** (B3, B5 are
endgame-fork ideas), and **at most one of C2(b) and F2** (C2 is an economy-fork idea). No fork reads another fork's variant keys.

## 4. Screening protocol and final report
Shared rules: each idea is a feature module `scripts/features/<name>.gd` + one line in `FeatureRegistry.FEATURES` + a default in
`Rules.VARIANT_DEFAULTS`; hooks only (`Rules.tune`, `unit.incoming_mults`, `world.push_weight_hooks`, `world.tick_hooks`, Events,
`Game.count_usage`); an off feature runs no code and draws no random numbers; no new AI skill threshold; game code never reads
`tests/lib/adv_index.gd`. Checks first: `load_all`, `det_hash` (900 s normal + 300 s `--late`) identical to main with every key at
default, doc_check 100%, bot_pilot, support_probe, ui_tour (every new button), ms_duel for F3. Matches ONLY through `RUN =
<SCRATCH>\run_batch.ps1`.
- Screen each idea alone with 10 symmetric late runs: `& $RUN -Project <fork folder> -Seeds (101..110) -OutDir <logs>\<tag> -Tag
  <key>_<value> -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=<key>:<value>"`, then `python
  tools/fun_score.py --dir <logs>\<tag> --vs <baseline v2 late logs>`. NOTE: `fun_lib.LATE_SUBSET` scores only S1, S2, S5 and S6
  on late logs, NOT S10, although the S10 pieces exist from 30:00 on (15 min of a late run). Until LATE_SUBSET is extended
  (README, open question 2) read `late_spend_ratio`, `admiral_decisions_per_min_late`, `asset_kill_share` and
  `treasury_float_late` from FUN_JSON (medians vs baseline v2 late logs) and score them by hand with the bands above. Keep an idea
  if its target rises 8+ points and FUN does not fall; usage near 0 = INVALID, not negative.
- Order (about 3.3 match-equivalents per screen; ~60 total, 20 for the final): F1 on, F2, F4, F3, F1 xray, F6, F5 early, F1 full,
  carry-over; F7 needs no screen.
- Final: best combination (at most 4 buttons) on seeds 101-120, FULL matches (`--secs=3600 --skill-jitter`), vs baseline v2, plus
  the weak-admiral A/B on 20 seeds with sides swapped. Acceptance: FUN +5 with a one-sided 90% paired-bootstrap lower bound > 0
  and no ingredient whose 80% CI is wholly below -15. Targets: decisions 0.5-3 per min, late_spend_ratio >= 0.75,
  treasury_float_late <= 4,000, asset_kill_share 0.30-0.70, unattended_turret_loss_share <= 0.10, S10 >= 80, S9 up 20+, A/B
  60-90%.
- **Final report must contain:** S1-S11 median/IQR baseline v2 vs combination; FUN with 90% lower bound; every S10 piece; the A/B
  win rate and per-side numbers; the button list (max 4) with a timed-task result for each; usage counters by asset type; ms_duel
  table (F3); gate list; keep/drop per idea; every REQ-CHANGE (F1 xray, F5, F7) and DESIGN note (F6) in plain words; the sinks
  that win (F1, F2) flagged to the user, since repeatable sinks were left as their decision.
