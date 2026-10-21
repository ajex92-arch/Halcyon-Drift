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

### 2026-10-17: v0.2.0, the fun council's two rule sets ship as opt-in presets (user decisions)
- The six fun-plan forks (docs/FUN_PLAN.md section 5) were merged into the game and the council (section 6) built
  and validated two combinations. The user chose to ship both as rule sets the player picks: "Within
  requirements" (`--preset=within`) and "Council's pick" (`--preset=pick`). The start screen has a new RULE SET row
  (under the rules text, above the seats) with "Standard rules", "Within requirements" and "Council's pick";
  Game.apply_preset() applies the choice before `--variant`, so `--variant` can still change one key of a preset.
  An unknown `--preset` name stops the match at its start ("PRESET UNKNOWN", exit code 3) instead of quietly
  playing the default game.
- The key promise: with no preset (and no `--variant`) the game is exactly v0.1.0. Every key of every fork
  defaults to off, FeatureRegistry installs only the switched-on ones, and the shared-code edits are empty hooks,
  so tests/det_hash.gd prints v0.1.0's hash lines (normal 900 s and `--late` 300 s).
- The user's choices (2026-10-17): the pick stays "Within requirements" plus the turret-rebuild lock
  (`node_persist`), although the lock added nothing on 80 seeds; and both presets use a fleet cap of 60 bought
  minions (the keys-off game stays at 30; `--preset=within --variant=fleet_cap:30` plays the old limit inside a
  preset). `fleet_cap` is a new key: Minions.control_cap() reads it, so one limit holds for both teams and for a
  human or AI Admiral, and the Admiral board's texts show the limit of the match.
- What is in the presets: within = `minion_cap:on,lance_role:on,bomber_role:both,admiral_sinks:fleet,redeploy:on,
  gear_mk2:on,fleet_cap:60`; pick = within + `node_persist:on`. None changes a requirement: the user also made
  60 the Fleet Command limit requirement on 2026-10-17 (DESIGN.md C22; the verbatim docs/USER_REQUIREMENTS_2026-10-13.md
  still says 30, and the standard rules keep 30). The requirement-changing ideas stay one switch each, off by default
  (docs/RELEASE_NOTES.md lists them in plain words, FORK_MANIFEST.md lists every switch).
- Validation (the preset build, 80 fresh AI-vs-AI matches per arm on the same seeds 181-260, cloud runs): FUN 63.0
  for the default game, 81.4 for "Within requirements" (+18.4, 95% lower bound +14.5) and 79.8 for "Council's
  pick" (+16.8, lower bound +13.3); the bar was +5 with a lower bound above 0. Every match ended in both presets
  (default: 55% within an hour), typically after about 29 minutes. node_persist adds no fun on top of "within"
  (-1.6, not significant). The matches were AI against AI.
- Known issues: very short last pushes at cap 60 (46% under 45 s in "within", 38% in the pick, 27% by default),
  the pick may lean to Vhorr (Aurelian won 38% of 80; 44% of 80 in "within", 48% of the 44 that ended by default),
  "both ship sizes needed" and "admiral matters" may dip (chance alone gives such dips in about two of three
  comparisons of this size: things to watch in a playtest), and cap 60 costs about 39% more late-game simulation
  time. Next: a human feel
  check of a match where the AI Admiral buys Fleet Command, a big-ship role, a final-push band, and the held
  `doctrine:on` once the user's Admiral changes are in.
- Docs and code map: new docs/RELEASE_NOTES.md, FORK_MANIFEST.md rewritten for the game (rule sets and every
  switch), docs/fork_manifests/ (the six forks' manifests), README.md and docs/CODE_GUIDE.md (the scripts/features
  folder, the "feature module", "preset / rule set" and "variant" entries), docs/DESIGN.md (the Fleet Command
  limit) and docs/API_INDEX.md (rebuilt). The root README has a short "Rule sets" note.
- The enemy team's display name is now Vhorr (user decision, 2026-10-17: everywhere, like Aurelian). Same split as the
  Aurelian rename: Rules.TEAM_DISPLAY[1] and Rules.display_label() give the player-facing name (HUD, end screen,
  scoreboard, feed, Admiral board, place names such as "Vhorr Top"), and the docs and code comments that name the
  team say Vhorr. Kept as the internal label Cinder on purpose: Rules.TEAM_NAMES, Rules.CINDER, Palette.CINDER,
  Roster.CINDER, scene node names, log and print output (the SUMMARY line included), JSON keys and values, test labels,
  the tools, file names, the user's verbatim documents and the older entries of this file. Recorded as C23 in
  docs/DESIGN.md and in the "Team names" note and glossary of docs/CODE_GUIDE.md. Display only: no game logic changed.

