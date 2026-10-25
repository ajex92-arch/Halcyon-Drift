class_name Hud
extends Control
## WHAT THIS IS: the HUD ("heads-up display"): everything drawn on top of
## the game during a match, such as the clock, your credits, the kill feed,
## your ship's shields and the minimap. It is also the screen manager: it
## decides which big panel (hangar, Admiral board, help...) is open and what
## the menu keys do.
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud.tscn: one node
## ("Hud") that covers the whole window, lets mouse clicks pass through to
## the game, and keeps running while the game is paused (so the pause
## message and the P key still work). Inside it are the widgets (a
## "widget": one small, self-contained part of the screen, each with its
## own scene and script), in this order: later ones draw on top of earlier
## ones.
##   TopBar      top centre: HudTopBar: clock, next minion wave, both
##               motherships' hull bars and how many turrets each side
##               has per lane
##   MePanel     top left: HudMePanel: you (credits, or the Admiral's
##               treasury), K/D/A, ship, and a short log of what just
##               paid you
##   Feed        top right, under the top bar: HudFeed: the kill / event
##               feed
##   Banner      centre: HudBanner: big messages (respawn timer, docked, a
##               turret targeting you, mothership trouble, the armed
##               Admiral map tool, pause)
##   Toast       bottom centre: HudToast: short pop-up hints
##   ShipStatus  bottom centre, 8 pixels up: shields, hull, energy,
##               routing, ability (it draws itself)
##   Minimap     bottom right, 8 pixels in from both edges (it draws
##               itself)
##   Slots       bottom left: HudSlots: the 6 gear slots and a reminder of
##               the keys
## _ready() gives the HUD the game's look (UiKit.make_theme()). setup()
## then sets the interface's highlight colour to the human's team (amber for
## Aurelian and for a spectator, red for Vhorr: UiKit.set_accent_team(), and a
## new theme if that changed the colour) and wires everything up: it makes the
## Admiral's map-tool layer, tells
## the widgets which world they show, and listens to game news from
## Events. (A "signal" is a message a script sends out; any other script
## can "connect" a function to it, and that function then runs every time
## the message is sent.) Each piece of news goes to the widget that shows
## it. Every 0.1 seconds (10 times a second) _refresh() tells every widget
## to update its text.
## Big panels: Hangar (B), Admiral board (Tab, admiral), Scoreboard (hold
## Tab, pilots), Help (H) and the End screen. They are made from their own
## scenes when first needed. HudPanels keeps only one of them open at a
## time. HudLayout keeps the pieces out of each other's way: it moves the
## top bar, the gear slots and the ship readout aside when the window is
## narrow, and hides the pieces a big panel would cover while it is open.
## HudInput routes the keys: Esc closes panels or cancels a map
## tool, C switches the Admiral's camera between free and following their
## ship, P pauses, F launches when docked (in flight, PlayerController
## uses F to dock instead). DESIGN.md A15 shows the layout.
##
## WHO USES IT: main.gd loads scenes/ui/hud.tscn and calls setup(world).
## tests/ui_tour.gd finds the "Hud" node and uses hud.hangar, hud.board,
## hud.overlay, _toggle_help(), _show_scoreboard() and _toggle_board(). Its
## parts: the widgets above, HudPanels (opens and closes panels) and
## HudInput (menu keys).

## The end-of-match screen (who won, totals, top pilots).
const END_SCENE := preload("res://scenes/ui/end_screen.tscn")
## The Admiral's map-tool layer (drawn in the game world, not on the HUD).
const OVERLAY_SCENE := preload("res://scenes/ui/command_overlay.tscn")

## The pop-up text shown when one of the human Admiral's orders worked,
## keyed by the order's name (as sent in Events.admiral_result). Orders not
## listed here succeed silently. A failed order shows AdmiralCommand's own
## reason instead.
const RESULT_OK := {"facility": "Module queued.", "research": "Research queued.", "turret": "Turret under construction.",
	"bay": "Repair bay launched: it will fly there and anchor.", "ward": "Ward launched.", "waypoint": "Rally waypoint set.",
	"move": "The mothership is moving.", "drone": "Mining drone queued.", "order": "Orders sent.", "minion": "Minion launched."}

