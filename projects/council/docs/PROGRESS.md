# Remake progress log

Read this first when resuming. Newest entries at the bottom.

## Request (2026-10-13, ~13:45)

The user asked to remake the game in Godot/GDScript from the original
prompts (docs/prompt1_original_brief.txt, docs/prompt2_amendments.txt),
using v1 (../godot) as reference, PLUS a long list of overriding
requirements captured verbatim in docs/USER_REQUIREMENTS_2026-10-13.md
(MOBA lanes, minions, jungle, shields with 4 zones, energy routing, pilot
items, mobile repair bays, turrets at nodes, wards, LOS fog, zoom lock,
13v13 with a chosen human/AI admiral, mothership-only win, movable
mothership at 20:00, ...). Where the resolution of a conflict is unclear,
the user wants multiple resolutions tested.

## Plan

1. DESIGN.md written by the lead (single author for coherence).
2. Foundation code written by the lead: data, core utils, Unit base,
   combat, weapons, projectiles, spatial hash, vision, map generation,
   world loop, ship flight/shields/energy, player controller, team state.
   Stub classes with documented APIs for everything else.
3. Parallel module implementation by workflow agents against the stubs.
4. Integration by the lead.
5. Playtest/fix loops (AI-vs-AI soaks, variant tests, bot-player input
   playtests, screenshot reviews) until dry.

## Log

- 13:45 Earlier design workflow (4 designers) died at the session limit
  before the new requirements arrived; its output is obsolete.
- DESIGN.md written by the lead (Part A rules/numbers, Part B architecture).
- Foundation written by the lead and RUNNING: data (rules, ships, weapons,
  modules, items, tech, minions, structures, jungle, map layout), core
  (util, mulberry, spatial hash, route graph, stat block, steer), world
  (World loop, MapBuilder/MapInfo, AsteroidField, Vision, Projectiles,
  Combat, Effects, MatchRules, MinionDirector, JungleDirector, MapDecor,
  FogView), entities (Unit, Ship, ShieldZones, EnergyPool, WeaponMount,
  RepairDrone, Mothership, ResourceNode, MiningDrone, Minion, Turret,
  RepairBay, Ward, Derelict, SnubFighter, ShipVisual, UnitVisual), team
  (TeamState, PilotProfile, Economy), control (ShipControls,
  PlayerController, AdmiralCommand), AI baselines (PilotAI, AdmiralAI),
  CameraRig, Main (start fallback, debug overlay, headless reports).
  All entity scenes + world.tscn + main.tscn exist. docs/API_INDEX.md is a
  generated index of public functions.
- Headless 8-min all-AI match: 0 errors. Research Module 1:06, Bombers 2:00,
  corvettes ~5:00. 28 pilot kills by 8:00. No turret fell; ~190 minions
  alive (waves pile up). Sim ~8 ms/tick at ~250 units (units 5 ms,
  projectiles 2.3 ms) -> needs a perf pass.
- Run a match: godot --headless --path remake --fixed-fps 60 -- --all-ai --max-minutes=8 --profile
- Next: wave 1 of module agents (ui, pilot_ai, lanes, support) working in
  mirror copies under scratchpad/work/<module>/ and delivering only their
  owned files; lead does the core perf pass meanwhile.
- The wave-1 agents died at the session limit too. From here on the lead
  works inline, sequentially (no parallel agents).
- Lanes fixed: minion leash anchor is now the projection onto the lane
  (was the next waypoint, so side-lane waves passed through each other and
  ignored turrets). Minion damage up, aim error down: waves meet near the
  lane middle and trade. tests/lane_probe.gd and tests/death_probe.gd.
- Perf pass: projectile distance rejects, spatial hash cell 320, single-pool
  shield fast path, minions use `position`. ~5.8 ms/tick at ~250 units.
- UI built (scenes/ui + scripts/ui): StartScreen (seat choice, locked),
  Hud (top bar, me panel + earnings log, feed, banners, toasts, gear slots,
  key reminder), ShipStatus (4-zone shield diamond, bars, routing,
  cooldowns), Minimap (fog, lanes, nodes, units, waypoint, camera rect,
  click to move the camera / place tools), Hangar (Ships / Modules / Gear /
  Kits, trade-in prices, in-bay module swaps, hyperspace launch to bays),
  AdmiralBoard (Research HW2 board with facility row + 8 columns, Build,
  Mothership, Fleet, Pilots), CommandOverlay (map tools with live
  validity preview, Fleet Command box select + right-click orders),
  Scoreboard (hold Tab), HelpPanel (H), EndScreen (New match). P pauses.
- Decision: the Admiral can give orders while flying their own ship (the
  requirement says they "can look anywhere, even when flying"; only moving
  the mothership names "docked"). TeamState.admiral_docked is tracked by
  World.launch / try_dock / MatchRules.on_pilot_died.
- Tests: tests/load_all.gd (headless: loads every script/scene, instances
  UI scenes), tests/ui_tour.gd (windowed: drives the HUD for --role=pilot
  or admiral and saves screenshots), Main --snap=<png> (start screen).
  godot --path remake --resolution 1280x720 -- --auto --role=pilot --bot=tour --test=ui_tour --shots=<dir>
- Hyperspace launch now spools 6 s (PilotProfile state "spooling",
  World.hyperspace_launch, MatchRules.tick finishes it).
- Playtest round 1 (tests/match_probe.gd, 12-min AI matches) found and fixed:
  * AI pilots kept state "home" after relaunching and re-docked at once
    (ping-pong); now reset on launch. Shopping trips only when something
    specific is affordable, never within 60 s of launch. An AI could trade a
    Lance down to a Scout when short of credits; it now keeps its hull.
  * Pilots died more to minions (33) and rocks (14) than to pilots (~28):
    minions deal x0.6 to pilot ships; collisions gentler (safe 220, 0.07);
    AI slows down in the jungle (every rock death was a damaged ship racing
    home through a choke).
  * One team's mining collapsed and never recovered: AI admiral now keeps
    drones at >= 60% of target before spending on tech.
  * Tech came ~30% early (bombers 2:00, frigates 8:24): costs/times of the
    chassis/facility steps raised. Now bombers ~2:35, corvettes ~5:15-6:40,
    frigates ~10-12.
  * AI pilots: respect the turret aggro rule (won't shoot pilots under an
    enemy turret unless securing a kill), back out when a turret targets
    them, fall back when outnumbered and hurt, defend friendly turrets being
    hit by pilots, gather at the Admiral's waypoint after 10:00 (half the
    laners + flex), bombers/lances prefer corvettes and structures.
  * Admiral AI plan walker could jump to late items (built Hyperspace before
    frigates); now looks only 4 steps ahead. Fleet Command added to its plan
    with a simple buy-and-push routine.
  * Ship.homing_target crashed on a freed lock target; fixed.
