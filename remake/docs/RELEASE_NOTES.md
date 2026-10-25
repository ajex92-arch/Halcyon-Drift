# Release notes

What each release of Halcyon Drift changes, newest first. The Windows version of
each release is on the GitHub Releases page; the browser version always shows the
newest `main`.

## v0.3.0: two playable teams, the standard rules, new looks and smaller waves

### For players

**Play either team.** Before, you always played Aurelian.
- The start screen has a new TEAM row under the DIFFICULTY row: **Aurelian** (amber, starting on the left of the map) or **Vhorr** (red, starting on the right). It works for both seats, Pilot and Admiral, and the other team is all computer. The map is not mirrored: as Vhorr your camera starts in front of the Vhorr mothership and your base is on the right. Your pick is remembered between runs. From a terminal: `--team=aurelian` or `--team=vhorr`.
- The menus' highlight colour follows your team: amber for Aurelian (and for a spectator), red for Vhorr. Colours that mean something do not change: the team colours, the kill feed's amber for good news and red for bad news, the banners, Victory and Defeat, and the health, shield and energy bars.

**One set of rules for every match.** The RULE SET row of the start screen is gone. Every match plays the rules that v0.2.0 called Council's pick: late minions no longer out-fight pilots, the Lance hunts big ships that lost their escort, two Bomber seats fly Fighters and torpedoes hurt small craft less, the computer Admiral spends a big treasury and builds the Hyperspace Module early, gear has Mk II upgrades, a team may have up to 60 bought minions, and a node whose turret was destroyed stays locked longer. The older rule sets remain as launch options for tests (`--preset=none`, `--preset=within`, `--preset=pick`).

**Difficulty levels.** A new DIFFICULTY row on the start screen: Easy, Medium, Hard, Very hard and Extreme. In a match where one human plays against the computer, the enemy team earns 0.75, 1.0, 1.25, 1.5 or 2.0 times what it would have earned: its pilots' credits and its Admiral's treasury, from every source. Your own team's income, matches with nobody playing and every test are never changed. New games start on Medium, which plays as before, and your pick is remembered.

**New looks.**
- **Aurelian ships** have a steel look: armour plates, glass canopies, amber stripes, running lights and dark engine housings with warm nozzle lights, inside an amber outline.
- **Vhorr ships** have an alien look: dark, bladed hulls with glowing veins. Their engine flames are a quarter smaller than the Aurelian flames, so they do not hide the design.
- **Every gun that turns** (a turret or an automatic mount) on a pilot's ship, a lane tower, a Repair Bay or the Aurelian mothership is drawn as a small turret, turned the way the gun points: armoured octagons for Aurelian, thorned discs for Vhorr. Fixed guns get none. The Vhorr mothership still shows its guns as dots, and minions show none.
- **Minions** are plain, solid shapes that cannot be mistaken for a pilot's ship: a blunt wedge, a squat box and a plain triangle for Aurelian; the Spore, the Bloat and the Cocoon for Vhorr.

**Smaller minion waves, with new names and heavier handling.**
- Each lane has its own wave now. The top and bottom lanes get 3 Snub-Fighters, 1 Light Bomber and 1 Patrol Leader; the middle lane gets 5 Snub-Fighters, 4 Light Bombers and 2 Patrol Leaders: 21 minions a team, where v0.2.1 sent 30. The old names were Fighter, Bomber and Escort Corvette.
- Minions are slower to change speed (10% less acceleration along their way) and direction (20% less sideways), and their noses turn 20% slower. Top speed and the pace of the waves are unchanged.

**Fairer money for helpers.** The money for a kill is shared by the pilots who helped, and the total stays the same: the helpers' share comes out of the reward, never on top of it.
- A minion falls to an enemy pilot: if teammates also did at least a tenth of the damage in the last 15 seconds, the last hitter gets 75% of the credits and the helpers share the other 25%, by damage. With no helper the last hitter gets everything, as before.
- A pilot's ship falls: the helpers share a third of its bounty, and the killer keeps the other two thirds.

