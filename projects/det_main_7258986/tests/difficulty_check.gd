extends Node
## WHAT THIS IS: the "difficulty check": a quick test that the difficulty setting
## multiplies the right money by the right number, and nothing else. It builds
## the match, makes a few payments straight through the game's own gates and
## compares what each team receives with what the chosen level promises.
##
## HOW IT WORKS: setup() looks at who is human and at Game.difficulty, and works
## out the multiplier each team should have (its own table, written out here
## again so the check does not copy the game's numbers): the chosen level's number
## for the team without the human, exactly 1.0 for the human's team, and 1.0 for
## both teams when nobody is human. For each team it then checks that the team's
## notebook (TeamState.income_mult) and every pilot (PilotProfile.income_mult)
## hold that number, and pays 100 credits through each gate and compares the
## change with 100 times the multiplier: TeamState.earn() into the treasury,
## PilotProfile.earn() (also the amount sent on Events.credits_earned) and
## PilotProfile.earn_quietly() to a pilot, an ore delivery of 1,000 ore
## (Economy.deliver_ore(): 600 into the treasury, 400 among the pilots), and one
## second of the steady trickle (Economy.passive_income()). It also checks that
## money which is not income is not scaled: a pilot buys the cheapest gear item
## and sells it back, and must end with exactly what the sale rules say. It
## prints a PASS or FAIL line for each check and ends with
## "difficulty_check: N failures" (0 = all good), then quits.
## With --settings-check=<text> it also checks the start screen's picker and the
## remembered pick: it builds the start screen, presses a level's button, checks
## the game's setting, the texts and the settings file, then builds the screen
## again as a new run would (the pick must come back), and checks that
## --difficulty beats the remembered pick and that a damaged file is ignored.
## That writes the settings file, so <text> must be part of the name of the user
## data folder (a scratch one: start the game with the environment variable
## APPDATA pointing at an empty folder whose name holds the text); with any other
## folder this part only reports a failure and writes nothing.
##
## HOW TO RUN IT ("godot" is the Godot console program, started from the folder
## that holds remake/):
##   godot --headless --path remake --fixed-fps 60 -- --auto --role=pilot --difficulty=hard --test=difficulty_check
##   godot --headless --path remake --fixed-fps 60 -- --auto --all-ai --difficulty=extreme --test=difficulty_check
## The first has a human pilot (so the enemy team is scaled), the second has no
## human (so nothing is scaled). Try every level, with --role=pilot and
## --role=admiral, and with --all-ai.
##
## WHO USES IT: main.gd loads it for --test=difficulty_check. It changes the
## credits of the match it builds, so it is only for this check.

## The enemy income multiplier of each level, as the check expects it.
const EXPECTED := {"easy": 0.75, "medium": 1.0, "hard": 1.25, "very_hard": 1.5, "extreme": 2.0}
## The credits paid through each gate.
const AMOUNT := 100.0
## The ore of the test delivery (1 ore is worth 1 credit).
const ORE := 1000.0
## Two sums closer than this many credits count as equal (float noise).
const TOLERANCE := 1e-9

## The running match (set by setup()).
var world: World
## How many checks failed so far.
var fails := 0
## The amounts of the credits_earned messages the check itself caused.
var _heard: Array = []


## main.gd calls this once, right after the World is built. Run every check and
## quit.
func setup(w: World) -> void:
	world = w
	Events.credits_earned.connect(_on_credits)
	var human_team := -1
	if world.human != null:
		human_team = world.human.team
	var enemy_mult := float(EXPECTED.get(Game.difficulty, 1.0)) if human_team >= 0 else 1.0
	print("difficulty_check: level=%s human_team=%d, the enemy team should earn x%.2f" % [Game.difficulty, human_team, enemy_mult])
	for t in 2:
		var mult := enemy_mult if (human_team >= 0 and t != human_team) else 1.0
		_check_team(t, mult)
	_check_not_income()
	var marker := str(Game.opt("settings-check", ""))
	if marker != "":
		_check_settings(marker)
	print("difficulty_check: %d failures" % fails)
	get_tree().quit()


## A pilot was paid: keep the amount of the check's own payments.
func _on_credits(_profile: RefCounted, amount: float, reason: String) -> void:
	if reason == "difficulty_check":
		_heard.append(amount)


