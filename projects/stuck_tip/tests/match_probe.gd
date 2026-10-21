extends Node
## WHAT THIS IS: the "match probe": the big picture of an AI-vs-AI match,
## printed every 60 game seconds. Turret losses (when, where, what killed
## them), AI pilot states, hulls in flight, credits, unlock times,
## mining drones, sieges, mothership damage, and how many pilots are
## idle. Use it to see how a whole match flows and where it goes wrong.
##
## HOW IT WORKS: it listens for two events: a turret destroyed (it writes
## down who was near) and a pilot ship killed (it counts the killer, and
## writes down every death by flying into a rock). Every 60 game seconds
## _report() prints a block of lines per team. With --debug it also prints
## the sieging fleet every 15 seconds. At the end (--secs, or when the
## match ends) it prints a last report and the two lists.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the
## folder that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --all-ai --test=match_probe --secs=1500
## --headless runs with no window; --fixed-fps 60 makes every tick (one
## small step of game time) exactly 1/60 of a game second. --secs is how
## many game seconds to watch (default 1500 = 25 minutes).
##
## HOW TO READ THE OUTPUT: each report starts "--- probe 12:00 ---", then
## for each team:
##   "Halcyon states={...} intents={...} hulls={...} idle=2 tr=1500 ms=100%
##    turrets_alive=9 fac=[...]"  how many AI pilots are in each state
##       (an AI state like "lane", with "/evade" or "/fallback" added while
##       it is dodging a turret or falling back; or the pilot's own state
##       "docked", "dead" ... when not flying), what they are going for
##       (intents, plus "home:<why>" for pilots flying home to shop), the
##       hulls in flight, idle pilots (no target and almost still), the
##       treasury, the mothership's hull left, live turrets and the
##       facilities built.
##   "Halcyon drones=6 lost=2 ore=3400 at={...}"  mining drones alive,
##       drones lost, ore delivered, and drones per ore node.
##   "Halcyon siege=mid/assault defending=false bigs=3 ms_hull=... ms_shield=..."
##       the siege lane and phase, the "defend" call, big ships alive, and
##       the mothership's hull and shield points.
## Then "ship deaths by killer: {...}" (killer hull id, unit kind, or
## "rock"), up to 3 "home:" lines (pilots flying home to shop: credits,
## reason, inventory, seconds since launch), and when each team finished
## each facility and research ("unlocks H=id@m:ss, ..."). At the end:
## "TURRETS LOST:"
## and "ROCK DEATHS:" with one line per event.
##
## WHO USES IT: main.gd loads it for --test=match_probe (for --test=<name>
## it loads tests/<name>.gd, adds it after the World and calls setup()). It
## reads PilotAI's state, intent, target, goal, home_reason and timers.

## The running match (set by setup()).
var world: World
## How many game seconds to watch (--secs, default 1500).
var secs := 1500.0
## Game time (seconds) of the last 60-second report.
var last := 0.0
## Game time (seconds) of the last --debug siege report.
var last_siege := 0.0
## One text line per destroyed turret (printed at the end).
var turret_log: Array = []
## Pilot ship deaths by killer: killer text -> count.
var kills_by := {}
## One text line per pilot ship that died flying into a rock.
var rock_log: Array = []