**Computer pilots go for last hits.** A lane pilot with no target, nothing to push and nobody to hunt used to park at a spot behind its wave. Now it flies up to the enemy minions fighting near the front of its wave (within 1,500 units) and goes for last hits. A waiting spot that fell right on top of the pilot's own turrets is moved out of them.

**Bigger ships, easier targets, turrets without shields.**
- The Destroyer and the Battlecruiser are 1.5 times as big and the Flak Frigate and the Ion Frigate 1.25 times, in how they are drawn, how they are hit and how they collide.
- The Scout, Fighter, Lance Fighter and Bomber are 10% easier to hit (rounds, beams and blasts). Their bodies, the minions and every other unit are unchanged.
- Turrets have no shields, and nothing repairs a turret: not the Logistics Corvette's drones, not Emergency Repair. Repair bays, wards, motherships and ships are unchanged.

**Screens and looks.**
- The whole picture stretches with the window, the smallest window is 1280x720, and the big panels (hangar, help, Admiral board) stay clear of the ship readout and the key line. The text grows with the window instead of staying small.
- **F11** or **Alt+Enter** switches between the window and borderless fullscreen (in a browser, Alt+Enter; F11 stays the browser's own).
- The drift arrow shows on the ship you fly and on no other. A hit flashes a ship's outline and leaves its fill alone. The lane and node names on the map are never taller than about 60 screen pixels.

### How well it was tested

Each change was tested on its own when it was made, with its own checks and, for changes to play, matches between computer players before and after. This release was not measured again as a whole against v0.2.1.
- **The release build** (the play changes with the testing tools taken out; only documents changed after these tests): all scripts load, the bot pilot, the support probe, the UI tours for pilot and Admiral, the mouse-wheel check, and the checks for the difficulty levels, the hit size, turret repair, the rules and playing either team in every seat: all OK, with no script errors.
- **Replay test** (seed 7, with the drawing code running): taking the testing tools out changed nothing in play. Play changes on purpose against v0.2.1, so there are new reference runs: normal END f2ba4199 (180 lines), late start END d374fd49 (60 lines).
- **Pictures** of the start screen, the hangar and a match as Vhorr, the Admiral board as Aurelian, and two big computer fights, with no script errors.
- **A release review of the whole release** found no code defect. It found text faults in these notes and in the developer docs (a missing known issue, a turret sentence that said too much, leftover wording), all fixed before the release.

### Known issues

- The big Aurelian ships (the two frigates, the Destroyer and the Battlecruiser) have several engine nozzles but one exhaust trail until a later release.
- **Stuck ships.** Ships still get stuck in the rocks now and then, the big Battlecruisers most of all. The fix is not in this release.

### For developers

- New settings: `Game.human_team` (`--team`, remembered with the difficulty in a small settings file) and `Game.difficulty` (`--difficulty`; `scripts/data/difficulty.gd`). Money goes in through three gates that apply the team's multiplier: `PilotProfile.earn()`, `PilotProfile.earn_quietly()` and `TeamState.earn()`.
- The standard rules are `CouncilPresets.STANDARD` ("pick"); `Game.apply_preset()` and the start screen's rule-set buttons are gone, and the preset table has a `none` entry for the old rules.
- The damage modifiers (the damage table and the other fixed multipliers, DESIGN A5) are behind one switch, `Rules.DAMAGE_MODIFIERS_REMOVED`, which is false in this build; `--damage-modifiers-removed` overrides it for one run.
- Drawing: `AurelianShapes` and `AurelianPaint`, `CinderShapes` and `CinderPaint`, `TurretShapes` and `TurretPaint`, `MinionShapes`, `StructureShapes`, and the test-only part switches of `DrawParts` (`--bench-off`). `WindowMode` holds the minimum window size and the fullscreen key.
- Waves: `Minions.OUTER_WAVE`, `MID_WAVE`, `WAVES` and `wave_for(lane)`; handling: `MinionFlight.steer`; hit size: `Unit.hit_radius()` and `Rules.SMALL_PILOT_HIT_MUL`.
- New tests: `rules_check`, `team_check`, `difficulty_check`, `hit_size_check`, `turret_repair_check`, `assist_check`, `hit_reach_check`, `display_check`, and probes for the waves, income, farming, difficulty, hit size, minion handling and turret repair. `remake/README.md` gives the command for each.
- DESIGN rows C26 and C27 (the waves and the assist money) and sections A3, A5, A7, A8 and A15.

## v0.2.1: a free camera and a new AI opening

### For players

**Pilots can look around the whole map.** Before, only the Admiral and spectators could move the camera freely; a pilot's camera always followed the ship.
- Move the mouse to a screen edge (a 6-pixel zone; it pans at 80% of the view per second), drag with the middle mouse button, or click the minimap. How far out a pilot can zoom is unchanged (5,200 units across by default).
- **Space** puts the camera on your ship, or on the spot in front of your mothership when you are docked or dead. Hold Space to keep the camera centered on the ship while you fly; let go and it is free again from there.
- When your ship launches (also after a hyperspace jump), the camera jumps to it, so a new ship never appears off screen. The Admiral's camera stays where it is.
- **Space no longer fires.** Shoot with the left mouse button. W/A/S/D/Q/E still fly the ship.
- The Admiral's free camera and the C key (follow your ship) are unchanged. Spectators: Space does nothing.
- **Fixed** (found and fixed by reading the code; the automated checks cannot switch windows): losing focus (Alt+Tab or the Windows key) now ends a middle-button drag and lets go of a held fire button, and the camera edge-pans only while the pointer is inside the game window, so it no longer pans by itself with the pointer on a second monitor.

**The computer pilots open the match differently.**
- **The opening:** for the first 10 seconds every computer pilot waits at a spot past its mothership's bow. Then each one flies to the Crossing of its lane and holds it until the team's first minion wave arrives there, or for at most 3 minutes. In v0.2.0 they drifted out with the wave: the lane pilots' median arrival was 110 seconds; now it is about half a minute. They do not go shopping during the opening.
- **The flex pilot's** lane rotation now starts on the top lane instead of the middle, for the whole match (it still moves on to the next lane every 90 seconds), so in the opening it holds the top Crossing.
- **No second opening:** the first wave's arrival is one fact per team and lane, so a pilot who was dead, docked or retreating when the wave arrived does not start its opening again later.
- **Junglers fall back** from a losing fight in the opening (hurt and outnumbered), like the lane pilots.
- **The Admiral's flag:** new in v0.2.1, a rally flag that a human Admiral places during the opening pulls the pilots who answer it (seats 4, 5, 6 and the flex pilot) off their Crossings; in v0.2.0 no flag rallied them before 10:00. The computer Admiral's own flag at 1:00 still does not. From 10:00 on, any flag rallies them, as in v0.2.0.
- **The Crossing turrets:** the computer Admiral now builds its Crossing turret before extra turrets at home. While it holds no Crossing turret, it builds at the Crossing with the most of its own ships (pilots and minions) within 1,500 units, instead of trying the Crossings in map order (in the tests before this change, Aurelian's first one went to the Top Crossing in every match).

### How well it was tested

All numbers below compare v0.2.1 with v0.2.0 on the same six seeds (301-306), in matches between computer players.
- **The release build** (the AI opening fix and the camera change merged onto v0.2.0, with the camera fix from the release review; only documents changed after these tests): all scripts load, the bot pilot, the support probe and the UI tours for pilot and Admiral: all OK, with no script errors.
- **Replay test** (seed 7, with the drawing code running): two runs are identical. Play changes on purpose, so there are new reference runs: normal END f957a77a (180 lines), late start END ccbb4bde (60 lines).
- **Camera:** camera_check for the pilot, Admiral and spectator seats, 0 failures; zoom_check 5,200 units across, as before.
- **The AI opening:** the opening and Crossing probes on every round of the fix; the new opening_fix_check test (0 failures); and 40-minute matches with the fun, pilot and admiral audits.
- **Two independent code reviews of the AI change.** The first (rounds 1 and 2) found two defects, which round 3 fixed. The second (round 3) found none.
- **A release review of the whole release** found no code defect in the AI change and one small one in the camera change (a middle-button drag that stayed on after Alt+Tab). It is fixed, with two related cases (see For players). After the fix, the release-build, replay and camera checks were run again; the replay is identical, so the AI numbers above still stand.

### Known issues

- **A bloodier early game.** This comes from the new opening itself: the pilots meet at the Crossings in the first minute. In the first five minutes, kills rose by about half (99 to 149 over six matches; deaths 125 to 193). Retreats to repair before the first wave arrives went from 2 to 159, so the Crossings thin out between about 0:45 and 1:50.
- **Stuck ships.** Stuck episodes rose from 2.82 to 4.63 per 100 pilot-minutes. 63 of the 215 come from one bomber stuck in the rocks from 6:35 to the end of one match; without it the rise is 16%. Time in contact with rocks barely moved (+2%). Crash deaths went from 6 to 7. A fix is being worked on.
- **Fewer matches ended within 40 minutes:** 1 of 6 in v0.2.0, 0 of 6 now. Six matches are too few to tell.
- **No Crossing turret for one side:** in 3 of 12 team-matches a side built no Crossing turret by 25:00. Each time the other side had taken all three Crossings early; in the two of these matches where its money was logged, this side was also short of money.
- All match numbers come from matches between computer players.

### For developers

- AI only: PilotGoals (the opening, the first-wave fact TeamState.first_wave_at), PilotAI (the fall-back gate), PilotShopping (no shopping in the opening), AdmiralBuilder (the Crossing turret order, _crossings_in_order), AdmiralWaypoint, AdmiralCommand.set_waypoint(..., by_human), TeamState (waypoint_by_human), Rules (AI_OPENING_HOLD 10 s, AI_OPENING_MAX 180 s). The command overlay passes by_human = true; the computer Admiral passes false.
- Camera: CameraRig's free mode for every seat; the new action center_on_ship (Space); Space left the "fire" action; ZoomMaxFeature asks CameraRig.zoom_limited(). After the release review: CameraRig._notification() ends a middle drag on focus loss, _pointer_inside() gates the edge pan and the edge peek, and World._notification() lets go of mouse_fire and mouse_special on focus loss.
- New tests: opening_probe, crossing_probe, opening_fix_check, camera_check.
- DESIGN rows C24, C25 and A14 (the opening), A15 (the camera).

## v0.2.0: rule sets

### For players

**What is new.** The start screen has a new RULE SET row, between the rules text
and the seat cards. It picks the rules of the match you are about to start:

- **Standard rules** (chosen at first): the game exactly as in v0.1.0.
- **Within requirements**: a set of changes that fixes the late game and keeps
  every requirement on the project's list, as the user amended it (the Fleet
  Command limit is 60 since 2026-10-17).
- **Council's pick**: "Within requirements" plus one more change (persistent
  nodes, below).

