class_name StatsRecorder
extends Node
## WHAT THIS IS: the stats recorder for your own matches. Start the game
## with --record-stats=<file> and it writes down, for you (the human pilot)
## AND for every AI pilot, how each of you fought: shots fired and hits per
## weapon, the hit rate, damage dealt and taken per minute in space, kills,
## deaths and assists, the hulls flown, and how far away your shots landed.
## It is for the user test fork's stage 3: to make the AI pilots fly like an
## average human, the AI has to be compared with real human numbers.
##
## HOW IT WORKS: main.gd makes one (and calls setup()) only when the option
## --record-stats is given, so without it nothing exists and the game is
## exactly what it was. This is NOT a test script (--test=<name> scripts are
## for tests/): it also works in a normal window, in a match you start from
## the start screen and play yourself, and it can run beside any test.
##   - It keeps one StatsPilotRecord (a notebook page) per pilot in the match.
##   - Every game tick it lets each page count the shots fired, and every
##     hit arrives through Events.damage_applied (the probes' message, which
##     the game sends only while Combat.emit_damage_events is on: the
##     recorder switches it on).
##   - Every 60 seconds of match time, and at the end of the match, it writes
##     everything to the file as JSON, replacing the file's old content. The
##     last write has "final": true. If you close the window in the middle, or
##     the program stops, a last write still happens (final: false, with the
##     reason), so a match you leave early is not lost.
##   - If you play again in the same program run (the end screen's "play
##     again"), the next match is written to <name>_2.json, <name>_3.json ...
##     so the first one is not overwritten.
## It only OBSERVES: it never draws a random number, never changes anything
## in the match, and writes only to the file you name (a bare
## --record-stats uses user://halcyon_stats.json). Everything stays on this
## PC. With the option off the match is bit for bit the same (tests/det_hash.gd
## proves it; it is the same with the option on).
##
## THE FILE (JSON): "final", "reason", "match" (time, your seat, the seed),
## "human" (your page, or null when nobody plays), "ai_summary" (all AI pilots
## added up the same way, to hold your numbers against), "history" (one short
## entry per minute of match time: your key numbers so far and the AI added
## up, to see how they grow) and "ai" (one page per AI pilot, with its skill
## and temperament). A page is described in StatsPilotRecord. If the file
## cannot be written (its folder does not exist), the game says so on the
## console, and in a window with a toast, at the start.
##
## HOW TO RUN IT (an example; "godot" is the Godot program, started from the
## folder that holds remake/):
##   godot --path remake -- --record-stats=C:/temp/my_match_1.json
## then pick your seat on the start screen and play. For a quick test without
## a window: godot --headless --path remake -- --all-ai --max-minutes=3
## --record-stats=stats.json
##
## WHO USES IT: main.gd (it makes the recorder after the match is built, and
## calls finish() when the match ends or the time limit is reached).
## tools/ and the stage 3 skill calibration read the file.

## The file used when the option is given without a name.
const DEFAULT_FILE := "user://halcyon_stats.json"
## Seconds of match time between two writes.
const WRITE_EVERY := 60.0

## How many recorders this program run has made (a static variable lives for
## the whole run): the second match gets a file name with _2, and so on.
static var _made := 0

## The running match.
var world: World
## The file this recorder writes.
var path := ""
## One page per pilot, in the order of World.profiles.
var pages: Array[StatsPilotRecord] = []
## The same pages by pilot: PilotProfile -> StatsPilotRecord.
var _by_pilot := {}
## Match time (seconds) of the next write.
var _next_write := WRITE_EVERY
## The match clock and the winner as of the last tick. Kept here so that a
## last write at exit does not need the World, which may be gone by then.
var _t := 0.0
var _winner := -1
## The seat the human took ("pilot", "admiral" or "spectator"), the seed
## option (text, or null), and the match number (1 for the first).
var _role := ""
var _seed: Variant = null
var _number := 1
## True once the final write is done: nothing is written after that.
var _finished := false
## True once a failed write has been reported (it is reported once).
var _warned := false
## The minute-by-minute history: one entry per minute of match time, each
## {t, clock, human, ai}: the human's key numbers so far (null when nobody
## plays) and the AI pilots added up (see _ai_summary). It is written into
## the file with everything else, so the file shows how the numbers grew.
var _history: Array = []


