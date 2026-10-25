extends RefCounted
## WHAT THIS IS: the fun probe's accountant. It follows the money: what
## pilots are paid for (playing or just waiting), how unevenly pilots earn,
## how much money piles up unspent, and how busy the admiral seat is late in
## the match (docs/FUN_RESEARCH.md, fun model ingredients 9 and 10).
##
## HOW IT WORKS:
##   - on_credits() (every Events.credits_earned): adds the payment to its
##     reason ("kill", "minion", "ore", "stipend" ...). Pay for PLAYING is
##     the reasons in PLAY_REASONS plus any reason with "bounty" in it (for
##     bounty mechanics that forks may add). play_income_share = play pay /
##     everything the AI pilots earned (PilotProfile.earned, which also
##     holds the passive trickle that sends no event).
##   - tick() (every tick): each team's treasury change. A rise is income,
##     a fall is spending. (The game has no "spent" counter, so this is the
##     honest stand-in for the research's "change in TeamState.spent": a
##     purchase and some income in the very same tick (1/60 s) would cancel
##     out a little, which is rare and small.) From 30:00 on these are added
##     up for late_spend_ratio = spent / income.
##   - sample_30s() (every 30 s): from 30:00 on, the mean treasury of the
##     two teams (treasury_float_late averages these).
##   - on_admiral_result() (every Events.admiral_result): from 30:00 on, a
##     successful admiral order counts as a decision if it is not a drone,
##     a waypoint or a minion order (so: facilities, research, turrets, bays,
##     wards, minion purchases, mothership moves, and any new order a fork
##     adds), at most one per order type per team in each 30-s block.
##   - sample_minute() (v1): the pilots' unspent credits and both
##     treasuries at 30:00.
##
## WHO USES IT: tests/fun_probe.gd makes one, calls it from its timers and
## from the game's events, and merges results() into FUN_JSON.

## Helper maths (percentiles, ratios, rank correlation).
const FunStats := preload("res://tests/lib/fun_stats.gd")
## Match time (seconds) of 30:00, where "late" starts here.
const LATE_T := 1800.0
## Payment reasons that are pay for playing (kills, assists, last hits,
## minion assists, objectives). "ore", "escort", "stipend" and the passive
## trickle are not. ("minion assist" is the assist money of T-25.)
const PLAY_REASONS := ["kill", "assist", "minion", "minion assist", "turret", "derelict", "repair bay", "drone", "ward", "repair drone"]
## Admiral orders that are NOT counted as decisions.
const NOT_DECISIONS := ["drone", "waypoint", "order"]
## The decision cap: at most one per order type per this many seconds.
const DECISION_BLOCK := 30.0

## The v1 money snapshot at 30:00 (empty until then).
var money_30 := {}
## Credits paid to AI pilots per reason (reason -> credits).
var earned_by_reason := {}
## Each team's treasury at the last tick (credits).
var _tr_last: Array = [0.0, 0.0]
## Treasury income per team from 30:00 on (credits).
var inc_late: Array = [0.0, 0.0]
## Treasury spending per team from 30:00 on (credits).
var spent_late: Array = [0.0, 0.0]
## Treasury income per team over the whole watch (credits).
var inc_all: Array = [0.0, 0.0]
## Treasury spending per team over the whole watch (credits).
var spent_all: Array = [0.0, 0.0]
## The mean treasury of both teams, every 30 s from 30:00 on (credits).
var tr_late: Array = []
## Counted admiral decisions from 30:00 on (both teams).
var decisions_late := 0
## Decisions already counted: "team:action:block" -> true.
var _decided := {}


## Remember both treasuries now, so the first tick sees no false change.
## The probe calls this at the end of its setup (after a --late start
## filled the treasuries).
func start(world: World) -> void:
	for t in 2:
		_tr_last[t] = world.teams[t].treasury


## Every tick: each team's treasury change, as income or spending.
func tick(world: World) -> void:
	var late := world.time >= LATE_T
	for t in 2:
		var now_tr := world.teams[t].treasury
		var delta := now_tr - float(_tr_last[t])
		_tr_last[t] = now_tr
		if delta > 0.0:
			inc_all[t] = float(inc_all[t]) + delta
			if late:
				inc_late[t] = float(inc_late[t]) + delta
		elif delta < 0.0:
			spent_all[t] = float(spent_all[t]) - delta
			if late:
				spent_late[t] = float(spent_late[t]) - delta