(The fun council is the project's review step that combined the six fun
experiments and tested the combinations; `docs/FUN_PLAN.md` section 6.)

**Also new.** The enemy fleet is now called the Vhorr (it was Cinder in v0.1.0).
Only the name on screen and in the documents changed.

**Screens fixed for small windows.** The HUD, menus and start screen no longer
overlap or run off the edge at any window size from 1024x600 to 2560x1300. While a
big panel is open (the scores while you hold Tab, the hangar, help or the Admiral
board), the kill feed, big message, minimap, gear slots, ship readout and earnings
log are hidden instead of peeking out from under it.

Pick a rule set first, then pick your seat (Admiral or Pilot). The choice stays
until you change it or restart the game. The browser version has the same row. On
a computer you can also start the game with `--preset=within` or `--preset=pick`
(from the source folder, or with the Windows download). From the source
folder, import once first if your copy is fresh (see the README):

```
godot --headless --path remake --import
godot --path remake -- --preset=within
HalcyonDrift.exe -- --preset=within
```

**The promise.** With no rule set the rules are exactly v0.1.0's: an all-AI match
with the same seed plays out move for move as in v0.1.0 (determinism test, normal
and late-game windows).

**What "Within requirements" changes.**

- Late-game minions no longer out-fight pilots. A minion's shot at a pilot ship
  counts as at most 15% stronger than a fresh minion's, and the Reinforced Waves
  research does not count for it.
