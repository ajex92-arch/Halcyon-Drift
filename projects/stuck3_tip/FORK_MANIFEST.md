# Rule sets and fun-experiment switches (docs/FUN_PLAN.md section 6)

Since v0.2.0 the game carries every idea of the six fun-experiment forks, each behind its
own variant key, plus the fleet-cap key and two ready-made rule sets (presets). The base is
the v0.1.0 game (project name Halcyon Drift, team display name Aurelian; the internal team
label stays Halcyon). Every key defaults to off, which is the v0.1.0 rules for that key: with
`--preset=none` and no `--variant`, every variant is at its default (the other changes of
v0.3.0 are not switches and stay). Since v0.3.0 a match with no `--preset` plays Council's
pick, the standard rules.
The six forks' own manifests are kept in `docs/fork_manifests/<fork>.md`, with only their
paths, base names and a few notes (the user's later decisions, the API index) updated for this
repository (keys, values, usage counters and shared-file edits of each fork). Their build reports are in
`../fun_plan/reports/`, and the plain-words summary of this release, with the validation
result, is `docs/RELEASE_NOTES.md`.

## The presets (the two chosen by the user, Sat 2026-10-17)

| preset | launch option | the switches it turns on (`--variant` string) |
|---|---|---|
| Old standard rules (v0.1.0) | `--preset=none` | none: every key at its default (tests and research only) |
| Within requirements | `--preset=within` | `minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,gear_mk2:on,fleet_cap:60` |
| Council's pick: the STANDARD RULES (what a match with no `--preset` plays) | `--preset=pick` | the same plus `node_persist:on` |

What they do, in plain words:

- `minion_cap:on`: late-game minions no longer out-scale pilots. A minion's shot at a pilot
  ship counts as at most +15% stronger than a fresh minion, and the Reinforced Waves research
  does not count for it. This is a damage modifier: with the damage
  modifiers removed (see below) it does nothing, and the key still loads so the presets work.
- `lance_role:on`: the Lance hunts big ships that lost their escort and goes round to their
  tail; its beam does x1.35 to a large or capital ship's rear shield zone (a damage modifier:
  not with the damage modifiers removed).
- `bomber_role:both`: seats 6 and 10 fly Fighters instead of Bombers, a lane Bomber with
  nothing else to shoot may fire at a small enemy pilot ship, and a pilot's torpedo does x0.6
  to small craft (x0.35 by default; the x0.6 is a damage modifier, not applied with the damage
  modifiers removed).
- `admiral_sinks:fleet`: the AI admiral spends a big treasury: it builds the Fleet Command
  Module (free waves stop, it buys minions) and keeps placing wards.
- `redeploy:on`: the AI admiral builds the Hyperspace Module early. A hyperspace launch to a
  friendly repair bay spools for 4 s instead of 6, and AI pilots can also jump to a friendly
  turret near the fight (the hangar offers a human pilot repair bays only).
- `gear_mk2:on`: every gear item can be upgraded once to Mk II (2.5 x its price, stats
  x1.6): a repeatable pilot money sink, approved by the user.
- `fleet_cap:60`: a team may have up to 60 bought minions alive (30 in the old rules). The
  same limit holds for both teams and for a human or AI admiral; the board's texts show it.
- `node_persist:on` (pick only): a node whose turret was destroyed stays locked for 150 s
  (60 by default), a turret built there again starts at half hull but then only repairs 1% a
  second (a new turret is full when its build ends), and the AI admiral rebuilds the nodes
  nearest its own mothership first.

None of these changes a requirement. The Fleet Command limit of 60 is the requirement since
the user's decision of 2026-10-17 (docs/DESIGN.md, C22); the original
docs/USER_REQUIREMENTS_2026-10-13.md still says 30. The requirement-changing ideas (REQ-CHANGE)
are in neither preset: each stays a single switch (below), off by default, so the user makes
that call.

How to play a preset:

