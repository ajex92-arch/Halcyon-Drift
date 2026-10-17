class_name HelpPanel
extends PanelContainer
## WHAT THIS IS: the "How to play" panel (key H), with three pages: The
## match, Flying, and Admiral.
##
## HOW IT WORKS: the layout is the scene scenes/ui/help_panel.tscn: a box
## (the "HelpLook" look) holding one column, Col > Head (Title, one button
## per page: TheMatch, Flying, Admiral, then Close) and Scroll > Body (the
## scrolling area). Each page button shows its page's name, which is also
## the page's key in PAGES, where all the text lives. _show() fills Body
## with the chosen page: each entry is an amber heading and a wrapped
## paragraph, made in code. The current page's button is amber. When the
## panel is resized, the page is rebuilt so the paragraphs wrap to the new
## width.
##
## WHO USES IT: HudPanels makes it from scenes/ui/help_panel.tscn (H toggles
## it, through HudInput) and hides it when `closed` is sent.

## Sent when the player presses "Close (H)".
signal closed

## The help text: page name -> list of [heading, paragraph] pairs, shown in
## this order.
const PAGES := {
	"The match": [
		["Goal", "Destroy the enemy mothership. Nothing else ends the match. Motherships are huge: strike craft barely scratch them; frigates and capital ships tear into them, so late in the match fleets mass their big ships for sieges."],
		["The map", "Three lanes (top, mid, bottom) run between the motherships, joined by the Crossing, a lane straight down the middle. Between the lanes is the jungle: dense asteroids with gaps only strike craft (Scout to Bomber) fit through. You can't see through asteroids."],
		["Minions", "From 0:45 and every 35 seconds, each mothership launches a wave down every lane: 5 fighters, 4 bombers and an escort corvette. Minions fight anything in their way. Finishing one off (the last hit) pays you credits."],
		["Turrets", "Each side's Admiral builds turrets at the asteroid resource nodes. They are tough: alone, pilots deal only 30% damage to a turret, so push with your minion wave and let the minions tank. If you shoot an enemy pilot near an enemy turret, that turret targets you."],
		["The jungle", "Derelict monster camps (gunships, and carriers that launch snub fighters) sit in the jungle and pay a reward split by damage, with a bonus for the last hit. They respawn 1-2 minutes after being cleared."],
		["Credits", "Pilots earn credits from last hits, kills and assists, derelicts, destroying turrets and drones, and a share of every ore delivery. Spend them in the hangar on ships, modules, pilot gear and repair kits. The Admiral spends the separate team treasury."],
		["Respawning", "Destroyed pilots respawn at the mothership after a few seconds (longer as the match goes on). Gear is kept; the ship and its modules are lost. When 4 or more pilots respawn within 30 seconds, the mothership is strained: its guns slow and its shields stop recharging for a while."],
	],
	"Flying": [
		["Moving", "The mouse aims and your ship turns to face it. W thrusts forward, S brakes and reverses, A / D slide sideways, Shift boosts (strike craft). Hold Ctrl to lock your heading: big ships keep their shields facing a threat while their turrets keep tracking the mouse. V toggles flight assist (off = drift)."],
		["Shooting", "Left-click or Space fires. Right-click or G uses your ship's ability. Fixed guns fire where the nose points; turrets on bigger ships track the mouse; point-defense guns pick their own targets and shoot down torpedoes."],
		["Shields", "Shields have four zones: front, rear, left and right. A hit drains the zone facing the attacker; when it is empty, the hull takes the damage. Arrow keys focus shield strength into one zone (press it again to balance). Shields recharge a few seconds after the last hit. Bigger ships wait longer between focus changes."],
		["Energy", "1 Weapons (faster fire), 2 Shields (faster recharge, tougher shields), 3 Engines (speed, turning, cheaper boost), 4 Balanced. Bigger ships wait longer between changes."],
		["Asteroids", "Bumping rocks is harmless at low speed; ramming them fast hurts, bigger ships more. Capital-ship cannons break asteroids."],
		["Ship sizes", "Strike craft are fast, cheap and reward good flying; they can use the jungle. Corvettes, frigates and capital ships hit hard and see farther, but turn slowly: out of position they die quickly to bombers and flak. They are what breaks a mothership."],
		["Hangar (B)", "At the mothership (or while waiting to respawn), buy a hull, up to 2 modules, pilot gear (6 slots: flight suit, helmet, stick, cockpit layout, chair, implant) and repair kits. F launches. Inside one of your repair bays' range you can swap modules mid-flight."],
		["Repair", "R uses a repair kit: a small drone that heals your hull for 10 seconds (it can be shot down). Repair bays heal nearby ships with their drones. Docking at the mothership (F when close) repairs everything."],
		["Camera", "Mouse wheel or + / - zooms (how far out depends on your ship's size). Push the mouse to the screen edge to peek. The minimap is bottom-right."],
	],
	"Admiral": [
		["Your job", "Spend the team treasury to win the map: mining drones, turrets, repair bays, wards and the research tree. Tab opens the Admiral board. Your camera can go anywhere (you still see only what your team sees): move it with WASD, the screen edges, middle-drag, or by clicking the minimap."],
		["Economy", "The treasury earns a small trickle, 60% of every ore delivery, and bounties for destroyed enemy turrets and bays. Mining drones mine ore at the resource nodes; protect them, and turrets on nodes protect them too."],
		["Research", "Like Homeworld 2: build mothership modules (Research Module, Corvette / Frigate / Capital Ship Facilities, Platform Control, Sensors, Hyperspace, Fleet Command), then research in each module's column. Pilots can only buy ships you have unlocked."],
		["Map tools", "Repair bays fly to a spot and anchor for good (jungle too). Wards go only where your team can see. The rally waypoint speeds up and shields our ships inside it, and AI pilots gather there. From 20:00, move the mothership."],
		["Sieges", "Put the rally waypoint near the enemy mothership to order a siege: our AI frigates, capital ships and bombers converge on that lane and attack it. When a group of enemy frigates or capital ships pushes into OUR base, AI pilots come back and fight them on their own."],
		["Fleet Command", "Late game, the Fleet Command Module stops free minion waves: instead, buy minions and command them. Drag a box on the map to select, right-click to send them, or use the Fleet tab."],
		["Flying yourself", "You can launch a ship of your own from the hangar (B) with your personal credits. You can still give orders and look anywhere while flying (C switches the camera between your ship and free), but moving the mothership needs you docked."],
	],
}