- The Lance has a job. It hunts big ships that lost their escort, and its beam
  does 35% more damage to the rear shield zone of a large or capital ship.
- Fewer useless Bombers. Seats 6 and 10 fly Fighters instead, and a pilot's
  torpedo does x0.6 to small craft (x0.35 before).
- The AI Admiral spends a big treasury. It builds the Fleet Command Module (the
  free waves stop and it buys minions) and keeps placing wards.
- Less travelling. The AI Admiral builds the Hyperspace Module early. A
  hyperspace launch to a friendly repair bay spools for 4 seconds instead of 6,
  and AI pilots can also jump to a friendly turret near the fight (the hangar
  offers you repair bays only).
- Mk II gear. Every gear item can be upgraded once to Mk II for 2.5 times its
  price, with stats x1.6: something worth buying late in the match.
- A bigger fleet limit. A team may have up to 60 bought minions alive (30 in
  the standard rules). The limit is the same for both teams, for a human or an AI
  Admiral, and the Admiral board's texts show the limit of the match.

None of these changes a requirement. The Fleet Command limit of 60 is the
requirement since the user's decision of 2026-10-17 (`docs/DESIGN.md`, C22); the
original `docs/USER_REQUIREMENTS_2026-10-13.md` still says 30.

**What "Council's pick" adds.** Persistent nodes: a node whose turret was
destroyed stays locked for 150 seconds (60 in the standard rules), and a turret built
there again starts at half hull but then only repairs 1% a second (a new turret
is full when its build ends). The AI Admiral also rebuilds the nodes nearest its
own mothership first.

