class_name ShieldZones
extends RefCounted
## WHAT THIS IS: a unit's energy shield, split into four zones: front, rear,
## left and right. A hit only drains the zone on the side it came from.
## DESIGN.md A5.
##
## HOW IT WORKS:
##   - The shield has one total size (`max_total`). The "focus" setting
##     decides how that total is shared between the four zones
##     (Rules.FOCUS_WEIGHTS): Balanced gives each zone 25%; focusing Front
##     gives the front 50%, the rear 10% and each side 20% (and so on for
##     Rear, Left and Right). A zone's share is its "cap" (its maximum).
##   - A hit drains the zone facing the attacker (absorb()). Whatever that
##     zone can't hold goes on to the hull.
##   - Changing focus doesn't create or lose shield: the shield you have
##     right now is moved into the new shares (set_focus()).
##   - After `delay` seconds without a hit, the shield refills (tick()),
##     topping up the emptiest zones the most.
##   - `single = true` turns it into one shared pool with no zones (minions,
##     turrets, repair bays and the mothership use this); only zone 0 holds
##     anything.
##
## WHO USES IT: every Unit has a `shields` (or null). Ship, Minion, Turret,
## RepairBay and Mothership create and set it up. Unit.take_hit() calls
## zone_for_local() and absorb(); each owner calls tick() every tick; Ship
## calls set_focus() when the pilot asks; Ship.recompute_stats() and the
## Mothership call set_max() when upgrades change the size. ShipVisual and
## the HUD draw `values`, cap() and fraction(); PlayerController and the AI
## pilots read `focus` (the AI also uses zone_for_local()).

## The total shield size over all four zones, in shield points.
var max_total := 0.0
## The shield points in each zone right now, in the order front, rear,
## left, right (Rules.ZONE_FRONT, ZONE_REAR, ZONE_LEFT, ZONE_RIGHT = 0..3).
var values := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## The focus setting: one of Rules.FOCUS_BALANCED, FOCUS_FRONT, FOCUS_REAR,
## FOCUS_LEFT or FOCUS_RIGHT (0..4).
var focus := Rules.FOCUS_BALANCED
## True for one shared pool with no zones (only values[0] is used).
var single := false
## How fast the shield refills, in shield points per second.
var regen := 0.0
## Seconds without a hit before refilling starts.
var delay := 3.5
## The fraction (0..1) of each hit the shield shrugs off (0.9 at most,
## counting any extra resistance passed to absorb()).
var resist := 0.0
## Seconds since the last hit (starts high: "not hit for ages").
var since_hit := 999.0
## Per zone: seconds left on the "this zone just broke" flash (set to 0.4 s
## when a zone is emptied; only for drawing).
var flash := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


## Set up a full shield: `total` shield points, refilling at `regen_rate`
## per second after `delay_s` seconds without a hit. `single_pool` = one
## shared pool with no zones.
func setup(total: float, regen_rate: float, delay_s: float, single_pool: bool = false) -> void:
	max_total = total
	regen = regen_rate
	delay = delay_s
	single = single_pool
	fill()


## The most shield zone `zone` (0..3) can hold with the current focus. A
## single pool keeps everything in zone 0.
func cap(zone: int) -> float:
	if single:
		return max_total if zone == 0 else 0.0
	return max_total * float(Rules.FOCUS_WEIGHTS[focus][zone])


## Shield points left over all four zones.
func total() -> float:
	return values[0] + values[1] + values[2] + values[3]


## How full the shield is, as a 0..1 fraction (0 if it has no size).
func fraction() -> float:
	return total() / max_total if max_total > 0.0 else 0.0


## Fill every zone to its cap.
func fill() -> void:
	for z in 4:
		values[z] = cap(z)


## Change the total size (e.g. a module or upgrade) keeping the same
## fraction full: a half-full shield stays half full.
func set_max(new_total: float) -> void:
	var f := fraction() if max_total > 0.0 else 1.0
	max_total = new_total
	for z in 4:
		values[z] = cap(z) * f