### 2026-10-17: UI layout fix, no text on top of text at any window size
- Problem: in windows smaller than the design size (laptop screens, a browser window, 1024 wide or 600 high) the HUD
  put its pieces on top of each other. The top bar covered the "me" panel, the ship readout covered the gear slots
  and the minimap, a pop-up hint covered the minimap or the end screen, and every big panel (hangar, Admiral board,
  help, scoreboard) covered the kill feed, the big message, the minimap and the instruments. Some panels also ran off
  the window, and stayed too wide after the window got smaller.
- The fix is in the UI only; no game rule, simulation file or balance number changed. New scripts/ui/hud_layout.gd
  (HudLayout) places the HUD's pieces so they stay out of each other's way: the top bar moves right of the "me" panel
  in a narrow window, the gear slots go into two rows when the bottom row is too tight, the instruments hide while a big
  panel is open, and the big panels sit under the top bar. The hangar, board and help size their cards from the window
  (UiKit.panel_width) so they can shrink again and rebuild on a resize; their scroll areas take the height that is
  left. The scoreboard scrolls inside a short window and its Status column is wide enough for the Admiral. The kill
  feed starts under the top bar. The pop-up hint wraps, and stays away over the end screen. The start screen card
  keeps 10 pixels from each side of a 1024-pixel window. The Admiral board's module
  cards wrap instead of widening the board.
- The checker: tools/ui_layout_check.py reads the UI tour's layout dump (`--dump-layout`, with `--ui-size=WxH` for the
  window size, or several sizes separated by commas to resize the window between dumps; the dump code is
  tests/lib/ui_dump.gd) and reports text on text (OVERLAP), text under a solid panel (COVERED), controls outside the
  window (OFFSCREEN) and text that does not fit its box (CRAMPED), with the two controls and the step. It has
  `--selftest`. The tour (tests/ui_tour.gd) also fills the kill feed and the earnings log first, and covers two more
  screens, so the check sees the HUD at its fullest.
- Result, problem lines for the pilot and the Admiral tours together, v0.1.0 against the fix, at 1024x600, 1280x600,
  1280x720, 1366x657, 1366x768, 1536x730, 1600x789, 1920x969, 1920x1080 and 2560x1300: before 367, 226, 214, 171,
  147, 126, 142, 138, 58 and 58; after 0 at every size.

### 2026-10-17: v0.2.0 release review (Opus), and what it changed

- An adversarial Opus review read the UI fix merge (77f7073..2b155b1), the 18 review-fix commits with the Vhorr
  rename, the v0.2.0 release notes, and every commit message and added line since main for privacy.
- UI merge: no defects (the four conflict resolutions, freed or missing nodes, signals and timers, hidden panels and
  the mouse, the browser build, sizes between the tested ones). Review fixes and rename: no defects (the display
  name is never used as a key). Privacy: clean.
- Release notes, fixed: the sentence that the determinism test shows the rule-set matches play out the same had no
  evidence, because the determinism test ran without a rule set. It was run with both: the late window (25:00 to
  30:00, seed 7) on the tested code (7f19200) and on this release, identical over all 60 hash lines for "Within
  requirements" (END 40ad326f) and for "Council's pick" (END 3b7b77ef), no script errors. The sentence now says it
  was run with both rule sets.
- Release notes, fixed: the hidden-HUD sentence now names every big panel (scores, hangar, help, Admiral board)
  and every piece that steps aside.
- README and release notes: a fresh copy of the source has no import cache (the .godot folder), and a plain
  `godot --path remake` then shows an empty window because the scripts cannot find each other's class names. Both
  now say to run `godot --headless --path remake --import` once first. (Opening the project in the Godot editor
  imports it by itself.)

### 2026-10-18: hotfix (test tool only): tests/spectate_shots.gd photographs the fights again

- The photo tour could stop with "Trying to assign invalid previously freed instance": its search for the busiest
  spot read `.alive` of every unit the spatial hash returned, and a unit freed in that frame stopped it. It now
  skips freed units with `is_instance_valid()`.