**What the test matches showed (AI against AI).**

- With either rule set every test match ended. With the standard rules 55% of
  matches end within an hour; with a rule set, all of them did, typically after
  about 29 minutes (standard rules: about 50 minutes, counting an unfinished
  match as 60). None ended before 20 minutes.
- In both rule sets the fun model's "pilots decide fights" score rises from 42
  to about 94 out of 100 and its match-arc score from 41 to 90, and pilots spend
  less time dead or travelling.

**To feel the old fleet limit inside a rule set,** start with
`--preset=within --variant=fleet_cap:30` (`--variant` still works on top of a
preset and wins for its keys). A limit other than 60 counts as a requirement
change, so it is a switch of its own (see the list below).

### How well it was tested

Each rule set was played in 80 fresh matches, AI against AI, on the same 80 seeds
as the standard rules, and scored with the project's fun model (`docs/FUN_METRICS.md`,
0 to 100). The fun model's score rises from 63.0 (standard rules) to 81.4 with
"Within requirements" (+18.4; 95% lower bound of the gain +14.5), and to 79.8 with
"Council's pick" (+16.8; 95% lower bound +13.3). The bar was +5 with a lower
bound above 0, so both clear it about three times over. Every one of those 160
matches ended, typically in about 29 minutes. The turret-rebuild lock of the
pick adds no fun on top of "Within requirements" (-1.6, not significant); it
moves some fun from fights to Admiral play. The matches ran on the same game code
that v0.2.0 ships: only documentation, code comments and the screens (their text
and layout) differ, and the determinism test, run with both rule sets, shows the
matches play out the same.

### Every switch that changes a requirement

All of these are single switches, off by default, and in neither rule set: you
turn one on with `--variant=key:value` (several: comma-separated), so the game's
owner makes that call. The effects are what the forks measured on AI-only test
matches (their own screens, on fewer seeds than the 80-seed run above). These are
early screens on 3 to 20 AI-only seeds, scored against one shared baseline; treat
them as hints.

The exceptions to "off" are `escort_wing` and `fleet_cap`. `escort_wing`: its
default `extra` is v0.1.0's own rule (the Escort Wing research adds an 11th
minion, against "waves of 10"), and `escort_wing:upgrade` is the version that
keeps the wave at 10 (the single corvette gets +40% hull and +15% range
instead). `fleet_cap`: its default of 30 is v0.1.0's limit, but the requirement
is 60 since 2026-10-17; the standard rules keep 30 so that the default game stays
unchanged.

*The end of a match*

