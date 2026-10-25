extends Node
## WHAT THIS IS: the "rules check": a quick test that a match plays the rules its
## preset names (Council's pick, the standard rules, unless --preset says
## otherwise) and that the start screen offers no choice of rules.
##
## HOW IT WORKS: setup() runs after the match is built. It writes out again, on
## purpose, what each preset should switch on (so the check does not copy the
## game's table), and checks: the preset the game reports; every rule variant of
## the match against that table (nothing else may differ from
## Rules.VARIANT_DEFAULTS); which feature modules the match installed; and the
## Fleet Command limit (30 in the old rules, 60 otherwise). Then it builds the
## start screen as a new run would and checks that no rule-set row is there (no
## text about rule sets, presets or the council, the difficulty row right under
## the rules text, both seat buttons usable), builds it again with an unknown
## --preset pretended (Game.preset_error): one line under the rules text says so
## and both seat buttons are off. Last, the How to play pages must not speak of
## rule sets. It prints a PASS or FAIL line for each check and ends with
## "rules_check: N failures" (0 = all good), then quits. A run with --variant
## skips the variant table (the table is for the preset alone).
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/; the folder name is up to you):
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --test=rules_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --preset=none --test=rules_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --preset=within --test=rules_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --preset=pick --test=rules_check
## The first and the last play the same rules. An unknown --preset stops the
## match at its start (exit code 3), so it cannot be run with this check.
##
## WHO USES IT: main.gd loads it for --test=rules_check. It reads the game and
## builds throwaway start screens; it changes nothing in the match.

## What "within" switches on: variant -> value (the rest stay at their defaults).
const WITHIN := {"minion_cap": "on", "lance_role": "on", "bomber_role": "both", "admiral_sinks": "fleet",
	"redeploy": "on", "gear_mk2": "on", "fleet_cap": "60"}
## What "pick", the standard rules, switches on: "within" and persistent nodes.
const PICK := {"minion_cap": "on", "lance_role": "on", "bomber_role": "both", "admiral_sinks": "fleet",
	"redeploy": "on", "gear_mk2": "on", "fleet_cap": "60", "node_persist": "on"}
## Words a player must not meet on the start screen or in How to play: they
## would ask for a choice of rules.
const FORBIDDEN := "(?i)rule.?set|preset|council|within requirements"

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Run every check and
## quit.
func setup(w: World) -> void:
	world = w
	_check_match()
	_check_start_screen(false)
	_check_start_screen(true)
	_check_help()
	print("rules_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## The preset, the variants, the installed features and the Fleet Command limit
## of the match.
func _check_match() -> void:
	var asked := str(Game.opt("preset", ""))
	var want := asked if asked != "" else "pick"
	_check("the preset played is '%s'" % want, Game.preset == want and Game.preset_error == "", "Game.preset '%s', error '%s'" % [Game.preset, Game.preset_error])
	var table: Dictionary = {}
	if want == "within":
		table = WITHIN
	elif want == "pick":
		table = PICK
	# The variants: the defaults, changed only by the preset's table.
	if Game.opt("variant") == null:
		var bad := PackedStringArray()
		for key: String in Rules.VARIANT_DEFAULTS:
			var expected := str(table.get(key, Rules.VARIANT_DEFAULTS[key]))
			if Game.variant(key) != expected:
				bad.append("%s is %s, wanted %s" % [key, Game.variant(key), expected])
		_check("every variant is the preset's", bad.is_empty(), "; ".join(bad))
	# The feature modules: one per variant the preset turned on, none otherwise.
	var missing := PackedStringArray()
	for key: String in PICK:
		var on: bool = table.has(key)
		if world.features.has(key) != on:
			missing.append("%s %s" % [key, "missing" if on else "installed"])
	_check("the feature modules are the preset's", missing.is_empty(), "; ".join(missing))
	if Game.opt("variant") == null:
		var cap := Minions.control_cap()
		var want_cap := 60 if table.has("fleet_cap") else 30
		_check("the Fleet Command limit is %d" % want_cap, cap == want_cap, "it is %d" % cap)


## A start screen as a new run would build it (the settings file is not read),
## with `blocked` pretending the game was launched with an unknown --preset.
func _check_start_screen(blocked: bool) -> void:
	var tag := "start screen (unknown --preset)" if blocked else "start screen"
	Game._difficulty_open = false
	Game._team_open = false
	var saved_error := Game.preset_error
	if blocked:
		Game.preset_error = "unknown preset \"zz\" (the presets are: none, within, pick)"
	var screen: StartScreen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var col: VBoxContainer = screen.get_node("Scroll/Center/Card/Col")
	# Step 1: the texts. A launch line may name the option; nothing else may.
	var words: Array[String] = []
	_collect_texts(screen, words)
	var hits := PackedStringArray()
	var rx := RegEx.new()
	rx.compile(FORBIDDEN)
	for t: String in words:
		if rx.search(t) != null and not (blocked and t.begins_with("The launch option --preset was not understood")):
			hits.append(t.substr(0, 60))
	_check("%s: no text about rule sets, presets or the council" % tag, hits.is_empty(), "; ".join(hits))
	_check("%s: no RULE SET heading" % tag, not words.has("RULE SET"))
	# Step 2: what sits under the rules text.
	var at: int = col.get_node("Rules").get_index() + 1
	if blocked:
		var line := col.get_child(at)
		_check("%s: one line under the rules text says the option was not understood and to relaunch" % tag, line is Label and (line as Label).text.contains("not understood") and (line as Label).text.contains("Relaunch") and (line as Label).text.contains("zz"), (line as Label).text if line is Label else str(line))
		at += 1
	else:
		_check("%s: no launch line" % tag, screen._launch_note == null)
	var row := col.get_child(at)
	var heading: Node = null
	if row is HBoxContainer and row.get_child_count() > 0:
		heading = row.get_child(0)
	_check("%s: the difficulty row is next" % tag, heading is Label and (heading as Label).text == "DIFFICULTY", str(row))
	_check("%s: the five difficulty buttons are there" % tag, screen._difficulty_buttons.size() == 5)
	# Step 3: the seat buttons.
	var admiral: Button = screen.get_node("Scroll/Center/Card/Col/Seats/Admiral/Col/Pick")
	var pilot: Button = screen.get_node("Scroll/Center/Card/Col/Seats/Pilot/Col/Pick")
	_check("%s: both seat buttons are %s" % [tag, "off" if blocked else "on"], admiral.disabled == blocked and pilot.disabled == blocked, "Admiral disabled %s, Pilot disabled %s" % [admiral.disabled, pilot.disabled])
	screen.free()
	Game.preset_error = saved_error


## Every text of the Labels and Buttons under `node`, added to `out`.
func _collect_texts(node: Node, out: Array[String]) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c: Node in node.get_children():
		_collect_texts(c, out)


## The How to play pages (HelpPanel.PAGES and its replacements for removed
## damage modifiers) must not speak of rule sets.
func _check_help() -> void:
	var rx := RegEx.new()
	rx.compile(FORBIDDEN)
	var hits := PackedStringArray()
	for page: String in HelpPanel.PAGES:
		for entry: Array in HelpPanel.PAGES[page]:
			if rx.search(str(entry[0])) != null or rx.search(str(entry[1])) != null:
				hits.append("%s / %s" % [page, entry[0]])
	for heading: String in HelpPanel.PAGES_MODIFIERS_REMOVED:
		if rx.search(str(HelpPanel.PAGES_MODIFIERS_REMOVED[heading])) != null:
			hits.append("removed / " + heading)
	_check("How to play: no text about rule sets, presets or the council", hits.is_empty(), "; ".join(hits))