## Print a PASS or FAIL line for the check `what` (`ok` = it passed), with the
## measured `detail`, and count the failures.
func _check(what: String, ok: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", what, detail])
	if not ok:
		fails += 1


## Check that `got` is `want` (within TOLERANCE), as the check `what`.
func _near(what: String, got: float, want: float) -> void:
	_check(what, absf(got - want) <= TOLERANCE, "got %.9f, wanted %.9f" % [got, want])


## The credits of all the pilots of team `t`.
func _pilot_credits(t: int) -> float:
	var sum := 0.0
	for p: PilotProfile in world.profiles:
		if p.team == t:
			sum += p.credits
	return sum


## Check team `t`, which should have the multiplier `mult`: the numbers it
## holds, and what each gate pays.
func _check_team(t: int, mult: float) -> void:
	var ts: TeamState = world.teams[t]
	var tag := "team %d (x%.2f)" % [t, mult]
	# Step 1: the multiplier is held by the team and by every one of its pilots.
	_near(tag + " TeamState.income_mult", ts.income_mult, mult)
	var pilots: Array = []
	for p: PilotProfile in world.profiles:
		if p.team == t:
			pilots.append(p)
			if absf(p.income_mult - mult) > TOLERANCE:
				_check(tag + " pilot " + p.callsign + " income_mult", false, "got %.9f, wanted %.9f" % [p.income_mult, mult])
	# Step 2: the treasury gate.
	var before := ts.treasury
	ts.earn(AMOUNT)
	_near(tag + " TeamState.earn(100) into the treasury", ts.treasury - before, AMOUNT * mult)
	# Step 3: the two pilot gates: credits, earned, and the message.
	var p0: PilotProfile = pilots[0]
	var c0 := p0.credits
	var e0 := p0.earned
	_heard.clear()
	p0.earn(AMOUNT, "difficulty_check")
	_near(tag + " PilotProfile.earn(100) credits", p0.credits - c0, AMOUNT * mult)
	_near(tag + " PilotProfile.earn(100) earned", p0.earned - e0, AMOUNT * mult)
	_check(tag + " PilotProfile.earn(100) message", _heard.size() == 1 and absf(float(_heard[0]) - AMOUNT * mult) <= TOLERANCE, "heard %s" % str(_heard))
	c0 = p0.credits
	e0 = p0.earned
	_heard.clear()
	p0.earn_quietly(AMOUNT)
	_near(tag + " PilotProfile.earn_quietly(100) credits", p0.credits - c0, AMOUNT * mult)
	_near(tag + " PilotProfile.earn_quietly(100) earned", p0.earned - e0, AMOUNT * mult)
	_check(tag + " PilotProfile.earn_quietly(100) sends no message", _heard.is_empty())
	# Step 4: an ore delivery: 60% into the treasury, 40% among the pilots.
	before = ts.treasury
	var purse := _pilot_credits(t)
	Economy.deliver_ore(world, t, ORE, null)
	_near(tag + " ore delivery, treasury share", ts.treasury - before, ORE * float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE)) * mult)
	_near(tag + " ore delivery, pilots' share", _pilot_credits(t) - purse, ORE * (1.0 - float(Rules.tune("ore_treasury_share", Rules.ORE_TREASURY_SHARE))) * mult)
	# Step 5: one second of the steady trickle, for each pilot of the team.
	var each: Array = []
	for p: PilotProfile in pilots:
		each.append(p.credits)
	Economy.passive_income(world, 1.0)
	var rate := float(Rules.tune("passive_income", Rules.PASSIVE_INCOME))
	var worst := 0.0
	for i in pilots.size():
		var p: PilotProfile = pilots[i]
		worst = maxf(worst, absf(p.credits - float(each[i]) - (rate + p.gear_stats().g("income")) * mult))
	_check(tag + " trickle, one second, every pilot", worst <= TOLERANCE, "largest error %.12f" % worst)


## Make a start screen as a new run would: the setting is open again, then the
## scene is added to the tree (which builds the rows).
func _new_screen() -> StartScreen:
	Game.difficulty = Difficulty.DEFAULT
	Game.difficulty_error = ""
	Game._difficulty_open = true
	var screen: StartScreen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	return screen


