class_name HudSlots
extends VBoxContainer
## WHAT THIS IS: the bottom-left corner of the HUD: a one-line reminder of
## the menu keys, and under it the pilot's 6 gear slots (what they carry:
## pilot gear and repair kits).
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_slots.tscn: a column
## 8 pixels from the bottom-left corner, growing upward, holding Keys (the
## grey key reminder, 11 px; it wraps to the width of the gear slots) and
## Gear (a grid for the slot boxes, 4 pixels apart: one row of 6, or two rows
## of 3 in a narrow window, see set_compact()). The mouse passes through it.
## How many slots there are is game
## data (Items.SLOTS = 6), so _ready() adds the boxes to Gear: one per slot,
## each made from scenes/ui/hud_gear_slot.tscn (a dark 62 x 40 pixel box,
## the "SlotLook" look, with a centred, wrapping 10 px label, Item).
## refresh_slots() writes each slot's item name, "Kit x2 (R)" for repair
## kits, or a dash for an empty slot. refresh_keys() writes the key
## reminder for the human's seat (Admiral or pilot).
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it; Hud._refresh()
## calls refresh_slots() and refresh_keys() 10 times a second and shows
## slots_box only to pilots (and to an Admiral who is flying a ship).
## HudLayout asks wide_width() and calls set_compact().

## One gear slot's box (scenes/ui/hud_gear_slot.tscn).
const SLOT_SCENE := preload("res://scenes/ui/hud_gear_slot.tscn")

## The grid of gear slot boxes (Hud hides it when it isn't useful).
@onready var slots_box: GridContainer = $Gear
## The key reminder line ("B hangar · F dock/launch · ...").
@onready var _keys: Label = $Keys
## One label per gear slot, in slot order.
var _slot_labels: Array[Label] = []
## True while the gear slots are in two rows of 3 (set_compact).
var _compact := false


## Godot calls this when the corner joins the HUD: add one box per gear
## slot to the Gear grid, and remember each box's label. The key reminder is
## made as wide as the gear row, so it wraps there.
func _ready() -> void:
	for i in Items.SLOTS:
		var box: PanelContainer = SLOT_SCENE.instantiate()
		slots_box.add_child(box)
		_slot_labels.append(box.get_node("Item") as Label)
	_keys.custom_minimum_size.x = _row_width(Items.SLOTS)


## The width (pixels) of the gear slots in one row of all of them.
func wide_width() -> float:
	return _row_width(Items.SLOTS)


## Put the gear slots in two rows of 3 (`on`), or in one row of 6, for a
## window that is too narrow (or wide enough) for the whole bottom row.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	var cols := 3 if on else Items.SLOTS
	slots_box.columns = cols
	_keys.custom_minimum_size.x = _row_width(cols)


## The width (pixels) of `cols` gear slot boxes side by side.
func _row_width(cols: int) -> float:
	var box := slots_box.get_child(0) as Control
	return float(cols) * box.get_combined_minimum_size().x + float(cols - 1) * float(slots_box.get_theme_constant("h_separation"))


## Write what is in each of pilot `h`'s gear slots (nothing to do when
## there is no human pilot profile).
func refresh_slots(h: PilotProfile) -> void:
	if h == null:
		return
	for i in Items.SLOTS:
		var s: Dictionary = h.inventory[i]
		var txt := ""
		if s.is_empty():
			txt = "—"
		elif s["id"] == Items.KIT["id"]:
			txt = "Kit x%d\n(R)" % int(s["count"])
		else:
			txt = String(Items.ITEMS[s["id"]]["label"])
		UiKit.set_text(_slot_labels[i], txt)


## Write the key reminder for seat `role` ("admiral", "pilot" or
## "spectator"; a spectator only sees help and pause).
func refresh_keys(role: String) -> void:
	var keys := "H help · P pause"
	if role == "admiral":
		keys = "Tab Admiral board · B hangar · C camera · " + keys
	elif role == "pilot":
		keys = "B hangar · F dock/launch · R repair kit · hold Tab scores · " + keys
	UiKit.set_text(_keys, keys)
