class_name HudLayout
extends RefCounted
## WHAT THIS IS: the part of the HUD that keeps its pieces out of each
## other's way, whatever the size of the window.
##
## HOW IT WORKS: every piece of the HUD is fixed to a corner or an edge of
## the window by its anchors (scenes/ui/hud.tscn), so each one is in the
## right place on its own. What anchors cannot do is notice that two pieces
## are too big for the window together. apply() looks at how big each piece
## really is and nudges the ones that would collide:
##   - the top bar is pushed to the right of the "me" panel when the window
##     is too narrow for both side by side (it stays centred otherwise);
##   - the gear slots go from one row of 6 to two rows of 3 when the window
##     is too narrow for the gear slots, the ship readout and the minimap in
##     one row, and the ship readout is kept between the gear slots and the
##     minimap;
##   - while a big panel (hangar, Admiral board, help, scoreboard) is open,
##     the pieces it would cover are hidden instead of peeking out from under
##     it: the kill feed, the big message, the minimap and the earnings log.
##     The top bar and the "me" panel stay, and panel_top() and
##     panel_bottom() say where the panels may sit: under them (the
##     scoreboard, which is narrow, only under the top bar when it is clear
##     of the "me" panel). The hangar, the Admiral board and the help stop
##     above the bottom strip of the HUD instead of covering it: above the
##     ship readout while the pilot is flying, so hull, shields and energy
##     stay in sight, otherwise above the key line and the gear slots. The
##     scoreboard reaches down to the bottom edge, so while Tab holds it open
##     the gear slots and the ship readout are hidden too (and the hint
##     waits);
##   - toast_spot() says where the pop-up hint sits, and toast_width() and
##     banner_width() how wide the hint and the big message may be, so they
##     do not run into the ship readout, the gear slots, the minimap, the
##     kill feed, the "me" panel or the text of an open panel.
## The kill feed sits under the top bar (hud_feed.tscn), so those two never
## meet. apply() runs 10 times a second (Hud._refresh), when the window is
## resized and when a panel opens. It writes a value only when it changed.
##
## WHO USES IT: Hud makes one (hud.layout) in setup() and calls apply().
## HudPanels asks panel_top() and panel_bottom() to place the big panels;
## HudToast asks toast_spot() and toast_width(), HudBanner banner_width().
## It reads the HUD's pieces (hud.top_bar, me_panel, feed, banner, status,
## minimap, slots).

## The space (pixels) kept between two pieces, and between a piece and the
## edge of the window.
const GAP := 8.0
## The height (pixels) the hangar, the Admiral board and the help leave free
## at the bottom while the ship readout shows: the readout's height, its 8
## pixel gap to the window's edge and 8 pixels of air above it.
const READOUT_ROOM := ShipStatus.H + 16.0
## The least height (pixels) they leave free without the readout: the gear
## slots (40 pixels high, 8 above the edge), the key line over them (one line,
## about 15 pixels, 4 above the slots) and a little air. A longer key line
## (it wraps to two lines or more) asks for more: panel_bottom() measures the
## real HudSlots height and takes the larger.
const KEYBAR_ROOM := 76.0
## How far (pixels) the pop-up hint sits above the bottom edge while a big
## panel is open: in the strip under the panel, beside the gear slots or the
## ship readout (toast_spot()).
const TOAST_LIFT := 6.0
## How far (pixels) the pop-up hint sits above the bottom edge in flight: it
## stays clear of the ship readout.
const TOAST_LIFT_FLIGHT := 150.0
## The narrowest (pixels) a pop-up hint or big message is made, however
## little room there is; a narrower message would be a tall thin column.
const MIN_TEXT_W := 260.0

## The HUD this part belongs to.
var hud: Hud


## Remember which HUD we belong to.
func _init(owner: Hud) -> void:
	hud = owner


## Re-place everything that depends on the window size or on how big the
## other pieces are (see HOW IT WORKS).
func apply() -> void:
	var vp := hud.get_viewport_rect().size
	var panel := hud._any_panel_open()
	# Step 1: the pieces a big panel would cover step aside. The hangar, the
	# board and the help stop above the gear slots and the ship readout
	# (panel_bottom), so those two are hidden only under the scoreboard,
	# which reaches the bottom edge. (The ship readout is also hidden by the
	# HUD itself when there is no ship, so we only ever hide it here.)
	var table := hud.scoreboard != null and hud.scoreboard.visible
	hud.feed.visible = not panel
	hud.banner.visible = not panel
	hud.minimap.visible = not panel
	hud.slots.visible = not table
	hud.me_panel.earn_box.visible = not panel
	if table:
		hud.status.visible = false
	# Step 2: the top bar clears the "me" panel.
	_place_top_bar(vp)
	# Step 3: the bottom row: gear slots, ship readout, minimap.
	_place_bottom_row(vp)
	# Step 4: the big panels sit under the top bar and "me" panel.
	hud.panels.relayout()


## The y position (pixels from the top) where a big panel whose left edge is
## at x = `left` starts: GAP under the top bar, and also under the "me" panel
## if the panel reaches over it. The "me" panel is measured without its
## earnings log, which is hidden while a panel is open.
func panel_top(left: float) -> float:
	var top := hud.top_bar.offset_top + hud.top_bar.get_combined_minimum_size().y
	if left < hud.me_panel.offset_left + hud.me_panel.get_combined_minimum_size().x + GAP:
		top = maxf(top, hud.me_panel.offset_top + hud.me_panel.base_height())
	return top + GAP


