extends RefCounted
## WHAT THIS IS: the fun probe's "who is ahead?" part. It follows two kinds
## of lead through the match and turns them into the suspense and comeback
## numbers (docs/FUN_RESEARCH.md, fun model ingredient 3):
##   - the old lead by "worth" (fun probe v1; kept unchanged so old and new
##     runs can be compared), and
##   - the new advantage index A (tests/lib/adv_index.gd).
##
## HOW IT WORKS: sample() runs every 30 s of match time.
##   Old (v1): a team's worth = every credit its pilots earned + every bit
##   of ore its drones delivered. The leader is the team with more, once the
##   gap is over 5% of the average. Flips of the leader are counted, and the
##   leader at 10, 15 and 20 minutes is remembered.
##   New (v2): A and its lead L (+1 Aurelian ahead, 0 even, -1 Cinder ahead).
##   A lead change is counted when L takes the opposite non-zero sign and
##   keeps it for 2 samples in a row (a one-sample blip is not a change).
##   We keep every sample, L at 15:00 (comeback and "even at 15"), A at 15,
##   20 and 25 minutes (so tools/fun_score.py can check how well A predicts
##   the winner), and work out "decided_to_end": how long before the end the
##   winner was ahead without a break.
##   note_pilot_kill() is told about every pilot-on-pilot kill, for the
##   index's "kills in the last 300 s" count.
##
## WHO USES IT: tests/fun_probe.gd makes one, calls sample() every 30 s and
## note_pilot_kill() on kills, and merges results() into FUN_JSON.

## The advantage index's formula (measurement only; see adv_index.gd).
const AdvIndex := preload("res://tests/lib/adv_index.gd")

## The match clock (seconds) when the probe started watching: 0, or 1,500
## (25:00) for a --late run. Checkpoints before it are never recorded.
var start_t := 0.0

# --- v1: lead by worth (unchanged) -----------------------------------------

## How often the worth leader flipped.
var lead_changes := 0
## The last team that was clearly ahead by worth (+1, -1; 0 = nobody yet).
var _last_lead := 0
## The worth leader at 10, 15 and 20 minutes: "10"/"15"/"20" -> +1, -1, 0.
var leader_at := {}
## The biggest "richer team's worth / poorer team's worth" after 5:00
## (1.0 = always even).
var max_worth_ratio := 1.0
## Every check as [match seconds, Aurelian worth, Cinder worth] (credits).
var worth_samples: Array = []

# --- v2: the advantage index -------------------------------------------------

## Match times (seconds) of the pilot kills made by each team's pilots,
## [Aurelian's list, Cinder's list], for K5 (kills in the last 300 s).
var kill_times: Array = [[], []]
## Every sample as [match seconds, A] (A rounded to 0.01 points).
var adv_samples: Array = []
## The lead L (+1, 0, -1) of every sample, in the same order.
var l_samples: Array = []
## The sign of the current run of equal non-zero L samples (0 = none).
var _run_sign := 0
## How many samples the current run has lasted.
var _run_len := 0
## The confirmed leader (+1/-1): the last sign that held for 2 samples.
var _confirmed := 0
## Lead changes of the index: L took the opposite sign for 2 samples.
var adv_lead_changes := 0
## L at 15:00 (Aurelian's view), or null if the probe didn't watch 15:00.
var l15: Variant = null
## A at 15, 20 and 25 minutes: "15"/"20"/"25" -> A (only those watched).
var adv_at := {}
## The same for the pre-registered alternative index (no FV, K5 doubled).
var adv_alt_at := {}


## Make the part. `start` is the match clock when watching began.
func _init(start: float) -> void:
	start_t = start


## A pilot of team `team` destroyed an enemy pilot ship at time `t`
## (seconds).
func note_pilot_kill(team: int, t: float) -> void:
	if team == 0 or team == 1:
		(kill_times[team] as Array).append(t)


## Every 30 s: the v1 worth lead, then the v2 advantage index.
func sample(world: World) -> void:
	_sample_worth(world)
	_sample_index(world)


## A team's "worth" (v1): every credit its pilots have earned plus every bit
## of ore its drones delivered.
func _worth(world: World, t: int) -> float:
	var w := world.teams[t].ore_delivered
	for p: PilotProfile in world.profiles:
		if p.team == t:
			w += p.earned
	return w


## The v1 lead by worth (unchanged from fun probe v1): who leads (+1, -1,
## or 0 within 5%), the flips, the biggest ratio after 5:00, and the
## leader at 10, 15 and 20 minutes (the first check at or after each).
func _sample_worth(world: World) -> void:
	# Step 1: both worths, and the leader if the gap is over 5% of their
	# average.
	var h := _worth(world, 0)
	var c := _worth(world, 1)
	worth_samples.append([int(world.time), int(h), int(c)])
	var avg := maxf(1.0, (h + c) * 0.5)
	var lead := 0
	if absf(h - c) > avg * 0.05:
		lead = 1 if h > c else -1
	# Step 2: a flip is a clear leader different from the last clear leader.
	if lead != 0 and _last_lead != 0 and lead != _last_lead:
		lead_changes += 1
	if lead != 0:
		_last_lead = lead
	# Step 3: the biggest ratio after 5:00; the leader at 10, 15 and 20 min
	# (only marks the probe watched: a --late run starts after all three).
	if world.time >= 300.0:
		max_worth_ratio = maxf(max_worth_ratio, maxf(h, c) / maxf(1.0, minf(h, c)))
	for m in [10, 15, 20]:
		if not leader_at.has(str(m)) and world.time >= m * 60.0 and start_t < m * 60.0:
			leader_at[str(m)] = lead


