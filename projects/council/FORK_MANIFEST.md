# Council branch manifest (docs/FUN_PLAN.md section 6)

The council build = the v0.1.0 release (project name Halcyon Drift, team display name
Aurelian; the internal team label stays Halcyon) merged with all six fun forks and the
fleet-cap key. Every idea of every fork is here behind its own variant key, and every key
defaults to today's game: with no `--preset` and no `--variant`, a match is the v0.1.0
game (tests/det_hash.gd prints main's hash lines). The six forks' own manifests are kept
unchanged in `docs/fork_manifests/<fork>.md` (keys, values, usage counters, shared-file
edits of each fork).

Local-only git repo (no remote): branches `forkbase`, `fork/<name>` (tags
`fork/<name>/final`), `base` and `base-v010` (the base line; `base-v010` holds the v0.1.0
release tree), `council`, `fleetcap`, `council-presets`. A validated build is a tag
`council/presets-v<N>`; the council's final report cites that tag. Notes, key table and
presets of the council: `SP\fun\council\` (keys.md, presets.md, COUNCIL_REPORT.md).

## The two presets (chosen by the user, Sat 2026-10-17)

| preset | launch option | the switches it turns on (`--variant` string) |
|---|---|---|
| Within requirements | `--preset=within` | `minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,gear_mk2:on,fleet_cap:60` |
| Council's pick | `--preset=pick` | the same plus `node_persist:on` |

What they do, in plain words:

- `minion_cap:on`: late-game minions no longer out-scale pilots. A minion's shot at a pilot
  ship counts as at most +15% stronger than a fresh minion, and the Reinforced Waves research
  does not count for it.
- `lance_role:on`: the Lance hunts big ships that lost their escort; its beam does x1.35 to
  a large or capital ship's rear shield zone.
- `bomber_role:both`: seats 6 and 10 fly Fighters instead of Bombers, and a pilot's torpedo
  does x0.6 to small craft (x0.35 today).
- `admiral_sinks:fleet`: the AI admiral spends a big treasury: it builds the Fleet Command
  Module (free waves stop, it buys minions) and keeps placing wards.
- `redeploy:on`: the AI admiral builds the Hyperspace Module early; pilots can jump to a
  friendly repair bay or turret near the fight (4 s spool-up), and AI pilots do.
- `gear_mk2:on`: every gear item can be upgraded once to Mk II (2.5 x its price, stats
  x1.6): a repeatable pilot money sink, approved by the user.
- `fleet_cap:60`: a team may have up to 60 bought minions alive (30 today). The same limit
  holds for both teams and for a human or AI admiral; the board's texts show it.
- `node_persist:on` (pick only): a node whose turret was destroyed stays locked for 150 s
  (60 today), and a turret built there again starts at half hull and repairs 1% a second.

None of these changes a requirement in docs/USER_REQUIREMENTS_2026-10-13.md. The
requirement-changing ideas (REQ-CHANGE) are in neither preset: each stays a single switch
(below), off by default, so the user makes that call.

How to play a preset:

- Start screen: the RULE SET row under the rules text: "Today's game" (chosen at first),
  "Within requirements" or "Council's pick". Pick one, then pick your seat.
- Command line: `godot --path remake -- --preset=within` (or `pick`). `--variant` still
  works on top and wins for its keys: `--preset=pick --variant=fleet_cap:30` is the pick
  with today's limit.
- An unknown preset name stops the match at its start ("PRESET UNKNOWN", exit code 3),
  like a FEATURE CONFLICT, so a typo never plays today's game by mistake.
- The strings live in `scripts/data/council_presets.gd` (CouncilPresets); the council's
  80-seed validation runs the same strings as `--variant`.

## Every other switch: off by default, opt-in with --variant

`REQ` = changes a requirement (kept as a switch: FUN_PLAN, "don't reject anything that
violates my constraints"); `DESIGN` = the research had rejected the idea on fun grounds.
Status = the screens' verdict as the forks finished it (the council's final report has the
numbers).

| fork | key:value | in plain words | flag | status |
|---|---|---|---|---|
| endgame | `siege_fix:gather3` | sieges wait for 3 big ships | - | not in a preset (negative alone over full matches) |
| endgame | `siege_fix:full`, `siege_fix:stall` | other siege-AI fixes | - | rejected |
| endgame | `breach:on` | a lane-breach corvette | - | rejected |
| endgame | `breach:fulldmg` | breach corvettes hit the mothership at full strength | REQ | opt-in; rejected by the protocol (minions, not big ships, close the game) |
| endgame | `ms_cap:on` | mothership hull damage capped (x0.5 beyond a rate) | REQ (mild) | opt-in; rejected alone |
| endgame | `ms_cap:full` | the same cap at x0.1 | REQ | opt-in; in the endgame final fF6 |
| endgame | `attrition:on` | fleet attrition after 40:00 | - | rejected |
| endgame | `retreat:last_stand` | Last Stand at 35% hull | - | invalid alone |
| endgame | `surrender:vote` | a surrender vote | REQ | opt-in; rejected |
| endgame | `breach_extra:on` | an 11th (super) minion in breached lanes | REQ | opt-in; rejected |
| endgame | `ms_soft:hull`, `ms_soft:shield` | a weaker mothership hull or shield | REQ | opt-in; rejected |
| endgame | `ms_soft:mult` | big ships hit the mothership x3 | REQ | opt-in; in fF6 |
| endgame | `waves_late:slow`, `waves_late:none` | fewer or no free waves late | REQ | opt-in; in fF2 / fF6 |
| endgame | `lanespawn:on` | late minions launch from the lane ends | REQ | opt-in; in fF6; no significant gain on top of 'within' |
| endgame | `eff:on` | weapon-aware target choice | - | rejected |
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

Main's own variants (not fork ideas): `escort_wing` = `extra` (today's default: Escort Wing
adds an 11th minion, REQ-CHANGE "waves of 10") or `upgrade` (the requirement-compliant
version); `retreat` = `systems_failure` (default) or `none` (tests).

## Why the rejected modules stay in, switched off

FUN_PLAN says the council build ports the chosen modules. The council kept every module
instead, each switched off by default, and removed none:

- Engineer: every module is one file behind its own key. FeatureRegistry installs only the
  switched-on ones, and with every key off det_hash equals main's, so an off module changes
  nothing. Removing one means editing shared code too (FeatureRegistry, Rules.VARIANT_DEFAULTS
  and TUNABLES, the shared minion hook MinionHookChain, AI and UI call sites that ask
  `world.features.has(...)`, the fork manifests, the API index and the fork tests), with a
  real chance of breaking a kept module that shares a hook, for no change in play.
- Producer: removal is new scope on the way to the 80-seed validation, and it would change the
  code the screens measured. The user's rule keeps every REQ-CHANGE idea as a switch anyway,
  `doctrine:on` is held for the user, and several rejected ideas may be retested later
  (for example `econ:play` once doctrine is decided).
- Check: nothing to remove means keys-off stays identical to the release and run_checks stays
  as it was. The cost is a longer list of off switches, documented above.

## Keys that refuse to run together (FUN_PLAN 4.5)

`FeatureRegistry.CONFLICTS` lists the pairs; a match with both keys of a pair on prints
`FEATURE CONFLICT: ...` and quits at match start (exit code 3). See the list in
`scripts/features/feature_registry.gd`.