- Its free camera also drifted toward the map's top-left corner by itself (CameraRig's edge panning sees a fresh
  window's mouse at (0, 0)), so even a correct aim ended at the map edge. The camera's own per-frame work is now off
  from the aim until the picture is saved, with its position and zoom set by hand.
- After each picture it prints the camera spot and how many units, pilot ships and minions are in view, and a FAIL
  line when no pilot ship and no minion is in view; its last line is "spectate_shots: done N pictures, F failures".
- Measured on this same file (seed 7, --speed=4, 1280x720, six pictures from 1:30 to 20:00): units in view
  3, 0, 0, 0, 0, 0 before the fix and 14, 12, 21, 22, 22, 22 after it, 0 failures, no script error.
- Only the test script changes: no game code, so every match plays exactly as before.

### 2026-10-17/18: the AI opening fix, rounds 1-3 (M-03, for v0.2.1)

- AI opening fix (user report and decision, 2026-10-17; ships as v0.2.1; DESIGN.md C24 and A14). The user saw the AI
  ships hover around their own inner nodes until the minions spawned, and some fly home to shop before escorting the
  minions to the middle. Now, for the first 10 seconds (Rules.AI_OPENING_HOLD) every AI pilot of both teams waits near
  its own mothership; from 10 s each one flies to its lane's Crossing node (the three ore nodes on the centre line) and
  contests it, even before any minion has launched. Junglers contest the middle Crossing, then go to their camps; the flex pilot
  contests the top Crossing (its lane rotation now starts on the top lane; second-round entry below). The opening ends per lane when the team's first minion wave reaches that Crossing (or at
  Rules.AI_OPENING_MAX, 180 s). No trips home to shop in the opening; retreats for low health still happen; an admiral's
  waypoint, a siege, a defend call and a test's hold point still win. AI layer only (PilotGoals.opening_active() and
  opening_goal(), PilotShopping.wants_shopping(), PilotAI.opening_done): no change to the simulation core, the win
  condition or other rules, and the human pilot is unaffected. New test: tests/opening_probe.gd (--test=opening_probe).
  Measured on seeds 301-306 (all-AI, 300 s), before then after: distance to the own mothership at 10 s, 6,000 on average
  (none of the 144 pilots within 3,000) then 840 (all within 1,200); first pilots within 1,500 of the Crossing, 92 s at
  the earliest and only together with the first wave, then at 24-36 s (all 144 pilots, a median of 68-77 s before the wave); shop trips before the first
  wave, 0 then 0 (the first shop trip of any pilot was at 173 s before and 175 s after, so trips home were never the
  cause of the empty Crossing); with the fix the junglers choose a camp when the wave arrives (24 of 24). The price is a much earlier and
  heavier fight, since both teams reach the Crossing at the same time: pilot deaths in the first 300 s went from 125 to
  232 over the 6 seeds, first blood from minute 1.7 to 0.55, and retreats before the first wave from 2 to 181. Full
  matches (2,400 s, seeds 301-306, fun_probe, pilot_audit, admiral_audit; none of the fix matches ended in 40 minutes, one
  baseline match did): kills per minute +9%, deaths per pilot +9%, fights +17%, mining drones lost +7%, admiral decisions
  unchanged, rock contact -26%, stuck episodes +16% (131 to 152; the count before 10:00 is the same, 16 and 15; 4 and 9
  before 5:00). Flagged for the user: the stuck episodes, the "skirmish ramps into battle" fun ingredient (-22: the fights
  now start at once instead of ramping up), and the share of matches that end in 40 minutes (1 of 6, then 0 of 6).
  Determinism of the final build: see the second-round entry below.
- New test tests/crossing_probe.gd (--test=crossing_probe): when each team gets a turret at each Crossing node, how long
  it stands, and, second by second, what the admiral's build check answers there (free, enemy ships near, enemy turret,
  rebuild lock, full). Measuring only; the AI admiral's turret order is unchanged.
