# How the code is written (style guide)

Read this before changing any script. It has two parts: how we **explain**
the code (comments), and how we **split** the code into small pieces
(modules). The goal: someone who has never programmed can open any file and
understand what it is for, and anyone can find, change or replace one piece
without touching the rest.

---

## Part 1: Comments that a beginner can follow

Write as if you are explaining the game to a curious child who is good at
listening: short sentences, everyday words, one idea at a time. Keep every
number and rule exact. Simple words, never vague ones.

### 1. Every file starts with a "what is this" block

```gdscript
class_name MiningDrone
extends Unit
## WHAT THIS IS: a small robot ship that flies to a rock field, scoops up
## ore (the game's money), and carries it home to the mothership.
##
## HOW IT WORKS: it picks the safest node with ore left, flies there, mines
## for a few seconds, flies home, and hands the ore to its team. Then it
## goes again. If enemies shoot it down, the team remembers the spot and
## avoids it for a while.
##
## WHO USES IT: World creates it (World.spawn_mining_drone); the admiral
## orders new ones (AdmiralCommand.build_drone); Economy pays out the ore.
##
## (Technical notes for programmers can follow here, as before.)
```

- **WHAT THIS IS**: one or two sentences, no jargon.
- **HOW IT WORKS**: the story of what happens, step by step.
- **WHO USES IT**: which other files call it, or which it calls. This is how
  a reader finds their way around.

### 2. Every function says what it does and why

```gdscript
## Should this pilot fly home to go shopping? Returns the reason as text
## ("hull:destroyer" means "to buy a destroyer"), or "" for "no, keep
## fighting". We never shop in the middle of our own siege, and never fly
## across the whole map just for small gear.
func _wants_shopping(ship: Ship) -> String:
```

- Say what goes in and what comes out when the names don't make it obvious.
- Say **why** it exists if that isn't obvious ("so the slow capital ships
  arrive together").

### 3. Every variable and constant gets a short note

```gdscript
## How long (in seconds) a destroyed turret's spot stays locked before the
## admiral can build there again.
const REBUILD_LOCK := 60.0
```

Always give the **unit**: seconds, per second, world units (1 world unit is
about one pixel at normal zoom), credits, 0..1 fractions.

### 4. Inline comments walk through the steps

Put a short comment above every small group of lines that does one step.
Roughly one comment for every 3-8 lines of logic:

```gdscript
	# Step 1: find the closest enemy turret that is shooting our minions.
	...
	# Step 2: only attack it if our minions are standing in its range,
	# because turrets take less damage when no minions are near them.
	...
```

### 5. Explain jargon the first time a file uses it

A file must not assume the reader knows words like *tick*, *hull*,
*spatial hash*, *lerp* or *bitmask*. Either explain it in one plain line the
first time it shows up, or point at the glossary:
`(see "tick" in docs/CODE_GUIDE.md)`.

### 6. Keep history out of the comments

Keep the beginner explanations this guide asks for (sections 1 to 5 above).
Dates, the user's quotes, decision records, ticket IDs and "fixed on" notes
come out of code comments; they live in docs/PROGRESS.md. A comment
says why the code is the way it is, never what changed when.

A quick test: if the sentence would still be true in a copy of the game that
never had the old version, it explains the code, so keep it. If it only makes
sense to someone who remembers the old version (a date, a quote, a ticket ID,
"this replaces", "fixed on", "playtest showed"), it is history, so move it to
PROGRESS.md. Keep the reason, drop the event: in the example below, "the short
wait stops it turning back and forth" stays, and "playtest 01-01 showed" goes.

Before (a made-up example: the ticket T-00, the date, the constant and the
playtest are invented, and the user's words are left as a placeholder, because
nobody's words may be made up):

```gdscript
## How long a lane turret waits after losing its target before it turns back.
## (T-00, 2026-01-01. The user: (their words here). Playtest 01-01 showed the
## turrets snapping back and forth when a target slipped in and out of range.
## This replaces LANE_TURN_BACK (0.5). Fixed on 2026-01-01.)
const LANE_TURN_BACK_DELAY := 1.5
```

After:

```gdscript
## How long, in seconds, a lane turret waits after losing its target before
## it turns back to face its lane. The short wait stops it turning back and
## forth when a target slips in and out of range.
const LANE_TURN_BACK_DELAY := 1.5
```

The history does not vanish: the date, the decision and what it replaced go
into a dated entry in docs/PROGRESS.md, under the heading of the change, with
the user's own words.

### 7. Comments must be true

A wrong comment is worse than no comment. Read the code you describe. If a
comment names a function, a number or a file, check it is still right.

---

## Part 2: Small pieces (modules)

### 1. One job per file

If you can't describe a file's job in one sentence without "and also", it
should probably be split. Rough size guide: aim for under ~350 lines per
script. Data tables (`scripts/data/`) may be longer.

### 2. How to split a big class

GDScript has no partial classes, so we split a big class into **parts**:

**a) Helper "part" objects** for a group of related functions that share
the owner's state. The part keeps a reference back to its owner:

```gdscript
class_name PilotShopping
extends RefCounted
## WHAT THIS IS: the "shopping brain" of an AI pilot. ...

## The pilot brain this part belongs to (we read its ship, credits, team).
var ai: PilotAI

func _init(owner: PilotAI) -> void:
	ai = owner

## Should we fly home to shop? ...
func wants_shopping(ship: Ship) -> String:
	...
```

The owner creates its parts once and calls them:

```gdscript
var shopping := PilotShopping.new(self)
...
home_reason = shopping.wants_shopping(ship)
```

**b) Static libraries** for pure calculations that need no state:

```gdscript
class_name SiegeMath
extends RefCounted
static func stage_point(...) -> Vector2:
```

**c) UI widgets** as their own Control scripts (one per panel, tab or bar).

### 3. Don't break other files

- Functions and variables that **other files** use are the class's public
  face. Keep their names and behaviour. If you move the real work into a
  part, leave a thin forwarding function on the original class with the
  same name (and a comment saying where the real code lives).
- Keep `class_name`s that other files or scenes use.
- Scenes (`.tscn`) point at scripts by path: don't move or rename a script
  that a scene uses.

### 4. Moving code must not change what it does

- Keep the **order** of things: loops, `randf()`/`randi()` calls (they share
  one random sequence), signal connections and node creation.
- Don't change numbers, conditions, `int` vs `float`, or `<` vs `<=`.
- Don't "fix" bugs while refactoring. Write them down in your report.

The test `tests/det_hash.gd` proves this. A seeded match prints a hash of
the whole game state every 5 seconds, and the hashes must not change.

### 5. Names and places

- A part of `pilot_ai.gd` lives next to it: `scripts/ai/pilot_shopping.gd`.
- `class_name`s are PascalCase and unique across the project.
- After adding a script with a new `class_name`, run Godot once with
  `--headless --import` so it registers the name.

---

## Part 3: How to check your work

From the project folder (`GODOT` is the Godot console executable):

1. Every script parses:
   `GODOT --headless --path . -- --auto --all-ai --test=load_all`
   should print `load_all: 0 failures`.
2. Behaviour is unchanged:
   `GODOT --headless --path . --fixed-fps 60 -- --all-ai --seed=7 --test=det_hash --secs=600`
   must print the same hash lines as the baseline.
3. Player-facing code (controls, hangar, HUD) also runs:
   `--auto --role=pilot --bot=input --no-pilots --no-admiral-ai --test=bot_pilot`
   and `--auto --all-ai --no-pilots --no-jungle --no-admiral-ai --test=support_probe`,
   both with `0 failures`.
