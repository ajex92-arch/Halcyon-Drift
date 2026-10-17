# Fork manifest: admiral_command (fun plan, fork F)

Base: a copy of the game with every AI fix (`SP\notate\int3`, about to be banked into `remake/`).
Rule of the fork: every new key defaults to `off`; with every key at its default no code path, random
draw or unit changes (det_hash normal 900 s and --late 300 s equal int3's, see the build report).

## Variant keys (Rules.VARIANT_DEFAULTS), used as `--variant=<key>:<value>`

| key | values (default first) | module | flag |
|---|---|---|---|
| `assets` | `off`, `on` (Sweep + Supply), `full` (also Barrage), `xray` (Sweep sees through rocks) | `scripts/features/admiral_assets.gd` (+ `admiral_assets_ai.gd`, `supply_drone.gd`) | `xray`: REQ-CHANGE "players cannot see through asteroids" |
| `orders` | `off`, `on` (Bounty orders) | `scripts/features/admiral_orders.gd` | none |
| `fortify` | `off`, `on` | `scripts/features/fortify.gd` | none (gate: ms_duel) |
| `admiral_smart` | `off`, `on` | `scripts/features/admiral_smart.gd` | none (AI only) |
| `ms_move` | `off`, `early`, `flying`, `both` | `scripts/features/ms_move.gd` | REQ-CHANGE "moved by a docked admiral ... starting at 20 minutes" |
| `home_vision` | `off`, `on` | `scripts/features/home_vision.gd` | DESIGN (the research rejected it) |
| `mutiny` | `off`, `on` | `scripts/features/mutiny.gd` | REQ-CHANGE "A player should be able to choose to be admiral ... locked into not being the admiral" |
| `admiral_sinks` | `off`, `fleet` | `scripts/features/admiral_sinks.gd` | none (deep-dive carry-over) |

Test option (not a game rule, read only by AdmiralAI, absent = no change): `--admiral-ai=weak` (Cinder weak),
`weak1` (the same), `weak0` (Halcyon weak), `weakboth` (see `scripts/features/admiral_weak.gd`). A weak admiral
starts a plan step every 90 s, builds turrets only at inner nodes, places no bays or wards, declares no sieges,
moves no mothership, and uses none of the new orders.

## Numbers

| idea | numbers |
|---|---|
| Sensor Sweep | 250 credits, cooldown 60 s, sight radius 3,500 for 8 s, aimed at a spot the team sees |
| Supply Drop | 400 credits, cooldown 90 s, 4 repair drones at 900 u/s, mend ships within 1,200 for 8 s at bay-drone rates |
| Barrage (`full`) | 600 credits, cooldown 150 s, within 12,000 of the mothership, red circle (both teams) for 3 s, then 600 "pure" damage in 500 to every enemy unit (motherships not hit; no pilot credit) |
| Bounty | 10% of the treasury (100 to 1,000) up front on an enemy turret or repair bay; at most 2 active; 180 s; refund 50% when it expires; split among the team's pilots who damaged the target in 15 s or fly within 2,500; order cooldown 60 s |
| Fortify | free, cooldown 150 s (ready again when the first inner turret falls), x0.2 damage on all friendly turrets and the mothership for 4 s, shimmer for both teams |
| Smart AI | skips waveArmor1-3 and escortWing; with 3+ enemy big ships seen: platformMissiles, ionCannons first; with 8+ strike craft seen: msFlak, frigate facility first; a composition call every 60 s |
| ms_move | `early`: `mothership_move_unlock` 1200 -> 720; `flying`: tuned flag `mothership_move_needs_dock` false |
| home_vision | x1.25 sight within 8,000 of own mothership hull or 3,500 of an own inner turret; enemy pilot ships there x0.75; enemy wards there 0 |
| mutiny | after 15:00, behind (lead <= -3) for 5 min; 8 of 12 seats; richest seat takes the chair |
| admiral_sinks | Fleet Command when treasury >= 4,000; a fresh ward every 45 s above 3,000 |

## Usage counters (Game.count_usage; printed in FUN_JSON "usage")

`assets_sweep`, `assets_supply`, `assets_barrage`, `assets_barrage_hits`, `assets_barrage_kills`,
`bounties_posted`, `bounties_claimed`, `bounties_expired`, `bounty_diverts`, `fortify_uses`,
`comp_calls`, `plan_reorders`, `early_moves`, `flying_moves`, `home_vision_seconds`,
`mutiny_votes`, `mutiny_yes`, `mutiny_swaps`, `fleet_command_built`, `sink_wards`.

## Files added (all new code is plain-language documented; doc_check TOTAL fully documented)

- `scripts/features/command_orders.gd` (CommandOrders): the shared order desk (price, cooldown, rules, news
  line, marks, tags, help lines) for the five orders.
- `scripts/features/command_orders_ui.gd` (CommandOrdersUi): the "Command orders" buttons on the board's Fleet tab.
- `scripts/features/admiral_assets.gd`, `admiral_assets_ai.gd`, `supply_drone.gd` + `scenes/entities/supply_drone.tscn`.
- `scripts/features/admiral_orders.gd`, `fortify.gd`, `admiral_smart.gd`, `ms_move.gd`, `home_vision.gd`,
  `mutiny.gd`, `admiral_sinks.gd`, `admiral_weak.gd`.
- `tests/admiral_fork_probe.gd`: scripted check of every order through the human path (CommandOrders.run).

## Files changed (the minimum: registrations, empty-by-default hooks, hook uses)

Core / data
- `scripts/data/rules.gd`: 8 keys in VARIANT_DEFAULTS (all `off`) and one TUNABLES entry (`mothership_move_needs_dock`).
- `scripts/features/feature_registry.gd`: 7 lines in FEATURES.
- `scripts/world/world.gd`: two empty hook lists, `vision_sources` and `vision_mods`.
- `scripts/world/world_visibility.gd`: `viewers()` adds the live vision sources and runs `vision_mods` (both empty by default).
- `scripts/team/team_state.gd`: `comp_call` ("" default) and `plan_hook` (empty Callable).
- `scripts/control/admiral_command.gd`: `orders` and `marks` (empty) and the dock check in `move_blocker()` reads the tuned flag (default true = unchanged).
- `scripts/ai/admiral_plan.gd`: `next_step()` uses `ts.plan_hook` when valid.
- `scripts/ai/pilot_shopping.gd`: `wish_list()` asks AdmiralSmartFeature when `comp_call` is set.
- `scripts/ai/admiral_ai.gd`, `admiral_builder.gd`: the `--admiral-ai=weak` test option (false unless the option names the team).

UI (small; every one does nothing while no order is registered)
- `scripts/ui/admiral_board_fleet.gd`: two lines call CommandOrdersUi (the buttons).
- `scripts/ui/command_overlay.gd`: `tool_text()`, and a default branch in `blocker_at()` and `apply_at()` for the new map tools.
- `scripts/ui/command_overlay_draw.gd`: draws the marks; the tool preview ring uses the order's radius.
- `scripts/ui/minimap.gd`: draws the marks (minimap icon).
- `scripts/ui/hud_top_bar.gd`: appends the order tags (HUD tag).
- `scripts/ui/help_panel.gd`: appends the orders' help paragraphs to the Admiral page.
- `tests/ui_tour.gd`: the admiral tour presses each new order button (nothing happens without variants).

## Buttons and map tools a human admiral gets (Fleet tab, "Command orders")

Sweep, Supply (`assets:on`), Barrage (`assets:full`), Bounty (`orders:on`), Fortify (`fortify:on`). The brief allows at
most 4 in the merged game: all five exist here so the lead can choose. Each has a news line (Events.feed), a HUD tag
(top bar), a map and minimap mark, a help line (Admiral page) and an AI use.
