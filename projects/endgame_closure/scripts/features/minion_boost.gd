class_name MinionBoost
extends RefCounted
## WHAT THIS IS: small tools that turn a freshly launched escort corvette
## into a tougher copy of itself. BreachFeature (the breach corvette) and
## BreachExtraFeature (the super minion) share them.
##
## HOW IT WORKS: Minions.TYPES is a fixed table, so instead of adding a new
## type to it, each tool changes ONE minion after it was made: its data row
## is copied (the copy goes into Minion.mdef), its hull and shield are set
## again from the copy (times the minion's own strength multiplier
## stat_scale, as Minion.setup() does) and its gun's reach is made longer.
## The minion keeps its type ("corvette"), so it flies and fights like the
## normal escort and is drawn the same way; a meta tag marks the copies.
## None of the tools draws a random number.
##
## WHO USES IT: BreachFeature and BreachExtraFeature call tough_copy(),
## longer_cannon() and add_siege_shell().

## The siege shell of the full-damage breach corvette (the weapon data a
## gun of this corvette uses): a heavy shell, one shot every 2 s, 70
## damage, 1,700 world units of reach (speed 1,000 x life 1.7).
const SIEGE_SHELL := {"label": "Siege shell", "kind": "shell", "rate": 0.5, "dmg": 70.0, "speed": 1000.0, "life": 1.7,
	"spread": 0.01, "radius": 6.0, "pellets": 1, "energy": 0.0, "turn": 1.2}


## Give corvette `m` its own copy of its data row with hull `hull`, shield
## `shield` and the name `label`, and set its hull and shield from it: full
## strength, times its stat_scale. Tags it with meta `tag` (true).
static func tough_copy(m: Minion, hull: float, shield: float, label: String, tag: String) -> void:
	# Step 1: the copy of the data row (Economy reads its bounty).
	var def: Dictionary = m.mdef.duplicate()
	def["label"] = label
	def["hull"] = hull
	def["shield"] = shield
	m.mdef = def
	m.display_name = label
	# Step 2: hull and shield from the copy, as Minion.setup() does: the
	# shield refills by a tenth of its base size per second.
	m.hull_max = hull * m.stat_scale
	m.hull = m.hull_max
	m.shields.setup(shield * m.stat_scale, shield * 0.1, 4.0, true)
	m.set_meta(tag, true)


## Make the escort cannon of `m` reach `bonus` times as far (1.2 = +20%): its
## own copy of the weapon data gets a longer round life, and the gun's reach
## is worked out again. The point defence gun is not touched.
static func longer_cannon(m: Minion, bonus: float) -> void:
	for mount: WeaponMount in m.mounts:
		if mount.weapon_id != "m_cannon":
			continue
		var d: Dictionary = mount.def.duplicate()
		d["life"] = float(d["life"]) * bonus
		mount.def = d
		mount.reach = Weapons.reach(d)


## Add the SIEGE_SHELL gun to `m` as its FIRST gun (the first gun sets how
## far the minion fights from its target, and the speed it aims with), a
## turret-type mount like the escort cannon's.
static func add_siege_shell(m: Minion) -> void:
	var mount := WeaponMount.new(m, "m_cannon", "turret", Vector2(m.radius, 0), 150.0)
	mount.weapon_id = "siege_shell"
	mount.def = SIEGE_SHELL
	mount.kind = Weapons.kind_id(SIEGE_SHELL)
	mount.reach = Weapons.reach(SIEGE_SHELL)
	m.mounts.push_front(mount)
	m._round_speed = float(SIEGE_SHELL["speed"])
