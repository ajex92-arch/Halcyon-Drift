class_name BreachTracker
extends RefCounted
## WHAT THIS IS: the "lane breach" notebook shared by two feature modules,
## BreachFeature (the breach corvette, variant "breach") and
## BreachExtraFeature (the extra super minion, variant "breach_extra"). It
## remembers which enemy lanes a team has broken open.
##
## HOW IT WORKS: a lane is "breached" for the attacking team when the LAST
## turret at an enemy INNER ore node (the ore field on that lane nearest the
## enemy mothership) is destroyed. The tracker listens to
## Events.turret_destroyed; when the dead turret's node is an inner node and
## no turret of the defending team is left on it, the lane is breached for
## the attacker for WAVES (8) free minion waves, about 280 s. A new breach on
## a lane that is already breached starts the count again.
## The owner (a feature) calls serve() for the first escort corvette of each
## free wave that launches: it answers "yes, that lane is breached, give this
## wave its special unit" and uses up one wave of the breach. The tracker
## also tells the HUD about it: a one-line feed message when a breach starts
## (for both teams), a banner text for 20 s afterwards (banner()) and the
## minimap chevrons (marks()).
## It draws no random numbers and creates no units.
##
## WHO USES IT: BreachFeature and BreachExtraFeature each make one in their
## install() and call start(), serve(), banner() and marks().

## How many free waves a breach lasts.
const WAVES := 8
## How long (seconds) the HUD banner shows after a breach starts.
const BANNER_SECS := 20.0

## The match we track.
var world: World
## Waves left per lane: [Halcyon's dictionary, Cinder's dictionary], each
## lane id ("top", "mid", "bot") -> waves still to serve (absent or 0 = the
## lane is not breached for that team).
var left: Array = [{}, {}]
## When each breach started (match time in seconds), laid out like `left`;
## the banner uses it.
var since: Array = [{}, {}]
## The lanes already served for the current wave: "<team><lane>" -> the
## wave id (MinionDirector.next_wave) it was served for, so a second
## corvette of the same wave (Escort Wing) is not counted as the first.
var _served := {}
## The ore node where each breach happened, laid out like `left`, so the
## minimap knows where to draw the chevron: lane id -> world position.
var _where: Array = [{}, {}]


## Remember the world. A feature makes this once per match.
func _init(w: World) -> void:
	world = w


## Start listening for destroyed turrets.
func start() -> void:
	Events.turret_destroyed.connect(_on_turret_destroyed)


## A turret died (Events.turret_destroyed). If it was the last one of its
## team at an inner node, that lane is breached for `by_team`.
func _on_turret_destroyed(turret: Node, by_team: int) -> void:
	var t := turret as Turret
	if t == null or by_team < 0 or by_team > 1 or t.node == null:
		return
	var n: ResourceNode = t.node
	# Step 1: only the last turret of the defending team at an INNER node.
	if n.node_kind != "inner" or n.turret_count(t.team) > 0:
		return
	# Step 2: breach the lane for the attacker and tell everyone.
	(left[by_team] as Dictionary)[n.lane] = WAVES
	(since[by_team] as Dictionary)[n.lane] = world.time
	(_where[by_team] as Dictionary)[n.lane] = n.global_position
	Events.feed.emit("The %s fleet has breached the %s: %d waves of reinforced escorts will follow." % [Rules.TEAM_NAMES[by_team], MapLayout.LANES[n.lane]["label"].to_lower(), WAVES], "info", -1)


## A free wave's first escort corvette of `team` on `lane` has just launched
## (`wave_id` = MinionDirector.next_wave then). Returns true when that lane is
## breached for `team` and this is the first corvette of this wave, and
## then uses up one wave of the breach. A second corvette of the same wave
## answers false.
func serve(team: int, lane: String, wave_id: float) -> bool:
	var waves: int = int((left[team] as Dictionary).get(lane, 0))
	if waves <= 0:
		return false
	var key := "%d%s" % [team, lane]
	if _served.get(key, -1.0) == wave_id:
		return false
	_served[key] = wave_id
	(left[team] as Dictionary)[lane] = waves - 1
	return true


## The HUD banner for the human on `team`: [] for none, else [title,
## sub line, tone] (tone "amber" or "cinder"). Shown for BANNER_SECS after a
## breach starts: the attacker sees "Lane breached", the defender "Our lane
## is breached".
func banner(team: int) -> Array:
	for att in 2:
		for lane: String in (since[att] as Dictionary):
			if world.time - float((since[att] as Dictionary)[lane]) > BANNER_SECS or int((left[att] as Dictionary).get(lane, 0)) <= 0:
				continue
			var label: String = MapLayout.LANES[lane]["label"]
			if att == team:
				return ["%s breached" % label, "Reinforced escorts launch with the next %d waves." % int((left[att] as Dictionary)[lane]), "amber"]
			return ["%s breached" % label, "The enemy has broken our inner defences: expect reinforced escorts.", "cinder"]
	return []


## The minimap chevrons: one Dictionary per breached lane, {"pos": the inner
## node's position, "team": the attacker}.
func marks() -> Array:
	var out: Array = []
	for att in 2:
		for lane: String in (left[att] as Dictionary):
			if int((left[att] as Dictionary)[lane]) > 0:
				out.append({"pos": (_where[att] as Dictionary)[lane], "team": att})
	return out