- Mothership rebalance (tests/ms_duel.gd, scenarios A-I): see DESIGN A12.
  The first draft made "barely beats multiple frigates" impossible (60k+16k
  HP, ~1,000 anti-ship dps upgraded: 3 frigates died in 20 s). Now: smaller
  pool (16k hull + 6k single-pool shield), big ships x2.5 vs the mothership,
  PD vs large x0.1, flak vs large x0.25, modest anti-ship upgrades. Results:
  upgraded vs 4 frigates wins with 24% left; base vs 3 frigates loses.
- Minion waves clashed for ~40 s (> the 35 s wave interval) so minions
  piled up (~200 alive): minions now deal x1.8 to minions. ~130-170 alive.
- Perf pass 2: minions steer/aim/shoot at 30 Hz (move every tick), minion
  guns fire half as often for double damage, projectiles query a small pad
  plus a separate big-unit hash, AI rock avoidance cached at 12 Hz,
  MapInfo.in_open_lane is a grid lookup (built at setup). ~6 -> ~4.5-5 ms
  per tick at ~240 units.
- Support check (tests/support_probe.gd): bays fly/anchor, drones per size,
  hull-hit lockout, Bay Defenses shield keeps repairing, kits heal ~50 over
  10 s, wards only in vision and they see, killed drones rebuilt: 18/18 pass.
  Logistics drones can now repair the mothership (not in the spatial hash).
- Input bot (tests/bot_pilot.gd): W/A/D/arrows/1-4/R/F through the real
  PlayerController: 12/12 pass (A = port/left, D = starboard/right).
- Long match 3 (27 min, stopped): STALEMATE. Only 2 pilot-on-pilot kills
  between 10:00 and 27:00; no mothership damage. Cinder held all middle
  nodes with PD turrets (12 turrets). Found with tests/arena.gd (AI squads
  in open space): AI pilots NEVER engage each other there: each squad flies
  to its lane station and only fights what comes within ~1,000 of it. In
  matches, pilots sit behind their own wave fronts and rarely meet.
  Also fixed: three Logistics per team (heavy AIs bought them before
  frigates); lance AI fired almost never (0.08 rad tolerance); jungle camps
  killed solo junglers (gunship 900 hull / 32 dps -> 600 / ~14).
  Sfx (scripts/audio/sfx.gd) ported from v1 with screen/fog relevance.
  NOTE: after adding a class_name script, run `godot --headless --path
  remake --import` or Main fails to parse ("Identifier not declared").
- Pilot AI engagement overhaul (2026-10-14): on top of the lane station,
  "push" (attack an enemy turret our minions tank near the front; big ships
  lead into PD turrets; the enemy mothership once the wave reaches it, big
  ships close to a standoff range) and "prey" (hunt a visible enemy pilot
  within SEEK 2,600 of us and LEASH 3,200 of the station when the local
  odds are fair and it isn't under an enemy turret; big ships don't chase).
  PilotAI.hold_point pins a station (tests, future orders).
- tests/arena.gd (squads hold the same ground in open space; --debug):
  after the overhaul every match-up resolves. Fighters > lances (3-0) and
  bombers; flak frigate > 3 fighters; 2 bombers > flak frigate and > ion
  frigate (after the torpedo change); ion > flak; destroyer > 3 bombers.
  The arena first sat on The Crossing node: its ore rocks blocked beams.
- Torpedoes were immune to any point defense (one PD hit killed one):
  torpedo HP 10 -> 24 (minion 6 -> 12, turret 20 -> 40), PD vs torpedo
  x3 -> x1, flak x2 -> x1.5, bolts x1 -> x0.6; torpedo damage 60 -> 70.
  Bomber AI now holds a stand-off barrage at 80-95% of torpedo reach and
  ignores strike craft. "dog" AIs fly Fighters; one "lancer" per side.
- Lane centres were fortresses: middle-node turret slots 2/3/2 -> 1/2/1,
  AI admiral builds one turret per middle node, PD turret 8 -> 6 shots/s.
- AI shopping trips: >= 150 s after launch and a bigger pile of credits.
- Mining drones avoid nodes where drones died in the last 150 s
  (TeamState.drone_danger; one team had lost 30 drones at the Crossing).
- 15-min probe after this: K/D 27/34 vs 24/38, ore 35k vs 37k, 54 pilot
  kills, push/prey intents active, frigates ~12-14 min.
- Long match 4 (to 28:00, then the session limit stopped it): 12 / 7
  turrets fell, but pilot kills froze at 56 from 20:00 and no mothership
  took damage. Both AI admirals had built Fleet Command (free waves stop, 30
  minions per side): removed from the AI plan. Cinder sat on 14k treasury.
