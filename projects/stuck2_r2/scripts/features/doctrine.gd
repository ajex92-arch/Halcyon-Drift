class_name DoctrineFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C5, Fleet Doctrine (variant
## doctrine:on): a repeatable research for the admiral, so a rich treasury
## always has something to buy. FLAG for the user: this is a repeatable
## money sink (up to 10 levels); the progress notes left sinks to the user.
##
## HOW IT WORKS: the admiral may research "Fleet Doctrine" again and again,
## up to level 10. Level n+1 costs 1,500 x 1.35^n credits from the treasury
## and takes 45 s (it needs the Research Module, like other research, and
## only one level is under way at a time). Each finished level gives every
## friendly PILOT ship +2% maximum hull and +3% shield regeneration
## (ShipStats reads TeamState.doctrine_level and the two per-level numbers
## below). Minions, turrets and the mothership are not changed.
## A human admiral buys it with a button on the Mothership tab of the admiral
## board (AdmiralBoardMothership). The AI admiral buys the next level
## whenever the treasury holds the cost plus 1,000 after reserving the cost
## of the next step of its normal build plan (so the plan still comes
## first). Counted in Game.usage as "doctrine_levels" (levels finished) and
## "doctrine_credits".
##
## WHO USES IT: FeatureRegistry installs it for --variant=doctrine:on.
## ShipStats reads HULL_PER_LEVEL and REGEN_PER_LEVEL; AdmiralBoardMothership
## calls build_card() and refresh_card().

## The variant key.
const KEY := "doctrine"
## Extra maximum hull per level, as a fraction (0.02 = +2%).
const HULL_PER_LEVEL := 0.02
## Extra shield regeneration per level, as a fraction (0.03 = +3%).
const REGEN_PER_LEVEL := 0.03
## The highest level.
const MAX_LEVEL := 10
## The price of level 1, in credits.
const BASE_COST := 1500.0
## Each level costs this many times the one before.
const GROWTH := 1.35
## Seconds one level takes.
const RESEARCH_TIME := 45.0
## The AI keeps this many credits beyond the price.
const AI_MARGIN := 1000.0

## The match.
var world: World
## Seconds left on the level under way, per team (-1 = none under way).
var left := [-1.0, -1.0]
## Seconds until the AI's next look.
var _ai_t := 0.0


## Switch the match to this idea.
func install(w: World) -> void:
	world = w
	if Game.variant(KEY) != "on":
		push_warning("doctrine: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	w.tick_hooks.append(_tick)


## The running match's doctrine feature, or null when it is off.
static func current() -> DoctrineFeature:
	var w := Game.world as World
	if w == null:
		return null
	return w.features.get(KEY) as DoctrineFeature


## What the next level costs for a team that has finished `level` levels.
static func cost_for(level: int) -> float:
	return BASE_COST * pow(GROWTH, float(level))


## Why team `team` cannot start the next level now, or "" if it can: below
## level 10, none under way, the Research Module built, and the treasury.
func blocker(team: int) -> String:
	var ts: TeamState = world.teams[team]
	if ts.doctrine_level >= MAX_LEVEL:
		return "Doctrine is at its highest level"
	if float(left[team]) >= 0.0:
		return "A level is already under way"
	if not ts.facilities.has("research"):
		return "Needs the Research Module"
	var price := cost_for(ts.doctrine_level)
	if not ts.can_afford(price):
		return "Not enough in the team treasury (%d short)" % int(ceil(price - ts.treasury))
	return ""


## Start the next level for `team`, paying from its treasury. Returns "" or
## why not.
func start(team: int) -> String:
	var b := blocker(team)
	if b != "":
		return b
	var ts: TeamState = world.teams[team]
	var price := cost_for(ts.doctrine_level)
	ts.spend(price)
	left[team] = RESEARCH_TIME
	Game.count_usage("doctrine_credits", int(price))
	return ""


## World tick hook: count down each team's level, finish it, and let the AI
## admiral buy.
func _tick(dt: float) -> void:
	for team in 2:
		if float(left[team]) < 0.0:
			continue
		var ts: TeamState = world.teams[team]
		var ms := world.mothership(team)
		# Like other research, it only advances while the mothership lives and
		# the Research Module is built.
		if ms == null or not ms.alive or not ts.facilities.has("research"):
			continue
		left[team] = float(left[team]) - dt
		if float(left[team]) <= 0.0:
			left[team] = -1.0
			ts.doctrine_level += 1
			# Make every pilot ship of the team work out its stats again.
			for s: Ship in world.ships:
				if s.team == team:
					s.stats_dirty = true
			Game.count_usage("doctrine_levels")
			Events.feed.emit("Fleet Doctrine level %d finished: pilot ships +%d%% hull, +%d%% shield regeneration." % [ts.doctrine_level, int(round(HULL_PER_LEVEL * 100.0 * ts.doctrine_level)), int(round(REGEN_PER_LEVEL * 100.0 * ts.doctrine_level))], "team", team)
	# The AI admirals, once a second.
	_ai_t -= dt
	if _ai_t > 0.0:
		return
	_ai_t = 1.0
	for team in 2:
		if world.admiral_ai[team] != null:
			_ai_buy(team)


## The AI admiral of `team` buys the next level when the treasury holds its
## price plus 1,000 after setting aside the cost of the next step of its
## normal build plan.
func _ai_buy(team: int) -> void:
	var ts: TeamState = world.teams[team]
	if blocker(team) != "":
		return
	var step := AdmiralPlan.next_step(ts)
	var reserve := float(step["cost"]) if not step.is_empty() else 0.0
	if ts.treasury - reserve >= cost_for(ts.doctrine_level) + AI_MARGIN:
		start(team)


# --- the admiral board (a human admiral) ----------------------------------------------

## Add the Fleet Doctrine button to the Mothership tab of board `b`
## (AdmiralBoardMothership.build calls this when the feature is on).
static func build_card(b: AdmiralBoard) -> void:
	b._content.add_child(UiKit.heading("Fleet Doctrine (repeatable research)"))
	var btn := UiKit.button("Fleet Doctrine", func() -> void: _press(b), 34)
	b._hover(btn, "Repeatable research, up to level 10: each level gives every friendly pilot ship +2% maximum hull and +3% shield regeneration. Costs 1,500 x 1.35 per level already finished; 45 s each.")
	b._content.add_child(btn)
	b._cards["doctrine_btn"] = btn


## Rewrite the Fleet Doctrine button on board `b`: level, price and why not.
static func refresh_card(b: AdmiralBoard) -> void:
	var f := current()
	if f == null or not b._cards.has("doctrine_btn"):
		return
	var ts: TeamState = b._ts()
	var btn: Button = b._cards["doctrine_btn"]
	var why := f.blocker(b.team)
	var text := "Fleet Doctrine: level %d of %d" % [ts.doctrine_level, MAX_LEVEL]
	if float(f.left[b.team]) >= 0.0:
		text += "  ·  level %d in %ds" % [ts.doctrine_level + 1, int(ceil(float(f.left[b.team])))]
	elif ts.doctrine_level < MAX_LEVEL:
		text += "  ·  next: %d credits" % int(cost_for(ts.doctrine_level))
	if why != "" and float(f.left[b.team]) < 0.0:
		text += "  ·  " + why
	btn.text = text
	btn.disabled = why != ""


## The button was pressed on board `b`: start the next level, or toast why not.
static func _press(b: AdmiralBoard) -> void:
	var f := current()
	if f == null:
		return
	var err := f.start(b.team)
	if err != "":
		Events.toast.emit(err)
	else:
		Events.cue.emit("buy", Vector2.ZERO)