## The game world this HUD shows (set by setup()).
var world: World
## The Admiral's map tools (CommandOverlay). It is a child of World, not of
## the HUD, so it can draw in world positions.
var overlay: CommandOverlay
## The minimap in the bottom-right corner.
@onready var minimap: Minimap = $Minimap
## The ship readout at the bottom centre (hidden while you have no ship).
@onready var status: ShipStatus = $ShipStatus
## The hangar panel (B). Made the first time it opens; null until then.
var hangar: Hangar = null
## The Admiral board (Tab, Admiral only). Made on first use; null until then.
var board: AdmiralBoard = null
## The pilots' scoreboard (hold Tab). Made on first use; null until then.
var scoreboard: Scoreboard = null
## The help pages (H). Made on first use; null until then.
var help: HelpPanel = null
## The end-of-match screen. Made when the match ends; null until then.
var end_screen: EndScreen = null

## Widget: clock, next wave, mothership bars, turret counts (top centre).
@onready var top_bar: HudTopBar = $TopBar
## Widget: your name, credits, K/D/A and earnings log (top left).
@onready var me_panel: HudMePanel = $MePanel
## Widget: the kill / event feed (top right).
@onready var feed: HudFeed = $Feed
## Widget: the big centre messages.
@onready var banner: HudBanner = $Banner
## Widget: the short pop-up hint box (see toast()).
@onready var toast_box: HudToast = $Toast
## Widget: the gear slots and key reminder (bottom left).
@onready var slots: HudSlots = $Slots
## Part: opens and closes the big panels (only one at a time).
var panels: HudPanels
## Part: keeps the HUD's pieces out of each other's way.
var layout: HudLayout
## Part: decides what each menu key does.
var router: HudInput

## Seconds until the next full refresh (counts down from 0.1).
var _t := 0.0


## Called once when the node joins the scene: give the HUD (and every
## widget inside it) the game's look. Each widget picks its own named look
## from this theme.
func _ready() -> void:
	theme = UiKit.make_theme()


## Wire the HUD to world `w` and start listening to game news. main.gd
## calls this once, right after adding the HUD to the screen.
func setup(w: World) -> void:
	world = w
	# Step 0: the highlight colour is the human's team's (a spectator's World
	# says Aurelian). The panels made from here on take it from UiKit, and the
	# theme made in _ready() is made again if it had another team's.
	if UiKit.accent_team != w.human_team:
		UiKit.set_accent_team(w.human_team)
		theme = UiKit.make_theme()
	# Step 1: the Admiral's map-tool layer lives in the game world.
	overlay = OVERLAY_SCENE.instantiate()
	world.add_child(overlay)
	overlay.setup(world)
	layout = HudLayout.new(self)
	panels = HudPanels.new(self)
	resized.connect(layout.apply)
	router = HudInput.new(self)
	# Step 2: tell the widgets (already in the scene) what they show.
	me_panel.world = w
	feed.world = w
	banner.hud = self
	toast_box.hud = self
	minimap.setup(world, overlay)
	# Step 3: listen to game news. Each signal goes to the widget that
	# shows it (the order of these lines is kept from the original code).
	Events.feed.connect(feed.on_feed)
	Events.toast.connect(toast)
	Events.unit_killed.connect(feed.on_unit_killed)
	Events.turret_destroyed.connect(feed.on_turret_destroyed)
	Events.research_done.connect(feed.on_research_done)
	Events.facility_done.connect(feed.on_facility_done)
	Events.credits_earned.connect(me_panel.on_credits)
	Events.respawned.connect(_on_respawned)
	Events.admiral_result.connect(_on_admiral_result)
	Events.match_over.connect(_on_match_over)
	# Step 4: a first hint. Pilots start in the hangar to pick a ship.
	if world.human_role == "pilot":
		_open_hangar()
		toast("Pick a ship in the hangar and launch. H explains everything.")
	elif world.human_role == "admiral":
		toast("You command %s. Tab opens the Admiral board; H explains everything." % Rules.TEAM_DISPLAY[world.human_team])
	_refresh()