- Multi-agent bug review (workflow, read-only; the session limit killed most
  verifiers, so the 41 findings were verified by hand; record in
  scratchpad/review_findings.txt). Fixed:
  * Mothership.hit_t sampled 5 points: ion beams passed through the hull
    in ~20% of positions. Now <= 60 u sampling + bisection.
  * Projectiles: a torpedo killed after its own step stayed in `active`, so
    its reused slot was stepped twice per tick (double-speed rounds).
  * Combat.area shared its loop array with the backdoor check: flak near
    turrets hit units twice / skipped units.
  * Beams ignored fire_mult (routing, gear, Broadside, strain): now scale
    beam damage. Capacitor Dump latches onto the next whole ion burst.
    Cooldowns keep overshoot (guns fired ~7% slow). AUTO mounts drop targets
    at their real range. PD torpedo locks re-check the owner.
  * Repair-kit drones were never pruned: AIs used one kit per life.
  * Retreating / falling-back strike craft kept dogfighting until dead: they
    now fly away and only shoot what's in front of the nose.
  * Big ships retreated toward bays in the jungle and pinned on rocks.
  * Human couldn't launch from a bay during a mothership outage (AI could);
    AI could shop during an outage (human couldn't). Both fixed.
  * Fresh enemy units popped out of the fog for up to 0.2 s; a jumped-away
    mothership stayed drawn.
  * Turret/drone armor and Improved Mining now upgrade existing units;
    Fire Control extends turret range; cutting beams use an asteroid
    multiplier (ion 0.6) per DESIGN.
  * Mothership moves follow the big-ship route graph (were straight lines
    through the jungle); minions at the end of their lane chase the live
    mothership (after it moves); a viewer's own vision cell no longer
    blocks its sight (ships beside rocks were blind).
  * Fleet Command no longer charges when the minion can't spawn. AI admiral:
    bays replace the lane that lost one, wards stop churning at the cap,
    ward ownership by quadrant (centre-line entrances went to one team).
  * Texts: Overcharge ("every gun"), Boost Trigger (real numbers).
  * DESIGN.md synced with deliberate retunes (torpedo column, PD turret,
    minion aggro order).
- Mothership re-tuned after the beam fixes (beams always connect now and
  honour Weapons routing): strike craft x0.3, frigates/capitals x2.0, MS PD
  8.5 dmg at 6/s; PD shoots close torpedoes first, else strike craft (it
  never shot the bombers before). Duels: H (upgraded vs 4 frigates) wins
  with 28%; C (3 ion) 24%; B 64%; I/A/E/F lose; D (12 strike craft) wins
  with 77% and no hull damage. Arena 2 bombers vs flak: 2 wins, 2 draws.
- Long match 5 (to 36:00): Halcyon destroyed 17 turrets, yet neither
  mothership took damage; treasuries 50k / 31k; pilots ~5.4k credits idle.
  Causes and fixes:
  * Big ships only pushed the mothership when their (front-based) station
    was within 5,000 of it, and the mothership's guns stop waves well before
    that. New "siege": once the enemy inner node on our lane has no built
    turret (after 15:00), big ships, bombers and the rally group station at
    the lane point just inside weapon reach of the enemy mothership.
  * Rich admirals rebuilt every lost turret instantly: TurretData
    .REBUILD_LOCK (60 s) after a turret dies at a node.
  * Respawn 6 s + 0.6 s/min, max 35 s (was 0.3, max 20).
  * Late admiral sink that also ramps waves: Flagship research Reinforced
    Waves I-III (+15% minion hull/damage each) and Escort Wing (+1 escort
    corvette per lane wave). AI admiral takes them late.
  * Mining drone cap 18 -> 14. Gear-only shopping trips need 2,500+
    credits (home trips are logged in match_probe as home:gear / home:hull).
  * AI admiral's late rally waypoint moves to the enemy inner node (0.66 of
    the lane) once our wave is past the middle.
- Long match 6 (50 min, siege tied to "enemy inner node cleared"): still no
  mothership hull damage; tests/endgame.gd showed why: the AI admiral
  rebuilt the missing turrets in 30 s, so the condition never held. Replaced
  by a TEAM SIEGE (TeamState.siege_lane / siege_phase):
  * AdmiralAI._siege: after 20:00 with 3+ healthy big ships, pick the lane
    with the fewest enemy inner turrets; phase "gather" at 0.6 of the lane
    until 3 big ships mass there (or 90 s), then "assault"; called off when
    fewer than 2 big ships are alive. A human admiral declares one by
    setting the rally waypoint within 6,000 of the enemy mothership.
  * PilotAI: big ships and bombers go to the staging point / the lane point
    just inside reach of the enemy mothership; in an assault, big ships put
    their main guns on the mothership once it's in reach (PD/flak handle
    the respawning defenders that soaked every shot before).
  * First result: Cinder's 3 battlecruisers killed Halcyon's upgraded
    mothership 2:39 into the end-game scenario, but as a base race (both
    fleets were away sieging).
  * TeamState._update_defense (both teams, whoever the admiral is): 2+
    enemy big ships within 7,000 of our mothership -> every AI pilot within
    18,000 converges on a point between the mothership and the threat, and
    our own siege is called off unless it's about to win.
- Siege/defense tuning: two-phase siege (gather at 0.6 of the lane until 2
  big ships mass or 90 s, then assault); a stalled assault (< 15% damage in
  150 s) is called off with a 60 s cooldown; sieges start only with a
  power edge (size-weighted fleet >= 1.2x the enemy's, or the enemy
  mothership < 60%); defense triggers on SEEN enemy big ships within 14,000
  (strike craft answer from 12,000, big ships from 18,000). After 20:00
  the dogfighter AIs move up to flak frigates and the lancer to an ion
  frigate (~5 big ships per side late).
  Endgame scenario per retreat variant (C11), first samples: none = loss at
  27:54 / held to 39:30 (two runs); systems_failure = loss at 28:24 /
  29:22; jump = held 20 min at 26% / loss at 28:41.
- FOUND THE "PILOTS ALWAYS GOING HOME" BUG (tests/stuck_probe.gd): AI
  pilots were physically stuck for minutes to the rest of the match:
  * route base nodes sat at the mothership's CENTRE (lanes start there):
    launching ships ground against their own hull. Base node is now 1,300
    ahead of the bow; lane nodes inside that radius snap to it.
  * RouteGraph.nearest() ignored walls, so ships next to the jungle were
    routed to a node behind the rocks: now the nearest of the 8 closest
    nodes with clear line of sight (World sets route.clear_fn).
  * waypoint advance reach 350 cut the corners of 86-wide jungle gates:
    110 in or next to the jungle.
  * progress-based unstick: no 150 u progress toward the waypoint in 4 s
    -> back off 1 s and re-plan.
  Stuck reports in a 10-minute match: dozens of multi-minute cases -> 7
  transient ones.
- Late-game ending, round 3: AI admiral moves its mothership up the lane
  it's pushing (0.35, after 20:00, when at least even in fleet strength;
  back home under 50% hull; at most one move per 2 min); respawn 0.9 s/min
  (max 50 s); siege gather timeout 45 s.
- C11 decided (full 50-min AI matches, same build): systems_failure ENDED
  at 32:32 (Cinder); none ran out the clock with Cinder's mothership at 4%;
  jump ran out the clock (64 turrets destroyed, no ending). Keep
  systems_failure (DESIGN A2 C11 has the reasoning).
