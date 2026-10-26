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

### 2026-10-17: user test fork, stage 0 (test tools and yardsticks)
- Stage 0 of docs/USER_FORK_PLAN.md: the tools every later stage is judged with. Tools only: the game plays the
  same (det_hash IDENTICAL to v0.1.0: normal END 749aa6eb over 180 lines, late END 4bccf106 over 60 lines).
- tests/map_check.gd (with tests/lib/map_check_*.gd): checks the built map against MapLayout (size, lanes, the 24
  jungle gates, strike and drone roads, clear space around nodes and camps, left-right mirror) and prints MAP_JSON.
  Today's map: 0 failures, 1 warning (22 of 24 gates let a corvette-sized ship squeeze through; DESIGN.md says
  corvettes cannot enter the jungle). --strict-choke turns that warning into a failure.
- tests/perf_probe.gd: --perf-worst (no respawn waits, the AI never flies home to shop) and one PERF_JSON line
  per run (mean ms per game second, CPU time, slowest ticks, p99/p99.9, share of ticks over 33 ms).
- --record-stats=<file>: StatsRecorder (scripts/stats_recorder.gd) and StatsPilotRecord
  (scripts/stats_pilot_record.gd) record the human and every AI pilot once a minute and at the end. Watch only:
  det_hash with it on is IDENTICAL. Off unless the option is given; it writes only that file.
- tools/utf_compare.py: PASS or FLAG per plan gate for two folders of runs. tests/admiral_audit.gd also prints
  idle-drone counters. remake/.gitattributes keeps *.import files LF, so an export's content hash survives
  Godot's first import.
- Cloud yardstick submitted: fun_probe, pilot_audit and admiral_audit on seeds 301-312 (batch utf0_yard).

### 2026-10-17: user test fork, the alien Cinder look
- The user asked for the red team to look more alien, inspired by the Vanduul of Star Citizen/Squadron 42 (all
  shapes original: no images, assets or names from the game). They approved the side-by-side gallery ("Approve
  all") and kept the redder fill on tiny and far ships; the --classic-red option was dropped.
- Drawing only, Cinder only: scripts/data/cinder_shapes.gd (the shape tables: HULLS, MINIONS, UNITS, MOTHERSHIP)
  and scripts/entities/cinder_paint.gd (draws them; a simpler outline for ships a few pixels long). ShipVisual and
  UnitVisual call CinderPaint for Cinder units and keep their own drawing for Aurelian. Sizes, hit circles and
  every number stay as before: det_hash IDENTICAL to v0.1.0 (normal END 749aa6eb over 180 lines, late END
  4bccf106 over 60 lines).
- Cost: about +1.3 ms per frame (+3%) in a real match on this PC (+7.1 ms, +11%, in a 280-unit crowd test).
- tests/hull_gallery.gd (with tests/lib/gallery_checks.gd, gallery_measure.gd, gallery_fights.gd): pictures of
  every unit of both teams (lineups, in-match fights), the shape checks (--check: every polygon fills, every
  outline within 10% of its Aurelian size) and the frame-time tests (--bench, --live).
- Found on the way: World.unit_hash.query() can return a unit freed in the same frame, so a typed loop over it
  can stop with "previously freed instance". The gallery guards with is_instance_valid(); other typed loops over
  the grid have the same rare risk.
- Merged into the fork as d4fc59b after the gates (run_checks ALL OK, the export stamp resolves after the import,
  det IDENTICAL). To add a hull, give it a CinderShapes.HULLS entry too (without one Cinder draws it as the fighter).

### 2026-10-17: a human observation from the user's own test run (no action yet)
- After a 20-minute all-AI match on the user test fork (seed 7, --speed=4, 1280x720), the user wrote: "in that match
  only two fights qualified as big in 20 minutes, both motherships at 100% at 20:00, and the 16:00 and 20:00 frames
  showed a nearly empty map." They asked for it to be kept for the design notes as an observation, not a bug. No
  action is planned yet.
- Facts that go with it, so the note is not read wrongly later (nothing to do about them now): "big" there is the hull
  gallery's own bar for taking pictures (a fight score of at least 9 with both teams in the same spot, plus 4 for every
  fight already photographed: GalleryFights.MIN_SCORE and SCORE_STEP), so it counts photographed fights, not all
  fights. The 16:00 and 20:00 frames came from tests/spectate_shots.gd, whose camera was off target in that run (fixed
  in the same branch: it now freezes its camera and skips freed units). The run's own log counted 256 units at 16:00
  (23 pilot ships, 156 minions). A re-run on the fixed tour (same seed and settings, real-time frames so not bit for
  bit the same match) had 22 units in view at 16:00 and at 20:00 (4 pilot ships, 17 minions each).

### 2026-10-17: user test fork, the display changes (stretch, minimum size, fullscreen key, hangar)
- The user's report: at 1024x600 the ship readout covered the gear row and key bar and the kill feed covered
  "Cinder (enemy)"; at 1366x768 the help panel sat over the bottom HUD with text bleeding through; at 1920x1061 the
  hangar was mostly empty with 13 px text. The cause: the screens were laid out in real pixels, so every window
  size was a different layout.
- Stretch: project.godot now has display/window/stretch/mode = canvas_items and aspect = expand on the 1280x720
  base. Godot scales the whole picture from the base, so every screen is laid out for at least 1280x720 base
  pixels; a window wider than 16:9 adds room on the wide side, a taller one on the tall side. The camera zoom
  limits were always worked out from the viewport's width, so how many world units fit across the screen never
  depended on the window size; what changes is that the HUD now grows with the window instead of staying 13 px.
- Minimum window size: Godot 4.7 has no project setting for it, so WindowMode.apply_minimum_size()
  (scripts/autoload/window_mode.gd) sets Window.min_size = 1280x720 from Game._ready(). It works with the
  stretch: a window asked for 1024x600 opens at 1280x720. --headless runs skip it.
- Fullscreen: F11 and Alt+Enter (Alt+keypad Enter) toggle borderless fullscreen
  (DisplayServer.WINDOW_MODE_FULLSCREEN; it goes back to window or maximised, whichever it was). The action
  "toggle_fullscreen" is defined in GameInputMap; Game._input() passes every event to WindowMode.handle_input(),
  which also marks the key used. In the web build only Alt+Enter is bound (the browser owns F11), and the call
  runs inside an input callback, as browsers require.
- Big panels vs the HUD, in HudPanels: with the hangar open in flight, its gear slot row sat on the ship readout's
  energy routing buttons (base size, so the stretch cannot fix it), and the help page and Admiral board sat on the
  readout, the key line and the top corner too. fit_panels() sets the bottom edge of the hangar, help page and
  Admiral board: 148 px above the bottom (readout height + 16) while the readout shows, 76 px (key line and gear
  slots stay visible) otherwise, called from Hud._refresh(). PANEL_TOP (92 px) starts all three below the "me"
  panel and the top bar. The hangar's scroll minimum went from 300 to 240 px. Still overlapping at base size:
  the panels cover about 55 px of the minimap's top-left while the readout shows, and the toast sits on the
  readout's last line while a panel is open in flight.
- Code that reads sizes or mouse positions, all in viewport units (base pixels) under the stretch: CameraRig
  (zoom limits, edge peek 16 px and edge pan 6 px, drag pan), Minimap (camera rectangle; clicks are local to the
  control), CommandOverlay (get_global_mouse_position), World.mouse_world(), ProjectilesDraw and Sfx (view size).
  Nothing reads physical pixels (no DisplayServer.window_get_size in the game). tests/display_check.gd checks
  the stretch, the minimum size, the keys and the mouse mapping.
- No simulation code changed: det_hash IDENTICAL to v0.1.0 (normal END 749aa6eb over 180 lines, late END
  4bccf106 over 60 lines).
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

### 2026-10-18: user test fork, main merged in (v0.2.0 and the release-notes workflow)
- The user (Sun ~01:18) asked that the improvements in main's pipeline come into the test branch, as long as they
  do not conflict with the changes the user asked for here. The user (Sun ~10:25): this was one time, so the two
  branches start at the same place; main's current plan (v0.2.1, v0.2.2) merges in when it ships, and after that
  every change goes through this branch first, then to main. This merge brings in main: v0.2.0 (the rule sets, the
  Vhorr name on screen, the screen layout fix) and the release-notes workflow.
