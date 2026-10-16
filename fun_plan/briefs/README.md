> **PROTOCOL UPDATE 2026-10-16 (user-approved; binding, overrides the screen text in every brief):** screen in the CHEAPEST scenario that measures the target ingredient (late symmetric runs for post-25:00 ideas; `--secs=1800` matches scored against baseline v2's FUN_JSON30 snapshot for ideas measured by 30:00; full 60-min only for S1-S3 ideas) and STOP EARLY (first half 101-103 / late 101-105; keep at +16 with FUN not falling, reject below +2 with FUN not rising 3+, else run the second half and apply +8). See docs/FUN_PLAN.md section 4.3.

# Fun plan: fork briefs (Halcyon Drift)

Six self-contained briefs from docs/FUN_PLAN.md (binding), FUN_RESEARCH.md, USER_REQUIREMENTS_2026-10-13.md and the AI deep dive's
"Decisions for you". Each fork works only in `forks/<name>/`, a copy of `remake/` made AFTER main prep and baseline v2 (so det_hash
references match). Idea counts: pacing 8, endgame 9 (12 variants), economy 9, teamfights 8, combat 6 + 2 optional, admiral 7 + 1 optional.

## Recommended order, two forks at a time (shortest and most independent first)
1. **endgame_closure + combat_roles.** Cheapest compute (endgame screens are 10 symmetric `--late` runs, about 3.3 match-equivalents each)
   and the smallest self-contained code. No shared lever. They fill the weakest or least-measured ingredients (S2 about 45; S6-S8 mostly
   unmeasured).
2. **pacing_downtime + economy_comebacks.** Full 6-seed screens, but their levers do not overlap (pacing: hyperspace, travel, respawn;
   economy: the Economy tunables).
3. **teamfights_jungle + admiral_command.** The largest and riskiest builds (a map-generation change in D7; new buttons, overlays and a
   weak-admiral A/B in F); by then the open questions below are settled.
Budget per fork: about 60 match-equivalents (20 for the 20-seed final, about 40 for screens; a `--late` run counts a third), roughly 10-15
machine-hours per pair. Each brief lists a screening order: drop ideas from the END when the budget runs out.

## Shared rules (repeated inside every brief)
- **Feature modules:** each idea is `scripts/features/<name>.gd` (notes per docs/CODE_STYLE.md), ONE line in `FeatureRegistry.FEATURES`,
  and a default in `Rules.VARIANT_DEFAULTS` (new keys default `"off"`; `retreat` and `escort_wing` keep theirs). Used as
  `--variant=<key>:<value>`; several values of one key are one module. New tuned numbers go into `Rules.TUNABLES` (read with
  `Rules.tune`). Pattern: `feature_registry.gd`, `escort_wing.gd`.
- **Hooks, not edits** (`unit.incoming_mults`, `world.combat.minion_scale_hook`, `world.push_weight_hooks`, `world.tick_hooks`, Events,
  `Game.tunables`) plus `Game.count_usage("name")`, printed in FUN_JSON. The AI must USE each mechanic; usage near 0 makes a screen
  INVALID, not negative.
- **Off means off:** no code, no random draws, no units. With every new key at default, `det_hash` (900 s normal + 300 s `--late`) equals
  main's exactly. Doc coverage stays 100%; `load_all`, `bot_pilot`, `support_probe`, `ui_tour` pass; `ms_duel` for anything touching the
  mothership. Game code never reads `tests/lib/adv_index.gd`, probe statistics or the skill knob; AI use adds no skill threshold.
- **REQ-CHANGE rule (FUN_PLAN section 1):** nothing is rejected for breaking a requirement; it is built as an opt-in variant, measured,
  and flagged `REQ-CHANGE: <requirement>` (`DESIGN` when only the research rejected it). Gates it breaks by design (wave 5/4/1, mothership
  constants, ms_duel) are REPORTED, not blocking.
- **Matches only through the shared queue** `scratchpad\run_batch.ps1` (full path and the exact call are in every brief; 6 matches at once
  18:00-06:00, 3 by day; run it in the background). Suggested log home: `scratchpad\fun\logs\<fork>\<tag>`.
- **Screen / final:** 6 seeds 101-106 with `--skill-jitter` at the 60-min cap, or 10 symmetric late runs (seeds 101-110, `--late
  --symmetric --secs=1200`) for endgame and admiral ideas. A screen only rejects: keep an idea if its target ingredient rises 8+ points
  and FUN does not fall. The best combination then runs on seeds 101-120 vs baseline v2 (`tools/fun_score.py --dir <logs> --vs
  <baseline>`): FUN +5, 90% paired-bootstrap lower bound > 0, no ingredient whose 80% CI is wholly below -15.
- **Lever owners:** hyperspace timing = pacing, rebuild lock = teamfights, siege AI = endgame. At most one of B3/B5/F3 merges, and one of
  C2(b)/F2. No fork reads another fork's keys. Conflicts expected only in `Rules.VARIANT_DEFAULTS`, `Rules.TUNABLES`,
  `FeatureRegistry.FEATURES` (the council merges by hand).

## Open questions I could not resolve from the docs
1. **Baseline v2:** done, and where are its logs? Endgame and admiral screens also need 10 symmetric `--late` baseline runs (seeds
   101-110, about 3.3 match-equivalents) that the 40-match baseline budget does not mention. Which deep-dive pass-3 settings are frozen in
   it (ret25/retsmall needs the user's OK; "always park on mid" is approved)?
2. **`tools/fun_lib.py` LATE_SUBSET scores only S1, S2, S5-late, S6-late**, so the admiral fork's target S10 (measurable from 30:00 in a
   late run) is not scored; recommend adding its three pieces (measurement tool only), else F-screens are hand-scored from FUN_JSON.
3. **`--admiral-ai=weak` is not in main** (only `--no-admiral-ai`); the admiral brief has the fork build it if missing, but main prep may
   be the better home.
4. **Surrender (B6)** needs an `ended_by` field and an end path the fun probe sees (it stops when a mothership dies): allow a small
   measurement-side change in tests/.
5. **Deep-dive decisions still open for the user** (lanespawn, eff, ms, ret25/ret35, bayA, minion knobs, bombers' role, stall rule, sinks)
   are routed as optional carry-overs: lanespawn, eff, ms, stall rule to endgame; bayA to pacing; bomber role to combat; Fleet Command
   sinks to admiral.
6. **Budget:** economy, teamfights and pacing list more ideas than about 6 full screens allow; REQ-CHANGE/DESIGN ideas come last, so
   extend the budget to measure them all.
7. **Restored-idea mechanics and key names are my proposals** (the numbers for surrender, Dreadnought, beacons, feats, catch-up, pilot
   mining and home vision are not in the research); forks may adjust them and must say so.
