# Halcyon Drift (remake)

A top-down space MOBA at Homeworld scale, built in Godot 4.7 with GDScript
only. The battle is fought in the Halcyon Drift, an asteroid belt. Two
motherships face each other across three lanes joined by a crossing down
the middle. Minion waves push every lane, Admirals build turrets at the
asteroid resource nodes, and an asteroid jungle full of derelict monsters
sits between the lanes. It is 13 vs 13: 12 pilots and 1
Admiral per side, with AI filling every seat you don't take. The match ends
only when a mothership is destroyed.

## Run it

Open `remake/project.godot` in Godot 4.7 and press Play. You can also run
it from a terminal. On a fresh copy, import once first: a copy without
Godot's import cache (the `.godot` folder) shows an empty window, because
the game's scripts cannot find each other yet.

```
godot --headless --path remake --import
godot --path remake
```

The start screen asks you to choose a seat, and the choice is locked for the
match:

- **Admiral**: spend the team treasury on mining drones, turrets, repair
  bays, wards, the Homeworld 2 style research board and mothership
  upgrades. You can also place the rally waypoint, move the mothership from
  20:00 and use Fleet Command late on. 12 AI pilots fly for you.
- **Pilot**: buy a ship, modules, pilot gear and repair kits with your own
  credits, then hold your lane, push turrets with your minions and break the
  enemy mothership. An AI Admiral commands.

Press **H** in game for the full how-to-play.

### The standard rules

Every match plays the standard rules: the fun council's "Council's pick". The
start screen offers no choice of rules. They are changes that keep every
requirement of the design (the Fleet Command limit of 60 is the requirement
since 2026-10-17, `docs/DESIGN.md` C22) plus persistent nodes:

- late minions no longer out-scale pilots, the Lance hunts lone big ships,
  Bomber seats and torpedoes are retuned, the AI admiral spends a big treasury
  and builds the Hyperspace Module early, a hyperspace launch to a repair bay
  spools for 4 seconds instead of 6 (AI pilots can also jump to a friendly
  turret near the fight; the hangar offers you repair bays only), gear has Mk II
  upgrades, and Fleet Command allows up to 60 bought minions;
- persistent nodes: a node whose turret was destroyed stays locked longer, a
  turret built there again starts at half hull and then only repairs 1% a
  second, and the AI Admiral rebuilds the nodes nearest its own mothership
  first.

For tests and research the older rules are launch options, not screens:
`--preset=none` plays the old standard rules of v0.1.0 (every variant at its
default, Fleet Command limit 30), `--preset=within` the list above without the
persistent nodes, and `--preset=pick` the standard rules (what a match plays
when no `--preset` is given). `--variant` is applied last and can change one key
of any of them. A name that is not one of these stops the match at its start. The
match log names the preset played.

(The fun council is the project's review step that combined the six fun
experiments and tested the combinations; `docs/FUN_PLAN.md` section 6.)

The damage modifiers (the damage table and the other fixed damage
multipliers, `docs/DESIGN.md` A5) are behind one switch,
`Rules.DAMAGE_MODIFIERS_REMOVED`. The switch is off in this build (false: the
modifiers are applied), and the standard rules above are described that way.
With the switch on (the modifiers removed), "late minions no longer out-scale
pilots" and the Bomber torpedo retune do nothing, and the Lance has no rear-zone
bonus.

The start screen has a DIFFICULTY row under the rules text: Easy, Medium, Hard, Very hard and
Extreme. In a match where one human plays against the AI, the level multiplies
everything the enemy team earns (its pilots' credits and its Admiral's treasury)
by 0.75, 1.0, 1.25, 1.5 or 2.0. Your own team's income, a match with nobody
playing and every test are never changed. New games start on Medium, which plays
exactly as before, and the last pick is remembered between runs.

