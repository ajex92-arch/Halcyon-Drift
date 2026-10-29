class_name RoutingPayoffFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "routing_payoff" rule variant
## (idea E4 of the combat_roles fork): a payoff for holding an energy
## routing mode. Pilots who keep their ship's power routed to Weapons,
## Shields or Thrusters long enough get a one-shot bonus, so using the
## routing switch well (and early) shows in the fight.
##
## HOW IT WORKS: install() adds one function to the match's tick hooks. Each
## tick it follows every live pilot ship:
##   - It counts how long the ship has stayed in its current routing mode
##     (changing the mode starts the count again). After HOLD_TIME seconds
##     (3 for a SMALL ship, 4 MEDIUM, 6 LARGE, 8 CAPITAL) in Weapons, Shields
##     or Thrusters the ship is "charged", and a pip lights in the ship
##     status panel (RoleHud). Balanced never charges. The mode-switch
##     cooldowns are not changed.
##   - Weapons charged: the ship's next shot from a main gun (a gun that is
##     not an automatic one) opens a 2 second overcharge. During it ALL
##     damage the ship deals is x1.4 (a rule in RoleScaling, the damage
##     calculator with plug-in rules). Then the charge is used up.
##   - Shields charged: the first hit the ship takes gives the shield zone
##     named by its focus (the front zone with Balanced focus) an extra
##     "overshield" of 40% of that zone's size. Hits drain the overshield
##     first. It is lost when it is used up or after 6 seconds.
##   - Thrusters charged: the next boost is free for 1.5 seconds (the
##     energy it uses is paid back every tick) and pushes 20% harder.
## Every charge that is used is counted in Game.usage as "charges_spent"
## (and by kind in "charges_weapons", "charges_shields",
## "charges_thrusters").
##
## THE AI: the AI pilots who already route energy (RoutingPayoffSystems
## checks that the original PilotSystems rule asked for a routing change;
## that rule is the existing skill > 0.55 one, nothing new) hold Weapons
## when an enemy ship is 1.2 to 2 weapon ranges away, so they are charged
## when the fight starts instead of switching on contact. RoleBrains puts
## the new part into the brains.
##
## WHO USES IT: FeatureRegistry installs it for --variant=routing_payoff:on.
## RoutingPayoffSystems counts its holds; RoleHud reads charged_mode().

## The variant key this module belongs to.
const KEY := "routing_payoff"
## Seconds a ship must stay in one routing mode to be charged, by size class
## (small, medium, large, capital).
const HOLD_TIME := [3.0, 4.0, 6.0, 8.0]
## Length (seconds) of the weapons overcharge.
const OVERCHARGE_TIME := 2.0
## Damage multiplier during the overcharge (1.4 = +40%).
const OVERCHARGE_MULT := 1.4
## Size of the overshield as a share of the focused zone's size (0.4 = 40%).
const OVERSHIELD_SHARE := 0.4
## How long (seconds) an overshield lasts if it is not used up.
const OVERSHIELD_TIME := 6.0
## Length (seconds) of the free, stronger boost.
const FREE_BOOST_TIME := 1.5
## Extra push of the free boost (0.2 = +20%).
const FREE_BOOST_THRUST := 0.2
## A hit counts as "just now" for the Shields payoff when it happened this
## many seconds ago or less (a few ticks).
const HIT_WINDOW := 0.1

## The match.
var world: World
## Seconds since the AI parts were last checked.
var _t := 0.0
## What we know about each pilot ship: ship uid -> a Dictionary with
## "mode" (the routing mode being held), "held" (seconds held), "charged"
## (true when the pip is lit), "over_until" (match time when the
## overcharge ends), "free_until" (match time when the free boost ends),
## "shield_zone" and "shield_until" (the overshield; zone -1 = none),
## "cds" (each gun's cooldown last tick) and "beams" (true while a main
## beam fired last tick).
var _state := {}


## Plug the feature into match `w`: the overcharge damage rule, a tick hook
## and the AI part. FeatureRegistry calls it once at match start.
func install(w: World) -> void:
	world = w
	RoleScaling.attach(w).hooks.append(Callable(self, "_damage"))
	w.tick_hooks.append(Callable(self, "_tick"))
	RoleBrains.ensure(w, "systems", RoutingPayoffSystems)


## The damage rule: x1.4 for every hit dealt by a pilot ship whose
## overcharge is on.
func _damage(_target: Unit, info: DamageInfo, amount: float) -> float:
	if not info.source_is_pilot:
		return amount
	var st = _state.get(info.source_uid)
	if st == null or world.time >= float(st["over_until"]):
		return amount
	return amount * OVERCHARGE_MULT


## Every tick (a hook): follow every live pilot ship.
func _tick(dt: float) -> void:
	# Step 1: now and then, give new brains the AI part.
	_t += dt
	if _t >= RoleBrains.CHECK_EVERY:
		_t = 0.0
		RoleBrains.ensure(world, "systems", RoutingPayoffSystems)
	# Step 2: follow each live ship, and forget the gone ones.
	var live := {}
	for s: Ship in world.ships:
		if s.alive:
			live[s.uid] = true
			_follow(s, dt)
	for uid in _state.keys():
		if not live.has(uid):
			_state.erase(uid)


