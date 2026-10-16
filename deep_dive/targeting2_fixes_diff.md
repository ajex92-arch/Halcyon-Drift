# Targeting round 2: fix code (switches in notate\dd_targeting2, DDStat.fix names)

Recommended set: `stick`, `hp2`, `bsm` (all in scripts/ai/pilot_targeting.gd). `eff` and `focus` are not recommended; `stick500` is a stronger variant (not run). The unified diff below is the working copy against dd_targeting_fix (which already holds the round-1 switches beam, los, ovl, ion, bd, ms, aim2).

Port notes (without DDStat): 
- `stick`: at the top of pick_target `var prev: Unit = brain.target` (null it when not is_instance_valid); `var stick_on := prev != null and prev.kind == Unit.K_SHIP and prev.alive`; query radius `r * 1.3 if stick_on else r`; accept `d > r` only for `u == prev` and `d <= r * 1.3`; after the kind match `if stick_on and u == prev: s -= 250.0`.
- `hp2`: new `static func health(u)` = (hull + shield_total) / (hull_max + shields.max_total); use it instead of `hull_frac()` in the "damaged" term of pick_target (:105) and prey (:259). Leave the turret-cover thresholds on hull_frac.
- `bsm`: `var bomber_lane := ship.hull_id == "bomber" and brain.state == "lane"`; in the loop, before the kind match, `if bomber_lane and u.size_class == Rules.SIZE_SMALL and u.kind != Unit.K_TURRET and u.kind != Unit.K_BAY: continue`.
- Drop every DDStat hook from the port.

```diff
--- dd_targeting_fix/scripts/ai/pilot_targeting.gd
+++ dd_targeting2/scripts/ai/pilot_targeting.gd
@@ -79,5 +79,24 @@
 	# Are we inside an enemy turret's range ourselves (plus 150)?
 	var me_covered := brain.senses.enemy_turret_at(ship.global_position, ship.team, 150.0) != null
-	for u: Unit in world.unit_hash.query(ship.global_position, r, _scratch):
+	# DDFIX stick: the pilot we are shooting now (a new pick has to beat it by
+	# 250, and it stays a target out to 1.3 times the range, so we don't swap
+	# between two near-equal pilots every think).
+	var prev: Unit = brain.target
+	if prev != null and not is_instance_valid(prev):
+		prev = null
+	var stick_on := (DDStat.fix.has("stick") or DDStat.fix.has("stick500")) and prev != null and prev.kind == Unit.K_SHIP and prev.alive
+	var stick_m := 500.0 if DDStat.fix.has("stick500") else 250.0
+	# DDFIX focus: the pilot targets of our allies within 1,500.
+	var ally_on := {}
+	if DDStat.fix.has("focus"):
+		for a: Unit in world.unit_hash.query(ship.global_position, 1500.0, _scratch):
+			if a.kind == Unit.K_SHIP and a.team == ship.team and a != ship and a.alive and (a as Ship).controller is PilotAI:
+				var at: Unit = ((a as Ship).controller as PilotAI).target
+				if at != null and is_instance_valid(at) and at.kind == Unit.K_SHIP:
+					ally_on[at.uid] = true
+	# DDFIX eff: the damage table row of our first gun.
+	var main_m: WeaponMount = ship.mounts[0] if (DDStat.fix.has("eff") and not ship.mounts.is_empty()) else null
+	var bomber_lane := DDStat.fix.has("bsm") and ship.hull_id == "bomber" and brain.state == "lane"
+	for u: Unit in world.unit_hash.query(ship.global_position, r * 1.3 if stick_on else r, _scratch):
 		# Step 1: only live, visible enemies truly within r.
 		# Neutral units (jungle monsters) only count while jungling.
@@ -89,5 +108,9 @@
 			continue
 		var d := ship.global_position.distance_to(u.global_position)
-		if d > r:
+		if d > r and not (stick_on and u == prev and d <= r * 1.3):
+			continue
+		# DDFIX bsm: a bomber in the lane leaves small craft alone (torpedoes do
+		# x0.35 to them and miss 8 in 10): minions, drones, wards and pilots.
+		if bomber_lane and u.size_class == Rules.SIZE_SMALL and u.kind != Unit.K_TURRET and u.kind != Unit.K_BAY:
 			continue
 		# Step 2: start from the distance, then adjust by kind.
@@ -96,9 +119,14 @@
 			Unit.K_SHIP:
 				# Pilots: +200, but up to 600 less the more damaged they are.
-				s += 200.0 - (1.0 - u.hull_frac()) * 600.0
+				# DDFIX hp2: how damaged it is counts shields too (hull alone stays
+				# at 100% until the shield is gone).
+				s += 200.0 - (1.0 - (health(u) if DDStat.fix.has("hp2") else u.hull_frac())) * 600.0
 				# Much bigger hulls (2+ size classes up) are a poor match,
 				# unless our weapons are made for them.
 				if u.size_class > ship.size_class + 1 and not heavy_hitter:
 					s += 500.0
+				# DDFIX focus: a pilot an ally is already shooting is 150 better.
+				if ally_on.has(u.uid):
+					s -= 150.0
 				# Torpedoes are wasted on strike craft (x0.35 damage, easy to
 				# dodge).
@@ -139,4 +167,15 @@
 			Unit.K_MONSTER, Unit.K_SNUB:
 				s += 100.0
+		# DDFIX eff: how well our first gun hurts this kind of target (the
+		# damage table and the small-craft bonus): 400 per 1.0 of multiplier
+		# below 1.
+		if main_m != null:
+			var mu := Rules.damage_mult(main_m.kind, u.size_class)
+			if u.size_class == Rules.SIZE_SMALL:
+				mu *= float(main_m.def.get("small_bonus", 1.0))
+			s += (1.0 - mu) * 400.0
+		# DDFIX stick: the pilot we are shooting now is 250 better.
+		if stick_on and u == prev:
+			s -= stick_m
 		# Step 3: keep the lowest score so far.
 		if s < best_s:
@@ -230,5 +269,5 @@
 			continue
 		# Step 4: score: distance, minus up to 800 the more damaged it is.
-		var s := d - (1.0 - u.hull_frac()) * 800.0
+		var s := d - (1.0 - (health(u) if DDStat.fix.has("hp2") else u.hull_frac())) * 800.0
 		# Match-ups: bombers hunt big hulls; everyone else avoids frigates
 		# and capitals unless they're nearly dead (30% hull or less), since
@@ -251,4 +290,10 @@
 			best = u
 	return best
+
+
+## DDFIX hp2: hull plus shield over their maximum, 0 to 1.
+static func health(u: Unit) -> float:
+	var mx := u.hull_max + (u.shields.max_total if u.shields != null else 0.0)
+	return (u.hull + u.shield_total()) / mx if mx > 0.0 else 0.0
 
 
`