## main.gd calls this once, right after the match is built. `file` is the
## --record-stats value ("" = the default file).
func setup(w: World, file: String) -> void:
	world = w
	_made += 1
	_number = _made
	path = path_for_match(file if file != "" else DEFAULT_FILE, _number)
	_role = w.human_role
	_seed = Game.opt("seed")
	_t = w.time
	_next_write = (floorf(_t / WRITE_EVERY) + 1.0) * WRITE_EVERY
	# One page per pilot (the human's too).
	for p: PilotProfile in world.profiles:
		var page := StatsPilotRecord.new(p, world.pilot_ai.get(p))
		pages.append(page)
		_by_pilot[p] = page
	# Hits arrive as damage events, which the game sends only for probes.
	world.combat.emit_damage_events = true
	Events.damage_applied.connect(_on_damage)
	# A first write now shows at once if the file cannot be written (for
	# example a folder that does not exist).
	var ok := write(false, "match started")
	var shown := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if ok:
		print("stats: recording to ", shown)
	else:
		print("stats: CANNOT WRITE ", shown, " (does its folder exist?); nothing will be recorded")
	# In a window, say so on screen too: someone who starts the game from the
	# start screen sees no console. (A toast is a short pop-up message.)
	if DisplayServer.get_name() != "headless":
		if ok:
			Events.toast.emit("Recording your match stats to %s" % shown)
		else:
			Events.toast.emit("Cannot write the stats file %s: does its folder exist?" % shown)


## The file name for match number `n` of this program run: the name itself
## for the first match, "name_2.json" (and so on) after it.
static func path_for_match(file: String, n: int) -> String:
	if n <= 1:
		return file
	var dot := file.rfind(".")
	var slash := maxi(file.rfind("/"), file.rfind("\\"))
	if dot > slash:
		return "%s_%d%s" % [file.substr(0, dot), n, file.substr(dot)]
	return "%s_%d" % [file, n]


## Godot calls this every tick, after the World has run its tick (the
## recorder is added after the World). Let every page count the tick, and
## write the file once a minute.
func _physics_process(dt: float) -> void:
	if _finished or world == null or world.phase != "play":
		return
	_t = world.time
	_winner = world.winner
	for page in pages:
		page.tick(dt)
	# Once a minute of match time (the next full minute, so a match that
	# starts late, like --late at 25:00, does not write once per tick to
	# catch up).
	if _t >= _next_write:
		_next_write = (floorf(_t / WRITE_EVERY) + 1.0) * WRITE_EVERY
		_note_history()
		write(false, "")


## A hit was applied (Events.damage_applied): file it with the pilot who
## landed it and with the pilot whose ship took it.
func _on_damage(target: Node, info: RefCounted, amount: float, hull_dmg: float) -> void:
	var t := target as Unit
	var di := info as DamageInfo
	if _finished or t == null or di == null:
		return
	# Landed by a pilot (not on their own team).
	if di.source_profile != null and _by_pilot.has(di.source_profile) and t.team != di.source_team:
		(_by_pilot[di.source_profile] as StatsPilotRecord).on_dealt(t, di, amount)
	# Taken by a pilot's ship.
	if t is Ship:
		var p := (t as Ship).profile
		if p != null and _by_pilot.has(p):
			(_by_pilot[p] as StatsPilotRecord).on_taken(di, amount, hull_dmg)


## The match is over (or its time limit is reached): write the last time.
## main.gd calls this with the reason text, such as "Halcyon wins: ...".
func finish(reason: String) -> void:
	if _finished:
		return
	if world != null and is_instance_valid(world):
		_t = world.time
		_winner = world.winner
	write(true, reason)
	_finished = true


