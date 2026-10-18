class_name AdmiralAssetsFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "assets" rule variant (fork
## admiral_command, idea F1 "Command assets"). It gives the admiral new
## orders to spend the treasury on all match long, after the tech tree is
## done, and each order helps the pilots fight right now:
##   Sensor Sweep   250 credits, cooldown 60 s. A new sight source of radius
##                  3,500 at a spot the team can see, for 8 s. It sees as
##                  every unit does, so rocks block it (the "on" and "full"
##                  values). Our pilots then see (and shoot) what is there.
##   Supply Drop    400 credits, cooldown 90 s. Four repair drones
##                  (SupplyDrone) fly from the mothership at 900 world units
##                  per second to a spot the team can see and mend friendly
##                  pilot ships within 1,200 of it for 8 s, at the usual bay
##                  drone rate. The drones can be shot down (10 credits).
##   Barrage        600 credits, cooldown 150 s (the "full" value only). A
##                  spot within 12,000 of our mothership: a red circle shows
##                  on the map of BOTH teams for 3 s, then every enemy unit
##                  inside 500 takes 600 damage (the same to everything; the
##                  motherships are not hit). Kills are credited to nobody:
##                  no pilot bounty and no assist, the admiral's team simply
##                  gets the kill (a non-pilot kill in the fun probe).
## The values of the variant (Rules.VARIANT_DEFAULTS "assets"):
##   "off"   (default) none of this exists.
##   "on"    Sweep and Supply.
##   "full"  Sweep, Supply and Barrage.
##   "xray"  like "on", but the Sweep sees through asteroids (it reuses the
##           Scout Ping's reveal circle, Vision.reveal). REQ-CHANGE: the
##           requirement "players cannot see through asteroids".
##
## HOW IT WORKS: install() registers the orders with CommandOrders (so a
## human admiral gets buttons and map tools, with a news line, a minimap
## mark, a top-bar tag and a help line for each), adds one AdmiralAssetsAI
## per team (the AI admiral's use of the orders) and a tick hook that runs
## the AI, cleans up old sweeps and fires barrages whose 3 seconds are up.
## Usage counters (Game.count_usage): assets_sweep, assets_supply,
## assets_barrage (orders given), and assets_barrage_hits / assets_barrage_kills
## (enemy units hit and destroyed by barrages).
##
## WHO USES IT: FeatureRegistry installs it for --variant=assets:on|full|xray.
## The AI admiral side lives in AdmiralAssetsAI.

## The variant key this module belongs to.
const KEY := "assets"
## The supply drone's scene (the repair drone's scene with SupplyDrone's script).
const SUPPLY_SCENE := preload("res://scenes/entities/supply_drone.tscn")
## Sensor Sweep: the price in credits.
const SWEEP_COST := 250.0
## Sensor Sweep: seconds before the same team may sweep again.
const SWEEP_COOLDOWN := 60.0
## Sensor Sweep: the sight radius in world units.
const SWEEP_RADIUS := 3500.0
## Sensor Sweep: how many seconds the sensor lasts.
const SWEEP_TIME := 8.0
## Supply Drop: the price in credits.
const SUPPLY_COST := 400.0
## Supply Drop: seconds before the same team may drop again.
const SUPPLY_COOLDOWN := 90.0
## Supply Drop: how many repair drones fly out.
const SUPPLY_DRONES := 4
## Supply Drop: the radius around the spot (world units) in which the
## drones mend ships (SupplyDrone.WORK_RANGE).
const SUPPLY_RADIUS := 1200.0
## Barrage: the price in credits.
const BARRAGE_COST := 600.0
## Barrage: seconds before the same team may fire again.
const BARRAGE_COOLDOWN := 150.0
## Barrage: how far from our mothership's centre the spot may be (world units).
const BARRAGE_RANGE := 12000.0
## Barrage: seconds between the red warning circle and the hit.
const BARRAGE_DELAY := 3.0
## Barrage: the damage every enemy unit in the circle takes.
const BARRAGE_DAMAGE := 600.0
## Barrage: the radius of the blast in world units.
const BARRAGE_RADIUS := 500.0

## The match this feature runs in.
var world: World
## Which value of the variant is on: "on", "full" or "xray".
var mode := "on"
## Barrages that were ordered and have not landed yet: each {"team", "pos",
## "at" (the match time it lands)}.
var pending: Array = []
## The AI admiral's use of the orders, one per team (AdmiralAssetsAI).
var ai: Array = []
## Seconds until each team's sweeps list is cleaned (counts down).
var _clean_t := 0.0


## Plug the orders into match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	mode = Game.variant(KEY)
	if not (mode in ["on", "full", "xray"]):
		push_warning("assets: unknown value \"%s\" (use off, on, full or xray); nothing changed" % mode)
		return
	# Step 1: the orders (a button, a map tool, a mark, a tag and a help line
	# each; CommandOrders).
	CommandOrders.add(world, {
		"id": "sweep", "label": "Sensor Sweep", "cost": SWEEP_COST, "cooldown": SWEEP_COOLDOWN,
		"needs_point": true, "radius": SWEEP_RADIUS, "color": Palette.VEIL,
		"hint": "Click a spot your team can see to light up %d units around it for %d s" % [int(SWEEP_RADIUS), int(SWEEP_TIME)],
		"tip": "%d credits, %d s cooldown. A sight source of radius %d at a spot you can see, for %d s.%s" % [int(SWEEP_COST), int(SWEEP_COOLDOWN), int(SWEEP_RADIUS), int(SWEEP_TIME), " It sees through asteroids." if mode == "xray" else " Rocks still block its sight."],
		"help": "Sensor Sweep (%d credits, every %d s): pick a spot your team can see. For %d seconds a sensor there sees %d units around it, so your pilots can spot and shoot what hides there.%s" % [int(SWEEP_COST), int(SWEEP_COOLDOWN), int(SWEEP_TIME), int(SWEEP_RADIUS), " This version sees through asteroids." if mode == "xray" else " Asteroids block it like any sight."],
		"blocker": _sweep_blocker, "run": _sweep_run, "tag": _sweep_tag,
	})
	CommandOrders.add(world, {
		"id": "supply", "label": "Supply Drop", "cost": SUPPLY_COST, "cooldown": SUPPLY_COOLDOWN,
		"needs_point": true, "radius": SUPPLY_RADIUS, "color": Palette.REPAIR,
		"hint": "Click a spot your team can see: four repair drones fly there and mend ships for %d s" % int(SupplyDrone.WORK_TIME),
		"tip": "%d credits, %d s cooldown. %d repair drones fly from the mothership (900 u/s) and mend friendly pilot ships within %d of the spot for %d s." % [int(SUPPLY_COST), int(SUPPLY_COOLDOWN), SUPPLY_DRONES, int(SUPPLY_RADIUS), int(SupplyDrone.WORK_TIME)],
		"help": "Supply Drop (%d credits, every %d s): pick a spot your team can see. Four repair drones leave the mothership and fly there fast; for %d seconds they mend friendly pilot ships within %d units, like a repair bay's drones. Enemies can shoot them down." % [int(SUPPLY_COST), int(SUPPLY_COOLDOWN), int(SupplyDrone.WORK_TIME), int(SUPPLY_RADIUS)],
		"blocker": _supply_blocker, "run": _supply_run, "tag": _supply_tag,
	})
	if mode == "full":
		CommandOrders.add(world, {
			"id": "barrage", "label": "Barrage", "cost": BARRAGE_COST, "cooldown": BARRAGE_COOLDOWN,
			"needs_point": true, "radius": BARRAGE_RADIUS, "color": Color(1.0, 0.2, 0.15),
			"hint": "Click a spot within %d of your mothership: a red circle shows to BOTH teams for %d s, then it takes %d damage" % [int(BARRAGE_RANGE), int(BARRAGE_DELAY), int(BARRAGE_DAMAGE)],
			"tip": "%d credits, %d s cooldown. The spot must be within %d of your mothership. Both teams see a red circle for %d s, then every enemy unit inside %d takes %d damage." % [int(BARRAGE_COST), int(BARRAGE_COOLDOWN), int(BARRAGE_RANGE), int(BARRAGE_DELAY), int(BARRAGE_RADIUS), int(BARRAGE_DAMAGE)],
			"help": "Mothership Barrage (%d credits, every %d s): pick a spot within %d units of your mothership. A red circle shows on BOTH teams' maps for %d seconds (the enemy can fly out of it), then every enemy unit within %d units takes %d damage. Enemy motherships are not hit." % [int(BARRAGE_COST), int(BARRAGE_COOLDOWN), int(BARRAGE_RANGE), int(BARRAGE_DELAY), int(BARRAGE_RADIUS), int(BARRAGE_DAMAGE)],
			"blocker": _barrage_blocker, "run": _barrage_run, "tag": _barrage_tag,
		})
	# Step 2: the AI admiral's use of them, and the tick hook.
	for t in 2:
		ai.append(AdmiralAssetsAI.new(world, t))
	world.tick_hooks.append(_tick)


# --- Sensor Sweep ---------------------------------------------------------------------------

## Why a sweep can't go at `p`: the spot must be where `team` can see now.
func _sweep_blocker(team: int, p: Vector2) -> String:
	if not world.vision.is_visible(team, p):
		return "Aim the sweep at a spot your team can see right now"
	return ""


## Carry out a sweep for `team` at `p`: a sight source for SWEEP_TIME seconds
## (rocks block it), or with "xray" a reveal circle that ignores rocks.
func _sweep_run(team: int, p: Vector2, _paid: float) -> void:
	if mode == "xray":
		world.vision.reveal(team, p, SWEEP_RADIUS, SWEEP_TIME)
	else:
		world.vision_sources.append({"team": team, "pos": p, "r": SWEEP_RADIUS, "until": world.time + SWEEP_TIME})
	CommandOrders.add_mark(world, {"pos": p, "r": SWEEP_RADIUS, "col": Palette.VEIL, "until": world.time + SWEEP_TIME,
		"teams": [team], "label": "Sweep", "kind": "ring"})
	Events.feed.emit("The %s admiral sweeps %s with sensors." % [Rules.TEAM_NAMES[team], world.place_name(p)], "team", team)
	Game.count_usage("assets_sweep")


## Top-bar tag: "SWEEP 5s" on our own side while a sweep runs.
func _sweep_tag(team: int, viewer: int) -> String:
	if viewer != team:
		return ""
	for m: Dictionary in world.command.marks:
		if str(m.get("label", "")) == "Sweep" and (m["teams"] as Array).has(team):
			return "SWEEP %ds" % int(ceil(float(m["until"]) - world.time))
	return ""


# --- Supply Drop ----------------------------------------------------------------------------

## Why a supply drop can't go at `p`: the spot must be where `team` can see
## now, and the mothership must be able to launch.
func _supply_blocker(team: int, p: Vector2) -> String:
	if not world.vision.is_visible(team, p):
		return "Aim the drop at a spot your team can see right now"
	var ms := world.mothership(team)
	if ms == null or not ms.available():
		return "The mothership can't launch drones right now"
	return ""


## Carry out a drop for `team` at `p`: SUPPLY_DRONES supply drones leave the
## mothership's launch points for the spot.
func _supply_run(team: int, p: Vector2, _paid: float) -> void:
	var ms := world.mothership(team)
	for i in SUPPLY_DRONES:
		var d: SupplyDrone = SUPPLY_SCENE.instantiate()
		world.registry.attach(d)
		d.setup_supply(world, ms, team, ms.launch_point(i), p)
		world.registry.index(d)
	CommandOrders.add_mark(world, {"pos": p, "r": SUPPLY_RADIUS, "col": Palette.REPAIR, "until": world.time + 20.0,
		"teams": [team], "label": "Supply", "kind": "ring"})
	Events.feed.emit("The %s admiral sends a supply drop to %s." % [Rules.TEAM_NAMES[team], world.place_name(p)], "team", team)
	Game.count_usage("assets_supply")


## Top-bar tag: "SUPPLY" on our own side while a drop's mark is up.
func _supply_tag(team: int, viewer: int) -> String:
	if viewer != team:
		return ""
	for m: Dictionary in world.command.marks:
		if str(m.get("label", "")) == "Supply" and (m["teams"] as Array).has(team):
			return "SUPPLY %ds" % int(ceil(float(m["until"]) - world.time))
	return ""


# --- Barrage ------------------------------------------------------------------------------------

## Why a barrage can't go at `p`: it must be within BARRAGE_RANGE of our
## mothership's centre, and the mothership must be alive.
func _barrage_blocker(team: int, p: Vector2) -> String:
	var ms := world.mothership(team)
	if ms == null or not ms.alive:
		return "No mothership to fire from"
	if ms.global_position.distance_to(p) > BARRAGE_RANGE:
		return "Too far: a barrage reaches %d units from your mothership" % int(BARRAGE_RANGE)
	return ""


## Carry out a barrage for `team` at `p`: warn both teams with a red circle
## now; _tick() lands it BARRAGE_DELAY seconds later.
func _barrage_run(team: int, p: Vector2, _paid: float) -> void:
	pending.append({"team": team, "pos": p, "at": world.time + BARRAGE_DELAY})
	CommandOrders.add_mark(world, {"pos": p, "r": BARRAGE_RADIUS, "col": Color(1.0, 0.2, 0.15), "until": world.time + BARRAGE_DELAY,
		"teams": [0, 1], "label": "BARRAGE", "kind": "fill"})
	Events.feed.emit("%s Barrage incoming at %s!" % [Rules.TEAM_NAMES[team], world.place_name(p)], "info", -1)
	Game.count_usage("assets_barrage")


## Top-bar tag: "BARRAGE 2s" on the firing side's name, for both teams.
func _barrage_tag(team: int, _viewer: int) -> String:
	for b: Dictionary in pending:
		if int(b["team"]) == team:
			return "BARRAGE %ds" % int(ceil(float(b["at"]) - world.time))
	return ""


## The shells land at `pos` for `team`: every enemy unit within
## BARRAGE_RADIUS takes BARRAGE_DAMAGE (kind "pure": the same to everything,
## with nobody named as the attacker). The motherships are not in
## World.units, so they are not hit.
func _land(team: int, pos: Vector2) -> void:
	var enemy := Rules.enemy_of(team)
	# Step 1: choose the victims first (units die and leave World.units
	# while we hit them).
	var victims: Array = []
	for u: Unit in world.units:
		if u.alive and u.team == enemy and u.global_position.distance_to(pos) <= BARRAGE_RADIUS + u.radius:
			victims.append(u)
	# Step 2: hit each one.
	for u: Unit in victims:
		var info := DamageInfo.new()
		info.amount = BARRAGE_DAMAGE
		info.kind = Rules.W_PURE
		info.source_team = team
		info.from_pos = pos
		world.combat.apply_damage(u, info)
		Game.count_usage("assets_barrage_hits")
		if not u.alive:
			Game.count_usage("assets_barrage_kills")
	world.effects.puff(pos, Color(1.0, 0.45, 0.2), 24)


# --- the tick ------------------------------------------------------------------------------------

## Every tick (a World.tick_hooks entry): land barrages that are due, let the
## AI admirals think, and every second drop the sweeps and marks that ran
## out.
func _tick(dt: float) -> void:
	# Step 1: barrages whose warning is over land now.
	if not pending.is_empty():
		var rest: Array = []
		for b: Dictionary in pending:
			if world.time >= float(b["at"]):
				_land(int(b["team"]), b["pos"])
			else:
				rest.append(b)
		pending = rest
	# Step 2: the AI admirals' thinking (each team once a second).
	for a: AdmiralAssetsAI in ai:
		a.tick(dt)
	# Step 3: once a second, forget finished sweeps and marks.
	_clean_t -= dt
	if _clean_t <= 0.0:
		_clean_t = 1.0
		var keep: Array = []
		for sv: Dictionary in world.vision_sources:
			if world.time < float(sv["until"]):
				keep.append(sv)
		world.vision_sources = keep
		CommandOrders.prune(world)
