# endgame_closure fork: manifest

This is the build manifest of one fun-experiment fork, kept as it was when the fork was merged into the game (v0.2.0), with only its paths, base names and a few notes (the user's later decisions, the API index) updated for this repository. Paths are relative to `remake/`; the build report is
`../fun_plan/reports/endgame_closure_build.md`.

The game with every AI fix (the AI deep dive's pass 3, banked into `remake/` before
v0.1.0) plus the endgame_closure ideas (brief B1-B9 plus the optional carry-overs)
built as opt-in feature modules. With every new key at its default, no new code
path runs, no random number is drawn and no unit changes (`tests/det_hash.gd`
equals the base game's, see the build report).

## Variant keys (`--variant=<key>:<value>`)

Every default is `off` except `retreat` (default `systems_failure`, unchanged).

| Key | Values | Module | Idea | Flag | Usage counters |
|---|---|---|---|---|---|
| `siege_fix` | `off` `gather3` `full` `stall` | `siege_fix.gd` | B1 sieges that land | none | `assaults_launched`, `assault_gather_ships`, `siege_throttles`, `base_races`, `siege_stall_saved` |
| `breach` | `off` `on` `fulldmg` | `breach.gd` (+ `breach_tracker.gd`, `minion_boost.gd`) | B2 lane breach corvette | `on` none; `fulldmg` REQ-CHANGE: "weak to attacks by large ships" | `breach_waves` |
| `ms_cap` | `off` `on` `full` | `ms_cap.gd` | B3 mothership damage-rate cap | `on` none; `full` REQ-CHANGE: "a lot of health" / "barely" tuning at risk | `ms_cap_seconds` |
| `attrition` | `off` `on` | `attrition.gd` | B4 fleet attrition after 40:00 | none | `attrition_seconds` |
| `retreat` | `systems_failure` (default) `none` `last_stand` | `last_stand.gd` | B5 Last Stand | none (does nothing for `none`/`systems_failure`) | `last_stands` |
| `surrender` | `off` `vote` | `surrender.gd` | B6 surrender vote | REQ-CHANGE: "only destroying the mothership should end the match" | `surrender_votes`, `surrenders`, `surrender_loser_halcyon`, `surrender_loser_cinder` |
| `breach_extra` | `off` `on` | `breach_extra.gd` (+ `breach_tracker.gd`, `minion_boost.gd`) | B7 extra siege minion after a breach | REQ-CHANGE: "wave of 10, with 5 fighters, 4 bombers, and 1 escort corvette" | `super_minions` |
| `ms_soft` | `off` `hull` `shield` `mult` | `ms_soft.gd` | B8 softer mothership | REQ-CHANGE: "a lot of health", "weak to large ships", the (barely) win against frigates | `ms_soft_hull_damage` |
| `waves_late` | `off` `slow` `none` | `waves_late.gd` | B9 fewer free waves late | REQ-CHANGE: minions "spawn from the mothership regularly" | `waves_skipped` |
| `lanespawn` | `off` `on` | `lanespawn.gd` | carry-over: late minions launch from the lane ends | REQ-CHANGE: minions "spawn from the mothership regularly" | `lanespawn_waves` |
| `eff` | `off` `on` | `eff.gd` | carry-over: weapon-aware target choice | none | `eff_picks` |
| `ms` | `off` `nosmall` | `ms_nosmall.gd` | carry-over: small non-bomber ships stop sieging the mothership | REQ-CHANGE: "both should be needed to push lanes" | `small_siege_skips` |

New tuned number: `mothership_attacker_large` in `Rules.TUNABLES` (read by
`CombatScaling`; only `ms_soft:mult` sets it).

Test-only command-line option (read only by the `attrition` and `waves_late`
modules): `--feature-time-shift=N` moves their start times N seconds EARLIER, so a
short `--late` run can reach 30:00 / 35:00 / 40:00. Never use it for a real screen.

## Files added

- `scripts/features/siege_fix.gd` (`SiegeFixFeature`), `breach.gd` (`BreachFeature`),
  `breach_tracker.gd` (`BreachTracker`, shared by B2 and B7), `minion_boost.gd`
  (`MinionBoost`, tough corvette copies), `ms_cap.gd` (`MsCapFeature`),
  `attrition.gd` (`AttritionFeature`), `last_stand.gd` (`LastStandFeature`),
  `surrender.gd` (`SurrenderFeature`), `breach_extra.gd` (`BreachExtraFeature`),
  `ms_soft.gd` (`MsSoftFeature`), `waves_late.gd` (`WavesLateFeature`),
  `lanespawn.gd` (`LanespawnFeature`), `eff.gd` (`EffFeature`), `ms_nosmall.gd`
  (`MsNosmallFeature`).
- `tests/fc_smoke.gd`: forced-event smoke test (`--test=fc_smoke --scenario=breach|
  laststand|surrender|mscap|siege|race`); prints `FC_SMOKE {...}`. Measurement tool only.

## Files changed (shared code; each change is small)

| File | Change | Why |
|---|---|---|
| `scripts/features/feature_registry.gd` | 12 `FEATURES` lines; `banner_for()` and `minimap_marks()` (new static functions) | registration; lets features show a HUD banner and minimap chevrons |
| `scripts/data/rules.gd` | 11 new `VARIANT_DEFAULTS` keys (all `"off"`), a note on `retreat:last_stand`, 1 `TUNABLES` entry (`mothership_attacker_large`) | registration |
| `scripts/entities/mothership_retreat.gd` | `Game.variant("retreat") == "none"` became `!= "systems_failure"` | so `last_stand` does not also run the systems failure; identical for `none` and the default |
| `scripts/world/combat_scaling.gd` | large/capital attacker multiplier vs a mothership read through `Rules.tune("mothership_attacker_large", ...)` | `ms_soft:mult` (same number when no feature sets it) |
| `scripts/autoload/events.gd` | new signal `minion_launched(m, wave_id)` | B2/B7/lanespawn react when a free-wave minion launches (no listener by default) |
| `scripts/world/minion_director.gd` | one `Events.minion_launched.emit(m, next_wave)` after a queued minion is spawned | same |
| `scripts/ai/pilot_flight.gd` | 3 lines at the end of `travel()`: `world.features.has("siege_fix")` then `throttle(ship)` | `siege_fix:full` formation (the AI ship slows if far ahead of its fleet) |
| `scripts/ai/pilot_targeting.gd` | `eff` term in `pick_target()` score, `ms:nosmall` check in `pick_target()` step 4 and `push_target()` step 2; all behind `world.features.has(...)` | the AI uses `eff` and `ms:nosmall` |
| `scripts/ui/hud_banner.gd` | last `elif` shows a feature banner (`FeatureRegistry.banner_for`) | B2/B3/B5/B6/B7 HUD banners |
| `scripts/ui/minimap.gd` | draws feature marks as chevrons | B2/B7 breach chevrons |
| `scripts/ui/hud_top_bar.gd` | 3 lines: the hull-bar label says PLATING HOLDING while `ms.incoming_mults` has `ms_cap` | B3 "plating holding" tick |
| `tests/fun_probe.gd` | prints `ended_by` ("mothership" / "surrender" / "none"); for a surrendered match `final_push_secs`, `close_out_secs`, `ms_big_damage_share` are null | B6 measurement (brief open question 4) |

Doc-only edits (header notes) in the changed files above. `docs/API_INDEX.md` is rebuilt
with `python tools/api_index.py` (it lists these files since the merge).

## Design notes and choices (deviations from the brief are listed here)

- B1: `TeamState.siege_speed_cap` is not added to `TeamState`; the cap and group centre
  live in the feature object (`SiegeFixFeature.cap/centre`). The gather decision is taken
  by the module (AdmiralSiege's `siege_gather_count`/`siege_gather_time` are set out of
  reach while it is on); a hard cap of 150 s starts the assault whatever is there so a
  siege cannot sit in "gather" forever. The base race only sounds the early defend call
  while the team runs NO siege (a defend call pulls siege ships home, see PilotGoals step 6).
- B3: the multiplier is set on the mothership only while the shield is down, so shields,
  the x2.0 large/capital multiplier and the point-defence weakness are untouched. The HUD
  "plating holding" tick is the words PLATING HOLDING next to the hull bar (top bar) plus a banner line.
- B5: guns x1.5 are done by running each gun's cooldown 1.5x faster (the guns' fire
  multiplier is recomputed every tick in `MothershipGuns.fire`, so a hook cannot change it).
- B6: AI seats vote the moment the vote opens (all by the same scoreboard rule); a human
  seat counts as one of the 13 seats, so with 12 AI "yes" votes a single human cannot
  stop a passing vote (80% of 13 = 11 seats). Human prompt: banner, F10 yes, F11 no.
- B9: "slow" uses the `wave_interval` tuned number; "none" sets the director's next wave
  time out of reach.
