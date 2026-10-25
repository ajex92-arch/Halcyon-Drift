class_name DamageInfo
extends RefCounted
## WHAT THIS IS: a small "note" that describes one hit: how much damage,
## what kind of weapon, who fired it and where it came from.
##
## HOW IT WORKS: whoever causes a hit fills in a DamageInfo and hands it to
## Combat.apply_damage(). `amount` is the raw damage BEFORE the damage table
## (Rules.damage_mult; not applied at all while the damage modifiers are
## removed), the shield zones and the resistances; Combat works those out.
## The note then travels on: Unit.take_hit() reads `from_pos` to
## pick the shield zone that was hit, Unit.log_damage() reads the source
## fields to remember the attacker, and on a kill the same note goes to
## Economy and to the victim's on_killed().
##
## Careful: `source` (the attacking unit itself) is only safe to use during
## the call. Units can be destroyed and freed later, so anything that keeps
## the note around should use `source_uid` / `source_profile` instead.
##
## WHO USES IT: Projectiles builds one per round that hits; Combat builds
## them for beams (from_unit) and blast areas; Ship builds one for asteroid
## crashes (Rules.W_COLLISION). Combat, Unit, Economy and the on_killed()
## functions read them.

## The raw damage of the hit, before the damage table, zones and resistances.
var amount := 0.0
## The weapon kind: one of Rules.W_* (bolt, lance, torpedo, flak, point
## defense, shell, ion, collision, pure). It picks the damage-table row (not
## while the damage modifiers are removed) and gates some behaviour (flak
## bursts, shooting torpedoes down) and the stats tally.
var kind := Rules.W_BOLT
## The attacking unit, or null (an asteroid crash has no attacker). Only
## valid during the call (see the top of this file).
var source: Unit = null
## The attacker's uid (its id number), or -1 for no attacker.
var source_uid := -1
## The attacker's team (0, 1 or Rules.NEUTRAL).
var source_team := Rules.NEUTRAL
## The attacker's size class (Rules.SIZE_*). Motherships take more or less
## damage depending on how big the attacker is (not while the damage
## modifiers are removed). Probes and the AI read it too.
var source_size := Rules.SIZE_SMALL
## True when a minion fired it (minion hits are scaled up or down against
## some targets, unless the damage modifiers are removed; a feature hook may
## also rescale a minion's hit).
var source_is_minion := false
## True when a pilot ship (human or AI pilot) dealt the hit.
var source_is_pilot := false
## The PilotProfile of that pilot, if any (for bounties and assists).
var source_profile: RefCounted = null
## Where the hit came from (world position). The shield zone facing this
## point takes the hit.
var from_pos := Vector2.ZERO
## An extra multiplier used only against SMALL targets (e.g. the fighter's
## twin autocannon has 1.25). 1.0 = none. CombatScaling applies it only while
## the damage modifiers are kept.
var small_bonus := 1.0


## Build a DamageInfo for a hit by unit `src` (which may be null, e.g. for
## the environment): `amount_value` raw damage of weapon kind `kind_value`,
## coming from point `from`. Copies the attacker's id, team and size, and
## its pilot profile if it is a pilot ship.
static func from_unit(src: Unit, amount_value: float, kind_value: int, from: Vector2) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount_value
	d.kind = kind_value
	d.from_pos = from
	# Copy who fired, if the attacker still exists.
	if src != null and is_instance_valid(src):
		d.source = src
		d.source_uid = src.uid
		d.source_team = src.team
		d.source_size = src.size_class
		d.source_is_minion = src.kind == Unit.K_MINION
		d.source_is_pilot = src.kind == Unit.K_SHIP
		if d.source_is_pilot:
			d.source_profile = (src as Ship).profile
	return d
