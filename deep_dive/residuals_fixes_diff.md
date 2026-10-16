# Residuals round: code diff of the rfix switches (dd_resid_s1 -> dd_resid, scripts only)

Switches: ret<NN> (+ retsmall), flaksg, msa. All read through PilotAI.rfix()/rfix_number() from Game.opt("rfix",""); default OFF = this game.

` diff
--- a/scripts/ai/pilot_ai.gd
+++ b/scripts/ai/pilot_ai.gd
@@ -145,4 +145,36 @@
 ## Game time (seconds) until which the unit `skip_id` is ignored.
 var skip_until := 0.0
+## Residuals switch ret<NN>: this retreat began because hull + shields fell
+## low while the hull was still over 35% (it ends sooner, see _think()).
+var soft_retreat := false
+
+## Residuals-round switches (--rfix=a,b,c): "" = the game as it is. Read once.
+static var _rfix: PackedStringArray = PackedStringArray()
+static var _rfix_read := false
+
+
+## Is the residuals switch `name` on (--rfix=name)?
+static func rfix(name: String) -> bool:
+	if not _rfix_read:
+		_rfix = str(Game.opt("rfix", "")).split(",", false)
+		_rfix_read = true
+	return name in _rfix
+
+
+## Residuals switch flaksg: a Flak Frigate's flak does only x0.3 to a
+## mothership, so it stays on the defenders (minions and pilots) during a
+## siege instead of taking the mothership as its target.
+func skips_ms(ship: Ship) -> bool:
+	return ship.hull_id == "flak" and rfix("flaksg")
+
+
+## The number NN of a switch written <name><NN> (--rfix=ret25 gives 0.25 for
+## "ret"), or 0.0 when no such switch is on.
+static func rfix_number(name: String) -> float:
+	rfix("")
+	for s in _rfix:
+		if s.begins_with(name) and s.substr(name.length()).is_valid_int():
+			return float(s.substr(name.length()).to_int()) / 100.0
+	return 0.0
 
 # --- the parts (see THE PARTS at the top) ----------------------------------------------
@@ -321,9 +353,25 @@
 	# below 60% between fights (no hull damage for 2 seconds), never while
 	# one is already working.
-	if hp < 0.35 or (state == "retreat" and hp < 0.85):
+	var want_retreat := hp < 0.35 or (state == "retreat" and hp < 0.85)
+	# Residuals switch ret<NN> (RetreatTotal): the hull is what is left after
+	# the shields are gone, so at 35% hull a ship has already lost most of
+	# its health. Also turn back when hull + shields together fall below NN%
+	# (a "soft" retreat), and come back out once they are over 70% again.
+	var ret_total := rfix_number("ret")
+	if ret_total > 0.0:
+		var total := (ship.hull + ship.shield_total()) / maxf(1.0, ship.hull_max + (ship.shields.max_total if ship.shields != null else 0.0))
+		if hp < 0.35:
+			soft_retreat = false
+		elif state != "retreat" and total < ret_total and (ship.size_class < Rules.SIZE_LARGE or not rfix("retsmall")):
+			want_retreat = true
+			soft_retreat = true
+		elif state == "retreat" and soft_retreat and total >= 0.7:
+			want_retreat = false
+	if want_retreat:
 		state = "retreat"
 		if hp < 0.5 and profile.kit_count() > 0 and not ship.has_active_kit():
 			c.use_kit = true
 	elif state == "retreat":
+		soft_retreat = false
 		state = "jungle" if profile.role == "jungle" else "lane"
 	elif hp < 0.6 and profile.kit_count() > 0 and not ship.has_active_kit() and world.time - ship.last_hull_damage_time > 2.0:
--- a/scripts/ai/pilot_targeting.gd
+++ b/scripts/ai/pilot_targeting.gd
@@ -160,5 +160,5 @@
 	# ships and bombers want it much more (+100 instead of +900).
 	var ems := world.mothership(1 - ship.team)
-	if ems != null and ems.alive and ems.hull_dist(ship.global_position) < r * 0.8:
+	if ems != null and ems.alive and ems.hull_dist(ship.global_position) < r * 0.8 and not brain.skips_ms(ship):
 		var s2 := ems.hull_dist(ship.global_position) + (100.0 if ship.size_class >= Rules.SIZE_LARGE or ship.hull_id == "bomber" else 900.0)
 		if s2 < best_s:
@@ -220,5 +220,5 @@
 	# Step 2: no turret: the enemy mothership, if it is close enough.
 	var ems := world.mothership(1 - ship.team)
-	if ems != null and ems.alive and ems.hull_dist(station) < PUSH_RANGE + 1500.0:
+	if ems != null and ems.alive and ems.hull_dist(station) < PUSH_RANGE + 1500.0 and not brain.skips_ms(ship):
 		if not ship.is_small() or ship.hull_id == "bomber" or brain.senses.minions_at_hull(ems, ship.team, 2500.0) >= 3:
 			return ems
--- a/scripts/ai/pilot_goals.gd
+++ b/scripts/ai/pilot_goals.gd
@@ -117,5 +117,5 @@
 	# defenders (who respawn right there and would otherwise soak every
 	# shot).
-	if ts.siege_phase == "assault" and not ship.is_small():
+	if ts.siege_phase == "assault" and not ship.is_small() and not brain.skips_ms(ship):
 		var ems := world.mothership(1 - ship.team)
 		if ems != null and ems.alive and ems.hull_dist(ship.global_position) < PilotTargeting.main_reach(ship) * 1.05:
--- a/scripts/ai/pilot_flight.gd
+++ b/scripts/ai/pilot_flight.gd
@@ -288,4 +288,41 @@
 
 
+## Residuals switch msa: a mothership is a solid wall to a pilot ship, and
+## once it has moved up into the lane it sits right across the lane line.
+## Ships (frigates and capitals above all, they turn slowly) flew into its
+## hull and stayed pressed against it, because the route and avoid_rocks()
+## know only rocks and avoid_rocks() does nothing under 60 units a second.
+## A ship that is about to run into a mothership hull (its own or the
+## enemy's) now slides along the hull, toward the side it wants to go.
+## Not when the goal itself is near the hull (docking, defending).
+func avoid_hulls(ship: Ship) -> void:
+	var brain := ai
+	var c := ship.controls
+	var p := ship.global_position
+	var want := c.face_point - p
+	if want.length() < 1.0:
+		return
+	want = want.normalized()
+	var trig := ship.radius + 140.0 + ship.velocity.length() * clampf(1.2 / maxf(ship.f_turn, 0.3), 0.3, 3.0)
+	for t in 2:
+		var ms := brain.world.mothership(t)
+		if ms == null or not ms.alive or ms.hull_dist(p) > trig or ms.hull_dist(brain.goal) < 600.0:
+			continue
+		var a := ms.global_position + Vector2.from_angle(ms.rotation) * ms.half_len
+		var b := ms.global_position - Vector2.from_angle(ms.rotation) * ms.half_len
+		var n := (p - Util.closest_on_segment(p, a, b)).normalized()
+		if want.dot(n) >= 0.25:
+			continue
+		# Slide along the hull the way we want to go, a little outward.
+		var tang := Vector2(-n.y, n.x)
+		if tang.dot(want) < 0.0:
+			tang = -tang
+		var dir := (tang + n * 0.5).normalized()
+		c.face_point = p + dir * 400.0
+		c.forward = maxf(c.forward, 0.6)
+		c.strafe = clampf(Util.port_of(ship.rotation).dot(dir) * 1.5, -1.0, 1.0)
+		return
+
+
 ## Nudge the nose away from rocks just ahead. It runs about once a tick;
 ## the rock search itself runs on every 5th call (about 12 times a second;
@@ -296,4 +333,6 @@
 	var c := ship.controls
 	var v := ship.velocity
+	if PilotAI.rfix("msa"):
+		avoid_hulls(ship)
 	# Step 1: nearly stopped (under 60 units a second): nothing to dodge.
 	if v.length() < 60.0:
`