- C12/C13 decided (30-min AI matches): base (nodes_9, per_lane) 5.8 ms/tick,
  144 minions, 20 turrets destroyed; nodes_7 similar, 15 turrets; split
  waves 4.0 ms/tick, 48 minions, only 7 turrets, turrets killed 19 pilots.
  Keep nodes_9 and per_lane (DESIGN A2 C12/C13).
- 2026-10-14 resume: windowed UI tours (both roles) and an 8-shot
  spectator match (1:30 to 35:00) reviewed. Fixes:
  * toasts sit on a dark backing; with a panel open they move to the bottom
    strip instead of covering it (they overlapped the hangar's gear slots).
  * node names on the map drawn fainter (0.34 alpha): "THE CROSSING" was
    painted over the fights there.
  * the siege announcement and the "all pilots defend" alert are team-only
    ("team" tone) and name both sides; the enemy's HUD showed our plan, worded
    from our side ("...assault on the enemy mothership").
- Torpedo interception no longer O(rounds x torpedoes): with > 10 torpedoes
  in flight they're bucketed into 512-unit cells once per tick; each
  bolt/PD/flak round checks only the cells its sweep (+48) touches. Also
  re-checks kind (a slot freed this tick can be reused by a bolt).
  tests/torp_grid.gd cross-checks every grid lookup against the full scan:
  1,705,390 checks over 15 minutes, 0 disagreements. Perf: no measurable
  average gain (projectiles 13.3% -> 14.1% of sim time over the last 10
  minutes of a 25-min match, under heavier machine load; typical torpedo
  counts are 11-22). The real costs are the per-round asteroid/unit sweeps,
  ships (~100 ms/sim-s), minions (~80) and vision (~50). Kept as a cap on
  the worst case (many minion bombers + torpedo turrets late).
- FOUND A STALEMATE CAUSE (match_probe "idle=9", K/D 27/53): the defend
  call (2+ seen enemy big ships within 14,000 of our hull) met them at
  half_len + 1,800 from our mothership; our inner nodes are 8,000-12,650
  out, so two frigates working an inner turret pulled the whole team home to
  idle out of range. Now: the threat is the closest big ship plus the ones
  within 5,000 of it (2+), and the defend point is 1,500 on our side of
  them (still at the hull when they are).
- Defend radius 14,000 -> 7,000 (TeamState.DEFEND_RADIUS). The endgame
  scenario showed BOTH teams "defending" for most of the match: every inner
  node is inside 14,000 (mid ~7,200, top/bottom ~12,100 from the hull), so
  frigates laning there kept the flag up, and defending blocks and cancels
  sieges: none launched by 37:00. Inner-turret pressure is answered by the
  lane (PilotAI._turret_under_attack). Endgame after: Cinder won 30:34;
  contested to 40:00; Halcyon won 31:07.
  Full 60-min AI matches, endings: before both defend fixes 1/4 (27:51);
  with them 2/3 (37:05, 53:13; the third ended the clock at 91%/92%).
- match_probe --debug prints the sieging team's big ships and bombers every
  15 s (hull, state/intent, target, distance to the enemy hull, goal
  distance, nearest enemy turret). It showed why assaults fizzled:
  * shopping trips mid-siege: three full-hull destroyers left an assault
    together to buy battlecruisers when they unlocked; two flak frigates
    spent a whole siege flying home for gear, 25,000 away across the map.
    Now siege participants (big ships, bombers) don't start shopping trips
    during our siege and turn back from one when a siege starts; gear-only
    trips need us within 9,000 of our mothership.
  * the siege/staging/assault points were lane fractions measured from the
    enemy mothership's HOME; after it moved up a lane the fleet "assaulted"
    the empty lane end (goal 5,000 -> 12,700 from the real hull). Now
    TeamState.siege_stage_point / siege_assault_point / enemy_ms_on_lane
    measure from where it is, PilotAI._siege_point walks back from it, and
    the admiral re-targets the siege to its new lane.
  * the AI mothership hopped lanes as the push lane flickered (pilots
    chased it): once up a lane it only changes lanes for a siege.
- With the siege points fixed, the debug trace showed assault goals right
  (600-1,500 from the real hull) but big ships closing at ~30 u/s for
  minutes: PilotAI._fight (big ships) travelled to the hold point but then
  turned the nose to face the target, so with the mothership 15,000 away
  behind jungle and base they thrust straight at it (bombers likewise flew
  straight through the jungle). New PilotAI._target_far: a target further
  than max(3,500, 2.5 x main reach) means follow the route to the goal
  (the standoff point) instead of fighting. Prey hunts stay within 2,600,
  so they're unaffected. Arena regressions unchanged (3 fighters beat 3
  lances 3-0; a destroyer beats 3 bombers); endgame scenario ended both
  runs (33:50 Halcyon, 30:38 Cinder).
- Siege traces (4 full matches, far-target fix in): assaults now reach
  6,000-8,000 of the hull, where the defenders' 7,000 response meets them.
  Two more problems:
  * the stall rule (< 15% damage within 150 s of the assault ORDER) fired
    as slow capitals (150-175 u/s, ~17,700 from the staging point) reached
    the hull. Now timed from first contact (a big ship within 3,000): 120 s
    to do 15%, or 300 s to get there at all.
  * the target moves: a mothership advancing up its push lane made the
    attackers re-target and reroute through the base mid-assault. New C19
    variant `ai_ms` (advance / siege / home) for how the AI admiral uses
    the mothership move; being tested 2 x 60 min per variant.
  * `--seed=N` was documented in Game but never applied; Main now seeds the
    global RNG with it.
- C19 decided (2 x 60 min per variant, stall fix in): advance 2/2 ended
  (43:49, 47:48); siege 1/2 (33:37); home 0/2. Keep "advance".
