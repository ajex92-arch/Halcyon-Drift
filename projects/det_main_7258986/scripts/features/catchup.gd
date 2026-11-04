class_name CatchupFeature
extends RefCounted
## WHAT THIS IS: the feature module for idea C6, catch-up income or shared
## team income (variants catchup:income and catchup:share). DESIGN note for
## the user: the research rejected both because the money is passive or
## unearned and so softens the reward for skill; they are built so the
## screens can measure it (corr(skill, earned) and skill_rho_small are
## expected to drop).
##
## HOW IT WORKS: both use the same deficit D as the comeback bounties
## (ComebackDirector, which counts turrets and pilot kills only).
##   income  From 10:00, every pilot of a team whose D is 3 or more earns
##           0.4 credits per second for each point of D, at most 2 credits
##           per second, whether alive, dead or docked and whatever they
##           do. The pay goes straight into credits and "earned" like the
##           passive trickle.
##   share   (the Heroes of the Storm team-experience idea) 30% of every
##           credit a pilot earns from kills, assists, minions and
##           turrets is taken from them and put in the team's pool, and
##           the pool is paid out at once, equally, to all 12 pilots of the
##           team (alive or dead). The credits stay in the team, but are
##           spread evenly.
## There is nothing for the AI to decide: it spends the money it gets as
## always. Counted in Game.usage as "catchup_credits" (income) and
## "shared_credits" (share).
##
## WHO USES IT: FeatureRegistry installs it for --variant=catchup:income or
## catchup:share.

## The variant key.
const KEY := "catchup"
## Match time (seconds) from which the income pays: 10:00.
const INCOME_START := 600.0
## Credits per second per point of D.
const INCOME_PER_D := 0.4
## The most credits per second a pilot gets.
const INCOME_CAP := 2.0
## A team needs at least this D to be paid.
const MIN_D := 3.0
## The share of a pilot's pay that goes into the pool.
const SHARE := 0.3

## The match.
var world: World
## The shared who-is-behind scorekeeper.
var director: ComebackDirector
## Credits paid out so far that have not yet been counted in Game.usage
## (usage counts whole credits).
var _income_carry := 0.0


## Switch the match to this idea.
func install(w: World) -> void:
	world = w
	var value := Game.variant(KEY)
	if value == "income":
		director = ComebackDirector.ensure(w)
		w.tick_hooks.append(_tick_income)
	elif value == "share":
		Events.credits_earned.connect(_on_credits_earned)
	else:
		push_warning("catchup: unknown value \"%s\" (use off, income or share); nothing changed" % value)


## World tick hook for catchup:income: pay the trailing team.
func _tick_income(dt: float) -> void:
	if world.time < INCOME_START:
		return
	for team in 2:
		var deficit := float(director.d[team])
		if deficit < MIN_D:
			continue
		var rate := minf(INCOME_CAP, INCOME_PER_D * deficit)
		for p: PilotProfile in world.profiles:
			if p.team == team and p.role != "admiral" and p.slot < Rules.PILOTS_PER_TEAM:
				p.earn_quietly(rate * dt)
				_income_carry += rate * dt
	if _income_carry >= 1.0:
		Game.count_usage("catchup_credits", int(_income_carry))
		_income_carry -= floorf(_income_carry)


## A pilot was paid (catchup:share): take 30% of kill, assist, minion and
## turret pay into the team pool and hand it out equally at once.
func _on_credits_earned(p: RefCounted, amount: float, reason: String) -> void:
	if reason != "kill" and reason != "assist" and reason != "minion" and reason != "turret":
		return
	var earner := p as PilotProfile
	if earner == null or earner.role == "admiral":
		return
	# Step 1: the pool takes its share from the earner.
	var cut := amount * SHARE
	earner.credits -= cut
	earner.earned -= cut
	# Step 2: pay it out equally to the 12 pilots of the team.
	var team: Array = []
	for q: PilotProfile in world.profiles:
		if q.team == earner.team and q.role != "admiral" and q.slot < Rules.PILOTS_PER_TEAM:
			team.append(q)
	if team.is_empty():
		return
	var each := cut / float(team.size())
	for q: PilotProfile in team:
		q.credits += each
		q.earned += each
	Game.count_usage("shared_credits", int(cut))
