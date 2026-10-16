class_name PilotCombat
extends RefCounted
## WHAT THIS IS: the AI pilot's hands on the controls, every tick (a part of
## PilotAI): either fight the current target, or fly toward the goal and
## only take the shots that are already lined up.
##
## HOW IT WORKS: steer() runs every tick. If we have a live target, aren't
## heading home or running away, and the target isn't far off, fight()
## flies the attack:
##   - medium and bigger ships hold a spot near the target, keep the nose
##     toward it (while still far from that spot they keep the nose they
##     fly with) and let their turrets aim; a big ship with a FIXED main
##     gun (the ion frigate) fires, and uses its special, only when the nose
##     points at the target;
##   - bombers keep their distance (most of their torpedo reach), back off
##     if the target comes close, and fire torpedoes when lined up;
##   - other strike craft close in, then creep closer while sliding
##     sideways around the target, backing off when they get too close,
##     and fire when the nose points at it (the lance also switches on its
##     Overload while the beam is on the target);
##   - a beam gun aims straight at the target (a beam hits at once, so
##     there is nothing to lead). All of a ship's turrets take the one aim
##     point, so a ship whose first gun is a beam aims every turret straight
##     at the target: the battlecruiser (first gun: an ion turret) fires its
##     heavy cannon without lead;
##   - a strike craft holds fire while a rock is between it and the target
##     (the shot would hit the rock), and gives the target up for 6 seconds
##     once it has stayed hidden for 3.
## Otherwise PilotFlight.travel() flies us to the goal.
##
## WHO USES IT: PilotAI.update() calls steer() every tick. It uses
## PilotFlight (travel, avoid_rocks, and target_hidden() with its hidden_t
## count) and PilotTargeting.main_reach(); when fight() gives up a hidden
## target it sets PilotAI.skip_id and skip_until and clears target and
## lock_target. It fills the ship's ShipControls (aim_point, face_point,
## forward, strafe, boost, fire, special).
##
## Words used here:
##   aim point   the world point the guns aim at.
##   face point  the world point the ship's nose turns toward.
##   strafe      sliding sideways with the side thrusters (+1 = to the left
##               (port), -1 = to the right (starboard)).
##   lead        aiming ahead of a moving target, where it will be when the
##               shot arrives (Util.lead_point).
##   special     each hull's special ability button (snap turn, focus
##               shot, ping, Overload...), see Ships.HULLS.
##   fixed gun   a gun bolted to the hull that fires straight ahead
##               (WeaponMount.FIXED): the whole ship turns to aim it.
##   beam        a gun whose shot hits instantly along a line (the lance,
##               the ion frigate), so it needs no lead.
##   angles      in radians: 0.1 is about 6 degrees, 1.0 about 57 degrees.

## The pilot brain this part belongs to (we read its target, goal, state,
## skill and orbit). It is reached through a weak link: see `_ai_ref`.
## Speed: every use of `ai` goes through the weak link (a small lookup), so each function below looks it up once into a local, `brain`, and uses that.
var ai: PilotAI:
	get:
		return _ai_ref.get_ref() as PilotAI

## A "weak" link to the brain. The brain holds this part with a normal
## (strong) link. If the part held the brain strongly too, each would keep
## the other alive forever and Godot could never free them (a memory leak).
## A weak link points at the brain without keeping it alive.
var _ai_ref: WeakRef


## Remember which brain we belong to.
func _init(owner: PilotAI) -> void:
	_ai_ref = weakref(owner)


## Every tick: fight the target, or fly to the goal.
func steer(ship: Ship) -> void:
	var brain := ai
	# Step 1: let go of the trigger, boost and special buttons; forget a
	# target that died or was removed.
	var c := ship.controls
	c.fire = false
	c.boost = false
	c.special = false
	if brain.target != null and (not is_instance_valid(brain.target) or not brain.target.alive):
		brain.target = null
	# Step 2: fight, unless going home, retreating, falling back (small
	# ships), or the target is still far away.
	var leaving := brain.state == "retreat" or (brain.fallback_t > 0.0 and ship.is_small())
	if brain.target != null and brain.state != "home" and not leaving and not target_far(ship):
		fight(ship)
	else:
		# Retreating (or falling back): fly away, and only take shots that
		# are already in front of the nose; never turn back to fight.
		brain.flight.travel(ship, brain.goal, 160.0)
		c.aim_point = c.face_point
		if leaving and brain.target != null:
			var to_t := brain.target.global_position - ship.global_position
			# Big ships' turrets swing round on their own; strike craft need
			# the target already in front of the nose (within 0.25 rad), and
			# so does a big ship whose main gun is fixed (the ion frigate;
			# within 0.1 rad).
			var arc_ok := not ship.is_small() or absf(Util.ang_diff(ship.rotation, to_t.angle())) < 0.25
			if not ship.is_small() and not ship.mounts.is_empty() and ship.mounts[0].mount_type == WeaponMount.FIXED:
				arc_ok = absf(Util.ang_diff(ship.rotation, to_t.angle())) < 0.1
			if to_t.length() < PilotTargeting.main_reach(ship) and arc_ok:
				c.aim_point = brain.target.global_position
				c.fire = true