- TEAM ASYMMETRY FOUND: K/D across 10 full matches leaned Cinder (Halcyon
  died ~11 more times per match; 7/10). Arena checks:
  * the arena itself was biased: it sat in Halcyon's base clearing, so
    damaged Halcyon ships docked within seconds (counted as out) and Cinder
    ships drifting west met Halcyon's mothership guns. Moved to the
    connector (20000, 8600), equidistant; --swap puts Halcyon east; docking
    is printed.
  * still 15-5 for Cinder in mirror-image 3v3 fighter duels: PilotAI skill
    was 0.5 + 0.45 * fmod(slot * 0.618 + TEAM * 0.31, 1), so each role had
    a different skill per side (Cinder's slots 0-2 averaged 0.77 vs 0.63).
    Now slot-only (+0.15 offset). After: Halcyon 11, Cinder 9 over 20 duels
    (alternating sides).
  * matchups re-run at the neutral arena (4 each, sides alternated):
    3 fighters beat 3 lances 4-0; flak frigate vs 3 fighters 2 wins 2 draws;
    ion beats flak 4-0; 2 bombers beat a flak frigate 4-0 (stand off at
    ~1,000-1,140, beyond flak reach ~720; 700 vs 1,100 credits);
    3 bombers beat a destroyer 3 of 4. Caveat: a lone ship always gets slot
    0 (skill 0.57, below the 0.72 average), so 1-vs-N arena results lean to
    the squad. Left as is: HW2-style chain (fighters counter bombers,
    bombers counter big hulls).
- Mothership duels re-run after the skill fix: H (upgraded vs 2 ion + 2
  flak) wins with 27% of total HP; A, E, I lose; B wins with 65%; D (base vs
  8 fighters + 4 bombers) wins with 37% (it varies a lot: 42-77% earlier).
- FINAL VALIDATION (6 x 60-min all-AI match_probe runs, this build): ALL SIX
  ENDED in a mothership kill: 29:42, 30:56, 42:57, 46:13, 48:52, 50:36
  (median ~44 min; Halcyon 4, Cinder 2). Deaths Halcyon 643 / Cinder 687.
  Turrets lost per match 12-37. Session start: 1 ending in 4.
- Open: late treasuries pile up with nothing to buy (admirals 11k-58k at
  the end, pilots 2.6k-5.8k; everything researched by ~40 min). Fleet
  Command is the designed late sink for a human admiral (the AI skips it).
  Whether to add a repeatable sink is a design call for the user.

## 2026-10-14/15: plain-language comments + modular split (user request)

User: make the code "well notated, sufficient for a 5 year old, and as
modular as possible", then run fun experiments in forks with a council
that merges the best ideas into a new branch.

- docs/CODE_STYLE.md: the rules (WHAT THIS IS / HOW IT WORKS / WHO USES
  IT headers, a doc comment on every function, units on every member, step
  comments, jargon explained; one job per file, parts with a back-reference
  or static libraries, public API kept with forwarders, no behaviour change).
- Behaviour-identical refactor proof: tests/det_hash.gd prints a hash of
  the whole game state every 5 s of a seeded match (--late starts at 25:00
  fully teched so sieges/capitals run). Seeded matches are deterministic
  (3 parallel runs identical to 25:00). Tooling in the session scratchpad:
  det_check.ps1 (normal 900 s + late 300 s vs baseline), run_checks.ps1
  (import, load_all, bot_pilot, support_probe, headless UI tours),
  doc_check.ps1 (header/function/member doc coverage), merge_group.ps1.
- Main: --force-hud builds the HUD headless so tests/ui_tour.gd can click
  through every panel without a window (screens print instead of saving).
- tests/fun_probe.gd + docs/FUN_METRICS.md: the fun meter (time budget,
  kills by cause, team fights, leads, comebacks, hull variety, money).
- Agent runs hit the account session limit twice (18 agents at once; then
  2 at a time used ~880k tokens in 55 min). Now one agent at a time; each
  banks its group into main itself and the loop stops at a failure.
- Merged so far (all checks OK, det identical, docs 100%): pilot_ai (919 ->
  314-line core + 7 parts: senses, targeting, goals, combat, flight,
  shopping, systems), admiral + controls (admiral_ai 408 -> 186 + 7 parts:
  plan, lanes, builder, waypoint, siege, mothership mover, fleet command).
- Bugs found by the refactor agents, NOT fixed yet (behaviour must stay
  identical during the refactor):
  * the AI's normal waypoint (55-66% down the push lane) can land within
    6,000 of an advanced enemy mothership, which makes set_waypoint declare
    an "assault" siege by accident; AdmiralSiege then cancels it with a 60 s
    cooldown every second, blocking real sieges.
  * hard-coded prices: AdmiralAI uses 200 (drone) and AdmiralBuilder 450
    (PD turret) instead of the data tables.
  * AdmiralCommand.bay_blocker has no null check on the mothership.

## 2026-10-15 08:41: status at the user's "main agent only" pause

- User directive: "Don't reject anything that violates my constraints":
  requirement-breaking ideas are built as opt-in variants and flagged
  REQ-CHANGE (docs/FUN_PLAN.md section 1 and 5). Escort Wing keeps adding
  the 11th minion by default; the 10-minion version becomes a variant.
- User asked for no new subagents until the session limit resets (about
  12:26). Notation agents already running (entities, shell, tests) finish.
- Notation pass: 10 of 13 groups merged and verified (pilot_ai,
  admiral_control, world_core, ship, hud, panels, map_core, combat, team,
  data); entities, shell, tests in progress.
- Fun research done: docs/FUN_RESEARCH.md (raw) and docs/FUN_PLAN.md (the
  rules). Shared queue for matches: scratchpad run_batch.ps1 (6 slots).
- NEXT (after the reset): verify main (run_checks, det_check, doc_check);
  launch the main-prep workflow (scratchpad wf_prep.js: P1 hooks + the
  waypoint bug fix + escort_wing variant + skill jitter + damage event,
  P2 fun_probe v2 + scorer + arena matrix, P3 det-identical speed-up);
  regenerate det baselines; run baseline v2 (40 seeds, --skill-jitter);
  then the six forks and the council.

## 2026-10-15 (main agent only, waiting for the session reset)

- Notation pass COMPLETE: all 13 groups merged. Whole project: headers
  168/168, functions 942/942 documented, members 1233/1234 noted; all
  checks OK; det_hash identical to the original (normal + late).
- docs/CODE_GUIDE.md: a beginner's map of the whole code (folders, one
  tick step by step, every area's parts, the speed-ups, how to find
  things, a 199-term glossary). Built by scratchpad make_code_guide.py from
  the agents' module maps; the README points at it.
