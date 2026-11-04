class_name RespawnSiteFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "respawn_site" rule variant (idea
## A5 of the pacing_downtime fork): "Respawn at a forward bay or the
## waypoint". When an AI pilot's wait is over it does not stop at the
## mothership's hangar: its replacement ship appears next to a forward repair
## bay (value "bay") or inside the admiral's waypoint ring (value "waypoint"),
## so the long flight back to the fight disappears. REQ-CHANGE: "pilots have
## to buy personal repair kits at the mothership" (the pilot skips the hangar,
## so it cannot buy kits, modules or gear until it docks later).
##
## HOW IT WORKS: --variant=respawn_site:bay or respawn_site:waypoint. When the
## game says a pilot is back (Events.respawned, sent by MatchRules after the
## respawn is counted for the respawn strain, so strain is unchanged),
## this module handles AI pilots only (a human keeps the hangar):
##   1. It picks a site: for "bay" an anchored friendly repair bay, for
##      "waypoint" the waypoint of the admiral while it lasts. Of the sites
##      with no enemy pilot ship that the team can see within 2,500, it takes
##      the one with the best score: nearest the pilot's lane station
##      (the front of its lane) and, as a tie-breaker, farthest from the
##      enemy pilots (every 2 world units of distance to the nearest visible
##      enemy, up to 5,000, count as 1 unit nearer). The site must also be at
##      least MIN_GAIN (3,000) closer to the station than the mothership's
##      launch point. With no such site the pilot respawns at the mothership
##      as usual.
##   2. It gives the pilot a hull without the hangar (provide_hull()): the
##      hull it flew last if the pilot can pay its normal price and keep 120
##      credits, else a Fighter on the same terms, else the free Scout. The
##      ship has no modules, and no kits or gear are bought; the AI's usual
##      go-home rule (PilotShopping.wants_shopping) decides later when a trip
##      home to shop is worth it.
##   3. It launches the ship (World.launch) and moves it to a free spot 300
##      world units from the site on the side facing the mothership (for the
##      waypoint: 300 units inside the ring's edge) and starts a fresh plan
##      for the pilot's AI brain.
## Usage counters in Game.usage: "forward_respawns" (all), "forward_respawns_bay"
## or "_waypoint", "shopless_respawns" (forward respawns of a pilot that
## carried fewer than 2 repair kits and so missed a purchase),
## "kit_purchases" (every repair kit bought by any pilot, so the report can
## give kit purchases per death).
##
## WHO USES IT: FeatureRegistry installs it. Events.respawned calls
## _on_respawned(); World's tick_hooks call tick().

## The variant key this module belongs to.
const KEY := "respawn_site"
## The site must be at least this much (world units) closer to the pilot's
## lane station than the mothership's launch point.
const MIN_GAIN := 3000.0
## A visible enemy pilot ship within this distance (world units) of a site
## makes it unsafe.
const SAFE_RADIUS := 2500.0
## How far (world units) from a bay the ship appears, and how far inside the
## waypoint ring's edge.
const LANDING_DIST := 300.0
## Credits a pilot keeps unspent when it buys its hull (like PilotShopping).
const RESERVE := 120.0
## Enemy distance beyond which being farther away no longer helps the score
## (world units).
const ENEMY_CAP := 5000.0

## The running match.
var world: World
## "bay" or "waypoint".
var mode := "bay"
## The hull id each pilot flew last: PilotProfile -> String.
var _last_hull := {}
## The repair kits each pilot carried on the previous tick: PilotProfile ->
## int (to count purchases).
var _kits := {}


## Plug the feature into match `w`: listen for respawns and watch the pilots.
func install(w: World) -> void:
	world = w
	mode = Game.variant(KEY)
	if mode != "bay" and mode != "waypoint":
		push_warning("respawn_site: unknown value \"%s\" (use off, bay or waypoint); nothing changed" % mode)
		mode = "bay"
	w.tick_hooks.append(tick)
	Events.respawned.connect(_on_respawned)


## The tick hook (World.tick_hooks): remember each pilot's last hull and
## count repair-kit purchases (a rise in the kits a pilot carries).
func tick(_dt: float) -> void:
	for p: PilotProfile in world.profiles:
		if p.state == "flying" and p.ship != null and is_instance_valid(p.ship):
			_last_hull[p] = p.ship.hull_id
		var kits := p.kit_count()
		var before := int(_kits.get(p, kits))
		if kits > before:
			Game.count_usage("kit_purchases", kits - before)
		_kits[p] = kits


## A pilot's respawn wait is over (Events.respawned): launch an AI pilot at a
## forward site if there is a good one (see HOW IT WORKS).
func _on_respawned(profile: RefCounted) -> void:
	var p := profile as PilotProfile
	if p == null or p.is_human or p.state != "docked" or not world.pilot_ai.has(p):
		return
	var ts := world.teams[p.team]
	var ms := world.mothership(p.team)
	if ms == null or not ms.available():
		return
	var brain := world.pilot_ai[p] as PilotAI
	# Step 1: the best safe site.
	var station := brain.goals.lane_front(brain.goals.lane_id(), p.team)
	var launch_gap := ms.launch_point(p.slot).distance_to(station)
	var site := _best_site(ts, p.team, station, launch_gap)
	if site == Vector2.INF:
		return
	# Step 2: a hull without the hangar, then launch.
	provide_hull(p, ts)
	var ship := world.launch(p)
	if ship == null:
		return
	# Step 3: put the ship at the site and start a fresh plan.
	var toward := ms.global_position
	var pos: Vector2
	if mode == "waypoint":
		var inner := site + (toward - site).normalized() * (Rules.WAYPOINT_RADIUS - LANDING_DIST)
		pos = LandingSpot.find(world, inner, toward, 0.0, ship.radius + 30.0)
	else:
		pos = LandingSpot.find(world, site, toward, LANDING_DIST, ship.radius + 30.0)
	ship.global_position = pos
	ship.rotation = (world.map.mothership_pos[1 - p.team] - pos).angle()
	ship.velocity = Vector2.from_angle(ship.rotation) * 120.0
	ship.controls.aim_point = pos + Vector2.from_angle(ship.rotation) * 2000.0
	ship.controls.face_point = ship.controls.aim_point
	brain._reset_after_launch()
	# Step 4: count it.
	Game.count_usage("forward_respawns")
	Game.count_usage("forward_respawns_" + mode)
	if p.kit_count() < 2:
		Game.count_usage("shopless_respawns")


## The position of the best safe site for a pilot of `team` whose lane
## station is `station`, or Vector2.INF when there is none (see HOW IT WORKS,
## step 1). `launch_gap` is the distance from the mothership's launch point
## to the station.
func _best_site(ts: TeamState, team: int, station: Vector2, launch_gap: float) -> Vector2:
	# Step 1: the candidate positions.
	var sites: Array[Vector2] = []
	if mode == "waypoint":
		if ts.has_waypoint():
			sites.append(ts.waypoint)
	else:
		for b in world.bays:
			if b.team == team and b.alive and b.is_anchored():
				sites.append(b.global_position)
	# Step 2: score the safe ones; lower is better.
	var best := Vector2.INF
	var best_score := INF
	for s in sites:
		var d_enemy := _nearest_enemy_pilot(s, team)
		if d_enemy < SAFE_RADIUS:
			continue
		var d := s.distance_to(station)
		if launch_gap - d < MIN_GAIN:
			continue
		var score := d - 0.5 * minf(d_enemy, ENEMY_CAP)
		if score < best_score:
			best_score = score
			best = s
	return best


## The distance (world units) from `pos` to the nearest enemy pilot ship that
## team `team` can see, or INF when it sees none.
func _nearest_enemy_pilot(pos: Vector2, team: int) -> float:
	var best := INF
	for e: Ship in world.ships:
		if e.team != team and e.alive and e.visible_to(team):
			best = minf(best, e.global_position.distance_to(pos))
	return best


## Give pilot `p` a hull for its next launch without the hangar: the hull it
## flew last, if unlocked and affordable with RESERVE credits left over;
## else a Fighter on the same terms; else the free Scout. Normal prices
## (PilotProfile.buy_hull). No modules, kits or gear.
func provide_hull(p: PilotProfile, ts: TeamState) -> void:
	var want: String = _last_hull.get(p, "fighter")
	if not ts.ship_unlocked(want) or p.credits < float(Ships.HULLS[want]["price"]) + RESERVE:
		want = "fighter" if p.credits >= float(Ships.HULLS["fighter"]["price"]) + RESERVE else "scout"
	if p.hull_id != want:
		p.buy_hull(want, ts)
	if p.hull_id == "":
		p.buy_hull("scout", ts)