- Start screen: no rule choice. Every match plays the standard rules, Council's pick, unless
  the game was launched with another `--preset`. If the launch option was not understood, a
  line under the rules text says so and both seat buttons stay off (relaunch without it or
  with a known name).
- Command line: `godot --path remake -- --preset=none` (or `within`, or `pick`; `pick` is what
  a match plays without the option). `--variant` still works on top and wins for its keys:
  `--preset=pick --variant=fleet_cap:30` is the pick with the old rules' minion limit (a limit
  other than 60, so a requirement change).
- An unknown preset name stops the match at its start ("PRESET UNKNOWN", exit code 3),
  like a FEATURE CONFLICT, so a typo never plays other rules by mistake.
- The strings live in `scripts/data/council_presets.gd` (CouncilPresets); the 80-seed
  validation ran the same strings as `--variant`.

## The damage-modifiers switch

The damage modifiers (the damage table and the other fixed damage
multipliers, `docs/DESIGN.md` A5) are behind one switch, `Rules.DAMAGE_MODIFIERS_REMOVED`:

- false (the default of this build): the game plays with all of them.
  Every key above does what its description says. For a preset with pairs (the standard rules
  included), `CouncilPresets.variant_string()` adds `minion_cap:on,lance_role:on,bomber_role:both` after
  the preset's own pairs, so those three keys keep their damage parts even if a preset string
  stops listing them (`--variant` still wins).
- true: the modifiers are removed and every hit does its raw damage. `minion_cap`, the rear-zone
  part of `lance_role` and the torpedo number of `bomber_role` do nothing; the rest of those
  keys (the Lance's hunt, the Bomber's seats and its targeting rule) works as before.
- `--damage-modifiers-removed` (or `=0` / `=false`) overrides the constant for one run.

## The difficulty setting

Not a variant key: one setting, `Game.difficulty` (one of `Difficulty.ORDER`, `scripts/data/difficulty.gd`), that
multiplies everything the enemy team earns in a single-player match (one human, pilot or Admiral, against the AI).
The enemy team is the team with no human on it. A match with no human seat, the human's own team and Medium are
never changed: the multiplier is exactly 1.0 there, so those matches play exactly as before (det identical).

| level | `--difficulty` | the enemy earns |
|---|---|---|
| Easy | `easy` | x0.75 |
| Medium (the default) | `medium` | x1.0 (the standard game) |
| Hard | `hard` | x1.25 |
| Very hard | `very_hard` | x1.5 |
| Extreme | `extreme` | x2.0 |

- Start screen: the DIFFICULTY row under the rules text. The last pick is remembered between runs in
  `user://halcyon_settings.cfg`; only the start screen reads that file, so a test or any run without a start screen
  never depends on what was picked on this computer.
- Command line: `--difficulty=<level>` wins over the remembered pick. An unknown word stops the match at its
  start ("DIFFICULTY UNKNOWN", exit code 3), like an unknown `--preset`.
- What is multiplied (as each payment arrives, never rounded): the enemy pilots' credits (`PilotProfile.earn()` and
  `earn_quietly()`: kills, assists, minions, camps, turrets, bays, drones, wards, the ore share, the escort bonus, the
  stipend, the steady trickle) and its Admiral's treasury (`TeamState.earn()`: the 60% ore share, the mothership's
  income, the rewards for destroyed turrets and repair bays). Not multiplied: starting credits and treasury, sales and
  trade-ins, insurance, the refund of an expired admiral order, money moved between one team's pilots.

## The team you play for

Not a variant key: one setting, `Game.human_team` (`Rules.HALCYON` = Aurelian, the default, or `Rules.CINDER` =
Vhorr), that puts the human, in either seat, on that team. The other team is all computer. With Aurelian chosen
and in every match with no human seat (every test and determinism run) the match plays exactly as before
(det identical).

