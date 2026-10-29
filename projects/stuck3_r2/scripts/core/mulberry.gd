class_name Mulberry
extends RefCounted
## WHAT THIS IS: a small random number maker that always gives the same
## numbers in the same order when it starts from the same number (the
## "seed"). Map generation uses it so the same seed always lays out the
## same theater on every machine.
##
## HOW IT WORKS: this kind of maker is called a "PRNG" (pseudo-random
## number generator): the numbers look random, but each one is worked out
## from the last by a fixed recipe. This recipe is called "mulberry32". It
## keeps one 32-bit whole number (its "state", `a`). Each next() adds a
## fixed amount to the state and scrambles a copy of it with bit shifts
## (>>), XOR (^, "flip the bits that differ") and multiplying, then turns
## the result into a number from 0 up to (not including) 1.
## "& 0xFFFFFFFF" keeps only the lowest 32 bits of a number, like a car's
## mileage counter rolling over: GDScript's whole numbers have 64 bits, but
## the recipe is written for 32.
##
## Each user has its own Mulberry, so they never disturb each other or the
## game's main random numbers (Godot's randf()/randi()).
##
## WHO USES IT: MapBuilder (seed MapLayout.SEED: the whole map),
## AsteroidField (seed MapLayout.SEED + 77: rock shapes and shades) and
## MapDecor (seed 99: the stars).

## The state: a whole number from 0 to 4,294,967,295 (32 bits).
var a: int


## Start from `seed_value` (only its lowest 32 bits are kept).
func _init(seed_value: int) -> void:
	a = seed_value & 0xFFFFFFFF


## The next number in the sequence: from 0 up to (not including) 1.
func next() -> float:
	# Move the state on by a fixed odd amount (0x6D2B79F5 is written in
	# "hex", base 16).
	a = (a + 0x6D2B79F5) & 0xFFFFFFFF
	# Scramble it.
	var t: int = imul(a ^ (a >> 15), 1 | a)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
	# Divide by 2 to the power 32 to land between 0 and 1.
	return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


## A number from `lo` up to (not including) `hi`. Uses one next().
func range_f(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next()


## Low 32 bits of a 32x32 multiply.
## (x times y, keeping only the lowest 32 bits. It multiplies by x's low
## 16 bits and high 16 bits separately, so the 64-bit maths can never
## overflow.)
static func imul(x: int, y: int) -> int:
	x &= 0xFFFFFFFF
	y &= 0xFFFFFFFF
	var lo: int = (x & 0xFFFF) * y
	var hi: int = ((x >> 16) * y) & 0xFFFF
	return (lo + (hi << 16)) & 0xFFFFFFFF
