class_name HudBanner
extends VBoxContainer
## WHAT THIS IS: the big message in the middle of the screen, a title with
## a smaller line under it: "Paused", the armed Admiral map tool, the
## respawn countdown, a hyperspace jump countdown, "Docked at the
## mothership", "An enemy turret is targeting you", or our mothership's
## systems failing.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_banner.tscn: a
## column centred on the screen, starting 150 pixels above its middle,
## holding Title (24 px text, a 6-pixel outline) and Sub (15 px grey text,
## a 5-pixel outline), both centred. The mouse passes through it. _ready()
## makes both outlines dark (VOID) so the lines read over the game.
## refresh() runs 10 times a second and picks the FIRST of these that is
## true, in this order (most important first): paused, a map tool armed,
## we are dead, we are jumping (spooling) to a repair bay, we are docked as
## a pilot with the hangar closed, an enemy turret is aiming at our ship,
## our mothership's systems are failing. If none is true, the banner is
## empty. The title's colour shows the mood: ice (white) for information,
## amber for a map tool, cinder (red) for danger, veil (teal) for a jump.
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it. Hud.setup()
## gives it the HUD and Hud._refresh() calls refresh(). It reads the Hud
## (overlay, hangar), HudFeed.last_cause (how we died) and World (the
## human, turrets, motherships).

## The HUD this widget belongs to (Hud.setup() sets it).
var hud: Hud
## The big top line (24 px text).
@onready var _title: Label = $Title
## The smaller line under it (15 px text).
@onready var _sub: Label = $Sub


## Godot calls this when the banner joins the HUD: give both lines a dark
## outline, so they read over the game.
func _ready() -> void:
	for l: Label in [_title, _sub]:
		l.add_theme_color_override("font_outline_color", Palette.VOID)


## Pick the most important message right now and show it (see HOW IT
## WORKS for the order).
func refresh() -> void:
	var world := hud.world
	var title := ""
	var sub := ""
	var col := Palette.ICE
	var h := world.human
	var ts: TeamState = world.teams[h.team] if h != null else null
	# Paused, or an Admiral map tool waiting for a click on the map.
	if get_tree().paused:
		title = "Paused"
		sub = "Press P to resume."
	elif hud.overlay.tool != "":
		title = hud.overlay.hint()
		col = Palette.AMBER
	# Dead: the countdown, and how we died (HudFeed.last_cause).
	elif h != null and h.state == "dead":
		title = "Respawning in %ds" % int(ceil(h.respawn_t))
		sub = (hud.feed.last_cause + ".  " if hud.feed.last_cause != "" else "") + "Gear is kept; press B to shop while you wait."
		col = Palette.CINDER
	# Spooling: a hyperspace launch out to one of our repair bays.
	elif h != null and h.state == "spooling":
		title = "Hyperspace jump in %ds" % int(ceil(h.respawn_t))
		sub = "You'll arrive beside the repair bay."
		col = Palette.VEIL
	# A docked pilot who closed the hangar: remind them of the keys.
	elif h != null and h.state == "docked" and world.human_role == "pilot" and (hud.hangar == null or not hud.hangar.visible):
		title = "Docked at the mothership"
		sub = "B opens the hangar · F launches."
	# Flying into an enemy turret's aim.
	elif h != null and h.ship != null and is_instance_valid(h.ship) and _turret_on(h.ship):
		title = "An enemy turret is targeting you"
		sub = "Back off, or fight it with your minions beside you."
		col = Palette.CINDER
	# Our mothership's emergency "systems failure" (only the small line).
	elif ts != null and world.mothership(h.team).failure_t > 0.0:
		sub = "Our mothership's systems are failing: no launches or respawns there for %ds." % int(ceil(world.mothership(h.team).failure_t))
		col = Palette.CINDER
	UiKit.set_text(_title, title)
	UiKit.set_text(_sub, sub)
	_title.add_theme_color_override("font_color", col)


## Is any live enemy turret aiming at ship `s` right now?
func _turret_on(s: Ship) -> bool:
	for t: Turret in hud.world.turrets:
		if t.alive and t.team != s.team and t.target == s:
			return true
	return false
