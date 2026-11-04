class_name Economy
extends RefCounted
## WHAT THIS IS: the game's pay office. It decides who gets paid, and how
## much, when ore comes home, when something is destroyed, and as a small
## steady trickle. DESIGN.md A7.
##
## HOW IT WORKS: there are two kinds of money. Each pilot has their own
## credits (PilotProfile.credits) to buy ships and gear, and each team has
## a shared treasury (TeamState.treasury) for its admiral. Most pay to a
## pilot goes through PilotProfile.earn(), which also announces it so the
## screens can show "+45 minion". (The passive trickle goes through
## PilotProfile.earn_quietly(), without a message, and ship insurance is
## added to credits directly.) Every payment into a treasury goes through
## TeamState.earn(). These three gates are where a difficulty level scales
## the enemy team's income (Difficulty); ship insurance is a refund, not
## income, and is never scaled.
##   - Ore: 60% to the treasury, 40% shared by the team's living pilots,
##     plus an escort bonus (deliver_ore).
##   - Trickle: every pilot earns a little every second (passive_income).
##   - Kills: a bounty for each kind of thing destroyed (on_unit_killed).
##     Pilots who helped kill an enemy ship or an enemy minion get an
##     "assist" cut. The cut comes out of the bounty (the killer's pay is
##     smaller), it is never paid on top. Who helped is read from the
##     victim's damage log (contributors).
## Many rewards are raised by the pilot's gear ("bounty_pct" stat, see
## _bounty_mult).
## Every amount, share and time window here is a "tuned number": it is
## read through Rules.tune(name, normal value), so a feature module may
## change it for one match (the names are in Rules.TUNABLES). With no
## feature on, the normal Rules values below are used, exactly as before.
## (All functions here are "static": they belong to the class itself and
## are called as Economy.something(world, ...), without making an object.)
##
## WHO USES IT: Combat.kill() calls on_unit_killed(); MiningDrone calls
## deliver_ore() when it unloads at home; World calls passive_income()
## every tick (one small step of the game clock).


## A mining drone of `team` brought `amount` ore home (1 ore = 1 credit).
## Rules.ORE_TREASURY_SHARE (60%, tuned "ore_treasury_share") goes to the
## treasury. The other 40% is split evenly among the team's pilots who are
## not dead (a human admiral has a pilot record too, so they get a share).
## On top of that, pilots who escorted the drone (flew near it;
## `drone.escorts`) share an extra Rules.ESCORT_BONUS (20% of `amount`,
## tuned "escort_bonus"), raised by their bounty gear. `drone` may be null
## (then there is no escort bonus).
static func deliver_ore(w: World, team: int, amount: float, drone: MiningDrone) -> void:
	# Step 1: the treasury's share, and the team's ore count.
	var ts: TeamState = w.teams[team]
	var treasury_share := float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE))
	ts.earn(amount * treasury_share)
	ts.ore_delivered += amount
	# Step 2: the rest is shared by our living pilots.
	var living: Array = []
	for p: PilotProfile in w.profiles:
		if p.team == team and p.state != "dead":
			living.append(p)
	if not living.is_empty():
		var share := amount * (1.0 - treasury_share) / float(living.size())
		for p: PilotProfile in living:
			p.earn(share, "ore")
	# Step 3: the escort bonus, split among the escorts.
	if drone != null and not drone.escorts.is_empty():
		var cut := amount * float(Rules.tune("escort_bonus", Rules.ESCORT_BONUS)) / float(drone.escorts.size())
		for p: PilotProfile in drone.escorts:
			p.earn(cut * _bounty_mult(p), "escort")


## The steady trickle: every pilot (even a dead or docked one) earns
## Rules.PASSIVE_INCOME (1.5 credits per second, tuned "passive_income")
## plus their gear's "income" stat, for `dt` seconds. It goes into credits
## and earned (PilotProfile.earn_quietly()), without a message. The tuned
## number is read once per call, not once per pilot.
static func passive_income(w: World, dt: float) -> void:
	var base := float(Rules.tune("passive_income", Rules.PASSIVE_INCOME))
	for p: PilotProfile in w.profiles:
		var rate := base + p.gear_stats().g("income")
		p.earn_quietly(rate * dt)


## Pilot `p`'s reward multiplier from gear: 1 + their "bounty_pct" stat
## (1.15 with +15% bounty gear, 1.0 with none).
static func _bounty_mult(p: PilotProfile) -> float:
	return p.gear_stats().mul("bounty_pct")