| what | where | plays differently |
|---|---|---|
| The human pilot takes slot 0 of the chosen team, or the human Admiral its Admiral chair (and the extra Admiral record, slot 12); the other team's Admiral is the computer; the difficulty's income multiplier goes to the other team; the fog, the minimap, the HUD, the end screen, the Admiral board and map tools, the pop-ups and the camera's start (1,800 units in front of the human's own mothership) follow the chosen team. The map is not mirrored: as Vhorr you start on the right | `WorldSetup.build` step 1, 4 and 5, `World.human_team`, `CameraRig.setup`, `CommandOverlay.setup`, `AdmiralBoard.setup`, `Hud` | only with Vhorr chosen, and then only which team the human is on |
| The menus' highlight colour (the top-left panel's first line, the pressed and chosen buttons, the filled buttons, the selected hangar and Admiral board tabs, prices, your own scoreboard row, the rally point, the start screen's chosen buttons and top line) follows the human's team: amber for Aurelian and for a spectator, red (`Palette.CINDER_VEIN`) for Vhorr. The start screen changes it the moment the team button is pressed. Colours that mean something do not change: the team colours, the kill feed's amber for good news and red for bad news, the banners' tones, Victory and Defeat, warnings, the health, shield and energy bars | `Palette.accent()`, `UiKit.accent()` and `UiKit.set_accent_team()`, `Hud.setup`, `StartScreen._use_team_accent` | nothing in a match: colours only (det identical) |

- Start screen: the TEAM row under the DIFFICULTY row: Aurelian and Vhorr buttons (each in its team colour) and a
  one-line description. The last pick is remembered between runs in `user://halcyon_settings.cfg` (the key `team`,
  next to the difficulty); only the start screen reads that file, so a test or any run without a start screen never
  depends on what was picked on this computer. The Pilot card names the chosen team as the one the computer Admiral
  commands.
- Command line: `--team=aurelian` or `--team=vhorr` (any capitals) wins over the remembered pick. An unknown word
  stops the match at its start ("TEAM UNKNOWN", exit code 3), like an unknown `--preset`. A spectator (`--all-ai`) has
  no team: the option changes nothing for them.
- Checked by `tests/team_check.gd` (run_checks: team_pilot_aurelian, team_pilot_vhorr, team_admiral_aurelian,
  team_admiral_vhorr, team_default, team_spectator, team_spectator_hud, team_unknown), which also checks the highlight
  colour of the HUD, the tabs, a card and the start screen for each team; `tests/team_shots.gd` takes pictures of a real
  match on the chosen team (the open hangar, the Admiral board, the start screen).

## Lane pilots farm minions

Not a variant key and not a setting: a new step in the lane pilots' thinking that is always on in this build, with
one tuning number. It changes how the AI plays, so a match is no longer the same as in v0.2.1.

| what | where | the number | plays differently |
|---|---|---|---|
| A lane pilot with no target, nothing to push, no pilot to hunt and a plain station behind our wave (no opening, no admiral order) flies out to the best enemy minion within `FARM_RADIUS` of our wave's front minion, to gun reach of it on our side, and shoots it (a minion about to die first) | `PilotGoals.think_lane` step 7, `PilotTargeting.farm_target()` and `minion_score()`, `PilotGoals.front_minion()` | `PilotTargeting.FARM_RADIUS`, 1,500 world units | yes, in every match with lane minions |
| A plain station is moved out of our own turrets: nearer one than its hull plus the ship's radius plus 160, it is pushed straight out to that distance | `PilotGoals._pick_station` step 3b | none (the 160 is the distance at which a pilot counts as arrived) | yes, only where a station met a turret (the outer Crossings) |

## Minion handling, small-ship hit size and turrets

Not variant keys and not settings: three rules that are always on in this build, each with named numbers. They
change how a match plays, so a match is no longer the same as in v0.2.1.

