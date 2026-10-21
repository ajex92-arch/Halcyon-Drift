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

### Rule sets

Under the rules text, above the seats, the RULE SET row of the start screen
picks the rules of the coming match:

- **Standard rules** (chosen at first): the rules of v0.1.0, exactly as before.
- **Within requirements**: the fun council's changes that keep every
  requirement of the design (the Fleet Command limit of 60 is the requirement
  since 2026-10-17, `docs/DESIGN.md` C22): late minions no
  longer out-scale pilots, the Lance hunts lone big ships, Bomber seats and
  torpedoes are retuned, the AI admiral spends a big treasury and builds the
  Hyperspace Module early, a hyperspace launch to a repair bay spools for 4
  seconds instead of 6 (AI pilots can also jump to a friendly turret near the
  fight; the hangar offers you repair bays only), gear has Mk II upgrades, and
  Fleet Command allows up to 60 bought minions.
- **Council's pick**: "Within requirements" plus persistent nodes (a node
  whose turret was destroyed stays locked longer, a turret built there again
  starts at half hull and then only repairs 1% a second, and the AI Admiral
  rebuilds the nodes nearest its own mothership first).

(The fun council is the project's review step that combined the six fun
experiments and tested the combinations; `docs/FUN_PLAN.md` section 6.)

From a terminal: `godot --path remake -- --preset=within` (or `pick`).
`docs/RELEASE_NOTES.md` explains the rule sets in plain words, and
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

## Layout

- `docs/` holds the design and its history:
  - `CODE_GUIDE.md` is the place to start reading the code: what each part
    does, one tick step by step, and a glossary, in plain words.
  - `CODE_STYLE.md` is how the code is written (comments and modules).
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
    (v0.2.0 adds the rule sets).
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
    gets when its variant key (or a rule set) turns it on.
  - `ui/`: the HUD and panels.
  - `audio/`: synthesized sound cues.
- `tests/` holds headless probes and playtest harnesses. They run through
  Main with `--test=<name>`; see each file's header for its exact command.
  `tests/lib/` holds helpers the tests share.
- `tools/` holds Python helpers (standard library only), such as
  `api_index.py`.

## Tests

```
# 12-minute all-AI match with a status report every minute
godot --headless --path remake --fixed-fps 60 -- --all-ai --test=match_probe --secs=720

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

# Ships stuck in the asteroids: a line for every stuck episode and every trap of a whole match
godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=305 --skill-jitter --sim-only --test=stuck_trace2 --secs=1500

# Every script and scene loads
godot --headless --path remake -- --auto --all-ai --test=load_all

# Windowed UI screenshots (pilot or admiral)
godot --path remake --resolution 1280x720 -- --auto --role=pilot --bot=tour --test=ui_tour --shots=<dir>
```

Command-line options are documented at the top of
`scripts/autoload/game.gd`. They include `--variant=` for the rule
variants (see `Rules.VARIANT_DEFAULTS`; every switch is listed in
`FORK_MANIFEST.md`, and all are off unless you set them), and `--preset=` for
the rule sets (`scripts/data/council_presets.gd`).
