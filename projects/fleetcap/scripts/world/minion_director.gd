class_name MinionDirector
extends RefCounted
## WHAT THIS IS: sends out the minions (small computer-flown lane ships)
## in waves, and runs the Fleet Command mode where an admiral buys and
## steers minions instead. DESIGN.md A8.
##
## HOW IT WORKS:
##   - Free waves: the first wave at 0:45 (Minions.FIRST_WAVE), then one
##     every 35 s (Minions.WAVE_INTERVAL; a feature module may tune it as
##     "wave_interval", see Rules.tune). For each lane, each mothership
##     launches 1 escort corvette, 5 fighters and 4 bombers (Minions.WAVE),
##     plus one extra corvette per TeamState.wave_corvettes (the Escort
##     Wing research). The minions of a lane leave 0.35 s apart.
##   - The escort_wing rule variant can change what Escort Wing does: with
##     "upgrade" its feature module (EscortWingFeature) sets
##     escort_upgrade. Then no corvette is added: each wave's own corvette
##     is marked in the queue and upgraded as it launches
##     (EscortWingFeature.upgrade: +40% hull, +15% weapon range).
##   - Waves are not spawned at once: each minion is put in `queue` with
##     its launch time, and tick() spawns the ones whose time has come.
##     Minions launch from one of 5 spots off the mothership's bow, picked
##     at random.
##   - Fleet Command (the team owns the "fleet" facility): free waves stop
##     for that team; the admiral buys minions with team money
##     (Minions.TYPES[type].buy_cost, at most 30 alive, CONTROL_CAP) and
##     gives them orders through set_order().
##
## WHO USES IT: World makes one (World.minion_director) in WorldSetup and
## calls tick() every tick. AdmiralCommand calls buy() and set_order();
## the AI admiral, the admiral's board, the command overlay and the HUD
## ask controlled(), alive_count() and next_wave. EscortWingFeature sets
## escort_upgrade. tick() sends Events.minion_launched for each free-wave
## minion it launches; BreachFeature, BreachExtraFeature and LanespawnFeature
## listen (nobody does by default).

## The match we send minions into.
var world: World
## Match time (seconds) of the next free wave. Starts at 45 s.
var next_wave := Minions.FIRST_WAVE
## Minions waiting to launch. Each entry is
## [launch time (s), team, type id, lane id], plus a fifth entry `true` on
## a corvette marked for the Escort Wing upgrade (only with escort_upgrade).
var queue: Array = []
## The escort_wing variant's switch, set by its feature module
## (EscortWingFeature.install). false (the default, "extra") = today's
## game: Escort Wing research adds one corvette per lane to every free
## wave. true ("upgrade") = waves keep their 10 minions, and while the team
## has Escort Wing each wave's corvette launches upgraded.
var escort_upgrade := false


## Remember the world. WorldSetup makes this once per match.
func _init(w: World) -> void:
	world = w


## True if `team` owns the Fleet Command Module (then its admiral runs the
## minions and the free waves stop).
func controlled(team: int) -> bool:
	return world.teams[team].facilities.has("fleet")


## How many live minions `team` has.
func alive_count(team: int) -> int:
	var n := 0
	for m: Minion in world.minions:
		if m.team == team and m.alive:
			n += 1
	return n


## Called by World every tick: start a new free wave when it is due, then
## launch every queued minion whose time has come. `_dt` is not used (we
## go by the match clock).
func tick(_dt: float) -> void:
	# Step 1: a new wave is due. Queue it for each team without Fleet
	# Command. (The gap to the next wave is a tuned number, normally
	# Minions.WAVE_INTERVAL.)
	if world.time >= next_wave:
		next_wave += float(Rules.tune("wave_interval", Minions.WAVE_INTERVAL))
		for team in 2:
			if controlled(team):
				continue
			_queue_wave(team)
	# Step 2: launch the due minions (in queue order) and keep the rest. A
	# corvette marked for the Escort Wing upgrade (a fifth entry) gets it
	# as it launches.
	var keep: Array = []
	for q: Array in queue:
		if world.time >= float(q[0]):
			var m := _spawn(int(q[1]), q[2], q[3])
			# Tell the feature modules that listen (nobody does by default).
			if m != null:
				Events.minion_launched.emit(m, next_wave)
			if q.size() > 4 and m != null:
				EscortWingFeature.upgrade(m)
		else:
			keep.append(q)
	queue = keep


## Put one wave for `team` into the queue: the whole wave on every lane,
## with the minions of a lane 0.35 s apart. With Escort Wing researched,
## each lane also gets the research corvettes; with escort_upgrade set,
## it gets none, and the wave's own corvette is marked for the upgrade.
func _queue_wave(team: int) -> void:
	var t0 := world.time
	var wave: Array = Minions.WAVE.duplicate()
	var extra := world.teams[team].wave_corvettes
	# Step 1: today's game adds the research corvettes to the wave.
	if not escort_upgrade:
		for k in extra:
			wave.append("corvette")
	# Step 2: the "upgrade" variant marks the corvette instead (when the
	# team has Escort Wing).
	var mark := escort_upgrade and extra > 0
	# Step 3: queue the wave on every lane.
	for lane: String in MapLayout.LANE_ORDER:
		for i in wave.size():
			if mark and wave[i] == "corvette":
				queue.append([t0 + 0.35 * float(i), team, wave[i], lane, true])
			else:
				queue.append([t0 + 0.35 * float(i), team, wave[i], lane])


## Launch one minion now, at a random one of the mothership's 5 launch
## spots (one random number). Returns null, and the minion is dropped, if
## the mothership is dead.
func _spawn(team: int, type_id: String, lane: String) -> Minion:
	var ms := world.mothership(team)
	if ms == null or not ms.alive:
		return null
	var slot := randi() % 5
	return world.spawn_minion(team, type_id, lane, ms.launch_point(slot))


## Fleet Command: buy one minion of type `type_id` for lane `lane`, paid
## from the team treasury. Returns "" or why not.
func buy(team: int, type_id: String, lane: String) -> String:
	# Check every reason it can't happen, in order.
	if not controlled(team):
		return "Needs the Fleet Command Module"
	var cap := Minions.control_cap()
	if alive_count(team) >= cap:
		return "Minion cap reached (%d)" % cap
	var ms := world.mothership(team)
	if ms == null or not ms.alive:
		return "The mothership can't launch minions"
	# Pay, then launch it straight away (not through the queue).
	var cost: float = float(Minions.TYPES[type_id]["buy_cost"])
	if not world.teams[team].spend(cost):
		return "Not enough in the team treasury"
	_spawn(team, type_id, lane)
	return ""


## Fleet Command: give `order` to the listed minions of `team` (others,
## and dead ones, are skipped). order = {"type": "lane", "lane": id}
## | {"type": "move", "pos": Vector2} | {"type": "hold", "pos": Vector2}.
## Each minion gets its own copy; a "lane" order also switches its lane.
func set_order(team: int, minions: Array, order: Dictionary) -> void:
	for m: Minion in minions:
		if m == null or not is_instance_valid(m) or m.team != team or not m.alive:
			continue
		m.order = order.duplicate()
		if order.get("type", "") == "lane":
			m.set_lane(order.get("lane", m.lane))
