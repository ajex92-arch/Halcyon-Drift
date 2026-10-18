class_name Hangar
extends PanelContainer
## WHAT THIS IS: the pilot's shop, the big panel that opens with B. Here a
## pilot spends their own credits (their personal money) on a hull (the
## ship itself), up to 2 modules for it, pilot gear (6 slots, one item per
## category) and repair kits, and then launches into space (F).
## DESIGN.md A6, A15.
##
## HOW IT WORKS: the frame that never changes is the scene
## scenes/ui/hangar.tscn: a box (the "HangarLook" look) holding one column,
## Col, with these rows from top to bottom:
##   Head (Texts (Title, Status), Launch, Close): the title with the
##     credits and the status line under it, then the big amber Launch
##     button (210 x 44 pixels) and Close (44 pixels tall);
##   BayRow: the hyperspace launch row, empty until HangarLaunch fills it;
##   Tabs (Ships, Modules, Gear, Kits): one button per tab, 110 pixels
##     wide; each button's text is its tab's name;
##   Scroll > Content: the scroll area (at least 120 pixels tall) and the
##     column inside it that holds the current tab's cards;
##   SlotsHeading, then Slots: the heading and the row for the pilot's 6
##     gear slot cards.
## Everything made from game data is added in code: _ready() adds the 6
## gear slot cards (click one to sell it; HangarGear), and each tab's cards
## come from its own static library (HangarShips, HangarModules,
## HangarGear, HangarKits), which builds them and keeps them up to date.
## Picking a tab (_set_tab) throws the old cards away and builds the new
## tab's cards once. Then, 4 times a second, _refresh() rewrites their
## footers, so prices and reasons ("Not enough credits (120 short)") stay
## live. The status line, the Launch button and the hyperspace launch row
## belong to HangarLaunch.
## What the hangar allows depends on where the pilot is (mode()):
##   - docked at a working mothership, or waiting there to respawn: buy
##     everything, then Launch;
##   - flying inside one of our repair bays' range: swap modules only;
##   - anywhere else in flight: look only (read-only);
##   - while the mothership is out of action (destroyed or systems
##     failure): no shopping, but a docked pilot can still launch from
##     one of our repair bays.
##
## WHO USES IT: the HUD makes it from scenes/ui/hangar.tscn
## (HudPanels.open_hangar), calls setup(), hides it on `closed`, and calls
## _set_tab(tab) again when its width changes by more than 20 pixels.
## HudInput calls launch() when F is pressed while docked. tests/ui_tour.gd
## calls _set_tab() and launch(). The tab libraries (files
## scripts/ui/hangar_*.gd) read this panel's fields (world, profile,
## _content, _cards, ...) directly.

## Sent when the hangar wants to close: the Close button, or a launch
## (normal or hyperspace) that worked. The HUD then hides the hangar.
signal closed

## The game world (teams, motherships, repair bays). Set by setup().
var world: World
## The human pilot's profile: credits, the hull and modules for the next
## launch, gear slots, state (docked, flying, ...). Set by setup().
var profile: PilotProfile
## The tab being shown (one tab button's text: "Ships", "Modules", "Gear"
## or "Kits"). The HUD reads it to rebuild the same tab after a resize.
var tab := "Ships"
## The title line: "Hangar · N credits".
@onready var _title: Label = $Col/Head/Texts/Title
## The status line under the title: where the pilot is and which ship they
## will fly (HangarLaunch.status_text).
@onready var _sub: Label = $Col/Head/Texts/Status
## The big Launch button (HangarLaunch.refresh_button sets its text).
@onready var _launch: Button = $Col/Head/Launch
## The row of hyperspace launch buttons, one per repair bay; empty unless
## a docked pilot's team has the Hyperspace Module and a working bay.
@onready var _bay_row: HBoxContainer = $Col/BayRow
## The tab buttons in the Tabs row, in the order they appear. Each one's
## text is its tab's name; _set_tab() colours the selected one amber.
@onready var _tab_buttons: Array[Button] = [$Col/Tabs/Ships, $Col/Tabs/Modules, $Col/Tabs/Gear, $Col/Tabs/Kits]
## The column inside the scroll area that holds the current tab's cards.
@onready var _content: VBoxContainer = $Col/Scroll/Content
## The 6 gear slot cards along the bottom (index = slot number).
var _slots: Array[CardButton] = []
## key -> card of the current tab, refreshed at 4 Hz (4 times a second).
## Keys: "ship:<hull id>", "mod:<module id>", "gear:<item id>", "kit", and
## "note" (a Label on the Modules tab, not a card).
var _cards := {}
## Seconds left until the next refresh (counts down from 0.25).
var _t := 0.0
## The uids (unique id numbers) of the repair bays shown in _bay_row, so
## the row is only rebuilt when that list changes.
var _bay_launch_ids: Array = []


