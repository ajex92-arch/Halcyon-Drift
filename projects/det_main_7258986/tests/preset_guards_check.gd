extends Node
## WHAT THIS IS: the check for the guards of the rule-set code (the presets
## patch, M-06): small cases where a preset feature or a launch option used to
## do the wrong thing in a corner, each with the answer it must give now.
##
## HOW IT WORKS: setup() runs after the match is built (the standard rules
## are on, the admiral AI is the weak one for Vhorr, see the command line
## below). Every case builds its own little scene and prints a PASS or FAIL
## line; the last line is "preset_guards_check: N failures" (0 = all good).
## The cases:
##   - breach and breach_extra with no tracker answer empty lists.
##   - attrition keeps the Flagship shield research that finishes after 40:00.
##   - doctrine: the weak test admiral does not buy a level, the normal one does.
##   - the top bar says "No more minion waves" for an infinite next wave.
##   - launch options: an empty --preset and a bad --variant pair set an error,
##     good ones do not; the start screen shows the --variant error and keeps
##     both seat buttons off.
##   - redeploy: a pilot spooling to a turret that is destroyed and freed
##     during the spool still launches, and "redeploy_site_lost" is counted.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --no-pilots --no-jungle --admiral-ai=weak --seed=7 --test=preset_guards_check
##
## WHO USES IT: main.gd loads it for --test=preset_guards_check. It builds its
## own ships, turret and start screen, and puts back what it changes.

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0


## main.gd calls this once, right after the World is built. Run every case and
## quit. (It waits for frames in the last case, so the rest of the match goes on
## meanwhile; nothing before that case needs a tick.)
func setup(w: World) -> void:
	world = w
	world.minion_director.next_wave = INF
	_case_breach_without_tracker()
	_case_attrition()
	_case_doctrine_weak()
	_case_wave_line()
	_case_launch_options()
	_case_start_screen_variant_error()
	await _case_redeploy_site_lost()
	print("preset_guards_check: %d failures" % fails)
	get_tree().quit()


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## BreachFeature and BreachExtraFeature whose install() stopped early on an
## unknown value (featA-2): no tracker, and the HUD functions must still answer.
func _case_breach_without_tracker() -> void:
	var b := BreachFeature.new()
	_check("breach: no tracker gives no banner", b.banner(world, 0).is_empty())
	_check("breach: no tracker gives no chevrons", b.minimap_chevrons(world).is_empty())
	var x := BreachExtraFeature.new()
	_check("breach_extra: no tracker gives no banner", x.banner(world, 0).is_empty())
	_check("breach_extra: no tracker gives no chevrons", x.minimap_chevrons(world).is_empty())


## Attrition's shield refill must follow Flagship shield research that
## finishes after 40:00 (featA-3).
func _case_attrition() -> void:
	var a := AttritionFeature.new()
	a.world = world
	# Move 40:00 to match time 0, so one update already works.
	a._shift = AttritionFeature.START_TIME
	var team := Rules.HALCYON
	var ms := world.mothership(team)
	var ts: TeamState = world.teams[team]
	a._tick(1.0)
	var base := ms.base_regen
	_check("attrition: the first update leaves the refill at its base", is_equal_approx(ms.shields.regen, base), "%.3f of %.3f" % [ms.shields.regen, base])
	ts.ms_shield = 0.5
	MothershipGuns.apply_upgrades(ms, ts)
	a._tick(1.0)
	_check("attrition: shield research finished later still counts", is_equal_approx(ms.shields.regen, base * 1.5), "%.3f of %.3f" % [ms.shields.regen, base * 1.5])
	ts.ms_shield = 0.0
	MothershipGuns.apply_upgrades(ms, ts)
	for t in 2:
		world.mothership(t).incoming_mults.erase(AttritionFeature.KEY)


## Fleet Doctrine's AI purchase must skip the weak test admiral (featA-4).
func _case_doctrine_weak() -> void:
	var weak_vhorr := AdmiralWeak.is_weak(Rules.CINDER) and not AdmiralWeak.is_weak(Rules.HALCYON)
	_check("doctrine: Vhorr's admiral is the weak one (--admiral-ai=weak)", weak_vhorr)
	_check("doctrine: both teams have a computer admiral", world.admiral_ai[0] != null and world.admiral_ai[1] != null)
	if not weak_vhorr or world.admiral_ai[0] == null or world.admiral_ai[1] == null:
		return
	var d := DoctrineFeature.new()
	d.world = world
	var saved := []
	for t in 2:
		var ts: TeamState = world.teams[t]
		saved.append([ts.treasury, ts.facilities.has("research")])
		ts.facilities["research"] = true
		ts.treasury = 100000.0
	d._tick(1.0)
	_check("doctrine: the normal admiral buys a level", float(d.left[0]) >= 0.0, str(d.left))
	_check("doctrine: the weak admiral does not", float(d.left[1]) < 0.0, str(d.left))
	for t in 2:
		var ts: TeamState = world.teams[t]
		ts.treasury = float((saved[t] as Array)[0])
		if not bool((saved[t] as Array)[1]):
			ts.facilities.erase("research")
		ts.doctrine_level = 0


