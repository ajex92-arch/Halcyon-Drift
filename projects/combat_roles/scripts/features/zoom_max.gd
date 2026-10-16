class_name ZoomMaxFeature
extends Node
## WHAT THIS IS: the feature module for the "zoom_max" rule variant (idea E6
## of the combat_roles fork). REQ-CHANGE: the requirements lock a pilot's
## maximum zoom close to their ship and make it grow with the ship's size.
## With this variant the human pilot's camera may zoom OUT further: "wide"
## shows 1.5 times as much of the map as the ordinary limit for the ship's
## size, "xwide" shows 2 times as much. It changes only what the human sees.
##
## HOW IT WORKS: the camera (CameraRig.zoom_limits) shows PILOT_VIEW_WIDTH
## world units across at its widest, by ship size (5,200 for a small ship up
## to 10,000 for a capital ship). It now multiplies that width by factor(),
## which is 1.0 with the variant off, 1.5 for "wide" and 2.0 for "xwide".
## Nothing else in the game reads the camera's zoom for a game rule: we
## checked. The zoom is read only to draw (ship, unit, effect and projectile
## sizes, the minimap's view box, the command overlay) and by Sfx to decide
## which sounds are loud enough to play. Fog of war and vision are worked out
## from ship positions and never from the screen, so a wider view does not
## show anything the pilot's team cannot see: what the fog hides stays dark.
## The AI never uses a camera, so a headless match cannot show any change
## and this variant is "not screenable" (judge it in a human playtest).
## As a Node the module also runs _process() once per drawn frame and counts
## the frames in which the human's camera is zoomed out beyond the ordinary
## limit, in Game.usage as "zoom_wide_frames" (0 in headless matches).
##
## WHO USES IT: FeatureRegistry installs it for --variant=zoom_max:wide or
## :xwide (it is a Node, so it also goes under the World). CameraRig calls
## factor().

## The variant key this module belongs to.
const KEY := "zoom_max"

## The match.
var world: World


## How many times wider than the ordinary limit the camera may show: 1.0
## (variant off), 1.5 ("wide") or 2.0 ("xwide"). CameraRig calls it.
static func factor() -> float:
	match Game.variant(KEY):
		"wide":
			return 1.5
		"xwide":
			return 2.0
	return 1.0


## Remember the match. FeatureRegistry calls it once at match start.
func install(w: World) -> void:
	world = w


## Every drawn frame: if the human's camera follows a ship and is zoomed out
## further than the ordinary limit for that ship's size, count the frame.
func _process(_dt: float) -> void:
	if world == null or world.camera == null or world.camera.free:
		return
	var s := world.camera.followed()
	if s == null:
		return
	var old_min := world.camera.get_viewport_rect().size.x / float(CameraRig.PILOT_VIEW_WIDTH[Rules.size_index(s.size_class)])
	if world.camera.zoom.x < old_min - 0.0001:
		Game.count_usage("zoom_wide_frames")