## This ship's record, made when first needed.
func _record(s: Ship) -> Dictionary:
	var st = _state.get(s.uid)
	if st == null:
		st = {"mode": s.energy.mode, "held": 0.0, "charged": false, "over_until": 0.0, "free_until": 0.0,
			"shield_zone": -1, "shield_until": 0.0, "cds": PackedFloat32Array(), "beams": false}
		_state[s.uid] = st
	return st


## One tick of following ship `s`: count the hold time, light the pip, and
## use the charge when its moment comes (see HOW IT WORKS).
func _follow(s: Ship, dt: float) -> void:
	var st := _record(s)
	var mode := s.energy.mode
	# Step 1: the hold time. A new mode starts the count again and drops any
	# charge.
	if mode != int(st["mode"]):
		st["mode"] = mode
		st["held"] = 0.0
		st["charged"] = false
	else:
		st["held"] = float(st["held"]) + dt
	# Step 2: charged after the hold time, in a mode that has a payoff.
	var need: float = HOLD_TIME[Rules.size_index(s.size_class)]
	if mode != Rules.ENERGY_BALANCED and not bool(st["charged"]) and float(st["held"]) >= need:
		st["charged"] = true
	# Step 3: the payoffs that are waiting for their moment.
	var fired := _fired(s, st)
	if bool(st["charged"]):
		if mode == Rules.ENERGY_WEAPONS and fired:
			st["over_until"] = world.time + OVERCHARGE_TIME
			_spend(st, "charges_weapons")
		elif mode == Rules.ENERGY_SHIELDS and s.last_damage_time >= world.time - HIT_WINDOW:
			_overshield(s, st)
			_spend(st, "charges_shields")
		elif mode == Rules.ENERGY_THRUSTERS and s.boosting:
			st["free_until"] = world.time + FREE_BOOST_TIME
			_spend(st, "charges_thrusters")
	# Step 4: the effects that are running.
	if world.time < float(st["free_until"]) and s.boosting:
		s.energy.value = minf(s.energy.max_value, s.energy.value + s.f_boost_drain * dt)
		s.velocity += Vector2.from_angle(s.rotation) * s.f_accel * s.f_boost_mul * FREE_BOOST_THRUST * dt
	_tick_overshield(s, st)


## A charge has been used: start the count again, and count it.
func _spend(st: Dictionary, kind_name: String) -> void:
	st["charged"] = false
	st["held"] = 0.0
	Game.count_usage("charges_spent")
	Game.count_usage(kind_name)


## Did ship `s` fire a main gun (not an automatic one) this tick? Also
## remembers each gun's cooldown for the next tick: a gun that has just
## fired has a longer cooldown than it had a tick ago. A beam counts when it
## starts firing.
func _fired(s: Ship, st: Dictionary) -> bool:
	var cds: PackedFloat32Array = st["cds"]
	if cds.size() != s.mounts.size():
		# First look (or the guns changed): remember, report nothing.
		cds.resize(s.mounts.size())
		for i in s.mounts.size():
			cds[i] = s.mounts[i].cd
		st["cds"] = cds
		return false
	var fired := false
	var beam_now := false
	for i in s.mounts.size():
		var m: WeaponMount = s.mounts[i]
		if m.mount_type == WeaponMount.AUTO:
			cds[i] = m.cd
			continue
		if m.is_beam:
			beam_now = beam_now or m.beam_firing
		elif m.cd > cds[i] + 0.0001:
			fired = true
		cds[i] = m.cd
	# A beam "fires" when it was off last tick and is on now.
	if beam_now and not bool(st["beams"]):
		fired = true
	st["beams"] = beam_now
	st["cds"] = cds
	return fired


## Give ship `s` the overshield (see HOW IT WORKS): +40% of the focused
## zone's size on that zone.
func _overshield(s: Ship, st: Dictionary) -> void:
	var sh := s.shields
	# The focus numbers are zone + 1 (Rules.FOCUS_FRONT = 1 ...); Balanced
	# (0) uses the front zone.
	var zone := maxi(0, sh.focus - 1)
	sh.values[zone] += OVERSHIELD_SHARE * sh.cap(zone)
	st["shield_zone"] = zone
	st["shield_until"] = world.time + OVERSHIELD_TIME


## End an overshield that is used up or has run out its time: the zone goes
## back to at most its normal size.
func _tick_overshield(s: Ship, st: Dictionary) -> void:
	var zone := int(st["shield_zone"])
	if zone < 0:
		return
	var sh := s.shields
	if world.time >= float(st["shield_until"]) or sh.values[zone] <= sh.cap(zone):
		sh.values[zone] = minf(sh.values[zone], sh.cap(zone))
		st["shield_zone"] = -1


## The routing mode (Rules.ENERGY_*) that ship `s` is charged in, or -1 when
## it is not charged. RoleHud lights the pip with it.
func charged_mode(s: Ship) -> int:
	var st = _state.get(s.uid)
	if st == null or not bool(st["charged"]):
		return -1
	return int(st["mode"])


## Seconds of overcharge left on ship `s` (0 when none). RoleHud shows it.
func overcharge_left(s: Ship) -> float:
	var st = _state.get(s.uid)
	if st == null:
		return 0.0
	return maxf(0.0, float(st["over_until"]) - world.time)