## The level whose button is pressed on start screen `screen` ("" if none, or
## more than one).
func _pressed_level(screen: StartScreen) -> String:
	var found := ""
	for lv: String in screen._difficulty_buttons:
		if (screen._difficulty_buttons[lv] as Button).button_pressed:
			found = lv if found == "" else "more than one"
	return found


## The start screen's picker and the remembered pick (see the top of the file).
## `marker` must be part of the user data folder's name, so the settings file
## written here is a scratch one.
func _check_settings(marker: String) -> void:
	var dir := OS.get_user_data_dir()
	if not dir.contains(marker):
		_check("settings check: the user data folder holds \"%s\"" % marker, false, "it is %s, so nothing was written" % dir)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))
	# Step 1: nothing remembered yet: Medium is pressed, and the text names it.
	var screen := _new_screen()
	_check("settings: Medium is pressed when nothing is remembered", _pressed_level(screen) == "medium", "pressed: " + _pressed_level(screen))
	# Step 2: press Hard: the setting, the text and the file follow.
	(screen._difficulty_buttons["hard"] as Button).pressed.emit()
	_check("settings: pressing Hard sets Game.difficulty", Game.difficulty == "hard", Game.difficulty)
	_check("settings: Hard is the pressed button", _pressed_level(screen) == "hard", "pressed: " + _pressed_level(screen))
	_check("settings: the text names Hard, 125% and single player only", screen._difficulty_blurb.text.begins_with("Hard:") and screen._difficulty_blurb.text.contains("125%") and screen._difficulty_blurb.text.contains("single player only"), screen._difficulty_blurb.text)
	var cfg := ConfigFile.new()
	_check("settings: the file was written", cfg.load(Game.SETTINGS_FILE) == OK and str(cfg.get_value("game", "difficulty", "")) == "hard")
	screen.free()
	# Step 3: a new run: the pick comes back.
	screen = _new_screen()
	_check("settings: the next run shows Hard, as remembered", Game.difficulty == "hard" and _pressed_level(screen) == "hard", "setting %s, pressed: %s" % [Game.difficulty, _pressed_level(screen)])
	screen.free()
	# Step 4: --difficulty beats the remembered pick (the game settles it at launch, before the screen).
	Game.difficulty = "easy"
	Game._difficulty_open = false
	screen = (load("res://scenes/ui/start_screen.tscn") as PackedScene).instantiate()
	add_child(screen)
	_check("settings: a launch option beats the remembered pick", Game.difficulty == "easy" and _pressed_level(screen) == "easy", "setting %s, pressed: %s" % [Game.difficulty, _pressed_level(screen)])
	screen.free()
	# Step 5: a damaged file is ignored.
	cfg.set_value("game", "difficulty", "banana")
	cfg.save(Game.SETTINGS_FILE)
	screen = _new_screen()
	_check("settings: a word that is not a level is ignored", Game.difficulty == "medium" and _pressed_level(screen) == "medium", "setting %s" % Game.difficulty)
	screen.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SETTINGS_FILE))


## Money that is not income must not be scaled: a pilot of each team buys the
## cheapest gear item and sells it back, and ends with exactly what is left
## after paying the price and getting Rules.SELL_BACK of it back.
func _check_not_income() -> void:
	var cheapest := ""
	for id: String in Items.ITEMS:
		if cheapest == "" or float(Items.ITEMS[id]["price"]) < float(Items.ITEMS[cheapest]["price"]):
			cheapest = id
	var price := float(Items.ITEMS[cheapest]["price"])
	for t in 2:
		var p: PilotProfile = null
		for q: PilotProfile in world.profiles:
			if q.team == t and q.state != "dead":
				p = q
				break
		p.credits = 5000.0
		var err := p.buy_gear(cheapest)
		var slot := -1
		for i in p.inventory.size():
			if not (p.inventory[i] as Dictionary).is_empty() and (p.inventory[i] as Dictionary)["id"] == cheapest:
				slot = i
		if err != "" or slot < 0:
			_check("team %d buys %s" % [t, cheapest], false, err)
			continue
		p.sell_slot(slot)
		_near("team %d buys and sells back %s: the sale is not scaled" % [t, cheapest], p.credits, 5000.0 - price + price * Rules.SELL_BACK)