# --- panels (the real code lives in HudPanels) --------------------------------

## Open the hangar. Forwards to HudPanels.open_hangar().
func _open_hangar() -> void:
	panels.open_hangar()


## Show or hide the Admiral board. Forwards to HudPanels.toggle_board().
func _toggle_board() -> void:
	panels.toggle_board()


## Show (`on` = true) or hide the scoreboard. Forwards to
## HudPanels.show_scoreboard().
func _show_scoreboard(on: bool) -> void:
	panels.show_scoreboard(on)


## Show or hide the help pages. Forwards to HudPanels.toggle_help().
func _toggle_help() -> void:
	panels.toggle_help()


## Hide every big panel except `keep` (null hides them all). Forwards to
## HudPanels.close_others().
func _close_others(keep: Control) -> void:
	panels.close_others(keep)


## Is any big panel showing? Forwards to HudPanels.any_open().
func _any_panel_open() -> bool:
	return panels.any_open()


# --- input ---------------------------------------------------------------------

## Godot sends here every key the game didn't use. HudInput.handle()
## decides what each menu key does.
func _unhandled_input(event: InputEvent) -> void:
	router.handle(event)


# --- events ----------------------------------------------------------------------

## Pop up a short hint for 3.5 seconds (see HudToast). Connected to
## Events.toast, so any script can show one. Not once the match is over:
## the end screen has the whole window.
func toast(text: String) -> void:
	if end_screen == null:
		toast_box.show_text(text)


## Someone respawned. If it is the human pilot, open the hangar so they can
## shop before launching, and forget how they died.
func _on_respawned(p: RefCounted) -> void:
	if p == world.human and world.human_role == "pilot":
		_open_hangar()
		feed.last_cause = ""


## One of an Admiral's orders was carried out (`ok`) or refused. Only the
## human Admiral (the one of the human's team) gets a pop-up: the RESULT_OK text
## when it worked, or the reason (`message`) when it didn't.
func _on_admiral_result(team: int, action: String, ok: bool, message: String) -> void:
	if world.human_role != "admiral" or team != world.human_team:
		return
	if ok:
		var m: String = RESULT_OK.get(action, "")
		if m != "":
			toast(m)
	else:
		toast(message)


## The match ended: unpause, close every panel and map tool, and show the
## end screen on top of everything (a pop-up hint still showing goes: it
## would be drawn over the end screen's text).
func _on_match_over(winner: int, reason: String) -> void:
	get_tree().paused = false
	_close_others(null)
	overlay.disarm()
	toast_box.visible = false
	end_screen = END_SCENE.instantiate()
	end_screen.setup(world, winner, reason)
	add_child(end_screen)


# --- refresh -----------------------------------------------------------------------

## Runs every frame (dt = seconds since the last frame). Fades the pop-up
## hint, and every 0.1 seconds refreshes all the widgets.
func _process(dt: float) -> void:
	if world == null:
		return
	toast_box.tick(dt)
	_t -= dt
	if _t <= 0.0:
		_t = 0.1
		_refresh()


## Update every widget's text from the game state. Old feed lines fade out
## after HudFeed.LIFE seconds and earnings lines after HudMePanel.EARN_LIFE.
func _refresh() -> void:
	# Step 1: the text widgets.
	top_bar.refresh(world)
	me_panel.refresh(world)
	banner.refresh()
	slots.refresh_slots(world.human)
	HudFeed.fade_lines(feed, HudFeed.LIFE)
	HudFeed.fade_lines(me_panel.earn_box, HudMePanel.EARN_LIFE)
	# Step 2: the ship readout only shows while our ship is alive.
	var h := world.human
	var ship: Ship = null
	if h != null and h.ship != null and is_instance_valid(h.ship) and h.ship.alive:
		ship = h.ship
	status.visible = ship != null
	status.set_ship(ship)
	# Step 3: gear slots for pilots (and for an Admiral flying a ship).
	slots.slots_box.visible = h != null and (world.human_role == "pilot" or ship != null)
	slots.refresh_keys(world.human_role)
	# Step 4: move the pieces out of each other's way (after step 2, which
	# may have shown the ship readout again).
	layout.apply()