## Which pilots helped kill `victim`. Looks at the victim's damage log
## (Unit.damage_log: attacker id -> [total damage, match time of their
## last hit, their PilotProfile or null]) and keeps the attackers whose
## last hit was within `window` seconds. Each attacker's share is their
## damage / all that recent damage. Returns pilot profile -> share (a 0..1
## fraction), for every pilot attacker whose share is at least `min_frac`.
## Damage from attackers that aren't pilots (turrets, minions) counts in
## the total, but nobody gets their share. A pilot who hit it with two
## different ships gets both shares added together (each must reach
## `min_frac` on its own).
static func contributors(w: World, victim: Unit, window: float, min_frac: float) -> Dictionary:
	var out := {}
	# Step 1: add up all the recent damage.
	var total := 0.0
	for uid in victim.damage_log:
		var e: Array = victim.damage_log[uid]
		if w.time - float(e[1]) > window:
			continue
		total += float(e[0])
	if total <= 0.0:
		return out
	# Step 2: each recent pilot attacker's share, if it is big enough.
	for uid in victim.damage_log:
		var e: Array = victim.damage_log[uid]
		if w.time - float(e[1]) > window or e[2] == null:
			continue
		var frac := float(e[0]) / total
		if frac >= min_frac:
			var p: PilotProfile = e[2]
			out[p] = float(out.get(p, 0.0)) + frac
	return out


## Something was destroyed: pay whoever earned it. `victim` is what died;
## `info` says who did the damage (info.source_profile is the pilot who
## made the last hit, or null if it wasn't a pilot). Each kind of thing
## pays differently (see the steps below; the names in quotes are the
## tuned numbers of Rules.TUNABLES). Kinds not listed (such as a
## mothership) pay nothing here.
static func on_unit_killed(w: World, victim: Unit, info: DamageInfo) -> void:
	var killer: PilotProfile = info.source_profile as PilotProfile
	match victim.kind:
		# A pilot's ship (human or AI): the big one, see _ship_killed().
		Unit.K_SHIP:
			_ship_killed(w, victim as Ship, info, killer)
		# A minion: an enemy pilot who made the last hit gets its bounty,
		# which grows 5% (Rules.MINION_BOUNTY_GROWTH, "minion_bounty_growth")
		# every full 5 minutes of match time. Pilots of that team who helped
		# share a quarter of it (see _minion_killed). A minion that a minion,
		# turret or monster finished off pays nobody.
		Unit.K_MINION:
			if killer != null and killer.team != victim.team:
				_minion_killed(w, victim as Minion, killer)
		# A turret: every pilot of the other team who hit it in the last
		# Rules.ASSIST_WINDOW (15 s, "assist_window") shares
		# Rules.TURRET_BOUNTY (350, "turret_bounty"), and that team's
		# treasury gets Rules.TURRET_TREASURY (400, "turret_treasury").
		Unit.K_TURRET:
			var by_team := Rules.enemy_of(victim.team)
			var who := contributors(w, victim, float(Rules.tune("assist_window", Rules.ASSIST_WINDOW)), 0.0)
			var pilots: Array = []
			for p: PilotProfile in who:
				if p.team == by_team:
					pilots.append(p)
			if not pilots.is_empty():
				var each := float(Rules.tune("turret_bounty", Rules.TURRET_BOUNTY)) / float(pilots.size())
				for p: PilotProfile in pilots:
					p.earn(each * _bounty_mult(p), "turret")
			if by_team >= 0:
				w.teams[by_team].earn(float(Rules.tune("turret_treasury", Rules.TURRET_TREASURY)))
				w.teams[by_team].turrets_destroyed += 1
			Events.turret_destroyed.emit(victim, by_team)
		# A repair bay: the pilot who made the last hit gets
		# Rules.BAY_BOUNTY (200, "bay_bounty"), the other team's treasury
		# Rules.BAY_TREASURY (250, "bay_treasury").
		Unit.K_BAY:
			var by_team := Rules.enemy_of(victim.team)
			if killer != null:
				killer.earn(float(Rules.tune("bay_bounty", Rules.BAY_BOUNTY)) * _bounty_mult(killer), "repair bay")
			if by_team >= 0:
				w.teams[by_team].earn(float(Rules.tune("bay_treasury", Rules.BAY_TREASURY)))
		# A mining drone: its team counts the loss; an enemy pilot who made
		# the last hit gets Rules.MINING_DRONE_BOUNTY (35,
		# "mining_drone_bounty").
		Unit.K_MINING_DRONE:
			w.teams[victim.team].drones_lost += 1
			if killer != null and killer.team != victim.team:
				killer.earn(float(Rules.tune("mining_drone_bounty", Rules.MINING_DRONE_BOUNTY)) * _bounty_mult(killer), "drone")
		# A ward (a small sensor buoy): Rules.WARD_BOUNTY (30,
		# "ward_bounty") to the pilot who made the last hit.
		Unit.K_WARD:
			if killer != null:
				killer.earn(float(Rules.tune("ward_bounty", Rules.WARD_BOUNTY)) * _bounty_mult(killer), "ward")
		# A repair drone: Rules.REPAIR_DRONE_BOUNTY (10,
		# "repair_drone_bounty") to an enemy pilot who made the last hit
		# (gear doesn't raise this one).
		Unit.K_REPAIR_DRONE:
			if killer != null and killer.team != victim.team:
				killer.earn(float(Rules.tune("repair_drone_bounty", Rules.REPAIR_DRONE_BOUNTY)), "repair drone")
		# A derelict monster: its reward (times "derelict_reward_mult",
		# normally 1) is shared by every pilot (either team) who did at
		# least Rules.ASSIST_MIN_FRACTION (10%, "assist_min_fraction") of
		# the damage in the last 30 s ("derelict_assist_window"), by their
		# share of the damage. The one who made the last hit also gets
		# Jungle.LAST_HIT_BONUS (25% of the reward,
		# "derelict_last_hit_bonus") extra, if they are one of those pilots.
		Unit.K_MONSTER:
			var reward: float = float((victim as Derelict).cdef["reward"]) * float(Rules.tune("derelict_reward_mult", 1.0))
			var who := contributors(w, victim, float(Rules.tune("derelict_assist_window", 30.0)), float(Rules.tune("assist_min_fraction", Rules.ASSIST_MIN_FRACTION)))
			var last_hit_bonus := float(Rules.tune("derelict_last_hit_bonus", Jungle.LAST_HIT_BONUS))
			var total := 0.0
			for p: PilotProfile in who:
				total += float(who[p])
			for p: PilotProfile in who:
				var cut := reward * float(who[p]) / maxf(0.001, total)
				if p == killer:
					cut += reward * last_hit_bonus
				p.earn(cut * _bounty_mult(p), "derelict")
				p.monster_kills += 1


