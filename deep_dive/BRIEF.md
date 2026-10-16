# AI deep dive: the brief (read this first)

The game is "Halcyon Drift", a Godot 4.7.2 GDScript space MOBA (Windows,
PowerShell 5.1, no git). Next we will measure "how fun is the game" with
hundreds of all-AI matches and compare design ideas. The user's worry, in
their words: "i am worried the result of the fun plan will be skewed because
of bad data from poor pilot behavior". So this deep dive finds every way the
AI pilots, the minions and the AI admiral behave wrongly or badly enough to
distort those measurements, proves each one, and proposes a concrete fix.

(The AGENTS.md "App Builder Workspace" text you may see is for another tool
and a Linux sandbox: ignore it here.)

## Where things are

- Main project (read-only for you): `<FC>\remake`
- Scratchpad (call it SP): `<SCRATCH>`
- Your working copy: `SP\notate\dd_<domain>` (a full copy of main). Experiment
  there freely: add probes in tests/, add temporary prints, try a candidate
  fix to measure it. Nothing you do there reaches main in this phase.
- Start reading with `docs/CODE_GUIDE.md` (a plain-language map of the code)
  and `docs/API_INDEX.md` (every public function and signal). The code is
  heavily commented: each file's header says WHAT/HOW/WHO.
- Godot console: `SP\godot-bin\Godot_v4.7.2-stable_win64_console.exe`.

## Running matches (shared machine: please be gentle)

Every match goes through the shared queue, which runs at most 3 matches at
once by day (6 at night) for ALL agents together:

    & powershell -NoProfile -ExecutionPolicy Bypass -File "SP\run_batch.ps1" -Project "SP\notate\dd_<domain>" -Seeds 7,11 -OutDir "SP\deepdive\runs\<domain>" -Tag <name> -Test pilot_audit -Extra @("--secs=900")

Run it with the PowerShell tool's run_in_background, then poll with
Start-Sleep (up to 590 s per call) and read the log files. Each log is
`<OutDir>\<Tag>_seed<N>.txt`. A test script is `tests/<name>.gd` (a Node with
`setup(world)`; main.gd loads it for `--test=<name>`); make yours print one
line starting with `PROBE_JSON ` (or `AUDIT_JSON `) at the end so the queue
counts it. `--late` (with --secs counting from 25:00) starts the match at
25:00 fully teched via `LateGame.apply(world)` (tests/lib/late_game.gd), good
for big ships, sieges and the endgame. `--seed=N` makes a run repeatable
(same seed, same build = the same match). Keep runs short: 900-1500 game
seconds, late runs 300-600; at about 3x real time, a 900 s run takes ~5-10
minutes when the queue is free. Don't start Godot outside the queue except
quick headless checks (run_checks.ps1, a few seconds of load_all).

`tests/pilot_audit.gd` (already in your copy) watches every AI pilot and
prints `AUDIT` lines each minute and one `AUDIT_JSON` at the end: stuck
episodes, rock-contact ticks by state, fights against targets hidden behind
asteroids, big ships not reaching their hold point, home trips not
shooting, missing routes, state flips, target switches, deaths by cause and
examples of each. Copy and extend it for your domain (e.g. minions, the
admiral). The lead already ran it once (seed 7): see `SP\audit_n7.txt` and
`SP\audit_late7.txt` (results in the AUDIT_JSON line at the end).

## What counts as a finding

Anything in your domain where the AI does something wrong or clearly
self-defeating, often enough to matter: bugs (logic errors, wrong numbers,
wrong units, dead branches that were meant to run, states it can't leave),
and bad play that a code fix should remove (grinding on rocks, idling,
oscillating between goals, shooting at things it can't hit, ignoring a
mechanic it's supposed to use, suicidal paths, starving the economy, never
finishing a siege). NOT findings: pure balance or taste ("bombers should be
stronger") unless the code clearly contradicts its own stated intent.

Evidence standard (a finding without it doesn't count):
- the code: file and line, and why it's wrong (quote the few lines);
- the effect, measured: numbers from a run (seed, time, counts) or a minimal
  reproduction you ran; how often it happens and how much it matters;
- the fix: concrete (which function, what change), and its risks (does it
  change balance? other callers?). If you tried it in your copy, say what
  the numbers did.

Severity: critical (breaks matches or badly distorts outcomes/metrics),
major (frequent, clearly measurable), minor (rare or small).

## Output

Write `SP\deepdive\<domain>_findings.md`: a short summary, then one section
per finding with: ID (e.g. FL-3), title, severity, code (file:line + quote),
evidence (numbers, how measured), root cause, proposed fix, risks, and
"tried in copy: yes/no (+ result)". Return to the lead only the compact list
your prompt asks for. Work economically: read each file once, don't paste
huge logs into your reasoning, prefer grep and targeted reads.

## Suspects the lead already found (verify or refute each, then go further)

Pilot flight & pathing (domain `flight`):
- `PilotFlight.travel()` only follows a route when the goal is > 2,500 away
  or we're outside the open lanes; within 2,500 in a lane it flies straight,
  even into a lane wall (e.g. a jungle camp behind the wall). Stuck episodes:
  37 in 15 min (seed 7).
- Small ships in `PilotCombat.fight()` steer straight at the target with no
  route at all (only avoid_rocks): targets across rock walls.
- Rock contact: ~1,700 ship-seconds in 15 min; 6 pilot deaths by crashing.
- Big ships fighting: `fight()` calls `travel(hold)` and then overrides
  face_point to the target, so travel's thrust (computed for facing the
  waypoint) is wrong: hold points behind/beside the ship are never reached
  (63% of "hold far" samples not approaching; 68% late game). Then the
  stuck timer fires and the ship reverses for 1 s ("unstick") mid-fight.

Pilot behaviour (domain `behavior`):
- State "home" picks a target (`think_home`) but `PilotCombat.steer()`
  only shoots while retreating/falling back: pilots flying home never shoot
  back.
- A jungler whose camps run out switches to "lane" and nothing switches it
  back when camps respawn (only a death/dock resets it).
- The flex pilot rotates lanes every 90 s (may spend most of its life
  travelling).

Pilot targeting & combat (domain `targeting`):
- The Ion Frigate's ion cannon is a FIXED forward burst beam (2 s on, 4 s
  off; a trigger pull commits to the whole burst), but `fight()` fires big
  ships whenever the target is in reach, with no nose-alignment check.
- 13% of fight samples have the target behind an asteroid (no line-of-
  sight check in `pick_target` / `prey`).
- `fight()` takes reach from `mounts[0]`, other code uses `main_reach()`
  (consistent today because every hull lists its main gun first).

Minions (domain `minions`) and admiral (domain `admiral`): no suspects yet;
start from the code and from measurements.
