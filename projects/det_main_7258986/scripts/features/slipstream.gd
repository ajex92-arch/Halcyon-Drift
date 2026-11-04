class_name SlipstreamFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "slipstream" rule variant
## (ideas A1 and A1b of the pacing_downtime fork): "Lane Slipstream". It
## cuts the dead time of the long flight from the mothership to the fight.
##
## HOW IT WORKS: the variant has four values (Rules.VARIANT_DEFAULTS):
##   "off"   (the default, today's game) this module is not installed.
##   "on"    A1: a pilot ship that is well behind its team's front line on
##           a lane (see WorldSlipstream for every condition) flies at twice
##           its normal top speed, but at most 1,000 world units per second.
##           Heavier hulls are still slower: a Battlecruiser slips at 300,
##           a Fighter at 1,000. REQ-CHANGE: none.
##   "flat"  A1b: every hull slips at exactly 1,100 world units per second,
##           so a 150 u/s Battlecruiser crosses its half of the map about
##           seven times faster. REQ-CHANGE: "slowly pushing across the map"
##           (heavier ships travel slower).
##   "probe" measurement only: nobody slips and nothing else changes, but the
##           arrival times of big ships are measured (see below), so the
##           normal game can be compared with "on" and "flat".
## install() makes a WorldSlipstream (it works out who slips, draws the lane
## bands and counts the usage), adds it under the World and plugs its tick()
## into World.tick_hooks. The AI needs no rule of its own: its routes
## follow the lanes, so it simply arrives sooner. Usage is counted in
## Game.usage as "slip_seconds" (and "slip_seconds_small" ... "_capital").
## For the report of A1b the part also measures the trip time of big ships
## from launch to arrival: "big_arrivals", "big_arrival_s_sum" and
## "big_arrival_s_sq" (mean = sum / n; spread = sqrt(sq / n - mean^2)).
##
## WHO USES IT: FeatureRegistry installs it for --variant=slipstream:on, :flat
## or :probe. WorldSlipstream does the work; ShipStats calls
## WorldSlipstream.apply() for a slipping ship.

## The variant key this module belongs to.
const KEY := "slipstream"


## Make the slipstream part for match `world` (see HOW IT WORKS). Any value
## other than "on", "flat" or "probe" only gets a warning and changes nothing.
func install(world: World) -> void:
	# Step 1: only "on", "flat" and "probe" mean something.
	var value := Game.variant(KEY)
	if value != "on" and value != "flat" and value != "probe":
		push_warning("slipstream: unknown value \"%s\" (use off, on, flat or probe); nothing changed" % value)
		return
	# Step 2: make the part, give it its place under the World, and let the
	# World tick it.
	var part := WorldSlipstream.new()
	part.setup(world, value == "flat", value == "probe")
	world.add_child(part)
	world.tick_hooks.append(part.tick)