- Speed-ups, all det-identical (seeded fingerprint unchanged), about 12%
  overall (A/B side by side, seed 7, 14 min: 385 -> 347 ms per sim-second,
  then 371 -> 363):
  * PilotAI parts looked their brain up through a weak link on every use
    (168 uses, per tick): now once per function (`var brain := ai`).
    AI control 68 -> 56 ms/sim-s.
  * Vision: viewers sharing a cell + radius share one answer; "explored"
    marked once per cell + radius per team; ray steps precomputed per ray
    count (64-bit floats, identical values); ray cache 8,000 -> 30,000
    answers (it was emptied every ~2 minutes). Vision 47 -> 28.
  * Shots: a round whose whole straight path is rock-free at firing (with
    a 4-unit margin; rocks only disappear) skips the per-tick rock check.
    Projectiles 67 -> 56.
  * AsteroidField.clear_at(): a 100-unit "distance to the nearest rock
    edge" map lets rock-dodging units in open space skip the rock search
    (Steer.avoid_rocks, PilotFlight). Mining drones 26 -> 22.
  * Spatial hash skips empty row segments; a gun's turn rate and a
    minion's round speed are read once, not per tick.
- BUG FIXED (behaviour change, intended): AdmiralCommand.set_waypoint gets
  declare_siege (default true for humans); the AI's own waypoint passes
  false, so its rally point near an advanced enemy mothership no longer
  declares an accidental "assault" that AdmiralSiege cancelled every
  second (with a 60 s cooldown), blocking real sieges. A human-declared
  assault now also stamps siege_t.
- Tools: Python 3.15 and ImageMagick installed by the user. The prep
  workflow's scorer becomes tools/fun_score.py; the perf agent (P3) was
  dropped (done here); P1 no longer needs the bug-fix stage.
- Slimming pass, batch 1 (behaviour-identical: the seeded fingerprint is
  unchanged, normal + late):
  * Dead code out: functions, variables, constants and a signal that
    nothing used (e.g. AdmiralCommand.assign_drones, Effects.float_text
    and its floating-text lists, Vision.occluded, EnergyPool.can_spend,
    Minimap.clicked_world, Ship.thrust_rev, Minion.wave_id,
    DamageInfo.bonus, TeamState.spent and turret_dmg: nothing ever read
    or set them).
  * The design variants that lost their tests are gone from the code
    (DESIGN.md keeps the results): C11 "jump" (and with it
    Mothership.jump_t and Unit.targetable, which only the jump ever
    switched off), C12 "nodes_7", C13 "split" waves, C19 "siege" and
    "home" (the ai_ms switch). Only "retreat" can still be switched
    (systems_failure / none; ms_duel and endgame use none).
  * Six Events signals that nothing listened to are gone (unit_died,
    ship_destroyed, minion_killed, structure_built, ore_delivered,
    strain_changed), and so are the one-off probes lane_probe,
    death_probe and stuck_probe.
  * tests/lib/late_game.gd (LateGame.apply) replaces the two copies of
    the 25:00 setup in endgame.gd and det_hash.gd.
  * tools/api_index.py rebuilds docs/API_INDEX.md (it was out of date:
    it missed every part file and listed deleted functions).
  * GDScript: 12,791 -> 12,507 code lines (comments 11,412 -> 11,131);
    the survey finds no dead-code candidates any more.
- Slimming pass, batch 2 (meant to change the game a little; new
  fingerprint baselines, and two runs of the new build are identical):
  * Effects (particles) and Sfx (sounds) now have their own random
    numbers (RandomNumberGenerator, fixed seed) instead of the shared
    sequence the game rules use. Before, a puff skipped in the fog, or a
    sound cue dropped because of real time, moved the shared sequence, so
    a windowed match played differently from a headless one with the same
    --seed, and even two windowed runs differed. Now the rules never see
    what the screen or the speakers do.
  * The torpedo grid (ProjectilesTorpGrid, its test tests/torp_grid.gd and
    its test switches) is gone: rounds that can shoot torpedoes down just
    check every torpedo in flight (rarely more than about 20). With
    several torpedoes on one line, the first in list order is hit now (the
    grid went cell by cell), so the fingerprint changes there too.
- Torpedo grid removal, measured fairly: with the grid put back into a
  copy of main (same random numbers, so the identical match: all 84
  fingerprint lines equal), the late game's projectile cost was 1-6 ms per
  sim-second LOWER without the grid in every minute from 25:00 to 32:00.
  Rebuilding the grid every tick cost more than it saved.
- The UI is built from scenes now ("implement nodes where appropriate"):
  every screen's fixed layout is a Godot scene in scenes/ui/: the HUD
  (hud.tscn holds the top bar, me panel, feed, banner, toast, ship
  readout, minimap and gear slots as child scenes), the start and end
  screens, help, scoreboard, hangar and Admiral board. Each script reaches
  its nodes with @onready and only fills in what changes while playing.
  Rows and cards made from game data stay in code, and so do the widgets
  that draw themselves (minimap, ship readout, command overlay). Colours
  stay in Palette: UiKit.make_theme() defines named looks (Godot "type
  variations": MistText, AmberText, PrimaryButton and the PANEL_LOOKS
  boxes) that scene nodes pick by name. UI scripts went from 1,865 to
  about 1,605 code lines.
  * Exact check, new: tests/ui_tour.gd --dump (headless, fixed frame step,
    1280 x 720) prints every control on screen at all 18 tour steps (now
    including the end screen and the start screen): its class, place,
    size, text, font size and colour, box style and gaps. Every conversion
    matched the old UI line for line (2,057 lines) before it was banked;
    scratchpad ui_dump.ps1 runs and compares it. The pilot UI tour now
    runs to the end headless (run_checks waits for "ui_tour: done").
  * Windowed screenshots are for eyes only: the player's ship follows the
    real mouse, so two windowed runs of the same build differ.
  * Done by 4 agents, two at a time, each in its own copy and banked under
    the main lock with the full checks; the lead then removed the
    scoreboard's fallback for Scoreboard.new() (the board now uses the
    scene), regenerated docs/API_INDEX.md, updated CODE_GUIDE.md and merged
    its near-duplicate glossary entries (26 groups).