## The pilots who helped kill `victim` (a minion or a pilot's ship): pilots
## of the other team than the victim's, not `killer`, who did at least
## Rules.ASSIST_MIN_FRACTION (10%, "assist_min_fraction") of the damage in
## the last Rules.ASSIST_WINDOW (15 s, "assist_window"). Returns pilot
## profile -> their share of that recent damage (a 0..1 fraction), in the
## order of the damage log. `killer` is the pilot who made the last hit, or
## null when a turret, minion or monster did.
static func _helpers(w: World, victim: Unit, killer: PilotProfile) -> Dictionary:
	var out := {}
	var who := contributors(w, victim, float(Rules.tune("assist_window", Rules.ASSIST_WINDOW)), float(Rules.tune("assist_min_fraction", Rules.ASSIST_MIN_FRACTION)))
	for p: PilotProfile in who:
		if p != killer and p.team != victim.team:
			out[p] = who[p]
	return out


## An enemy pilot (`killer`) made the last hit on minion `m`. The pay is the
## minion's bounty plus 5% (Rules.MINION_BOUNTY_GROWTH, "minion_bounty_growth")
## for every full 5 minutes of match time. If other pilots of the killer's
## team helped (see _helpers), they share Rules.MINION_ASSIST_SHARE (a
## quarter, "minion_assist_share") of it by their share of the damage, and
## the killer keeps the rest. With no helpers the killer keeps all of it.
## Each pilot's cut is raised by their own gear. The killer counts a last
## hit (minion_kills); each helper counts a minion assist (minion_assists,
## which no screen shows). (T-25.)
static func _minion_killed(w: World, m: Minion, killer: PilotProfile) -> void:
	# Step 1: the minion's pay.
	var growth := float(Rules.tune("minion_bounty_growth", Rules.MINION_BOUNTY_GROWTH))
	var pay := float(m.mdef["bounty"]) * (1.0 + growth * floorf(w.time / 300.0))
	# Step 2: the helpers' part, if there are any helpers.
	var helpers := _helpers(w, m, killer)
	var pool := 0.0
	if not helpers.is_empty():
		pool = pay * clampf(float(Rules.tune("minion_assist_share", Rules.MINION_ASSIST_SHARE)), 0.0, 1.0)
	# Step 3: the killer keeps the rest.
	killer.earn((pay - pool) * _bounty_mult(killer), "minion")
	killer.minion_kills += 1
	# Step 4: the helpers share the pool by their share of the damage (the
	# shares are scaled to add up to 1 over the helpers).
	var total := 0.0
	for p: PilotProfile in helpers:
		total += float(helpers[p])
	for p: PilotProfile in helpers:
		p.earn(pool * float(helpers[p]) / maxf(0.001, total) * _bounty_mult(p), "minion assist")
		p.minion_assists += 1


