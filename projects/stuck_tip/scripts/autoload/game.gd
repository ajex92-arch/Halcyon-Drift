extends Node
## WHAT THIS IS: the game's settings desk (the autoload "Game"). It holds
## the launch options typed on the command line, the chosen rule
## variants, a link to the running match, the tuned numbers that feature
## modules changed for this match, and the feature usage counts. It also
## sets up the keyboard and mouse controls.
##
## HOW IT WORKS: an "autoload" is a script Godot starts before everything
## else and keeps running; every file can reach it by its name, `Game`.
## In _ready() it:
##   1. reads the options written after `--` on the command line
##      (_parse_options), such as `godot -- --auto --seed=7`;
##   2. fills in the rule variants: the defaults from
##      Rules.VARIANT_DEFAULTS, then the council preset named by --preset
##      (if any; CouncilPresets), then the pairs of --variant;
##   3. defines the controls ("input actions") through GameInputMap.
## The start screen may choose a preset later (apply_preset()), before the
## match is built.
## Other files then ask Game.opt("name") or Game.variant("name").
## Two lists belong to the feature modules (scripts/features/, see
## FeatureRegistry): `tunables` (numbers a feature changed for this match;
## Rules.tune() reads them) and `usage` (how often a feature's mechanic was
## used; count_usage() adds to it). Both start empty, which means "today's
## game", and WorldSetup empties them again whenever a match is built.
##
## WHO USES IT: main.gd reads most of the options below; WorldSetup reads
## the --no-* switches, sets Game.world and empties tunables and usage;
## the mothership's retreat, the admiral board and FeatureRegistry ask
## Game.variant(), and MainReport writes all the variants into the
## end-of-match summary; feature modules write tunables and call
## count_usage(); Rules.tune() reads tunables; the fun probe prints usage;
## PilotAI and SkillJitter read --skill-jitter and --seed; tests read
## their own options (such as --secs); the end screen clears Game.world
## before a new match. The start screen calls apply_preset() (its rule-set
## buttons) and FeatureRegistry reads preset_error.
##
## The options (who reads them in brackets):
##   --role=pilot|admiral|spectator   the human's seat. Without --auto (and
##                                    with a window) the start screen asks
##                                    instead; with --auto the default is
##                                    pilot. (main.gd)
##   --auto                           skip the start screen and use --role;
##                                    the human (pilot or admiral) buys a
##                                    Fighter and launches at once, unless
##                                    --bot is given. (main.gd)
##   --all-ai                         no human ship; the human only watches
##                                    (spectator) and everyone else is AI.
##                                    (main.gd)
##   --seed=N                         the match's random seed: main.gd
##                                    seeds the shared random sequence with
##                                    N before the match is built, so the
##                                    same N plays the same match. The map
##                                    layout is fixed and doesn't use it.
##   --variant=retreat:none,escort_wing:upgrade
##                                    rule variants as name:value pairs
##                                    (names and values: see
##                                    Rules.VARIANT_DEFAULTS). A variant
##                                    that has a feature module switches
##                                    it on (FeatureRegistry).
##   --preset=within|pick             a council rule set for playtests: a
##                                    named --variant string
##                                    (CouncilPresets). The preset is
##                                    applied first, then --variant, so
##                                    --variant can change one of its keys.
##                                    Without it the match is today's game.
##                                    An unknown name stops the match at
##                                    its start (FeatureRegistry, exit
##                                    code 3). The start screen offers the
##                                    same choice. (Game, StartScreen)
##   --skill-jitter[=S]               fun tests: every AI pilot seat's skill
##                                    gets its own random nudge of up to S
##                                    either way (0.20 when no S is given),
##                                    from a generator seeded by --seed, the
##                                    same for that seat on both teams.
##                                    Without it skills are unchanged.
##                                    (PilotAI, SkillJitter)
##   --max-minutes=N                  tests: stop after N minutes of match
##                                    time. (main.gd)
##   --bot=<scenario>                 tests: a test script flies the human.
##                                    main.gd only checks that it is given
##                                    (then no automatic Fighter launch).
##   --shots=<dir>                    tests: the folder for screenshots
##                                    taken on a tour. (ui_tour,
##                                    spectate_shots)
##   --speed=N                        tests: run the game N times as fast
##                                    (Engine.time_scale). (main.gd)
##   --sim-only                       tests: a speed mode for windowless runs.
##                                    Everything that only draws or sounds
##                                    is skipped (unit pictures, shot and
##                                    effect drawing, sound cues, HUD,
##                                    camera); the match is exactly the same
##                                    as without it (tests/det_hash.gd proves
##                                    it). Read into Game.sim_only. (main.gd,
##                                    Effects, UnitVisual, ShipVisual and
##                                    others)
##   --profile                        print the cost of each part of the
##                                    simulation every minute. (main.gd)
##   --report=<path>                  also write the end-of-match summary
##                                    (JSON) to this file. (main.gd)
##   --test=<name>                    run the test script tests/<name>.gd.
##                                    (main.gd)
##   --snap=<png>                     save one screenshot after 1.5 s and
##                                    quit. (main.gd)
##   --force-hud                      build the HUD even with no window, for
##                                    UI tests. (main.gd)
##   --no-pilots / --no-jungle / --no-admiral-ai
##                                    strip systems out for tests: no AI
##                                    pilots, no jungle monster camps, no AI
##                                    admirals. (WorldSetup)
##
## The controls are defined in code (GameInputMap), not in project.godot,
## so they are easy to read and tests can press them by name.

