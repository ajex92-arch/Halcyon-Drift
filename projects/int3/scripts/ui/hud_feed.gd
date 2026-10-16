class_name HudFeed
extends VBoxContainer
## WHAT THIS IS: the kill / event feed in the top-right corner of the HUD:
## short lines like "Wren shot down Pike's Bomber" or "Research complete:
## ...". It also remembers how the human's own ship last died, for the
## respawn banner.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_feed.tscn: one empty
## column, 330 pixels wide, 10 pixels in from the top-right corner and
## growing to the left, that the mouse passes through. The lines are made
## here in code, one per piece of news. Hud connects game news (Events) to
## the on_* functions here. Each one decides whether our side should hear
## about it, writes a sentence, and adds it as a line with add_line().
## Colours: amber for good news for us, cinder (red) for bad news, team
## colours for a spectator, mist (grey) for plain information. At most
## MAX_LINES lines are kept; Hud._refresh() fades each one out after LIFE
## seconds (fade_lines()).
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it. Hud.setup()
## gives it the world and connects Events.feed, unit_killed,
## turret_destroyed, research_done and facility_done to it. HudBanner reads
## last_cause; Hud._on_respawned() clears it. Hud also uses fade_lines()
## for HudMePanel's earnings log.

## Most lines the feed shows at once (older ones are removed).
const MAX_LINES := 7
## How long (seconds) a feed line stays. It fades out during its last 1.5
## seconds.
const LIFE := 9.0

## The game world (Hud.setup() sets it).
var world: World
## How the human's own ship was last destroyed ("Wren shot down Pike's
## Bomber"), shown on the respawn banner; "" after they respawn.
var last_cause := ""


## Fade out and remove the old lines of `box`. Every line remembers when it
## was made ("born" metadata, in milliseconds). A line older than `life`
## seconds is removed; during its last 1.5 seconds it fades (modulate.a is
## its see-through amount: 1 = solid, 0 = invisible).
static func fade_lines(box: Container, life: float) -> void:
	var now := Time.get_ticks_msec()
	for c in box.get_children():
		var age := float(now - int(c.get_meta("born", now))) / 1000.0
		if age > life:
			c.queue_free()
		elif age > life - 1.5:
			(c as CanvasItem).modulate.a = (life - age) / 1.5
	# (queue_free removes a node at the end of the frame, not at once.)


## Add one line of `text` in colour `col`, right-aligned with a dark
## outline so it reads over the game. Drops the oldest lines past MAX_LINES.
func add_line(text: String, col: Color) -> void:
	var l := UiKit.label(text, 13, col, true)
	l.custom_minimum_size = Vector2(330, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Palette.VOID)
	l.add_theme_constant_override("outline_size", 4)
	l.set_meta("born", Time.get_ticks_msec())
	add_child(l)
	while get_child_count() > MAX_LINES:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()


## The team whose eyes we see through (-1 = a spectator who sees all).
func _vt() -> int:
	return world.viewer_team


## The colour for news that is good for `team`: amber if that is our
## team, cinder (red) if not. A spectator sees team colours instead.
func _good_bad(team: int) -> Color:
	if _vt() < 0:
		return Palette.team(team)
	return Palette.AMBER if team == _vt() else Palette.CINDER


## A plain feed message (Events.feed). `tone` is "good", "bad" or "info";
## `team` is whose news it is (-1 = everyone's). We hide the enemy's own
## good and bad news, and also their "free mining drone" info lines.
func on_feed(text: String, tone: String, team: int) -> void:
	if team >= 0 and _vt() >= 0 and team != _vt() and tone != "info":
		return
	if team >= 0 and _vt() >= 0 and team != _vt() and text.contains("free mining drone"):
		return
	add_line(text, Palette.MIST if tone == "info" else Palette.ICE)