## Every 30 s: from 30:00 on, the mean treasury of both teams.
func sample_30s(world: World) -> void:
	if world.time >= LATE_T:
		tr_late.append((world.teams[0].treasury + world.teams[1].treasury) * 0.5)


## Once a minute (v1): the money snapshot at 30:00.
func sample_minute(world: World) -> void:
	if not money_30.has("t") and world.time >= LATE_T:
		money_30 = money(world)
		money_30["t"] = int(world.time)


## Average unspent credits per AI pilot and each team's treasury, right now
## (v1).
func money(world: World) -> Dictionary:
	var total := 0.0
	var n := 0
	for p: PilotProfile in world.profiles:
		if not p.is_human:
			total += p.credits
			n += 1
	return {"pilot_credits_avg": int(total / maxf(1.0, float(n))), "treasury_h": int(world.teams[0].treasury), "treasury_c": int(world.teams[1].treasury)}


## An AI pilot `p` was paid `amount` credits for `reason`.
func on_credits(p: PilotProfile, amount: float, reason: String) -> void:
	if p.is_human:
		return
	earned_by_reason[reason] = float(earned_by_reason.get(reason, 0.0)) + amount


## Is `reason` pay for playing (see PLAY_REASONS)?
static func is_play(reason: String) -> bool:
	return reason in PLAY_REASONS or reason.contains("bounty")


## An admiral order finished (Events.admiral_result): count it as a late
## decision if it worked, is a counted type, and is the first of its type
## for this team in this 30-s block.
func on_admiral_result(world: World, team: int, action: String, ok: bool) -> void:
	if not ok or world.time < LATE_T or action in NOT_DECISIONS:
		return
	var key := "%d:%s:%d" % [team, action, int(world.time / DECISION_BLOCK)]
	if not _decided.has(key):
		_decided[key] = true
		decisions_late += 1


## Everything this part measured, for FUN_JSON. `pilots` = the AI pilots,
## `skills` = their PilotAI.skill (same order), `late_min` = minutes
## watched from 30:00 on.
func results(world: World, pilots: Array, skills: Array, late_min: float) -> Dictionary:
	# Step 1: what the pilots earned, in all and for playing.
	var earned: Array = []
	var total := 0.0
	for p: PilotProfile in pilots:
		earned.append(p.earned)
		total += p.earned
	var play := 0.0
	var reasons := {}
	for r: String in earned_by_reason:
		reasons[r] = int(earned_by_reason[r])
		if is_play(r):
			play += float(earned_by_reason[r])
	# Step 2: the earning spread, p75 / p25 of the pilots' earned.
	var p25: Variant = FunStats.percentile(earned, 0.25)
	var p75: Variant = FunStats.percentile(earned, 0.75)
	var spread: Variant = null
	if typeof(p25) != TYPE_NIL and float(p25) > 0.0:
		spread = float(p75) / float(p25)
	# Step 3: the late treasury: income, spending, and decisions per
	# team-minute.
	var inc := float(inc_late[0]) + float(inc_late[1])
	var spent := float(spent_late[0]) + float(spent_late[1])
	return {
		"money_30": money_30,
		"money_end": money(world),
		"earned_by_reason": reasons,
		"earned_total": int(total),
		"play_income_share": FunStats.snap(FunStats.ratio(play, total), 0.001),
		"earn_spread": FunStats.snap(spread, 0.001),
		"pilot_float_30": money_30.get("pilot_credits_avg", null),
		"treasury_float_late": FunStats.snap(FunStats.mean(tr_late), 1.0),
		"skill_earned_rho": FunStats.snap(FunStats.spearman(skills, earned), 0.001),
		"treasury_all": {"income": [int(inc_all[0]), int(inc_all[1])], "spent": [int(spent_all[0]), int(spent_all[1])]},
		"treasury_late": {"income": int(inc), "spent": int(spent)},
		"late_spend_ratio": FunStats.snap(FunStats.ratio(spent, inc), 0.001),
		"admiral_decisions_late": decisions_late,
		"admiral_decisions_per_min_late": FunStats.snap(FunStats.ratio(float(decisions_late), 2.0 * late_min), 0.001),
	}