## The height (pixels) the big panels leave free at the bottom of the window.
## The hangar, the Admiral board and the help (`strip` true) stop above the
## bottom strip of the HUD: READOUT_ROOM while the ship readout shows (our
## ship is alive; asked of the readout's ship, not of its visibility, which
## the scoreboard takes away), otherwise the key line and gear slots: their
## real height (HudSlots, which grows when the key line wraps to more lines)
## plus the 8 pixel gap to the window's edge and 8 pixels of air, but at
## least KEYBAR_ROOM. The scoreboard (`strip` false) leaves only GAP: the
## pieces under it are hidden.
func panel_bottom(strip: bool) -> float:
	if not strip:
		return GAP
	if is_instance_valid(hud.status.ship):
		return READOUT_ROOM
	return maxf(KEYBAR_ROOM, hud.slots.get_combined_minimum_size().y + 2.0 * GAP)


## Where the pop-up hint's box sits: x is how far (pixels) its centre is to
## the right of the window's middle, y how far its bottom edge is above the
## window's bottom. With no big panel open it is centred, TOAST_LIFT_FLIGHT
## up, clear of the ship readout. While a big panel is open it drops into the
## strip under the panel, TOAST_LIFT up: centred when the ship readout is not
## showing; with the readout showing (the panel stops above it, see
## panel_bottom()), in the bottom-right corner between the readout and the
## window's edge, where the minimap is when no panel is open.
func toast_spot(panel_open: bool) -> Vector2:
	if not panel_open:
		return Vector2(0.0, TOAST_LIFT_FLIGHT)
	if not hud.status.visible:
		return Vector2(0.0, TOAST_LIFT)
	# The corner runs from GAP right of the readout to GAP in from the edge,
	# so its middle is half the readout's right edge right of the window's.
	return Vector2(_readout_right(hud.get_viewport_rect().size) * 0.5, TOAST_LIFT)


## The widest (pixels) the pop-up hint's box may be. In flight it sits in the
## middle of the bottom edge, so it must stay clear of the minimap at the
## right (and is kept centred, so the same room is left on the left). While
## a big panel is open the minimap is hidden and the hint sits under the
## panel (toast_spot()): beside the ship readout, in the room between it and
## the right edge; with no readout, centred and clear of the gear slots and
## key line at the left.
func toast_width(panel_open: bool) -> float:
	var vp := hud.get_viewport_rect().size
	if panel_open:
		if hud.status.visible:
			return maxf(MIN_TEXT_W, vp.x - _readout_right(vp) - 2.0 * GAP)
		if not hud.slots.visible:
			return maxf(MIN_TEXT_W, vp.x - 2.0 * GAP)
		var slots_right := hud.slots.offset_left + hud.slots.get_combined_minimum_size().x
		return maxf(MIN_TEXT_W, vp.x - 2.0 * (slots_right + GAP))
	var map_w := hud.minimap.get_combined_minimum_size().x
	var half := minf(vp.x * 0.5 - GAP, vp.x * 0.5 - map_w - 2.0 * GAP)
	return maxf(MIN_TEXT_W, 2.0 * half)


## The x position (pixels from the left) of the ship readout's right edge.
## It is anchored to the middle of the bottom edge and shifted sideways by
## its offset (_place_bottom_row()), and it grows to both sides.
func _readout_right(vp: Vector2) -> float:
	return vp.x * 0.5 + hud.status.offset_left + hud.status.get_combined_minimum_size().x * 0.5


## The widest (pixels) the big centre message may be: the window less the
## kill feed's width and gaps on both sides, since the message is centred
## and the feed is at the right.
func banner_width() -> float:
	var vp := hud.get_viewport_rect().size
	var feed_w := hud.feed.get_combined_minimum_size().x + 2.0 * GAP
	return maxf(MIN_TEXT_W, vp.x - 2.0 * feed_w)


## Keep the top bar centred, but not over the "me" panel at its left and not
## past the right edge. It is anchored to the middle of the top edge, so a
## sideways shift is the same number added to its left and right offsets.
func _place_top_bar(vp: Vector2) -> void:
	var w := hud.top_bar.get_combined_minimum_size().x
	var low := hud.me_panel.offset_left + hud.me_panel.get_combined_minimum_size().x + GAP
	var high := vp.x - GAP - w
	_shift_centered(hud.top_bar, vp, w, clampf(vp.x * 0.5 - w * 0.5, low, maxf(low, high)))


## Place the gear slots, the ship readout and the minimap along the bottom.
## The minimap and the gear slots stay in their corners. The ship readout is
## centred, then kept between them. If the three do not fit in one row, the
## gear slots shrink to two rows of three first.
func _place_bottom_row(vp: Vector2) -> void:
	var status_w := hud.status.get_combined_minimum_size().x
	var map_w := hud.minimap.get_combined_minimum_size().x
	var need := GAP + hud.slots.wide_width() + GAP + status_w + GAP + map_w + GAP
	hud.slots.set_compact(vp.x < need)
	var low := hud.slots.offset_left + hud.slots.get_combined_minimum_size().x + GAP
	var high := vp.x - map_w - 2.0 * GAP - status_w
	_shift_centered(hud.status, vp, status_w, clampf(vp.x * 0.5 - status_w * 0.5, low, maxf(low, high)))


## Move control `c`, which is anchored to the middle of an edge and `w`
## pixels wide, so its left edge is at `left` pixels. Does nothing if it is
## there already.
func _shift_centered(c: Control, vp: Vector2, w: float, left: float) -> void:
	var dx := left + w * 0.5 - vp.x * 0.5
	if absf(c.offset_left - dx) > 0.5 or absf(c.offset_right - dx) > 0.5:
		c.offset_left = dx
		c.offset_right = dx
