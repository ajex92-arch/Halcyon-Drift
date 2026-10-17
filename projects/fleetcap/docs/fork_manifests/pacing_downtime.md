# FORK_MANIFEST: pacing_downtime (fork A of the fun plan)

Base: `notate/int3` (the game with every AI fix). Every idea is a feature module behind its own variant key.
With every key at its default (`off`) no new code runs: no random draws, no units, no changed numbers.
Use a key with `--variant=<key>:<value>` (several keys: `--variant=a:x,b:y`).

## Variant keys (default `off` for all)

| key | values | idea | flag |
|---|---|---|---|
| `slipstream` | `on` | A1 Lane Slipstream, size-scaled (x2 top speed, at most 1,000 u/s) | none |
| `slipstream` | `flat` | A1b Slipstream with a FLAT 1,100 u/s for every hull | REQ-CHANGE: "slowly pushing across the map" (heavier ships travel slower) |
| `slipstream` | `probe` | measurement only: nobody slips; big-ship arrival times are measured (baseline for A1b) | none |
| `redeploy` | `on` | A2 Forward Redeploy (hyperspace plan step after the Frigate Facility; jump to a bay OR turret; 4 s spool; AI jumps; next bay at 0.5 of the push/siege lane) | none (owns the hyperspace-timing lever) |
| `recall` | `on` | A3 Recall (key T, 8/10/12 s channel, docks from anywhere; AI recalls when far from home) | none |
| `respawn` | `size` | A4 Size-scaled respawn (x0.6 / 0.85 / 1.1 / 1.3 by hull size lost) | none |
| `respawn_site` | `bay` | A5 respawn next to a safe forward repair bay | REQ-CHANGE: "pilots have to buy personal repair kits at the mothership" |
| `respawn_site` | `waypoint` | A5 respawn inside the admiral's waypoint ring | REQ-CHANGE: same |
| `bay_shop` | `on` | A6 kits and gear sold at repair bays | REQ-CHANGE: same |
| `respawn_curve` | `steep` | A7 steeper late respawn curve (8 s + 1.8 s/min, max 90 s) | DESIGN (the research rejected it) |
| `bayA` | `on` | deep-dive option: AI repair bays at 0.22 of the lane, not 0.33 (optional carry-over) | none |

Tuned numbers: no new entry in `Rules.TUNABLES`. `respawn_curve:steep` sets the existing `respawn_base` (6 -> 8), `respawn_per_minute` (0.9 -> 1.8) and `respawn_max` (50 -> 90).

## Usage counters (`Game.usage`, printed in FUN_JSON as `usage`)

| key | counters |
|---|---|
| `slipstream` | `slip_seconds`, `slip_seconds_small/medium/large/capital` (pilot-seconds slipping); `big_arrivals`, `big_arrival_s_sum`, `big_arrival_s_sq` (trip time of big ships launch -> within 2,500 of their goal; mean = sum/n, spread = sqrt(sq/n - mean^2); also under `probe`) |
| `redeploy` | `hyperspace_launches`, `hyperspace_launches_team0/1`, `redeploy_turret_landings`, `redeploy_site_lost` |
| `recall` | `recalls_started`, `recalls_completed`, `recalls_cancelled` |
| `respawn` | `size_respawns` |
| `respawn_site` | `forward_respawns`, `forward_respawns_bay/waypoint`, `shopless_respawns`, `kit_purchases` (all kit purchases by any pilot, for "kit purchases per death") |
| `bay_shop` | `bay_purchases`, `bay_kit_purchases`, `bay_gear_purchases`, `bay_shop_trips` |
| `respawn_curve` | `steep_respawns` (waits longer than the old 50 s cap) |
| `bayA` | `bays_placed_back` |

## New files