| what | where | the numbers | plays differently |
|---|---|---|---|
| Minions handle heavier: a minion's change of velocity in one step is held to an ellipse, 0.9 x accel along the way it flies and 0.8 x accel across it; the nose turns at 0.8 of what it did. Top speed, the wave's pace and the rock push are as before; the mining drones, wards and repair bays keep `Steer.seek` | `MinionFlight.steer` (used by `combat_move` and `lane_move`), `Minions.TYPES` "turn" | `Minions.ALONG_ACCEL_MUL` 0.9, `Minions.SIDE_ACCEL_MUL` 0.8, `Minions.MIN_HEADING_SPEED` 10; turn 2.4, 1.28 and 0.8 | yes, every lane minion |
| The small pilot ships (Scout 9, Fighter 12, Lance Fighter 13, Bomber 17) are 10% bigger for rounds, beams and blasts (9.9, 13.2, 14.3, 18.7); the AI aims and fires against that size. Their body (physics circle, push-apart, rocks, walls, docking, vision) and every other unit are unchanged | `Unit.hit_radius()` (`Ship.hit_radius()` overrides it), read by `Unit.hit_t`, `ProjectilesHitScan.scan`, `CombatBeamArea.area`, `PilotCombat.fight`, `WeaponMountTargeting`, `Turret`, `Minion`, `Derelict`, the Barrage | `Rules.SMALL_PILOT_HIT_MUL` 1.1 | yes, wherever a shot meets a small pilot ship |
| Turrets have no shields and nothing can repair one: shield 0 for both types (no pool, no bar, no refill); `Unit.heal()` refuses turrets, so the Logistics Corvette's drones and Emergency Repair pass them by, and the drones do not look for them as work. Kept: the build itself, Platform Armor keeping the share of hull, and the `node_persist` rule's slow repair of a rebuilt turret; repair bays, wards, the motherships and every ship keep their shields and repairs | `TurretData.TURRETS` "shield", `Turret.setup` and `sim_update`, `Unit.heal`, `RepairDrone._pick_target` | shield 0.0 | yes, every turret |

## Minion looks

Drawing only: not a variant key and not a setting. How the three lane minions are drawn is fixed in the code
(`scripts/data/minion_shapes.gd` for Aurelian, `CinderShapes.MINIONS` for Vhorr), and a match plays exactly as
before (det_check -Full identical). `docs/CODE_GUIDE.md` ("minion look") says why they are plain.

| minion | Aurelian look | Vhorr look | plays differently |
|---|---|---|---|
| Snub-Fighter | a blunt wedge | Spore: a narrow, pointed teardrop | no |
| Light Bomber | a squat box | Bloat: a short, broad pod, blunt at both ends (redrawn: it was a long teardrop that read too like the Spore) | no |
| Patrol Leader | a plain triangle | Cocoon: a long gourd of two lobes | no |

## The look fixes

Drawing only: not a variant key and not a setting. Three small changes to what is drawn, fixed in the code, and a match
plays exactly as before (det_check -Full identical). `docs/PROGRESS.md` has the details and the checks.

| what | where | the numbers | plays differently |
|---|---|---|---|
| The drift arrow (and its slip tick) is drawn on the ship the human flies and on no other ship, at any zoom (it used to show on every ship once zoomed in past 0.4) | `ShipVisual._draw` | none | no |
| A hit flashes the outline and leaves the fill alone: for the same 0.09 s the line turns toward white and is drawn thicker (pilot ships of both teams, minions, drones, wards, turrets, repair bays, derelict camps, snub fighters and both motherships; not the pilot extractor of the `pilot_mining:extractor` variant, which draws itself) | `ShipVisual._draw_hull`, `UnitVisual._poly`, `UnitVisual._draw_mothership`, `CinderPaint.draw_shape`, `Palette.hit_edge()` and `hit_width()` | `Palette.HIT_FLASH` 0.8, `HIT_FLASH_MOTHER` 0.4, `HIT_WIDTH_GAIN` 1.2 | no |
| The lane and node names on the map are never taller than about 60 screen pixels: each is drawn at the smaller of its old size (180 and 150 world units) and the size that is 60 pixels tall at the camera's zoom | `MapDecor._process` and `_draw_names` (the names have a child node of their own, so only they are redrawn when their size changes) | `MapDecor.LABEL_MAX_PX` 60 | no |

## Every other switch: off by default, opt-in with --variant