- `breach:fulldmg`: breach corvettes hit the mothership at full strength (the
  requirement: the mothership is weak to big ships, not to minions). Fun +34 on a
  short late-game test of 5 seeds and +17.1 on 20, but the endgame score fell
  (-5.9) because minions, not big ships, finish the game.
- `ms_cap:on` (mild) and `ms_cap:full`: the mothership's hull loss is capped
  (x0.5, or x0.1, beyond a rate). The requirement: a lot of health. Mild: slightly
  negative alone. Full: the finales drag (added to "Within requirements", the
  median last push was about 12 minutes, 729 s) and some matches stalemate.
- `ms_soft:mult`: big ships hit the mothership x3 (fun +6.8 on 10 late seeds, not
  significant; alone it loses the mothership duel test). `ms_soft:hull` and
  `ms_soft:shield`: a weaker mothership hull (x0.75) or shield (x0.5): +3.3 on 20
  seeds and -2.9 on 10; both rejected.
- `waves_late:slow` (a free wave every 70 s from 30:00) and `waves_late:none`
  (none from 35:00): fewer free minion waves late (the requirement: minions spawn
  regularly). +19.9 and +24.6 on late tests, but no gain on top of "Within
  requirements".
- `lanespawn:on`: late minions launch from the ends of the lanes. +37.5 on a late
  test, but it over-closes games (15 of 20 last pushes under 45 s); on top of
  "Within requirements" +2.4, not significant.
- `breach_extra:on`: an 11th (super) minion per wave in breached lanes (the
  requirement: waves of 10). +4.3 on 20 seeds; rejected.
- `surrender:vote`: the AI team may vote to surrender (the requirement: only a
  mothership kill ends the match). One vote in 10 full matches; no effect.
- `ms:nosmall`: small craft stop sieging the mothership (the requirement: both
  sizes push lanes). +1.6.

*Combat*

- `jungle_big:all`: big ships may enter the jungle (the requirement: the jungle is
  for small ships). +1.7 over the combat set, not significant; it costs the
  endgame and Admiral scores. `jungle_big:medium` exists, but its test was invalid
  (it measured only the wider gates).
- `zoom_max:wide` and `zoom_max:xwide`: a wider maximum zoom (the requirement:
  the camera zoom stays close to the ship). An AI cannot judge it; it needs a
  human playtest.

*Pacing*

- `slipstream:flat`: a lane slipstream at one speed for every hull (the
  requirement: heavier ships are slower). Downtime +6.8 on 12 seeds, 30-minute
  fun -1.0; still rejected.
- `respawn_site:bay` and `respawn_site:waypoint`: respawn at a forward repair bay
  or at the Admiral's waypoint (the requirement: kits are bought at the
  mothership). Downtime +0.6 and +1.2 on 12 seeds; both rejected. A forward
  respawn ended many matches early (5 and 6 of 12 ended before 30:00, against 1 of
  12); that was never screened over full matches.
- `bay_shop:on`: kits and gear sold at repair bays. The AI never made a shop trip;
  downtime -0.2.

*Economy*

- `pilot_mining:hold` and `pilot_mining:extractor`: pilots mine resource nodes, or
  build extractors (the requirements: no pilot mining; extractors were removed).
  Fun 58.6 to 53.3 for hold (6 seeds) and 58.4 to 57.2 for extractor (12 seeds);
  both rejected.
- `ms_spend_weak:on`: the mothership weakens after big treasury spends (the
  requirement was reversed). No effect (late fun 53.6 to 53.5 on 20 seeds).

*Team fights*

- `beacons:on`: salvage beacons and a sensor blackout (the requirements: no
  dynamic event zones; mining drones replaced capture points). Teamwork +0.9 at
  30:00 on 12 seeds (+7.4 on the first 3), and with the Dreadnought it hurt full
  matches (-1.8; only 19 of 40 ended).
- `epic:dreadnought` and `epic:elder`: timed epic neutrals (the requirement: no
  timed events). The Dreadnought hurt at full length and needs a test AI to be
  killed at all; the Elder Core ended 1 match of 20.

*Admiral*

- `fleet_cap:<n>` (any whole number other than 60): a Fleet Command limit other
  than 60 (the requirement since 2026-10-17). The standard rules use 30, both
  rule sets use 60.
