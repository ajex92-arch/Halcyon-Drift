class_name AdmiralOrdersFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "orders" rule variant (fork
## admiral_command, idea F2 "Bounty orders"). The admiral can post a BOUNTY:
## treasury money paid up front and put on one enemy turret or repair bay.
## Whoever of the team's pilots helps destroy that target shares the money.
## It turns spare treasury money into an objective that pilots chase.
## (It is the alternative to the economy fork's idea C2(b); at most one of
## them should merge.)
##
## HOW IT WORKS:
##   - The order "bounty" (CommandOrders, a button and a map tool for a human
##     admiral): click near an enemy turret or repair bay that the team has
##     seen. The price is 10% of the treasury, at least 100 and at most 1,000
##     credits (cost_of), taken at once. At most 2 bounties of a team can
##     be active, a target carries only one, and the order recharges for
##     60 s. A gold diamond marks the target on the map and minimap for BOTH
##     teams, with the amount.
##   - A bounty lasts 180 s. If it runs out (or its target disappears)
##     half of the amount goes back to the treasury (REFUND).
##   - When the target is destroyed, the amount is split equally between
##     the team's pilots who damaged it in the last 15 s or who fly within
##     2,500 units of it (SPLIT_WINDOW, SPLIT_RANGE). Each gets credits with
##     the reason "bounty". If nobody qualifies, half goes back to the
##     treasury.
##   - The AI admiral (once a second, only a computer admiral): every 60 s,
##     while its treasury is over 3,000, it posts a bounty on the weakest
##     (lowest hull) enemy turret that the team has seen on the lane it is
##     pushing or sieging (ai_think). The amount is the same 10% (cap 1,000).
##   - AI pilots follow the bounty (a World.push_weight_hooks entry): an
##     enemy turret with our bounty counts as twice as near for a pilot
##     whose own lane it is. Flex pilots and junglers (the roaming seats)
##     within 8,000 of a bounty target divert to it: they are given a hold
##     point next to it (PilotAI.hold_point) until the bounty ends or they
##     get hurt.
## Usage counters (Game.count_usage): bounties_posted, bounties_claimed (a
## bounty paid out to pilots), bounties_expired, bounty_diverts (a roaming
## pilot sent to a target).
##
## WHO USES IT: FeatureRegistry installs it for --variant=orders:on. The
## scripted test (tests/admiral_fork_probe.gd) calls post_bounty().

## The variant key this module belongs to.
const KEY := "orders"
## The smallest bounty (credits).
const MIN_BOUNTY := 100.0
## The largest bounty (credits).
const MAX_BOUNTY := 1000.0
## The share of the treasury a bounty costs (0.1 = 10%).
const SHARE := 0.10
## At most this many bounties of a team are active.
const MAX_ACTIVE := 2
## How long (seconds) a bounty lasts.
const LIFETIME := 180.0
## How much of the amount an unclaimed bounty gives back (0.5 = half).
const REFUND := 0.5
## Pay-out rule: a pilot who damaged the target in the last this many
## seconds gets a share...
const SPLIT_WINDOW := 15.0
## ...and so does a pilot who flies within this many world units of it.
const SPLIT_RANGE := 2500.0
## How far from the clicked spot (world units) a target may be.
const PICK_RADIUS := 700.0
## The order's cooldown in seconds.
const COOLDOWN := 60.0
## The AI posts only while its treasury is over this (credits).
const AI_MIN_TREASURY := 3000.0
## The AI posts at most once in this many seconds.
const AI_EVERY := 60.0
## Roaming pilots (flex and jungle seats) within this distance (world units)
## of a bounty target divert to it...
const DIVERT_RANGE := 8000.0
## ...and stop when their hull fraction (0..1) is below this.
const DIVERT_MIN_HULL := 0.6
## The gold of the marker.
const GOLD := Color(1.0, 0.82, 0.25)

## The match this module runs in.
var world: World
## The active bounties: each {"team" (who paid), "target" (the Unit), "uid"
## (its id), "amount" (credits), "until" (match time it runs out)}.
var bounties: Array = []
## Seconds until the AI admirals think again (once a second).
var _think_t := 1.0
## Per team: seconds until the AI may post its next bounty.
var _ai_t: Array = [AI_EVERY, AI_EVERY]
## The roaming pilots now diverted: PilotProfile -> true.
var diverted := {}
## Seconds until the next divert check.
var _divert_t := 2.0


## Plug the bounty orders into match `w` (FeatureRegistry calls this once).
func install(w: World) -> void:
	world = w
	CommandOrders.add(world, {
		"id": "bounty", "label": "Bounty", "cost_fn": _price, "cooldown": COOLDOWN,
		"needs_point": true, "radius": PICK_RADIUS, "color": GOLD,
		"hint": "Click an enemy turret or repair bay you have seen: your pilots share the bounty when it is destroyed",
		"tip": "10%% of the treasury (%d to %d credits) is paid now and put on an enemy turret or repair bay. Pilots who help destroy it share it. At most %d active; %d s each; unclaimed bounties refund half." % [int(MIN_BOUNTY), int(MAX_BOUNTY), MAX_ACTIVE, int(LIFETIME)],
		"help": "Bounty (10%% of the treasury, %d to %d credits, every %d s): click an enemy turret or repair bay your team has seen. A gold diamond marks it for both teams. Your pilots who damage it or fly within %d units when it is destroyed share the money; AI pilots on that lane push it first. After %d s an unclaimed bounty refunds half. At most %d at a time." % [int(MIN_BOUNTY), int(MAX_BOUNTY), int(COOLDOWN), int(SPLIT_RANGE), int(LIFETIME), MAX_ACTIVE],
		"blocker": _blocker, "run": _run, "tag": _tag,
	})
	world.push_weight_hooks.append(_push_weight)
	world.tick_hooks.append(_tick)
	Events.unit_killed.connect(_on_killed)
	world.tree_exiting.connect(func() -> void:
		if Events.unit_killed.is_connected(_on_killed):
			Events.unit_killed.disconnect(_on_killed))


## The price of a bounty for `team`: SHARE of its treasury, between
## MIN_BOUNTY and MAX_BOUNTY.
func _price(team: int) -> float:
	return clampf(world.teams[team].treasury * SHARE, MIN_BOUNTY, MAX_BOUNTY)


## The enemy turret or repair bay of `team` nearest to `p` within
## PICK_RADIUS that `team` has seen (and that is alive and has no bounty
## yet), or null.
func pick_target(team: int, p: Vector2) -> Unit:
	var best: Unit = null
	var best_d := PICK_RADIUS
	var candidates: Array = []
	candidates.append_array(world.turrets)
	candidates.append_array(world.bays)
	for u: Unit in candidates:
		if not u.alive or u.team != 1 - team or (u.seen_mask & (1 << team)) == 0:
			continue
		var d := u.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = u
	return best


## Does a live bounty already sit on unit `u`?
func has_bounty(u: Unit) -> bool:
	for b: Dictionary in bounties:
		if int(b["uid"]) == u.uid:
			return true
	return false


## How many active bounties `team` has paid.
func active_count(team: int) -> int:
	var n := 0
	for b: Dictionary in bounties:
		if int(b["team"]) == team:
			n += 1
	return n


## The order's own rules: a target near the clicked spot that has no bounty
## yet, and a free bounty slot.
func _blocker(team: int, p: Vector2) -> String:
	if active_count(team) >= MAX_ACTIVE:
		return "Two bounties are already active"
	var t := pick_target(team, p)
	if t == null:
		return "Click an enemy turret or repair bay that your team has seen"
	if has_bounty(t):
		return "That target already has a bounty"
	return ""


## Carry out the order: put the bounty on the target near `p`. `paid` is
## the amount CommandOrders.run() has just taken from the treasury.
func _run(team: int, p: Vector2, paid: float) -> void:
	_post(team, pick_target(team, p), paid)


## Put a bounty of `amount` credits (already paid by the caller) from `team`
## on `target`: remember it, mark it on the map for both teams and tell
## everyone.
func _post(team: int, target: Unit, amount: float) -> void:
	bounties.append({"team": team, "target": target, "uid": target.uid, "amount": amount, "until": world.time + LIFETIME})
	CommandOrders.add_mark(world, {"pos": target.global_position, "unit": target, "r": target.radius + 120.0, "col": GOLD,
		"until": world.time + LIFETIME, "teams": [0, 1], "label": "Bounty %d" % int(amount), "kind": "gold"})
	Events.feed.emit("%s posts a %d credit bounty on a %s at %s." % [Rules.TEAM_NAMES[team], int(amount), "turret" if target.kind == Unit.K_TURRET else "repair bay", world.place_name(target.global_position)], "info", -1)
	Game.count_usage("bounties_posted")


## Post a bounty of `amount` credits on `target` for `team`, paying it now
## from the treasury, outside the order desk (the scripted test uses it).
## Returns "" or the reason it can't. The amount must be between MIN_BOUNTY
## and MAX_BOUNTY.
func post_bounty(team: int, target: Unit, amount: float) -> String:
	if target == null or not target.alive or target.team != 1 - team or not (target.kind == Unit.K_TURRET or target.kind == Unit.K_BAY):
		return "A bounty goes on an enemy turret or repair bay"
	if amount < MIN_BOUNTY or amount > MAX_BOUNTY:
		return "A bounty is %d to %d credits" % [int(MIN_BOUNTY), int(MAX_BOUNTY)]
	if active_count(team) >= MAX_ACTIVE:
		return "Two bounties are already active"
	if has_bounty(target):
		return "That target already has a bounty"
	if not world.teams[team].spend(amount):
		return "Not enough in the team treasury"
	_post(team, target, amount)
	return ""


## Top-bar tag: "BOUNTY 2" next to the team that has bounties active.
func _tag(team: int, _viewer: int) -> String:
	var n := active_count(team)
	return "BOUNTY x%d" % n if n > 0 else ""


## Hook for AI pilots choosing a turret to push (World.push_weight_hooks):
## an enemy turret that carries our team's bounty counts as half as far for a
## pilot whose own lane it is. Everything else keeps its score.
func _push_weight(ship: Ship, t: Unit, score: float) -> float:
	for b: Dictionary in bounties:
		if int(b["uid"]) == t.uid and int(b["team"]) == ship.team:
			var brain: PilotAI = world.pilot_ai.get(ship.profile)
			var node: ResourceNode = (t as Turret).node if t is Turret else null
			if brain != null and node != null and node.lane == brain.goals.lane_id():
				return score * 0.5
	return score


# --- the bounty life ------------------------------------------------------------------------

## A unit died (Events.unit_killed): if it carried a bounty, pay it out.
func _on_killed(unit: Node, _info: RefCounted) -> void:
	var u := unit as Unit
	if u == null:
		return
	for b: Dictionary in bounties:
		if int(b["uid"]) == u.uid:
			bounties.erase(b)
			_pay_out(b, u)
			return


## Pay the bounty `b` whose target `victim` has just been destroyed: split
## it equally between the paying team's pilots who damaged it lately or fly
## near it; with nobody, REFUND of it goes back to the treasury.
func _pay_out(b: Dictionary, victim: Unit) -> void:
	var team := int(b["team"])
	var amount := float(b["amount"])
	# Step 1: who qualifies (a Dictionary used as a set).
	var who := {}
	var damaged := Economy.contributors(world, victim, SPLIT_WINDOW, 0.0)
	for p: PilotProfile in damaged:
		if p.team == team:
			who[p] = true
	for s: Ship in world.ships:
		if s.team == team and s.alive and s.profile != null and s.global_position.distance_to(victim.global_position) <= SPLIT_RANGE:
			who[s.profile] = true
	# Step 2: pay them, or refund.
	if who.is_empty():
		world.teams[team].treasury += amount * REFUND
		return
	var each := amount / float(who.size())
	for p: PilotProfile in who:
		p.earn(each, "bounty")
	Game.count_usage("bounties_claimed")
	Events.feed.emit("The %d credit bounty is paid out to %d pilots." % [int(amount), who.size()], "team", team)


# --- the tick --------------------------------------------------------------------------------------

## Every tick (a World.tick_hooks entry): expire old bounties, let the AI
## admirals think and divert the roaming pilots.
func _tick(dt: float) -> void:
	# Step 1: once a second, expire bounties (refund half) and drop the ones
	# whose target vanished without dying (the unit is gone).
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = 1.0
		var keep: Array = []
		for b: Dictionary in bounties:
			var tgt: Variant = b["target"]
			var gone: bool = tgt == null or not is_instance_valid(tgt) or not (tgt as Unit).alive
			if gone or world.time >= float(b["until"]):
				world.teams[int(b["team"])].treasury += float(b["amount"]) * REFUND
				Game.count_usage("bounties_expired")
			else:
				keep.append(b)
		bounties = keep
		for t in 2:
			_ai_think(t)
	# Step 2: every 2 s, send the roaming pilots to targets near them.
	_divert_t -= dt
	if _divert_t <= 0.0:
		_divert_t = 2.0
		_divert()


## The computer admiral of `team` thinks about a bounty (once a second, but
## it posts at most every AI_EVERY seconds): with the treasury over
## AI_MIN_TREASURY, put one on the weakest visible enemy turret on the lane
## it pushes or sieges.
func _ai_think(team: int) -> void:
	var ai: AdmiralAI = world.admiral_ai[team]
	_ai_t[team] = float(_ai_t[team]) - 1.0
	if not AdmiralWeak.ai_acts(world, team) or float(_ai_t[team]) > 0.0:
		return
	var ts := world.teams[team]
	if ts.treasury < AI_MIN_TREASURY or active_count(team) >= MAX_ACTIVE or CommandOrders.ready_in(world, "bounty", team) > 0.0:
		return
	# Step 1: the lane: the siege lane while one runs, else the push lane.
	var lane := ts.siege_lane if ts.siege_lane != "" else ai.lanes.push_lane()
	if lane == "":
		return
	# Step 2: the weakest (lowest hull) built enemy turret we have seen there.
	var best: Turret = null
	for tu: Turret in world.turrets:
		if tu.team != 1 - team or not tu.alive or not tu.is_built() or tu.node == null or tu.node.lane != lane:
			continue
		if (tu.seen_mask & (1 << team)) == 0 or has_bounty(tu):
			continue
		if best == null or tu.hull < best.hull:
			best = tu
	if best == null:
		return
	# Step 3: give the order the way a human does (the click lands on it).
	if CommandOrders.run(world, "bounty", team, best.global_position) == "":
		_ai_t[team] = AI_EVERY


## Send roaming pilots (flex and jungle seats) that are within DIVERT_RANGE
## of an active bounty target to it, and release the ones that no longer
## qualify. A diverted pilot gets a hold point 1,200 units short of the
## target, on its side (PilotAI.hold_point).
func _divert() -> void:
	# Step 1: which roaming pilots should be diverted now: profile -> point.
	var want := {}
	for b: Dictionary in bounties:
		var tgt: Unit = b["target"]
		for p: PilotProfile in world.pilot_ai:
			if p.team != int(b["team"]) or not (p.role == "flex" or p.role == "jungle") or p.state != "flying":
				continue
			var s := p.ship
			if s == null or not is_instance_valid(s) or not s.alive or s.hull_frac() < DIVERT_MIN_HULL:
				continue
			var d := s.global_position.distance_to(tgt.global_position)
			if d > DIVERT_RANGE:
				continue
			var brain: PilotAI = world.pilot_ai[p]
			if brain.state == "retreat" or brain.state == "home":
				continue
			want[p] = tgt.global_position + (s.global_position - tgt.global_position).normalized() * 1200.0
	# Step 2: divert them.
	for p in want:
		var brain: PilotAI = world.pilot_ai[p]
		if not diverted.has(p):
			diverted[p] = true
			Game.count_usage("bounty_diverts")
		brain.hold_point = want[p]
		if brain.state == "jungle":
			brain.state = "lane"
	# Step 3: release the others.
	for p in diverted.keys():
		if want.has(p):
			continue
		diverted.erase(p)
		var brain2: PilotAI = world.pilot_ai.get(p)
		if brain2 != null:
			brain2.hold_point = Vector2.INF
			if p.role == "jungle" and brain2.state == "lane":
				brain2.state = "jungle"
