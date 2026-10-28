class_name Difficulty
extends RefCounted
## WHAT THIS IS: the difficulty levels of a single-player match, and the one thing
## each level changes: how much the enemy team earns. Easy, Medium, Hard, Very
## Hard and Extreme multiply everything the enemy team earns by 0.75, 1.0, 1.25,
## 1.5 and 2.0. Nothing else changes: prices, rules and the AI stay the same.
##
## HOW IT WORKS: the chosen level is held in one place, Game.difficulty (a level id
## such as "hard"). It comes from the launch option --difficulty=<level>, or from
## the picker on the start screen, which remembers the last pick between runs
## (Game.choose_difficulty()). The five multipliers are the named constants below,
## and INCOME lists them by level id. When WorldSetup builds a match it asks
## team_income_mult() once for each team and stores the answer in
## TeamState.income_mult and in the income_mult of each of the team's pilots. Every
## credit then goes through one of three gates that multiplies it:
##   PilotProfile.earn()         every payment to a pilot that has a message
##                               (kills, assists, minions, monsters, turrets, ore ...);
##   PilotProfile.earn_quietly() the steady trickle and the feature modules' running pay;
##   TeamState.earn()            everything that lands in a team's treasury (the
##                               mothership's income, the ore share, destroyed turrets
##                               and repair bays).
## The enemy team is the team with no human on it. In a match with no human seat (every
## test, determinism and tour run) both teams get exactly 1.0, and so does the human's
## own team in every match. Multiplying a number by exactly 1.0 changes nothing, so
## those matches, and Medium, play exactly as they did without a difficulty.
## Nothing is rounded: credits are fractional numbers in this game, and each payment
## is multiplied as it arrives, so the enemy's total over a match is exactly the
## level's multiple of what it would have earned at the normal rate. What is not
## income is never multiplied: the credits and the treasury a team starts with,
## what a pilot gets back for selling gear or trading in a hull or a module, ship
## insurance, the refund of an expired admiral order, and money moved between the
## pilots of one team.
##
## WHO USES IT: Game (the setting, the launch option, the remembered pick),
## WorldSetup (makes the multipliers), the start screen (the picker and its
## texts), tests/difficulty_check.gd and tests/difficulty_probe.gd.

## The id of the Easy level (the id is what --difficulty and the settings file say).
const EASY := "easy"
## The id of the Medium level, the standard game.
const MEDIUM := "medium"
## The id of the Hard level.
const HARD := "hard"
## The id of the Very Hard level.
const VERY_HARD := "very_hard"
## The id of the Extreme level.
const EXTREME := "extreme"

## How much the enemy team earns on Easy, as a multiplier (0.75 = 75% of normal).
const EASY_INCOME := 0.75
## On Medium: the normal income. A match on Medium plays as one without a difficulty.
const MEDIUM_INCOME := 1.0
## On Hard (1.25 = 125% of normal).
const HARD_INCOME := 1.25
## On Very Hard (1.5 = 150% of normal).
const VERY_HARD_INCOME := 1.5
## On Extreme (2.0 = 200% of normal).
const EXTREME_INCOME := 2.0

## Every level id, in the order the start screen lists them.
const ORDER := [EASY, MEDIUM, HARD, VERY_HARD, EXTREME]
## The level a new game starts on.
const DEFAULT := MEDIUM
## The enemy team's income multiplier of each level: level id -> multiplier.
const INCOME := {EASY: EASY_INCOME, MEDIUM: MEDIUM_INCOME, HARD: HARD_INCOME, VERY_HARD: VERY_HARD_INCOME, EXTREME: EXTREME_INCOME}
## Each level's name for players (the start screen's buttons).
const LABELS := {EASY: "Easy", MEDIUM: "Medium", HARD: "Hard", VERY_HARD: "Very hard", EXTREME: "Extreme"}
## The sentence the start screen ends every level's description with.
const SCOPE_NOTE := "This changes the enemy's income in single player only."


## Is `id` one of the levels (a key of INCOME)?
static func is_level(id: String) -> bool:
	return INCOME.has(id)


## The enemy income multiplier of level `level` (1.0 for a word that is not a level).
static func income_mult(level: String) -> float:
	return float(INCOME.get(level, MEDIUM_INCOME))


## The multiplier for everything team `team` earns in a match whose one human sits
## on team `human_team` (-1 = nobody is human): the chosen level's multiplier for
## the team without the human, exactly 1.0 for the human's team, for a match with
## no human and for the neutral team. WorldSetup calls it once per team.
static func team_income_mult(human_team: int, team: int) -> float:
	if human_team < 0 or team == human_team or team < 0 or team > 1:
		return 1.0
	return income_mult(Game.difficulty)


## The start screen's description of level `level`: what the enemy earns, then
## SCOPE_NOTE.
static func blurb(level: String) -> String:
	var pct := roundi(income_mult(level) * 100.0)
	var what := "the enemy earns its normal income, as in the standard game." if pct == 100 else "the enemy earns %d%% of its normal income." % pct
	return "%s: %s %s" % [String(LABELS.get(level, level)), what, SCOPE_NOTE]