- AI opening, second round (user decisions of 2026-10-17, DESIGN C25; ships in the same v0.2.1). (1) The AI admiral's
  AdmiralBuilder.more_turrets() now picks the Crossing turret (one PD turret per middle node, 750 credits) before the
  extra turrets at the inner nodes; nothing else about its turrets changed (no new build step, no capture rule: the code
  has none, a Crossing is held by whoever has a live turret there and the build check needs no enemy turret, a free
  slot, no rebuild lock and no enemy ship or minion within 1,500). (2) The flex pilot's 90-second lane rotation now
  starts on the top lane (PilotGoals.FLEX_ROTATION_SHIFT = 2): top, mid, bot, instead of mid, bot, top, for the whole
  match, the same for both teams (top stays top when the map is mirrored left to right); in the opening it keeps the top
  Crossing. (3) Not built, kept as a later design item: making it clearer to both teams that a point is contested, how
  long it must stay uncontested before it can be built on, and more counterplay. New test: tests/crossing_probe.gd.
  Measured on seeds 301-306 against the v0.2.0 game: the opening is as before (every AI pilot within 1,200 of its mothership
  at 10 s; first pilot at its Crossing at 24-36 s, junglers 27-28 s, the flex pilot 34 s at the top Crossing; 72-77 s before the
  first wave; no shop trip before the wave); pilot deaths in the first 300 s 125 to 191, first blood minute 1.73 to 0.61.
  Full matches (2,400 s): kills per minute +1%, deaths per pilot +1%, fights +16%, mining drones lost -2%, rock contact
  -10%, crash deaths 0.13 to 0.02, admiral decisions 2.92 to 3.08 per minute (the band is 0.5-3.0), stuck episodes per 100
  pilot-minutes 2.82 to 3.10 (+10%; 131 to 134 in all, but 4 to 23 in the first 5 minutes and 16 to 30 in the first 10,
  from a few ships stuck again and again near the Crossings: the known asteroid snag, not fixed), matches that end in 40
  minutes 1 to 2 of 6 (all three ended matches in both builds were won by Vhorr), FUN 62.0 to 61.7. The reorder alone barely
  moves the Crossing turrets (they are limited by money: the admiral has 300-500 credits at 5-10 minutes and builds extras
  only over 800 spare): the first turret at a Crossing went up at a median of 530-960 s before and 590-1,360 s after, 22 of
  36 team-and-node slots had one by 25:00 before and 23 after, and 20 turrets were lost against 11. Determinism: two runs of
  the final build agree; normal END 6f268d9d (180 hash lines), late END ccbb4bde (60 hash lines). The late run is no
  longer the v0.1.0 one (4bccf106): the turret order alone gives 880f0eca, with the flex shift ccbb4bde.