## The running match (a World), or null between matches. WorldSetup sets
## it when a match is built; the end screen clears it before a new match.
var world: Node = null
## The command-line options: name (without the "--") -> value. "--seed=7"
## gives "seed" -> "7" (always text); a bare "--auto" gives "auto" -> true.
var options := {}
## The rule variants for this match: variant name -> chosen value (text).
## Starts as a copy of Rules.VARIANT_DEFAULTS; a council preset (--preset,
## or the start screen) and then --variant change entries.
var variants := {}
## The council preset (rule set) of this match: one of CouncilPresets.ORDER,
## or "" for none, which is today's game. Set from --preset by
## _parse_options(), or by the start screen through apply_preset().
var preset := ""
## Why the preset that was asked for could not be used: "" when it could
## (or when none was asked for), else a line naming the unknown name.
## FeatureRegistry.install() then refuses the match (exit code 3), so a typo
## never plays today's game by mistake.
var preset_error := ""
## Feature hook: tuned numbers changed for this match, by name: name ->
## new value (for example "kill_base" -> 150.0). Empty (the default) =
## every number has its normal value. A feature module sets entries in its
## install() (Game.tunables["kill_base"] = 150.0); the game reads them
## through Rules.tune(name, normal value), and Rules.TUNABLES lists every
## name that is read. WorldSetup empties it when a match is built.
var tunables := {}
## How often each feature mechanic was used this match, by name: name ->
## count (for example "escort_wing_upgrades" -> 12). Feature modules add
## to it with count_usage(); the fun probe prints it, because a mechanic
## the AI never used proves nothing. WorldSetup empties it when a match is
## built.
var usage := {}
## True when --sim-only was given: a speed mode for windowless test runs. The
## game then skips everything that only draws or sounds (the unit pictures,
## the shot and ring drawing, the sound cues, the HUD, the camera), because
## the simulation never reads any of it. The match plays out exactly the
## same, only faster. Read once from the options by _parse_options().
var sim_only := false


## Godot calls this once at startup: read the options, then set up the
## controls.
func _ready() -> void:
	_parse_options()
	_define_actions()


## Read the command-line options into `options`, then build `variants`.
## Only words after `--` on the command line count ("user args"); of
## those, only words starting with "--" are options.
func _parse_options() -> void:
	# Step 1: each option: "--name=value" or a bare "--name" (= true).
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq := body.find("=")
		if eq < 0:
			options[body] = true
		else:
			options[body.substr(0, eq)] = body.substr(eq + 1)
	# Step 1b: --sim-only (a bare switch; "--sim-only=0" or "=false" turns it
	# off again) is read here once, into the plain variable `sim_only`, so
	# the many places that check it need no lookup in `options`.
	var so: String = str(options.get("sim-only", "false"))
	sim_only = so != "false" and so != "0"
	# Step 2: the variants: start from the defaults, then the council preset
	# named by --preset (if any), then each "name:value" pair of --variant
	# (see _build_variants()). A preset is named in the log.
	_build_variants(str(options.get("preset", "")))
	if preset != "":
		print("preset: %s = %s" % [preset, CouncilPresets.variant_string(preset)])


## Use council preset `preset_name` (one of CouncilPresets.ORDER, or "" for
## none: today's game) for the next match: `variants` is built again from
## the defaults, that preset and --variant. The start screen calls it when a
## rule-set button is pressed; it must run before the match is built, since
## FeatureRegistry reads the variants then.
func apply_preset(preset_name: String) -> void:
	_build_variants(preset_name)


## Build `variants`: start from Rules.VARIANT_DEFAULTS, then apply the pairs
## of council preset `preset_name` (CouncilPresets; "" = none), then the
## pairs of --variant, so --variant wins where both set a key. Sets `preset`
## and `preset_error`: an unknown preset name adds nothing and leaves an
## error line for FeatureRegistry.
func _build_variants(preset_name: String) -> void:
	variants = Rules.VARIANT_DEFAULTS.duplicate()
	preset = ""
	preset_error = ""
	if preset_name != "":
		if CouncilPresets.is_preset(preset_name):
			preset = preset_name
			_apply_pairs(CouncilPresets.variant_string(preset_name))
		else:
			preset_error = "unknown preset \"%s\" (the presets are: %s)" % [preset_name, ", ".join(PackedStringArray(CouncilPresets.ORDER))]
	_apply_pairs(str(options.get("variant", "")))


## Apply each "name:value" pair of `text` (pairs split by commas) to
## `variants`; a pair that isn't exactly name:value is skipped.
func _apply_pairs(text: String) -> void:
	for pair in text.split(",", false):
		var kv := pair.split(":")
		if kv.size() == 2:
			variants[kv[0]] = kv[1]


## The value of option `key` (the name without "--"), or `default_value`
## when it was not given. Values are text (or true for a bare option), so
## callers turn them into numbers with int() or float().
func opt(key: String, default_value = null):
	return options.get(key, default_value)


## The chosen value of rule variant `key` (such as "retreat"), or "" if
## there is no such variant.
func variant(key: String) -> String:
	return str(variants.get(key, ""))


## Count `n` more uses (1 unless told otherwise) of feature mechanic `key`
## in `usage`, for example Game.count_usage("escort_wing_upgrades").
func count_usage(key: String, n: int = 1) -> void:
	usage[key] = int(usage.get(key, 0)) + n


## Define every control (input action). The real code is
## GameInputMap.define_all().
func _define_actions() -> void:
	GameInputMap.define_all()