## main.gd calls this once, right after the World is built. Read --secs and
## start listening for turret losses and ship deaths.
func setup(w: World) -> void:
	world = w
	secs = float(Game.opt("secs", 1500.0))
	# A turret died ("signal" = the game calls this function each time;
	# the function is a "lambda", written in place). Write down when, whose,
	# what type, at which node, which team killed it, and which of the
	# killers' ships and how many of their minions were within 2,500.
	Events.turret_destroyed.connect(func(t: Node, by_team: int) -> void:
		var tu := t as Turret
		# The killing team's pilot ships near the turret (their hull ids).
		var near := []
		for s: Ship in world.ships:
			if s.team == by_team and s.alive and s.global_position.distance_to(tu.global_position) < 2500.0:
				near.append(s.hull_id)
		# The killing team's minions near the turret (how many).
		var minions := 0
		for m: Minion in world.minions:
			if m.team == by_team and m.alive and m.global_position.distance_to(tu.global_position) < 2500.0:
				minions += 1
		turret_log.append("%s %s %s at %s by %s (ships near: %s, minions near: %d)" % [Util.clock(world.time), Rules.TEAM_NAMES[tu.team], tu.ttype, tu.node.node_name if tu.node else "?", Rules.TEAM_NAMES[by_team] if by_team >= 0 else "?", near, minions]))
	# A unit died. For pilot ships only: count the killer (its hull id if it
	# was a pilot ship, else its unit kind; "rock" for a collision), and
	# write a line for every rock death (where, in the jungle or not, and
	# what the AI was doing).
	Events.unit_killed.connect(func(u: Node, info: RefCounted) -> void:
		var d := info as DamageInfo
		if (u as Unit).kind != Unit.K_SHIP:
			return
		var k := "?"
		if d.source != null and is_instance_valid(d.source):
			k = Unit.KIND_NAMES[d.source.kind]
			if d.source is Ship:
				k = (d.source as Ship).hull_id
		elif d.kind == Rules.W_COLLISION:
			# Flew into a rock: also log it ("human" when there is no AI).
			k = "rock"
			var s := u as Ship
			var ai: PilotAI = world.pilot_ai.get(s.profile)
			rock_log.append("%s %s %s at %s jungle=%s state=%s" % [Util.clock(world.time), s.hull_id, s.profile.callsign, world.place_name(s.global_position), not world.map.in_open_lane(s.global_position), ai.state if ai else "human"])
		kills_by[k] = int(kills_by.get(k, 0)) + 1)


## Godot calls this every tick. Report every 60 game seconds (and every 15
## with --debug for sieges); at the end, report once more, print the turret
## and rock lists, and quit.
func _physics_process(_dt: float) -> void:
	if world == null:
		return
	if world.time - last >= 60.0:
		last = world.time
		_report()
	if Game.opt("debug", false) and world.time - last_siege >= 15.0:
		last_siege = world.time
		_siege_report()
	# The end: time is up, or a mothership died ("play" = still going).
	if world.time >= secs or world.phase != "play":
		_report()
		print("TURRETS LOST:")
		for l: String in turret_log:
			print("  ", l)
		print("ROCK DEATHS:")
		for l: String in rock_log:
			print("  ", l)
		get_tree().quit()


## Print one report block (see HOW TO READ THE OUTPUT above).
func _report() -> void:
	print("--- probe %s ---" % Util.clock(world.time))
	for t in 2:
		# Step 1: this team's pilots: their states, the hulls flying, and
		# the idle ones (flying, no target, slower than 40 units a second).
		var states := {}
		var hulls := {}
		var idle := 0
		for p: PilotProfile in world.profiles:
			if p.team != t:
				continue
			var ai: PilotAI = world.pilot_ai.get(p)
			var st := p.state
			if p.state == "flying" and ai != null:
				st = ai.state
				if ai.evade_t > 0.0:
					st += "/evade"
				if ai.fallback_t > 0.0:
					st += "/fallback"
				if p.ship != null and is_instance_valid(p.ship):
					hulls[p.ship.hull_id] = int(hulls.get(p.ship.hull_id, 0)) + 1
					if ai.target == null and p.ship.velocity.length() < 40.0:
						idle += 1
			states[st] = int(states.get(st, 0)) + 1
		var ts := world.teams[t]
		var ms := world.mothership(t)
		# Step 2: what the flying AI pilots are going for, plus
		# "home:<reason kind>" (like "home:hull") for those flying home.
		var intents := {}
		for p: PilotProfile in world.profiles:
			var ai2: PilotAI = world.pilot_ai.get(p)
			if p.team == t and ai2 != null and p.state == "flying" and ai2.intent != "":
				intents[ai2.intent] = int(intents.get(ai2.intent, 0)) + 1
			if p.team == t and ai2 != null and p.state == "flying" and ai2.state == "home":
				var key := "home:" + ai2.home_reason.get_slice(":", 0)
				intents[key] = int(intents.get(key, 0)) + 1
		# Step 3: how many live mining drones work each ore node.
		var nodes := {}
		for d: MiningDrone in world.mining_drones:
			if d.team == t and d.alive:
				nodes[d.node_id] = int(nodes.get(d.node_id, 0)) + 1
		print("  %s states=%s intents=%s hulls=%s idle=%d tr=%d ms=%d%% turrets_alive=%d fac=%s" % [Rules.TEAM_NAMES[t], states, intents, hulls, idle, int(ts.treasury), int(ms.hull_frac() * 100.0), _turrets(t), ts.facilities.keys()])
		print("  %s drones=%d lost=%d ore=%d at=%s" % [Rules.TEAM_NAMES[t], world.mining_drone_count(t), ts.drones_lost, int(ts.ore_delivered), nodes])
		# Step 4: big ships alive (size class large or more), and the siege.
		var bigs := 0
		for s: Ship in world.ships:
			if s.team == t and s.alive and s.size_class >= Rules.SIZE_LARGE:
				bigs += 1
		print("  %s siege=%s/%s defending=%s bigs=%d ms_hull=%d ms_shield=%d" % [Rules.TEAM_NAMES[t], ts.siege_lane, ts.siege_phase, ts.defending(world.time), bigs, int(ms.hull), int(ms.shields.total())])
	print("  ship deaths by killer: %s" % kills_by)
	# Who is flying home to shop, and with what (debugging trip frequency).
	# At most 3 pilots are shown.
	var shown := 0
	for p: PilotProfile in world.profiles:
		var ai3: PilotAI = world.pilot_ai.get(p)
		if ai3 == null or p.state != "flying" or ai3.state != "home" or shown >= 3:
			continue
		shown += 1
		# The pilot's inventory slots: item id, or "-" for an empty slot.
		var inv: Array = []
		for s: Dictionary in p.inventory:
			inv.append("-" if s.is_empty() else str(s["id"]))
		print("    home: %s %s cr=%d reason=%s inv=%s since_launch=%ds" % [p.callsign, p.ship.hull_id if p.ship else "?", int(p.credits), ai3.home_reason, inv, int(world.time - ai3.launched_at)])
	print("  unlocks H=%s" % _unlocks(0))
	print("  unlocks C=%s" % _unlocks(1))


