class_name SkillJitter
extends RefCounted
## WHAT THIS IS: the --skill-jitter test option. It gives every AI pilot
## seat a random nudge to its skill, so the fun tests can tell "this pilot
## is good" apart from "this pilot sits in seat 6" (each seat also has its
## own lane, role and favourite hulls, see PilotAI).
##
## HOW IT WORKS: without --skill-jitter nothing here runs and every seat
## keeps its normal skill. With it, PilotAI asks jittered() for each AI
## pilot. Seat number `slot` gets its OWN random number generator, started
## ("seeded") from the --seed number and the seat number. It never touches
## the game's one shared random sequence (randf(), randi()), so every
## other random roll in the match stays exactly where it was. The
## generator draws one number between -spread and +spread (SPREAD, 0.20,
## or the number given as --skill-jitter=0.3), which is added to the seat's
## skill, and the result is kept between MIN_SKILL (0.30) and MAX_SKILL
## (0.98). The same seat number gets the same nudge on both teams, so
## neither side is favoured. The same --seed always gives the same nudges.
## (Skill is a 0..1 number: better pilots think more often, aim straighter
## and use energy routing and shield focus.)
##
## WHO USES IT: PilotAI._init() calls jittered() when
## Game.opt("skill-jitter") is set. This is a "static library": plain
## functions with no memory of their own.

## The largest nudge, up or down, when --skill-jitter is given without a
## number (0.2 = up to 0.20 of skill either way).
const SPREAD := 0.2
## The lowest skill a nudged seat can end up with.
const MIN_SKILL := 0.3
## The highest skill a nudged seat can end up with.
const MAX_SKILL := 0.98


## Seat `slot`'s skill with its nudge: `base` (the seat's normal skill,
## PilotAI step 2) plus offset(slot), kept between MIN_SKILL and MAX_SKILL.
static func jittered(base: float, slot: int) -> float:
	return clampf(base + offset(slot), MIN_SKILL, MAX_SKILL)


## The random nudge for seat `slot`: a number between -spread and +spread
## from the seat's own random number generator, seeded from --seed (0 when
## it is not given) and the seat number. The same on both teams.
static func offset(slot: int) -> float:
	# Step 1: the spread: SPREAD, or the number given as --skill-jitter=N.
	var spread := SPREAD
	var given = Game.opt("skill-jitter", true)
	if given is String and (given as String).is_valid_float():
		spread = float(given)
	# Step 2: the seat's own generator, so the shared random sequence is
	# never used. hash() turns the text into a whole number for the seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("skill-jitter:%d:%d" % [int(Game.opt("seed", 0)), slot])
	return rng.randf_range(-spread, spread)