## A push/assault target still far away (a mothership or turret 15,000
## off): follow the route to our goal (the standoff point) first. Far means
## more than 3,500 from its edge (mothership: its hull), or more than 2.5
## times our main reach if that is bigger. (Playtest: fight() pointed the
## nose straight at it, through the jungle and around the base, and big
## ships crawled ~30 units a second toward a siege for minutes.)
func target_far(ship: Ship) -> bool:
	var brain := ai
	var target := brain.target
	var d: float
	if target is Mothership:
		d = (target as Mothership).hull_dist(ship.global_position)
	else:
		d = ship.global_position.distance_to(target.global_position) - target.radius
	return d > maxf(3500.0, PilotTargeting.main_reach(ship) * 2.5)


## Fly the attack on the brain's target (see HOW IT WORKS at the top).
func fight(ship: Ship) -> void:
	var brain := ai
	var c := ship.controls
	var target := brain.target
	# Step 1: where the target is. For a mothership, the closest point on
	# its spine (the line from bow to stern).
	var tp := target.global_position
	if target is Mothership:
		tp = Util.closest_on_segment(ship.global_position,
			target.global_position + Vector2.from_angle(target.rotation) * (target as Mothership).half_len,
			target.global_position - Vector2.from_angle(target.rotation) * (target as Mothership).half_len)
	var d := ship.global_position.distance_to(tp)
	# Step 2: our first gun's shot speed and reach (1,200 and 700 if we
	# have no gun).
	var main := ship.mounts[0] if not ship.mounts.is_empty() else null
	var speed := float(main.def.get("speed", 1200.0)) if main != null else 1200.0
	var reach := (main.reach * ship.range_mult) if main != null else 700.0
	# Step 3: aim ahead of the target (lead). Weaker pilots aim a little
	# off: an error of up to 0.06 rad at skill 0.5, swinging slowly back and
	# forth over time (a sine wave).
	var lead := Util.lead_point(ship.global_position, ship.velocity * 0.35, tp, target.velocity, speed)
	# A beam hits at once, so there is nothing to lead: aim straight at the
	# target. Every turret gets this one aim point, so it holds for all of the
	# ship's turrets when the first gun is a beam (the battlecruiser's heavy
	# cannon fires without lead; its two ion turrets are beams).
	if main != null and main.is_beam:
		lead = tp
	var err := (1.0 - brain.skill) * 0.12 * sin(brain.world.time * 1.3 + float(brain.profile.slot))
	var aim := ship.global_position + (lead - ship.global_position).rotated(err)
	c.aim_point = aim
	if ship.size_class >= Rules.SIZE_MEDIUM:
		# Big ships: turrets aim; the hull holds its station facing the enemy.
		c.face_point = tp if d > 200.0 else ship.global_position + Vector2.from_angle(ship.rotation) * 400.0
		# Where to hold: for a push, the standoff point (goal); if our goal
		# is far from the target (more than 60% of our reach), the goal;
		# otherwise a spot at 75% of our reach from the target, on our side.
		var hold: Vector2
		if brain.intent == "push":
			# goal is already the standoff point for the structure.
			hold = brain.goal
		elif brain.goal.distance_to(tp) > reach * 0.6:
			hold = brain.goal
		else:
			hold = tp + (ship.global_position - tp).normalized() * reach * 0.75
		brain.flight.travel(ship, hold, 200.0)
		# Far from the hold point (more than 500), keep the nose that travel()
		# chose (its thrust was worked out for it) and let the turrets aim.
		# The ion frigate's beam is fixed, so it turns to the target as soon as
		# the target is in reach.
		var far_hold := ship.global_position.distance_to(hold) > 500.0
		if not (far_hold and (ship.hull_id != "ion" or d > reach + target.radius)):
			c.face_point = tp
		c.fire = d < reach + target.radius
		# A FIXED main gun (the ion frigate's burst beam) only starts when
		# the nose points at the target: one trigger pull commits the ship to
		# a whole 2 s burst.
		var fixed_main := main != null and main.mount_type == WeaponMount.FIXED
		if fixed_main and c.fire:
			var mp := main.world_pos()
			var tol := asin(clampf((target.radius + 2.0) / maxf(mp.distance_to(tp), 1.0), 0.0, 1.0)) + 0.02
			if absf(Util.ang_diff(ship.rotation, (tp - mp).angle())) > tol:
				c.fire = false
		# Use the special in reach (a logistics ship saves its emergency
		# repair, which heals allies nearby, until its own hull is below
		# 70%). With a fixed main gun it goes off together with the burst.
		if ship.special_ready() and d < reach:
			c.special = ship.hull_id != "logistics" or ship.hull_frac() < 0.7
			if fixed_main:
				c.special = c.fire
		return
	# A target hidden behind rocks: hold fire (a shot would only hit the
	# rock), and once it has stayed hidden for 3 s give it up for 6 s (the
	# brain picks another target, or goes back to its station).
	var hidden := brain.flight.target_hidden(ship, tp)
	if hidden and brain.flight.hidden_t > 3.0:
		brain.skip_id = target.get_instance_id()
		brain.skip_until = brain.world.time + 6.0
		brain.target = null
		brain.lock_target = null
		brain.flight.hidden_t = 0.0
		brain.flight.travel(ship, brain.goal, 160.0)
		c.aim_point = c.face_point
		return
	# How far (in radians) the nose is from the aim point.
	var ang_err := absf(Util.ang_diff(ship.rotation, (aim - ship.global_position).angle()))
	match ship.hull_id:
		"bomber":
			# Stand-off barrage: hold at 80-95% of torpedo reach (55-95% for
			# small targets), nose on the target, and keep the torpedoes
			# coming; back off if it closes (flak frigates reach ~720,
			# torpedoes ~1,200). Too close to turn away safely: burn
			# straight out past it.
			var near := target.radius + (reach * 0.8 if target.size_class >= Rules.SIZE_MEDIUM or target.is_structure() else reach * 0.55)
			var far := target.radius + reach * 0.95
			c.face_point = aim
			c.strafe = 0.0
			if d < target.radius + 380.0:
				c.face_point = ship.global_position + (ship.global_position - tp).rotated(brain.orbit * 0.6) * 2.0
				c.forward = 1.0
			elif d < near:
				c.forward = -1.0
			elif d > far:
				c.forward = 1.0 if ang_err < 0.4 else 0.2
			else:
				# In the sweet spot: cancel our closing speed and slide.
				var closing := ship.velocity.dot((tp - ship.global_position).normalized())
				c.forward = -0.6 if closing > 40.0 else (0.3 if closing < -40.0 else 0.0)
				c.strafe = brain.orbit * 0.6
			# Fire only when lined up (within 0.12 rad); the focus-shot
			# special only against medium and bigger targets.
			c.fire = d < reach + target.radius and ang_err < 0.12
			c.special = c.fire and target.size_class >= Rules.SIZE_MEDIUM and ship.special_ready()
		_:
			# Dogfight: close to within 90% of our reach, then creep in at
			# 30% thrust while sliding sideways; back off when closer than
			# 60% of the "desired" distance (55% of our reach, 60% in a
			# lance), i.e. about a third of our reach.
			c.face_point = aim
			var desired := reach * (0.6 if ship.hull_id == "lance" else 0.55)
			if d > reach * 0.9:
				# Out of reach: full ahead (boost when far and lined up).
				c.forward = 1.0
				c.boost = d > reach * 1.8 and ang_err < 0.25
				c.strafe = 0.0
			elif d < desired * 0.6:
				# Too close: back off while sliding.
				c.forward = -0.5
				c.strafe = brain.orbit
			else:
				c.forward = 0.3
				c.strafe = brain.orbit * 0.8
			# The lance beam is cheap to hold (regen outpaces it), so sweep it on.
			c.fire = d < reach + target.radius and ang_err < (0.2 if ship.hull_id == "lance" else 0.16)
			# Fighters snap-turn when the target is far off the nose (more
			# than 1.2 rad) and within 600; scouts ping (reveal enemies)
			# when within 1,500.
			if ship.hull_id == "fighter" and ang_err > 1.2 and d < 600.0:
				c.special = ship.special_ready()
			if ship.hull_id == "scout":
				c.special = ship.special_ready() and d < 1500.0
			# The lance uses Overload (+60% beam damage for 2.5 s) while its
			# beam is on a target.
			if ship.hull_id == "lance":
				c.special = c.fire and ship.special_ready()
	# No shots into the rock between us and a hidden target (and no focus
	# shot or Overload spent on it).
	if hidden:
		c.fire = false
		if ship.hull_id == "bomber" or ship.hull_id == "lance":
			c.special = false
	# Step 4: don't fly into rocks while dogfighting (PilotFlight).
	brain.flight.avoid_rocks(ship)
