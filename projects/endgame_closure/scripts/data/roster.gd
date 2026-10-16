class_name Roster
extends RefCounted
## WHAT THIS IS: the pilots' callsigns (the short nicknames the game uses
## for its pilots in messages and on screen). Callsigns for pilots. Index 0
## of Halcyon is the human when flying.
##
## HOW IT WORKS: each team has a list of 13 names. A pilot's "slot" is its
## seat number on the team (0, 1, 2, ...), and callsign() gives the name at
## that place in the list (starting again from the top if the slot number
## is past the end). Each team has 12 pilots (Rules.PILOTS_PER_TEAM), so
## every pilot gets a different name and the last name in each list is not
## used.
##
## WHO USES IT: WorldSetup, when it makes the pilots at the start of a
## match.

## Halcyon's callsigns, by slot ("Lancer" is slot 0).
const HALCYON := ["Lancer", "Wren", "Kestrel", "Marlin", "Sable", "Cobalt", "Juno", "Rook", "Vega", "Tamsin", "Orrin", "Pike", "Ardent"]
## Cinder's callsigns, by slot.
const CINDER := ["Ash", "Brand", "Coil", "Drake", "Ember", "Flint", "Grist", "Hex", "Ixen", "Jolt", "Kiln", "Lark", "Morrow"]


## The callsign for the pilot in seat `slot` of team `team`. Any team other
## than Halcyon uses the Cinder list.
static func callsign(team: int, slot: int) -> String:
	var names: Array = HALCYON if team == Rules.HALCYON else CINDER
	return names[slot % names.size()]
