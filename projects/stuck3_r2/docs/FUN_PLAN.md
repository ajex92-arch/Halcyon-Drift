# Fun experiments: the plan and the rules

This is the contract for the fun phase: what we measure, how forks test
ideas, how the council decides, and what the user has ruled. The research
behind it is in docs/FUN_RESEARCH.md (fun model, score formula, fork
briefs, the critic's fixes). Where the two differ, THIS file wins.

## 1. What the user asked for

> "Next brainstorm ways to make the game more competitive and fun, fun
> being a relative term of course but do your best to calculate what is
> fun for the average video game player who would play a game like this.
> Maybe use agents to create forks of the project and test their own
> designs and ideas, then have a council that all the agents report their
> results to. The council would then synthesize their best ideas into a new
> branch of the project that i can then playtest. Take all the time you
> need and keep the new branch modular and well notated."

> 2026-10-15: **"Don't reject anything that violates my constraints."**

So: an idea is **never thrown out because it breaks a requirement** in
docs/USER_REQUIREMENTS_2026-10-13.md. It is built as an **opt-in variant**,
measured like every other idea, and **flagged** `REQ-CHANGE: <which
requirement>` in every report. The council may adopt requirement-changing
ideas; in the council branch each one stays switchable, so the user makes
the final call.

What still gets left out: things that would make the MEASUREMENT dishonest
(game mechanics reading the scoring index, AI behaviour keyed to the skill
knob, statistical shortcuts). Those aren't design ideas; they're ways of
fooling ourselves.

## 2. Branches (folders; git isn't installed)

- `remake/` main: the notated, modular game. Shared infrastructure lives
  here. Forks and the council branch start from it.
- `forks/<name>/`: one copy per fork. Each fork works only in its folder.
- `remake-council/`: the council's synthesis, for the user to playtest.

## 3. Shared infrastructure in main (built before forking)

- **Feature switches.** Every new mechanic is a *feature module*
  (`scripts/features/<name>.gd`, plain-language notes per CODE_STYLE.md)
  installed at match start only when its variant key is on
  (`--variant=key:value`, defaults in `Rules.VARIANT_DEFAULTS` keep today's
  game). With every new key at its default, a fork must produce EXACTLY
  main's det_hash (normal 900 s + late 300 s).
- **Hooks** that features plug into instead of editing shared code:
  incoming-damage multipliers on any unit, a per-target minion damage scale
  in Combat, a push-target weight in PilotTargeting, and `Rules.tune(name,
  default)` so a feature can override any tuned number (economy, respawn,
  rebuild lock, siege settings, ...).
- **Measurement:** a probe-only per-hit event (`Events.damage_applied`), skill
  jitter for AI seats (`--skill-jitter`, the same per seat on both teams),
  usage counters (`Game.usage`, printed in FUN_JSON: a mechanic the AI
  never used proves nothing), fun_probe v2 with every metric in the fun
  model, and `tools/fun_score.py` (Python, standard library only:
  ingredient scores, FUN 0-100, paired bootstrap confidence bounds between
  two batches).
- **Simulation queue:** every full-match batch goes through the session's
  `run_batch.ps1`, which runs at most 6 matches at once at night
  (18:00-06:00, when the user lets us use the whole 6-core PC) and 3 by
  day.

## 4. How a fork tests ideas

1. Build each idea as a feature module behind its own variant key, with AI
   use (pilots or the AI admiral must actually use it) and a usage counter.
2. Checks: the fast checks, det_hash identical with every key at its
   default, doc coverage.
3. Screen each idea in the CHEAPEST scenario that measures its target
   ingredient (user, 2026-10-16), always with --skill-jitter:
   - ideas that act only after 25:00 (endgame, most admiral ideas): symmetric
     late runs (`--late --symmetric --secs=1200`, about a third of a match);
   - ideas whose target ingredient is measured by 30:00 (the early parts of
     S4-S9, e.g. travel, deaths, fight ramp, economy): matches capped at 30:00
     (`--secs=1800`), scored against baseline v2's 30:00 snapshot
     (the FUN_JSON30 line fun_probe prints at 30:00);
   - only ideas aimed at S1-S3 (match arc, endgame arc, comebacks) need full
     60-minute matches (`--secs=3600`).
   Screens STOP EARLY (sequential screening, user 2026-10-16): run the first
   half (seeds 101-106; late screens 101-110) and score it paired against
   baseline v2 on the same seeds. Stop and KEEP if the target ingredient rose
   16+ points and FUN did not fall; stop and REJECT if it rose less than 2
   points (or fell) and FUN did not rise 3+; otherwise run the second half
   (107-112; late 111-120) and apply the standard rule: keep if the target
   ingredient rises 8+ points and FUN doesn't fall. A screen only REJECTS
   ideas from the fork's combination. A screen where usage is near zero is
   invalid, not negative (fix the AI's use and rerun).
4. Run the fork's best combination on 40 seeds (101-140) against baseline
   v2. Report every ingredient, FUN with its 90% lower bound, usage, the
   ms_duel results for anything touching the mothership, and the REQ-CHANGE
   flags.
5. Lever owners (to avoid two forks pulling the same lever): hyperspace
   timing = pacing fork; turret rebuild lock = teamfights fork; siege AI =
   endgame fork. Alternatives of which at most one merges: C2(b) vs F2, and
   B3 vs B5 vs F3. No fork reads another fork's variant.

## 5. The six forks (ideas from FUN_RESEARCH.md plus restored ideas)

Every fork keeps the ideas listed for it in docs/FUN_RESEARCH.md and ALSO
builds these restored ideas (REQ-CHANGE = breaks a requirement; DESIGN =
rejected by the research on fun grounds, worth measuring anyway):

- **pacing_downtime** (A): A1 slipstream also with a FLAT speed for every
  hull (REQ-CHANGE: heavier ships travel slower); automatic respawn at a
  forward repair bay or the waypoint (REQ-CHANGE: kits are bought at the
  mothership); repair kits and gear sold at repair bays (REQ-CHANGE); a
  steeper late respawn curve toward LoL/Dota values (DESIGN).
- **endgame_closure** (B): a surrender vote (REQ-CHANGE: only a mothership
  kill ends the match; the AI team votes when far behind); an extra super
  or siege minion per wave after a breach (REQ-CHANGE: waves of 10);
  breach corvettes with full damage against the mothership (REQ-CHANGE);
  less mothership hull/shield or a bigger big-ship multiplier (REQ-CHANGE:
  "a lot of health", "barely beats frigates"); B3 at full strength as well
  as the softened version; fewer or no free waves late (REQ-CHANGE).
- **economy_comebacks** (C): shared team XP or a flat catch-up income for
  the trailing team (DESIGN); C2 comeback bounties split equally (DESIGN);
  pilot mining of hardpoints / personal extractors (REQ-CHANGE: removed by
  the user); the mothership weakening after big treasury spends
  (REQ-CHANGE: reversed by the user); a push/morale meter that strengthens
  the next waves after kills (DESIGN).
- **teamfights_jungle** (D): a timed epic neutral at the crossing (a
  Derelict Dreadnought with a Baron-style team buff) and the late "Elder
  Core" buff (REQ-CHANGE: no timed/dynamic events); capture points /
  salvage beacons with a sensor-blackout reward (REQ-CHANGE); a fourth
  jungle clearing per quadrant (DESIGN, map-generation risk); an early
  "feats of strength" race (DESIGN).
- **combat_roles** (E): big ships allowed into the jungle (REQ-CHANGE: only
  small ships fit); a wider maximum zoom (REQ-CHANGE: zoom lock; measure
  vision-driven effects only).
- **admiral_command** (F): Sensor Sweep that sees through asteroids
  (REQ-CHANGE: line of sight); moving the mothership before 20:00 or while
  the admiral flies (REQ-CHANGE); a defenders' home-field vision advantage
  (DESIGN); an admiral-swap / mutiny rule (REQ-CHANGE: locked role; only
  meaningful with a human admiral, so judge it on paper unless it can be
  simulated).

Also in main, as a variant (not a fork idea): `escort_wing` = `extra`
(default, today's game: Escort Wing adds an 11th minion, a second escort
corvette, to each lane's wave; REQ-CHANGE: waves of 10) or `upgrade` (the
requirement-compliant version: the single corvette gets +40% hull and +15%
weapon range).

## 6. The council

Judges with different lenses (competitive MOBA player, new/casual player,
space-combat pilot, RTS/admiral player, game designer and producer for
scope and risk, engineer for modularity) read every fork report and score
every idea that survived screening. A chair synthesizes a combination; the
combination is built in `remake-council/` from main by porting the chosen
feature modules; it must reach FUN +5 over baseline v2 with a 95% lower
bound above 0 on 80 seeds, with every ingredient checked on its 80%
interval. Requirement-changing ideas in the council branch stay behind
switches, grouped into two presets: "within requirements" and "council's
pick". The final report lists every REQ-CHANGE in plain words.

## 7. Compute budget

One 60-minute match takes 20-50 minutes of wall time depending on load;
the machine runs 6 at once (about 8-12 matches an hour). Budget about 60
match-equivalents per fork (a `--late` run counts as a third), 40 for
baseline v2 and 80 for the council. Forks share the queue, so they run
for many hours: that's expected.

(Seed counts raised 2026-10-16 by the user's choice to spend the free cloud runners on
statistical power: screens 12 seeds in two halves of 6, late screens 20 in halves of 10,
final combinations 40, council validation 80; baseline v2 extended to seeds 141-180 and late 111-120.)