## --debug: every 15 s during a siege, where the sieging team's big ships
## and bombers are and what they're doing (finding where assaults stall).
func _siege_report() -> void:
	for t in 2:
		var ts := world.teams[t]
		if ts.siege_lane == "":
			continue
		var ems := world.mothership(1 - t)
		var lines: Array = []
		# Each living ship of this team that is not small (size class
		# small; bombers count anyway) and has an AI brain.
		for s: Ship in world.ships:
			if s.team != t or not s.alive or (s.is_small() and s.hull_id != "bomber"):
				continue
			var ai: PilotAI = world.pilot_ai.get(s.profile)
			if ai == null:
				continue
			# Its target as "name@distance", or "-" for none.
			var tg := "-"
			if ai.target != null and is_instance_valid(ai.target):
				tg = "%s@%d" % [ai.target.display_name, int(s.global_position.distance_to(ai.target.global_position))]
			# The distance to the nearest live enemy turret (INF = none).
			var tur := INF
			for tu: Turret in world.turrets:
				if tu.team != t and tu.alive:
					tur = minf(tur, s.global_position.distance_to(tu.global_position))
			# Hull left, AI state/intent, target, distances from the ship
			# and from its goal to the enemy mothership's hull, the nearest
			# turret, and the place name.
			lines.append("%s %d%% %s/%s tg=%s ms=%d goal_ms=%d tur=%d at=%s" % [s.hull_id, int(s.hull_frac() * 100.0), ai.state, ai.intent, tg,
				int(ems.hull_dist(s.global_position)), int(ems.hull_dist(ai.goal)), int(tur), world.place_name(s.global_position)])
		print("  [%s %s siege %s/%s, enemy ms %d/%d] %s" % [Util.clock(world.time), Rules.TEAM_NAMES[t], ts.siege_lane, ts.siege_phase, int(ems.hull), int(ems.shields.total()), " | ".join(lines)])


## How many live turrets team `t` has.
func _turrets(t: int) -> int:
	var n := 0
	for tu: Turret in world.turrets:
		if tu.team == t and tu.alive:
			n += 1
	return n


## When team `t` finished each facility and research, as text:
## "id@m:ss, id@m:ss, ..." (TeamState.unlock_times).
func _unlocks(t: int) -> String:
	var parts: Array = []
	var ut: Dictionary = world.teams[t].unlock_times
	for k in ut:
		parts.append("%s@%s" % [k, Util.clock(float(ut[k]))])
	return ", ".join(parts)
