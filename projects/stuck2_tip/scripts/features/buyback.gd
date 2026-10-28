class_name BuybackFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C4, buyback that strains the
## mothership (variant buyback:on). A pilot who has just died may pay
## credits to come back at once instead of waiting out the respawn timer.
## It is a way to turn the late pile of idle credits into a quick return to
## a fight, and it strengthens the existing respawn strain rule, because a
## bought respawn counts twice toward it.
##
## HOW IT WORKS: the price is 150 credits + 25 per match minute + 10% of the
## value of the hull and modules the pilot just lost (Ship.bounty_value()
## at the moment of death). Each pilot may buy back at most once every 180 s.
## Paying makes the pilot "docked" at once (as if the timer had run out):
## the team's stipend is paid, TeamState.note_respawn() is called TWICE (so
## many buybacks quickly strain the mothership: its guns slow and its
## shield stops refilling) and Events.respawned is sent. It is refused
## while the mothership is down with no repair bay to stand in.
## Humans get a button on the hangar's Launch button while dead (HangarLaunch),
## and the death banner mentions it (HudBanner).
## The AI uses it: every half second, a dead AI pilot buys back when its
## team is defending its mothership (the "defend" call is on) or its
## mothership is under 60% hull, and it holds the price + 500 credits, and
## the respawn timer still has more than 5 s to run. Counted in Game.usage
## as "buybacks" (and "buyback_credits").
##
## WHO USES IT: FeatureRegistry installs it for --variant=buyback:on.
## HangarLaunch and HudBanner call the static functions below.

## The variant key.
const KEY := "buyback"
## The price starts at this many credits...
const BASE_COST := 150.0
## ...plus this many for every minute of match time...
const PER_MINUTE := 25.0
## ...plus this share of the hull-and-modules value just lost.
const VALUE_SHARE := 0.10
## A pilot may buy back once in this many seconds.
const COOLDOWN := 180.0
## The AI keeps this many credits after paying.
const AI_MARGIN := 500.0
## The AI's mothership-hull condition: under this fraction of hull.
const AI_MS_HULL := 0.6
## The AI does not buy when the timer has this many seconds or fewer left.
const AI_MIN_WAIT := 5.0
## Seconds between the AI's checks.
const AI_EVERY := 0.5

## The match.
var world: World
## Value (credits) of the hull and modules each pilot lost when they died:
## PilotProfile -> credits.
var lost_value := {}
## Match time of each pilot's last buyback: PilotProfile -> seconds.
var last_buy := {}
## Seconds until the AI's next check.
var _ai_t := 0.0


## Switch the match to this idea.
func install(w: World) -> void:
	world = w
	if Game.variant(KEY) != "on":
		push_warning("buyback: unknown value \"%s\" (use off or on); nothing changed" % Game.variant(KEY))
		return
	Events.unit_killed.connect(_on_unit_killed)
	w.tick_hooks.append(_tick)


## The running match's buyback feature, or null when it is off.
static func current() -> BuybackFeature:
	var w := Game.world as World
	if w == null:
		return null
	return w.features.get(KEY) as BuybackFeature


## A unit died: if it was a pilot's ship, remember what it was worth.
func _on_unit_killed(unit: Node, _info: RefCounted) -> void:
	var s := unit as Ship
	if s != null and s.profile != null:
		lost_value[s.profile] = s.bounty_value()


## The price for pilot `p` to buy back now, in credits.
func cost(p: PilotProfile) -> float:
	return BASE_COST + PER_MINUTE * floorf(world.time / 60.0) + VALUE_SHARE * float(lost_value.get(p, 0.0))


## Why pilot `p` cannot buy back now, or "" if they can: dead, not bought in
## the last 180 s, the credits, and a mothership (or a repair bay) to
## respawn at.
func blocker(p: PilotProfile) -> String:
	if p.state != "dead":
		return "Not waiting to respawn"
	var since := world.time - float(last_buy.get(p, -9999.0))
	if since < COOLDOWN:
		return "Buyback again in %ds" % int(ceil(COOLDOWN - since))
	var price := cost(p)
	if p.credits < price:
		return "Not enough credits (%d short)" % int(ceil(price - p.credits))
	var ms := world.mothership(p.team)
	if ms == null or not ms.alive or (not ms.available() and world.best_bay(p.team, ms.global_position) == null):
		return "The mothership can't launch you right now"
	return ""


## Pilot `p` buys back: pay, come back at once, and strain the mothership.
## Returns "" when it worked, or why not (nothing changes then).
func buy(p: PilotProfile) -> String:
	var b := blocker(p)
	if b != "":
		return b
	var price := cost(p)
	p.credits -= price
	last_buy[p] = world.time
	# The same steps as MatchRules when a respawn timer runs out, but
	# note_respawn() counts twice.
	p.state = "docked"
	p.respawn_t = 0.0
	var ts: TeamState = world.teams[p.team]
	if ts.stipend > 0.0:
		p.earn(ts.stipend, "stipend")
	ts.note_respawn()
	ts.note_respawn()
	Events.respawned.emit(p)
	Game.count_usage("buybacks")
	Game.count_usage("buyback_credits", int(price))
	return ""


## World tick hook: every half second the AI pilots that are dead decide
## whether to buy back (see HOW IT WORKS).
func _tick(dt: float) -> void:
	_ai_t -= dt
	if _ai_t > 0.0:
		return
	_ai_t = AI_EVERY
	for p: PilotProfile in world.profiles:
		if p.state != "dead" or p.is_human or p.respawn_t <= AI_MIN_WAIT:
			continue
		var ts: TeamState = world.teams[p.team]
		var ms := world.mothership(p.team)
		var urgent := ts.defending(world.time) or (ms != null and ms.alive and ms.hull_frac() < AI_MS_HULL)
		if urgent and p.credits >= cost(p) + AI_MARGIN:
			buy(p)


# --- for the screens (humans) --------------------------------------------------------

## For the Launch button of a dead human's hangar: the text, or "" when
## buyback is off. Example: "Buy back now: 480 credits".
static func button_text(p: PilotProfile) -> String:
	var f := current()
	if f == null:
		return ""
	var b := f.blocker(p)
	if b != "":
		return "Respawn in %ds  ·  buyback: %s" % [int(ceil(p.respawn_t)), b]
	return "Buy back now: %d credits" % int(f.cost(p))


## True when the human `p` can buy back right now (the button is enabled).
static func can_buy(p: PilotProfile) -> bool:
	var f := current()
	return f != null and f.blocker(p) == ""


## The human `p` pressed the buyback button. Returns "" or why not.
static func press(p: PilotProfile) -> String:
	var f := current()
	if f == null:
		return "Buyback is off"
	return f.buy(p)