## The page being shown (a key of PAGES).
var _page := "The match"
## The page buttons in the header row, in PAGES order. Each one's text is
## its page's name.
@onready var _tabs: Array[Button] = [$Col/Head/TheMatch, $Col/Head/Flying, $Col/Head/Admiral]
## The scrolling column that holds the current page's entries.
@onready var _body: VBoxContainer = $Col/Scroll/Body


## Called once when the node joins the scene: each page button shows its
## page and Close sends `closed`; the page is rebuilt whenever our size
## changes, and shown now.
func _ready() -> void:
	for b in _tabs:
		b.pressed.connect(_show.bind(b.text))
	$Col/Head/Close.pressed.connect(func() -> void: closed.emit())
	resized.connect(func() -> void: _show(_page))
	_show(_page)


## Show page `p`: mark its button amber, clear the old entries, and add a
## heading and a paragraph per entry. Paragraphs are pinned to our width
## minus 60 pixels (but at least 400) so they wrap neatly.
func _show(p: String) -> void:
	_page = p
	for b in _tabs:
		b.add_theme_color_override("font_color", Palette.AMBER if b.text == p else Palette.ICE)
	# queue_free removes each old entry at the end of this frame.
	for c in _body.get_children():
		c.queue_free()
	var w := maxf(400.0, size.x - 60.0)
	# The Admiral page also explains the orders that feature modules add
	# (CommandOrders); there are none in today's game.
	var entries: Array = (PAGES[p] as Array).duplicate()
	if p == "Admiral":
		entries.append_array(CommandOrders.help_entries())
	for entry: Array in entries:
		var row := UiKit.vbox(2)
		_body.add_child(row)
		row.add_child(UiKit.label(entry[0], 15, Palette.AMBER))
		var l := UiKit.label(entry[1], 14, Palette.ICE, true)
		UiKit.pin_width(l, w)
		row.add_child(l)