## Which zone a hit lands on. `local` is where the attacker is "in the
## ship's own frame": as if the ship were facing right, so +x is ahead and
## +y is to the right (starboard). We measure the attacker's angle: within
## 45 degrees (PI/4 radians) of the nose is the front, within 45 degrees of
## the tail is the rear, and the rest is the left or right side.
static func zone_for_local(local: Vector2) -> int:
	var a := atan2(local.y, local.x)
	if absf(a) <= PI * 0.25:
		return Rules.ZONE_FRONT
	if absf(a) >= PI * 0.75:
		return Rules.ZONE_REAR
	return Rules.ZONE_LEFT if a < 0.0 else Rules.ZONE_RIGHT


## Soak `raw` damage on zone `zone`. Resistance (our `resist` plus
## `extra_resist`, at most 0.9 together) shrinks the hit before it drains
## the zone. Returns the raw damage left over for the hull.
func absorb(zone: int, raw: float, extra_resist: float = 0.0) -> float:
	since_hit = 0.0
	var zi := 0 if single else zone
	var z := values[zi]
	# An empty zone lets the whole hit through.
	if z <= 0.0:
		return raw
	# Shrink the hit by our resistance. If the zone can hold it all, it
	# drains and nothing reaches the hull.
	var r := 1.0 - clampf(resist + extra_resist, 0.0, 0.9)
	var eff := raw * r
	if eff <= z:
		values[zi] = z - eff
		return 0.0
	# Too big: the zone breaks (and flashes). The hull gets the part of the
	# raw hit the zone couldn't cover (z / r is how much raw damage the
	# zone's points were worth).
	values[zi] = 0.0
	flash[zi] = 0.4
	return raw - z / r


## Switch to focus setting `f`, moving the shield we have right now into
## the new shares.
func set_focus(f: int) -> void:
	if single or f == focus:
		return
	# Step 1: share the current total out by the new weights (no zone above
	# its new cap) and count what didn't fit.
	var t := total()
	focus = f
	var left := t
	for z in 4:
		var v := minf(cap(z), t * float(Rules.FOCUS_WEIGHTS[f][z]))
		values[z] = v
		left -= v
	# Step 2: anything that didn't fit (capped zones) tops up the others.
	for z in 4:
		if left <= 0.0:
			break
		var room := cap(z) - values[z]
		var add := minf(room, left)
		values[z] += add
		left -= add


## Refill for one tick of `dt` seconds. `mult` multiplies the refill speed
## (energy routing, gear and waypoint bonuses); `delay_bonus` adds seconds
## to the wait (gear). The wait is never shorter than 0.5 s.
func tick(dt: float, mult: float, delay_bonus: float = 0.0) -> void:
	since_hit += dt
	if single:
		# Cheap path for minions, turrets, bays and the mothership: one
		# shared pool.
		if since_hit >= maxf(0.5, delay + delay_bonus) and values[0] < max_total and regen > 0.0:
			values[0] = minf(max_total, values[0] + regen * mult * dt)
		return
	# Count down the "zone broke" flashes.
	for z in 4:
		if flash[z] > 0.0:
			flash[z] = maxf(0.0, flash[z] - dt)
	# Still waiting after the last hit (or no refill at all)? Then stop.
	if since_hit < maxf(0.5, delay + delay_bonus) or regen <= 0.0:
		return
	var amount := regen * mult * dt
	# Fill zones in proportion to their missing shield: add up what is
	# missing, then give every zone the same share k (0..1) of its gap.
	var missing := 0.0
	for z in 4:
		missing += maxf(0.0, cap(z) - values[z])
	if missing <= 0.0:
		return
	var k := minf(1.0, amount / missing)
	for z in 4:
		values[z] += maxf(0.0, cap(z) - values[z]) * k