- AI opening, third round (user decisions of 2026-10-18, DESIGN.md C25 items 4 to 6; ships in the same v0.2.1). An
  independent review of the opening fix found two small defects, which are fixed, and the user answered two questions,
  which are built. (1) The first wave's arrival at a Crossing is now one fact per team and lane
  (TeamState.first_wave_at, noted once by PilotGoals._note_first_waves(), which looks at all three lanes whichever
  pilot asks), not something each pilot had to see itself. A pilot that was dead, docked, retreating or flying home
  when the wave got there used to start a second opening when that wave died before the next one came; now it is done
  at its first think. (2) A jungler in the opening falls back when it is hurt and outnumbered, as a lane pilot does:
  the rule in PilotAI._think() was gated on the lane state, and a jungler's state stays "jungle" while it runs
  think_lane(). (3) "Only a human admiral's" (the user): in the opening the waypoint seats (4, 5, 6 and the flex
  pilot) follow a waypoint only when a human admiral placed it (TeamState.waypoint_by_human, set through the new
  by_human argument of AdmiralCommand.set_waypoint, default false; the command overlay passes true, AdmiralWaypoint
  false). The AI admiral's own waypoint goes up at 60 s in every match and used to pull those seats off their
  Crossings. Outside the opening nothing changes: from 10:00 any waypoint rallies those seats, and a human admiral's
  waypoint still wins over the opening. (4) "Where its ships are" (the user): the admiral's first Crossing turret goes
  to the allowed Crossing (no turret of its own there, build check passes) with the most of its own pilots and minions
  within 1,500 of it (AdmiralBuilder._crossings_in_order(); the radius is TurretData.BUILD_CLEAR_RADIUS, the disc of
  the build check's "enemy ships too close"). A tie, or none of its ships near any allowed Crossing, keeps the map
  order; once the team holds a Crossing the later Crossing turrets and the extra turrets at home follow the old rules.
  No random numbers and no clock were added.
- Measured on seeds 301-306 (all-AI, 300 s, skill jitter), the round-2 build then this one. (1) Pilots that started a
  second opening: 6 of 144 (89 pilot-seconds in all, one of them for 50 s, in a Bottom-lane opening that ran to the
  180 s limit) then 0. (2) Fall-backs in the opening by the 24 junglers: 0 then 11 (9 junglers); by the lane roles and
  the flex pilots 26 then 27. (3) Rally-seat pilots with their goal off the opening spot for more than 10 s: 47 of 48
  (40 s on average) then 0 of 48 (0.4 s); the share of the window from 60 s to the first wave that these seats spend
  within 1,500 of their own Crossing 8% then 34% (the other seats 26% then 29%); pilots within 1,500 of their own
  Crossing, all three Crossings of a team together, at 80 s 2.5 (Aurelian) and 2.7 (Vhorr) then 4.2 and 5.2, at 100 s
  2.8 and 2.2 then 3.7 and 4.2. Per lane that is still only 1 to 2 pilots, because about three quarters of the pilots
  (105 of 144 before, 106 after) retreat to repair between 44 s and 110 s (median first retreat at 53 s): the early
  fight, not the waypoint, empties the Crossings, in both builds. (4) The Crossing that got each team's first turret,
  seeds 301-306, then and now: Aurelian Top 6, Middle 0, Bottom 0, then Top 3, Middle 1, Bottom 1 (none by 25:00 in
  1); Vhorr Top 1, Middle 4, Bottom 1, then Top 1, Middle 3, Bottom 0 (none in 2). The same-every-match split is gone.
  Three of the 12 teams built no Crossing turret by 25:00 (round 2: none): in seeds 301 and 306 Aurelian took all
  three Crossings by about 12 minutes while Vhorr had 75 to 95 credits at 5 minutes, and in seed 304 Vhorr took all
  three by 14.6 minutes; 21 of the 36 team-and-node slots had a turret by 25:00 (round 2: 23). The opening itself is
  as before: first wave at the Crossing 93 to 119 s on average (the Top lane up to 151 s in one seed), no shop trip
  before the wave, pilot kills and deaths in the 300 s 160 and 191 then 149 and 193.
- Full matches (2,400 s, seeds 301-306, fun_probe, pilot_audit, admiral_audit), the round-2 build then this one: kills
  per minute 8.09 then 8.74 (+8%), deaths per pilot per 10 minutes 3.37 then 3.64 (+8%), first blood at minute 0.61
  both, fights per 10 minutes 6.19 then 6.12, mining drones lost per 10 team-minutes 26.1 then 27.2 (+4%), shots into
  rocks per 100 pilot-minutes 4.69 then 4.63, admiral decisions per minute 3.08 then 2.75 (back inside the 0.5 to 3.0
  band; round 2 was just above it), rock contact 0.83 then 0.94 ship-seconds per pilot-minute (+13%), crash deaths 1
  then 7 events (the v0.2.0 baseline had 6), stuck episodes per 100 pilot-minutes 3.10 then 4.63 (134 then 215; before
  5:00 23 then 15, before 10:00 30 then 28). The rise in stuck episodes and rock contact is one Vhorr bomber in seed
  306 that sat in the rocks at (28,356; 15,070) from 6:35 to the end (63 of the 215 episodes, 1,784 stuck seconds,
  about 690 of the 4,379 rock-contact ship-seconds): without it 152 episodes, 3.3 per 100 pilot-minutes (+6%), rock
  contact 0.79 (-4%); it is the known asteroid snag, not fixed. Matches that end within 40 minutes: 2 of 6 (both won
  by Vhorr), then 0 of 6 (the gate flags the fall, as in the first round; n is small). FUN 64.4 then 60.3 (for
  information; its "decisive match arc" ingredient is 0 without an ended match). Rule-set presets (1,200 s, seeds
  301-303, within and pick): all 6 matches ran to 20:00 with their result line and no script error (node_persist on
  for pick, off for within). Script errors in every log of this round: 0.
- Determinism of this build (seed 7): normal 900 s, two runs identical, 180 hash lines, END t=900 234 units f957a77a
  (the round-2 build: 6f268d9d; the first line that differs is t=65, when the AI waypoint stopped pulling the rally
  seats); late 300 s, two runs identical, 60 hash lines, END t=1800 203 units ccbb4bde, the same as round 2 on all 60
  lines (the opening and the Crossing turret choice do not touch the late start). The normal hash is the new baseline
  for v0.2.1; the late one is unchanged.
- New test tests/opening_fix_check.gd (--test=opening_fix_check): in an all-AI match it checks that the AI waypoint
  leaves the rally seats on their opening spots, that a waypoint placed with by_human pulls Aurelian's seats away and
  leaves Vhorr's, that a pilot whose opening was put back is done at once when its wave has died, and that the order
  the admiral tries the Crossings in for its first turret equals an independent count of its own ships (0 failures on
  seeds 301-306). tests/opening_probe.gd now also records, per pilot, when its opening ended (t_done), the seconds it
  was back in an opening after its lane's first wave had arrived (reopen_s, one OPENING_FLAG line for each pilot above
  1 s), its fall-backs, the seconds it held its Crossing (held_s) and the seconds its goal was off the opening spot
  (goal_off_s), and takes its snapshots per lane; tests/crossing_probe.gd gives the first turret of each team at any
  Crossing with the build check's answer and the own ships near each Crossing.