## Godot sends this when the window is closed with the close button: write
## what we have (marked final: false, since the match did not end).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _finished:
		write(false, "window closed")
		_finished = true


## The program is stopping and the match was not finished: write what we
## have (it is marked final: false, so you can tell).
func _exit_tree() -> void:
	if not _finished:
		write(false, "program stopped")
		_finished = true


# --- the file ------------------------------------------------------------------------------

## Write everything to the file now, replacing what was there. `final` marks
## the last write of the match; `reason` says why it is the last (or why a
## write happened out of turn). Returns false when the file cannot be opened
## (a warning is printed the first time).
func write(final: bool, reason: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if not _warned:
			_warned = true
			push_warning("stats: cannot write %s (error %d); nothing will be recorded" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(snapshot(final, reason), "  "))
	return true


## Everything as plain data, ready for JSON (see "THE FILE" at the top).
func snapshot(final: bool, reason: String) -> Dictionary:
	var human: Variant = null
	var ai: Array = []
	for page in pages:
		if page.profile.is_human:
			human = page.to_dict()
		else:
			ai.append(page.to_dict())
	return {
		"tool": "stats_recorder", "version": 1, "final": final, "reason": reason,
		"match": {"t": snappedf(_t, 0.1), "clock": Util.clock(_t), "number": _number, "role": _role, "seed": _seed,
			"winner": _winner, "variants": Game.variants, "sim_only": Game.sim_only, "godot": Engine.get_version_info()["string"]},
		"human": human, "ai_summary": _ai_summary(), "history": _history, "ai": ai,
	}


## Add this minute's entry to the history (see `_history`).
func _note_history() -> void:
	var human: Variant = null
	for page in pages:
		if page.profile.is_human:
			human = page.brief()
	_history.append({"t": snappedf(_t, 1.0), "clock": Util.clock(_t), "human": human, "ai": _ai_summary()})


## All the AI pilots added up: the numbers to hold the human's page against.
## Rates are over the pilots' pooled shots and flying time, not an average
## of averages, so a pilot who barely flew counts for little.
func _ai_summary() -> Dictionary:
	var n := 0
	var flying := 0.0
	var shots := 0
	var hits := 0
	var dmg_out := 0.0
	var dmg_in := 0.0
	var kills := 0
	var deaths := 0
	var assists := 0
	var dist_sum := 0.0
	var dist_n := 0
	for page in pages:
		if page.profile.is_human:
			continue
		n += 1
		var d := page.to_dict()
		flying += float(d["time_s"]["flying"])
		shots += int(d["shots"])
		hits += int(d["hits"])
		dmg_out += float(d["dmg_out"])
		dmg_in += float(d["dmg_in"])
		kills += int(d["kills"])
		deaths += int(d["deaths"])
		assists += int(d["assists"])
		dist_sum += page.dist_ship_sum
		dist_n += page.dist_ship_n
	var mins := flying / 60.0
	return {
		"pilots": n, "flying_s": snappedf(flying, 0.1), "shots": shots, "hits": hits,
		"hit_rate": snappedf(float(hits) / float(shots), 0.001) if shots > 0 else null,
		"dmg_out_per_min": snappedf(dmg_out / mins, 0.1) if mins > 0.0 else null,
		"dmg_in_per_min": snappedf(dmg_in / mins, 0.1) if mins > 0.0 else null,
		"kills_per_10min": snappedf(float(kills) / mins * 10.0, 0.01) if mins > 0.0 else null,
		"deaths_per_10min": snappedf(float(deaths) / mins * 10.0, 0.01) if mins > 0.0 else null,
		"assists_per_10min": snappedf(float(assists) / mins * 10.0, 0.01) if mins > 0.0 else null,
		"hit_dist_ship_mean": snappedf(dist_sum / float(dist_n), 1.0) if dist_n > 0 else null,
	}
