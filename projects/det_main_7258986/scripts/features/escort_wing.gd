class_name EscortWingFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "escort_wing" rule variant. It
## decides what the Escort Wing research (Tech.TECHS "escortWing") does to
## the free minion waves. It is the first feature module, and a small
## worked example for forks (FeatureRegistry explains how features work).
##
## HOW IT WORKS: the variant has two values (Rules.VARIANT_DEFAULTS):
##   "extra"    (the default, today's game) Escort Wing adds one more Patrol
##              Leader (minion type "corvette") per lane to every free wave,
##              so every lane's wave has one more minion. This module is not
##              installed at all for it: MinionDirector does that on its own.
##   "upgrade"  the version that keeps every lane's wave as it is: once
##              Escort Wing is researched, the first Patrol Leader of each
##              lane's wave launches with +40% hull (HULL_BONUS) and +15%
##              weapon range (RANGE_BONUS). (The middle lane's wave has two
##              Patrol Leaders; only its first one is upgraded.)
## install() switches MinionDirector to the upgrade (escort_upgrade) and
## gives the research card a matching description. From then on
## MinionDirector marks the first corvette of every lane's free wave queued
## while the team has Escort Wing, and calls upgrade() on it as it launches.
## Every upgrade is counted in Game.usage as "escort_wing_upgrades".
##
## WHO USES IT: FeatureRegistry installs it for --variant=escort_wing:upgrade.
## MinionDirector calls upgrade(). The admiral board shows BLURB through
## Tech.blurb().

## The variant key this module belongs to.
const KEY := "escort_wing"
## Hull multiplier for an upgraded Patrol Leader (1.4 = +40%).
const HULL_BONUS := 1.4
## Weapon range multiplier for an upgraded Patrol Leader (1.15 = +15%).
const RANGE_BONUS := 1.15
## What the Escort Wing research card says under "upgrade" (instead of the
## "extra" text in Tech.TECHS).
const BLURB := "The first Patrol Leader of every free minion wave launches with +40% hull and +15% weapon range."


## Switch match `world` to the "upgrade" version (see HOW IT WORKS).
## FeatureRegistry calls this once at match start when the variant is not
## "extra". Any other unknown value only gets a warning and changes
## nothing.
static func install(world: World) -> void:
	# Step 1: only "upgrade" changes anything.
	var value := Game.variant(KEY)
	if value != "upgrade":
		push_warning("escort_wing: unknown value \"%s\" (use extra or upgrade); nothing changed" % value)
		return
	# Step 2: waves keep their size; the marked corvettes get upgrade() as
	# they launch.
	world.minion_director.escort_upgrade = true
	# Step 3: the research card tells the admiral what it now does.
	Game.tunables["tech_blurb:escortWing"] = BLURB


## Upgrade Patrol Leader `m`, which has just launched with a free wave:
## +40% hull (and it starts with full hull), and +15% reach for each of its
## guns. MinionDirector calls this for the corvettes it marked. It draws no
## random numbers.
static func upgrade(m: Minion) -> void:
	# Step 1: more hull, on top of the minion's normal strength scaling.
	m.hull_max *= HULL_BONUS
	m.hull = m.hull_max
	# Step 2: longer reach. Each gun gets its own copy of its weapon data
	# (the shared table must not change) with a 15% longer round life, so
	# its rounds fly 15% farther (a beam gets 15% more range instead). The
	# gun's reach is then worked out again from that copy, so the corvette
	# also opens fire from 15% farther away.
	for mount: WeaponMount in m.mounts:
		var d: Dictionary = mount.def.duplicate()
		if d.get("beam", false):
			d["range"] = float(d["range"]) * RANGE_BONUS
		else:
			d["life"] = float(d["life"]) * RANGE_BONUS
		mount.def = d
		mount.reach = Weapons.reach(d)
	# Step 3: count it, so the reports show the mechanic was used.
	Game.count_usage("escort_wing_upgrades")