- P1 of the fun-plan prep is banked (feature registry, Rules.tune, damage
  and minion-scale hooks, push-target weight hook, Events.damage_applied,
  usage counters, --skill-jitter, the escort_wing variant); the seeded
  fingerprint is unchanged. P2 (fun_probe v2, tools/fun_score.py, arena
  matrix) is written but not yet proven or banked.
- AI bug hunt (the user: check pilot flight pathing, behaviour and
  targeting, then a deep dive of AI pilots, minions and the admiral before
  the fun plan, so bad AI doesn't skew the fun data). New probe
  tests/pilot_audit.gd (kept in the scratchpad for now). Seed 7, 25 min:
  98 stuck episodes, ~3,900 ship-seconds of rock contact, 6 crash deaths,
  11% of fight samples aimed at targets behind asteroids, big ships not
  approaching their hold point in 58% of samples (68% late game).
  Confirmed in the code so far (fixes pending):
  * pilots flying home ("home" state) pick a target but never shoot;
  * the Ion Frigate's fixed burst beam fires with no nose-alignment check;
  * a jungler whose camps ran out stays a laner until it next dies/docks;
  * big ships fighting can't reach a hold point behind or beside them
    (travel's thrust assumes facing the waypoint; fight() faces the
    target), and the stuck timer then reverses them mid-fight;
  * no line-of-sight check when picking targets or prey.
  The deep-dive workflow was paused at the 5-hour usage cap; its probes and
  logs are kept for the resume.

### 2026-10-15 ~15:20: deep-dive salvage (no code changed in main)
The stopped investigators' work was rebuilt from their fix copies and
transcripts into the scratchpad's deepdive\PRELIM.md: 24 candidate AI fixes
(flight 5, pilot behaviour 8, targeting 7, minions 4), each behind a switch
in a scratch copy. Newly measured: fighter and bomber minions face the
target instead of the lead point they compute, so only ~22% of fighter
bolts and ~10% of bomber torpedoes are on a hitting line (88% and 69%
would be if aimed at the lead); most rounds expire. Found in code: the
late-game rally pulls the whole mid trio (seats 1, 5, 9) off mid; the AI
never uses the Hyperspace Module; repair kit drones trail moving patients
out of heal range. A/B audits of every fix bundle (seeds 7, 11, 13) were
queued to run during the usage wait.
### 2026-10-15 ~16:05: first A/B verdicts on the salvaged AI fixes (scratch copies only)
- Minion aiming fix bundle: clear win. Fighter bolts on a hitting line go
  from ~20% to ~78%, bomber torpedoes from ~8% to ~47%, and rounds into
  rocks almost vanish. Minions do ~30% more damage to pilots. Lane-front
  deaths keep the same shape.
- Flight bundle: stuck episodes -75%, big ships failing to reach their
  firing spot -77%, crash deaths -70%. But rock contact while fighting
  rises x4.6, so the five fixes are being tested one at a time.
- Pilot behaviour bundle: pilots spend 2.4x longer flying home (the "shoot
  on the way home" fix makes strike craft turn to fight). It needs
  splitting before any of it is kept.
- Admiral: confirmed that the push lane is measured in raw distance, so
  mid is chosen 5-13% of the time against 14-36% by real progress. No
  siege dented a mothership in 30 minutes. Repair bays last ~3 minutes on
  average, costing each side 5,000-8,500 credits per match.
Details and next steps: the scratchpad's deepdive\PRELIM.md and STATE.md.
### 2026-10-15 ~17:50: P2 banked (fun probe v2 and the fun scorer)
16 files from the P2 copy into main: tests/fun_probe.gd and its parts
(tests/lib/fun_probe_time/fights/kills/lead/motherships/economy/ttk.gd,
fun_stats.gd, adv_index.gd), the arena kit and matrix (tests/arena.gd,
tests/arena_matrix.gd, tests/lib/arena_kit.gd), tests/lib/late_game.gd
(new optional `symmetric` start; the default is unchanged, so the det
baselines still hold), tools/fun_score.py and tools/fun_lib.py. Proof: all
checks pass; two 20-minute matches and one late match scored (FUN 58.5
normal, cut at 20:00; 89.1 late, ended 33:43). API_INDEX.md regenerated; doc
coverage 178/178 headers, 1011/1011 functions, 1405/1405 members. No game
code changed.
### 2026-10-16 ~02:20: AI deep dive, pass 1 banked (18 fixes: flight, pilot behaviour, minions)
After the deep dive (investigators per domain; every fix measured behind a
switch on 3-6 seeds; ported by one agent, adversarially reviewed by another,
issues fixed), 20 files banked; all checks pass; new det baselines made
(deterministic; the map differs from t=0 because of the rock-gap sealing).
- Flight: short hops route around rocks (A); The Crossing's route dots split
  around its rock field (B); big ships keep their travel heading toward a far
  firing spot (D); braking with the main engine when sliding tail-first into
  rock (E); hold fire at a hidden target and drop it after 3 s (I); an escape
  planner for ships wedged in rock notches, new scripts/ai/pilot_escape.gd,
  with a counted work budget so it never stalls a frame (U); rock gaps
  narrower than a ship sealed at map build (M); corner and gate speed caps
  (O); bombers' waypoint reach (X).
- Pilot behaviour: repair-kit drones follow a moving patient (kits heal
  again at speed, for humans too); the late rally takes one seat per lane
  instead of the whole mid trio; energy routing counts only real fights;
  junglers angle shields at the monster hitting them; the AI uses the
  Hyperspace Module.
- Minions: fixed-gun minions aim at the lead point and fire only when lined
  up, route to their lane when they start outside it, and skip targets behind
  rocks.
Measured on 6 seeds x 15 min against the old game: stuck episodes 209 -> 37,
stuck seconds 3274 -> 256, rock contact -72%, shots fired at hidden targets
4024 -> 113, crash deaths 28 -> 2, big ships failing to reach their firing
spot -54%. Pilot deaths +38% (the AI fights more; minions now hit what they
aim at: deaths to minions 95 -> 190; a later minion re-targeting fix takes
much of that back). Next: pass 2 (targeting + admiral) and minion re-targeting.
### 2026-10-16 ~07:35: AI deep dive, pass 2 banked (targeting + admiral, 10 fixes)
- Targeting: beam weapons aim straight at the target (they hit instantly);
  a target behind an asteroid scores 700 worse; the Lance uses Overload
  while its beam is on; the Ion Frigate's fixed burst beam fires only
  nose-on.
- AI admiral: the push lane is judged by the fraction of each lane, not raw
  distance (mid chosen 8% -> 33%); no retries on a turret spot in its
  rebuild lockout; one drone order per think; the "base under attack" alarm
  uses a 4,000 radius once the mothership has moved forward, and while we
  siege only a push within 2,500 of our hull; sieges go to the lane the
  parked enemy mothership is on.
- New permanent probe tests/admiral_audit.gd. Full report of the deep dive:
  docs/AI_DEEP_DIVE.md. Pass 3 (minion re-targeting, target stickiness,
  bombers skipping small craft, ships sliding along mothership hulls, a
  shield-aware retreat for small ships, and the user's "always park on mid")
  is being ported.
### 2026-10-16 evening: cloud runs, baseline v2, fork screens, speed-ups (no game code banked yet today after pass 2)
- GitHub: the project now lives also in a public repository; matches run on GitHub's free cloud runners
  (each platform repeats itself exactly; cloud and PC runs are never mixed in one comparison). Personal and
  machine-identifying information was scrubbed from it and a pre-push guard keeps it (and any credential) out.
- Baseline v2 (40 full matches in the cloud): FUN 63.9; 70% of matches end, median 46.5 min; Halcyon and
  Cinder won 14 each (the earlier "Cinder always wins" was chance; six small code asymmetries were found and
  fixed behind switches anyway).
- A "sim-only" mode for headless test runs (no drawing or sound, provably identical simulation) makes
  matches ~1.9x faster; being ported into the game with an adversarial exactness review.
- All six fun-plan forks are built (every idea as a switchable feature module, requirement-breaking ones
  flagged) and are being screened in the cloud with early stopping; results so far: combat roles keeps the
  minion damage cap on pilots, the Lance hunter role and stronger torpedoes vs small craft; pacing keeps the
  ship-size-scaled respawn wait.
- In progress: pass 3 of the AI fixes (incl. "always park on mid"), a balance-tuning sweep for the open
  design calls, playable builds (Windows on GitHub Releases, browser on GitHub Pages).

## 2026-10-16: performance pass (agent "perf"), ported onto pass 3
- New launch option `--sim-only` (Game.sim_only), a speed mode for windowless test runs: everything that only draws or sounds is skipped (unit pictures and flame emitters, shot and effect drawing, sound cues, HUD, camera). A windowless run was spending about half of its computer time on that. The match is exactly the same: tests/det_hash.gd gives identical lines with and without it. Careful detail found by that test: Godot's CPUParticles2D takes one number from the shared random sequence when it is made, so ShipVisual takes the same three numbers in this mode.
- Exact speed-ups (no result changes): AI pilots skip the hull-distance maths for motherships that are clearly far away (PilotFlight.avoid_hulls; pass 3's own distance check there was kept, and the "which way do I want to go" maths now waits until a hull is near), Mothership.keel_arrow() keeps the keel's nose arrow until the ship turns, minion targeting asks the rock check only of an enemy that would become the best target so far (and not again of the target it keeps).
- tests/perf_probe.gd got `--late` and `--noprof`; tests/det_hash.gd prints "DET_RNG" (the next shared random number) at the end.

### 2026-10-16 evening: the project is now called Halcyon Drift, the asteroid belt the battle is fought in (user decision, text only)
- The user decided: "Lets change the project name to Halcyon Drift, which we shall say is the name of the
  asteroid belt we are fighting in." So Halcyon Drift is the project name and also the setting: the battle is
  fought in the Halcyon Drift, an asteroid belt. The lanes, the asteroid resource nodes and the asteroid jungle
  are inside it. Nothing else about the belt is decided (no history, factions or extra places were invented).
- The game folder already used the name (project title, start screen title, HalcyonDrift.exe, doc headers); the
  old name "Fleet Command 2" was left only at repo level (the repository's root README title; the repository
  name and the folder names are unchanged on purpose: they are the user's GitHub setting and running paths).
- Setting added in: docs/DESIGN.md (a "Setting" paragraph at the top, row C20 in the conflicts table, and a new
  section A16 "Open questions"), README.md (opening paragraph), project.godot (config/description) and the start
  screen's tagline text (now ends "THE HALCYON DRIFT ASTEROID BELT", was "AN ASTEROID JUNGLE").
- Not changed on purpose: "Fleet Command" is the late-game admiral module (Fleet Command Module, AdmiralFleetCommand)
  and keeps its name; the team names Halcyon (amber) and Cinder (red); the user's verbatim documents and older log
  entries. No game logic changed: only docs, the project description and one label's text.
- Open question for the user (DESIGN.md A16): the Halcyon team shares its name with the Halcyon Drift; keep it
  (e.g. the belt's home fleet) or rename the team?
### 2026-10-16 evening: the good-guy team is now called Aurelian (user decision)
- The user answered the open question from the project rename: the team that was called Halcyon (team 0, amber)
  is renamed Aurelian, the user's own pick for an uncommon good-guy name. Cinder (team 1, red) keeps its name, and
  Halcyon Drift stays the name of the project and of the asteroid belt. Recorded in docs/DESIGN.md (row C21 in A2;
  A16 is answered) and docs/CODE_GUIDE.md (a "Team names" note and a glossary entry).
- Everything the player sees says Aurelian. Rules.TEAM_DISPLAY holds the player-facing names and
  Rules.display_label() swaps the internal label in text that was built from one (the place names
  "Halcyon Top/Mid/Bottom", the end screen's reason). They are used by the HUD top bar, the end screen, the
  scoreboard heading, the kill feed and the other feed lines, the map's node labels, the Admiral board's node
  and waypoint lines, the hangar's repair-bay buttons and the debug overlay; the start screen's seat text and
  the Admiral's opening hint were changed too. The docs and code comments that name the team say Aurelian.
  The README files name no team.
- Kept as the internal label Halcyon on purpose, so every past research log, JSON file and baseline stays
  comparable: Rules.TEAM_NAMES, Rules.HALCYON and the other identifiers, scene node names (and the node names
  themselves), log and print output (the SUMMARY line included), JSON keys and values, test output labels, the
  tools scripts, file names, the user's verbatim documents and the older entries of this file.
- Display only: the code changes are the new constant and helper and their use at the display sites; no game
  logic changed.