## A pilot's ship was destroyed. The bounty is Rules.KILL_BASE (100,
## "kill_base") plus Rules.KILL_VALUE_SHARE (12%, "kill_value_share") of
## what the ship was worth (Ship.bounty_value: hull + module prices), plus
## Rules.SHUTDOWN_PER_STREAK (50, "shutdown_per_streak") for each kill in
## the victim's streak after the first (ending a streak pays more).
##   - An enemy pilot who made the last hit (`killer`) gets a kill on their
##     streak and the bounty: all of it when nobody helped, else two thirds
##     of it (see the helpers below). With Rules.ACE_KILLS (3) or more in a
##     row they become an "ace" for Rules.ACE_TIME (25 s): faster and
##     harder-hitting.
##   - Helpers (enemy pilots who did at least 10% of the damage in the last
##     15 s, Rules.ASSIST_MIN_FRACTION / ASSIST_WINDOW, tuned
##     "assist_min_fraction" / "assist_window") share Rules.KILL_ASSIST_SHARE
##     (a third, "kill_assist_share") of the bounty in equal parts. That
##     third comes out of the killer's pay, so a kill never pays more than
##     its bounty. (T-25. Before, the helpers got half the
##     bounty on top of the killer's pay.) If no pilot made the last hit (a
##     turret, minion or monster did), the helpers share the whole bounty
##     instead.
##   - The victim's death is counted, their streak ends, and insurance
##     pays back part of the ship's value (straight into credits): their
##     insurance gear's share plus "insurance_base" (normally 0).
static func _ship_killed(w: World, ship: Ship, info: DamageInfo, killer: PilotProfile) -> void:
	# Step 1: how much the kill is worth.
	var victim: PilotProfile = ship.profile
	var value := ship.bounty_value()
	var bounty := float(Rules.tune("kill_base", Rules.KILL_BASE)) + value * float(Rules.tune("kill_value_share", Rules.KILL_VALUE_SHARE))
	if victim != null:
		bounty += float(Rules.tune("shutdown_per_streak", Rules.SHUTDOWN_PER_STREAK)) * float(maxi(0, victim.streak - 1))
		# Feature hook (World.bounty_hooks): extra bounty, such as a pilot's
		# accrued bounty (an empty list adds nothing).
		for f: Callable in w.bounty_hooks:
			bounty += float(f.call(victim, ship))
	# Step 2: the helpers (not the killer, not the victim's own team).
	var helpers := _helpers(w, ship, killer)
	# Step 3: pay the killer and count the kill (and maybe make them an ace).
	# The helpers' part comes out of the killer's pay, not on top of it.
	var assist_pool := 0.0
	if killer != null and killer.team != ship.team:
		var killer_pay := bounty
		if not helpers.is_empty():
			assist_pool = bounty * clampf(float(Rules.tune("kill_assist_share", Rules.KILL_ASSIST_SHARE)), 0.0, 1.0)
			killer_pay = bounty - assist_pool
		killer.earn(killer_pay * _bounty_mult(killer), "kill")
		killer.kills += 1
		killer.streak += 1
		killer.best_streak = maxi(killer.best_streak, killer.streak)
		w.teams[killer.team].kills += 1
		if killer.streak >= Rules.ACE_KILLS and killer.ship != null and killer.ship.alive:
			killer.ship.ace_t = Rules.ACE_TIME
			killer.ship.stats_dirty = true
	elif not helpers.is_empty():
		# Killed by a turret, minion or monster: the enemy pilots who helped
		# share all of it.
		assist_pool = bounty
	# Step 4: pay the helpers their equal parts.
	for p: PilotProfile in helpers:
		p.earn(assist_pool / float(helpers.size()) * _bounty_mult(p), "assist")
		p.assists += 1
	# Step 5: the victim's side: a death, the streak ends, and insurance
	# (gear's share plus the tuned base share, which is normally 0).
	if victim != null:
		victim.deaths += 1
		victim.streak = 0
		var insurance := victim.gear_stats().g("insurance") + float(Rules.tune("insurance_base", 0.0))
		if insurance > 0.0:
			victim.credits += value * insurance
