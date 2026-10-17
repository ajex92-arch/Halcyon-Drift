class_name MainDebugOverlay
extends RefCounted
## WHAT THIS IS: a bare-bones text display for when the real HUD scene
## (scenes/ui/hud.tscn) is missing. It keeps an early build playable: it
## shows the clock, your money, your ship's numbers and both motherships,
## and the F1 key buys a Fighter and launches you.
##
## HOW IT WORKS: main.gd makes the label once (make_label), sets its text
## every frame (text) and hands the F1 key to on_f1(). All three functions
## are "static": they belong to the class itself and are called as
## MainDebugOverlay.text(world), without making an object first.
##
## WHO USES IT: only main.gd, and only when there is a window but no HUD
## scene.


## Make the overlay's label: 12 pixels from the top-left corner, with
## 13-pixel text. main.gd adds it to its screen layer.
static func make_label() -> Label:
	var label := Label.new()
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 13)
	return label


## The overlay text for `world`: the match clock and the human's seat;
## then the human pilot's credits, state, hull and kills/deaths/assists;
## then, while flying, the ship's hull, shields, energy, energy routing,
## shield focus and speed / top speed (or a hint while docked, or the
## respawn countdown while dead); then each team's treasury and mothership
## hull; and last, how long one tick of the simulation takes.
static func text(world: World) -> String:
	# Step 1: the clock and the seat.
	var t := "%s  role=%s\n" % [Util.clock(world.time), world.human_role]
	# Step 2: the human pilot (a spectator has none).
	var h := world.human
	if h != null:
		t += "credits %d  state %s  hull %s  K/D/A %s\n" % [int(h.credits), h.state, h.hull_id, h.kda()]
		# The pilot has a ship in space: its numbers.
		if h.ship != null and is_instance_valid(h.ship):
			var s := h.ship
			t += "hull %d/%d  shields %d/%d  energy %d/%d  routing %s  focus %s  speed %d/%d\n" % [
				int(s.hull), int(s.hull_max), int(s.shields.total()), int(s.shields.max_total), int(s.energy.value), int(s.energy.max_value),
				Rules.ENERGY_NAMES[s.energy.mode], Rules.FOCUS_NAMES[s.shields.focus], int(s.velocity.length()), int(s.f_max)]
		elif h.state == "docked":
			t += "Docked. Press F1 to buy a Fighter and launch.\n"
		elif h.state == "dead":
			t += "Destroyed. Respawning in %ds.\n" % int(ceil(h.respawn_t))
	# Step 3: both teams (0 = Aurelian, 1 = Cinder), then the tick cost.
	for i in 2:
		t += "%s treasury %d  mothership %d%%\n" % [Rules.TEAM_DISPLAY[i], int(world.teams[i].treasury), int(world.mothership(i).hull_frac() * 100.0)]
	t += "sim %.2f ms/tick" % (world.tick_usec / 1000.0)
	return t


## The F1 key on the overlay: a docked human pilot with no ship chosen yet
## buys a Fighter, and a docked pilot then launches. Does nothing while
## flying or dead. main.gd checks that the human exists first.
static func on_f1(world: World) -> void:
	var h := world.human
	if h.state == "docked":
		if h.hull_id == "":
			h.buy_hull("fighter", world.teams[0])
		world.launch(h)