| file | what |
|---|---|
| `scripts/world/world_slipstream.gd` | `WorldSlipstream`: fronts, who slips, lane bands, usage, arrival measure (A1/A1b) |
| `scripts/features/slipstream.gd` | `SlipstreamFeature` (key `slipstream`) |
| `scripts/features/redeploy.gd` | `RedeployFeature` (key `redeploy`): plan, jump start/finish, AI site choice, bay spots |
| `scripts/features/recall.gd` | `RecallFeature` (key `recall`): channel, cancel, dock, AI rule, ring |
| `scripts/features/recall_bar.gd` | `RecallBar`: the HUD bar of the human's recall (only with a window) |
| `scripts/features/size_respawn.gd` | `SizeRespawnFeature` (key `respawn`) |
| `scripts/features/respawn_site.gd` | `RespawnSiteFeature` (key `respawn_site`) |
| `scripts/features/bay_shop.gd` | `BayShopFeature` (key `bay_shop`) |
| `scripts/features/steep_respawn.gd` | `SteepRespawnFeature` (key `respawn_curve`) |
| `scripts/features/bay_back.gd` | `BayBackFeature` (key `bayA`) |
| `scripts/features/landing_spot.gd` | `LandingSpot`: a free spot next to a site (shared by A2 and A5) |
| `FORK_MANIFEST.md` | this file |

(Each script also has its `.uid` file made by `godot --import`.)

## Shared files changed (small, each guarded so that off means off)

| file | change |
|---|---|
| `scripts/data/rules.gd` | `VARIANT_DEFAULTS`: 8 new keys (all `off`) |
| `scripts/features/feature_registry.gd` | `FEATURES`: 8 new lines (order matters, see the comment there) |
| `scripts/entities/ship.gd` | new `var slip := false` |
| `scripts/entities/ship_stats.gd` | last step: `if ship.slip: WorldSlipstream.apply(ship)` |
| `scripts/ui/ship_status.gd` | `SLIPSTREAM` tag when `ship.slip` |
| `scripts/team/pilot_profile.gd` | new `var spool_site: Unit` (redeploy jump target) |
| `scripts/team/team_state.gd` | new `var plan_override: Array` (empty = normal plan) |
| `scripts/ai/admiral_plan.gd` | `next_step` reads `ts.plan_override` when not empty |
| `scripts/ai/admiral_builder.gd` | `place_bay` takes its [lane, fraction] list from `bay_spots()` of the features that have one |
| `scripts/ai/pilot_ai.gd` | `_hyperspace_bay()` returns `Unit`; first lines hand over to `RedeployFeature.pick_site` when on |
| `scripts/ai/pilot_goals.gd` | `think_home` first asks features with `ai_think_home()` (recall, bay_shop) |
| `scripts/world/world_hangar.gd` | `hyperspace_launch(p, bay: Unit)` hands over to `RedeployFeature.start` when on; `try_dock(s, from_anywhere := false)` |
| `scripts/world/world.gd` | forwarders: `hyperspace_launch(..., bay: Unit)`, `try_dock(s, from_anywhere := false)` |
| `scripts/world/match_rules.gd` | spool end: `if p.spool_site != null: RedeployFeature.finish(p)` |
| `scripts/ui/hangar.gd`, `hangar_gear.gd`, `hangar_kits.gd` | `can_shop_goods()` (kits and gear may be bought inside a serving bay when `bay_shop` is on) |

No test file was changed.

## What the AI does with each idea

- A1/A1b: nothing new; its lane routes simply get faster (jungle-job pilots are excluded).
- A2: `PilotAI.update_docked` -> `RedeployFeature.pick_site` (destination: siege stage/assault point, defend point, jungle camp, or lane front; nearest safe bay/turret at least 6,000 closer than the mothership); the admiral builds hyperspace early and puts its next bay at 0.5 of the push/siege lane.
- A3: `PilotGoals.think_home` -> `RecallFeature.ai_think_home` (retreat/home state, > 9,000 from the mothership hull, no visible enemy pilot within 3,000, 4 s without damage): channel, hold still, shoot nothing.
- A4, A7: nothing needed (the wait is simply different).
- A5: the AI pilot is launched at the forward site; its usual go-home rule decides when it shops.
- A6: AI pilots hovering at a serving bay run their kit and gear wish list there; a "gear:" shopping trip goes to such a bay when it is 6,000 closer than the mothership.
