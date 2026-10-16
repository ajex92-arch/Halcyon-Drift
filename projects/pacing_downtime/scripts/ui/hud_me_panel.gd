class_name HudMePanel
extends PanelContainer
## WHAT THIS IS: the small panel in the top-left corner of the HUD about
## you: your callsign and credits, K/D/A (kills / deaths / assists), last
## hits, ship and lane. For the Admiral it shows the team treasury, mining
## drones, ore delivered and current research instead. Under that is a
## short log of what just paid you ("+40 last hit").
##
## HOW IT WORKS: the layout is the scene scenes/ui/hud_me_panel.tscn: a
## see-through dark panel (the "MeLook" look) 8 pixels from the top-left
## corner, as big as its text, holding one column: Rows (Title, Line,
## Earnings). Title is the amber first line, Line the grey lines under it
## and Earnings the earnings log. The mouse passes through it to the game.
## refresh() rewrites the text 10 times a second. on_credits() hears every
## payment in the game and adds a green "+amount reason" line for the
## human's own payments. Payments of the same kind within 1.5 seconds are
## added together on one line, at most 4 lines are kept, and Hud._refresh()
## fades each line out after EARN_LIFE seconds (HudFeed.fade_lines).
##
## WHO USES IT: the HUD's scene (scenes/ui/hud.tscn) holds it. Hud.setup()
## gives it the world and connects Events.credits_earned to on_credits();
## Hud._refresh() calls refresh() and fades earn_box.

## How long (seconds) an earnings line stays before it is removed. It fades
## out during its last 1.5 seconds.
const EARN_LIFE := 5.0
## Plain words for the payment reasons sent with Events.credits_earned
## ("minion" -> "last hit"). A reason not listed is shown as it is.
const EARN_REASON := {"minion": "last hit", "kill": "kill", "assist": "assist", "ore": "ore share", "escort": "drone escort",
	"turret": "turret destroyed", "repair bay": "repair bay destroyed", "drone": "mining drone destroyed", "ward": "ward destroyed",
	"repair drone": "repair drone destroyed", "derelict": "derelict", "stipend": "stipend"}

## The game world (Hud.setup() sets it).
var world: World
## The earnings log: one Label per recent payment, oldest first. Each line
## remembers when it was made ("born", in milliseconds) and its total
## ("amount", credits) as metadata (extra values stored on the node).
@onready var earn_box: VBoxContainer = $Rows/Earnings
## First line: callsign and credits (or "Admiral · treasury ...").
@onready var _me_title: Label = $Rows/Title
## The lines under it: K/D/A, ship and lane (or the Admiral's economy).
@onready var _me_line: Label = $Rows/Line
## The newest earnings line for each reason text, so a quick second
## payment of the same kind adds to it instead of making a new line.
var _earn_last := {}


## Rewrite the panel's text for the human's seat: spectator, Admiral or
## pilot.
func refresh(w: World) -> void:
	var h := w.human
	# Spectators see no panel at all. (With no human profile in another
	# seat, the panel stays visible and says "Spectating".)
	if w.human_role == "spectator" or h == null:
		visible = w.human_role != "spectator"
		UiKit.set_text(_me_title, "Spectating")
		return
	# The Admiral: treasury, drones, ore, research, and their own credits.
	if w.human_role == "admiral":
		var ts := w.teams[h.team]
		UiKit.set_text(_me_title, "Admiral  ·  treasury %s" % Util.money(ts.treasury))
		var line := "%d mining drones · %s ore delivered" % [w.mining_drone_count(h.team), Util.money(ts.ore_delivered)]
		if not ts.research.is_empty():
			line += "\nResearching %s" % Tech.TECHS[ts.research[0]["id"]]["label"]
		line += "\nYour own ship: %s credits" % Util.money(h.credits)
		UiKit.set_text(_me_line, line)
		return
	# A pilot: credits, K/D/A, last hits, ship (or the docked hull) and lane.
	UiKit.set_text(_me_title, "%s  ·  %s credits" % [h.callsign, Util.money(h.credits)])
	var ship_txt := "No ship"
	if h.ship != null and is_instance_valid(h.ship):
		ship_txt = String(Ships.HULLS[h.ship.hull_id]["label"])
	elif h.hull_id != "":
		ship_txt = "%s (docked)" % Ships.HULLS[h.hull_id]["label"]
	UiKit.set_text(_me_line, "K/D/A %s · last hits %d\n%s · %s lane" % [h.kda(), h.minion_kills, ship_txt, h.role])


## Someone (profile `p`) earned `amount` credits for `reason`. If it is the
## human, add or update an earnings line.
func on_credits(p: RefCounted, amount: float, reason: String) -> void:
	if p != world.human:
		return
	var label: String = EARN_REASON.get(reason, reason)
	var now := Time.get_ticks_msec()
	# Step 1: the same kind of payment less than 1.5 seconds (1500 ms) after
	# the last one: add it to that line instead of making a new one.
	var last = _earn_last.get(label)
	if last is Label and is_instance_valid(last) and now - int(last.get_meta("born")) < 1500:
		var total := float(last.get_meta("amount")) + amount
		last.set_meta("amount", total)
		last.text = "+%d %s" % [int(total), label]
		return
	# Step 2: a new line.
	var l := UiKit.label("+%d %s" % [int(amount), label], 12, Palette.REPAIR)
	l.set_meta("born", now)
	l.set_meta("amount", amount)
	earn_box.add_child(l)
	_earn_last[label] = l
	# Step 3: keep only the newest 4 lines.
	while earn_box.get_child_count() > 4:
		var old := earn_box.get_child(0)
		earn_box.remove_child(old)
		old.queue_free()
