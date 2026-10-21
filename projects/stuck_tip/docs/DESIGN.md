# Halcyon Drift — Remake design (v2)

Single source of truth for the remake. Owner: lead. Implementation agents
follow this document plus the code contract (the foundation code and the
documented stub classes in `remake/scripts`). If code and this document
disagree, raise it; do not silently diverge.

**Setting.** The battle is fought in the Halcyon Drift, an asteroid belt,
and the project is named after it (user decision, 2026-10-16; see C20 in
A2). The three lanes, the asteroid resource nodes and the asteroid jungle
described below are all inside the belt. That is all that is decided about
it: no history, factions or other places are invented. The two teams are
Aurelian (team 0, amber; the user's name for it since 2026-10-16, see C21
in A2 and A16) and Vhorr (team 1, red; the user's name for it since 2026-10-17, see C23 in A2).

Requirement sources, in priority order (later overrides earlier):

1. `prompt1_original_brief.txt` — the original brief.
2. `prompt2_amendments.txt` — drones instead of capture, HW2 tech tree,
   start with Scout (free) + Fighter, more players, AI pass.
3. `USER_REQUIREMENTS_2026-10-13.md` — the MOBA restructure (overrides
   everything above where they conflict).
4. The user's later decisions, recorded in A2 (for example C22, the Fleet
   Command limit of 60). They override the sources above where they conflict.

Also read `LESSONS_FROM_V1.md` (what v1 got right/wrong, Godot gotchas,
environment) and `TECH_TREE_REFERENCE.md`.

All numbers below are STARTING values. Playtest harnesses will tune them;
the tuned values live in `scripts/data/*.gd`, which win over this file.

---------------------------------------------------------------------------

## PART A — GAME DESIGN

### A1. Vision

A top-down 2D space MOBA at Homeworld scale. Two motherships face each other
across three lanes. Minion waves grind down each lane; turrets built by each
side's Admiral anchor the lanes at asteroid resource nodes; a dense asteroid
"jungle" between the lanes holds derelict monsters and is passable only by
strike craft. Each team is 12 pilots plus 1 Admiral.

The match is a skirmish that ramps into a major engagement:

- **Early (0–6 min):** Scouts and Fighters dogfight over minion waves; first
  turrets go up; mining drones start hauling. Small-ship flight skill decides
  fights (Counter-Strike-like duels: strafing, boost timing, shield facing,
  energy routing).
- **Mid (6–18 min):** Bombers, Lance fighters, corvettes arrive; first
  frigates; turrets start to fall; repair bays and wards shape the map.
- **Late (18 min+):** Frigates and capital ships anchor pushes; large-ship
  players win through positioning (flak + point defense shred anything that
  comes at their front; out of position = dead fast). Capital guns can carve
  the jungle open. From 20:00 the docked Admiral may move the mothership. The
  match ends ONLY when a mothership is destroyed.

Pillars:

1. **Skill shows.** Small ships: momentum, strafing, shield focus, energy
   routing, last-hitting minions, jungle routes. Large ships: positioning,
   facing (4 shield zones), choosing when to push.
2. **Every size matters.** Big ships are not strictly better: torpedo
   bombers and lance fighters punish lone frigates; flak/PD frigates punish
   fighter swarms; minions are needed to take turrets; capitals are slow and
   blind without escorts.
3. **The Admiral seat matters but pilots are never helpless.** Pilots earn
   their own money (kills, minion last hits, jungle, drone deliveries share,
   passive income) and buy their own ships, modules and pilot gear.
4. **Readable at scale.** Velocity arrow, thruster particles (main and
   lateral), 4-zone shield arcs, team colours, lane guides, ownership rings
   on nodes, clear turret aggro tells, fog of war that respects asteroids.

### A2. Conflicts between the sources and how they are resolved

