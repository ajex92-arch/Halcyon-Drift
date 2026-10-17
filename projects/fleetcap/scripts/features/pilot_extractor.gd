class_name PilotExtractor
extends Unit
## WHAT THIS IS: a pilot's personal ore extractor, the small structure of
## the pilot_mining:extractor idea (PilotMiningFeature). A pilot pays 500
## credits to anchor one on a free ore node; it then pays its owner 3
## credits per second for as long as it stands. REQ-CHANGE: the user removed
## pilot-independent extractors, so this exists only as a switchable
## variant.
##
## HOW IT WORKS: it is a Unit of its own kind (Unit.K_EXTRACTOR) that sits
## on the node's centre with 600 hull and no shields, belongs to the
## owner's team, and can be shot by the enemy like any structure. Each tick
## it pays its owner. When it is destroyed, the enemy pilot who made the
## last hit gets 150 credits (PilotMiningFeature pays that). It is in
## World.units (so it is hit, seen and removed like any unit) but in none of
## the kind lists. It draws itself (a diamond in the team colour and a hull
## bar); there is no scene file for it.
##
## WHO USES IT: PilotMiningFeature.build_extractor() makes it through
## World.registry (attach, setup, index).

## Hull points when new.
const HULL := 600.0
## Credits per second it pays its owner.
const INCOME := 3.0
## How big it is, as a circle radius in world units.
const SIZE := 45.0

## The pilot who owns it (and is paid).
var owner_profile: PilotProfile = null
## The ore node it stands on.
var node: ResourceNode = null
## Credits it has paid its owner so far, not yet counted in Game.usage.
var _carry := 0.0


## Set the extractor up for pilot `p` on ore node `n` in world `w`.
## PilotMiningFeature calls this between attach() and index().
func setup(w: World, p: PilotProfile, n: ResourceNode) -> void:
	world = w
	owner_profile = p
	node = n
	team = p.team
	kind = Unit.K_EXTRACTOR
	size_class = Rules.SIZE_STRUCTURE
	radius = SIZE
	hull_max = HULL
	hull = HULL
	vision_radius = 0.0
	display_name = "%s's extractor" % p.callsign
	position = n.global_position
	# No physics bumps: ships fly through it, shots still hit it.
	collision_layer = 0
	collision_mask = 0


## One tick of `dt` seconds: pay the owner.
func sim_update(dt: float) -> void:
	if not alive:
		return
	if flash > 0.0:
		flash = maxf(0.0, flash - dt)
		queue_redraw()
	owner_profile.credits += INCOME * dt
	owner_profile.earned += INCOME * dt
	_carry += INCOME * dt
	if _carry >= 1.0:
		Game.count_usage("extractor_credits", int(_carry))
		_carry -= floorf(_carry)


## Combat.kill() calls this when the extractor is destroyed: a puff of
## sparks in the team's colour.
func on_killed(_info: DamageInfo) -> void:
	world.effects.puff(global_position, Palette.team(team), 14)


## Draw a diamond in the team colour (white while it flashes from a hit) and
## a small hull bar under it.
func _draw() -> void:
	var col := Palette.team(team)
	var fill := Palette.with_alpha(col, 0.55)
	if flash > 0.0:
		fill = Color(1, 1, 1, 0.9)
	var r := SIZE
	var pts := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, 6.0, true)
	draw_rect(Rect2(-r, r + 12.0, r * 2.0, 8.0), Palette.with_alpha(Palette.VOID, 0.75))
	draw_rect(Rect2(-r, r + 12.0, r * 2.0 * clampf(hull_frac(), 0.0, 1.0), 8.0), col)