## The top bar's wave line for the three cases (featB-2).
func _case_wave_line() -> void:
	var md := world.minion_director
	md.next_wave = INF
	_check("top bar: an infinite next wave reads 'No more minion waves'", HudTopBar.wave_line(md, 100.0) == "No more minion waves", HudTopBar.wave_line(md, 100.0))
	md.next_wave = 130.0
	_check("top bar: a wave due in 30 s reads 'Next minion wave 0:30'", HudTopBar.wave_line(md, 100.0) == "Next minion wave 0:30", HudTopBar.wave_line(md, 100.0))
	md.next_wave = INF


## What Game does with --preset and --variant (edits-1, featA-5). The options
## are put back and the variants built again at the end.
func _case_launch_options() -> void:
	var saved_options: Dictionary = Game.options.duplicate()
	# No --preset: the standard rules.
	Game.options = {}
	Game._build_variants("", false)
	_check("options: no --preset plays the standard rules", Game.preset == "pick" and Game.preset_error == "" and Game.variant_error == "")
	# --preset= (empty): refused.
	Game.options = {"preset": ""}
	Game._build_variants("", true)
	_check("options: an empty --preset is refused", Game.preset == "" and Game.preset_error != "", Game.preset_error)
	# --preset=none, --preset=zz.
	Game.options = {"preset": "none"}
	Game._build_variants("none", true)
	_check("options: --preset=none is fine", Game.preset == "none" and Game.preset_error == "")
	Game.options = {"preset": "zz"}
	Game._build_variants("zz", true)
	_check("options: an unknown --preset is refused", Game.preset_error != "")
	# --variant pairs.
	for text: String in ["fleetcap:30", "fleet_cap:6:0", "fleet_cap:", ":30", "fleet_cap", "bomber_rol:both"]:
		Game.options = {"variant": text}
		Game._build_variants("", false)
		_check("options: --variant=%s is refused" % text, Game.variant_error != "", Game.variant_error)
	Game.options = {"variant": "fleet_cap:30"}
	Game._build_variants("", false)
	_check("options: --variant=fleet_cap:30 is fine and wins over the preset", Game.variant_error == "" and Game.variant("fleet_cap") == "30", Game.variant_error)
	Game.options = {"variant": "fleet_cap:30,fleetcap:30"}
	Game._build_variants("", false)
	_check("options: a bad pair among good ones is refused", Game.variant_error != "")
	# Put back what the match was built with.
	Game.options = saved_options
	Game._build_variants(str(saved_options.get("preset", "")), saved_options.has("preset"))


## The start screen with a --variant error: one line says so and both seat
## buttons are off (edits-1, featA-5).
func _case_start_screen_variant_error() -> void:
	Game._difficulty_open = false
	Game._team_open = false
	var saved := Game.variant_error
	Game.variant_error = "unknown variant name \"zz\" (check its spelling)"
	var screen: StartScreen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	var note := screen._launch_note
	_check("start screen: a --variant error shows one line", note != null and note.text.contains("--variant") and note.text.contains("zz") and note.text.contains("Relaunch"), note.text if note != null else "no line")
	var admiral: Button = screen.get_node("Scroll/Center/Card/Col/Seats/Admiral/Col/Pick")
	var pilot: Button = screen.get_node("Scroll/Center/Card/Col/Seats/Pilot/Col/Pick")
	_check("start screen: both seat buttons are off", admiral.disabled and pilot.disabled)
	screen.free()
	Game.variant_error = saved


## A pilot spooling to a turret that is destroyed and freed during the spool
## still launches, and the loss is counted (edits-2). It needs frames: a
## destroyed turret is freed at the end of its frame.
func _case_redeploy_site_lost() -> void:
	var redeploy := world.features.get("redeploy") as RedeployFeature
	_check("redeploy: the feature is on", redeploy != null)
	if redeploy == null:
		return
	var team := Rules.HALCYON
	var ts: TeamState = world.teams[team]
	var had_hyperspace := ts.facilities.has("hyperspace")
	ts.facilities["hyperspace"] = true
	var node: ResourceNode = world.nodes[team]
	var site := world.spawn_turret(team, node, node.free_slot(), "pd", true)
	var p := PilotProfile.new("redeploy-test", team, 3, false)
	p.hull_id = "fighter"
	p.role = "mid"
	world.profiles.append(p)
	world.pilot_ai[p] = PilotAI.new(world, p)
	var lost_before := int(Game.usage.get("redeploy_site_lost", 0))
	var why := redeploy.start(p, site)
	_check("redeploy: the jump to the turret starts", why == "" and p.state == "spooling", why)
	# The turret dies during the spool and is freed at the end of that frame.
	world.combat.kill_silently(site)
	for i in 3:
		await get_tree().physics_frame
	_check("redeploy: the destroyed turret is freed", not is_instance_valid(site))
	# The spool runs out.
	p.respawn_t = 0.0
	for i in 3:
		await get_tree().physics_frame
	_check("redeploy: the pilot launched anyway", p.state == "flying" and p.ship != null, p.state)
	_check("redeploy: the lost site is counted once", int(Game.usage.get("redeploy_site_lost", 0)) == lost_before + 1, str(Game.usage.get("redeploy_site_lost", 0)))
	if not had_hyperspace:
		ts.facilities.erase("hyperspace")