## How many of team `t`'s pilot kills happened in the last 300 s.
func _k5(t: int, now: float) -> int:
	var n := 0
	for k: float in kill_times[t]:
		if now - k <= AdvIndex.K5_WINDOW:
			n += 1
	return n


## The v2 advantage index: A and L now, lead changes (L must hold the new
## sign for 2 samples), and the checkpoints at 15, 20 and 25 minutes.
func _sample_index(world: World) -> void:
	# Step 1: both teams' counts and the index (and the alternative).
	var now := world.time
	var h := AdvIndex.team_parts(world, 0, _k5(0, now))
	var c := AdvIndex.team_parts(world, 1, _k5(1, now))
	var a := AdvIndex.value(h, c)
	var l := AdvIndex.lead(a)
	adv_samples.append([int(now), snappedf(a, 0.01)])
	l_samples.append(l)
	# Step 2: the run of equal non-zero leads; at its 2nd sample the sign is
	# confirmed, and a confirmed sign opposite to the old one is a change.
	if l != 0 and l == _run_sign:
		_run_len += 1
	else:
		_run_sign = l
		_run_len = 1
	if _run_sign != 0 and _run_len == 2:
		if _confirmed != 0 and _run_sign != _confirmed:
			adv_lead_changes += 1
		_confirmed = _run_sign
	# Step 3: the checkpoints: the first sample at or after each minute
	# mark, only if the probe was already watching before that mark.
	for m in [15, 20, 25]:
		var key := str(m)
		if not adv_at.has(key) and now >= m * 60.0 and start_t < m * 60.0:
			adv_at[key] = snappedf(a, 0.01)
			adv_alt_at[key] = snappedf(AdvIndex.value(h, c, true), 0.01)
			if m == 15:
				l15 = l


## "decided_to_end", in minutes. Ended match: the end minus the start of
## the winner's final unbroken run of L = +1 (winner's view); 0 if the
## winner was not clearly ahead at the last sample. Unended match: the end
## of watching minus the start of the final run of the same non-zero lead
## (the research's "60 minus ..." for the usual 60-minute cap); 0 if the
## last sample was even. Null with no samples. `end_t` is the end time.
func _decided_to_end(winner: int, ended: bool, end_t: float) -> Variant:
	var n := l_samples.size()
	if n == 0:
		return null
	# Step 1: whose run we look for: the winner's (as +1 from their side),
	# or, with no winner, whoever leads at the last sample.
	var want := 0
	if ended and winner >= 0:
		want = 1 if winner == 0 else -1
	else:
		want = int(l_samples[n - 1])
	if want == 0 or int(l_samples[n - 1]) != want:
		return 0.0
	# Step 2: walk back to the first sample of that final run.
	var i := n - 1
	while i > 0 and int(l_samples[i - 1]) == want:
		i -= 1
	return snappedf((end_t - float(adv_samples[i][0])) / 60.0, 0.01)


## Everything this part measured, for FUN_JSON. `winner` is the winning
## team (-1 = none), `ended` whether a mothership died, `end_t` the time
## watching stopped (seconds).
func results(winner: int, ended: bool, end_t: float) -> Dictionary:
	# v1: the winner was behind (by worth) at 15:00.
	var lead15 := int(leader_at.get("15", 0))
	var comeback := winner >= 0 and lead15 != 0 and ((lead15 == 1) != (winner == 0))
	# v2: comeback15 (the winner's L at 15:00 was -1) needs an ended match;
	# even15 (L = 0 at 15:00) needs only the 15:00 sample.
	var comeback15: Variant = null
	var even15: Variant = null
	if typeof(l15) != TYPE_NIL:
		even15 = int(l15) == 0
		if ended and winner >= 0:
			var winner_view := int(l15) if winner == 0 else -int(l15)
			comeback15 = winner_view == -1
	return {
		"lead_changes": lead_changes,
		"leader_at": leader_at,
		"comeback": comeback,
		"max_worth_ratio": snappedf(max_worth_ratio, 0.01),
		"worth": worth_samples,
		"adv_lead_changes": adv_lead_changes,
		"adv_l15": l15,
		"comeback15": comeback15,
		"even15": even15,
		"decided_to_end_min": _decided_to_end(winner, ended, end_t),
		"adv_at": adv_at,
		"adv_alt_at": adv_alt_at,
		"adv": adv_samples,
	}