The start screen's TEAM row (Aurelian or Vhorr) picks the team you play for,
as a pilot or as the Admiral. Aurelian (amber) starts on the left of the map and
Vhorr (red) on the right; the map is not mirrored, so as Vhorr your camera and
your mothership are on the right. The other team is all computer. New games
start on Aurelian, and the last pick is remembered between runs. From a
terminal: `godot --path remake -- --team=vhorr` (or `aurelian`; an unknown word
stops the match).

From a terminal: `godot --path remake -- --preset=none` (or `within`, or `pick`;
tests and research only), and
`godot --path remake -- --difficulty=hard` (`easy`, `medium`, `hard`, `very_hard`
or `extreme`).
`docs/RELEASE_NOTES.md` says in plain words what each release changes, and
`FORK_MANIFEST.md` lists every other switch.

## Controls

| Key | Action |
|---|---|
| Mouse | Aim (the ship turns to face it; big ships' turrets track it) |
| W / S | Thrust / brake and reverse |
| A / D (Q / E) | Slide left / right |
| Shift | Boost (strike craft) |
| Left click | Fire |
| Right click / G | Ship ability |
| Ctrl (hold) | Lock heading, so turrets keep tracking while the hull holds its facing |
| Arrow keys | Focus shields front / rear / left / right (press again to balance) |
| 1 / 2 / 3 / 4 | Energy to weapons / shields / engines / balanced |
| R | Use a repair kit |
| F | Dock at the mothership (when close) / launch when docked |
| B | Hangar |
| Tab | Admiral board (Admiral) / scoreboard while held (pilots) |
| Space | Center the camera on your ship (on your mothership when you have no ship); hold it to keep the camera centered as you fly, let go and it is free again |
| Screen edge, middle-drag, minimap click | Move the camera anywhere on the map (W / A / S / D too, while you are not flying) |
| C | Admiral: switch the camera between free and following your own ship |
| V | Flight assist on/off |
| Wheel, + / - | Zoom (pilots are limited by ship size) |
| P | Pause |
| H | How to play |
| Esc | Close panels, cancel a map tool |
| F11 / Alt+Enter | Switch between the window and borderless fullscreen (in a browser, Alt+Enter; F11 stays the browser's own) |

## Layout

- `docs/` holds the design and its history:
  - `CODE_GUIDE.md` is the place to start reading the code: what each part
    does, one tick step by step, and a glossary, in plain words.
  - `CODE_STYLE.md` is how the code is written (comments and modules).
  - `PITFALLS.md` lists the engine and tooling quirks we have hit, each with its fix.
  - `RECIPES.md` says where each common change lives (a hull, a weapon, a wave, a research item, a HUD panel, a
    test, a palette colour), which checks it needs and which files never to touch.
  - `DESIGN.md` is the design (rules, numbers, conflicts and how each was
    resolved, architecture).
  - `PROGRESS.md` is the work log.
  - `API_INDEX.md` lists every script's public functions and signals
    (rebuilt by `tools/api_index.py`).
  - `USER_REQUIREMENTS_2026-10-13.md` holds the requirements verbatim.
  - `FUN_PLAN.md`, `FUN_RESEARCH.md` and `FUN_METRICS.md` are the fun
    experiments: the rules, the research behind them, and how fun is
    measured.
  - `RELEASE_NOTES.md` says what each release changes, in plain words
    (newest first).
  - `../FORK_MANIFEST.md` and `fork_manifests/` list every switch the fun
    experiments added and what each one does.
- `scenes/` holds one scene per entity, world piece and UI screen.
- `scripts/` holds the code:
  - `data/`: tuning tables (ships, weapons, items, modules, tech, minions,
    turrets, map layout, rules).
  - `world/`: the match loop, map, vision, projectiles and combat.
  - `entities/`: ships, minions, turrets, repair bays, drones, wards,
    derelicts and the mothership.
  - `team/`: team state, pilot profiles and the economy.
  - `ai/`: pilot AI and Admiral AI.
  - `control/`: the player controller and Admiral commands.
  - `features/`: optional mechanics, one module each, that a match only
    gets when its variant key (or the standard rules) turns it on.
  - `ui/`: the HUD and panels.
  - `audio/`: synthesized sound cues.
- `tests/` holds headless probes and playtest harnesses. They run through
  Main with `--test=<name>`; see each file's header for its exact command.
  `tests/lib/` holds helpers the tests share.
- `tools/` holds Python helpers (standard library only), such as
  `api_index.py` and `draw_cost_table.py` (turns the hull gallery's parts
  bench output into the draw-cost table).

## Tests

```
# 12-minute all-AI match with a status report every minute
godot --headless --path remake --fixed-fps 60 -- --all-ai --test=match_probe --secs=720

# The minion waves lane by lane: live minions, how far they get, turrets lost, last-hit credits
godot --headless --path remake --fixed-fps 60 -- --all-ai --skill-jitter --test=lane_probe --secs=1200

# Pilot income by source (last hits, minion assists, kills, camps, ore ...), one INCOME_JSON line
godot --headless --path remake --fixed-fps 60 -- --all-ai --skill-jitter --sim-only --test=income_probe --secs=900

# What the lane pilots do with their time: idle and parked seconds, last hits per lane pilot, pilot deaths,
# stuck ships, and how far the enemy minions are from our front minion, one FARMING_PROBE_JSON line
godot --headless --path remake --fixed-fps 60 -- --all-ai --skill-jitter --sim-only --test=farming_probe --secs=1800

# The difficulty setting multiplies the right money by the right number (try every --difficulty level;
# --role=pilot or admiral scales the enemy team, --all-ai scales nothing)
godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --difficulty=hard --test=difficulty_check

# The team you play for: --team=aurelian or --team=vhorr puts the human (pilot or Admiral) on that team and
# nothing human on the other (the seats, the income multiplier, the fog, the ship, the camera's start, the HUD's
# map tools and Admiral board); --all-ai ignores it. --settings-check=<text> also tests the start screen's TEAM row
# and the settings file (APPDATA pointing at an empty scratch folder whose name holds the text). An unknown team,
# such as --team=vhoor, prints TEAM UNKNOWN and stops the match (exit code 3)
godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --team=vhorr --difficulty=hard --bot=team --force-hud --test=team_check

# What the human sees on the chosen team: a windowed two-minute tour of a real match that saves a few pictures
# (a pilot flies under a computer brain, an Admiral opens the board); --role=admiral for the other seat
godot --path remake --resolution 1280x720 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --auto --role=pilot --team=vhorr --bot=team --test=team_shots --shots=<dir>

# The rules of a match: it plays the standard rules (Council's pick) unless --preset names another (try --preset=none,
# within and pick), its variants and feature modules are the preset's, and the start screen has no choice of rules
godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --test=rules_check

# Both teams' money by source and their ships by size class in a match with one human seat,
# one DIFFICULTY_PROBE_JSON line (--bank gives everybody a huge purse so every level plays the same match)
godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --skill-jitter --sim-only --difficulty=hard --test=difficulty_probe --secs=1800

# The exact pay-out check for assist money: who is paid how much for a minion or a pilot kill
godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=assist_check

# Pictures of the first minion waves, one per lane (needs a window)
godot --path remake --resolution 1280x720 -- --all-ai --speed=2 --test=wave_shots --shots=<dir> --times=72

# Mothership balance duels (A..I)
godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --variant=retreat:none --test=ms_duel --scenario=H

# Repair bays, drones, kits and wards
godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=support_probe

# Player controls through real input actions
godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=bot_pilot

# The AI opening's rules: the waypoint, no second opening, the first Crossing turret
godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=301 --test=opening_fix_check

# The camera: Space, the free pilot camera and the zoom-out limit
# (--role=pilot or admiral; for the spectator use --all-ai instead of --auto --role --bot)
godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=camera_check

# The mouse wheel over an open menu never zooms the camera behind it (--role=pilot or admiral)
godot --headless --path remake -- --auto --role=admiral --bot=tour --force-hud --test=wheel_check

# A round that grazes the rim of a big hull's hit circle is found by the hit search
# (the two frigates and the two capitals; a few seconds)
godot --headless --path remake -- --auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_reach_check

# How nimble the three minion types are: standstill to top speed, a full reverse, the tightest circle at
# top speed and the nose's half turn, in combat and on the lane (a few seconds; one AGILITY_PROBE_JSON line)
godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=minion_agility_probe

# How big each hull and minion is for a round, a beam and a blast, its physics circle and the distance at
# which two ships are pushed apart (a few seconds; one HIT_PROBE_JSON line)
godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_size_probe

# The small pilot ships (Scout, Fighter, Lance Fighter, Bomber) are 10% bigger for rounds, beams and blasts and
# nothing else is, and their body is unchanged (a few seconds; prints "hit_size_check: N failures")
godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hit_size_check

# Turrets have no shields and nothing repairs one: a damaged turret beside a Logistics Corvette (drones and
# Emergency Repair) keeps its hull exactly, a damaged repair bay beside it is repaired (40 match seconds;
# prints "turret_repair_check: N failures")
godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=turret_repair_check

# A damaged turret, repair bay and fighter beside a Logistics Corvette: hulls and the turret's shield second by
# second (40 match seconds; one TURRET_PROBE_JSON line)
godot --headless --path remake -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=turret_repair_probe

# What the minions, the small pilot ships and the turrets go through in a match: minion lifetimes and killers,
# pilot ship deaths and lifetimes per hull, time to kill, money, turrets built and lost, hull gained by turrets
# and what the Logistics Corvettes' repairs raised, one CHANGE_PROBE_JSON line (--late starts at 25:00)
godot --headless --path remake --fixed-fps 60 -- --all-ai --skill-jitter --sim-only --test=change_probe --secs=1800

# Every script and scene loads
godot --headless --path remake -- --auto --all-ai --test=load_all

# The window: stretch, smallest size, the fullscreen key (F11 / Alt+Enter);
# with a window (see the header of tests/display_check.gd) it also prints the real sizes
godot --headless --path remake -- --auto --all-ai --test=display_check

# Windowed UI screenshots (pilot or admiral)
godot --path remake --resolution 1280x720 -- --auto --role=pilot --bot=tour --test=ui_tour --shots=<dir>

# The hull gallery's frame cost: what each part of the ship and unit drawing costs
# (flames, shield arcs, drift arrow, bars, name tag, hull outline, the every-frame
# redraw) in ms per frame and draw calls. Needs a window; --bench-busy makes the
# crowd drift and burn its engines (options: the header of tests/hull_gallery.gd).
godot --path remake --resolution 1920x1080 --position 30000,30000 --disable-vsync --audio-driver Dummy -- --all-ai --no-pilots --no-jungle --no-admiral-ai --test=hull_gallery --bench --bench-parts --bench-busy > bench.txt
python -B -I remake/tools/draw_cost_table.py bench.txt
```

Command-line options are documented at the top of
`scripts/autoload/game.gd`. They include `--bench-off=flames,arcs,arrow,bars,name,outline,redraw`
(test only: leaves single parts of the ship drawing out to measure what each
costs; without it nothing is left out), `--variant=` for the rule
variants (see `Rules.VARIANT_DEFAULTS`; every switch is listed in
`FORK_MANIFEST.md`, and all are off unless you set them), `--preset=none|within|pick`
for the rules played (tests and research; without it a match plays the standard
rules, `pick`; `scripts/data/council_presets.gd`), `--difficulty=` for the
difficulty level (`scripts/data/difficulty.gd`), `--team=aurelian|vhorr` for the
team you play for (`Game.human_team`), and
`--damage-modifiers-removed` (or `=0`) to play, for one run, with the damage
modifiers removed (or kept) whatever `Rules.DAMAGE_MODIFIERS_REMOVED` says.
