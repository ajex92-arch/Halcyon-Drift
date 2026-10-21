class_name BountyRing
extends Node2D
## WHAT THIS IS: the gold rings the comeback bounties draw around the enemy
## turrets and repair bays that currently pay extra (see ComebackDirector).
## It only draws; it changes nothing in the game. No ring node is made when
## the game runs with no window.
##
## HOW IT WORKS: four times a second it asks the director which structures
## pay a comeback bounty to each team (ComebackDirector.bounty_structures)
## and redraws a gold ring around each one. Both teams see the rings of
## their own side's chances and of the other side's: the ring is on a
## structure of the team that is AHEAD.
##
## WHO USES IT: ComebackDirector.enable_banner() makes it.

## The director that knows which team is behind (set by the director).
var director: ComebackDirector = null
## The ring's radius around a structure, in world units.
const RING_RADIUS := 240.0
## Seconds between redraws.
const REDRAW_EVERY := 0.25
## Seconds until the next redraw.
var _t := 0.0


## Godot calls this when the rings join the match: draw them above the units.
func _ready() -> void:
	z_index = 20


## Godot calls this every frame: redraw the rings four times a second.
func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = REDRAW_EVERY
		queue_redraw()


## Draw a gold ring (two circles) around every structure that pays a
## comeback bounty.
func _draw() -> void:
	if director == null or director.world == null:
		return
	var gold := Palette.AMBER
	for team in 2:
		for s: Unit in director.bounty_structures(team):
			if not is_instance_valid(s) or not s.alive:
				continue
			# Only draw what the viewing team can see (a spectator sees all).
			var viewer := director.world.viewer_team
			if viewer >= 0 and not s.visible_to(viewer):
				continue
			draw_arc(s.global_position, RING_RADIUS, 0.0, TAU, 48, gold, 10.0, true)
			draw_arc(s.global_position, RING_RADIUS * 0.8, 0.0, TAU, 48, Palette.with_alpha(gold, 0.45), 6.0, true)