| # | Conflict | Resolution |
|---|---|---|
| C1 | P1 32v32, P2 "all 64 players" vs new 13v13 | **13v13**: 12 field pilots + 1 Admiral per team. |
| C2 | P1 capture zones; P2 drone mining | Drones mine; no capture. "Node ownership" = which side has turrets built there (ring colour). |
| C3 | P2 removed admiral turrets; new: turrets back at nodes | Turrets at nodes: middle nodes PD only; inner nodes PD or torpedo. |
| C4 | P1 extractors / P2 drones / new "no extractors" | Mining drones only. No extractors of any kind. |
| C5 | P1 pilot mining of hardpoints | Removed (new). Hardpoints exist only as ore rocks for drones. |
| C6 | P1 pilot logistics (repair drones, personal extractor, node marker) | Only repair kits remain, as inventory items (LoL potions). Kit deploys the same repair drone type as bays (weaker, short, destroyable). |
| C7 | P1 repair bays at captured nodes | Bays are spawned at the mothership by the Admiral, fly to a chosen spot, then anchor permanently. Small enough for the jungle. |
| C8 | P1 mothership weaker after big spends / launch waves | Replaced: weaker when many PLAYER respawns happen quickly ("respawn strain"). |
| C9 | P1 win by score or majority hold | Removed: only mothership destruction ends the match. |
| C10 | P1 dynamic events | Removed (new). |
| C11 | P1 retreat phase vs "only destruction ends the match" + movable mothership | **Unclear → tested.** Variants: `none`, `systems_failure` (one-time 45 s blackout at 35% hull: no buying/respawn there, guns at 50%, still targetable), `jump` (v1-style 40 s untargetable withdrawal). **Tested 2026-10-14 → `systems_failure` kept.** Full 50-min AI matches (same build): systems_failure ended at 32:32; none ran out the clock with one mothership stuck at 4%; jump ran out the clock (64 turrets destroyed, no ending). End-game scenario (tests/endgame.gd, 2 runs each): systems_failure lost both quickly; none lost one, held one; jump held one for 20 min at 26%, lost one. Jump turns won games into stalemates; none lets a crippled mothership linger; systems_failure gives a dramatic last stand that still lets the winner finish. (2026-10-15: `jump` was taken out of the code; `none` stays for tests.) |
| C12 | P1 "5–7 nodes" vs 3 lanes with inner + middle nodes | **Unclear → tested.** Variant `nodes_9` (inner + middle node on every lane) vs `nodes_7` (side lanes have no middle node). **Tested 2026-10-14 → `nodes_9` kept:** 30-min AI matches: nodes_9 had 20 turrets destroyed vs 15, similar tech pace (frigates ~11 min) and cost; it gives every lane a middle objective and matches the requirement's plural "resource nodes in the middle of the map". (2026-10-15: `nodes_7` was taken out of the code.) |
| C13 | "wave of 10" per lane or per wave? | **Unclear → tested.** Default `per_lane` (10 per lane per wave, 30 per side per wave); variant `split` (10 total split 4/2/4... per wave). **Tested 2026-10-14 → `per_lane` kept:** split averaged 48 minions alive (vs 144) and 4.0 ms/tick (vs 5.8), but only 7 turrets fell in 30 min (vs 20) and turrets killed 19 pilots (vs 6): with 3-4 minions per lane nothing tanks turrets and pushes die, the opposite of the requirement's push-your-wave-into-turrets loop. (2026-10-15: `split` was taken out of the code.) |
| C14 | "6 item slots: flight suit, helmet, stick, cockpit layout, chair, implant" vs repair kits "take up an item slot" | 6 generic inventory slots; each gear item has one of the 6 categories and you can own at most one per category; repair-kit stacks (up to 3 per slot) also use slots. So a full gear build leaves no room for kits — the LoL trade-off. |
| C15 | P1 Admiral can fly a ship | Kept. While flying, the Admiral keeps the command UI and free camera, but cannot move the mothership (must be docked). |
| C16 | P1 waypoints with benefits | Kept: ships inside the waypoint ring get +8% speed, +25% shield regen, +15% vision. One active waypoint, lasts 75 s. |
| C17 | P1 "Use CharacterBody2D or kinematic" | Pilot ships are CharacterBody2D using move_and_slide (asteroid collisions, forgiving damage). Light units (minions, drones, wards, bays in flight) use custom kinematics for performance. |
| C18 | P1 modules (CS-style per ship) + new pilot items | Both: ship modules (2 per ship, lost when the ship dies, swappable at mothership or a repair bay) and pilot gear (6 slots, persists through death). |
| C19 | "mothership can be moved by a docked admiral from 20:00" — how should the AI admiral use it? | Humans can always move it. AI variants (`ai_ms`): advance (up the push/siege lane when at least even; since 2026-10-16 always up the mid lane), siege (only up its own siege lane, home otherwise), home (never). **Decided: advance.** Full 60-minute AI matches, 2 per variant: advance ended both (43:49, 47:48), siege 1 of 2, home 0 of 2. (2026-10-15: `siege` and `home` were taken out of the code, and with them the `ai_ms` switch. 2026-10-16: the advance lane is now always the mid lane, also during a siege. Following the push or siege lane parked the two motherships on different lanes, top against bottom some 30,000 units apart, and no 30-minute AI match ended; parked on the shortest lane they meet, and two test matches ended after about 24 and 25 minutes. That was on the AI before the pass 1-3 fixes; with them, 0 of 3 normal 30-minute AI matches ended, see docs/AI_DEEP_DIVE.md.) |
| C20 | Project name and world: the project (repo) was still called Fleet Command 2, and the world had no name. | **Decided by the user, 2026-10-16:** "Lets change the project name to Halcyon Drift, which we shall say is the name of the asteroid belt we are fighting in." So Halcyon Drift is both the project and the asteroid belt the battle is fought in; the lanes, nodes and jungle are inside it. Nothing else about the belt is decided. Unchanged on purpose: "Fleet Command" as the late-game admiral module (A13), the team names Halcyon and Cinder (open question in A16, answered in C21), folder and repo names, and the user's verbatim documents. Text-only change; no game logic touched. |
| C21 | Team name: the good-guy team (team 0, amber) was called Halcyon, the same word as the Halcyon Drift (the open question in A16). | **Decided by the user, 2026-10-16:** rename the team to **Aurelian**, the user's own pick for an uncommon good-guy name. Cinder (team 1, red) keeps its name, and Halcyon Drift stays the name of the project and of the asteroid belt. Aurelian is the name in all player-facing text, docs and comments. Done as a split between what the player sees and the internal label: `Rules.TEAM_DISPLAY` holds the player-facing names, and `Rules.display_label()` swaps the label in text that was built from an internal one (the place names "Halcyon Top/Mid/Bottom", the end screen's reason). `Rules.TEAM_NAMES` stays the internal label "Halcyon", together with `Rules.HALCYON`, the scene node names (and the node names themselves), logs, JSON, test output and the tools, so every past research log and baseline stays comparable (docs/CODE_GUIDE.md, "Team names"). Unchanged on purpose: the user's verbatim documents and older log entries. Display only: no game logic touched. |
| C22 | Fleet Command limit: the requirements file says the late-game module limits friendly minions to 30 (`USER_REQUIREMENTS_2026-10-13.md`); both v0.2.0 rule sets use 60. | **Decided by the user, 2026-10-17:** "Make 60 the requirement." The Fleet Command limit is now **60** (it was 30). Both rule sets, "Within requirements" and "Council's pick", use 60, so they stay within the amended requirements. The standard rules keep v0.1.0's 30 in v0.2.0, because v0.2.0 promises that the default game is unchanged (`fleet_cap` defaults to "30"). Any limit other than 60 is a requirement change (REQ-CHANGE). The user's verbatim requirements file is not edited: this row is the amendment. |
| C23 | Team 1 display name: the enemy team (team 1, red) was called Cinder. | **Decided by the user, 2026-10-17:** the enemy team's display name changes from Cinder to **Vhorr**, everywhere, like Aurelian (C21). Vhorr is the name in all player-facing text, docs and comments. Done with the same split as C21: `Rules.TEAM_DISPLAY` holds the player-facing names, and `Rules.display_label()` swaps the internal label in text that was built from one (the place names "Cinder Top/Mid/Bottom", the match-over reason). `Rules.TEAM_NAMES` stays the internal label "Cinder", together with `Rules.CINDER`, `Palette.CINDER`, `Roster.CINDER`, the scene node names, logs, JSON, test output and the tools, so every past research log and baseline stays comparable (docs/CODE_GUIDE.md, "Team names"). Unchanged on purpose: the user's verbatim documents and older log entries (C20, C21, A16 and the PROGRESS entries before 2026-10-17 still say Cinder). Display only: no game logic touched. |
| C24 | AI opening: how the computer pilots play the first minutes. The user's report: "Ive noticed that AI player ships at the start of the game do not immediately head out to contest the center map points, and instead hover around the left map points and wait for the minions to spawn. Even then, many of the AI player ships head back to the mothership to shop before returning to escort the minions to the middle of the map. This is an incorrect behavior. The AI player ships should stay near the mothership for the first 10 seconds of the match to allow the human player to get their bearings, then head to the middle map points to contest them, even before the minions spawn or reach the middle of the map points themselves." | **Decided by the user, 2026-10-17** (ships as v0.2.1): the text above is the requirement, plus the user's answer on the junglers: "Middle first, then camps". Done in the AI layer only (`Rules.AI_OPENING_HOLD` = 10 s, `Rules.AI_OPENING_MAX` = 180 s, `PilotGoals.opening_active()` and `opening_goal()`, `PilotShopping.wants_shopping()`; see A14). The "middle map points" are the three Crossing nodes on the centre line; every AI pilot of both teams contests the one on its lane, the junglers contest the middle one, and the flex pilot the top one (C25). The opening ends per lane when the team's first minion wave reaches that Crossing, and then the junglers peel off to their camps. No trips home to shop in the opening. A human admiral's waypoint (not the AI admiral's own: C25), a siege, a defend call and a test's hold point still win. The simulation core, the win condition and all other rules are unchanged, and the human pilot is unaffected. |
| C25 | The Crossing turrets and the flex pilot, after the opening fix. The user's answers to the questions of C24, 2026-10-17: "Yes, that is what i want. These middle of the map lane turrets should be priority for the Admiral to build as they help secure map control. If the AI pilots do not try and contest the zone it cannot be captured so the Admiral cannot build a turret there." (The early fight at the Crossings stays as built.) On the Admiral: "Only reorder the extras for now. However it should be made more obvious to both teams that a point is being contested, more obvious as to how long a point needs to be uncontested before it can be build on, and give more opportunity for counterplay." On the flex pilot: "Start rotation on a side lane". A third round of questions, 2026-10-18, after an independent review of the opening fix. On the AI admiral's own waypoint (it goes up at 60 s in every AI match and pulled the waypoint seats 4, 5, 6 and the flex pilot off their Crossings until the waves arrived): "Only a human admiral's". On where each admiral builds its first Crossing turret (the first allowed one in map order gave the Top Crossing to whichever team had the money first: Aurelian took it in 6 of 6 test matches): "Where its ships are". | **Decided by the user, 2026-10-17** (ships as v0.2.1). The code has no capture step: a Crossing is held by whoever has a live turret there, and the build check only needs no enemy turret there, a free slot, no rebuild lock and no enemy ship or minion within 1,500 (ResourceNode.build_blocker). So (1) AdmiralBuilder.more_turrets() now picks the Crossing turret (one PD per Crossing, 750 credits) before the extra turrets at the inner nodes (it was after them); nothing else about turrets changed. (2) The flex pilot's 90-second lane rotation now starts on the top lane (PilotGoals.FLEX_ROTATION_SHIFT = 2): top, mid, bot, then top again, for the whole match; before it was mid, bot, top. Both teams use the same lane, which keeps the two sides symmetric when the map is mirrored left to right. In the opening it stays on the top Crossing. (3) NOT built, kept for a later design item: making it clearer to both teams that a point is contested, how long a point must stay uncontested before it can be built on, and more counterplay. **Third round (decided by the user, 2026-10-18; ships in the same v0.2.1):** (4) In the opening, seats 4, 5, 6 and the flex pilot follow a waypoint only when a human admiral placed it (TeamState.waypoint_by_human, set through the new by_human argument of AdmiralCommand.set_waypoint: the command overlay passes true, the AI admiral false); the AI admiral's own waypoint no longer pulls them off their Crossings. Outside the opening nothing changes: from 10:00 any waypoint rallies them, and a human admiral's waypoint still wins over the opening. (5) The admiral's first Crossing turret goes to the allowed Crossing (no turret of its own there, build check passes) with the most of its own pilots and minions within 1,500 of it (the same disc as the build check's "enemy ships too close"; AdmiralBuilder._crossings_in_order()). A tie keeps the map order (Top, Middle, Bottom), and so does a Crossing choice with none of its ships near any allowed Crossing. Once the team holds a Crossing, the later Crossing turrets and the extra turrets at home follow (1) unchanged. (6) Two fixes from the review, not asked about: the first wave's arrival at a Crossing is noted once per team and lane (TeamState.first_wave_at), so a pilot that was dead, docked or away at that moment can no longer start a second opening when that wave dies; and a jungler in the opening falls back when hurt and outnumbered, as a lane pilot does (it did not before). |

### A3. Roles and the core loop

**Start screen.** The human picks once:
- **Command as Admiral** — plays Aurelian's Admiral (command UI, free
  camera; can also launch a ship). 12 AI pilots fly for Aurelian.
- **Fly as a Pilot** — joins Aurelian as one of the 12 field pilots. The
  Aurelian Admiral is AI. The choice is locked for the match.
Vhorr is always 12 AI pilots + an AI Admiral.

**Pilot loop.** Spawn docked at the mothership → Hangar (CS-style): buy a
ship (Scout free), up to 2 ship modules, pilot gear, repair kits → launch →
go to your lane / jungle → last-hit minions, duel, take turrets, kill
monsters, escort pushes → return to the mothership to shop (or swap modules
at a repair bay) → repeat. Death destroys the ship and its modules (pilot
gear and remaining kits are kept); respawn after a timer, docked (6 s +
0.6 s per match minute, max 35 s: late deaths open push windows).

**Admiral loop.** Spend the team treasury: mining drones, facilities and
research (HW2 tree), turrets at nodes, repair bays, wards, mothership
upgrades, team upgrades, waypoint, late-game direct minion control, and
(after 20:00, docked) moving the mothership.

### A4. Map

Theater 40,000 × 26,000 world units, mirror-symmetric about x = 20,000
(Aurelian left, amber; Vhorr right, red). Coordinates below are Aurelian's
(H = its mothership, short for the internal label Halcyon; C = Vhorr's, short
for the internal label Cinder);
Vhorr mirrors x → 40,000 − x.

- **Motherships:** H at (3,600, 13,000) facing +x. Base clearing radius
  6,000 (no asteroids).
- **Lanes** (polylines, corridor half-width 1,800, no asteroids inside):
  - Mid: (3,600, 13,000) → (20,000, 11,700) → (36,400, 13,000), passing
    north of the centre node.
  - Top: H → (8,200, 3,800) → (31,800, 3,800) → C.
  - Bot: H → (8,200, 22,200) → (31,800, 22,200) → C.
  - Connector (the perpendicular lane): x = 20,000 from (20,000, 3,800)
    to (20,000, 22,200), half-width 1,600.
- **Jungle:** four quadrants between the lanes (TL, BL Aurelian side; TR, BR
  Vhorr side), each ≈ 9,600 × 5,400, densely packed with asteroids
  (radius 70–260). Inside: winding paths 220–320 wide joining clearings
  (radius 650) for monster camps. Every entrance from a lane or base is a
  choke 82–90 units wide between rocks, so only small ships (collision
  radius ≤ 17) fit; corvettes and larger (radius ≥ 44) cannot enter. Each
  quadrant has 4–5 entrances (two per adjacent lane, one at the base side,
  one at the connector).
- **Border:** a rim of large asteroids outside the lane corridors.
- **Resource nodes** (indestructible ore clusters with 4–6 ore rocks for
  drones, radius ~650, sit at a lane edge so the lane passes within turret
  range):
  - Inner (near each mothership): top (10,800, 2,500), mid (11,500, 14,300),
    bot (10,800, 23,500). Ore value 1.0. Turret slots 3, PD or torpedo.
  - Middle: top (20,000, 2,500), centre (20,000, 13,000) (ore 1.6 — the
    high-value, high-risk node), bot (20,000, 23,500). Ore value 1.3.
    Slots 2 (centre 3). PD only. Either side may build if no enemy
    turret stands there and no enemy ship is within 1,500.
- **Route graph:** lanes + jungle paths + base points; edges tagged
  `small_only` inside the jungle. Used by AI pilots, drones, bays, wards.
- **Fog of war:** team vision on a 200-unit grid; asteroids (and node
  rocks) block line of sight. Units within 350 of a friendly are always
  visible. Enemy structures, once seen, stay drawn as last-known ghosts.

Travel-time targets: Fighter crosses mid lane (~33k) in ~55 s; Bomber
~85 s; Flak Frigate ~2:15; Destroyer ~3:10; minion waves meet near the
middle ~55 s after spawning.

### A5. Ships

Size classes: SMALL (strike craft, jungle-capable), MEDIUM (corvettes),
LARGE (frigates), CAPITAL. Structures and the mothership are their own
classes for damage tables.

| id | Name | Size | Price | Unlock | Hull | Shield | Energy | Max spd | Turn | Role |
|---|---|---|---|---|---|---|---|---|---|---|
| scout | Scout | S | 0 | start | 70 | 120 | 100 | 720 | 3.6 | Vision, wards hunting, Ping |
| fighter | Fighter | S | 150 | start | 100 | 200 | 100 | 640 | 3.2 | Dogfighter, +25% vs small |
| lance | Lance Fighter | S | 300 | Lance Beams | 110 | 220 | 120 | 600 | 2.9 | Beam, strong vs corvettes |
| bomber | Bomber | S | 350 | Fusion Bombs | 170 | 240 | 120 | 400 | 1.15 | Torpedoes vs large/turrets |
| logistics | Logistics Corvette | M | 500 | Corvette Facility | 380 | 420 | 150 | 350 | 1.55 | 2 repair drones, structure repair |
| support | Support Corvette | M | 550 | Command Systems | 300 | 500 | 180 | 430 | 1.9 | Vision, aura, paint, Jam |
| flak | Flak Frigate | L | 1100 | Frigate Facility | 1000 | 900 | 200 | 250 | 0.78 | Flak turret + 2 PD, anchor |
| ion | Ion Frigate | L | 1250 | Ion Cannons | 850 | 1000 | 220 | 260 | 0.85 | Forward ion beam vs large/turrets |
| destroyer | Destroyer | C | 2200 | Destroyer Chassis | 2400 | 1800 | 300 | 175 | 0.45 | 2 heavy cannon turrets, 3 PD, flak; cuts asteroids |
| battlecruiser | Battlecruiser | C | 3800 | Battlecruiser Chassis | 4200 | 3000 | 400 | 150 | 0.32 | 2 ion turrets, heavy cannon, 4 PD, 2 flak |

Full flight stats (accel, reverse, strafe, turn bleed, assist, boost,
vision, radius, length), weapons and specials are in
`scripts/data/ships.gd` / `weapons.gd`.

**Weapon mounts.** Small ships: fixed forward guns (aim = flight). Corvettes:
turrets with limited arcs. Frigates/capitals: main batteries are turrets
that track the mouse reticle within their arcs, so hull facing (shields) and
aim are decoupled; plus AUTO mounts (flak, PD) that pick their own targets —
this is how a well-positioned big ship "racks up kills with flak and PD".

**Weapon kinds and damage table** (multiplier by target class):

| kind | small | medium | large | capital | structure | mothership | torpedo | asteroid |
|---|---|---|---|---|---|---|---|---|
| bolt | 1.0 | 0.85 | 0.6 | 0.45 | 0.5 | 0.4 | 0.6 | 0 |
| lance (beam) | 0.8 | 1.4 | 0.9 | 0.7 | 0.6 | 0.5 | 0 | 0 |
| torp | 0.35 | 1.0 | 1.6 | 1.8 | 2.2 | 2.0 | – | 0 |
| flak | 1.4 | 0.9 | 0.25 | 0.2 | 0.3 | 0.3 | 1.5 | 0 |
| pd | 1.0 | 0.5 | 0.1 | 0.05 | 0.2 | 0.1 | 1.0 | 0 |
| shell | 0.5 | 1.0 | 1.3 | 1.4 | 1.8 | 1.5 | 0 | 1.0 |
| ion (beam) | 0.4 | 0.9 | 1.5 | 1.6 | 1.6 | 1.5 | 0 | 0.6 (capital mounts only) |

Torpedoes are projectiles with hit points (bomber 24, minion 12, turret 40):
PD, flak and bolts can shoot them down. Tuned in the arena tests
(2026-10-14): at x3 one PD hit killed a torpedo and big ships were immune to
bombers; now one PD-armed frigate stops a lone bomber but two get through. The Fighter's cannons get +25% vs SMALL. Mothership takes extra
multipliers by attacker size: small ×0.3, medium ×0.8, large ×2.0, capital
×2.0, minions ×0.5 ("weak to large ships"; tuned by tests/ms_duel.gd).
Pilot ships take ×0.6 from minions (playtest: minions were the top killer
of pilots; pilots should die mostly to pilots).

**Shields (4 zones).** Each ship has a total shield capacity split into
front/rear/left/right zones by its focus mode:

| focus | front | rear | left | right |
|---|---|---|---|---|
| balanced | .25 | .25 | .25 | .25 |
| front | .50 | .10 | .20 | .20 |
| rear | .10 | .50 | .20 | .20 |
| left | .20 | .20 | .50 | .10 |
| right | .20 | .20 | .10 | .50 |

A hit picks the zone from the direction it came from relative to the hull's
facing. Damage hits that zone's shield first (after shield resistance), the
overflow hits the hull (after hull resistance). Changing focus moves the
current shield total into the new proportions. Focus cooldown by size:
S 1.0 s, M 2.0 s, L 3.5 s, C 5.0 s. Shields regenerate after a delay with no
damage taken (S 3.5 s, M 5 s, L 6 s, C 8 s). Controls: arrow keys
(↑ front, ↓ rear, ← left, → right; press the active one again for balanced).

**Energy routing.** One capacitor (energy pool) recharges continuously;
weapons (per shot / per second for beams), boost and specials draw from it.
Routing presets (keys 1–4):

| mode | weapons (fire rate) | shields (regen, resist) | thrusters (accel/speed/turn, boost cost) |
|---|---|---|---|
| 1 Weapons | ×1.25 | regen ×0.6 | ×0.92 |
| 2 Shields | ×0.85 | regen ×2.0, +15% resist | ×0.92 |
| 3 Thrusters | ×0.85 | regen ×0.6 | accel/speed ×1.12, turn ×1.08, boost cost ×0.6 |
| 4 Balanced | ×1 | ×1 | ×1 |

Routing cooldown by size: S 1.5 s, M 3 s, L 5 s, C 7 s.

**Flight model.** v1's Newtonian-lite model (`LESSONS_FROM_V1.md`): per-class
accel/reverse/strafe/max speed/turn, turn bleed at speed, flight assist (V)
that damps sideways drift only while not strafing (weaker on agile ships),
soft speed cap that main thrust cannot exceed, boost and strafe can briefly
exceed it, velocity arrow, thruster particles. Asteroid collisions bump
(move_and_slide) and deal forgiving damage: none below 180 u/s impact speed,
then (impact − 180) × 0.12 × size factor to hull (shields absorb first).

**Specials** (G or right mouse): Scout Ping (reveal radius 4,500 through
asteroids for 3 s; +EMP with Scout EMP research), Fighter Snap Turn,
Lance Overload, Bomber Focus Shot, Logistics Emergency Repair pulse,
Support Jam, Flak Brace, Ion Capacitor Dump, Destroyer Overcharge,
Battlecruiser Broadside. Costs energy, has a cooldown.

**Ship modules** (2 per ship; price scales with size S×1, M×1.6, L×2.5,
C×4): Plating, Engines, Weapons, Shield Booster, Capacitor, Boost Cell,
PD Module (medium+), Sensor Suite. Lost when the ship dies. Swappable while
docked or inside a friendly repair bay's radius.

**Ace streak.** 3 kills without dying → Ace for 25 s: +12% damage, +8% speed,
refreshes on each kill; killing an Ace pays a shutdown bonus.

### A6. Pilot gear (items)

6 inventory slots. Categories: Flight Suit, Helmet, Stick, Cockpit Layout,
Chair, Implant — max one per category. Repair-kit stacks (3 per slot) share
the slots. Gear persists through death; sells back for 50% at the mothership.
Each category offers 4 choices aimed at different ship styles. The full list
with stats and prices is in `scripts/data/items.gd`. Stats available:
`hull_pct, hull_resist, shield_pct, shield_resist, shield_regen_pct,
shield_delay, energy_pct, energy_regen_pct, fire_rate_pct, damage_pct,
turn_pct, accel_pct, speed_pct, strafe_pct, boost_pct, vision_pct,
income, redirect_cd_pct, special_cd_pct, collision_resist, repair_recv_pct,
respawn_pct, bounty_pct`.

**Repair kit** (60 cr): R deploys a repair drone from your ship that heals
your hull for 10 s (S 5/s, M 8/s, L 10/s, C 12/s). The drone has 25 HP and
can be shot down.

### A7. Economy

- Start: pilot credits 700; treasury 1,500; 4 mining drones.
- **Mining drones** (Admiral, 200 each, max 14; was 18, late treasuries
  overflowed to 30-50k): fly from the mothership to a
  node, cut ore (40/s, carry 300), fly home; ore pays ONLY on delivery: 60%
  to the treasury, 40% split equally among living field pilots (and the
  human Admiral). +20% escort bonus split among friendly pilots within
  1,100 of the drone on its trip. Comeback floor: free drone every 20 s when
  a side has fewer than 3; mothership skims 3 treasury/s.
- **Passive pilot income:** 1.5 cr/s (alive or dead).
- **Kills:** 100 + 12% of the victim's ship+modules value; assists split 50%
  of that among other attackers with ≥10% of damage in the last 15 s.
- **Minion last hits:** fighter 14, bomber 18, corvette 45 (+5% per 5 min).
- **Turret destroyed:** 350 split among attackers who damaged it in the last
  15 s, +400 to their treasury.
- **Jungle camps:** small 110, medium 200, split by damage (≥10%), last hit
  +25%.
- **Other bounties:** mining drone 35, ward 30, repair drone 10, repair bay
  200 (+250 treasury).

### A8. Minions

Waves every 35 s from 0:45. Per lane: 5 Fighters, 4 Bombers, 1 Escort
Corvette. They spawn at their
mothership's launch bay, join their lane and advance in formation at the
corvette's speed; they engage enemies inside aggro range and resume.

| minion | hull | shield | speed | weapon | notes |
|---|---|---|---|---|---|
| fighter | 55 | 30 | 480 | bolt 3/s × 4 dmg, range 600 | low skill aim (±6°) |
| bomber | 85 | 30 | 360 | torp 0.4/s × 28, range 1,000 | prefers turrets, large ships, corvette minions |
| escort corvette | 480 | 160 | 280 | cannon 1/s × 16, range 1,250; 1 PD | the "cannon minion" |

Minions do ×0.35 damage to turrets and ×0.5 to the mothership. +7% hull and
damage every 5 min. Minion aggro (as built, LoL-like): an enemy ship that is
attacking one of our ships nearby > nearest enemy minion > enemy structure in
range > nearest enemy ship. Pilot ships take x0.6 from minions; minions take
x1.8 from minions (fast wave clashes).

**Fleet Command module** (late): free waves stop; the Admiral buys minions
(fighter 35, bomber 50, corvette 140), at most 30 alive in the standard
rules, and orders them (lane / attack-move point / hold). The limit is one
rule for both teams and for a human or AI Admiral; the `fleet_cap` variant
changes it. Both rule sets, "Within requirements" and "Council's pick", use
60, which has been the requirement since the user's decision of 2026-10-17
(C22 in A2; the standard rules keep v0.1.0's 30), and the board's texts show
the limit of the match.

### A9. Turrets (Admiral, at node slots)

| turret | where | cost / build | hull | weapon | range |
|---|---|---|---|---|---|
| PD Turret | any node | 450 / 25 s | 2,500 (+600 shield) | point defense 6/s × 9 (anti-strike-craft; PD barely scratches frigates and capitals, so big ships take middle nodes), intercepts torpedoes | 1,500 |
| Torpedo Turret | inner nodes only (needs Platform Missiles) | 750 / 35 s | 3,000 (+700 shield) | torpedo 0.45/s × 110 | 2,300 |

- **Node disruption:** when a turret dies, nothing can be built at that node
  for 60 s (rich admirals otherwise rebuilt every lost turret at once).
- **Backdoor protection:** if no attacking-team minion is within 1,800 of the
  turret, damage from players is ×0.3. Minions make turrets killable.
- **Aggro (LoL rule):** an enemy ship that damages one of our SHIPS inside
  the turret's range becomes top priority for 3 s; otherwise nearest enemy
  minion; otherwise nearest enemy in range (ships, then structures).
  Consecutive shots on the same ship ramp damage +20% each (max +100%).
- A visible red tether line shows who a turret is targeting.

### A10. Jungle monsters

12 camps (3 per quadrant): 2 small "Derelict Gunship" (hull 900, 2 auto
turrets 2/s × 8, range 900; respawn 80 s) and 1 medium "Derelict Carrier"
(hull 1,600, 1 turret, launches snub fighters 2 at a time every 12 s while
engaged; respawn 120 s). Monsters are neutral, attack anything that
attacks them or comes within 700, and reset/heal when attackers leave a
2,500 leash.

### A11. Repair bays, repair drones, wards

- **Repair bay** (needs Repair Bays research; 450; max 3 per team): spawns at
  the mothership, flies (380 u/s, route graph, jungle OK) to the point the
  Admiral chose, then anchors forever. Hull 600, radius 40. Sends repair
  drones to damaged friendly ships within 1,400. Drones per bay: 1, +1 per
  Repair Drones II/III/IV research (max 4). Drones per target by size: S 1,
  M 2, L 3, C 4. Heal per drone (hull/s): S 8, M 14, L 18, C 22. Drones have
  40 HP, can be shot down; the bay rebuilds one every 15 s. The bay stops
  repairing for 5 s whenever its HULL takes damage. Bay Defenses research
  adds a 400-point shield and a PD mount; while only the shield is hit,
  repair continues. Ship modules can be swapped inside a bay's radius.
- **Ward** (75; max 6; oldest expires when exceeded): Admiral picks any point
  currently in friendly vision; a ward drone flies there from the mothership
  (900 u/s) and anchors forever. Vision radius 1,400 (blocked by
  asteroids). Hull 25. Stealthy: enemies see it only within 500 or via Scout
  Ping.

### A12. Mothership

- Hull 16,000 (10% resist); shield 6,000 as ONE pool (a hull this big
  can't have a zone starved); regen 40/s after 10 s; PD ×6 (range 1,600,
  so it reaches past its own 1,600-long hull); 2 light cannon turrets.
- Weak to large ships: damage TO the mothership is multiplied by attacker
  size (strike craft ×0.3, corvettes ×0.8, frigates and capitals ×2.0),
  and point defense barely scratches big hulls (PD vs large ×0.1).
- Tuned with tests/ms_duel.gd (2026-10-13, the "barely" requirement):
  fully upgraded vs 2 ion + 2 flak frigates → wins with ~28% HP left;
  vs 3 ion → wins with ~24%; vs 3 frigates + a destroyer → loses;
  base vs 3 frigates → loses (kills 1-2); base vs 8 fighters + 4 bombers →
  wins without hull damage (PD 6/s × 8.5; it shoots close torpedoes first,
  otherwise the strike craft launching them). Re-tuned 2026-10-14 after the
  beam fixes (beams always connect and honour energy routing). (The first draft had 60,000 hull + 16,000
  shields and ~1,000 anti-ship dps when upgraded: it deleted 3 frigates in
  20 s, so "barely" was impossible; the fix is a smaller pool, a strong
  big-ship multiplier and modest anti-ship guns.)
- **Respawn strain:** 4+ player respawns within 30 s → 20 s strain: guns
  ×0.6, no shield regen. More respawns extend it.
- **Upgrades** (Flagship column): Hull Reinforcement I–III, Shield
  Generator I–II, PD Grid II, Flak Batteries, Heavy Batteries I–II, Ion
  Lance. Fully upgraded it beats 4 frigates at once, barely (see above),
  and is by far the strongest ship against everything except big hulls.
- **Movement:** from 20:00, a DOCKED Admiral (not flying their own ship) can
  order the mothership to a point (80 u/s, open space only). Spawns,
  minion launches and docking follow it.
- Retreat variant per C11.

### A13. Tech tree (HW2-style)

Facilities are modules built onto the mothership (one at a time, 2 can be
queued). Research needs the Research Module plus the column's facility (up to
3 queued). Full costs/times in `scripts/data/tech.gd`.

- **Fighter Facility** (start): Scout, Fighter. Research: Fusion Bombs →
  Bomber; Lance Beams → Lance Fighter; Scout EMP; Improved Bombs; Fighter
  Drive 1/2.
- **Research Module** (400, 20 s).
- **Corvette Chassis** (research) → **Corvette Facility** (module) →
  Logistics Corvette; Command Systems → Support Corvette; Corvette Drive
  1/2; Corvette Armor 1/2.
- **Frigate Chassis** (research, needs Corvette Chassis) → **Frigate
  Facility** → Flak Frigate; Ion Cannons → Ion Frigate; Frigate Drive/Armor.
- **Capital Ship Facility** (needs Frigate Facility) → Destroyer Chassis →
  Destroyer; Battlecruiser Chassis → Battlecruiser; Capital Drive/Armor.
- **Platform Control Module** → Platform Missiles (torpedo turrets),
  Platform Armor 1/2. (PD turrets need nothing.)
- **Advanced Sensors Array** → +20% vision team-wide; Fire Control (+8%
  weapon range); Ward upgrades.
- **Hyperspace Module** → pilots can launch straight to any friendly repair
  bay (6 s spool).
- **Utility** (Research Module): Repair Bays; Repair Drones II–IV; Bay
  Defenses; Drone Armor 1/2; Improved Mining; Pilot Stipend (team starting
  money: +250 credits per respawn).
- **Flagship** column: mothership upgrades (A12).
- **Fleet Command Module** (needs Capital Ship Facility): direct minion
  control (A8).

Pacing target in AI matches: bombers ~3–4 min, corvettes ~6–8, frigates
~10–12, destroyers ~16–20, battlecruiser 25+.

### A14. AI

- **Pilots (11–12 per side):** lane assignment top 3 / mid 3 / bot 3 /
  jungle 2 / flex 1. States: SHOP → TRAVEL (route graph) → LANE (hold behind
  the friendly wave front at a hull-appropriate distance; last-hit; trade
  when favourable; never tank enemy turrets without minions; push turrets
  when our minions tank) → RETREAT (low hull / outnumbered / turret aggro;
  repair kit; go to bay or home) → JUNGLE (clear camps, gank pushed-up
  enemies) → DEFEND (turret or mothership under attack) → GROUP (late game,
  follow the waypoint). Big ships station behind the front with shields
  facing the threat and retreat when isolated. AI uses shield focus and
  energy routing. Skill varies per pilot (aim error, reaction, greed).
  **No idle orbiting:** stationary goals are held with a stop, not circled.
- **Getting unstuck (added 2026-10-20, v0.2.2):** AI ships used to end up
  pinned in the asteroids (about 28 stuck episodes and 700 s of rock contact
  a match in a 12-match study). A pilot's route now starts at the cheapest
  route-graph dot the ship can really fly to (a straight line clear of every
  rock by the ship's radius plus 6 units), not at the nearest dot; with no
  such dot the ship is in the rocks and plans an escape at once: a grid
  search for the nearest spot that sees a route dot (coarse cells first, then
  fine cells, so a narrow gap a ship really passes is not missed), after which
  the route goes on from that dot. A ship that makes no progress for 4 seconds
  (a small ship in a fight: pushes forward without moving for 3 seconds) is
  stalled. The first stall sends it back along its own track (a trail of up
  to 24 breadcrumbs, one every 50 units, dropped while the ship touches no
  rock) to the first spot where it can join the route graph again, and for 60
  seconds its routes go round the route dot it was flying to (another jungle
  gate, for example, when the first one pins it again and again); a second
  stall in the same place plans an escape. Small ships no longer take
  a target with a rock between them and the target, and with a hidden target
  more than 450 units away they follow the route to their goal instead of
  flying straight at it. Stalls in an open lane (slow turning and waiting
  frigates) are not touched.
- **The opening (added 2026-10-17, v0.2.1, C24):** for the first 10 seconds
  (`Rules.AI_OPENING_HOLD`) every AI pilot of both teams waits near its own
  mothership, so a human player can get their bearings. From 10 s each AI
  pilot flies to its lane's Crossing node (the three ore nodes on the
  centre line, x = 20000) and contests it, on its own side of the node and
  spread by seat, even before any minion has launched. Junglers contest
  the middle Crossing. The flex pilot contests the top Crossing: its
  90-second lane rotation (top, mid, bot, then top again) now starts on the
  top lane instead of the middle one, for the whole match, and it keeps the
  top Crossing until the opening ends (C25). Both teams use the same lane
  for it, so the two sides stay symmetric. The opening ends, per lane, when
  our first minion wave reaches that Crossing (or at
  `Rules.AI_OPENING_MAX`, 180 s, if it never does): the pilots then station
  behind the wave front as before, and the junglers go to their camps.
  The arrival is one fact for the whole team and lane (noted once, by
  whichever pilot sees it first), not a private matter of each pilot: a
  pilot that was dead, docked or flying home when the wave got there is
  done as soon as it flies again, and cannot start a second opening when
  that wave dies (C25). There are no trips home to shop in the opening
  (pilots shop before they launch); a retreat for low health still
  happens, and a pilot that is hurt and outnumbered falls back, junglers
  too. A waypoint a human admiral placed, a siege, a "defend the
  mothership" call and a test's hold point still win over the opening. The
  AI admiral's own waypoint (it goes up at 60 s in every match) does not:
  it does not pull the waypoint seats (4, 5, 6 and the flex pilot) off
  their Crossings (C25).
- **Minions:** low skill: follow lane, simple aggro, simple aim.
- **Admiral AI:** build plan through the tree, turrets at inner nodes
  first (one at each; then, with spare money, one PD turret at each middle
  node, the Crossings, before any extra turret at home: reordered
  2026-10-17, C25; the first Crossing turret goes to the Crossing where
  the admiral's own pilots and minions are, 2026-10-18, C25), drones to
  target count, bays behind contested lanes, wards at
  jungle entrances and the connector, waypoint on the lane being pushed,
  mothership upgrades mid/late (no Fleet Command: it starved AI pushes),
  mothership advance after 20:00 when at least even in fleet strength
  (always up the mid lane, also during a siege, so that both motherships
  park on the shortest lane and meet there).
- **Siege and defense (late game, added 2026-10-14 after AI-vs-AI matches
  ran 50 minutes without touching a mothership):** with 2+ healthy big
  ships and a power edge, the admiral declares a siege on the lane with the
  fewest enemy inner turrets (or, once the enemy mothership is parked more
  than 2,500 from home, on the lane it is parked on: the mid lane when the other admiral is an AI too): gather at 0.6 of the
  lane (until 2 big ships mass, max 45 s), then assault; in the assault big ships put their main
  guns on the mothership and let PD/flak handle defenders. A stalled
  assault regroups: < 15% hull damage in the 120 s after the first big
  ship gets within 3,000 of the hull, or nobody gets there in 300 s.
  All siege points are measured
  from where the enemy mothership is now (staging at least 7,000 short of
  it, assault rally 4,500 short); if it moves to another lane the siege
  follows. Siege participants don't fly home to shop mid-siege, and
  gear-only trips need the pilot within 9,000 of their own mothership. A human admiral declares one by
  placing the rally waypoint near the enemy mothership. Defense: a group
  of 2+ seen enemy big ships (the closest one plus any within 5,000 of it)
  past our inner nodes (within 7,000 of the hull; 4,000 once our
  mothership is parked more than 2,500 from home) calls that team's AI
  pilots to a point 1,500 on our side of them (strike craft from 12,000,
  big ships from 18,000) and blocks/cancels our own siege (while our siege
  is on, only a push within 2,500 of the hull does). Pressure on an
  inner turret is answered by that lane's pilots only. (A 14,000 trigger
  kept both teams "defending" most of the match, and sieges rarely
  started: 1 ending in 4 full 60-minute AI matches.)

### A15. UI

- **Start screen:** role choice (Admiral / Pilot) with one-line explanations
  and a clear "this choice is locked" note.
- **Pilot HUD:** top-centre clock + both motherships' hull bars + turret
  counts per lane; top-left credits, K/D/A; bottom-centre ship status:
  4-zone shield diamond, hull bar, energy bar, routing mode, shield focus,
  cooldowns (special, routing, focus), boost, speed; bottom-left 6 item
  slots (kit charges, R hint); bottom-right minimap with fog; right kill
  feed; centre banners. Turret aggro warning when a turret targets you.
- **Hangar** (B, docked; modules also in a bay): tabs Ships / Modules /
  Gear / Kits; locked items explain which research unlocks them.
- **Admiral board** (Tab): Research (HW2-style board), Build (drones,
  turrets per node, bays, wards), Mothership (upgrades, move), Fleet
  (waypoint, minion control). Map tools with click-to-place.
- **Scoreboard** (Tab for pilots), **How to play** (H), **End screen**.
- **Camera:** every seat has a free camera that stays where the player puts
  it, anywhere on the map: a screen edge or the middle-mouse drag pans, a
  minimap click jumps, and W/A/S/D pan only while the human is not flying
  (flying, they steer the ship). **Space** centers the camera on the ship (no
  ship, docked or dead: on the spot in front of the mothership); holding it
  keeps the camera centered while the ship moves, and letting go frees it
  again from where it is. A pilot's camera also jumps to the ship when it
  launches. Space is not a fire key any more (left mouse fires). Pilots:
  max zoom-out scales with ship size (visible width ≈ S 5,200, M 6,400,
  L 8,000, C 10,000), so a pilot pans a limited window over the whole map.
  Admiral and spectator: any zoom, the whole map. The Admiral's C key
  switches to a follow camera (glides after the ship, looks ahead, limited
  edge peek, a pilot's zoom limit) and back.
- Wording conventions from v1's clarity pass.

### A16. Open questions (user decisions)

No question is open now. Answered:

- **Team name (answered 2026-10-16).** The first team shared its name,
  Halcyon, with the Halcyon Drift: keep it (e.g. the belt's home fleet) or
  rename the team? **The user's answer: rename it to Aurelian**, the user's
  own pick for an uncommon good-guy name. Team 0 (amber) is Aurelian and
  team 1 (red) stays Cinder; see C21 in A2. The old name survives only as
  the internal label (see docs/CODE_GUIDE.md, "Team names").

---------------------------------------------------------------------------

## PART B — ARCHITECTURE

### B1. Principles

- One Godot project at `remake/`. Scenes for every entity type, map
  element and UI screen. GDScript only. Major systems carry header
  comments explaining how to extend them.
- **World is the clock.** `World._physics_process` runs systems in a fixed
  order each 60 Hz tick (B4). Entities do not have their own
  `_physics_process`; they expose `sim_update(dt)` etc. Visual-only code
  may use `_process`.
- **Data-driven.** Hulls, weapons, items, modules, minions, turrets, tech,
  map layout and rules live in `scripts/data/*.gd` as const dictionaries
  with static helpers.
- **One damage pipeline:** `Combat.apply_damage(target, info)` handles
  tables, zones, resistances, backdoor protection, assists and death.
- **Spatial hash** rebuilt every tick for all units; every proximity query
  goes through it.
- **Vision** is computed on a grid at 5 Hz per team, with asteroid
  occlusion (shadowcasting), and read by AI, targeting and rendering.
- **Controllers:** a ship is driven by a controller (`PlayerController`,
  `PilotAI`) that fills a `ShipControls` intent each tick. The human and the
  AI use the same ship code and rules.
- **Admiral actions** all go through `AdmiralCommand` (one API used by the
  human UI and the Admiral AI), which validates and spends treasury.
- **Headless-testable:** `Main` accepts options (`--all-ai`, `--seed`,
  `--variant`, `--max-minutes`, `--bot`, `--shots=`), and tests run with
  `--headless --fixed-fps 60`.

### B2. Folder layout

```
remake/
  project.godot, icon.svg, README.md
  docs/                      design, progress, requirements, lessons
  scenes/
    main.tscn                Main (root): World + UI layer
    world/world.tscn         World: Map, Units, Projectiles, Effects, Fog, CameraRig
    world/map.tscn           Map (asteroid fields, lanes, nodes) built by map.gd
    entities/*.tscn          ship, minion, mothership, turret, repair_bay,
                             repair_drone, mining_drone, ward, resource_node,
                             derelict, snub_fighter, asteroid_chunk (fx)
    ui/*.tscn                start_screen, hud, hangar, admiral_board,
                             scoreboard, help, end_screen, minimap
  scripts/
    autoload/                events.gd (signal bus), game.gd (match handle)
    core/                    util.gd, spatial_hash.gd, route_graph.gd,
                             mulberry.gd, stat_block.gd
    data/                    rules.gd, ships.gd, weapons.gd, modules.gd,
                             items.gd, tech.gd, minions.gd, structures.gd,
                             jungle.gd, map_layout.gd, palette.gd, roster.gd
    world/                   world.gd, map.gd, asteroid_field.gd, vision.gd,
                             projectiles.gd, combat.gd, effects.gd,
                             match_rules.gd, minion_director.gd,
                             jungle_director.gd, fog_view.gd
    entities/                unit.gd (base), ship.gd, shield_zones.gd,
                             energy.gd, weapon_mount.gd, minion.gd,
                             mothership.gd, turret.gd, repair_bay.gd,
                             repair_drone.gd, mining_drone.gd, ward.gd,
                             resource_node.gd, derelict.gd, snub_fighter.gd,
                             ship_visual.gd
    team/                    team_state.gd, pilot_profile.gd, economy.gd
    control/                 ship_controls.gd, player_controller.gd,
                             admiral_command.gd
    ai/                      pilot_ai.gd, admiral_ai.gd
    ui/                      ui_kit.gd + one script per screen
    camera/                  camera_rig.gd
    audio/                   sfx.gd
  tests/                     headless tests and harnesses
```

### B3. Core types (contract summary — exact signatures live in code)

- `Unit extends CharacterBody2D` — base for every combat entity: `uid`,
  `team` (0 Aurelian = `Rules.HALCYON`, 1 Vhorr = `Rules.CINDER`, 2 neutral), `kind`, `size_class`, `radius`,
  `hull`, `hull_max`, `hull_resist`, `shields: ShieldZones` (nullable),
  `vision_radius`, `alive`, `facing()`; `take_hit(info) -> void` (only
  called by Combat); `on_killed(info)`; damage log for assists;
  `visible_to(team) -> bool`.
- `DamageInfo` — amount, kind, source (Unit, nullable), source_team,
  source_size, from_pos, is_minion_source, flags.
- `Ship extends Unit` — hull def + modules + pilot profile → `stats`;
  `controls: ShipControls`; flight step; `ShieldZones`; `EnergyPool`;
  `mounts: Array[WeaponMount]`; special; docking state.
- `WeaponMount` — fixed / turret / auto; owns cooldown and fires through
  `Projectiles` or instant beams via `Combat`.
- `Projectiles` — pooled arrays; swept hits via the spatial hash;
  torpedoes are interceptable; flak bursts; draws itself in one node.
- `Vision` — per-team visibility grid; `is_visible(team, pos)`,
  `reveal(team, pos, r, secs)`.
- `RouteGraph` — `path(from, to, small_only) -> PackedVector2Array`.
- `TeamState` — treasury, facilities, research, unlocks, upgrades, drone
  count, structures, waypoint, strain, respawn log, admiral kind.
- `PilotProfile` — credits, items (6 slots), kills/deaths/assists,
  respawn timer, bounty, streak; aggregated item stats.
- `AdmiralCommand` — every admiral action (build facility, research,
  drone, turret at node slot, bay at point, ward at point, waypoint,
  mothership upgrade/move, fleet orders); returns "" or a reason string.

### B4. Tick order (World._physics_process, 60 Hz)

1. Match clock, director spawns (minion waves, jungle respawns).
2. Spatial hash rebuild.
3. Vision update (5 Hz, staggered by team).
4. Controllers: player input, AI think (staggered rates) → ShipControls.
5. Units `sim_update(dt)`: ships (flight + move_and_slide + collision
   damage + weapons + energy + shields), minions, drones, structures,
   monsters, mothership.
6. Ship-vs-ship separation (light shoves).
7. Projectiles update (movement, hits, flak bursts, torpedo interception).
8. Deaths/cleanup, economy deliveries, respawns, match end check.
9. Effects tick; UI refresh at 10 Hz via signals/polling.

Physics layers: 1 asteroids, 2 pilot ships, 3 structures (turrets, bays,
mothership hull proxy), 4 node rocks. Pilot ships mask 1|3|4.

### B5. Performance budget (UHD 630, 60 fps; ~26 pilots, ~120 minions,
~40 drones, ~30 monsters, ~25 structures, ~600 projectiles)

Sim ≤ 7 ms/tick: ships ~1.5 ms (move_and_slide ≈ 21 µs each, measured),
minions ~1.5 ms (custom kinematics, AI 4 Hz staggered), projectiles ~1.5 ms,
vision ≤ 1 ms amortised, rest ~1.5 ms. Render ≤ 6 ms: static asteroids
cached per chunk; units draw simple polygons; one draw node for projectiles.

### B6. Test harness

- `tests/run_match.gd` — headless all-AI match: `--seed`, `--variant`,
  `--max-minutes`, metrics CSV/JSON (match length, winner, tech timings,
  turret falls, kills by class, gold curves, frame cost), invariant checks.
- `tests/unit_checks.gd` — flight signs/caps, shield zone math, energy
  modes, item aggregation, tech prerequisites, turret aggro rule, map
  mirror/fairness, route graph reachability (small vs large).
- `tests/bot_player.gd` — drives the human slot through the real input
  path (InputEvents on UI and flight) through scripted scenarios.
- `--shots=<dir>` screenshot tour at several resolutions.

### B7. Module plan (parallel implementation)

Foundation (lead): autoloads, core, data, Unit/Ship/ShieldZones/Energy/
WeaponMount, Combat, Projectiles, SpatialHash, Vision, Map/AsteroidField/
RouteGraph, World loop, TeamState/PilotProfile/Economy, PlayerController,
CameraRig (basic), MatchRules (basic), minimal debug HUD, stubs for the rest.

Then agents, each owning disjoint files:

1. **Lanes & turrets:** minion.gd, minion_director.gd, turret.gd (+scenes).
2. **Jungle:** derelict.gd, snub_fighter.gd, jungle_director.gd.
3. **Support structures:** repair_bay.gd, repair_drone.gd, ward.gd,
   mining_drone.gd, resource_node.gd, mothership.gd (weapons, upgrades,
   strain, movement, retreat variants).
4. **Pilot AI:** pilot_ai.gd.
5. **Admiral:** admiral_command.gd, admiral_ai.gd, tech execution.
6. **UI:** all ui/*, fog_view.gd, camera_rig.gd polish, minimap.
7. **Tests:** tests/*.
8. **VFX/audio:** effects.gd, ship_visual.gd polish, sfx.gd.

Integration and playtest loops by the lead with review/playtest workflows.
