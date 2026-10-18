class_name MinionCapFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "minion_cap" rule variant (idea
## E1 of the combat_roles fork): minions stop out-scaling pilots. Late in a
## match the lane minions are much tougher than they were (+7% hull and
## damage for every full 5 minutes, plus the Reinforced Waves research), and
## because their shots now land, they became the top killer of pilots after
## 30:00. With this variant a minion's shot at a PILOT SHIP counts as if the
## minion had at most +15% strength, and the Reinforced Waves bonus does not
## count for that shot at all.
##
## HOW IT WORKS: Combat already lets a feature re-scale a minion's hit
## against one target (Combat.minion_scale_hook). install() plugs in
## _scale(). For a hit on a pilot ship it works out the minion's strength
## without the research bonus (the strength it carries, Minion.stat_scale,
## divided by 1 + the team's minion_buff) and caps that at CAP (1.15). The
## answer is never higher than the strength the minion really has, so the
## variant can only lower damage. Hits on anything else (minions, turrets,
## repair bays, the mothership) keep their full strength, and so do the
## minions' hull and shields. MINION_VS_SHIP_MULT (x0.6) and the turret
## numbers are not touched. The AI needs nothing new: the pilots simply
## stop dying to old minions. Every hit that this lowered is counted in
## Game.usage as "capped_minion_hits".
##
## WHO USES IT: FeatureRegistry installs it for --variant=minion_cap:on.
## Combat._rescale_minion_hit() calls _scale() for every minion hit.

## The variant key this module belongs to.
const KEY := "minion_cap"
## The strongest a minion counts as against a pilot ship (1.15 = +15%).
const CAP := 1.15

## The match (we read the teams' Reinforced Waves bonus from it).
var world: World


## Switch the cap on for match `w`: plug _scale() into Combat. FeatureRegistry
## calls this once at match start.
func install(w: World) -> void:
	world = w
	MinionHookChain.add(w, Callable(self, "_scale"), true)


## The strength a minion's hit should use against `target`. `scale` is the
## strength the minion carries (its growth with match time times its team's
## research bonus). Against a pilot ship we return the strength without the
## research bonus, capped at CAP; against everything else, `scale` itself.
func _scale(m: Minion, target: Unit, scale: float) -> float:
	# Step 1: only hits on pilot ships are capped.
	if target.kind != Unit.K_SHIP:
		return scale
	# Step 2: take the research bonus out, then cap what is left.
	var bonus := 1.0 + world.teams[m.team].minion_buff
	var capped := minf(scale / bonus, CAP)
	# Step 3: never give a minion MORE strength than it has; count the hits
	# the cap really lowered.
	if capped < scale:
		Game.count_usage("capped_minion_hits")
		return capped
	return scale