## Godot calls this when the hangar joins the HUD (the frame is already
## there, from the scene): connect the buttons, then add the 6 gear slot
## cards, side by side and 54 pixels tall. A click on a slot sells what is
## in it. The tab contents come later, from _set_tab().
func _ready() -> void:
	# Step 1: Launch launches (its true / false answer is not needed),
	# Close sends `closed`, and each tab button shows the tab it names.
	_launch.pressed.connect(launch)
	$Col/Head/Close.pressed.connect(func() -> void: closed.emit())
	for b in _tab_buttons:
		b.pressed.connect(_set_tab.bind(b.text))
	# Step 2: one card per gear slot (Items.SLOTS), sharing the row's width.
	for i in Items.SLOTS:
		var c := CardButton.new("Empty", "", "", 0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size = Vector2(0, 54)
		c.pressed.connect(func() -> void: HangarGear.sell_slot(self, i))
		$Col/Slots.add_child(c)
		_slots.append(c)


## Connect the hangar to world `w` and pilot profile `p`, then build a tab:
## Ships if the pilot has no ship chosen yet, else the current tab. The HUD
## calls this once, right after making the hangar.
func setup(w: World, p: PilotProfile) -> void:
	world = w
	profile = p
	_set_tab("Ships" if p.hull_id == "" else tab)


## Where the pilot is, which decides what the hangar allows:
##   "dock"       docked at a working mothership: shop and launch;
##   "dead"       waiting to respawn at a working mothership: shop;
##   "bay"        flying inside one of our repair bays' range: swap modules;
##   "flying"     flying anywhere else: look only;
##   "spooling"   waiting for a hyperspace launch to a repair bay;
##   "bay_launch" docked while the mothership is out of action, but a
##                working repair bay can be launched from;
##   "offline"    the mothership is out of action (and no bay launch), or
##                there is no profile.
func mode() -> String:
	if profile == null:
		return "offline"
	var ms := world.mothership(profile.team)
	# Step 1: in flight: inside a bay's module-swap circle, or not.
	if profile.state == "flying":
		var s := profile.ship
		if s != null and is_instance_valid(s) and world.bay_at(profile.team, s.global_position) != null:
			return "bay"
		return "flying"
	if profile.state == "spooling":
		return "spooling"
	# Step 2: the mothership is gone or not available (Mothership.available:
	# alive and no systems failure).
	if ms == null or not ms.available():
		# During an outage docked pilots can still launch from a repair bay
		# (World.launch falls back to one), but not shop.
		if profile.state == "docked" and world.best_bay(profile.team, ms.global_position if ms != null else Vector2.ZERO) != null:
			return "bay_launch"
		return "offline"
	# Step 3: a working mothership: docked, or dead and waiting to respawn.
	return "dock" if profile.state == "docked" else "dead"


## May the pilot buy and sell right now? Only at a working mothership:
## docked ("dock") or waiting to respawn ("dead").
func can_shop() -> bool:
	var m := mode()
	return m == "dock" or m == "dead"


## May the pilot buy repair kits and gear right now? At the mothership
## (can_shop), or, with the Bay shop feature on, in flight inside a repair
## bay's range when BayShopFeature allows it (hulls and modules still need
## the mothership).
func can_shop_goods() -> bool:
	if can_shop():
		return true
	return mode() == "bay" and world.features.has("bay_shop") and (world.features["bay_shop"] as BayShopFeature).human_can_shop(self)


## Show tab `t` (one tab button's text): colour its button amber, throw
## away the old cards, build the new tab's cards and fill them in at once.
## Other files call it too (the HUD after a resize, tests/ui_tour.gd).
func _set_tab(t: String) -> void:
	tab = t
	# Step 1: the selected tab's button gets amber text and border.
	for b in _tab_buttons:
		b.add_theme_color_override("font_color", Palette.AMBER if b.text == t else Palette.ICE)
		b.add_theme_stylebox_override("normal", UiKit.box(Palette.INK, Palette.AMBER if b.text == t else Palette.LINE, 8))
	# Step 2: remove the old cards (queue_free deletes a node at the end of
	# this frame).
	for c in _content.get_children():
		c.queue_free()
	_cards.clear()
	# Step 3: build the new tab with its library.
	match t:
		"Ships":
			HangarShips.build(self)
		"Modules":
			HangarModules.build(self)
		"Gear":
			HangarGear.build(self)
		"Kits":
			HangarKits.build(self)
	# Step 4: fill in the texts straight away.
	_refresh()


## The width in pixels of one card when `cols` cards sit side by side: the
## panel's width minus 60 (but at least 600), less the 8-pixel gaps
## between cards, shared out and rounded down. The panel's width is the one
## it is meant to have (UiKit.panel_width), not its `size`: the cards make
## the panel at least as wide as they are, so `size` could never shrink.
func _card_width(cols: int) -> float:
	var w := maxf(600.0, UiKit.panel_width(self) - 60.0)
	return floorf((w - float(cols - 1) * 8.0) / float(cols))


## Add a grid with `cols` columns and 8-pixel gaps to the tab's content and
## return it. The grid itself ignores the mouse; its cards still get it.
func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(g)
	return g


## Make a card `w` pixels wide with `title` and description `sub`, add it
## to `parent`, remember it in _cards under `id`, and call `on_press` when
## it is clicked. The description and footer wrap 22 pixels inside the
## card. Returns the card.
func _make_card(parent: Control, id: String, title: String, sub: String, w: float, on_press: Callable) -> CardButton:
	var c := CardButton.new(title, sub, "", w)
	UiKit.pin_width(c.sub, w - 22.0)
	c.foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.pin_width(c.foot, w - 22.0)
	c.pressed.connect(on_press)
	parent.add_child(c)
	_cards[id] = c
	return c


## Every frame while the hangar is shown: count `dt` (seconds since the
## last frame) down and refresh every 0.25 seconds.
func _process(dt: float) -> void:
	if not visible or world == null:
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.25
		_refresh()


## Rewrite everything that changes: the title (credits), the status line,
## the Launch button and hyperspace row, every card's footer, the Modules
## tab's note and the gear slots.
func _refresh() -> void:
	if profile == null:
		return
	var m := mode()
	var shop := can_shop()
	var goods := can_shop_goods()
	var ts := world.teams[profile.team]
	UiKit.set_text(_title, "Hangar  ·  %s credits" % Util.money(profile.credits))
	# Step 1: the status line, the Launch button, and the hyperspace row
	# (only docked, and only with the Hyperspace Module).
	UiKit.set_text(_sub, HangarLaunch.status_text(self, m))
	HangarLaunch.refresh_button(self, m)
	HangarLaunch.refresh_bay_row(self, m == "dock" and ts.facilities.has("hyperspace"))
	# Step 2: each card's footer, by the start of its key. (The "note"
	# Label is not a card, so it is skipped here.)
	for key: String in _cards:
		var node = _cards[key]
		if not (node is CardButton):
			continue
		var c: CardButton = node
		if key.begins_with("ship:"):
			HangarShips.refresh_card(self, c, key.substr(5), shop, ts)
		elif key.begins_with("mod:"):
			HangarModules.refresh_card(self, c, key.substr(4), m)
		elif key.begins_with("gear:"):
			HangarGear.refresh_card(self, c, key.substr(5), goods)
		elif key == "kit":
			HangarKits.refresh_card(self, c, goods)
	# Step 3: the Modules tab's note, then the gear slots.
	if _cards.has("note"):
		HangarModules.refresh_note(self, _cards["note"], m)
	HangarGear.refresh_slots(self, shop)


## Launch from the mothership (F or the Launch button), or from a repair
## bay while the mothership is out of action. Returns true on success. The
## real code lives in HangarLaunch.launch().
func launch() -> bool:
	return HangarLaunch.launch(self)
