# Release notes

What each release of Halcyon Drift changes, newest first. The Windows version of
each release is on the GitHub Releases page; the browser version always shows the
newest `main`.

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