- `assets:xray`: the Sensor Sweep sees through asteroids (the requirement: no
  seeing through asteroids). Fun -5.7.
- `ms_move:early`: the mothership moves from 12:00 (the requirement: from 20:00,
  by a docked Admiral). On 6 normal seeds the endgame score fell by 18.2 and fun
  by 0.4; rejected.
- `ms_move:flying` and `ms_move:both`: the mothership moves while the Admiral
  flies. Untested in play: AI Admirals never fly.
- `mutiny:on`: pilots may vote the Admiral out (the requirement: the role is
  locked). Untested in play, for the same reason.

Held back or rejected, but not a requirement change: `doctrine:on` (a repeatable
Admiral research, Fleet Doctrine) waits for the owner's own Admiral-upgrade
changes. `assets:on` / `assets:full` (Sensor Sweep, Supply Drop, Barrage):
rejected on their fun screens (-6.3 on 10 late seeds; +1.6 on 20, not
significant). `FORK_MANIFEST.md` lists every other switch (rejected ideas
included).

### Known issues

- **Very short final pushes at fleet limit 60.** 46% of the last pushes in
  "Within requirements" (38% in the pick, 27% in the standard rules) take under 45
  seconds: the AI Admiral's paid fleet often finishes the job in one rush. A last
  push of two to seven minutes is the next design problem.
- **The pick may lean to Vhorr.** Aurelian won 38% of the pick's 80 matches (an
  80% interval of 30 to 45%), 44% of the 80 in "Within requirements", and 48% of
  the 44 matches that ended with the standard rules.
- **The matches were AI against AI.** They used skill jitter, and nobody played
  them. The fun model stands for an average player, so a human feel check is
  still open, especially of a match where the AI Admiral buys Fleet Command.
- **Two scores may dip.** "Both ship sizes needed" is lower in both rule sets
  (-4.0, -6.5) and "Admiral matters" in "Within requirements" (-6.0). Dips like
  these appear by chance in about two of three comparisons of this size: things
  to watch in a playtest, not findings.
- **Fleet limit 60 costs computer time.** About 39% more late-game simulation
  time than limit 30, and fun about 2 points lower in a paired comparison (not
  significant). It matters most for the browser version.

### For developers

- `scripts/data/council_presets.gd` holds the two rule sets as `--variant`
  strings, and the start screen and `Game.apply_preset()` use them. An unknown
  `--preset` name stops the match at its start (exit code 3, "PRESET UNKNOWN").
- Every idea of the six fun-experiment forks is a module in `scripts/features/`
  behind its own variant key (`FeatureRegistry`), off by default. See
  `FORK_MANIFEST.md` and `docs/fork_manifests/`.
- The `fleet_cap` key sets the bought-minion limit (30 by default, v0.1.0's limit;
  both rule sets use 60, the requirement).
- New test and probe scripts in `tests/` (the forks' probes and smoke tests).
  `tests/fun_probe.gd` also prints how a match ended.
- `docs/API_INDEX.md` is rebuilt for the new scripts.
- `tools/ui_layout_check.py` finds overlapping or cut-off screen elements in the
  dump of a `tests/ui_tour.gd` run (`tests/lib/ui_dump.gd` writes it; `--selftest`
  checks the checker).

## v0.1.0: the first release

Released on 2026-10-17.

- The game: Halcyon Drift, a top-down space MOBA, 13 against 13 (12 pilots and an
  Admiral per side), with AI in every seat you do not take. Windows (GitHub
  Releases) and browser (GitHub Pages) versions.
- Names: Halcyon Drift is the project and also the asteroid belt the battle is
  fought in. The team that was called Halcyon is now Aurelian (Cinder keeps its
  name).
- Speed for tests: the new `--sim-only` option skips everything that only draws or
  makes sound in windowless runs. The simulation is identical (the determinism
  hashes match) and test matches run about 1.9 times faster, with a few exact
  speed-ups in pilot avoidance, the keel arrow and minion targeting.
- The AI passes 1 to 3 of the AI deep dive: flight, targeting, retreats and the
  Admiral (`docs/AI_DEEP_DIVE.md`).