### 2026-10-18: pilots can look around the whole map; Space centers the camera on your ship (M-04, for v0.2.1)

- The request (the user, Sunday): all pilots, not only the Admiral, scroll their screen around the entire map, and the space bar centers the camera on your ship; holding it keeps the camera centered as the ship moves. The user's answer on the fire key was "Mouse only": the left mouse button fires and Space only moves the camera.
- Every seat now starts with the free camera (CameraRig). A pilot pans with a screen edge (within 6 pixels), the middle-mouse drag and minimap clicks (look_at_point works for pilots). W / A / S / D / Q / E still fly the ship while the human flies and pan the camera only when there is no ship, as for the Admiral. A pilot's zoom-out limit is unchanged (PILOT_VIEW_WIDTH by ship size times the zoom_max factor): the new CameraRig.zoom_limited() keeps it (ZoomMaxFeature asks it too). The Admiral's free camera and C switch, and the spectator's camera, are unchanged.
- New input action center_on_ship (Space). Tap: the camera goes to the ship; with no ship (docked or dead) it goes to the spot in front of the mothership that the old follow camera used. Hold: every frame the camera's goal is the ship's place plus its speed / 12, which is how far the slide lags, so a ship flying steadily stays in the middle; let go: the camera is free again from where it is. A spectator has no ship, so Space does nothing for them.
- A pilot's camera also jumps to the ship when it launches (a hyperspace jump too), so a new ship is never off screen after the camera was left elsewhere. An Admiral who launches keeps their camera (C15).
- Space left "fire": the left mouse button is the only fire control. Nothing else read Space (searched scripts, scenes, tests, project.godot and the web export preset).
- The follow camera (look-ahead, edge peek) stays: the Admiral's C key still uses it, so no code became dead. Texts changed: the key line (pilot and Admiral), the help pages (Shooting, Camera, Admiral), the start screen controls, README Controls and Tests, DESIGN A15, CODE_GUIDE (CameraRig paragraph, glossary, tests), the zoom_max manifest line (E6).
- New test tests/camera_check.gd (one run per seat: pilot, admiral, spectator). It presses and releases Space and moves the mouse through Godot's own input events and checks the key map, the docked tap, the launch jump, look_at_point, the edge pan, the middle drag, tap, hold (the ship stays within 8 units of the middle at 900 units a second), release, Space not firing, and the zoom-out limits. Two throw-away mutations showed the checks bite: Space back on "fire" fails two checks, and dropping the speed term of the hold fails the hold check (83 units off).
- The pilot ui tour holds Space for the whole tour (tests/ui_tour.gd): a fresh window's mouse sits at (0, 0), where the free camera pans into the map corner, so the pictures would otherwise show an empty map instead of the ship.
- Results: run_checks ALL OK (load_all, bot_pilot, support_probe, both ui tours); camera_check 0 failures for the pilot, the Admiral and the spectator seat; zoom_check still 5,200 units across (7,800 with zoom_max:wide, 150 counted frames, for a pilot and for a made-up human with free = false); the layout check at six window sizes for both roles clean (it was clean before); det_hash with the drawing code running (det_check.ps1 -Full, because --sim-only switches the camera off): normal IDENTICAL over 180 lines (END 749aa6eb), late IDENTICAL over 60 lines (END 4bccf106) against v0.2.0's baselines, no script errors. Only test files changed after the det runs.
- v0.2.1 release (Sun 2026-10-18). A fresh Fable review of the opening fix's round 3 (5e1e926..e87398b) found no defects. It noted three readings: two the user confirmed (the Admiral counts its pilots and its minions near each Crossing, and the rule applies whenever it holds no Crossing turret, rebuilds included), and one that is bounded (a jungler finishing its fall-back flies to its camp without fighting for at most 4 s). The user kept the camera jump at launch and shipped the bloodier opening as is. Against v0.2.0 on seeds 301-306 (40-minute AI matches): stuck episodes 2.82 -> 4.63 per 100 pilot-min (63 of 215 from one bomber stuck from 6:35 in seed 306; +16% without it), rock contact +2%, crash deaths 6 -> 7, matches ended 1/6 -> 0/6, FUN 64.1 -> 60.3.
- v0.2.1 release review (Opus, Sun 2026-10-18, the release branch against main 7e681a6): no defect in the AI change. In the camera change one low defect (a middle drag stayed on after a focus loss) and two unverified readings of the same kind (the edge pan with the pointer outside the window, fire held through a focus loss); all three are fixed (M-04: CameraRig._notification(), _pointer_inside(), World._notification()). Public text fixed: the opening's kills and deaths were round 1's (now the shipped build's 149 / 193, retreats 159); the human Admiral's flag in the opening is new (v0.2.0 rallied nobody before 10:00); the flex pilot's rotation starts on the top lane for the whole match; no local branch names in the notes; the AI opening fix entries above got their own heading. Checks after the fix (the release branch at 4532997): run_checks ALL OK (load_all, bot_pilot, support_probe, both ui tours); det_check -Full normal IDENTICAL over 180 lines and late IDENTICAL over 60 (END f957a77a and ccbb4bde, as before the fix); camera_check 0 failures for the pilot, the Admiral and the spectator; zoom_check 5,200 units across; no script errors. Only documents changed after these checks.
### 2026-10-19: hotfix: the mouse wheel over a menu no longer zooms the camera behind it

- The report (the user, as the Admiral at 1920x1080): scrolling the Tab menu (the Admiral board) with the mouse wheel
  also zoomed the camera in and out behind it.
- The cause: Godot passes a wheel turn up through panels that stop the mouse (Control.mouse_force_pass_scroll_events
  is on by default, so nested scroll areas work). A menu's scroll area takes a turn only when it really scrolls, so
  every turn past the top or the bottom of a list, and every turn over a menu's frame, went on to the game, and
  CameraRig._unhandled_input zoomed.
- The fix: the Admiral board, the hangar, the help, the scoreboard and the end screen turn the property off on their
  root. A wheel turn over them now scrolls the menu or does nothing. Cards and buttons inside still pass the wheel to
  their list, so the lists scroll as before; the wheel over the open map, the minimap and the HUD's edges zooms as
  before. Pilots notice it too: the wheel over the hangar (open while docked or dead), the help or the held-Tab
  scoreboard no longer zooms the map behind it.
- New test tests/wheel_check.gd (run once per seat): it opens each menu alone at 1920x1080 (the board on all five
  tabs, the hangar on all four, the help on every page, the scoreboard, the end screen), turns the wheel 30 notches
  down and 30 up at the menu's middle, top and bottom, and fails any menu where a turn changed the camera's zoom goal,
  or where a list taller than its scroll area did not scroll. A control turn over the open map must zoom.
- Before the fix: 13 of 13 menus failed for the Admiral and 8 of 8 for a pilot (174 to 180 of 180 turns zoomed the
  camera); with the four menus fixed and the end screen not yet, only the end screen failed (180 of 180). After:
  0 failures for both seats.
- Results: run_checks ALL OK (load_all, bot_pilot, support_probe, both ui tours, both wheel checks); det_check -Full
  normal IDENTICAL over 180 lines and late IDENTICAL over 60 against v0.2.1's release runs, no script errors. The
  change is a UI input setting: the simulation never reads it, and the HUD is not built in simulation runs.

### 2026-10-20: ships stuck in the asteroids (main, for v0.2.2)

- The request (the user, Saturday, with a screenshot of the browser game): "I have here a screenshot showing a ship stuck
  in the asteroids. Playing the match further notes more of these instances. Come up with a plan to try and fix them."
  (The screenshot stays private; it was not copied anywhere.)
- The study (12 cloud matches, seeds 301-312, v0.1.0, and PC replays): 340 stuck episodes (28 a match), half of them
  rock-bound (160), half stalls in the open lane that are slow turning and waiting, not rocks. Three causes were
  confirmed. (1) A route's first leg ended at a route dot hidden behind rocks: RouteGraph.nearest() took the nearest dot
  when none of the 8 nearest was visible, and the plain unstick planned the same route from the same spot (112 of the 160
  rock-bound episodes). (2) PilotEscape threw away exits nearer than 120 units, sent a ship that saw no dot to the
  farthest cell of a closed region, and left the route empty during an escape (the audit's "noroute" counts were
  escapes, not map gaps). (3) fight() flew small ships, mostly bombers, straight at a target through the lane wall, and
  its stuck timer lived only in travel(). A ship stuck for a whole match (a "trap") happened in about one match in four.
- Four changes, one commit each:
  1. The route's way onto the graph is the cheapest dot the ship can fly to: RouteGraph.entry() weighs "distance to
     the dot + cost of the rest of the route" (costs_to(), one search from the goal's dot, remembered) among the dots
     within 2,500 units whose straight line is clear of every rock by the ship's radius plus 6; path() takes the
     radius, minions and drones are untouched. With no such dot (no_entry) PilotFlight.travel() plans an escape at once
     (PilotEscape.plan_now()) and plans the route again from where it ends.
  2. A real unstick: PilotTrail (new) keeps up to 24 breadcrumbs of free spots; the first stall (4 s without
     progress, PilotFlight.stall()) flies the track back to the first spot where the ship can join the route graph and
     plans again; a stall also happens in a fight (PilotFlight.watch_pinned(): forward thrust without moving for 3 s,
     then the target is given up for 6 s); a second stall in the same place plans an escape as before. A stall bans the
     route dot the ship was flying to for 60 s, so the new route goes round it (RouteGraph.node_path() and path() take
     banned dots; another jungle gate): a trace of a whole match showed a ship overshooting one gate for 1,000 s.
  3. The escape planner: any exit to a dot is taken, however near (cells are tested from 30 units out); when the
     coarse grid sees no dot, a fine grid over 800 units looks again before the ship settles for the farthest cell;
     the 8 dots it looks for are the cheapest to join on the way to the goal; the brain keeps a route (the escape's
     waypoints, then the route from its dot) while an escape flies; a grid with many cells costs more work units.
  4. Small ships do not take a target (pick_target, prey) or a turret (push_target: its stand-off point) with a rock
     between, and fight() flies travel() to the goal instead of straight at a hidden target more than 450 units away.
  New numbers, all named constants with notes: RouteGraph ENTRY_RANGE 2500, ENTRY_TRIES 12, ENTRY_MARGIN 6, ENTRY_START
  12; PilotFlight REPLAN_WAIT 1, PINNED_FWD 0.5, PINNED_SPEED 30, PINNED_T 3, BAN_T 60; PilotTrail STEP 50, MAX_CRUMBS
  24; PilotEscape PLAN_RETRY 3, RETRACE_MIN 40, RETRACE_TIME 10, FAR_MIN 120, TEST_MIN 30, COARSE_HALF 1100,
  COARSE_MARGIN 4, FINE_HALF 800, FINE_CELL 6, FINE_MARGIN 0.4, CANDIDATE_DOTS 8; PilotCombat HIDDEN_CLOSE 450.
- New and changed test tools (no game change): tests/pilot_audit.gd now writes, for every stuck episode, the pilot, the
  rock class (on a rock, next to one, in the open), the end time and why, and the seconds of rock contact; the counters
  stuck_class_*, stuck_team_*, no_route_escape and no_route_plain (an empty path while an escape flies, apart from a
  really missing route), escape_samples, and the "traps" list with traps, trap_seconds, trap_rock_seconds and
  traps_farming (a ship that stays within 400 units for 60 s while it scrapes a rock for 2 s; mostly fighting = a camp
  being farmed). tests/stuck_trace2.gd is the trace harness of the study (EPJ, TRAPJ, TRACE, ESC, TOP_ROCK and TOP_ESC
  lines; pictures in a window). tests/stuck_spots.gd replays 91 old stuck spots in 3 waves, 100 s each: with the old
  code 5.7 of 91 ships were still within 400 units after 100 s (mean of 3 seeds) and 1,193 ship-seconds were spent
  near the start; after the four changes 0.7 and 389 (seconds of rock contact 922 -> 277).
- PC matches (looking only; 3 to 4 matches of 1,500 s, pilot_audit, seeds 401-404): the ships that sat in the same
  wall notches in the old code (a fighter at the Drake notch for 727 s, one at the tl crack for 1,274 s) no longer do;
  seconds of rock contact per match 818 -> about 300, traps 4 -> 0, no_route_far 1,281 -> 11 (escapes no longer empty
  the route), jungle share of pilot time 46.5% -> 50.4%, monster kills by pilots 446 -> 468 (3 matches each).