class_name Camp4Feature
extends RefCounted
## WHAT THIS IS: the feature module for the "camp4" rule variant (fork
## teamfights_jungle, idea D7): a fourth derelict camp in every quarter of
## the jungle. DESIGN flag: it changes how the MAP is generated (the rocks,
## the jungle paths and the route graph), so it is built with extra care.
##
## HOW IT WORKS: the map change itself is not here. MapBuilderJungle.run()
## adds MapLayout.CAMPS_EXTRA to the camp list ONLY while this variant is on
## (it reads Game.variant("camp4"): any value but "" and "off"; the
## documented value is "on"): the new camps "tl_d", "bl_d" (and
## their mirror copies "tr_d", "br_d") are carriers, the existing medium camp
## type, with its reward (200) and respawn (120 s). With the variant off,
## MapBuilderJungle uses MapLayout.CAMPS itself, so the map, the random
## numbers and the rocks are exactly today's (the match prints the rock and
## camp counts in its "match:" line, and tests/det_hash.gd the state hash).
## This module only counts: AI junglers clear the new camps like any other
## camp (they are in the jungle director's list and the route graph, so
## PilotGoals.think_jungle finds and reaches them), and every kill is
## counted. It draws no random numbers.
## Usage counts: "camp4_camps" (extra camps in the match) and "camp4_kills".
##
## WHO USES IT: FeatureRegistry installs it for --variant=camp4:on.

## The variant key this module belongs to.
const KEY := "camp4"


## Count the extra camps of this match and listen for their kills.
func install(w: World) -> void:
	var n := 0
	for c: Dictionary in w.map.camps:
		if str(c["id"]).ends_with("_d"):
			n += 1
	Game.count_usage("camp4_camps", n)
	Events.unit_killed.connect(_on_unit_killed)


## Events.unit_killed: count a kill of one of the extra camps.
func _on_unit_killed(unit: Node, _info: RefCounted) -> void:
	if unit is Derelict and (unit as Derelict).camp_id.ends_with("_d"):
		Game.count_usage("camp4_kills")