## Something died (Events.unit_killed). `info` is the DamageInfo of the
## killing blow. Ships always get a line, repair bays too; a cleared
## derelict only when our side cleared it. Other kills are not shown.
func on_unit_killed(u: Node, info: RefCounted) -> void:
	var d := info as DamageInfo
	var unit := u as Unit
	if unit == null:
		return
	var killer: PilotProfile = d.source_profile as PilotProfile
	match unit.kind:
		Unit.K_SHIP:
			# A ship: say who or what destroyed it, coloured for the
			# killer's side (good for us if an enemy ship died).
			var s := unit as Ship
			var victim := s.profile
			var cause := _ship_cause(s, d, killer)
			add_line(cause, _good_bad(1 - s.team) if _vt() >= 0 else Palette.team(1 - s.team))
			if victim != null and victim == world.human:
				last_cause = cause
		Unit.K_BAY:
			add_line("%s repair bay at %s destroyed" % [Rules.TEAM_NAMES[unit.team], world.place_name(unit.global_position)], _good_bad(1 - unit.team))
		Unit.K_MONSTER:
			if killer != null and (_vt() < 0 or killer.team == _vt()):
				add_line("%s cleared a derelict %s" % [killer.callsign, (unit as Derelict).ctype], Palette.VEIL)


## The sentence for ship `s` being destroyed by the blow `d` (fired by
## pilot `killer`, or null when no pilot did it): shot down by a pilot,
## crashed into an asteroid, destroyed by something else (a turret, a
## minion, a mothership, a derelict...), or just "destroyed".
func _ship_cause(s: Ship, d: DamageInfo, killer: PilotProfile) -> String:
	var victim := s.profile
	var hull := String(Ships.HULLS[s.hull_id]["label"])
	var vname := victim.callsign if victim != null else "A pilot"
	var cause := ""
	if killer != null:
		cause = "%s shot down %s's %s" % [killer.callsign, vname, hull]
	elif d.kind == Rules.W_COLLISION:
		cause = "%s's %s crashed into an asteroid" % [vname, hull]
	elif d.source != null and is_instance_valid(d.source):
		# Name the thing that fired, with its team: "a Cinder turret",
		# "the Halcyon mothership" or "a derelict gunship".
		var what: String = Unit.KIND_NAMES[d.source.kind]
		if d.source.kind == Unit.K_MOTHERSHIP:
			what = "the %s mothership" % Rules.TEAM_NAMES[d.source.team]
		elif d.source.team == Rules.NEUTRAL:
			what = "a derelict " + what
		else:
			what = "a %s %s" % [Rules.TEAM_NAMES[d.source.team], what]
		cause = "%s's %s was destroyed by %s" % [vname, hull, what]
	else:
		cause = "%s's %s was destroyed" % [vname, hull]
	return cause


## A turret was destroyed (Events.turret_destroyed) by team `by_team`
## (-1 = nobody's, shown as "Someone"). Names its resource node, or, if it
## has none, the name World.place_name() gives the spot where it stood.
func on_turret_destroyed(t: Node, by_team: int) -> void:
	var tu := t as Turret
	if tu == null:
		return
	var where := tu.node.node_name if tu.node != null else world.place_name(tu.global_position)
	add_line("%s destroyed the %s %s at %s" % [Rules.TEAM_NAMES[by_team] if by_team >= 0 else "Someone", Rules.TEAM_NAMES[tu.team], String(tu.tdef["label"]), where], _good_bad(by_team))


## Team `team` finished research `id` (Events.research_done). Only our
## own team's research is shown. If it unlocked a ship that can now be
## bought, the line says so.
func on_research_done(team: int, id: String) -> void:
	if _vt() >= 0 and team != _vt():
		return
	var d: Dictionary = Tech.TECHS[id]
	var extra := ""
	var eff: Dictionary = d["effect"]
	if eff.has("unlock_ship"):
		var sid: String = eff["unlock_ship"]
		if world.teams[team].ship_unlocked(sid):
			extra = " %s can now be bought in the hangar." % Ships.HULLS[sid]["label"]
	add_line("Research complete: %s.%s" % [d["label"], extra], Palette.REPAIR)


## Team `team` finished building mothership module `id`
## (Events.facility_done). Only our own team's modules are shown. Ships
## that this module unlocks ("fac:<id>" in Ships.HULLS) are named; if
## there are several, the last one in Ships.ORDER wins.
func on_facility_done(team: int, id: String) -> void:
	if _vt() >= 0 and team != _vt():
		return
	var extra := ""
	for sid: String in Ships.ORDER:
		if Ships.HULLS[sid]["unlock"] == "fac:" + id:
			extra = " %s can now be bought in the hangar." % Ships.HULLS[sid]["label"]
	add_line("Module built: %s.%s" % [Tech.FACILITIES[id]["label"], extra], Palette.REPAIR)
