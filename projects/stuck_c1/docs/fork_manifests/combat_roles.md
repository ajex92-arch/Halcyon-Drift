# Fork manifest: combat_roles (fork E of the fun plan)

This is the build manifest of one fun-experiment fork, kept as it was when the fork was merged into the game (v0.2.0), with only its paths, base names and a few notes (the user's later decisions, the API index) updated for this repository. Paths are relative to `remake/`; the build report is
`../fun_plan/reports/combat_roles_build.md`.

Base: the game with every AI fix (the AI deep dive's pass 3, banked into `remake/` before
v0.1.0). Everything here is
opt-in: with every key below at its default (`off`) nothing runs, no random
number is drawn and no unit changes, and tests/det_hash.gd prints exactly the
base game's hash lines (checked: seed 7, 900 s normal and 300 s `--late`).

Use a key as `--variant=<key>:<value>` (several keys: comma-separated).

## Variant keys

| key | values (default first) | idea | REQ-CHANGE | usage counters (Game.usage) |
|---|---|---|---|---|
| `minion_cap` | `off`, `on` | E1: a minion's hit on a pilot ship counts as at most +15% strong, Reinforced Waves ignored for that hit | none | `capped_minion_hits` |
| `escort_pd` | `off`, `on` | E2: big ships' PD / flak / flak battery fire at x(0.6 + 0.2 x support), shields x0.7 when alone, ESCORTED / ISOLATED on the status panel | none | `big_isolated_seconds`, `big_escorted_seconds` |
| `lance_role` | `off`, `on` | E3: Lance beam x1.35 on a big ship's rear shield zone; Lance pilots hunt isolated big ships and go round to the tail | none | `rear_lance_hits`, `lance_prey_picks` |
| `routing_payoff` | `off`, `on` | E4: holding Weapons / Shields / Thrusters 3 / 4 / 6 / 8 s (small / medium / large / capital) charges a one-shot bonus; HUD pip | none | `charges_spent`, `charges_weapons`, `charges_shields`, `charges_thrusters`, `routing_holds` |
| `jungle_big` | `off`, `medium`, `all` | E5: MEDIUM (or also LARGE and CAPITAL) ships may use the jungle (wider gates / paths, route graph, AI route choice by flying time) | **REQ-CHANGE: "a jungle ... that only small ships can travel through"** | `big_jungle_seconds`, `big_jungle_routes`, `camp_kills_small`, `camp_kills_medium`, `camp_kills_big` |
| `zoom_max` | `off`, `wide` (x1.5), `xwide` (x2.0) | E6: the human camera may zoom out further | **REQ-CHANGE: "lock players to a max zoom that is close to their ship ... scales with ship size"** | `zoom_wide_frames` (0 headless: not screenable) |
| `bomber_role` | `off`, `seats`, `torp`, `both` | carry-overs: seats 6 and 10 fly Fighters; pilot torpedoes x0.6 (not x0.35) to small craft | none | `bomber_seat_swaps`, `torpedo_small_hits` |

New tuned number (Rules.TUNABLES): `torp_small_mult` (0.35 normal; set to 0.6
by `bomber_role:torp` / `both`).

## Files added

Feature modules (scripts/features/):

- `minion_cap.gd` (MinionCapFeature) E1, through `Combat.minion_scale_hook`.
- `escort_pd.gd` (EscortPdFeature) E2, through `World.tick_hooks`.
- `lance_role.gd` (LanceRoleFeature) E3: damage rule, prey search, approach steering.
  - `lance_role_goals.gd` (LanceRoleGoals extends PilotGoals): hunt after the normal think.
  - `lance_role_combat.gd` (LanceRoleCombat extends PilotCombat): go round to the tail.
- `routing_payoff.gd` (RoutingPayoffFeature) E4.
  - `routing_payoff_systems.gd` (RoutingPayoffSystems extends PilotSystems): hold Weapons 1.2-2 ranges from an enemy.
- `jungle_big.gd` (JungleBigFeature) E5: gate / path numbers, route choice, counters.
- `zoom_max.gd` (ZoomMaxFeature, a Node) E6.
- `bomber_role.gd` (BomberRoleFeature) carry-overs.
  - `bomber_role_shopping.gd` (BomberRoleShopping extends PilotShopping): seats 6 / 10 want Fighters.
  - `bomber_role_targeting.gd` (BomberRoleTargeting extends PilotTargeting): a lane Bomber with nothing else may shoot a small enemy pilot ship.
- Shared helpers for the above:
  - `role_scaling.gd` (RoleScaling extends CombatScaling): the damage calculator with a list of plug-in rules (`hooks`). Installed into `world.combat.scaling` by E3, E4 and `bomber_role:torp`. No Combat edit needed.
  - `role_brains.gd` (RoleBrains): puts a feature's version of an AI brain part into every pilot's brain (now and every 0.5 s, so arena brains made later get it too).
  - `role_hud.gd` (RoleHud): the ESCORTED / ISOLATED words and the routing pip on the ship status panel.

Tests (tests/):

- `roles_probe.gd`: arena / travel / unit checks that print the usage counters (`--test=roles_probe`; options in its header: `--a`, `--b`, `--secs`, `--show`, `--debug`, `--start`, `--goto`, `--unit`, `--unit4`).
- `zoom_check.gd`: E6 camera limits and counter; windowed with `--shots=<dir>` it saves `zoom_<value>.png`.

## Shared files changed (all small; a variant at its default changes nothing)

| file | change | why |
|---|---|---|
| `scripts/features/feature_registry.gd` | 7 lines added to `FEATURES` | the registrations |
| `scripts/data/rules.gd` | 7 keys in `VARIANT_DEFAULTS` (all `"off"`), 1 entry in `TUNABLES` (`torp_small_mult`) | defaults and the new tuned number |
| `scripts/ui/ship_status.gd` | 1 line: `RoleHud.draw(self, ship)` at the end of `_draw()` | E2 / E4 panel text and pip (returns at once when no feature is on) |
| `scripts/camera/camera_rig.gd` | `zoom_limits()`: the follow-mode width is multiplied by `ZoomMaxFeature.factor()` (1.0 when off) | E6 |
| `scripts/world/map_builder_walls.gd` | 3 reads of `MapLayout.CHOKE_GAP` became `JungleBigFeature.choke_gap()` (same number when off) | E5 gate width |
| `scripts/world/map_builder_fill.gd` | 1 read of `MapLayout.PATH_HALF` became `JungleBigFeature.path_half()` (same number when off) | E5 path width |
| `scripts/ai/pilot_flight.gd` | the route request `route.path(p, to, ship.is_small())` became `JungleBigFeature.plan_route(route, ship, p, to)` (the same call when off) | E5 AI route choice |
| `scripts/ai/pilot_escape.gd` | 2 uses of `ship.is_small()` for route dots became `JungleBigFeature.route_small(ship)` (same answer when off) | E5 (a big ship stuck in the jungle plans its way out through jungle dots) |
| `docs/API_INDEX.md` | sections for the new files | code map |

Nothing else outside scripts/features/ and tests/ was edited.

## Design notes (what each idea does exactly)

- **E1** `Combat.minion_scale_hook`: for a hit on a pilot ship the strength used is `min(stat_scale / (1 + team.minion_buff), 1.15)`; never above what the minion has. Hull, shields and hits on minions / turrets / bays / mothership unchanged. `MINION_VS_SHIP_MULT` (0.6) untouched.
- **E2** Every 0.5 s: support = friendly pilot ships within 2,500 (not itself) + floor(friendly minions within 2,500 / 3), max 3, for each LARGE / CAPITAL pilot ship. Guns (`pd_gun`, `flak_auto`, `flak_battery`) get their own copy of the weapon data with `rate` x(0.6 + 0.2 x support); `shields.regen` x0.7 at support 0.
- **E3** Rule: kind `W_LANCE`, target a pilot ship of size LARGE or CAPITAL, the hit lands in `ZONE_REAR` (the game's own zone test): x1.35. AI: a Lance with >= 60% hull and no other pilot target picks the nearest visible isolated enemy big ship within 6,000 (support 0 under `escort_pd`, else no friend within 2,500) as prey (intent `prey`), flies to its tail, and circles it at 450 from its hull (boosting) until it is in the rear zone.
- **E4** thresholds 3 / 4 / 6 / 8 s. Weapons charged: the first main-gun shot (not an auto gun) opens a 2 s window in which ALL damage the ship deals is x1.4. Shields charged: the first hit adds 40% of the focused zone's size to it (Balanced focus: the front zone); what is above the zone's normal size is dropped after 6 s. Thrusters charged: the first boost is free (energy paid back each tick) and pushes 20% harder for 1.5 s. AI: pilots whose original `PilotSystems` rule asked for a routing (the existing skill > 0.55 rule; no new threshold) request Weapons when an enemy ship is 1.2-2 weapon ranges away (not when retreating / home / below 40% hull / asking for Shields).
- **E5** Gate opening 86 -> 130 (`medium`) or 400 (`all`); filler-free path half-width 150 -> 260 (`all` only). `plan_route`: for MEDIUM (`medium`) or any non-small ship (`all`), the cheaper (flying time; jungle legs at 62% speed) of the lane-only and the jungle-allowed route. Small ships and junglers: unchanged. Random numbers are drawn in the same order, so only rocks next to gates and paths differ from the normal map. The map is exactly the normal one when the key is `off`.
- **E6** `PILOT_VIEW_WIDTH` x1.5 / x2.0 for a pilot's zoom-out limit (`CameraRig.zoom_limited()`). No game rule reads the zoom (checked: only drawing code and Sfx's hearing range), so a headless match cannot show any change.
- **bomber_role**: `seats`: seats 6 and 10 (striker temperament) wish list = just the Fighter; seat 2 keeps the Bomber. `torp`: only torpedoes fired by PILOTS (not minions or turrets, so E1 stays the only lever on minion damage) do `torp_small_mult` (0.6) instead of the table's 0.35 to small craft; and a lane Bomber that would otherwise have no target may shoot a small enemy pilot ship.
