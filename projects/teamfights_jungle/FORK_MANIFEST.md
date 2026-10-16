# Fork manifest: teamfights_jungle (fork D of docs/FUN_PLAN.md)

Copy of the game "int3" (every AI fix, about to be banked into remake/). Built for the fun plan: eight ideas, each a feature
module behind its own variant key, all defaulting to "off". With every key at its default nothing changes: the match prints the
same `rocks=2676 camps=12 route_nodes=347` line and the same det_hash lines as int3 (checked, see the build report).

## Variant keys (use `--variant=key:value`, several separated by commas)

| Key | Values (default first) | Idea | Flag | Module | Usage counters |
|---|---|---|---|---|---|
| `group_late` | off, on | D1 late grouping on the push lane | none | `scripts/features/group_late.gd` | `grouped_seconds` |
| `salvage_core` | off, on | D2 Derelict Battleship and the carried Salvage Core | none | `scripts/features/salvage_core.gd` | `cores_carried`, `core_minion_seconds` |
| `jungle_scale` | off, on | D3 a jungle that scales with the match, AI gank | none | `scripts/features/jungle_scale.gd` | `gank_attempts` |
| `node_persist` | off, on | D4 persistent nodes (owns the turret rebuild-lock lever) | none | `scripts/features/node_persist.gd` | `persist_rebuilds` |
| `epic` | off, dreadnought, elder | D5 timed epic neutral at the Crossing | REQ-CHANGE: "Remove the dynamic event zones" | `scripts/features/epic_neutral.gd` | `epic_kills`, `boon_seconds`, `elder_cores`, `elder_executes`, `elder_ms_hits` |
| `beacons` | off, on | D6 salvage beacons with a sensor blackout | REQ-CHANGE: "Remove the dynamic event zones" and the capture points that mining drones replaced | `scripts/features/beacons.gd` | `beacon_trips`, `beacon_captures`, `blackout_seconds` |
| `camp4` | off, on | D7 a fourth jungle camp per quarter | DESIGN (map generation changes) | `scripts/features/camp4.gd` + map builder | `camp4_camps`, `camp4_kills` |
| `feats` | off, on | D8 early feats of strength and the 14:00 Vanguard | DESIGN | `scripts/features/feats.gd` | `feats_claimed`, `vanguards` |

Test-only command-line options (no effect unless given; read only by the modules above while their variant is on):
`--tfj-hull-scale=F` (multiplies the hull of every Battleship and Dreadnought when made; smoke runs use 0.05-0.1) and
`--tfj-vanguard-at=SECONDS` (brings the 14:00 Vanguard decision forward), `--tfj-elder-from=SECONDS` (replaces the 30:00 of the
Elder Core) and `--tfj-beacon-any=1` (beacons: the AI group rule counts friendly ships of every size, not only small ones).

## Files added

- `scripts/features/tfj_kit.gd` (TfjKit): shared helpers (news line, friends near, "go for that derelict" AI step, test-hull option).
- `scripts/features/minion_buffs.gd` (MinionBuffs): owns Combat.minion_scale_hook for the whole fork and the minion hull boosts used by
  D2 (Core), D5 (Boon) and D8 (Vanguard); made on first use only.
- `scripts/features/group_late.gd`, `salvage_core.gd`, `jungle_scale.gd`, `node_persist.gd`, `epic_neutral.gd`, `beacons.gd`,
  `camp4.gd`, `feats.gd`: the eight feature modules.
- `tests/camp4_probe.gd`: map check for D7 (every camp clear, reachable by a 17-unit ship, rock gaps sealed).
- `FORK_MANIFEST.md` (this file).

## Files changed (shared code; every change is a no-op with all keys at default)

- `scripts/features/feature_registry.gd`: eight lines in FEATURES (one per key).
- `scripts/data/rules.gd`: eight keys in VARIANT_DEFAULTS (all "off"). No new TUNABLES: D4 uses the existing `rebuild_lock`, D3 the
  existing `derelict_reward_mult`.
- `scripts/data/jungle.gd`: two rows in CAMPS (`battleship`, `dreadnought`; data only, never made unless D2/D5 is on).
- `scripts/data/weapons.gd`: two rows (`battleship_gun`, `dreadnought_gun`).
- `scripts/data/map_layout.gd`: `CAMPS_EXTRA` (the four extra camps' data; read only by D7).
- `scripts/world/map_builder_jungle.gd`: with `camp4` on it lays out `CAMPS + CAMPS_EXTRA`; with it off `camp_list` is MapLayout.CAMPS
  itself, same loops, same random draws (the only map-generation change).
- `scripts/ai/pilot_ai.gd`: `_think` step 6 asks `_feature_takes_over()` (new function) before the normal state job; skipped when
  `world.features` is empty.
- `scripts/ai/pilot_goals.gd`: `_pick_station` asks the `group_late` module (a `grouped` plan; empty when off); `think_jungle` asks
  `_feature_allows_camp()` (new function) per camp; both skipped when no feature is on.
- `scripts/ai/admiral_builder.gd`: `_nodes_in_order()` (new function): the two turret builders visit nodes nearest the own
  mothership first under `node_persist`, else `world.nodes` exactly as before.
- `scripts/ui/minimap.gd`: `_feature_hides()` and `_draw_feature_marks()` (new): the Dreadnought and beacon marks, beacon blackout.
- `scripts/ui/scoreboard.gd`: `_feature_notes()` (new): the feats note after a team heading.

## Notes

- Hooks used: `world.tick_hooks`, `world.combat.minion_scale_hook` (through MinionBuffs), Events, `Game.tunables` (`rebuild_lock`,
  `derelict_reward_mult`), `Game.count_usage`. The new AI entry points are `pilot_think(brain, ship) -> bool`,
  `allow_camp(brain, ship, camp) -> bool`, `minimap_marks(vt)`, `minimap_hides(unit, vt)` and `scoreboard_note(team)`, found by
  `has_method` on the objects in `world.features`.
- Several keys can be on together. Only one minion hook exists in the game, so MinionBuffs merges the Core, the Boon and the Vanguard
  (damage: the best multiplier, never a product; hull: product).