`REQ` = changes a requirement (kept as a switch: FUN_PLAN, "don't reject anything that
violates my constraints"); `DESIGN` = the research had rejected the idea on fun grounds.
Status = the screens' verdict as the forks finished it (`docs/RELEASE_NOTES.md` has the
requirement-changing ones in plain words with their measured effect).

| fork | key:value | in plain words | flag | status |
|---|---|---|---|---|
| endgame | `siege_fix:gather3` | sieges wait for 3 big ships | - | not in a preset (negative alone over full matches) |
| endgame | `siege_fix:full`, `siege_fix:stall` | other siege-AI fixes | - | rejected |
| endgame | `breach:on` | a lane-breach corvette | - | rejected |
| endgame | `breach:fulldmg` | breach corvettes hit the mothership at full strength (with the damage modifiers removed this is a doubling, since minions' x0.5 on the mothership is gone) | REQ | opt-in; rejected by the protocol (minions, not big ships, close the game) |
| endgame | `ms_cap:on` | mothership hull damage capped (x0.5 beyond a rate) | REQ (mild) | opt-in; rejected alone |
| endgame | `ms_cap:full` | the same cap at x0.1 | REQ | opt-in; in one of the endgame fork's final combinations |
| endgame | `attrition:on` | fleet attrition after 40:00 | - | rejected |
| endgame | `retreat:last_stand` | Last Stand at 35% hull | - | invalid alone |
| endgame | `surrender:vote` | a surrender vote | REQ | opt-in; rejected |
| endgame | `breach_extra:on` | an 11th (super) minion in breached lanes | REQ | opt-in; rejected |
| endgame | `ms_soft:hull`, `ms_soft:shield` | a weaker mothership hull or shield | REQ | opt-in; rejected |
| endgame | `ms_soft:mult` | big ships hit the mothership x3 (does nothing with the damage modifiers removed: the big-ship multiplier it raises is gone) | REQ | opt-in; in one of the endgame fork's final combinations |
| endgame | `waves_late:slow`, `waves_late:none` | fewer or no free waves late | REQ | opt-in; in one of the endgame fork's final combinations (a different one for each value) |
| endgame | `lanespawn:on` | late minions launch from the lane ends | REQ | opt-in; in one of the endgame fork's final combinations; no significant gain on top of 'within' |
| endgame | `eff:on` | weapon-aware target choice (does nothing with the damage modifiers removed: the damage table it reads is gone) | - | rejected |
| endgame | `ms:nosmall` | small craft stop sieging the mothership | REQ | opt-in; rejected |
| combat | `escort_pd:on`, `routing_payoff:on` | escorts guard big ships; a payoff for holding a routing | - | rejected |
| combat | `jungle_big:all` (`:medium`) | big ships may enter the jungle | REQ | opt-in; adds nothing significant on top of set A (`:medium` invalid) |
| combat | `zoom_max:wide`, `zoom_max:xwide` | a wider maximum zoom | REQ | opt-in; needs a human playtest |
| pacing | `slipstream:on` | a lane slipstream, size-scaled | - | rejected |
| pacing | `slipstream:flat` | a lane slipstream, one speed for every hull | REQ | opt-in; rejected |
| pacing | `slipstream:probe` | measurement only | - | no game change |
| pacing | `bayA:on`, `recall:on`, `respawn:size` | forward AI bays; a recall channel; size-scaled respawn | - | not kept (respawn:size harmful alone) |
| pacing | `respawn_site:bay`, `respawn_site:waypoint` | respawn forward | REQ | opt-in; rejected |
| pacing | `bay_shop:on` | kits and gear sold at repair bays | REQ | opt-in; rejected |
| pacing | `respawn_curve:steep` | a steeper late respawn curve | DESIGN | rejected |
| economy | `econ:play` | income from play | - | not in a preset (harmful without doctrine) |
| economy | `doctrine:on` | Fleet Doctrine research (a repeatable admiral sink) | - | HELD BY THE USER (their own admiral changes first) |
| economy | `catchup:income`, `catchup:share` | catch-up or shared income for the trailing team | DESIGN | not in a preset (the user's decision) |
| economy | `morale:on` | a push / morale meter | DESIGN | not in a preset (the user's decision) |
| economy | `bounties:on`, `bounties:equal`, `buyback:on` | comeback bounties; respawn buyback | - (equal: DESIGN) | rejected |
| economy | `pilot_mining:hold`, `pilot_mining:extractor` | pilots mine nodes | REQ | opt-in; rejected |
| economy | `ms_spend_weak:on` | the mothership weakens after big spends | REQ | opt-in; rejected |
| teamfights | `group_late:on` | late grouping on the push lane | - | not kept |
| teamfights | `salvage_core:on`, `jungle_scale:on` | a salvage core; a scaling jungle | - | rejected |
| teamfights | `feats:on` | early feats + a 14:00 Vanguard | DESIGN | rejected |
| teamfights | `epic:dreadnought`, `epic:elder` | timed epic neutrals | REQ | opt-in; hurt at full length (elder rejected) |
| teamfights | `beacons:on` | salvage beacons + sensor blackout | REQ | opt-in; hurt at full length |
| teamfights | `camp4:on` | a fourth jungle camp per quarter | DESIGN | not kept |
| admiral | `assets:on`, `assets:full` | Sensor Sweep, Supply Drop, Barrage | - | rejected |
| admiral | `assets:xray` | the Sweep sees through asteroids | REQ | opt-in; rejected |
| admiral | `orders:on`, `fortify:on`, `admiral_smart:on` | bounty orders; Fortify; a reactive AI admiral | - | rejected |
| admiral | `ms_move:early` | the mothership moves from 12:00 | REQ | opt-in; rejected |
| admiral | `ms_move:flying`, `ms_move:both` | the mothership moves while the admiral flies | REQ | opt-in; paper only |
| admiral | `home_vision:on` | a defenders' vision edge | DESIGN | dropped (harmful alone) |
| admiral | `mutiny:on` | pilots may vote the admiral out | REQ | opt-in; paper only |
| admiral | `fleet_cap:<n>` | a Fleet Command limit other than 60 | REQ | the requirement is 60 since 2026-10-17; the old rules (`--preset=none`) use 30 (v0.1.0), the standard rules and `within` use 60 |

The game's own variants (not fork ideas): `escort_wing` = `extra` (the default: Escort Wing
adds an 11th minion, REQ-CHANGE "waves of 10") or `upgrade` (the requirement-compliant
version); `retreat` = `systems_failure` (default) or `none` (tests).

## Why the rejected modules stay in, switched off

FUN_PLAN says the council's build ports the chosen modules. The council kept every module
instead, each switched off by default, and removed none:

- Engineer: every module is one file behind its own key. FeatureRegistry installs only the
  switched-on ones, and with every key off det_hash equals v0.1.0's, so an off module changes
  nothing. Removing one means editing shared code too (FeatureRegistry, Rules.VARIANT_DEFAULTS
  and TUNABLES, the shared minion hook MinionHookChain, AI and UI call sites that ask
  `world.features.has(...)`, the fork manifests, the API index and the fork tests), with a
  real chance of breaking a kept module that shares a hook, for no change in play.
- Producer: removal is new scope on the way to the 80-seed validation, and it would change the
  code the screens measured. The user's rule keeps every REQ-CHANGE idea as a switch anyway,
  `doctrine:on` is held for the user, and several rejected ideas may be retested later
  (for example `econ:play` once doctrine is decided).
- Check: nothing to remove means keys-off stays identical to v0.1.0 and run_checks stays as
  it was. The cost is a longer list of off switches, documented above.

## Keys that refuse to run together (FUN_PLAN 4.5)

`FeatureRegistry.CONFLICTS` lists the pairs; a match with both keys of a pair on prints
`FEATURE CONFLICT: ...` and quits at match start (exit code 3). See the list in
`scripts/features/feature_registry.gd`.
