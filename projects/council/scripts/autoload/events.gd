extends Node
## WHAT THIS IS: the game's notice board (the autoload "Events"). When
## something happens in the match (a ship is destroyed, research finishes,
## a weapon fires), the game posts a "signal" here, and any screen, the
## sound player or a test that cares can listen for it.
##
## HOW IT WORKS: a "signal" is a named message with a few values attached.
## The simulation (the part of the code that runs the match) "emits"
## (sends) them; a listener "connects" one of its functions, which Godot
## then calls with those values. The simulation never waits for a listener
## or depends on one, so a run with no window (no HUD, no sound) plays
## exactly the same match. An "autoload" is a script Godot starts before
## everything else; every file can reach it by its name, `Events`.
##
## WHO USES IT: each signal below names who sends it and who listens. The
## main listeners are the HUD (hud.gd and its parts), the sound player
## (Sfx), main.gd (match_over) and several tests.
##
## The object values have loose types (Node, RefCounted), so this small
## file does not need the game's own classes; each note names the real
## type.

## A line for the news feed. `tone` is "info" (news for everyone) or
## "team" (one team's news: the HUD shows it in another colour and hides
## it from the other team's screen). The HUD treats every tone other than
## "info" the same way. `team` is whose news it is (-1 = everyone's).
## Sent by match_rules.gd, mothership.gd, team_defense.gd, team_drones.gd,
## team_strain.gd and admiral_siege.gd; the HUD news feed shows it.
signal feed(text: String, tone: String, team: int)
## A short pop-up message for the human, such as "Flight assist on". Sent
## by the hangar screens, the admiral board, the command overlay, the
## player controller and WorldHangar; the HUD shows it.
signal toast(text: String)
## A unit (a Unit) died. `info` is the DamageInfo of the killing blow
## (who hit it, from which team, with what). Sent by combat.gd; the HUD
## (kill lines) and several tests listen.
signal unit_killed(unit: Node, info: RefCounted)
## A turret (a Turret) was destroyed. `by_team` is the other team, which
## gets the reward. Sent by economy.gd; the HUD and tests/match_probe.gd
## listen.
signal turret_destroyed(turret: Node, by_team: int)
## Team `team` finished research `id` (a tech id). Sent by team_tech.gd;
## the HUD listens.
signal research_done(team: int, id: String)
## Team `team` finished building facility `id` onto its mothership. Sent
## by team_tech.gd; the HUD listens.
signal facility_done(team: int, id: String)
## A pilot (`profile`, a PilotProfile) earned `amount` credits. `reason` is
## a short word such as "minion", "assist", "ore" or "stipend". Sent by
## PilotProfile.earn(); the HUD listens.
signal credits_earned(profile: RefCounted, amount: float, reason: String)
## A dead pilot (`profile`, a PilotProfile) is back in the hangar, ready to
## launch. Sent by MatchRules (match_rules.gd); the HUD listens.
signal respawned(profile: RefCounted)
## The match is over. `winner` is the winning team (0 = Halcyon,
## 1 = Cinder); `reason` is the text, such as "The Cinder mothership was
## destroyed." Sent by MatchRules; main.gd and the HUD listen.
signal match_over(winner: int, reason: String)
## A minion (`m`, a Minion) has just launched from its mothership with a
## minion wave (not one bought with Fleet Command). Sent by MinionDirector
## right after the minion is made and before it takes its first step; only
## feature modules listen (BreachFeature, BreachExtraFeature,
## LanespawnFeature). `wave_id` is the director's next_wave at that moment,
## the same number for every minion of one wave.
signal minion_launched(m: Node, wave_id: float)
## A sound cue at world position `pos` (in world units; 1 world unit is
## about one pixel at normal zoom). Vector2.ZERO means an interface sound
## that is always heard. The names sent today: "fire", "pd", "flak",
## "shell" and "torp" (weapon shots, by weapon kind), "hit", "shield_hit",
## "boom", "bump", "launch", "ui", "buy", "warn", "special" and "repair".
## Sent by weapons, combat, effects, ships, the mothership and the hangar;
## only Sfx listens and plays them.
signal cue(name: String, pos: Vector2)
## An admiral order finished. `action` names the order, `ok` says whether
## it worked, and `message` is "" on success or the reason it failed. Sent
## by AdmiralCommand; the HUD listens.
signal admiral_result(team: int, action: String, ok: bool, message: String)
## Measurement only: a hit was applied to `target` (a Unit). `info` is the
## hit's DamageInfo (who hit, with what), `amount` the damage after every
## damage rule and feature hook (before shields), and `hull_dmg` what the
## hull took after the shields and armour (0 when the shields soaked it
## all). Sent by Combat.apply_damage(), but ONLY while
## world.combat.emit_damage_events is true, which only probes turn on
## (tests/fun_probe.gd and tests/pilot_audit.gd); the game itself never
## listens. For a killing hit
## it comes just before unit_killed.
signal damage_applied(target: Node, info: RefCounted, amount: float, hull_dmg: float)
