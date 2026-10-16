extends RefCounted
## WHAT THIS IS: the "advantage index", a measuring stick for the fun probe:
## one number that says which team is ahead right now, and by how much. It
## feeds the suspense and comeback numbers (docs/FUN_RESEARCH.md, fun model
## ingredient 3).
##
## MEASUREMENT ONLY: no game script may ever load this file. If a game
## mechanic reacted to the same number that we score, it would "earn" lead
## changes by construction (Goodhart's law: a measure that becomes a target
## stops measuring). So it lives in tests/lib/ and has no class_name on
## purpose: a class_name would make it visible to every script in the game.
## Mechanics that need a "who is behind?" rule must define their own, from
## numbers the players can see on the scoreboard.
##
## HOW IT WORKS: for each team we count four things:
##   TA  its turrets still alive
##   K5  enemy pilot ships its pilots destroyed in the last 300 s (the
##       caller keeps the kill times and passes the count in)
##   FV  its "fleet value": the summed Ship.bounty_value() (hull + module
##       prices, in credits) of its pilot ships flying right now
##   MS  its mothership's hull left, as a 0..1 fraction (0 once destroyed)
## and combine them, always as Halcyon minus Cinder:
##   A = (TA_H - TA_C)/3 + (K5_H - K5_C)/6 + (FV_H - FV_C)/4000
##       + 6 x (MS_H - MS_C)
## So 3 turrets, 6 recent kills, 4,000 credits of ships, or a sixth of a
## mothership's hull are each worth 1 point. The lead L is +1 (Halcyon is
## ahead) when A >= 1, -1 (Cinder is ahead) when A <= -1, and 0 (even)
## otherwise. The weights and the threshold were fixed before any results
## ("pre-registered") and must not be tuned to make the numbers look good.
## The one pre-registered alternative, "alt": drop FV and double K5:
##   A_alt = (TA_H - TA_C)/3 + (K5_H - K5_C)/3 + 6 x (MS_H - MS_C)
## Rule (FUN_RESEARCH.md): after baseline v2, if sign(A) predicts the
## winner at 20:00 with an AUC below 0.65 (tools/fun_score.py prints it),
## switch once to alt and freeze it. The probe prints both, so no re-run is
## needed. This is a "static library": plain functions, no memory.
##
## WHO USES IT: tests/lib/fun_probe_lead.gd preloads it and samples it
## every 30 s of a tests/fun_probe.gd run.

## How many alive turrets make 1 point of advantage.
const TA_PER_POINT := 3.0
## How many recent pilot kills make 1 point (the main index).
const K5_PER_POINT := 6.0
## How many recent pilot kills make 1 point in the "alt" index (K5 doubled).
const K5_PER_POINT_ALT := 3.0
## How many credits of flying ships make 1 point (the main index only).
const FV_PER_POINT := 4000.0
## Points for a whole mothership's hull (so 1/6 of a hull = 1 point).
const MS_WEIGHT := 6.0
## |A| at or above this (points) means one team is clearly ahead.
const LEAD_AT := 1.0
## "Recent" kills for K5: the last this many seconds.
const K5_WINDOW := 300.0


## Team `team`'s four counts right now, as {"ta": turrets alive, "k5":
## `k5` (recent kills, passed in), "fv": fleet value in credits, "ms":
## mothership hull fraction 0..1}.
static func team_parts(world: World, team: int, k5: int) -> Dictionary:
	# Step 1: turrets still alive (built or still being built).
	var ta := 0
	for tu: Turret in world.turrets:
		if tu.alive and tu.team == team:
			ta += 1
	# Step 2: what the team's flying pilot ships are worth.
	var fv := 0.0
	for s: Ship in world.ships:
		if s.alive and s.team == team:
			fv += s.bounty_value()
	# Step 3: the mothership's hull left (0 once destroyed).
	var ms := world.mothership(team)
	var frac := ms.hull_frac() if ms != null and ms.alive else 0.0
	return {"ta": ta, "k5": k5, "fv": fv, "ms": frac}


## The advantage index A from Halcyon's counts `h` and Cinder's counts `c`
## (both from team_parts()). Positive = Halcyon ahead. `alt` = the
## pre-registered alternative (no fleet value, recent kills doubled).
static func value(h: Dictionary, c: Dictionary, alt: bool = false) -> float:
	var a := float(int(h["ta"]) - int(c["ta"])) / TA_PER_POINT
	a += float(int(h["k5"]) - int(c["k5"])) / (K5_PER_POINT_ALT if alt else K5_PER_POINT)
	if not alt:
		a += (float(h["fv"]) - float(c["fv"])) / FV_PER_POINT
	a += MS_WEIGHT * (float(h["ms"]) - float(c["ms"]))
	return a


## The lead L for an index value `a`: +1 (Halcyon clearly ahead), -1
## (Cinder clearly ahead) or 0 (too close to call).
static func lead(a: float) -> int:
	if a >= LEAD_AT:
		return 1
	if a <= -LEAD_AT:
		return -1
	return 0
