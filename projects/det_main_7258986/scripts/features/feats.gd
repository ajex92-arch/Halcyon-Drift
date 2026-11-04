class_name FeatsFeature
extends RefCounted
## WHAT THIS IS: the feature module for the "feats" rule variant (fork
## teamfights_jungle, idea D8): an early race for three "feats of strength"
## and a reward at 14:00 for the team that won at least two. DESIGN flag
## (the research rejected it: an early snowball that fixes no late problem).
##
## HOW IT WORKS: there are three feats, each claimed once per match by the
## first team to do it: the first pilot kill, the first turret destroyed and
## the first derelict camp cleared. Each claim puts a banner in the news feed
## and shows on the scoreboard (a note after the team's heading). At 14:00
## the team that holds two or more feats gets the "Vanguard": 300 credits to
## each of its pilots (all twelve seats, whether flying or not) and +10% hull
## for all its minions for 6 minutes (MinionBuffs). The AI needs no special
## rule: the feats come from its normal play. Nothing here draws random
## numbers.
## Usage counts: "feats_claimed" and "vanguards".
##
## WHO USES IT: FeatureRegistry installs it for --variant=feats:on. The
## scoreboard asks scoreboard_note().

## The variant key this module belongs to.
const KEY := "feats"
## Match time (seconds) of the Vanguard reward: 14:00.
const VANGUARD_AT := 840.0
## Credits to each pilot of the Vanguard team.
const VANGUARD_PAY := 300.0
## Extra minion hull of the Vanguard (1.1 = +10%).
const VANGUARD_HULL := 1.1
## Seconds the Vanguard's hull bonus lasts: 6 minutes.
const VANGUARD_TIME := 360.0
## The feats: id -> the words for the banner and the scoreboard.
const NAMES := {"kill": "first pilot kill", "turret": "first turret destroyed", "camp": "first camp cleared"}

## The match.
var world: World
## The shared minion buffs.
var buffs: MinionBuffs
## Feat id -> the team that holds it (-1 = nobody yet).
var holders := {"kill": -1, "turret": -1, "camp": -1}
## True once the 14:00 reward has been decided.
var vanguard_done := false


## Hook the module into match `w`: listen for the three kinds of event and
## start the tick.
func install(w: World) -> void:
	world = w
	buffs = MinionBuffs.ensure(w)
	Events.unit_killed.connect(_on_unit_killed)
	Events.turret_destroyed.connect(_on_turret_destroyed)
	w.tick_hooks.append(Callable(self, "tick"))


## Events.unit_killed: a pilot ship killed by a pilot is the "kill" feat; a
## derelict camp (not the Dreadnought) cleared by a pilot is the "camp" feat.
func _on_unit_killed(unit: Node, info: RefCounted) -> void:
	var di := info as DamageInfo
	if di == null or di.source_profile == null:
		return
	var team := (di.source_profile as PilotProfile).team
	if unit is Ship and (unit as Ship).team != team:
		_claim("kill", team)
	elif unit is Derelict and (unit as Derelict).camp_id != "epic":
		_claim("camp", team)


## Events.turret_destroyed: the "turret" feat goes to the team that did it.
func _on_turret_destroyed(_turret: Node, by_team: int) -> void:
	_claim("turret", by_team)


## Team `team` claims feat `feat` if nobody holds it yet.
func _claim(feat: String, team: int) -> void:
	if team < 0 or team > 1 or int(holders[feat]) != -1:
		return
	holders[feat] = team
	Game.count_usage("feats_claimed")
	TfjKit.news("%s claims a feat of strength: %s" % [Rules.TEAM_NAMES[team], NAMES[feat]])


## Called by World every tick: at VANGUARD_AT decide the Vanguard.
func tick(_dt: float) -> void:
	# (TEST OPTION --tfj-vanguard-at=SECONDS brings the 14:00 reward forward
	# for short smoke runs; without it this is exactly VANGUARD_AT.)
	if vanguard_done or world.time < float(Game.opt("tfj-vanguard-at", VANGUARD_AT)):
		return
	vanguard_done = true
	for t in 2:
		if _count(t) >= 2:
			_vanguard(t)


## How many feats team `t` holds.
func _count(t: int) -> int:
	var n := 0
	for feat in holders:
		if int(holders[feat]) == t:
			n += 1
	return n


## Give team `t` the Vanguard reward.
func _vanguard(t: int) -> void:
	for p: PilotProfile in world.profiles:
		if p.team == t and p.role != "admiral":
			p.earn(VANGUARD_PAY, "vanguard")
	buffs.add_source("vanguard:%d" % t, t, world.time + VANGUARD_TIME, VANGUARD_HULL, 1.0)
	Game.count_usage("vanguards")
	TfjKit.news("%s is the Vanguard: 300 credits each and sturdier waves for 6:00" % Rules.TEAM_NAMES[t])


## Feature hook (the scoreboard): the note after team `t`'s heading, listing
## its feats ("" when it holds none).
func scoreboard_note(t: int) -> String:
	var names: Array = []
	for feat in holders:
		if int(holders[feat]) == t:
			names.append(NAMES[feat])
	if names.is_empty():
		return ""
	return "  ·  feats: " + ", ".join(PackedStringArray(names))
