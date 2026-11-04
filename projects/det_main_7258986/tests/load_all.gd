extends Node
## WHAT THIS IS: a quick "does every file still load?" check. It loads
## every script and scene in the project so parse errors (typing mistakes
## that stop Godot reading a script) show up in a quick headless run (one
## with no window). The HUD isn't built headless, so its scripts would
## otherwise go unchecked. It also builds each UI scene once.
##
## HOW IT WORKS: setup() walks the scripts/ and tests/ folders (and all
## folders inside them) and loads every .gd file, then walks scenes/ and
## loads every .tscn file. Each scene in scenes/ui/ (except
## command_overlay.tscn) is also made into real nodes once, added here and
## freed again. Any file that fails to load prints a LOAD FAIL line. Half
## a second later the test quits.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake -- --auto --all-ai --test=load_all
##
## HOW TO READ THE OUTPUT: "LOAD FAIL res://scripts/..." for each file
## that did not load, then "load_all: N failures". 0 failures means every
## script and scene loaded. Godot's own SCRIPT ERROR or Parse Error lines
## above it say what went wrong.
##
## WHO USES IT: main.gd loads it for --test=load_all (for --test=<name> it
## loads tests/<name>.gd, adds it after the World and calls setup()).
## docs/CODE_STYLE.md (Part 3) uses it as the first check after any
## change.


## main.gd calls this once, right after the World is built (the World `_w`
## is not needed). Load everything, print the failure count, and quit half
## a second later.
func setup(_w: World) -> void:
	var bad := 0
	# Step 1: every script.
	for path in _files("res://scripts", ".gd") + _files("res://tests", ".gd"):
		var s = load(path)
		if s == null:
			print("LOAD FAIL ", path)
			bad += 1
	# Step 2: every scene; the UI scenes (except the command overlay) are
	# also built once and then freed.
	for path in _files("res://scenes", ".tscn"):
		var ps = load(path)
		if ps == null:
			print("LOAD FAIL ", path)
			bad += 1
		elif path.begins_with("res://scenes/ui/") and not path.ends_with("command_overlay.tscn"):
			var n: Node = (ps as PackedScene).instantiate()
			add_child(n)
			n.queue_free()
	# Step 3: the result, then quit after 0.5 s.
	print("load_all: %d failures" % bad)
	get_tree().create_timer(0.5).timeout.connect(func() -> void: get_tree().quit())


## Every file under the folder `dir` (and all folders inside it) whose name
## ends with `ext` (for example ".gd"), as full "res://" paths.
func _files(dir: String, ext: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	# The files in this folder ...
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	# ... then the files in each folder inside it.
	for sub in d.get_directories():
		out += _files(dir.path_join(sub), ext)
	return out