- One real clash: v0.2.0's layout fix and this branch's display change both move the hangar, the Admiral board and
  the help so they clear the HUD. v0.2.0 let a panel reach down to a strip at the bottom and hid the ship readout and
  the gear slots under it; this branch stops the panel above them, so hull, shields and energy stay in sight in
  flight. This branch's rule stays. HudLayout (from v0.2.0) now places the panels, and panel_bottom() returns this
  branch's room: 148 px while the readout shows (READOUT_ROOM), 76 px otherwise (KEYBAR_ROOM); apply() hides the
  readout and the gear slots only under the scoreboard, which reaches the bottom edge. fit_panels() is gone, and the
  panels' top edge is HudLayout.panel_top() (under the top bar and the "me" panel, about 95 px) instead of the fixed
  PANEL_TOP of 92 px. The pop-up hint (HudLayout.toast_spot(), a follow-up commit): with a panel open it drops into
  the strip under the panel, in the middle, or, while the readout shows there, in the bottom-right corner beside it
  (the minimap's place; the minimap is hidden under a panel); the first version left it 150 px up, over the help
  page's last lines, which the layout checker caught. The hangar's scroll area keeps this branch's 240 px minimum
  (v0.2.0 had 120).
- Everything else in v0.2.0 comes in whole: the panels' card widths from the window (UiKit.panel_width) and
  on_window_resized(), the top bar kept clear of the "me" panel, the kill feed under the top bar, the scoreboard's
  room and scrolling, the start screen and the board's card wrap at narrow sizes, no hint over the end screen, the
  layout tests (ui_tour --ui-size and --dump-layout, tools/ui_layout_check.py), the rule sets and presets (opt-in,
  the default game unchanged) and the Vhorr name.

### 2026-10-17/18: the AI opening fix, rounds 1-3 (M-03, for v0.2.1; rounds 1 and 2 have been in the test branch since 2026-10-18, round 3 comes with the v0.2.1 merge)

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

### 2026-10-18: user test fork, the AI opening fix merged in ahead of v0.2.1
- The AI opening fix (the entry above, branch local/opening-fix) is built for v0.2.1 and waits for its review; it
  comes into the test branch now (the user's one-time request of Sun ~01:18, see the entry above), so the user
  plays the new opening. Main holds v0.2.0 as one squashed
  commit, so v0.2.0's own history (local/release-v020, the same files) was recorded here first; the opening fix then
  merged on its real base (77f7073) and brought only its own files: the AI (pilot_goals, pilot_ai, pilot_shopping,
  admiral_builder), rules.gd's opening constants, two probe tests (opening_probe, crossing_probe) and docs. No file
  that the test branch's own changes touch. Fixes from its review reach this branch with the v0.2.1 merge.
- Checks (exports of the merges and of 0e7af5f, the hint fix): every export imports clean (no script errors);
  run_checks ALL OK on the merged build and on 0e7af5f (load_all, bot_pilot, support_probe, both HUD tours);
  doc_check clean on every changed script; display_check 0 failures (the keys, the stretch settings). The screen
  layout: the UI tour's layout dump at six window sizes (1280x720, 1366x657, 1024x600, 1920x1080, 2560x1080,
  1280x1024; under the stretch these are laid out at 1280x720, 1497x720, 1280x750, 1280x720, 1706x720 and 1280x1024)
  for pilot and admiral, read by tools/ui_layout_check.py: clean at every size for both roles (the first merge showed 3 COVERED, the hint over the help page's last lines in flight, fixed by 0e7af5f). Determinism: the main merge alone (d9ff71b) is
  IDENTICAL to v0.1.0 (normal 180 lines, END 749aa6eb; late 60 lines, END 4bccf106), so v0.2.0's default game and
  this branch's own changes still play like v0.1.0 together; the merged build (f68e2d1) is IDENTICAL line for line to
  both runs of local/opening-fix (normal END 6f268d9d over 180 lines, late END ccbb4bde over 60), so the merge kept
  the opening fix exactly. Those two runs are this branch's new determinism baselines.

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
- On the test branch only (found by the merge's layout check, which was clean before it): the pilot's key line is now two lines tall, and HudLayout.panel_bottom() (the T-04 rule) assumed one line (KEYBAR_ROOM 76), so the hangar covered the key line at every window size. panel_bottom() now takes the larger of KEYBAR_ROOM and the real HudSlots height plus the 8 + 8 pixel margins, so a longer key line moves the panels up by itself.

### 2026-10-18: T-02 round 1: the Vhorr engine flames are a quarter smaller (the user's note)

- The user tried the alien look in the game: "I tested the Vhorr ship designs and they look great with one note. The
  engine effects are too large and overwhelm the design. Reduce the size of the engine effects on the test branch by
  25%."
- ShipVisual.CINDER_JET_SIZE = 0.75: a Cinder ship's three flame emitters (main engine and both side thrusters) get dots
  25% smaller and 25% less speed, so each plume is a quarter shorter and narrower. Aurelian's flames and the hull drawing
  (with its small engine lights) are unchanged.
- Checks: run_checks ALL OK; the hull gallery's shape checks (93 polygons, 20 sizes) pass before and after; det_hash with
  the drawing code running (det_check.ps1 -Full, --sim-only=0) against the test branch's baselines:
  normal IDENTICAL over 180 lines; late IDENTICAL over 60 lines.
- Before/after pictures (hull gallery, play and near zoom) went to the user with the merge.

### 2026-10-18: T-03 round 1: the hull gallery's team headers and name tags (the user's note 11)

- The user's note on Sunday's fork pictures: "hull_gallery labels Cinder instead of Rules.TEAM_DISPLAY;
  LOGISTICS/SUPPORT CORVETTE labels overlap at mid and play zoom."
- tests/hull_gallery.gd: the two team headers come from Rules.TEAM_DISPLAY (AURELIAN, VHORR). A pilot ship's slot in a
  lineup row is now as wide as its in-game name tag when the tag shows (ShipVisual writes it from zoom 0.45 on), so
  neighbouring tags never overlap; at play and far zoom no tag shows and the rows are unchanged.
- Test-only (no game code). Checks: run_checks ALL OK; the gallery's shape checks (93 polygons, 20 sizes) pass; 29
  pictures, no script errors. Before/after sheets (mid and play zoom) went to the user with the merge.
### 2026-10-18: user test fork, smaller minion waves per lane and new minion names (T-07)

- The user's request (test fork only; it walks back the earlier "no minions in the test branch" idea): keep the minion
  waves, but smaller, and rename the ships, which "should be flying weaker versions of the standard ships". The top and
  bottom lanes get 3 fighters, 1 bomber and 1 corvette; the middle lane gets one corvette more than it had; the
  Fighter becomes "Snub-Fighter", the Bomber "Light Bomber" and the Corvette "Patrol Leader". DESIGN C26 holds the
  decision and the user's words. One variable at a time: this item changes the waves and the names, nothing else.
- Waves as built (Minions.OUTER_WAVE, MID_WAVE, WAVES and Minions.wave_for(lane), which replace the single Minions.WAVE;
  MinionDirector._queue_wave sends each lane its own): top and bottom 1 Patrol Leader, 3 Snub-Fighters, 1 Light Bomber
  (5 ships); middle 2 Patrol Leaders, 5 Snub-Fighters, 4 Light Bombers (11 ships). A team sends 21 minions a wave
  instead of 30. The order within a lane is as before (corvettes first, 0.35 s apart, the research corvettes last).
  The first wave (0:45), the 35 s gap, every minion number, the Fleet Command Module (up to 30 bought minions) and its
  prices are unchanged. The wave still marches at the Patrol Leader's pace (FORMATION_SPEED 330): every lane's wave
  has one.
- Escort Wing still adds one Patrol Leader to every lane's wave (6, 12 and 6 ships once researched). Under
  `escort_wing:upgrade` the first Patrol Leader of each lane's wave is upgraded (it used to be every corvette of the
  wave, which was one). The lane-breach modules (off by default) serve the first corvette of a wave and ignore a
  second one, which they already did. Checked in matches that start at 25:00 with the research done (lane_probe
  --late, 5 waves): the default sent 2 Patrol Leaders, 3 Snub-Fighters and 1 Light Bomber a wave down the top and
  bottom lanes and 3, 5 and 4 down the middle lane; `escort_wing:upgrade` sent the plain waves (1/3/1 and 2/5/4) and
  upgraded 30 Patrol Leaders in those 5 waves (one per lane and wave, 3 lanes, 2 teams).
- The names (display only: the type ids `fighter`, `bomber`, `corvette`, the class names and the research name Escort
  Wing stay). Player-visible strings: the labels in Minions.TYPES (the Admiral board's Fleet tab buy rows read them);
  the help page's "Minions" paragraph (now with each lane's wave); the board's Fleet Command text; the Escort Wing
  research blurb (tech.gd) and its `escort_wing:upgrade` blurb (escort_wing.gd); the feed and banner words of the
  breach modules (breach_tracker.gd, off by default); the gun table's labels (weapons.gd, which nothing reads); the
  hull gallery's captions. Comments that used the old names were updated in minion.gd, minion_flight.gd,
  minion_director.gd, minion_boost.gd, breach.gd, breach_extra.gd, rules.gd, team_state.gd, pilot_targeting.gd,
  admiral_fleet_command.gd and feature_registry.gd. Nothing of the jungle was touched (data/jungle.gd, the help page's
  jungle section): the Scum faction track renames the carriers' craft, so the fork can show "Snub-Fighter" (minion)
  beside the carriers' "snub fighters" until both are in. README has no minion names. The older documents (release
  notes, fun research and plan, fork manifests, the user's requirements file) still describe main's wave of 10 and
  the old names, as history.
- The AI is not changed. Counts that now matter more with 5-ship waves, left as they are: PilotSenses.minions_tanking
  (3 or more minions around a turret count as tanking it), PilotSenses.minions_at_hull (3 at a mothership's hull),
  the turret backdoor rule (any attacking minion within 1,800) and fun_probe's SUPPORT_MINIONS (3).
- New test tools, both only reading the game: tests/lane_probe.gd (one LANE_JSON line: live minions and the wave front
  per team and lane every 10 s, the minions launched by type, turrets lost, last hits by type and lane, and each
  pilot's last-hit credits; --late as in fun_probe) and tests/wave_shots.gd (a windowed photo tour: one picture per
  lane of Aurelian's wave).
- Checks (exports of the tip; the game code last changed in 004e744, later commits are docs and test tools): every
  export imports clean; run_checks ALL OK (load_all, bot_pilot, support_probe, both HUD tours); doc_check clean on every
  changed script; every run log scanned, SCRIPT ERRORS 0. Determinism changes on purpose, and two runs of each kind
  agree: normal (seed 7, 900 s) 180 hash lines, END t=900 178 units e4836f89 (the earlier test-branch baseline had 233
  units, 6f268d9d); late (--late, 300 s) 46 lines, END t=1734 178 units cedeca41 (earlier: 60 lines, ccbb4bde). The late
  match now ends early: Aurelian destroys the Vhorr mothership at 1734 s, 234 s after the 25:00 start, where before it
  ran the whole 300 s. The first line that differs from the earlier baselines is t=50 (normal) and t=1510 (late), 18
  units fewer (9 fewer minions a team), so everything before the first wave is unchanged: only the waves changed.
  These runs are the test branch's new determinism baselines.
- A quick look at the effect (fun_probe and lane_probe, AI against AI, seeds 301 and 302, 1200 s each; before = the
  game as it was, after = this item; two matches each, so hints and not a measurement):
  - Minions alive per team and lane, mean over the 20 minutes, top / middle / bottom: 21.8 / 17.2 / 21.6 before and
    10.9 / 20.5 / 10.4 after (about 61 a team before, 42 after; 105 to 147 on the map at 10:00 to 19:00 before, 73
    to 105 after). The middle lane now holds half of the minions.
  - Lane pushes: the two waves on a side lane still meet near the middle of it, as before (mean front 0.46 to 0.49
    of the lane, was 0.48 to 0.49; furthest 0.71, was 0.71 to 0.79); the middle lane's waves push further (furthest
    0.92 and 0.95, was 0.72 and 0.86).
  - Turrets lost, both teams: 6 and 4 before, 3 and 5 after. Before, 9 of the 10 fell on the top and bottom lanes; now
    7 of the 8 fell on the middle lane and 1 on the top. Aurelian's middle inner turret fell 6 times in the two
    matches (once before).
  - Last-hit credits: the minion bounties paid to all 24 pilots in a match were 6,532 and 7,948 before and 5,612 and
    5,811 after (the waves are worth 21% less, 442 credits against 561 for the 3 lanes of a wave). The mean per pilot
    was 241 and 351 for Aurelian, 303 and 311 for Vhorr before, and 265 and 307 for Aurelian, 203 and 177 for Vhorr
    after; Vhorr pilots' last hits fell from 181 and 176 to 92 and 93 while Aurelian's stayed (130 and 190 to 135
    and 155), which two seeds cannot explain.
  - Odd: pilot ships die more, 111 and 108 times before and 141 and 137 after (kills per minute 5.5 to 7.0; time
    spent dead 5.6% to 7.3%), 34 and 27 of the deaths by minions and 93 and 98 by pilots (was 22, 27 and 78, 78): with
    fewer minions to shoot, the pilots shoot each other more. The matches did not end in 20 minutes either way. The
    fun meter went from 61.1 to 58.8; its one flagged ingredient (suspense, -21.5) rests on two matches. The first wave
    still reaches the side lanes' Crossings at about 110 s, before and after (opening_probe), so the AI opening is
    unchanged.

### 2026-10-18: T-22: ship_action_shots joins the test branch (the user's note 12, "Yes")

- The user's note on Sunday's fork pictures: "Consider adopting the side test ship_action_shots.gd (one picture per
  hull per team while an enemy is near; --late for capitals) as a test-only fork item". Their answer: "Yes".
- tests/ship_action_shots.gd: during an AI match it photographs one ship of every hull type for each team while an
  enemy is near it, with a caption; fallback pictures for hulls that never met an enemy. Run command and options in its
  header. The code is the side session's, unchanged; only the header and the doc comments are new (doc_check clean).
- Test-only (no game code). First runs: seed 7 for 20 minutes at speed 4, and --late at seed 11 for the capital ships.
### 2026-10-18: user test fork, plain minion designs that differ from the pilot ships (T-08)
- The user asked, verbatim: "Each of the minion ships should have a visual design distinct from the near equivalent pilot
  ships, a more simple design to visually represent their more basic quality." The three lane minions (type ids "fighter",
  "bomber" and "corvette"; the waves item names them Snub-Fighter, Light Bomber and Patrol Leader) were scaled-down copies of
  the pilot ships' darts and hexagons (Aurelian) and of the pilot shapes' horns and jaws (Vhorr, the red team).
- Drawing only. Aurelian: a new script, scripts/data/minion_shapes.gd (MinionShapes), holds three plain outlines, each with a
  flat tail: the Snub-Fighter is a blunt wedge (4 corners), the Light Bomber a squat box with its nose corners cut off (6) and
  the Patrol Leader a plain triangle (3). UnitVisual._draw_minion fills each with the team colour mixed into the hull colour
  (MinionShapes.FILL_MIX, 0.32) and outlines it at 1.3 px; a pilot ship is a dark hull seen through a 1.4 px outline.
  Vhorr: CinderShapes.MINIONS has three new smooth shells without horns, claws or plates (Spore, Larva and Cocoon: 16, 16 and
  22 outline points instead of 28, 18 and 32, and 8, 8 and 10 instead of 14, 12 and 11 for the tiny drawing), each with one
  engine light and the Cocoon with one spine line. CinderPaint reads a new optional "body" number of a shape, the least red its
  fill may be (0.35 for the minions), so they stay solid bodies next to the dark pilot hulls.
- Unchanged: hit circles, mount positions, the drawn size of each minion (each outline within 10% of the old length and width:
  1.6 x 1.1, 1.75 x 1.0 and 1.9 x 1.16 units against 1.6 x 1.1, 1.8 x 1.0 and 2.0 x 1.1) and every number the simulation
  reads. The jungle's snub fighters and derelict camps still use UnitVisual.MINION_SHAPES, which is not changed. The Patrol
  Leader's gun has no picture; its simpler turret graphic belongs to the turret pass.
- Why they read as basic and differ from the pilot ships. Aurelian: the pilot hulls are hollow darts and hexagons with a
  notched or pointed tail; the minions are solid plates with a flat tail, no notch, no swept wing and 3 to 6 corners. Vhorr: the
  pilot hulls are spiky, bladed and plated; the minions are smooth and rounded, with no blade and no plate. A helper measure
  (the overlap of each outline with its pilot twin after scaling both to one length, 1.0 = the same outline; it is not in the
  game) for Aurelian, old to new: Fighter 0.70 to 0.43, Bomber 0.91 to 0.62, Logistics Corvette 0.80 to 0.51 (Support Corvette
  0.59 to 0.72: by this measure the triangle is closer to that slim dart, because the measure cannot see the dart's notched tail). For Vhorr
  the measure hardly moves (the shells are about as bulky as the pilot hulls); they differ in the outline: smooth, not horned.
- New check in tests/lib/gallery_checks.gd (hull_gallery --check): "minion looks", every Aurelian minion outline has at most 6
  corners and a flat tail. The size check of the Cinder shells now compares them with MinionShapes. For the Friday redesign
  of the Aurelian pilot ships: keep the pilot hulls' pointed noses, notched or pointed tails and hollow look, and leave the
  wedge, the squat box and the plain triangle to the minions.
- Checks on commit 2c99278: run_checks ALL OK; hull_gallery checks (84 polygons, 20 sizes, 3 minion looks) 0 failures;
  doc_check clean; no script error in any log. Determinism with the drawing code running (det_check -Full, seed 7, against this
  branch's baselines): normal IDENTICAL over 180 lines (END 6f268d9d), late IDENTICAL over 60 lines (END ccbb4bde).
- Frame time, the check the alien look used: hull_gallery --bench (70 ships and 70 minions a team), the old and the new build
  taking turns five times: the draw calls are identical (2,843, 4,168 and 4,243 for the Aurelian-only, Cinder alien and Cinder
  plain looks) and the frame means are 29.1, 51.9 and 50.3 ms old against 29.6, 53.1 and 51.3 ms new over all five rounds
  (28.5, 51.0 and 49.5 against 28.5, 51.4 and 49.3 ms over the three quietest), inside the run-to-run noise of about 1 ms.
  hull_gallery --live (an 8-minute match, both builds at the same time): game work per frame 29.3 and 28.3 ms old (alien and
  plain look) against 28.5 and 28.6 ms new. No measurable cost; the outlines have fewer points and the same number of drawing
  commands.
- Pictures, as agreed in the test pipeline (no gallery before the merge): one comparison per minion type (old, new and the pilot
  ship, both teams, at the usual zoom and as a close-up) and two frames of a real match with full waves.

### 2026-10-18: T-21 stage A: where the drawing time goes (test only: part switches, a parts bench, a table maker)

- Why: the user's note 9. At 1080p the hull gallery's bench draws 70 ships and 70 minions per team at play zoom: 28.9
  ms per frame and 2,843 draw calls for the 140 Aurelian units, 51.3 ms and 4,168 draw calls for both teams (280 units),
  and a late game at speed 1 runs at 15 fps at 26:00. The user said "Go" to stage A of the frame-rate plan: say, part by
  part, what each piece of the per-unit drawing costs, before anything is changed. Stage B (the fix) starts only on a second
  go, once the table has been seen. Nothing in play changes.
- DrawParts (scripts/entities/draw_parts.gd) holds seven true/false switches, read once from --bench-off=<parts> through
  Game.opt: flames, arcs, arrow, bars, name, outline, redraw (`all` names every part, `drawing` the six drawn ones without
  the redraw). ShipVisual, UnitVisual and CinderPaint read them where they draw. With "flames" off the three emitters are
  still made (each CPUParticles2D takes one number from the shared random sequence when it is made) and are only stopped
  and hidden; with "redraw" off a picture is drawn once and kept (Godot replays it, so the draw calls stay). With no
  switch given every part is drawn exactly as before.
- The hull gallery's parts bench (tests/hull_gallery.gd --bench --bench-parts; code in tests/lib/gallery_measure.gd): the
  bench crowd, for each of the three looks, once per switch set (all drawn, each part left out alone, the six drawn parts
  left out, all left out, and an empty scene with every unit hidden), in interleaved rounds after a warm-up round, the order
  of the sets reversed every second round.
  Each measurement prints one DRAWCOST line: the frame mean and 95th percentile, script ms (the game's own _process and
  _draw work) and render ms (Godot's drawing), split at the RenderingServer's frame_pre_draw signal, Godot's own "process"
  monitor (it is refreshed once a second with the slowest frame of that second, so only a hint) and the draw calls.
  The reference crowd stands still, burns no engines and is unhurt, and at play zoom (a view 4,500 wide, zoom 0.29) no bars,
  arrows or names are drawn (they need a view narrower than about 4,340, 3,255 and 2,890 world units), so those parts would
  read nothing there. --bench-busy therefore makes the crowd drift, burn its engines and take damage like a fight, and
  --bench-view=2200 shows the bars, arrows and names. The plain --bench keeps its output and numbers.
- tools/draw_cost_table.py turns the DRAWCOST lines into the markdown table: ms per frame, script and render ms and draw
  calls saved by each part, with the share of the all-drawn total, the sum of the parts, the all-left-out floor and the raw
  means (python -B -I tools/draw_cost_table.py --selftest checks its maths).
- The official numbers come from a quiet-machine run (3 interleaved rounds per set, 1920x1080 window parked off screen,
  vsync off, through the shared match queue) that the lead's measure_quiet.ps1 does; this entry has none.
- Smoke runs on a busy PC, on the export of the merge with the test branch's tip 69bcc45 (5ffe894), one round of 90
  frames per set, so NOT the official numbers: the still crowd gives the user's bench in draw calls exactly (2,843 Aurelian
  only, 4,168 both teams) and within a few milliseconds in frame time, and every switch changes something (the arrow, bars
  and name tags only in the 2,200-wide view). The draw-call counts do not depend on how busy the PC is. For the reference
  crowd, both teams with the alien look (4,168 calls): the shield arcs are 1,680 of them (40%), the hull outlines 636 (15%),
  every drawn part together 2,316 (56%), and 1,852 stay with every part left out; the every-frame redraw saves no draw call
  at all (it costs script time, the next stage's table says how much). Aurelian only (2,843): arcs 840, outlines 420. With the
  engines burning (busy crowd) the flames add 208 calls. The empty scene (every unit hidden) already draws 1,443 calls, which
  matches MapDecor's 1,400 star circles (one drawing command each) plus a few dozen others, so the plan's gate of at most 1,200
  draw calls for 280 units cannot be met by the unit drawing alone: the starfield has to be batched too.
- Checks (exports of 5ffe894; the commits after it change no game code, only this entry, comments, the bench's empty-scene set in tests/lib and tools/draw_cost_table.py, and an export of the last one loads with load_all: 0 failures): run_checks ALL OK (load_all, bot_pilot,
  support_probe, both HUD tours); det_check.ps1 -Full (the drawing code running, --sim-only=0) against the test branch's
  baselines of 004e744 (T-07): normal IDENTICAL over 180 lines (END t=900 178 units e4836f89), late IDENTICAL over 46 lines
  (END t=1734 178 units cedeca41). One more det_hash run with the drawing code running and --bench-off=all (every part off,
  300 s) is IDENTICAL over its 60 lines too, so the switches take no number from the shared random sequence. doc_check
  clean on every changed script; every run log scanned, SCRIPT ERRORS 0.

### 2026-10-18: user test fork, v0.2.1 merged in (M-03, M-04)
- v0.2.1 came in as main released it (local/release-v021 342bc21). Main's squash of it (6781db2) has the same files and is
  recorded with an "ours" merge, so the next release merges on its real base. It brings round 3 of the AI opening fix (only a
  human admiral's waypoint pulls the opening pilots off their Crossings; each admiral builds its first Crossing turret where its
  ships are) and the free camera for pilots (Space centers on your ship; the focus-loss fix).
- Conflicts. The AI files (admiral_builder.gd, pilot_goals.gd) had no change of this branch's own, so they are now byte for
  byte the released files. game_input_map.gd: only the header comment, which now lists both F11 / Alt+Enter and Space.
  DESIGN.md: C24 and C25 carry the release's round-3 text, and C26 (the smaller waves) stays after them. CODE_GUIDE.md and
  PROGRESS.md keep both sides; a line-by-line check found no line that both sides had and the merge dropped. No rule was
  changed differently on the two sides.
- One fork-only change on top (from the camera rehearsal, 98bc3c4): HudLayout.panel_bottom() now leaves the real height of
  the key line (at least KEYBAR_ROOM) instead of a fixed 76 px, because the longer key line is two lines tall. Without it the
  layout check found 30 places where the hangar, the board or the help covered the key line. Those panels now stop a few
  pixels higher when the key line wraps.
- Checks on 98bc3c4: run_checks ALL OK, no script errors; camera_check 0 failures for pilot, Admiral and spectator; zoom_check
  5,200 units across; display_check 0 failures; the layout check at six window sizes clean for pilot and Admiral;
  opening_fix_check on seeds 301 and 302, 0 failures. Determinism (det_check -Full, seed 7, two runs each, identical to each
  other): normal 180 lines, END 06a80013; late 46 lines, END cedeca41. Against this branch's previous baselines (004e744) the
  normal match first differs at 1:05 (round 3's opening change); the late match is identical. These are this branch's new
  determinism baselines.

### 2026-10-18: user test fork, assist money (T-25)
- The request (the user, verbatim): "In the test branch, i want pilots to be able to gain some money from minion assists, not just
  kills. Same with pilot kill and jungle monster kill assists. Dont let the economy inflate." The user's answers: minion split
  "Last hit 75%, helpers 25%"; pilot kills "Inside the bounty now"; "Tonight". Recorded as DESIGN.md C27; A7 has the new rule.
- Assist money now comes out of the reward, never on top. Minions: when an enemy pilot makes the last hit, the other pilots of that
  team with at least 10% of the damage in the last 15 s are helpers. With no helper the last hitter gets all of it, as before. With
  helpers the last hitter gets 75% and the helpers share 25% by their damage. Each cut is raised by that pilot's own gear. A minion
  finished by a minion, turret or monster pays nobody, as before. The new count PilotProfile.minion_assists is only for the test
  reports (no screen shows it, p.assists stays for pilot kills); the payment reason is "minion assist" (the pilot's own earnings
  list shows it as "+N minion assist"). Pilot kills: the killer gets 2/3 of the bounty and the helpers share 1/3 in equal parts
  (before, the helpers got half the bounty on top, so a kill with helpers paid 1.5 times); no helpers: the killer gets all of it;
  no pilot made the kill (turret, minion, monster): the helpers share all of it, as before. Streaks, aces, kills, assists and
  insurance are unchanged, and so are jungle camps, turrets and every other kind.
- Tuned numbers: "minion_assist_share" (0.25) and "kill_assist_share" (1/3) are new. "assist_share" (0.5, on top) and the constant
  ASSIST_SHARE are gone: no preset, variant, feature module, test or tool ever set it (only rules.gd and economy.gd used it). The
  help page's Minions line, DESIGN.md (A7, C27), CODE_GUIDE.md and README.md are updated. tests/lib/fun_probe_economy.gd counts
  "minion assist" as pay for playing. Two variants that read payment reasons (catchup:share and bounties) do not know the new
  reason; neither is in a rule set, and both are left as they are.
- New tests: tests/income_probe.gd (income by team and reason, one INCOME_JSON line) and tests/assist_check.gd (44 exact payout
  checks: a minion alone, with one and two helpers split by damage, a hit under 10% or older than 15 s, finished by a minion, a
  turret or a pilot of its own team; a pilot kill alone, with one and two helpers, with a streak, finished by a turret or a minion;
  gear on the killer or the helper only; two end-to-end kills through the damage code; the total paid is always exactly the
  bounty). Run against the old Economy it fails 16 of the 44.
- Checks on the game code of 18016c0 (an export of the commit): assist_check 0 failures; run_checks ALL OK (import, load_all, bot
  pilot, support probe, both UI tours); doc_check clean on the changed scripts. The before build (the probe commit 1dd042b, game
  code of ce1ba94): det_check -Full IDENTICAL to the 98bc3c4 baselines (normal 180 lines, late 46), so the probe does not change play.
- Income, six seeds (401-406), 900 s, AI against AI, before against after: total pilot income 7,182 a minute before (spread of the
  six: 273) and 6,874 after, 4.3% lower. That is more than one before-standard-deviation, so it is flagged; all six seeds are lower
  after (by 139 to 508 a minute). The drop is the old pilot-kill extra half (4,603 credits a match, 4.27% of all pilot income in the
  before runs) leaving the economy. The minion cut is a transfer: 463 credits a match (11.6% of minion pay, since 40% of last hits
  have helpers) moved from last hitters to helpers, 3,131 credits a match moved from killers to helpers on pilot kills.
- Determinism: play changes on purpose (money moves between pilots). det_check -Full, seed 7, two runs each, identical to each
  other: normal 180 lines, END t=900 187 units a7201933; late 46 lines, END t=1734 178 units 8fdcd340. Against the 98bc3c4 baselines
  the normal match first differs at 0:35 (a pilot kill with helpers: minions only start at 0:45) and the late match at 26:40 (t=1600). These are this
  branch's new determinism baselines.

### 2026-10-18: user test fork, no arbitrary damage modifiers (T-27)
- The user's request: "I want to remove all the arbitrary damage modifiers from the test branch, from every ship and turret.
  Modifiers like the ones you just mentioned "x1.4 against corvettes". Weapons should be balanced via other means than arbitrary
  modifiers like this". Shown five groups, the user decided: "Number 4 and 5 can stay, but i want to get rid of 1 to 3. They dont
  need balanced replacements right now. I will test it myself and figure it out". Nothing was tuned to make up for the removal and
  no mechanic was added: every hit now does its raw damage (after the player-earned boosts and the target's own defences).
- Removed (groups 1-3): the whole damage table (Rules.DAMAGE, Rules.damage_mult(), SIZE_TORPEDO, the torpedo column: bolt, flak and
  PD rounds still shoot torpedoes down, now for their full damage), the Fighter cannon's +25% against small ships and its plumbing,
  the torpedo x0.35 / x0.6 against small craft (torp_small_mult); in CombatScaling the mothership attacker-size multipliers, the
  minion multipliers against mothership, turret, ship and minion, the turret backdoor x0.3 and the +30% from torpedoes against a
  painted ship (painting itself stays); the flat x0.5 of a flak burst on a mothership (the burst now falls off with distance from
  its hull, like for every other target); the x0.6 an ion beam did to asteroids (only "cuts" weapons hurt rocks, as before);
  lance_role's x1.35 on a big ship's rear zone; minion_cap (a no-op, the key still loads); bomber_role's torpedo number.
- Kept on purpose: groups 4 and 5; the weapon kind ids; TurretData.BACKDOOR_RADIUS (the AI pilots push a turret when their minions
  are near it); the Lance's prey hunt and tail circling; bomber_role's seats 6 and 10 flying Fighters and its AI rule that lets a
  lane Bomber shoot a small enemy pilot; all AI target choice. Opt-in variants that were off: eff:on (its term is always 0 now),
  ms_soft:mult (does nothing) and breach:fulldmg (its x2.0 on a mothership is now a real doubling) were touched only in comments
  and in the smallest way that keeps them loading.
- Texts changed: the Fighter, Lance, Bomber, Support, Flak Frigate and Ion Frigate blurbs, the turret blurbs, the help page's Goal
  and Turrets lines, the admiral board's turret note, the "within" preset description, README, FORK_MANIFEST, DESIGN.md (A5 says
  the table is removed, with the user's words; A9 and A12 say the backdoor and "weak to large ships" rules are gone and that the
  requirement lines on turrets and the mothership are no longer enforced by damage rules in the test branch), CODE_GUIDE.md and the
  regenerated API_INDEX.md.
- Checks on the game code of 2199ba3: run_checks ALL OK; doc_check clean on the 36 changed scripts; no remaining read of any removed
  constant (grep proof). Determinism (det_check -Full, seed 7, two runs each, identical to each other): normal 180 lines, END
  cd93ab0f; late 60 lines, END 5a1f15a1 (it now plays its full 300 s: the early end at 1734 s is gone). Against fork_98bc3c4 the
  normal match first differs at t=30 s (unit counts at t=35 s) and the late match at t=1520 s. These are this branch's proposed new
  baselines (fork_2199ba3).
- A look at four long matches (fun_probe, seeds 401 and 402, 30 minutes, AI everywhere, skill jitter), before and after: no
  mothership took hull damage after the change in either seed, and seed 401, which the game before the change ended at 25:47
  with an Aurelian win, no longer ended. Minions killed about half the pilot-ship deaths (123 and 153 of 257 and 297) instead of a fifth to
  a quarter; turrets fell about twice as often (15 and 16 destroyed against 5 and 8). Not a gate, not tuned.
- The measurement tests' expected numbers (arena_matrix bands, ms_duel winners, the fun metrics for pilot kill share and unattended
  turret losses) describe the old multipliers; read, not run, in WHAT_CHANGED.

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

### 2026-10-19: T-41: the photo tours stitch their pictures into a short video clip

- The user's wish: judge the motion and the pace of a match from the phone. The shot runs now end by stitching their
  pictures into one MP4 with ffmpeg, in the order the pictures were taken: tests/spectate_shots.gd writes
  spec_clip.mp4 and tests/ship_action_shots.gd writes action_clip.mp4, next to the pictures.
- New helper tests/lib/shot_clip.gd (ShotClip.make; no class_name, like the other test helpers). The clip is H.264
  (High profile, level 4.0) in yuv420p colours with faststart, at most 1280 px wide (the height follows), 12 frames a
  second (--clip-fps=N, 1 to 30). A tour with few pictures holds each longer so the clip lasts at least 4 s; more
  pictures than fit in 55 s are thinned out evenly, so a clip stays under a minute. For a film of the pace of a match,
  ask spectate_shots for many pictures, for example --times every 10 s of the first ten minutes.
- Automatic, with an off switch: --clip=0. ffmpeg is called by name and found on the PATH; nothing about where it lives
  is stored. Without it the tour prints "clip skipped: ffmpeg is not on the PATH ..." and the command that makes the
  clip later (a shell started before ffmpeg was installed does not see it). The pictures stay, the failure count is
  unchanged and the run still ends with its usual last line.
- Only files under tests/ and docs changed: no game code, so no match can differ (no determinism run for this commit).
- Checks: run_checks ALL OK on the export of the branch tip (its tests/ files are the same as in the clip commit);
  script_error_scan 0 on every log; doc_check clean on the three scripts. Four windowed runs of the real tours (seed 7,
  parked off screen): spectate_shots with --times every 6 s from 0:30 to 10:00 saved 96 pictures and made a clip of
  8.0 s at 12 fps, 1280x720, H.264 High, yuv420p, faststart, 1.4 MB (checked with ffprobe); with ffmpeg off the PATH
  it saved 3 pictures and printed the "clip skipped" line, and the printed command made a 4.0 s clip by hand;
  --clip=0 made no clip; ship_action_shots with --clip-fps=6 saved 6 pictures and made a 4.0 s clip (1280x708).

### 2026-10-19: T-41: the match log warns when the first ten minutes have no big fight

- The user's wish: pacing problems should show up in the numbers before anyone notices them in play. The match log
  (MainReport) now prints one line at 10:00 of match time when no fight of 10 or more ships has happened yet, for example
  "WARN pacing: no fight of 10 or more ships in the first 10:00 (biggest: 7 ships at 6:42)" ("biggest: no fight at all"
  when there was none). Nothing is printed when a big enough fight happened, for a match that is cut off or ends
  before 10:00, or for a run that starts late (the --late tests start at 25:00 and never see the first ten minutes).
  The other printed lines are unchanged.
- A fight is the fun probe's "v2" fight, read from the match as it is (new scripts/fight_watch.gd, FightWatch, owned by
  MainReport): every 2 s the live pilot ships (no minions) are grouped into crowds (ships 2,500 world units or closer are
  linked); a crowd with 3 or more ships of each team is a fight when, in the last 4 s, one of its ships was hit by an
  enemy pilot of the same crowd (Unit.damage_log, which Combat keeps for kill rewards). The fight's size is its ship
  count.
- Logging only: it reads ships, positions and damage logs, takes no random number, never switches on
  Combat.emit_damage_events (epic_neutral and the stats recorder use that switch) and changes nothing, so the match is
  the same with it.
- --big-fight=N changes the 10 (listed with the other options in game.gd): 99 always warns and shows the biggest fight,
  6 warns only when there was no fight at all.
- Checks (game code of c615663): run_checks ALL OK; det_check against fork_e2567a8: normal IDENTICAL over 180 lines,
  late IDENTICAL over 60; script_error_scan 0; doc_check clean on the changed scripts. The first version of this code
  printed a WARN at the first tick of the --late run (it starts at 25:00); the late-start rule above fixed that, and
  both gates were repeated on the fixed code. Seed 7, 12 minutes: no WARN with the bar at 10; with --big-fight=99 the
  line shows "biggest: 11 ships at 1:00"; with 6 no WARN. The biggest fight of the first ten minutes on seeds 11 to
  16 was 10, 11, 10, 10, 10 and 10 ships (at 0:30, 6:46, 0:28, 0:28, 0:28, 0:28): the AI's opening clash is already
  a fight of about 10 ships in almost every match, so the bar of 10 is met with little or no margin.

### 2026-10-20: user test fork, T-27 behind a switch (T-35)

- The user's decision (timetable v3, decision 2): "T-27 goes behind a switch: off in the build I play, on for T-28's measurement branch. With the switch off, the play build's det must return to the pre-T-27 baselines. Tweak lane, this week." So the damage modifiers that T-27 removed are back in the code, and one switch decides whether they apply. Nothing was tuned and no mechanic was added.
- The switch: the constant `Rules.DAMAGE_MODIFIERS_REMOVED` (rules.gd, false in this build), read through `Rules.damage_modifiers_removed()`. The option `--damage-modifiers-removed` (or `=0` / `=false`) overrides it for one run (Game reads it in `_parse_options`, before the variants are built). Both exist because the tools differ: `det_check.ps1` cannot pass a game option (its arguments are fixed), so T-28's branch turns the switch on by changing the constant (its det and run_checks then work as they are); `run_batch.ps1` can pass options (`-Extra`), so batch runs can use the option on one export.
- Switch off (this build): the game as it was before T-27 (the commit before it is 832887d): the damage table and its torpedo column, the Fighter cannon's +25% against small ships, `torp_small_mult`, the mothership attacker-size rule, the minion multipliers, the turret backdoor x0.3, the paint bonus, the asteroid multiplier, the flak burst's flat half damage on a mothership, `lance_role`'s x1.35 on a rear zone, `minion_cap`, the `bomber_role` torpedo number, and the table term of `eff`, the `mult` of `ms_soft` and the x2.0 of `breach:fulldmg` as they were. Switch on: T-27 as merged (e2567a8). The off paths are the pre-T-27 code put back behind the guard: `git diff 832887d` of the changed files shows only the guards, the on paths, the accessor and option, the text selection and comments.
- The places that ask the switch: `CombatScaling.final_amount` (the raw damage first when removed), `Projectiles` (a round's damage to a torpedo's hit points), `CombatBeamArea` (rock damage of a cutting beam, a flak burst on a mothership), the `install()` of `lance_role`, `minion_cap` and `bomber_role` (the torpedo half), `MsSoftFeature` (`mult`), `EffFeature.adjust`, and the texts.
- The off path's own defaults (finding 21 of the lead's REFUTE check of timetable v3): `CouncilPresets.variant_string()` adds `minion_cap:on,lance_role:on,bomber_role:both` after a rule set's own pairs while the modifiers are kept (`--variant` is still applied last), so the old rules of those three variants do not depend on the preset strings still listing them. With the switch on the strings are used as they are. Main's v0.2.2 preset change (M-05, M-06, M-07) was not on any branch of the repo clone when this was built, so it was not read. What this cannot keep: a rule set that is chosen some other way than by name (for example a default changed in `Rules.VARIANT_DEFAULTS`) does not go through `variant_string()`.
- Texts follow the switch: the hull blurbs (`Ships.blurb`), the turret blurbs (`TurretData.blurb`), the help page's Goal and Turrets paragraphs, the Admiral board's turret note, and the "within" rule-set description on the start screen (`CouncilPresets.blurb`). Docs: DESIGN.md A5 and the lines T-27 changed now say the rules are behind a switch (off in the play build until T-28 merges, by the user's decision, quoted), CODE_GUIDE.md (glossary and two paragraphs), README, FORK_MANIFEST and the two fork manifests' notes, API_INDEX.md regenerated. Code comments say what the code does with the switch off and on.
- Checks (game code of 9ef437a; the commits after it change only docs). The switch-on game was checked on a second branch, local/utf-t27switch-on, one commit (the constant set to true) on top of the code commit, because det_check cannot pass the option; that branch is not for the play build.
  - The branch point e6e3e00 first: det_check -Full against fork_e2567a8 IDENTICAL (normal 180 lines, late 60), so the merges after e2567a8 did not move the match.
  - run_checks ALL OK (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks) on the exports of the switch-off game and of the switch-on game; script_error_scan 0 on every log; doc_check clean on the 39 changed scripts (headers 39/39, functions 213/213, members 506/506), off and on. A grep of every restored constant and rule shows each read behind the switch (list kept with the builder's notes).
  - Switch off, det_check -Full against fork_832887d, two runs: normal IDENTICAL over 180 lines both times (END t=900 187 units a7201933), late IDENTICAL over 46 lines both times (END t=1734 178 units 8fdcd340). The switch-off game's determinism baselines are again fork_832887d.
  - Switch on (the flip commit), det_check -Full against fork_e2567a8: normal IDENTICAL over 180 lines (END t=900 189 units 508ecd1d), late IDENTICAL over 60 lines (END t=1800 182 units 3dca3433).
  - Beyond the brief, det_hash through run_batch (seed 7, sim-only, the same match as the full run): the switch-off export run with `--damage-modifiers-removed` is IDENTICAL to fork_e2567a8 (180 / 60 lines), and the switch-on export run with `--damage-modifiers-removed=0` is IDENTICAL to fork_832887d (180 / 46), so the option works both ways on one build.
  - The standard rules never turn on `lance_role`, `minion_cap`, `bomber_role` or the opt-in variants, so the baselines above do not cover them. With `--preset=pick`: the pre-T-27 export against the switch-off export IDENTICAL (normal 180 lines, END t=900 188 units 402de3bd; late 60 lines, END t=1800 182 units ace3d4f1), and T-27 as merged against the switch-on export IDENTICAL (normal 180 lines, END 196 units ecd2b25c; late 58 lines, the match ends at t=1790, END 162 units 36156161). With `--preset=pick` plus 15 opt-in variants (`ms_soft:mult`, `eff:on`, `breach:fulldmg`, `breach_extra`, `ms_cap`, `escort_pd`, `routing_payoff`, `morale`, `salvage_core`, `epic`, `feats`, `assets:full`, `ms_spend_weak`, `jungle_scale`, `attrition`): off against pre-T-27 IDENTICAL (normal 180 lines, END 153 units 119ff583; late 31 lines, the match ends at t=1657, END 155 units 579598da), on against T-27 as merged IDENTICAL (normal 180 lines, END 176 units 3ff81d97; late 60 lines, END 147 units b126499c). The switch-off pick differs from the switch-on pick at t=30, so those runs do exercise the old rules. The pick's switch-off reference hashes (402de3bd, ace3d4f1) are what a re-check after the v0.2.2 merge can be compared with.
  - The HUD tours with a rule set chosen (the start screen's description): ui_tour done and no script error, off and on.
### 2026-10-20: user test fork, difficulty levels (T-32)

- The user's words (Mon 10-19): "I would like to add difficulty levels to the test branch. Easy, medium, and hard. For now keep it simple, only a modifier to enemy pilot and admiral income, and the difficulty modifier only applies to single player games." Their answers: Easy x0.75, Medium x1.0, Hard x1.25 "on everything the enemy team earns (its AI pilots' credits and its Admiral's treasury, every source)"; new games start on Medium; the start screen remembers the last pick. Added Tue 10-20: "I want to move up the difficulty level addition as the game is currently too easy thanks to the poor state of the enemy admiral AI (which we will get to). This make it hard to test and see late game ship. I also want to add a "very hard" option for 150% income and an "extreme" option for 200% income." So five levels: Easy x0.75, Medium x1.0, Hard x1.25, Very Hard x1.5, Extreme x2.0. Nothing else changed: no prices, rules, AI or damage modifiers.
- The setting: `Game.difficulty` (game.gd), one of `Difficulty.ORDER` (new scripts/data/difficulty.gd, where the five multipliers are the named constants `EASY_INCOME` ... `EXTREME_INCOME`). Source of the level: the launch option `--difficulty=<level>` (an unknown word stops the match, exit code 3, like `--preset`), else the start screen's picker. The enemy team is the team with no human on it: `Difficulty.team_income_mult(human_team, team)` gives the chosen level's number to it and exactly 1.0 to the human's own team and to both teams when nobody is human (spectator, `--all-ai`: every test, determinism and tour run). WorldSetup asks once per team and stores the answer in `TeamState.income_mult` and in each pilot's `PilotProfile.income_mult`.
- Three gates carry the multiplier (one choke point per kind of income): `PilotProfile.earn()` (every payment with a message: kills, assists, minion last hits and assists, jungle camps, turrets, repair bays, drones, wards, the ore share, the escort bonus, the research stipend, and the payments of the optional feature modules), the new `PilotProfile.earn_quietly()` (the steady trickle, `Economy.passive_income`; the running pay of the catch-up, pilot-mining and extractor modules) and the new `TeamState.earn()` (the treasury's 60% ore share, a destroyed enemy turret's and repair bay's reward, the mothership's 3 credits a second, the comeback bounty's treasury share). Not income, so never multiplied: the starting credits and treasury, sales and trade-ins of gear, hulls and modules, ship insurance, the refund of an expired admiral order, the catch-up pool's moves between one team's pilots. A grep of `credits +=`, `earned +=` and `treasury +=` in scripts/ finds only these and the gates.
- Rounding: none. Credits are fractional numbers in this game and each payment is multiplied as it arrives, so the enemy's total over a match is exactly the level's multiple of what it would have earned (checked to 1e-12). Multiplying by exactly 1.0 changes no number, so Medium, the human's team and every all-AI match play bit for bit as before.
- Start screen: a DIFFICULTY row under the rule sets (heading and five buttons in one row, one text line: "Hard: the enemy earns 125% of its normal income. This changes the enemy's income in single player only."). Medium is the default. The game had no settings file (only `user://halcyon_stats.json` for `--record-stats`), so the last pick is kept in a new small file, `user://halcyon_settings.cfg` (Godot's ConfigFile; the browser version keeps it in browser storage), written when a button is pressed and read only by the start screen, so no test or headless run depends on what was picked on this computer. `--difficulty` beats the remembered pick. The pictures (five levels at 1920x1080, two at 1280x720) show both seat buttons in view on a 1080p screen.
- Tests (new): `tests/difficulty_check.gd` pays 100 credits through each gate for each team, delivers 1,000 ore, runs one second of the trickle and sells gear back, and compares with the level's promise (`--settings-check=<text>` also presses the picker, checks the file and the next run's start screen, and only writes into a scratch data folder: PITFALLS); `tests/difficulty_probe.gd` follows both teams' money source by source (the trickle tick by tick, each treasury against the normal rate) and the ships each field, with one human seat; `--bank` gives everybody a huge purse so that all five levels play the same match, `--events` writes every pilot payment.
- Checks (simulation code of 6d8dc3c; the commits after it change only the start screen, tests and docs, and the gates below ran on bd15d28):
  - det_check, plain, on the probe commit 252b16a against fork_832887d: IDENTICAL, normal 180 lines, late 46 lines.
  - Default (Medium), det_check -Full on bd15d28 against fork_832887d: normal IDENTICAL over 180 lines (END t=900 187 units a7201933), late IDENTICAL over 46 lines (END t=1734 178 units 8fdcd340).
  - All-AI is never affected: det_hash through run_batch with `--difficulty=extreme` and with `--difficulty=easy`: all four IDENTICAL to fork_832887d (normal 180 lines a7201933, late 46 lines 8fdcd340).
  - Same match at every level (`--bank`, human pilot seat, seed 7, 600 s): 2,595 pilot payments, the same order, time, team, seat and reason at all five levels; the 1,269 enemy payments are exactly 0.75 / 1.0 / 1.25 / 1.5 / 2.0 times Medium's (worst relative difference 9e-13, the printing), the 1,326 payments of the human's team are identical text; the treasury income ratio is 0.750000 / 1.000000 / 1.250000 / 1.500000 / 2.000000 for the enemy and 1.000000 for the human's team; the trickle check (every pilot, every tick) found 0 bad ticks; each source's total divided by Medium's is the level's number. Medium against the build without the setting: the probe's whole payload and the payment file IDENTICAL. The natural runs (seeds 7, 401, 402, 30 minutes, no bank): Medium's whole payload IDENTICAL to the before build for all three seeds.
  - difficulty_check: 0 failures at all five levels with a pilot seat, at Hard and Extreme with the Admiral seat, at Easy and Extreme all-AI; `--settings-check` passed; `--difficulty=extreem` prints DIFFICULTY UNKNOWN and stops. run_checks ALL OK; script_error_scan 0 on every log; doc_check clean on the changed scripts.
- What the levels do to the late game (natural runs, one human pilot who flies a Fighter and then sits still, seeds 7 / 401 / 402; the enemy's first Destroyer, first Battlecruiser, and how the match ended): Medium 21:57 / 19:28 / 22:03, never / 27:36 / 25:22, nobody won in 30:00. Hard 17:20 / 20:00 / never, 22:58 / 22:52 / never, ended 26:50 (Vhorr) / 30:00 / 23:27 (Aurelian). Very Hard 15:29 / 17:27 / 17:57, 22:38 / 22:33 / 23:29, Vhorr won at 23:22 / 28:47 / 25:12. Extreme 13:17 / 13:13 / 13:59, never / 22:28 / 20:59, Vhorr won at 19:57 / 25:48 / 26:52. Easy: Battlecruiser never, Destroyer in one seed at 25:52. More income does show up as bigger ships, earlier: the Admiral AI spends the extra at first (Extreme: 6 facilities and 15 research done by 10:00, Medium 4 and 9 to 10) and the pilots, who earn the multiple too, buy bigger hulls sooner. But the Admiral AI runs out of things to buy: by 20:00 Very Hard and Extreme have finished 7 facilities and 28 to 29 research items (Medium 23 to 25) and the treasury piles up unspent (13,000 to 37,000 credits, Medium 900 to 3,800), so income above about x1.5 mostly sits in the treasury. The AI was not changed. With an idle human seat the richer enemy also ends the match before the late game has had time (the human's team loses its mothership at 20 to 29 minutes at Very Hard and Extreme), so a player who plays well will see these ships later than these times.
- Notes for the next reader: a human-seat run through run_batch needs a wrapper that turns its `--all-ai` into `--auto --role=pilot` (the lead's tools folder has them); `difficulty_check` prints no line that run_batch counts as a result line, so its batch line says "no result line" although the run is fine (read the log's last line).

### 2026-10-20: user test fork, lane pilots farm minions (T-34)

- The user's words (Mon 10-19): "AI pilots shouldnt be parked with nothing to do, they should be trying to get last hits in on minions". They chose the start: "Tue 18:00 (Recommended)". Why pilots park (the lead's trace of the user's screenshot): a lane pilot's station is a fixed spot 500 to 1,100 world units behind the wave's front minion, and it only looks for targets within about 975 of itself, so when the front minion fights enemy minions some 1,400 away the pilots wait. The same trace found a small defect next to it: at the Top and Bottom Crossing the turret slot lies 500 off the lane line and the 450 sideways spread by seat put one seat's station on top of our own turret. Both are fixed here. Not in this item, by the lead's brief: holding fire to time the killing shot, and denying the enemy the last hit. No other number was touched; `Rules.DAMAGE_MODIFIERS_REMOVED` stays off.
- The new step (`PilotGoals.think_lane`, step 7, after push and prey): with no target, no structure to push, no pilot to hunt, and a plain station behind the wave (not the opening, no rally, defend, siege or hold order; `_pick_station()` now returns the station's lane, or "" when something else set the goal), the pilot asks `PilotTargeting.farm_target()` for the best live enemy minion it can see within `FARM_RADIUS` of our wave's front minion (`PilotGoals.front_minion()`: the minion `wave_front_s()` measures), sets it as target with the new intent "farm", and sets its goal to the standoff point at gun reach of it on our side (the point a push uses). "Best" is the score a minion always had in `pick_target()` (distance + 250, a last hit 700 better, a heavy hitter 300 better on the bigger minions), now one function, `PilotTargeting.minion_score()`, used by both; a candidate gets +700 when a rock hides it. Left out: a minion under an enemy turret that our minions are not tanking (the 250 margin of the station keep-out), one given up behind rocks (`skip_id`), small minions for a bomber, and a minion where `odds_at()` is worse than -1 (the rule for hunting a pilot). A ship under half hull, a scout and a logistics ship do not farm (as for push and prey). A pilot fight, a push, a fall-back (which returns before the step), a retreat (another state) and the admiral's orders (they make the goal not plain) still win. Big ships farm too; their goal is the standoff point.
- The one new number: `PilotTargeting.FARM_RADIUS` = 1,500 world units. Why: the enemy's Patrol Leader holds 55% to 85% of its cannon reach (1,250) from its target, so up to 1,062, its Snub-Fighters circle at about 470 and its Light Bombers at 380; 1,500 covers that front line and the ranks behind it. The probe measured it in the six "before" matches (30 minutes each): at the moments a lane pilot had no target and stood still, the nearest enemy minion was within 1,000 of our front minion in 50.0% of them, within 1,500 in 57.6%, within 2,000 in 62.6%, within 3,000 in 68.7%, and in 27.6% there was none within 4,000 (nothing to farm, or no wave out). Past 1,500 each further 250 adds 2 to 3 points, so a bigger circle sends the pilots further up the lane for little.
- The station fix (`PilotGoals._pick_station`, step 3b): a plain wave station nearer one of our live turrets than its hull plus the ship's radius plus 160 (the distance at which a pilot counts as arrived) is moved straight out from the turret's centre to that distance. Stations made by the opening, a rally, a defend order, a siege or a hold point are left alone. In the "before" game the diagnostic runs wrote down goals 50 to 62 from the Top Crossing's PD turret (an Aurelian seat 8 fighter, the pilot of the trace) and 50 from the Bottom Crossing's (a Vhorr seat 2 bomber), and at inner nodes (Halcyon Mid, Cinder Top); with the fix the plain stations are gone. What is left (19 s in the six "after" matches, 36 s before): the defend-a-turret order parks a pilot 300 from the attacked turret, which at a three-turret inner node (slots 414 apart) can be 139 from its neighbour; orders win, so it stays.
- Tests: new `tests/farming_probe.gd` (reads the game, no random numbers): per lane pilot (roles top, mid, bot, flex) idle time (no target and slower than 40 units a second; a spell over 5 s is "parked"), last hits, deaths and their killers, stuck ships (the `pilot_audit` rule), station goals inside our own turrets (with notes on the first 40), the brain's intent by seconds, the winner and the match length, and three histograms of the distance from our front minion to the nearest enemy minion. One FARMING_PROBE_JSON line. Run it with `--all-ai --skill-jitter --sim-only --test=farming_probe --secs=1800`.
- Checks (game code of 517a4aa; the later commits change only docs and `tests/farming_probe.gd`):
  - Commit 1's probe (de16bac, the second probe commit; it differs from the first only in the probe): det_check, plain, against fork_832887d: normal IDENTICAL over 180 lines, late IDENTICAL over 46 lines, script errors 0.
  - The restructuring alone changes nothing: with `FARM_RADIUS` 0 and the turret clearance never true (a throwaway commit on `local/utf-farming-off`, not for the play build), det_check plain against fork_832887d is IDENTICAL (normal 180 lines, late 46 lines). So `minion_score()`, `front_minion()` and `_pick_station()` returning the lane leave the match as it was; every difference below comes from the farm step and the station fix.
  - The new play, det_check -Full twice (export of 5b1ff58): run A and run B are IDENTICAL on every line. Normal: 180 hash lines, END t=900 190 units b47b03e5. Late: 60 hash lines, END t=1800 173 units 89e73068 (the late match plays its full 300 s now; fork_832887d's ended at t=1734 with 46 lines). First difference from fork_832887d: normal at t=100 (hash eb7c5a68 became db1c1766, both 133 units), late at t=1535 (b12c61f2 became a87c15da, both 127 units). Proposed as the next baselines of the play build.
  - run_checks ALL OK (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty); script_error_scan 0 on every match log; doc_check clean on the four changed scripts.
- The measurement (same six seeds 301 to 306, all-AI, `--skill-jitter`, 30 minutes, before = de16bac, after = 517a4aa; lane pilots = the 20 pilots with role top, mid, bot or flex):

| measure (six matches in all) | before | after |
|---|---|---|
| matches that ended before 30:00 | 1 (seed 306, 28:50, Aurelian) | 0 |
| lane-pilot seconds in the lane state after the opening | 150,936 | 151,981 |
| seconds with intent "farm" | 0 | 15,459 (10.2%) |
| idle seconds (no target, slower than 40) | 3,301 (2.2%) | 3,074 (2.0%) |
| parked seconds (idle spells over 5 s), spells | 900, 94 | 850, 80 |
| of the idle moments, those with an enemy minion within 1,500 of our front minion | 3,803 samples = 1,902 s | 2,526 samples = 1,263 s |
| last hits by lane pilots (per lane pilot and match) | 2,427 (20.2) | 2,618 (21.8) |
| minion kills by pilots, all | 2,556 | 2,752 |
| minions destroyed by anything | 12,326 | 12,439 |
| pilot deaths (lane pilots) | 1,423 (1,354) | 1,415 (1,362) |
| deaths by minions / pilots / turrets / rocks / other | 350 / 917 / 76 / 1 / 79 | 331 / 904 / 69 / 4 / 107 |
| stuck episodes (lane pilots), stuck seconds | 93 (86), 396 | 111 (109), 534 |
| station goals inside our own turrets, seconds | 36 | 19 |

  Per seed (before, after): last hits per lane pilot 17.5, 21.9, 19.9, 22.2, 19.6, 20.1 and 25.4, 21.9, 19.4, 22.7, 19.8, 21.7; pilot deaths 235, 236, 259, 226, 228, 239 and 234, 226, 209, 244, 247, 255; stuck episodes 15, 14, 18, 19, 16, 11 and 13, 23, 20, 33, 10, 12.
- Side effects, looked at with `tests/pilot_audit.gd` on the same six seeds (before and after): pilot deaths by cause (the audit's causes; the probe's "other" in the table is mostly the motherships): minions 350 to 329, pilots 915 to 904, turrets 76 to 69, crashes 1 to 4, motherships 77 to 103. Stuck ships by the audit's rule: 99 episodes before and 102 after, in 95 and 75 distinct places (a place = seed, team, hull and a 400-unit cell), stuck seconds 404 and 502 (the probe's own count, which keeps each pilot's history by team and seat, says 93 and 111). Two things moved. (1) In the "after" matches two bombers sat trapped on rocks at the lower edge of the middle lane for 126 s (seed 301, Vhorr, near (16410, 15049)) and 390 s (seed 304, Aurelian, near (28346, 15058)): 26 of the 43 bomber episodes, and the bombers' stuck seconds went from 138 to 348. The "before" matches had no such trap (15 bomber episodes in 15 places), and the other 76 episodes of the "after" matches are fewer than the 99 before. Whether the farm step sent those two there is not proven: the known asteroid snag near the Crossings (PROGRESS, AI opening, second round) catches strike craft by itself. (2) Pilots killed by a mothership's guns: 77 to 103, and before 20:00 from 3 to 22; the victims were pilots already retreating from the enemy base, killed within about 2,000 of its mothership. The turret rule of the farm step (and the station keep-out) looks at turrets only, not at a mothership's guns, so a pilot that follows a minion fight to the enemy base can end up in their reach. Total deaths did not move, because the deaths by minions, pilots and turrets fell by about as many.
- What the numbers say: the step works (a tenth of the lane pilots' time is spent flying out to a minion and shooting it, and the idle moments with something to farm fell by a third), pilot deaths did not rise, and the last hits went up by 8%, but that gain is mostly seed 301 (the other five seeds moved by -0.5 to +1.6 last hits per pilot): six matches cannot tell a gain of that size from chance. Idle time was never large (2.2% of the lane pilots' time, 0.6% parked): a pilot dies about ten times in a 30-minute match, so most "no target" time is the flight back from the base. In the "before" matches about 28% of the idle moments had no enemy minion within 4,000 of the front minion at all (the wave died or the lane is quiet), which is nothing to farm. The one change to consider for a second round, if the deaths by motherships matter: let `farm_target()` skip a minion within the enemy mothership's reach (2,600, its Ion lance, plus the 250 margin) of its hull, the way it skips one under an untanked turret.
- Notes for the next reader: `run_batch` counts a run "ok" only if its log has one of a few result markers, so the probe prints FARMING_PROBE_JSON (the first version printed FARMING_JSON and every run said "no result line"). The balance rule "one number per round" holds: FARM_RADIUS is the only new tuning number (the 160 in the station fix is the pilots' arrival distance, and 0.5 hull and the odds limit -1 are the numbers `prey()` already uses). A second round, if wanted, is a change of the radius or of who may farm; neither was tried.

### 2026-10-21: user test fork, the Vhorr minion bomber redrawn (T-08 round 2)

- The user's words (Tue 10-20), verbatim: "The designs of the Vhorr minion fighter and minion bomber are too similar, lets redo the minion
  bomber design". The plan they were shown (defaults, the user can change any): only the Vhorr Light Bomber changes; a different
  silhouette family from the fighter's narrow, pointed teardrop, wide and blunt, so that it reads heavy and slow; still a smooth, plain
  minion (no blades, horns, plates or veins, one engine light, the same body tint of 0.35), so it is never taken for a bladed pilot
  hull. Drawing only.
- Why the two read as one: the Spore (the Vhorr Snub-Fighter) is 1.60 long and 1.04 wide, the old Larva (the Light Bomber) 1.75 by
  1.00, both smooth teardrops, the Larva a little longer with its widest point further forward. A shape under 24 px long is drawn
  as its tiny outline only, and from the usual zoom (4,500 units across) outwards both minions sit at the 6 px size floor, about 10
  px long, so they were two similar small teardrops. Turned the other way round, the Larva is nearly a Spore (overlap 0.86, below).
- The new bomber, called Bloat in a code comment (CinderShapes.MINIONS "bomber", scripts/data/cinder_shapes.gd): a short, broad pod,
  blunt at both ends: a round nose with a shallow dimple, widest through the middle, a flat tail. One smooth outline of 20 points and
  a tiny outline of 10 (a flat nose and a flat tail), no plates, no veins, one engine light (now inside the tail) and the same body
  tint. The Spore, the Cocoon, the Aurelian minions, every pilot hull, CinderPaint, hit circles, sizes and every number the match
  reads are untouched.

| unit space | length | width | width / length | outline points (full / tiny) | area | fills its box |
|---|---|---|---|---|---|---|
| Spore (the fighter) | 1.60 | 1.04 | 0.65 | 16 / 8 | 1.18 | 71% |
| Larva (the old bomber) | 1.75 | 1.00 | 0.57 | 16 / 8 | 1.22 | 70% |
| Bloat (the new bomber) | 1.62 | 1.08 | 0.67 | 20 / 10 | 1.58 | 90% |

- The proportion cannot go much further: a Vhorr outline must stay within 10% of the Aurelian outline's length and width (the size
  check of hull_gallery --check, which keeps hits and ranges reading the same) and the Aurelian Light Bomber is 1.75 by 1.0, so the
  new bomber's 1.62 by 1.08 (-8% and +8%) is near the edge, and a width of 80% of the length is out of reach (about 0.69 at most).
  The difference is in the ends and the fullness: blunt where the Spore is pointed, flat-tailed where it is round, and 34% more area
  than the Spore (the Larva had 4% more); the Aurelian Light Bomber, a squat box, covers 1.67.
- How it was chosen: four preview sheets and about 20 candidates, drawn the way CinderPaint draws them and judged at the near zoom,
  at the usual zoom and in a crowd turned every which way. Tried and left: a notch in the nose (it reads as an open mouth, and the
  pilot Bomber has jaws), a payload sac or two lobes (a nub on a seed is still a seed, and a peanut is too near the Cocoon's gourd),
  a broad ray, plow or shield (turned round it overlaps the Spore as much as the Larva does, 0.85 to 0.87) and a plain loaf. A pod
  that is blunt at both ends cannot be taken for a teardrop however it turns: its overlap with the Spore is 0.76 as drawn and 0.75
  turned round, against the Larva's 0.70 and 0.86 (the overlap of two outlines scaled to one length, 1.0 = the same outline; a
  helper measure, not in the game, and within a box this size it cannot fall below about 0.67). The dimple and the flat tail keep it
  from being a plain brick. The dimple is left out of the tiny outline: it is under a pixel deep at that size and the tiny outline is
  drawn without smoothing, so it only made a ragged nose (the second code commit).
- Checks (game code of 8ee6918; the commit after it changes only docs):
  - det_check -Full (the drawing code runs), seed 7, against this branch's baselines (fork_5faf514): normal IDENTICAL over 180 lines
    (END t=900 190 units b47b03e5), late IDENTICAL over 60 lines (END t=1800 173 units 89e73068). The first code commit (3f8b8ea) gave
    the same two results: a redrawn outline moves no hash.
  - run_checks ALL OK (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty); hull_gallery
    --check: 84 polygons (the new outlines can be filled), 20 sizes within 10% of the Aurelian shapes, 3 minion looks, 0 failures;
    doc_check clean on cinder_shapes.gd; script_error_scan 0 on every log. API_INDEX.md is unchanged (no public function or signal
    changed).
- Pictures for the user, from the game's own gallery and a real match: the old bomber, the new one, the Spore and the Cocoon side by
  side at the near zoom, the usual zoom and far out (only the tiny outline is drawn there), a Vhorr wave in a real match with its
  Light Bombers among Snub-Fighters, and two enlargements of it. At the usual zoom the pod is a rounded block about 10 px long where
  the Spore is a pointed seed; the user judges the look in the game.
- Open choice for the user: if the block is not what they want, the other families tried (a notched nose, two lobes, a plow) pass the
  size check too and are a one-entry swap in CinderShapes.MINIONS.

### 2026-10-21: user test fork, the note key (T-19)

- The user's words (Sun 10-18 ~01:05, choosing the optional helpers): "Note key and match recorder". T-19 is the note key; T-20, the match recorder, is its own item. Why: the user plays the test build and their feedback drives the fixes and the balance, so a key that saves one line of theirs together with the match details and a screenshot gives whoever reads it the moment, not a guess.
- What it does: F9 opens a one-line note box and pauses the match; Enter saves the note, Esc cancels. Either way the match carries on as it was: a match already paused with P stays paused, and the mouse buttons are set back to their real state (a button let go while the match is paused never reaches the game, so the guns could otherwise keep firing). Why F9: F1 to F8 are kept for fleet groups (the RTS plan), the key must never be Esc or P, and nothing used F9 (F10 and F11 are the surrender vote's keys, and F11 is fullscreen). It works in every seat and after the match is over. While the box is open the HUD ignores every other key (typing "b" or "p" opens nothing), and the big centre message says "Paused" without "Press P to resume". F9 is on the key line (`... H help · P pause · F9 note`) and on the help page "The match" as "Notes (F9)".
- The note: a small JSON file `note_<date>_<time>.json` in `user://feedback`, which on Windows is `%APPDATA%\Godot\app_userdata\Halcyon Drift\feedback\`, and in a game with a window a PNG of the same name, the screen as it was when F9 was pressed (taken before the box opens). The file has one entry per line: the text, the item ID when the text starts with one ("T-07: ..."), the real date and time, the match (time, clock, phase, and whether P had paused it), the setup (the seed, or "random" when no `--seed` was given, the rule set and its name, the variants that differ from the standard rules, the difficulty, the damage modifiers), the human (seat, team, state, ship, next hull, modules, position with a word on whether it is the ship's or the camera's, hull percent, credits, treasury, K/D/A), the window size in pixels and the camera, the screenshot's name and the Godot version. About 0.7 KB, plus a PNG of 40 to 90 KB (370 KB with the hangar open at 1920x1080). A headless game draws nothing, so its notes have no PNG. `--feedback-dir=<folder>` puts the notes elsewhere (the test uses it, so it never writes among the real notes).
- New code: `scripts/ui/note_box.gd` (NoteBox, scene `scenes/ui/note_box.tscn`: a dim cover that takes every click, a card with the text box) and `scripts/ui/note_writer.gd` (NoteWriter: the note's contents, the file name from the real date and time, the files). `Hud` makes the box the first time F9 is pressed (`note_box`, `_open_note()`, `_note_is_open()`); `HudInput` opens it (before its "only during play" test) and ignores key presses while it is open; `HudBanner`, `HudSlots` and `HelpPanel` carry the texts; `GameInputMap` has the "note" action. Nothing exists before the first press, so a match plays exactly as before.
- How it pauses: `get_tree().paused`, which the HUD ignores (its process mode is "always"), so the box and the HUD keep working. The box remembers whether the tree was already paused and gives that back when it closes; Esc is caught in the box's own `_input` before the text box sees it; Enter is the text box's `text_submitted`.
- Test: new `tests/note_check.gd` (`--test=note_check --feedback-dir=user://<scratch>`; with a window and `--shots=<folder>` it also saves two pictures of the open box). It presses the keys through `Viewport.push_input`. It checks: nothing exists before F9; the box opens and the match clock stands still for 400 ms; menu keys typed into the box are text and open nothing (and the HUD's key router, called with P, B, H, C, F and Tab itself, ignores them); Enter saves one note with the right text, item, date, match time, seed, rule set, seat, ship, position, credits and window size, and in a window a PNG as big as the window; Esc saves nothing; a match paused with P stays paused after a note; an empty note is saved as a marker; a second F9 changes nothing; the mouse buttons are re-synced; F9 works after the match is over; `item_id()` reads the IDs it should.
- Checks (game code of b40e8af, the last commit that touches a script; the commits after bd9acf1 change only comments, `tests/` and docs):
  - det_check -Full, normal and late, against fork_5faf514, on the exports of bd9acf1, 47a1e1c and b40e8af: all three IDENTICAL, normal over 180 lines, END t=900 190 units b47b03e5, late over 60 lines, END t=1800 173 units 89e73068. The key does nothing until it is pressed. det_hash with the HUD built and no key pressed (`--force-hud --sim-only=0` through run_batch, export of e71e9cb): normal 180 lines and late 60 lines IDENTICAL, the same END lines.
  - run_checks ALL OK (exports of e71e9cb, 47a1e1c and b40e8af); script_error_scan 0 on every log; doc_check clean on the ten changed or new scripts (84 of 84 functions and 66 of 66 members documented).
  - note_check: 0 failures with the pilot seat, the Admiral seat and the spectator seat, headless (export of b40e8af); in a window parked off screen (pilot at 1920x1080, spectator at 1280x720, and through `run_windowed.ps1`) the PNG exists and is as big as the window.
- Notes for the next reader: a game started without `--seed` has a random seed that Godot does not reveal, so its notes say "random"; the match recorder (T-20) must choose a seed and keep it. A headless game has no screen to photograph. The pause is the same one P uses, so the pause menu that v0.2.2 brings (M-07, Esc's last step) has to leave F9 and the box's own Esc alone; the box catches Esc first while it is open.

### 2026-10-21: user test fork, the note key reaches a browser player (T-50)

- The user's words (Wed 10-21 ~20:55, asking about the note key of T-19): "Will the notes key work for games run through the web browser?" The answer, read from the code: F9 and the save work in a browser, but the note and its picture land in `user://feedback`, which a browser keeps inside its own storage for that website, so nothing reaches a folder the reader can look at, and clearing the site's data would wipe the notes. A small change to the test-only tool was offered (hand each note and its picture to the browser as a download after saving). The user's request (~21:02): "I do want, please". T-50 is that change. Why it matters: the test website (from Sat 10-24) is where the user will play the test build, and a note that cannot leave the browser's storage cannot be read.
- What it does: in the browser build only (`OS.has_feature("web")`), after a note is saved exactly as before, `NoteWriter.save()` hands the same two files to the browser as downloads through `JavaScriptBridge.download_buffer`, in this order: first the note (`note_<date>_<time>.json`, its text as UTF-8 bytes, mime `application/json`), then, when the picture was saved, the picture (`note_<date>_<time>.png`, `Image.save_png_to_buffer()`, mime `image/png`). The names are the ones the files have in the folder, with the `_2`, `_3` suffixes when they apply, so downloaded notes sit together like the folder's own and a folder of them is read the same way as the game's own notes folder. The note comes first so that a browser that lets only one download through gives the player the note. The write to `user://feedback` stays as it was, and it still decides the free name. If a browser build has no `download_buffer`, the save still succeeds and the log says so. On every other platform nothing changes.
- What the player sees in the browser: the pop-up says "Note saved and downloaded." (on Windows it stays "Note saved."), and the "Notes (F9)" entry of the help page ends with "Each note comes to you as two downloads, the note and its picture. The browser may ask once whether this site may download several files: allow it." instead of "Notes stay on this computer." (the Windows text is unchanged). "F9 note" on the key line is unchanged. Chrome and Edge may ask once before a site downloads several files in a row; the player allows it.
- New code: `NoteWriter.browser_files()` (the list of files: name, mime type, bytes), `NoteWriter._hand_to_browser()` (one download of each, and the log line "note: handed to the browser as downloads: ..."), a "downloaded" entry in the save result that `NoteBox` reads for the pop-up, and `HelpPanel.NOTES_WHERE` and `NOTES_WHERE_BROWSER` (`_show()` swaps the second for the first in the browser build). No match code, no other keys, no other panels.
- What cannot be tested here: the browser path itself. This PC has no web export templates and no browser test rig, and building one is new infrastructure, so the real download and the browser's "several files" question are not run. Verification is on the test website after its first push: press F9 once in a match, type a line, press Enter, and two files arrive in the Downloads folder (the `.json` first, then the `.png`), the pop-up says "Note saved and downloaded.", and the browser's console shows the line "note: handed to the browser as downloads: ...".
- Test (`tests/note_check.gd`, every earlier step unchanged): `ClassDB.class_exists("JavaScriptBridge")` and `ClassDB.class_has_method("JavaScriptBridge", "download_buffer")`, so the call the browser build makes exists in this engine; `NoteWriter.browser_files()` lists the note first and the picture second with the folder's names, `application/json` and `image/png`, bytes that read back as the text (UTF-8) and as a picture of the same size, the picture's bytes equal to the PNG file the same picture makes in the folder, and only the note when there is no picture or an empty one; the saved note file is plain UTF-8 text, so the note's download is the same file; the help page's notes paragraph still ends with the sentence the browser build swaps, and the browser's sentence names the two downloads and the question; in step 4 the pop-up after Enter is "Note saved." and none speaks of a download, which shows in the log that a Windows game hands nothing to a browser.
- Checks (game code of e7a5cf9, the last commit that touches a script under `scripts/`; the commits after it change only `tests/note_check.gd` and docs):
  - det_check -Full (the drawing code runs), seed 7, against fork_5faf514, on the export of e7a5cf9: normal IDENTICAL over 180 lines (END t=900 190 units b47b03e5), late IDENTICAL over 60 lines (END t=1800 173 units 89e73068), a second comparison of the hash lines (their SHA-256) equal. The key does nothing until it is pressed, and the help page is built only when H is pressed.
  - run_checks ALL OK on the exports of e7a5cf9 and 30037cc (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty); script_error_scan 0 on every log; doc_check clean on the four changed scripts (headers 4 of 4, functions 44 of 44, members 23 of 23).
  - note_check: 0 failures with the pilot, Admiral and spectator seats headless (exports of e7a5cf9 and 30037cc, the commit that adds the last two checks), and in a window parked off screen (pilot, 1920x1080, export of e7a5cf9): the PNG exists and is as big as the window. In none of those logs does a "handed to the browser" line appear: a Windows game runs no download step and its pop-up is "Note saved.".
- Notes for the next reader: the browser build encodes the picture twice (once into the folder, once for the download); on a large picture that is a short pause when Enter is pressed, and if it shows it can be avoided by reading the saved file back instead. Browsers may block downloads that do not follow a key press or a click; the save happens on Enter, which is one.

### 2026-10-21: user test fork, the browser help sentence says how to undo a Block (T-50)

- What a fresh review found: Chrome and Edge ask once whether a site may download several files, and they keep a Block answer as a setting for that site. From then on the second download of every note, its picture, is dropped without a word, while the game's pop-up ("Note saved and downloaded.") and its log line still say both files were handed to the browser, because the game cannot see what the browser does with them. The sentence the T-50 entry above quotes said "allow it" but not how to undo a Block.
- What changed: the browser build's notes sentence (`HelpPanel.NOTES_WHERE_BROWSER`) has one more sentence, so the "Notes (F9)" entry of the help page now ends with: "Each note comes to you as two downloads, the note and its picture. The browser may ask once whether this site may download several files: allow it. If you chose Block, the pictures stop arriving; to get them back, allow automatic downloads for this site in the browser's site settings (the padlock or page icon beside the address)." The Windows text ("Notes stay on this computer.") is unchanged, and nothing else changes: no match code, no other panels, no other keys. The test's help-text check (`tests/note_check.gd`) also looks for "Block" in the browser's sentence. PITFALLS.md has the remembered Block as a new entry.
- Why no match can change: the sentence is a string that only the help page (key H) reads, and the other code change is in `tests/`. The pop-up still says "Note saved and downloaded." in a browser, because the game cannot know that a Block dropped the picture; the help sentence is where the player learns it.

### 2026-10-21: user test fork, bigger capitals and frigates (T-49)

- The user's words (Wed 10-21): "I would like to increase the size of the battlecruiser and destroyer by 1.5x and the frigates by 1.25x, now if possible". Asked whether the hulls should only look bigger (hit and collision unchanged) or be bigger in every way, they chose "Bigger in every way (Recommended)": the hulls are drawn bigger and their hit and collision circles grow with them. So this changes how a match plays (the option's stated case against: big ships are hit more often and crowd lanes and rocks more) and it moves the determinism baseline.
- What changed (scripts/data/ships.gd): the Destroyer and the Battlecruiser by 1.5, the Flak Frigate and the Ion Frigate by 1.25. Both teams use the same table, so the Aurelian and Vhorr ships (the Cinder look) both get it. Each hull's `radius` (the hit and collision circle) and `length` (how long it is drawn) is scaled, and so is every gun mount's `off` (where the gun sits on the hull, in world units), so the guns keep their place on the bigger hull. The arcs, weapon ids, weapon ranges, speeds, accelerations, turn rates, hull and shield numbers, prices, vision and every other hull are unchanged. The outlines (ShipVisual.HULLS and CinderShapes.HULLS) are drawn in a 36-unit design space and scale with `length`, so they were not touched.

| hull | radius old -> new | length old -> new |
|---|---|---|
| Flak Frigate (x1.25) | 70 -> 87.5 | 210 -> 262.5 |
| Ion Frigate (x1.25) | 68 -> 85 | 220 -> 275 |
| Destroyer (x1.5) | 120 -> 180 | 420 -> 630 |
| Battlecruiser (x1.5) | 160 -> 240 | 560 -> 840 |

- Gun mounts (x forward, y to the right, world units; new = old times the factor): Flak Frigate flak battery (40,0) -> (50,0), PD guns (-50,+-40) -> (-62.5,+-50); Ion Frigate ion cannon (100,0) -> (125,0), PD gun (-40,0) -> (-50,0); Destroyer heavy cannons (120,0) -> (180,0) and (-60,0) -> (-90,0), PD guns (60,+-70) -> (90,+-105) and (-140,0) -> (-210,0), flak (0,0) stays; Battlecruiser ion turrets (170,0) -> (255,0) and (-130,0) -> (-195,0), heavy cannon (30,0) -> (45,0), PD guns (120,+-90) -> (180,+-135) and (-180,+-80) -> (-270,+-120), flak (60,0) -> (90,0) and (-80,0) -> (-120,0).
- What follows from the radius by itself (nothing was re-tuned; each is the same rule with a bigger number): rounds and beams hit the bigger circle; blasts (flak bursts) are measured to the unit's edge, so they reach a bigger hull from further; guns, turrets, minions and the AI measure their reach and their engagement to the target's edge, so a bigger hull is shot at from slightly further (by the growth of its radius: 17.5 and 15 for the frigates, 60 for the Destroyer, 80 for the Battlecruiser); ships push each other apart by the sum of their radii and weigh as radius times radius, so a bigger hull gives way less against a smaller one (a Battlecruiser weighs 400 times a Fighter now, 178 times before); the fog-of-war "touching" test and the stealth-ward check (500 plus the radii) see a little further; the bigger collision circle touches rocks, ore rocks, turrets and the motherships more; the AI's rock and hull avoidance margins, its escape planner and its keep-out from its own turrets all add the ship's radius; a module's extra AUTO gun sits at 0.4 times the radius behind the centre; the death explosion and the shield ring are drawn bigger. The size class does not change, so the crash-damage constants, camera view widths, shield delays, focus cooldowns and the minimap dots stay as they were.
- What the bigger hulls broke, and the fixes (each its own commit, each the plainest rescaling of a spacing):
  - Round hits (Projectiles.BIG_PAD 110 -> 200): a round's line looks for big units (radius over 60) in World.big_hash out to HASH_PAD + BIG_PAD around it, which was 170. That was enough until now, but the Destroyer (180) and the Battlecruiser (240) are bigger, so a round that crossed only the outer band of their new hit circle could be missed (the grid has 320-unit cells), which would have shrunk the very circle that was asked for. 60 + 200 = 260 covers the biggest hull.
  - The "+200" margins (new constant Projectiles.MAX_UNIT_RADIUS = HASH_PAD + BIG_PAD = 260): four searches ask the spatial hash for "within range of the unit's edge" and left 200 units for the unit's radius: the ship pair search of WorldSeparation, the beam target search and the blast search of CombatBeamArea, and the turret target pick (Turret). A Battlecruiser (240) could be missed at the edge (a flak burst, a turret picking it up late, an overlap not pushed apart until deep). They now add MAX_UNIT_RADIUS.
  - Launch (Mothership.launch_point(slot, ship_radius), called with the hull's radius by WorldHangar.launch): pilots appear 160 past the tip of the mothership's solid bow, so a Battlecruiser (240) appeared 80 units inside it and a Destroyer (180) 20 units inside, and the physics shoved them out. The gap is now max(160, radius + 20): 200 for the Destroyer, 260 for the Battlecruiser, 160 for every other hull, as before. Minions, wards, repair bays and supply drones call it without a radius and appear where they did.
  - Lane stations (PilotGoals): a lane pilot stands 450 to the left, in the middle or 450 to the right of its station, by seat. The Battlecruiser is now 480 wide, so neighbours would overlap by 30 and be shoved apart every tick. The spread is max(450, 2.2 x radius): 528 for the Battlecruiser and 450 for every other hull (the Destroyer's is 396).
- Looked at and left alone (small, rare, or already like that): the AI's route entry test uses a fixed 16-unit width, not the ship's; the look-ahead for rocks is 0.6 s of speed, 90 units for a Battlecruiser, less than its radius (the old Battlecruiser's 160 was too); the connector detour past The Crossing passes close to the north PD turret slots, which a Battlecruiser or Destroyer on that link would clip once a turret is built there (turrets are solid; rare); the AI's keep-out from enemy turrets (range + 250) leaves the Battlecruiser's edge 10 units outside a torpedo turret's reach (large and capital ships ignore PD turrets); the hyperspace and "mothership offline" launches 160 from a bay (bays are not solid; only a rock next to the spot matters); the fog "touching" search (200 beyond its reach, so a pair of Battlecruisers is found only by grid luck, and a bigger hull spots stealth wards a little further, by its radius); the AUTO guns' target search (no margin; the edge test still decides); the jungle_big:all variant (off in every preset), whose 400-wide gate was sized for a 320-wide Battlecruiser; the test helpers arena_kit (ROW_GAP 300: capital squads start overlapped and are pushed apart on the first tick) and map_check_choke (SEARCH_MAX 160: only a ceiling in what it reports for wide gaps).
- Test tools: tests/pilot_audit.gd also counts the damage a ship took, and the time it scraped rocks, per hull (`dmgin_<hull>`, `dmgin_hull_<hull>`, `rock_ticks_hull_<hull>`); new tests/hit_reach_check.gd (`--test=hit_reach_check`, headless, a few seconds: the four biggest hulls stand at 64 spots over one hash cell and a one-tick round that passes 2 units inside the rim of the hit circle, from 12 sides, must find the ship); the hull gallery's play lineup would have run off the screen (the four big hulls of a team came to about 1,146 pixels against 960), so its second row holds the two frigates, a new `play_big_ships` picture holds the capitals, and the far picture keeps all ten ships together.
- Checks (game code of d7660b9; the commits after it change only tests and docs):
  - det_check -Full (the drawing code runs), seed 7, run twice on the same export, against this branch's baselines (fork_5faf514). The play differs by design. The two runs are identical to each other on every hash line (normal 180 lines, END t=900 192 units 73960193; late 60 lines, END t=1800 190 units 88a25058), so the new version is deterministic. First difference from fork_5faf514: normal at line 144 (t=725: 167 units in both, hash 00c4a1d0 became 5900304d; the 144 lines before it, t=5 to t=720, are unchanged); late at the first line (t=1505: 75 units in both, e0828817 became 9233a5f1; the late start launches the capitals at once). The old END lines were 190 units b47b03e5 (normal) and 173 units 89e73068 (late).
  - run_checks ALL OK (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty); hull_gallery --check: 84 polygons, 20 sizes within 10% of the Aurelian shapes, 3 minion looks, 0 failures (the outlines were not touched); doc_check clean on the eleven changed or new scripts (98 of 98 functions, 115 of 115 members); script_error_scan 0 on every log.
  - hit_reach_check: with the sizes alone (the hit search as it was) 80 of 768 rim rounds at the Battlecruiser were missed (10%), none at the other three hulls (the Destroyer's rim is exactly at the old limit); with the changes 0 of 768 at every hull.
- Before and after, AI against AI (tests/pilot_audit.gd, seeds 301 to 306, --skill-jitter, 6 matches each). "Before" is the fork tip's game code (c7c30a1 plus the audit's new counters: the same match, it reproduces the earlier fork_5faf514 audit line for line at 30:00); "after" is the game code of d7660b9. The matches part ways after the first difference, so six matches of each are a sample, not a proof: read the counts beside the rates. A normal match has hardly any Battlecruiser (about 15 hull-minutes in six matches), so a second set starts at 25:00 with both sides fully teched (--late, ten game minutes). A hull-minute is one pilot's ship of that hull in space for a minute. Each cell is before -> after.

| normal matches, up to 60:00 | hull-min | losses | losses per 100 hull-min | mean life at death (s) | damage taken per hull-min (before shields) | stuck episodes |
|---|---|---|---|---|---|---|
| Flak Frigate | 514.6 -> 639.9 | 290 -> 364 | 56.4 -> 56.9 | 94 -> 91 | 1996 -> 1990 | 31 -> 37 |
| Ion Frigate | 160.3 -> 162.8 | 96 -> 106 | 59.9 -> 65.1 | 88 -> 79 | 1570 -> 1710 | 10 -> 13 |
| Destroyer | 82.7 -> 72.7 | 32 -> 35 | 38.7 -> 48.2 | 124 -> 105 | 3003 -> 3370 | 3 -> 4 |
| Battlecruiser | 14.8 -> 15.7 | 6 -> 5 | 40.4 -> 31.9 | 140 -> 166 | 5613 -> 4313 | 3 -> 2 |

| late start, 25:00 to 35:00 | hull-min | losses | losses per 100 hull-min | mean life at death (s) | damage taken per hull-min (before shields) | stuck episodes |
|---|---|---|---|---|---|---|
| Flak Frigate | 149.1 -> 175.4 | 70 -> 66 | 47.0 -> 37.6 | 108 -> 139 | 2333 -> 2067 | 5 -> 3 |
| Ion Frigate | 73.3 -> 66.2 | 35 -> 29 | 47.7 -> 43.8 | 101 -> 97 | 1862 -> 1736 | 4 -> 2 |
| Destroyer | 18.5 -> 39.6 | 14 -> 20 | 75.7 -> 50.5 | 61 -> 81 | 6560 -> 4450 | 0 -> 4 |
| Battlecruiser | 190.3 -> 222.5 | 32 -> 39 | 16.8 -> 17.5 | 196 -> 220 | 3648 -> 3429 | 29 -> 38 |

  - Matches: normal, mean length 51.3 -> 55.1 minutes, 3 of 6 ended each time (before: Aurelian 2, Vhorr 1; after: Aurelian 3); late, 34.2 -> 35.0 of 35.0 minutes, 2 -> 1 of 6 ended (all Vhorr). All pilots together (normal): deaths 2,700 -> 2,887, crash deaths 8 -> 9, stuck episodes 215 -> 185, rock contact 330,082 -> 296,754 ticks, mothership contact 46,221 -> 49,933 ticks. Frigates touched the mothership longer in the normal set (95.7 -> 141.9 s); capitals about the same in the late set (235.9 -> 248.1 s).
  - Stuck ships: the audit counts a ship that moved under 150 units in 8 s while over 800 from its goal and not fighting. Capitals: 6 -> 6 episodes (normal) and 29 -> 42 (late, nearly all Battlecruisers: 29 -> 38; of those, 11 of 29 were within 800 of their own mothership and 3 at rocks before, 6 of 38 and 6 after); frigates: 41 -> 50 (normal) and 9 -> 5 (late). The Battlecruiser already had the most stuck episodes of any hull in the late set before (29 in 190 hull-minutes).
  - Step time: perf_probe (--late --perf-worst, 300 game seconds, seeds 301 and 302, four runs at once on one PC): CPU time per game second 484.7 -> 467.2 ms (wall 470.0 -> 451.2 ms), the slowest tick of each run 52.1 and 42.5 ms before, 60.9 and 43.0 ms after, the share of ticks over 33 ms 0.13% and 0.05% before, 0.06% and 0.03% after. The match logs' wall step time (six matches at once): 389 -> 370 ms per game second (normal), 453 -> 490 (late, with other jobs running). Drawing (the hull gallery's bench, 70 ships and 70 minions a team): frame mean 29.25 -> 29.35 ms (Aurelian only), 51.83 -> 52.12 ms (Vhorr alien look), 51.62 -> 52.18 ms (Vhorr plain look); draw calls 2,843 -> 2,843, 4,168 -> 4,172, 4,243 -> 4,243.
- Pictures for the user (the game's own gallery and a real late-start match): the four grown hulls before and after at the play zoom (4,500 units across), and three frames of a real match with a Battlecruiser or Destroyer among strike craft, minions and other ships. The Battlecruiser is 840 units long: at the closest zoom a pilot can use (1,100 units across) it fills about three quarters of the screen; the camera limits were not changed.
- Open choice for the user: if a hull should be less big than asked, each of the four factors is one number in `ships.gd` (radius, length and the gun offsets move together). The determinism baseline moves with this change (the new hash files are the ones above); anything measured against the old sizes is measured again.

### 2026-10-22: user test fork, three look fixes from the user's notes (T-23)

- What the user asked (item 10 of his notes on Sunday's fork pictures, 2026-10-18): three design questions about how things look, with no code yet. His answers, verbatim: "The white drift arrow on AI ships?" = "Your ship only (Recommended)"; "The hit flash?" = "Outline only (Recommended)"; "Lane and node labels at close zoom?" = "Cap at ~60 px (Recommended)". Those three answers are the whole item, one commit each. All three change only what is drawn: no rule, number, AI choice or timer changes (the hit trigger `Unit.take_hit` and the 0.09 s `flash` countdowns are as they were).
- The drift arrow (ship_visual.gd:265): `ShipVisual._draw` draws the arrow and its slip tick only when `is_human`, the ship the human flies, at any zoom. Before, the human's ship always drew it and every other ship drew it once the camera zoom was above 0.4 (a view narrower than 3,200 world units). Teammates' and enemies' AI ships never draw one now, and a match with no human seat draws none. The Vhorr hull goes through the same `_draw`; no other unit draws a velocity arrow (looked at: UnitVisual, CinderPaint, MothershipHull, the HUD speed readouts and the minimap; the mothership's move line points at its target, not along its velocity). `DrawParts.arrow` (`--bench-off=arrow`) still switches the human's arrow off. The arrow line is drawn at the human's 2 px width only (the 1.2 px branch could no longer be reached). The bench comments in tests/hull_gallery.gd and tests/lib/gallery_measure.gd and the arrow note in tools/draw_cost_table.py said an AI crowd draws arrows; they now say it draws none, so the arrow row of the all-AI bench is zero by design.
- The hit flash (palette.gd:118-125 and 157-170, ship_visual.gd:280-299, unit_visual.gd:106-125 and 314-329, cinder_paint.gd:179-219): a hit no longer lightens the fill. Before, the fill (and the plates of a big Vhorr hull) moved 60% toward white for 0.09 s (a mothership 25%), so under steady fire a hull stayed grey. Now the fill and the plates keep their colours and the outline flashes for the same time: its colour moves `Palette.HIT_FLASH` = 0.8 of the way toward ICE (a mothership `HIT_FLASH_MOTHER` = 0.4) and its width is multiplied by 1 + `HIT_WIDTH_GAIN` (1.2) times that strength (about 2 times for a ship, 1.5 for a mothership), so a thin 1.4 px line still reads. `Palette.hit_edge()` and `hit_width()` hold the rule; they are called only while a unit flashes, so no frame pays for them otherwise, and a hit adds no draw command (the same lines are drawn, in another colour and width). With the test switch `DrawParts.outline` off a hit shows nothing (the outline is the part that flashes).
  - Follow the new rule (they flash through the same code): pilot ships of both teams (`ShipVisual._draw_hull`; Vhorr through `CinderPaint.draw_shape`), lane minions, mining drones, turrets and repair bays of both teams, Vhorr repair drones (and supply drones) and wards, derelict camps and the jungle's snub fighters (`UnitVisual._poly`), and both motherships (gentler).
  - Do not flash, now as before: the Aurelian repair drone (a green plus with no fill or outline) and the Aurelian ward (a plain filled diamond with no outline). Not touched: `PilotExtractor` (scripts/features/pilot_extractor.gd:79-91 draws itself and turns its whole diamond white on a hit; it belongs to the `pilot_mining:extractor` variant, which is off in every rule set; say if it should follow), the ship's shield arcs (they brighten on a hit by their own rule) and the HUD's red "shield zone broke" arcs (ship_status.gd:100-102).
- The labels (map_decor.gd:30-49, 72-110 and 141-171): `MapDecor` drew each lane name at font size 180 world units and each ore node name at 150, so close up they grew to hundreds of screen pixels. Now each is drawn at the smaller of its old size and the size that is `LABEL_MAX_PX` = 60 tall on the screen at the camera's zoom. The pixels are the game's own (the window is stretched from a 1280 x 720 picture), the same pixels as every `px` in the painters, so the usual zoom (4,500 units across) and farther out are exactly as before. `_process()` reads the camera's zoom each frame and asks for a redraw of the names only when a label's size changes; with `--sim-only` it is switched off. The label's box and sideways offset shrink with the letters and its baseline moves so the middle of the capitals stays where it was at full size (`_label_shift()`), so a smaller label stays centred on the same spot. Colours and alpha are unchanged. The names are drawn on a child node of their own (`_names`, made in `setup()` and drawn by `_draw_names()`), so a new label size redraws only the names: drawing the whole decor (1,400 stars, the bands and the dashed lines) again takes about 30 ms on this PC, and a first version that redrew all of it on every frame the size changed (each frame of a zoom close up) took frames from 13 to about 45 ms, where redrawing only the names with a new size every frame left them at 13.5 ms (medians of six rounds of 150 frames each, in a window parked off screen, with the PC busy with other matches).

| label height on the screen, in pixels | lane name before -> after | node name before -> after |
|---|---|---|
| closest zoom, 1,100 units across (zoom 1.164) | 209.5 -> 60.5 | 174.5 -> 60.5 |
| usual zoom, 4,500 units across (zoom 0.284) | 51.2 -> 51.2 | 42.7 -> 42.7 |
| whole map, 44,000 units across (zoom 0.029) | 5.2 -> 5.2 | 4.4 -> 4.4 |

  Height is the font size times the zoom, read from the running game (the picture script prints the size `MapDecor` draws at); a capital letter is about 0.7 of it.
- Checks (game code of 379d114, the last commit that touches a script under `scripts/`; the commit after it changes only PROGRESS.md; each check below ran on the export of 379d114 itself, and the det pair also on the export of d96bf32, the commit before the names change, with the same result):
  - det_check -Full (the drawing code runs), seed 7, against fork_84d8653, on the export of 379d114: normal IDENTICAL over 180 lines (END t=900 192 units 73960193), late IDENTICAL over 60 lines (END t=1800 190 units 88a25058), so a drawing change moves no hash.
  - run_checks CHECKS ALL OK on the same export (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty); script_error_scan 0 on every log (the two det runs, the run_checks logs and the picture runs).
  - doc_check clean on the seven changed scripts and the two test files whose comments changed (headers 9 of 9, functions 105 of 105, members 139 of 139); `python tools/draw_cost_table.py --selftest`: 0 failures; API_INDEX.md rebuilt (two new lines: `Palette.hit_edge`, `Palette.hit_width`).
  - Pictures for the user, from the branch point and from this tip with the same throwaway picture script (it is not part of the branch): the player's ship among a staged crowd of AI ships (six of each team gathered round it for the picture; arrows on every AI ship before, on "YOU" only after), a crowd and close-ups of ships and units at the moment of a hit (a grey fill before, a bright outline over the unchanged design after), and a lane name and an ore node name at the closest and the usual zoom. Every kind of unit that flashes was also photographed calm and just hit on the new build to check the list above.
- Open choices for the user: the strength of the flash is one number, `Palette.HIT_FLASH` (how white the outline goes), and its thickness one more, `HIT_WIDTH_GAIN`; the cap of the labels is `MapDecor.LABEL_MAX_PX`.

### 2026-10-22: user test fork, test tools: unlock everything, slow motion, the camera while paused (T-43, T-44, T-45)

What the user asked (Tue 2026-10-20), verbatim:
- T-43: "I want to add an "unlock everything" feature to the test branch so i can immediately spawn whatever i want no matter the cost for testing. Add it to the schedule. Make it an option on the start menu"
- T-44: "I want to add a "slow simulation" button to the test branch so i can play the game at 0.75 and 0.5 speed to help me see details for testing. I need to be able to toggle this speed on and off at will while in game."
- T-45: "I want to be able to move the game screen around while the game is paused so i can see what is happening and take screenshots of bug or bad AI behavior."

Three test tools, test branch only. With each one off a match is exactly the match without it (det_check -Full identical to fork_84d8653). Game code of ebe1e40; the commits after it change only tests and docs.

**T-43, Unlock everything (test)** (`scripts/team/unlock_all.gd`, `docs/DESIGN.md` A17).
- A toggle "Unlock everything (test)" at the right end of the start screen's difficulty row (`start_screen.gd` `_build_difficulty`, `_toggle_unlock`; off the first time) and the launch option `--unlock-all` (`=0` turns a remembered "on" off). `Game.unlock_everything` is remembered between runs in `user://halcyon_settings.cfg` next to the difficulty (`Game.use_remembered_unlock()`, `Game.choose_unlock()`). The HUD's top bar shows UNLOCKED (`hud_top_bar.gd`, a hidden "Tags" label under the wave timer), and the F9 note records the switch (`note_writer.gd` "setup").
- The one query: `UnlockAll.is_unlocked(buyer)` (`unlock_all.gd:39`). It says yes for exactly two buyers, only while the option is on: the human's own pilot record (`PilotProfile.is_human`: the pilot seat, and the Admiral's own record) and the treasury of the team whose Admiral is the human (`TeamState.admiral == "human"`). Computer pilots (teammates too), the other team and the computer Admirals are never unlocked.
- Pilot seat: every price counts as 0 (`PilotProfileShop.pay_price()`) for gear, repair kits, ship classes and modules, the Mk II upgrade, a buy-back and an extractor, and no ship class is locked (`PilotProfileShop.hull_unlocked()`). The hangar's cards say so (Free, 0 credits, no "Locked"). What selling and trading in give back is NOT changed, so the credits never go down but a swap of hulls pays the usual trade-in. The team's research and facilities are not touched: teammates get no help.
- Admiral seat: `TeamState.can_afford()` and `spend()` (the treasury's one gate) say yes and pay nothing; `TeamTech.facility_blocker()` and `tech_blocker()` do not ask for the earlier facility or research (any facility or research may be queued at once; the queue sizes stay), a queued research runs without the Research Module (`TeamTech.tick`), and torpedo turrets and repair bays need no research (`AdmiralCommand.turret_blocker()`, `bay_blocker()`; the board's bay button and "Needs the ..." line follow). A module or research still takes its time, and a finished research helps the whole team as research always does.
- Readings of the lead's text (change any): "with any unlock it needs" is read as the facility and research rules waived, not as instant completion. Fleet Command minion buying is not waived: `MinionDirector.controlled()` also stops the free waves, so the Fleet Command Module is queued (free, no prerequisites, 60 s) and then works as usual. Variant-only features' own prerequisites (Fleet Doctrine's Research Module) are not waived. Placing any unit anywhere on the map (a sandbox spawner) is not included.

**T-44, Slow motion (test)** (`scripts/world/world_speed.gd`, `docs/DESIGN.md` A17, `docs/PITFALLS.md`).
- The backquote key (action "slow_motion", `game_input_map.gd`; the key was unused) steps the world speed 1x -> 0.75x -> 0.5x -> 1x at any time in a match, also while paused (`hud_input.gd`, step 2b). `--slow=0.75` or `--slow=0.5` starts a match slowed. A pause keeps the speed; a new match starts at 1x. SPEED 0.75x / 0.5x shows in the top bar; the help text lists the key and the F9 note records the speed.
- One setting, `World.speed` (`WorldSpeed`): a factor and a counter. The tick length, Godot's physics rate and `Engine.time_scale` are untouched: `World._physics_process` (`world.gd:457`) takes its tick when the counter, which adds the factor on every physics frame, reaches 1: every second frame at 0.5x, three in four at 0.75x, each tick exactly as long as at 1x. `World.ticked` says whether the frame had a tick; `main.gd`'s report counter and the stats recorder count only those. A later game-speed control can drive `factor`; speeds above 1x (extra full-length ticks) are not built.
- A key tapped on a frame without a tick is kept for the next tick (`WorldSpeed.just_pressed`, used by `PlayerController` and the Recall feature): without it a tap on the shield arrows, 1 to 4, R, F or V would be lost half the time at 0.5x (shown by the control tap in `tests/speed_check.gd --speed-taps`).
- What the first version missed: the 0.5x and 0.75x det_hash runs differed from the 1x run (first hash line at t=50 and t=60). `tests/tick_trace.gd` (one full-precision hash per World tick) found the first differing tick, t=44.6: one pilot ship bumping into rocks, with the same place, speed and turn the tick before and a different bump response. Cause: Godot's physics server steps at the end of every physics frame and each step refits its collision search tree; two steps between two ticks instead of one reorder the tree, and the order in which `move_and_slide` meets several rocks changes the bump. Fix: `WorldSpeed.step()` switches the 2D physics server off (`PhysicsServer2D.set_active()`, the switch the pause uses) on the frames without a tick, so it steps once per tick (`world_speed.gd` `_switch_physics`; at 1x nothing is switched; the World hands the server back in `_exit_tree`). After it the traces are identical tick for tick over 70 s at 0.5x and 0.75x, and the det_hash lines identical over 300 s.
- Visual effects in `_process`: the effects' particles and rings (`effects.gd`) and the ships' engine flames (`ship_visual.gd`, `speed_scale`) follow `World.speed.factor`. Not followed: the camera, HUD, menus, note box, pause, the minimap, the fog picture's refresh (0.2 s of real time), the HUD's fading lines, the alien glow pulse (real time), sound playback, and the variant-only bounty ring and recall bar.
- Cadence in a window (checked in an off-screen window: 801 physics frames for 10 s of match at 0.75x, 1200 at 0.5x, the exact patterns below): 0.5x is T.T.T.: the world moves 30 times a second, each position held for two 60 Hz frames, the steady look of a 30 fps game while the camera and HUD run at full rate. 0.75x is T.TTT.TTT.: the world stands still for one frame in four, a small regular hitch at 15 Hz that shows on fast ships. It cannot be spread more evenly (one skip in four is the most even). If it is bad, the one change to propose is drawing the units at a position interpolated between their last two ticks (render interpolation, drawing only, no effect on the match); it is not built.

**T-45, the camera while paused** (`scripts/camera/camera_rig.gd`, `docs/DESIGN.md` A15 and A17).
- P still pauses (`get_tree().paused`), but the camera rig has `process_mode` always (`camera_rig.gd:105`): pan (keys, screen edge, middle-drag, minimap click), zoom, Space and follow work in a pause. W/A/S/D pan even a flying pilot's camera while paused (`camera_rig.gd:373`: a paused ship does not fly). While a text box has the keyboard (the note box) the camera ignores every key and the mouse (`_typing()`), so typing never moves it. Unpausing goes on from the same place.
- What runs while paused: `CameraRig._process`, `_unhandled_input` (wheel, middle button) and the focus notification, plus the HUD (which always did). The camera reads the match and writes only its own view: no order, no click on the map, no timer. A paused match draws nothing new, so when the view moves the camera also asks the pictures that depend on it (the units' visuals, the shots, the effects, the Admiral's map tools) to draw again (`_redraw_if_paused()`); that changes nothing of the match.
- The v0.2.2 pause menu is not in this branch: the second of the two to merge checks the camera under it. There is no screenshot key (Windows' Win+Shift+S and PrtScn work).

Checks:
- det_check -Full (the drawing code runs), seed 7, against fork_84d8653, on the export of ebe1e40: normal IDENTICAL over 180 lines (END t=900 192 units 73960193), late IDENTICAL over 60 lines (END t=1800 190 units 88a25058). The export of the measuring-tools commit alone (tests only) was IDENTICAL on the plain det_check too (180 and 60 lines).
- The speed check, det_hash seed 7, 300 s, through run_batch on the same game code: 1x, `--slow=0.75` and `--slow=0.5` give the same 60 hash lines and END t=300 158 units ce80de51, equal to the first 60 lines of fork_84d8653's normal baseline. tests/speed_check.gd prints the length of every World tick at each speed: 0.016666666667 s, the same at 1x, 0.75x and 0.5x, equal to Godot's step, `Engine.time_scale` 1.
- run_checks ALL OK on the export of the last commit that changed a test (import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty, and the new unlock_pilot, unlock_admiral, unlock_default, unlock_spectator, speed_half, speed_three_quarters, speed_normal, speed_keys, speed_taps, camera_pause). Also 0 failures: note_check (pilot, Admiral, all-AI), camera_check (three seats), display_check, hit_reach_check; ui_layout_check clean at 1280x720 and 1366x657 with both tags showing; the start screen toggle and the settings file (a scratch user data folder). doc_check clean on the 38 changed or new scripts. SCRIPT ERRORS: 0 in every log.
- New tests: tests/unlock_check.gd, tests/speed_check.gd, tests/camera_pause_check.gd (also saves pictures in a window), tests/tick_trace.gd; the new run_checks entries are in the lead's hand-over. API_INDEX.md rebuilt with tools/api_index.py.
- Pictures for the user: the start screen with the option off and on, the HUD with UNLOCKED and SPEED 0.5x, and the paused camera.

### 2026-10-22: user test fork, minions handle heavier, small pilot ships easier to hit, turrets with no shields or repair (T-42, T-46, T-47)

- The user's words (Tue 10-20). T-42: "Minions in general are to maneuverable . Top speed is fine. Lets reduce their acceleration by 10% and maneuverability by 20%"; asked whether that meant the path or the aim, the answer was "Split it the way I meant it" (along the path x0.9, sideways x0.8, turn x0.8). T-46: "The hit boxes of the small ships should be slightly larger, maybe 10%."; the answers "Hits only (Recommended)" and "Pilot ships only". T-47: "I would like to remove the shields from turrets and make it so they cannot be repaired by any means". One branch, one commit each (the probes first, then T-42, T-46, T-47), each measured on its own commit against the one before. The play changes on purpose, so the determinism baselines are made again. `Rules.DAMAGE_MODIFIERS_REMOVED` untouched; no other number changed.
- **T-42, the minions handle heavier.** Before, a minion's path had one knob: `accel` limited every change of its velocity, speeding up and changing direction alike (`combat_move` through `move_toward`, `lane_move` through `Steer.seek`); `turn` only swung the nose. Now both go through one minion-only step, `MinionFlight.steer` (`minion_flight.gd:54`, called at :119 and :158). The change wanted (the wanted velocity less the velocity) is split against the way the minion flies into `along` (speeding up or slowing down) and `side` (bending the path), and may be at most `ALONG_ACCEL_MUL` 0.9 x accel x dt along and `SIDE_ACCEL_MUL` 0.8 x accel x dt across (`minions.gd:70` and :76), as an ellipse: inside it the whole change is taken (the velocity becomes the wanted one, as `move_toward` does when close), outside it the change is shrunk, keeping its direction, until it touches the ellipse. Two separate limits would have let a half-and-half change use both at once (about 1.2 x today's accel), so the minions would have turned faster than before; the ellipse is never more than accel in any direction. At `MIN_HEADING_SPEED` 10 world units per second or less (`minions.gd:80`, the speed `lane_move` already used to decide facing) there is no direction of travel and the whole change counts as along. `lane_move` works out the wanted velocity `Steer.seek` works out (at the wave's pace, in proportion to the distance inside 300, stopping within 1); `Steer.seek` itself is untouched, so the mining drones, wards and repair bays fly as before. Turn: 3.0, 1.6 and 1.0 became 2.4, 1.28 and 0.8 (`minions.gd:53`, :56, :59). Unchanged: speed, `FORMATION_SPEED`, the rock push, each type's fighting pattern and wanted velocities. The jungle's Snub Fighters (`snub_fighter.gd`, launched by a Derelict Carrier) are not minions and fly as before: one `move_toward` limit of accel 520 for every velocity change, nose turn 3.2.
- **T-46, the small pilot ships are 10% bigger for shots.** `Unit.hit_radius()` (`unit.gd:264`) is the size rounds, beams and blasts see and the AI aims against: `radius` for every unit; `Ship.hit_radius()` (`ship.gd:250`) returns `radius` x `Rules.SMALL_PILOT_HIT_MUL` (1.1, `rules.gd:139`) for pilot ships of size class small: the Scout 9, Fighter 12, Lance Fighter 13 and Bomber 17 count 9.9, 13.2, 14.3 and 18.7. It is worked out on each call, not stored (the hot loops call it; the sim speed lines of the match logs show no cost under the shared load: 398, 385 and 365 ms per sim-second for the before, T-42 and T-46 sets). Every hit test uses it: `Unit.hit_t` (`unit.gd:256`, rounds and beams), the cheap reject in `ProjectilesHitScan.scan` (`projectiles_hit_scan.gd:70`, which must agree with `hit_t`), the blast edge in `CombatBeamArea.area` (`combat_beam_area.gd:106`) and the Mothership Barrage's reach (`admiral_assets.gd:241`); flak bursts, torpedoes and point defense are rounds and go through these, there is no separate fuse test. The hash pads (`Projectiles.HASH_PAD` 60, `MAX_UNIT_RADIUS` 260) cover 18.7 by far. The AI fires against the target's hit size: `pilot_combat.gd` :175, :177, :184, :235, :257, `weapon_mount_targeting.gd` :62 and :113, the turrets (`turret.gd` :182, :233), the minions (`minion.gd` :263, :270) and the jungle monsters (`derelict.gd:125`). The body stays on `radius`: the physics circle, the push-apart, rocks, walls, docking, landing, vision and spacing. The full list of reads of a unit's own circle, sorted, is in the hand-back (88 reads: 4 hit, 12 AI aim, 33 body, 39 other).
- **T-47, turrets with no shields that nothing can repair.** `TurretData` "shield" is 0 for both types (was 600 and 700); `Turret.setup` makes a shield pool only for a type with a shield number, so `shields` stays null (no pool, no bar, nothing to refill; the Admiral's build menu and tooltips never showed the number, DESIGN.md did and now says "no shield"). `Unit.heal()` (`unit.gd:299`), the one place every repair goes through, refuses turrets: that stops both of the Logistics Corvette's repairs from raising a turret's hull, its repair drones and its Emergency Repair (which still heals ships, repair bays and the mothership). The drones' work search skips turrets (`repair_drone.gd:209`), so no drone hovers over a turret it cannot mend. The AI's choice to use Emergency Repair looks at its own hull only (`pilot_combat.gd:190`); the Admiral's supply drones serve pilot ships only; no other place counts turrets as repair work. Every assignment to `hull` and every `heal` call was looked for: the writes that still raise a built turret's hull are the build itself (`turret.gd`, 30% to 100% while it builds), Platform Armor (`world_research.gd`, which keeps the share of hull left) and the `node_persist` rule set's slow repair of a rebuilt turret (`node_persist.gd:82` and :94: a rebuilt turret starts at 50% and gains 1% of its hull a second). The last is **the one repair left**: `node_persist` is off by default (`rules.gd` VARIANT_DEFAULTS) but on in the Council's pick (`council_presets.gd`), the planned standard rule set; the lead asks the user whether to close it. Repair bays (their defence shield and repairs), wards, the motherships and every ship are as before. The Logistics Corvette's hangar text no longer says it heals "structures".
- Tests: four measuring tests, all reading the game and drawing no random numbers (commit 1): `tests/minion_agility_probe.gd` (per minion type, in combat and on the lane, through the real `MinionFlight` functions: standstill to top speed, a full reverse, the tightest circle held at top speed, the nose's half turn), `tests/hit_size_probe.gd` (per hull and minion type: how big the target is for a round, a beam and a blast, its physics circle, the push-apart distance), `tests/turret_repair_probe.gd` (a damaged turret, repair bay and fighter beside a Logistics Corvette) and `tests/change_probe.gd` (a whole AI match, one CHANGE_PROBE_JSON line: minion lifetimes and killers, pilot ship deaths and lifetimes per hull, time to kill, money, turrets built, lost and standing, hull gained by turrets, what the Logistics repairs raised; `--late` starts at 25:00). Two checks assert, each with its change's commit: `tests/hit_size_check.gd` (the four small hulls count 1.1 x radius for a round, a beam and a blast; a round passing at 1.05 x radius plus its own radius hits them and one at 1.15 x misses; every other hull and every minion counts exactly its radius, so the same pass misses a Snub-Fighter; the physics circle and the push-apart distance are unchanged) and `tests/turret_repair_check.gd` (a damaged turret beside a Logistics Corvette that sends drones and uses Emergency Repair keeps its hull exactly and has no shield; a damaged repair bay beside it is repaired). Both print "N failures", 0 on the builds they belong to.
- Checks:
  - Check 0, the probe commit (650ffdb; the later probe commit d17b9bd changes only tests and docs): det_check, plain, against fork_84d8653: normal IDENTICAL over 180 lines, late IDENTICAL over 60.
  - The agility table, before (d17b9bd) against after (a3f46c9), every type and both ways (combat and lane): standstill to top speed x1.111, a full reverse x1.111, the tightest circle at top speed x1.250, the nose's half turn x1.250. For the Snub-Fighter in combat: 0.960 s to 1.067 s, 1.920 s to 2.133 s, 460.8 to 575.9 units, 1.047 s to 1.309 s.
  - The hit probe, before (a3f46c9) against after (ed30a37): round, beam and blast edges of the Scout 9.00 to 9.90, Fighter 12.00 to 13.20, Lance Fighter 13.00 to 14.30, Bomber 17.00 to 18.70; every other hull and the minions unchanged; physics circle and push-apart distance (twice the radius) unchanged for every hull. hit_size_check 0 failures.
  - The turret probe, before (ed30a37) against after (79722fb): the turret starts at 1,000 hull (40%) and 600 shield; after 40 s it has 1,843.6 hull and 600 shield before, 1,000.0 hull (exactly) and 0 shield after; the damaged repair bay goes from 241.3 to 600 in both. turret_repair_check 0 failures.
  - The new play, det_check -Full twice (export of 79722fb, the game code of the tip): run A and run B are IDENTICAL on every line. Normal: 180 hash lines, END t=900 181 units 4ad96dbc. Late: 60 hash lines, END t=1800 184 units ae1a8b3c. First difference from fork_84d8653: normal at t=30 (hash 9461e736 became 9461e735, both 52 units), late at its first line, t=1510 (53c75f38 became 643d6092, both 119 units). Proposed as the next baselines of the play build.
  - run_checks (with hit_size_check and turret_repair_check added) ALL OK on the T-47 build: import, load_all, bot_pilot, support_probe, both HUD tours, both wheel checks, difficulty, hit_size, turret_repair. script_error_scan 0 on every match log; doc_check clean on the 24 changed scripts (headers 24/24, functions 170/170, members 415/415).
- The measurement: the same six seeds (301 to 306), all-AI, `--skill-jitter`, 30 minutes, `tests/change_probe.gd` through the PC queue; each change on its own commit against the one before. Counts are totals of the six matches, and a match that ended early plays fewer minutes, so the per-10-minute rows are the fair comparison.

| T-42 (before d17b9bd, after a3f46c9) | before | after | change |
|---|---|---|---|
| mean life of a dead minion, s (Snub-Fighter, Light Bomber, Patrol Leader) | 59.4, 55.9, 102.1 | 61.0, 57.7, 103.5 | +3%, +3%, +1% |
| minions killed by pilots (the pilots' last hits, the same count) | 2,725 | 2,326 | -15% (per 10 match minutes 151.4 to 136.7, -10%) |
| pilot deaths | 1,430 | 1,270 | -11% (per 10 minutes 79.4 to 74.7, -6%) |
| pilot income per minute (credits earned, both teams) | 9,268 | 8,894 | -4% |
| treasury income per minute | 4,336 | 4,262 | -2% |
| side-lane (top, bottom) turret losses | 33 (Aurelian 23, Vhorr 10) | 32 (16, 16) | -3% (per 10 minutes 1.83 to 1.88) |
| mid-lane turret losses | 28 | 34 | +21% (per 10 minutes 1.56 to 2.00) |
| matches that ended before 30:00 | 0 | 2 (seed 303, Vhorr at 24:54; seed 305, Aurelian at 25:12) | |
| match minutes played | 180.0 | 170.1 | |

| T-46 (before a3f46c9, after ed30a37) | before | after | change |
|---|---|---|---|
| small pilot ships launched / dead: Scout, Fighter, Lance Fighter, Bomber | 59/43, 1,057/589, 192/99, 338/275 | 77/54, 1,130/660, 231/132, 375/318 | deaths +26%, +12%, +33%, +16% |
| small pilot ships dead in all (per 100 match minutes) | 1,006 (591) | 1,164 (647) | +16% (+9%) |
| their life, launch to death: mean, median (s) | 91.6, 51.8 | 87.7, 58.5 | -4%, +13% |
| time to kill on small ships: median, mean (s) | 6.80, 7.71 | 7.10, 7.75 | +4%, +0% |
| pilot kills (per 10 match minutes) | 818 (48.1) | 926 (51.4) | +13% (+7%) |
| all pilot deaths (per 10 match minutes) | 1,270 (74.7) | 1,470 (81.7) | +16% (+9%) |
| matches that ended before 30:00 | 2 | 0 | the two early endings of the T-42 set did not repeat |

| T-47 (before ed30a37, after 79722fb) | before | after | change |
|---|---|---|---|
| turrets lost by minute 10, 20, 30 (both sides) | 3, 38, 69 | 4, 41, 85 | +33%, +8%, +23% |
| of them Aurelian's / Vhorr's by minute 30 | 38 / 31 | 38 / 47 | +0% / +52% |
| first turret lost per seed 301 to 306 (min:s) | 11:07, 8:24, 8:15, 10:03, 10:41, 8:14 | 10:55, 8:20, 7:53, 10:04, 10:35, 8:08 | 4 to 22 s earlier in five seeds, 1 s later in one |
| turret lifetime of the lost, mean, median (s, from the start of the build) | 347, 147 | 355, 196 | +2%, +34% |
| Logistics drones: hull raised on ships, turrets, repair bays, mothership | 416, 684, 39, 0 | 593, 0, 40, 13 | turrets -100% |
| Emergency Repair: uses; hull raised on ships | 14; 751 | 15; 955 | |
| seconds a Logistics drone had a turret as its target | 85 | 0 | -100% |
| hull gained by built turrets from any source | 24,131 | 20,211 | -16% (what is left can only be Platform Armor's rise) |
| matches that ended before 30:00 | 0 | 1 (seed 302, Aurelian at 29:51) | |

- What the numbers say. T-42: the minions live a little longer (+1% to +3%) and the pilots kill fewer of them (-10% per minute) and die less (-6% per minute); the prediction that last hits and income would rise was not borne out, they fell by 10% and 4%. Two of six matches ended before 30:00 where none did, which six matches cannot tell from the chaos of any change to a seeded match (the T-46 set, with the same seeds and the next change in, has none). T-46: the small ships die 9% more often per minute and the pilots score 7% more kills per minute; their time to kill is the same, so the larger circle shows in how often a shot lands rather than in how long a fight lasts. T-47: the turrets fall 23% more often per match minute (Vhorr's far more than Aurelian's), about what 600 to 700 shield points on 2,500 to 3,000 hull would give (a fifth or a quarter), and the first turret falls within 25 s of where it did; the 684 hull points the Logistics drones put on turrets in six matches are gone, and the hull they raise on ships went from 416 to 593.
- Notes for the next reader: `run_batch` counts a run "ok" only if its log has one of a few markers, so the match probe prints CHANGE_PROBE_JSON (contains PROBE_JSON) and the two checks, which print only "N failures", show "no result line" there although they passed. The probes put positions in 32-bit numbers, so sizes are rounded to a hundredth. One Light Bomber in the T-42 set (seed 302) was still alive at the end after 913.6 s: the only Snub-Fighter or Light Bomber older than 240 s in any of the 24 matches (no minion position is logged, so whether it was stuck is not known). T-26 (the Lance's circle, radius above 13 and at most 17) and T-12 (the bombers redrawn) will sit on top of the 10%: the hit size follows `radius`.

## T-11 and T-10: the Aurelian steel look and the rotating turrets (drawing only, test branch)

- What changed: every Aurelian pilot hull has a new look, and every gun that swings is drawn as a small turret on its ship, turned the way the gun points. Nothing in a match changes: no number, mount, hit circle or random draw moved (det -Full must be IDENTICAL to the fork_271b7b4 files; see the checks below).
- New files: `scripts/data/aurelian_shapes.gd` (AurelianShapes: the ten hulls as named pieces), `scripts/entities/aurelian_paint.gd` (AurelianPaint: merges the pieces into the outline, draws a whole hull as one triangle command, an outline and the engine lights), `scripts/data/turret_shapes.gd` (TurretShapes: one silhouette per weapon class in two team styles, the class of each weapon, the size of each hull's turrets) and `scripts/entities/turret_paint.gd` (TurretPaint). Test side: `tests/lib/gallery_aurelian.gd` (the shape checks, part of `hull_gallery --check`), `tests/lib/gallery_turrets.gd` (the turret sheet picture), `--bench-look=steel` and `--live-look=steel` in `tests/lib/gallery_measure.gd`. Changed: `ship_visual.gd` (the Aurelian hull branch, the flames follow the hull's own nozzle points, the turrets are drawn after the hull), `palette.gd` (the steel colours), `hull_gallery.gd`.
- The look (original, inspired by the clean, angular, panelled military ships of the Star Citizen universe): steel hulls with lighter armour plates, glass canopies, amber stripes and running lights, dark engine housings with warm nozzle lights, an amber outline. Scout: the Blade, one flat wedge with no separate fuselage, a swallowtail rear and two nozzles. Fighter: a thin fuselage with forward-swept blade wings and twin guns at the nose. Lance: a heavy fighter (twin booms, a fat gondola, an H tail). Bomber: a stout torpedo carrier with a dark bay, wide wings and a rear turret socket. Logistics: a boxy tender with two repair bays (green plus). Support: a sensor ring (an open octagon) round a long spine. The other directions drawn for the Scout (a nail with a bead; the Comet, a round sensor head on a thin boom with swept-back tail fins and one engine bell, the first Scout of the game) and for the Support (a box with a dish) are not in the game: it sits in tests/lib/option_hulls.gd, for the hull gallery's options sheet only. Flak: a wide armoured frigate with side sponsons. Ion: a long spear with a nose emitter and hooked nacelles. Destroyer: a long stepped slab with PD sponsons. Battlecruiser: a stepped capital with PD shoulders, hangar decks and a bridge tower.
- Pieces: each hull is a list of named pieces (kind core, wing, engine, mount, rear_turret or module), each with its attach point and a mirror flag; the outline is merged from them at load, never kept by hand. Nozzles per hull (the flames stay one stream; each nozzle can later get its own): Flak 3, Ion 3, Destroyer 4, Battlecruiser 5. Every gun mount of ships.gd lies inside the new outline (the mounts did not move: the hull is drawn round them), and every turret or automatic mount has a socket piece at its place. `hull_gallery --check` verifies all of this.
- Turrets: one silhouette per weapon class, the same for both teams: point defense two thin barrels, flak a boxy block with three barrels, light turret one short barrel, heavy cannon one long barrel with a muzzle brake, ion turret a forked dish with a lens, tail gun (the Bomber's rear gunner, by the weapon id `tail_gun`) a round ball with two stubs, torpedo turret two fat tubes; a coloured tip also tells the classes apart. Aurelian turrets are armoured octagons with straight barrels and an amber rim, Vhorr turrets thorned discs with fangs and a red rim. Fixed guns get no turret. A turret is never drawn smaller than 6 screen pixels reach, and a ship shorter than 22 screen pixels shows none. Cinder's hull tables are untouched: Vhorr hulls get the live turrets over their existing drawings. The Scum ships' turrets are left to their own item.
- To add a hull: give it an `AurelianShapes.HULLS` entry (and a `HULL_TU` size in `TurretShapes` if it has turrets). To change a look, edit the pieces; the outline follows.
- How to run: `hull_gallery` (pictures, now ending with `turret_sheet.png`), `hull_gallery --check` (headless, 0 failures wanted), `--bench --bench-look=steel` and `--live --live-look=steel` (frame time of the steel hulls and the turrets against the plain old look).

## T-11 part 2: the mothership, the lane towers and the Repair Bay redrawn (drawing only, test branch)

- What changed: the Aurelian mothership, the lane point-defense tower, the lane torpedo tower and the Admiral's Repair Bay have new drawings, and the guns of all four now show as turret heads (the same silhouettes as on the pilot ships). The three small structures are drawn for both teams (Cinder's in the Vhorr dress: the same pieces in the Cinder colours with thorns); the Cinder mothership keeps its citadel and its gun dots. Nothing in a match changes: no hit shape, gun spot, mount or number moved (det -Full must be IDENTICAL to the fork_271b7b4 files).
- The looks (the user's picks, Sat 2026-10-24, from three options each by one designer each): mothership B "Slipway" (two parallel hulls with a dark slip between them lit by amber rails, two cross-decks, a stern brace, a V prow, a socket under each of its 21 gun spots); point-defense tower B "Anchor" (a hexagonal hub with three legs ending in forked feet, the stem leg toward its node); torpedo tower A "Rampart" (a wide armoured bar across the lane, a square deck for the head, three fixed torpedo cells on each half); Repair Bay B "Clover" (four berth pads round a hub, a green bar on each, the repair plus as a body).
- New files: scripts/data/structure_shapes.gd (StructureShapes: the four drawings as named pieces, with the Vhorr thorn pieces; generated by the design tools, never edited by hand), 	ests/lib/gallery_structures.gd (the shape checks, part of hull_gallery --check) and 	ests/lib/gallery_scene.gd (hull_gallery --scene: the staged fight pictures). Changed: urelian_paint.gd (structure(), the Vhorr dress, a see-through draw, a structure counted by its biggest span, pieces that only meet through a later piece are merged), 	urret_paint.gd (draw_unit_mounts()), unit_visual.gd (the four draw functions), palette.gd (the Vhorr dress colours), 	urret_shapes.gd (the four structures' head sizes in HULL_TU).
- Sizes: the drawing may reach 15% of the radius past the hit shape (the mothership's capsule, a tower's or the bay's circle); hull_gallery --check verifies that, every gun spot inside the outline with a socket under it, the nozzles, no holes, and that the outline keeps every piece. The head sizes: mothership 0.5 design units per turret unit, point-defense tower 11, torpedo tower 5, Repair Bay 7.5.
- To change a look: edit the pieces in the design source and emit the tables; the outline follows. To add a structure: a StructureShapes.SHAPES entry and a HULL_TU size.
- How to run: hull_gallery (pictures: the close-ups of the towers, the bay and the mothership of both teams), hull_gallery --check (headless, 0 failures wanted), hull_gallery --scene (windowed; a staged fight with both teams' structures in one view).

### 2026-10-24: user test fork, Council's pick is the standard rules; the rule-set row goes (T-90)

- The user's words. Sun 2026-10-18: "lets git rid of the settings option on the start screen and incorporate the "Council's Pick" as the standard rules." Sat 2026-10-24: "In the user test branch, can we get rid of the "rule set" selection so it can disappear from main?" The timing: "Tonight, after 20:40". T-27's damage-modifier switch is not touched (`Rules.DAMAGE_MODIFIERS_REMOVED` stays false as the play build has it); no other tuning, no new mechanics, and the content of "pick" is unchanged.
- The default game plays Council's pick. With no `--preset`, every match (a human seat, all-AI, every test, tour and probe) gets the pairs of `CouncilPresets.variant_string("pick")`, so the three damage-modifier pairs still follow `Rules.damage_modifiers_removed()` as before; `--variant` is still applied last. `CouncilPresets.STANDARD` ("pick") names it, `Game._build_variants()` reads it, and `Game.apply_preset()` is gone (nothing calls it any more).
- The old rules stay for tests and research as launch options, no screen offers them: `--preset=none` is the old standard rules (a preset with no pairs: every variant at its default, Fleet Command limit 30, node lock 60 s ...), `--preset=within` and `--preset=pick` are as before. An unknown name (also `--preset=None`) still refuses the match: "PRESET UNKNOWN", exit code 3.
- The start screen: the RULE SET heading, its buttons and its description are gone (`_build_rule_sets()`, `_choose_rules()`, `_show_rules()`, the descriptions `BLURBS`, `BLURBS_REMOVED`, `TODAY_LABEL`, `TODAY_BLURB` and `blurb()` with them); the difficulty row now sits right under the rules text. A game launched with an unknown `--preset` shows one amber line there ("The launch option --preset was not understood: ... Relaunch the game without it, or with one of those names. The seat buttons stay off until you do.") and both seat buttons stay off, because no screen can clear that error any more (a wrong `--difficulty` is still cleared by pressing a level). Without the error no node is added. Every text of the start screen and of the How to play pages was read: none speaks of rule sets, and none says which rules are played, so no text needed new words.
- What is recorded. The match log prints `preset: <name> = <pairs>` for every match (`preset: none = (every variant at its default)` for the old rules), and the F9 note holds `"preset"` ("pick", "none", "within") and `"rule_set"` (CouncilPresets.LABELS: "the standard rules (Council's pick)", "the old standard rules (--preset=none)", "Within requirements (--preset=within)"). `variants_changed` of the note still lists what differs from `Rules.VARIANT_DEFAULTS`, so a standard-rules note lists the pick's eight pairs (and the three damage-modifier pairs are among them). `tests/note_check.gd` now checks that the note names the preset that was played and its label.
- A new test, `tests/rules_check.gd` (README, CODE_GUIDE): it writes out again what each preset switches on and checks the match's variants, installed feature modules and Fleet Command limit (30 or 60); builds the start screen (no word about rule sets, presets or the council, the difficulty row right under the rules text, both seat buttons on), builds it again with an unknown `--preset` pretended (one line, both buttons off), and reads the How to play pages. Run once per `--preset`; it prints "rules_check: 0 failures".
- Tests that assumed the old rules by default: none needed a change. All 20 `run_checks` entries pass on the new standard rules unchanged, and so do `assist_check`, `hit_reach_check`, `map_check`, `display_check`, `opening_fix_check` (seeds 301 and 302), `difficulty_check` and `unlock_check` with `--settings-check` (scratch user data folder) and `note_check` for a pilot, an admiral, a spectator and `--preset=none`. Nothing was loosened.
- Comments that said "30 in the standard rules" or "both rule sets use 60" were corrected (fleet_cap, admiral_sinks, tech, rules, feature_registry). Docs: DESIGN.md (A3 gets the paragraph "Rules of the match"; C22, A5, the Fleet Command module, turrets and research lines follow), CODE_GUIDE.md (the glossary entry, the features row, the tests paragraph), README (the rules section, the launch options, the Tests block), FORK_MANIFEST.md (the preset table gets the `none` row, the start-screen line, the difficulty line, the `fleet_cap` row), API_INDEX.md (rebuilt).
- Checks, all on the committed export of 3c6d7ee (the game code of the tip; later commits are docs only). Old rules, `--preset=none`, `det_check -Full` against fork_271b7b4 (through a copy of det_check that passes the option): normal IDENTICAL over 180 lines (END t=900 181 units, 4ad96dbc), late IDENTICAL over 60 (END t=1800 184 units, ae1a8b3c). New standard rules, `det_check -Full` twice (A and B): identical to each other on every line, and `--preset=pick` gives the same lines as no option. **The proposed new baselines of the standard rules: normal 180 lines, END t=900 189 units, f2ba4199; late 60 lines, END t=1800 172 units, d374fd49.** The first difference from fork_271b7b4 is the first hash line of each run (normal t=5, same 52 units, hash 274a1bc3 against ea600b83; late t=1505, 55 units against 75). At t=5 `node_persist:on` alone causes it (probably through the order in which the AI admiral builds its nodes; not looked into): each of the other seven pairs alone, on top of `--preset=none`, leaves the t=5 line at ea600b83. run_checks CHECKS ALL OK (20 of 20), script_error_scan 0 over every log of this item, doc_check clean on every changed script, `tools/ui_layout_check.py` clean for the pilot and admiral tours at 1280x720, 1366x657 and 1920x1080 (the start screen is the pilot tour's last step), windowed `ui_tour` pictures at 1280x720 and 1366x657 (the second window opened at 1366x720, the game's minimum height) with the start screen as `p10_start.png`; an unknown `--preset` exits with code 3.
- The smoke of the new standard against the old rules (all-AI `fun_probe`, sim-only, `--skill-jitter`, seeds 361 to 366, capped at 60 minutes; six matches a side, so not a trusted number, and nothing was tuned from it). Every match of the new standard rules ended, all six, between 23 and 44 minutes (mean 34.4); under the old rules 5 of 6 ended (mean 48.2 minutes) and seed 366 stood at the 60-minute cap with both mothership hulls at 100% (a rerun with a 120-minute cap did not end either: a stalemate, both mothership hulls at 100% at 63:00). The per-seed fun score is the fun model applied to that one match, so it is rough; the batch scores are 75.9 (new standard) against 58.6 (old rules).

| seed | old rules: winner | ended (match min) | fun | new standard: winner | ended (match min) | fun |
|---|---|---|---|---|---|---|
| 361 | Aurelian | 43.2 | 59.4 | Aurelian | 23.1 | 63.5 |
| 362 | Aurelian | 30.7 | 68.9 | Vhorr | 43.5 | 77.3 |
| 363 | Aurelian | 59.4 | 49.5 | Aurelian | 41.0 | 74.4 |
| 364 | Aurelian | 57.0 | 49.4 | Vhorr | 36.6 | 76.8 |
| 365 | Aurelian | 50.5 | 54.4 | Aurelian | 29.5 | 73.5 |
| 366 | none (not ended at 60.0) | 60.0 cap | 51.5 | Vhorr | 32.4 | 81.4 |

- What this means for other work. Everything that runs the test branch without `--preset` now plays Council's pick, so its numbers change (fleet limit 60, the AI admiral's Fleet Command and wards, persistent nodes, the 4 s hyperspace spool, gear Mk II, the Lance and Bomber rules, the minion cap); work that must compare with the old rules passes `--preset=none`. The det baselines of the play build become the ones above when this merges. Main is not touched.
- A quirk met on the way (PITFALLS): `docs/CODE_GUIDE.md` is stored with CRLF line endings, and `git add` under `core.autocrlf=true` rewrote the whole file with LF; the file was restored byte for byte from the base commit plus the four edited lines.

### 2026-10-24: user test fork, play as the Vhorr: a team choice on the start screen (T-108)

- The user's words (Sat 10-24): "For the test branch to be ready by tomorrow so we can merge it into main, i want you to add the ability to play as the Vhoor in the start screen". Read as: the Vhorr (team 1, red, `Rules.CINDER`) is playable in either seat, chosen on the start screen. The lead's defaults, taken: Aurelian stays the default; the map is not mirrored (as Vhorr you start on the right at Vhorr's mothership and the camera starts there); the team colours stay; the other team is all computer.
- The setting: `Game.human_team` (`Rules.HALCYON` or `Rules.CINDER`), from the launch option `--team=aurelian|vhorr` (any capitals; `Rules.team_from_name()`), else the start screen's TEAM row, which `Game.choose_team()` also remembers in `user://halcyon_settings.cfg` (the key `team`, next to the difficulty; only the start screen reads the file). An unknown word, or a bare `--team`, stops the match at its start ("TEAM UNKNOWN", exit code 3), like an unknown `--preset`. `WorldSetup.build` copies it into the new `World.human_team` (a spectator keeps Aurelian there for the camera; their fog still shows everything), seats the human pilot in slot 0 of that team or the human Admiral in its chair (and the extra Admiral record, slot 12, on it), gives the other team the computer Admiral and the difficulty's income multiplier, and prints one extra log line ("team: the human plays for Vhorr") only for Vhorr.
- What follows the human's team: the camera's start and its home spot (`CameraRig.setup`, `_home_spot`), the command overlay and the Admiral board (`team` set from the world), the Admiral's pop-ups (`Hud._on_admiral_result`, `CommandOrders.run`), the toast "You command <team>." and the Pilot card's "An AI Admiral commands <team>.", and the auto-launch of the human's Fighter (`main.gd`, the F1 overlay), which bought it from team 0's notebook. Already right and unchanged: the fog and what is drawn (`World.viewer_team`), the minimap, the HUD top bar ("(us)" and "(enemy)"), the kill feed (amber is good news for the viewer's team, red bad news: a meaning, not the team colour), the end screen (Victory or Defeat), the scoreboard, the slipstream bands, sound, the waypoint, `Difficulty.team_income_mult()` and the surrender and mutiny features (they read `world.human.team`). Kept on purpose, because they mean the team itself: the palette and the paint (`AurelianPaint`, `CinderPaint`, `TurretPaint`, `UnitVisual`), the callsign lists, `MapLayout.lane_points`, the minimap's chevron direction, and the AI's "which half of the map is mine" tests (`PilotGoals`, `AdmiralBuilder`, `AdmiralSinksFeature`, `RedeployFeature`, `SalvageCoreFeature`). The top bar keeps Aurelian's column on the left and Vhorr's on the right.
- Start screen: a TEAM row under the DIFFICULTY row (heading and two toggle buttons in one row, each in its team's colour, and a one-line description: "Vhorr: you play the red team and start at its mothership on the right of the map. The computer plays Aurelian."), built by its own function `_build_team()` so T-90's removal of the RULE SET row merged without touching it. An unknown `--team` shows a line and keeps both seat buttons off until a team is picked (as for `--difficulty`).
- Tests (new): `tests/team_check.gd` (run_checks entries team_pilot_aurelian, team_pilot_vhorr, team_admiral_aurelian, team_admiral_vhorr, team_default, team_spectator and team_unknown): the human's record, the Admiral's chair, the computer Admirals, the AI brains of the other team's pilots, the income multiplier, the fog and what is drawn, the launched ship, the camera's start, the HUD's map tools, the Admiral board, the pop-up hint and the top bar; `--settings-check=<text>` also tests the TEAM row and the settings file (scratch APPDATA, PITFALLS). `tests/team_shots.gd` (a windowed two-minute tour of a real match on the chosen team that saves pictures; for people to look at). `tests/ui_tour.gd` now buys from, builds for and feeds news to the human's own team and mirrors its map spots for Vhorr; `tests/rules_check.gd` leaves the remembered team alone.
- Checks (on an export of the merged tip's game code, c5ec265; the later commits are tests and docs only, checked on an export of 8c43177):
  - det_check -Full against the fork_ad3486a files (the standard rules of T-90; no team option = Aurelian): normal IDENTICAL over 180 lines (END t=900 189 units f2ba4199), late IDENTICAL over 60 lines (END t=1800 172 units d374fd49). With `--team=aurelian` (through a copy of det_check with `-ExtraOpts`; det_hash is an all-AI run, so a spectator ignores the option): IDENTICAL too, same END lines.
  - run_checks (the tested copy, 27 entries: the 20 old and the 7 new) CHECKS ALL OK on the c5ec265 export; the team entries and load_all again on the 8c43177 export. `rules_check` 0 failures for the default, `--preset=none`, `within` and `pick`. `team_check --settings-check` 16 settings checks pass. `--team=vhoor` and a bare `--team` exit with code 3.
  - tools/ui_layout_check.py "UI LAYOUT: clean" for pilot and Admiral at 1280x720, 1366x657, 1600x900 and 1920x1080, as Aurelian (c5ec265) and as Vhorr (8c43177); windowed ui_tour as Vhorr at 1280x720 and 1366x657 (the second window opened at 1366x720): 18 and 13 pictures, 0 script errors; both seat buttons are in view on the start screen at both sizes.
  - Windowed team_shots as Vhorr, a pilot (123 s) and an Admiral (122 s): 0 script errors. script_error_scan: SCRIPT ERRORS 0 over every raw log of this item; doc_check clean on the 18 changed scripts (211/211 functions, 306/306 members).
- Notes for the next reader: the first commit's message has no blank line after its subject (its whole paragraph is the subject); nothing was amended. `det_check` cannot pass a launch option, so a det proof of a launch option needs a copy of det_check that passes one. `CODE_GUIDE.md` is the one CRLF file: it was edited byte for byte, and its diff to the base is a handful of lines.

### 2026-10-24: user test fork, the menus' highlight colour follows the human's team (T-109)

- The user's words (Sat 10-24, answering the lead's question whether the menus' highlight colour should stay amber for both teams; the case against was that when you play Vhorr, amber is the enemy's colour): "Follow the team". Its option text: "The highlights turn red when you play the Vhorr. This is a new small item with its own price, so it won't be in tomorrow's play." Read as: with Vhorr chosen the interface's highlight is red in the places that were amber; Aurelian and a spectator keep today's amber exactly; no new art, no new mechanics.
- One place decides the colour: `Palette.accent(team)` gives amber (`Palette.AMBER`) for Aurelian and for anything else (a spectator has no side) and the vein red (`Palette.CINDER_VEIN`, the glow on a Vhorr ship) for Vhorr. `UiKit.accent_team` says which side the interface is built for and `UiKit.accent()` gives the colour; `Hud.setup()` sets the side from `World.human_team` (a spectator's world says Aurelian) and `StartScreen` sets it from the TEAM row, and makes its theme again the moment a team button is pressed (so the chosen difficulty button, both seat buttons and the top line change colour live). `UiKit.make_theme()` builds the pressed and hovered button borders, the pressed text, the progress bar fill, the filled button (`PrimaryButton`) and the named highlight text from `accent()`; the named look `AmberText` is now `AccentText` (three scenes, and the top bar's test tags use it).
- The colour: the vein red (1.0, 0.38, 0.22). Contrast against the panel fill (WCAG ratio): amber 7.78, vein red 5.79 (against the dark box fill 8.23 and 6.12); the team red `Palette.CINDER` is 4.21 and `CINDER_SIDE_JET` 7.64 but pink; the dark text on a filled button is 8.95 on amber and 6.66 on vein red. The vein red reads as red and clears the 4.5 that small text needs; it is also a different shade from the team red, so a Vhorr name line and a highlight line are not the same colour.
- Follows the team (the interface's highlight): the first line of the top-left panel (pilot name and credits, the Admiral's treasury), the pressed, hovered and chosen buttons, the filled buttons (Launch, New match, the start screen's seat buttons), the selected hangar, Admiral board and help tabs, a card's border and its price line, the Admiral board's out-flying note, the test tags (UNLOCKED, SPEED), your own scoreboard and end-screen rows, the shield focus outline and "Focus:" line, the active energy-routing button and "ability active" line, the help headings, the note box, the recall bar, the rally point (the map ring, the cross and the label, and the minimap ring), the start screen's top line, chosen difficulty and Unlock buttons and launch-option line.
- Stays as it was (a meaning, or Aurelian itself): the team colours (the top bar's columns, paint, the minimap, the start screen's two team buttons); the kill feed's amber for good news and red for bad news, and the end screen's Victory (amber) and Defeat (red) title, which follow the same rule; the banner tones (the map tool hint and a feature's "amber" notice; red stays danger); the health, shield and energy bars; the weapons-routing pip and overcharge text (amber means Weapons there); the comeback bounty's gold (the rings and the banner); Aurelian's paint. A red highlight next to the red bad-news lines reads acceptably: the highlight is the brighter, more orange vein red and sits on the top-left panel, the tabs and the buttons, the feed's bad news is the team red on the right; a red price on an affordable card is the one place that could be read as a warning, and blocked cards stay grey.
- Tests: `tests/team_check.gd` now also checks, for each team, the highlight colour that the HUD uses (UiKit, the HUD's theme, the top-left panel's first line, the test tags, a selected card, the hangar's or Admiral board's tabs and the Launch button) and that a start screen made with each team chosen is highlighted in that team's colour (its chosen difficulty button, both seat buttons and the top line, while the two team buttons keep their own colours); with `--settings-check=<text>` it also presses the start screen's team buttons and checks that the colour changes at once and comes back with the remembered pick. The existing team entries of `run_checks` run it, and the spectator with a HUD gets its own entry (team_spectator_hud). `tests/team_shots.gd` now photographs the pilot in the open hangar and ends with the start screen.
- Checks (on exports of the game code, 6bd93a8; the later commits are tests and docs only): det_check -Full against the fork_ad3486a files with no option: normal IDENTICAL over 180 lines (END t=900 189 units f2ba4199), late IDENTICAL over 60 lines (END t=1800 172 units d374fd49). run_checks CHECKS ALL OK (the 29 live entries and team_spectator_hud), script_error_scan SCRIPT ERRORS 0 over every log, doc_check clean on the 27 changed scripts, tools/ui_layout_check.py "UI LAYOUT: clean" for the pilot and Admiral tours as Aurelian and as Vhorr at 1280x720, 1366x657, 1600x900 and 1920x1080, windowed team_shots pictures for each team and seat (0 script errors). The Aurelian pictures were taken before and after the change: the start screen's card, the hangar's panel, the Admiral board and the top-left panel differ in no pixel by more than 7 of 255 (the translucent panels show the moving world a little).
- Notes for the next reader: `UiKit.accent_team` is a static variable, set once when a screen is built (the HUD, the start screen); a colour that is a meaning (good and bad news, tones, bars) must not use `UiKit.accent()`.

### 2026-10-25: v0.3.0 release prep: the test branch without its test tools

- The user's choices (Sun 10-25): what goes into v0.3.0 is "Test branch + T-109 (Recommended)" (the 6v6 stage stays out); the test tools: "Leave them out (Recommended)"; the user's look: "Pictures and review only". So the release is the test branch up to T-109 with its test tools taken out of the game, nothing else changed: every play change of the test branch ships.
- Removed, one commit each (the order is the commit order):
  1. The note key (F9) and its browser downloads: `NoteBox` and its scene, `NoteWriter`, the `note` input action, the key's handling in `HudInput`, `Hud` and `HudBanner`, the F9 reminder of `HudSlots`, the help page's Notes entry and its browser sentences, `--feedback-dir`, `CouncilPresets.LABELS` (only the notes read it), `tests/note_check.gd` and the PITFALLS entry about the browser's Block.
  2. Unlock everything: `UnlockAll`, `Game.unlock_everything` with its remembered choice, `--unlock-all`, the start screen's toggle, the UNLOCKED tag, `PilotProfile.pay_price()` and `hull_unlocked()` with the shop's twins, and every `UnlockAll.is_unlocked` check, which reads the plain rule again (shop, hangar, buyback, gear Mk II, extractor, `TeamState.can_afford` and `spend`, the facility and research blockers, the research countdown, the torpedo-turret and repair-bay checks, the Admiral board lines); `tests/unlock_check.gd`.
  3. Slow motion: `WorldSpeed` was used only by slow motion, so the whole class went, not just the key: `World.speed` and `World.ticked`, the speed step and `_exit_tree` of the World, `--slow`, the backquote key and its input action, the SPEED tag and the top bar's whole Tags label, the scaling in `Effects` and the flames of `ShipVisual`; `PlayerController` and the Recall feature read `Input.is_action_just_pressed` again, and the report of `main.gd` counts every tick again; `tests/speed_check.gd` and `tests/tick_trace.gd`, two PITFALLS entries.
  4. The camera while paused: `CameraRig` is the last release's (no `process_mode` always, no `_typing()`, no `_redraw_if_paused()`, `_process` is one function again) and keeps its play changes (the start in front of the human's own mothership, the home spot, the note about pixels); `tests/camera_pause_check.gd`; DESIGN A17 (it held only the three tools) and the Test tools sections of the README and the manifest.
  5. `tests/ship_action_shots.gd` (test only; it called the clip maker, so it went first).
  6. The feel-check clip and the no-fight warning: `FightWatch` and `--big-fight`, `tests/lib/shot_clip.gd`; `MainReport` and `tests/spectate_shots.gd` are the last release's again.
  7. The stats recorder (`StatsRecorder`, `StatsPilotRecord`, `--record-stats` and main.gd's hooks). It is a test-only yardstick of the test branch's first stage; it only watched the match.
  8. Test-only scripts and plans: `tests/map_check.gd` with its three parts, `tools/utf_compare.py`, `docs/USER_FORK_PLAN.md` and `docs/FINISHED_GAME.md`; `tests/perf_probe.gd` and `tests/admiral_audit.gd` are the last release's again. The manifest, the README, DESIGN, CODE_GUIDE, PITFALLS and RECIPES lose their words about the test branch (PITFALLS also its entries and section about the branch and the lead's tools).
  9. The version words and release notes (`docs/RELEASE_NOTES.md`, `release_notes/v0.3.0.md`, the READMEs), and three comments that said "the test branch".
- Kept on purpose: the damage-modifiers switch (`Rules.DAMAGE_MODIFIERS_REMOVED`, false: the modifiers apply), the measure-only part switches of `DrawParts` (`--bench-off`), every test that `run_checks` runs, the checks and probes of the play changes that ship (assist money, farming, difficulty, hit size, minion handling, turret repair, the waves, the display, the hull gallery and its parts, the photo tours of the waves and of the chosen team), and the small per-hull counts of `pilot_audit`.
- Nothing in a match changes. The tools were off in every match that did not use them, and the places that read them are back to the last release's code.
- Checks (the game code is the committed tip c297830; the later commits are docs only). `det_check -Full` against the standard-rules baselines of the test branch (normal 180 lines, late 60 lines, seed 7): normal IDENTICAL over 180 lines, late IDENTICAL over 60 lines, run on the commit before the last comment-only commit, so the release plays exactly as the test branch does. `run_checks` CHECKS ALL OK on the export of c297830: 20 entries OK and the 10 entries of the removed tools (unlock x4, speed x5, camera_pause) print SKIP, as `Needs` makes them for a copy without their scripts. `script_error_scan`: SCRIPT ERRORS 0 over every log of the runs (40 files each time). `doc_check` clean on the 48 scripts the release changes (443/443 functions, 557/557 members) and on all 312 scripts. A grep of the tree for the removed names finds nothing outside this log and `docs/RELEASE_NOTES.md`. A grep for paths, tool and machine names and e-mail addresses finds nothing in the lines this release adds; the whole tree still holds the hits that main 7bdff20 already had (its `deep_dive/`, `fun_plan/reports/` and `session_tools/` files).

### 2026-10-25: hotfix: the exported game laid the HUD out wrong (the browser build and the Windows data)

- The report (the user, Sun 10-25, with a picture of the website at 2000x745; "From the start", "It stays like this"): "Looks like the hud bug is back again". From the first second of a match the controls hint, the "me" panel (name, credits, K/D/A), the six gear slots, the pop-up hint, the big message ("Docked at the mothership") and "Next minion wave" were drawn on top of one another in a box of about 665x80 pixels at the top left; the top bar sat at the left edge instead of the centre; the minimap and the ship readout kept their anchors. The same was seen in v0.1.0's browser build and was not reproduced then, because every check ran on the project folder.
- Measured first, with the web build of main (v0.3.0) in headless Edge: `--test=ui_tour --dump-layout` printed by the page, fed to `tools/ui_layout_check.py`. The check finds the pile-up at once. The same tour on the exported game data (`godot --headless --main-pack index.pck`, the way the release workflow's smoke test starts it) gives the same pile-up on the desktop; on the project folder it is clean. So it is not the browser: it is what the export makes of the scenes.
- The cause: the export turns text scenes into binary ones. In the binary `scenes/ui/hud.scn` every scene instance that `hud.tscn` gives no properties of its own (TopBar, MePanel, Feed, Banner, Toast, Slots) carries `layout_mode = 0` (position mode) and, for all but the "me" panel, `anchors_preset = 0` (top left), and loading it resets the anchors and offsets that the instanced scene's own root sets (the top bar's centre anchor, the feed's right anchor, the gear slots' bottom anchor, the "me" panel's 8 pixel offsets). ShipStatus and Minimap name their anchors in `hud.tscn`, so they stayed where they belong. Read from `PackedScene.get_state()` of the exported pack against the text export: the stored properties of those nodes differ in exactly those entries. Turning `editor/export/convert_text_resources_to_binary` off alone gives 0 problems; script compression made no difference.
- The fix: that one setting, off, in `project.godot` (`[editor]` section). The export keeps the text scenes that the checks run on, so the exported game is laid out as the project is. No script, scene, rule, number, look or control changes; the pack is a little smaller.
- Before and after, layout problem lines of the pilot tour in the browser build (counts move by a few lines from run to run with the moment a line fades):

  | size | 1024x600 | 1280x600 | 1280x720 | 1366x657 | 1366x768 | 1536x730 | 1600x789 | 1920x969 | 1920x1080 | 2560x1300 | 2000x745 |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | main (before) | 338 | 338 | 338 | 325 | 338 | 325 | 325 | 305 | 318 | 305 | 305-325 |
  | fixed (after) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

  The Admiral tour at 1280x720 and 2000x745: 125 and 121 before, 0 and 0 after. At 1280x720 the pilot's 338 lines are 106 overlaps, 224 covered texts and 8 off-screen controls.
- Checks (on an export of the fix commit f6c77bb; the later commits change docs only): `det_check -Full` against the standard-rules baselines (normal 180 lines, late 60 lines, seed 7): normal IDENTICAL over 180 lines (END t=900 189 units f2ba4199), late IDENTICAL over 60 lines (END t=1800 172 units d374fd49). `run_checks` CHECKS ALL OK (the live entries; the removed tools' entries print SKIP); `script_error_scan` SCRIPT ERRORS 0 over the 42 logs of the run. `tools/ui_layout_check.py` "UI LAYOUT: clean" on the project folder for the pilot and Admiral tours at 1280x720, 1366x657 and 1920x1080, before and after. The browser check above ran on the export of f6c77bb; its console shows only the engine's usual lines at exit.
- Notes for the next reader: a check that reads the project folder cannot see this kind of bug; look at the exported data too (PITFALLS has the steps). The measuring build keeps `tests/` in a copy of the Web preset, because the UI tour lives there; the shipped preset leaves it out. The v0.3.0 Windows download has the same defect (the Windows preset's exported data gives the same pile-up; the exe itself was not run), so the fix ships as v0.3.1. Nothing in the release workflow or `run_checks` tests an exported pack's layout yet; until one does, every push to main gets the browser check above.
