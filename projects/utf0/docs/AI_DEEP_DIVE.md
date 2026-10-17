# Halcyon Drift: AI deep dive report (pilots, minions, admiral)

Written 2026-10-16. Plain-language report of the deep dive into the AI pilots,
the minions and the AI admiral, done before the fun plan. Every number below
comes from all-AI test matches run on this PC (about 500 logged runs); the
raw notes are in the session scratchpad (`deepdive\`), not in the project.
State of the code: pass 1 is in the game (banked 2026-10-16 02:20), pass 2 is
ported, reviewed and being banked, pass 3 is planned (section 4).

Words used in this report:

| Word | Meaning |
|---|---|
| seed | A number that fixes the random draws of a match. Same seed and same build = exactly the same match, so two builds can be compared fairly. |
| A/B | Run the old and the new build on the same seeds and compare the counters. |
| switch | A command-line flag that turns one fix on or off (off = the old game), so each fix can be measured alone. |
| 900 s / 15 min | One normal test match, cut at 15 minutes of game time. "30 min" = 1,800 s. |
| late-game run | A match that starts at 25:00 with everything researched (`--late`), run for 300-900 s. Used for big ships, sieges and the endgame. |
| ship-seconds | Seconds counted once per ship (10 ships for 5 s = 50 ship-seconds). |
| sample | One look at a pilot (twice a second). "Occluded samples" = looks where the target was behind a rock. |
| u/s | Units per second. A fighter is 24 units across; a lane is 3,600 wide. |

---

## 1. Summary

**Why.** You were worried that the fun measurements (hundreds of all-AI
matches) would be skewed by bad AI behaviour. So before the fun plan we hunted
for every way the pilots, minions and admiral play wrongly or badly enough to
distort the data.

**The eight biggest problems found** (the game as it was before the deep dive;
"6 matches" = seeds 7, 11, 13, 17, 19, 23, 15 minutes each):

1. **Pilots got stuck in rocks and stayed stuck.** 209 stuck episodes and 3,274 stuck ship-seconds in 6 matches. About one ship in every one or two matches was wedged for the rest of the match in a 24-26-unit gap between two rocks, always at the same map spots. In every match the first jungler crashed into the same gate wall at 13 s.
2. **Ships flew into rocks, sometimes to death.** 7,425 ship-seconds of rock contact and 28 pilot deaths by crashing in 6 matches.
3. **Shooting at targets hidden behind asteroids.** 4,024 firing samples with the target hidden (6 matches). In 3 matches, 24.5% of bomber torpedoes and 11.3% of fighter rounds went into rocks.
4. **Big ships did not reach their firing position.** 1,413 samples of "far from the firing spot and not approaching" in 6 matches (in the first audit, 58% of the samples where a big ship was far from its spot, 68% in the late game).
5. **Minions mostly missed.** Only 19-22% of fighter-minion bolts and 7.5-9% of bomber-minion torpedoes were on a path that could hit (3 matches).
6. **The admiral pushed the wrong lanes and its sieges did nothing.** Mid was picked as the push lane 5-13% of the time, against 14-36% by real progress. No normal 30-minute match ended (0 of 3), the enemy mothership lost about 1% hull, and 3 of 5 late-game sieges sent the mothership 13,400 units up the wrong lane (a 170 s sail).
7. **Smaller breakages.** A repair kit used by a ship flying 450 u/s healed 0.9 of its 50 hp. The Lance beam was on target 49% of its ticks and its Overload was never used (0 of 15,967 samples). After 10:00 the mid lane had no pilot in it for 8-35% of the time. Repair bays lived about 3 minutes and cost each team 5,000-8,500 credits per match. Each team sent 100-255 pointless failed turret orders per match.
8. **Pilots retreated at the last second.** 98% of pilot deaths happened in the "retreat" state; a retreat started at about 17% of total health and 63% of retreats ended in death (3 matches).

**What was fixed.** 35 fixes kept, in three passes (18 in the game, 10 being
banked, 7 planned). About 20 ideas were tried and dropped. 12 items are left
as decisions for you (section 5); four of them touch a requirement and are
marked `REQ-CHANGE`.

**Before / after** (6 matches of 15 min, same seeds, old game vs the game with
passes 1 and 2; lower is better except where noted):

| Measure | Old game | After pass 1 | After pass 2 |
|---|---|---|---|
| Stuck episodes | 209 | 37 | 33 |
| Stuck ship-seconds | 3,274 | 256 | 356 |
| Rock contact, ship-seconds | 7,425 | 2,060 | 2,026 (-73%) |
| Rock contact while fighting, ship-seconds | 2,994 | 928 | 823 |
| Firing at a hidden target (samples) | 4,024 | 113 | 98 (-98%) |
| Crash deaths | 28 | 2 | 3 |
| Big ships not approaching their firing spot (samples) | 1,413 | 653 | 660 (-53%) |
| Pilot deaths (higher is NOT better) | 447 | 617 | 662 (+48%) |
| ... killed by pilots | 306 | 389 | 381 |
| ... killed by minions | 95 | 190 | 246 |
| ... killed by turrets | 11 | 27 | 30 |
| Minion bolts / torpedoes on a hitting path (3 matches) | 19-22% / 7.5-9% | 78% / 47% | same |
| Admiral: push lane = mid (30 min, 3 matches) | 8% | 8% | 34% |
| Admiral: failed turret orders per match, both teams (30 min, 3 matches) | 275 | 141 | 0 |

Late game (3 matches, 25:00 + 300 s), old / pass 1 / pass 2: stuck episodes 69 /
50 / 35; rock contact 935 / 301 / 342 s; hidden-target firing 428 / 71 / 9; big
ships not approaching 4,632 / 2,487 / 1,794; pilot deaths 83 / 87 / 96.

**Why pilot deaths rose by 48%.** It is a real change of the game, not noise
(higher in 6 of 6 seeds). Four causes, measured:
1. Pilots no longer stuck, crashing or shooting rocks find each other. The flight fixes alone: deaths +17% (higher in 6 of 6 seeds), deaths by other pilots +28%.
2. Minions now hit what they aim at. Minion damage to pilot ships 16,383 -> 23,566 (+44%) and deaths by minions 56 -> 86 on 3 matches (pass 1). Pass 2 adds more: minion deaths 190 -> 246.
3. Retreats come too late (problem 8), so almost every fight that goes badly ends in a death.
4. Pilots that no longer sit stuck spend more time near enemy turrets (turret deaths 11 -> 30; the old game's count of 11 was unusually low).

Pass 3 is aimed at this. The minion re-targeting fix cut deaths by minions
86 -> 49 in its own test (3 matches). The retreat knob (also pass 3) cut total
pilot deaths 340 -> 255 (-25%, lower in 3 of 3 seeds) on the game after pass 2.
These two have not yet been measured stacked on one build.

**Verdict on more digging: not worth another round.** The last round
(residuals) found nothing bigger than about 1-2% of pilot time or about 5% of
deaths, which is smaller than what 3 matches of 15 minutes can even resolve
(deaths vary by +-5% from run to run, damage to pilots by +-5-10%). Stuck ships
are now 19 episodes / 100 seconds in 58,000 ship-seconds (0.17%). The findings
shrank from 209 stuck episodes in six matches to about one trapped bomber per
two matches. What remains is design choices (section 5), not AI defects.

**How sure are we.** Big effects (stuck, rocks, hidden shots, minion aim, lane
choice) are large and consistent across seeds; changes of +-10% on small counts
are noise. Admiral evidence in normal 30-minute matches is thin (1-3 matches).

---

## 2. How it was done

**Investigators, one per domain.** Flight and pathing; pilot behaviour;
targeting and weapons (two rounds); minions (two rounds); the AI admiral; and a
final "residuals" round chasing the leftovers. Each was a separate AI agent
that read the code, wrote a probe (a test script that counts things), measured,
proposed a fix and tested it. The first workflow also had a "skeptic" agent per
domain. That workflow was stopped by the usage limit, so its 24 half-tested
fixes were rebuilt from their code and notes and re-measured from scratch.

**Every fix behind a switch.** In the investigators' scratch copies each fix
was off by default, so "no switches" reproduced the old game exactly. Each fix
was measured alone and then in bundles, because a bundle can hide a bad fix:
the first flight bundle looked good but raised rock contact while fighting 4.6x
until single runs found the culprit (fix H, dropped).

**Paired seeds and match lengths.**
- Normal tests: 3 seeds (7, 11, 13), later 6 (adding 17, 19, 23), 900 s each. Old and new build run on the same seeds.
- Late-game tests: start at 25:00, 300 s (pilot audits) or 900 s (admiral).
- Long tests: 1,800-2,400 s (30-40 minutes) for the admiral and the Hyperspace Module.
- About 500 logged runs in total; all went through one shared queue (3 at a time by day, 6 at night).

**Two main probes.** `tests/pilot_audit.gd` (in the game) watches every AI
pilot: stuck episodes, rock contact, firing at hidden targets, big ships not
reaching their spot, missing routes, target switches, deaths by cause. A twin
for the admiral, `tests/admiral_audit.gd`, counts every admiral order and its
result, siege events, treasury, lanes and bays. Smaller benches reproduced one
problem in isolation: ships placed at 12 recorded trap spots, 37 one-on-one
duels with a rock between, a repair-kit speed test, a jungle-monster shield test.

**Honest about noise.** Any change alters every later event of a match, so
"paired" seeds only stay paired up to the first difference. With 3-6 matches,
counts dominated by one long-trapped ship (stuck seconds, time spent flying
home) swing by tens of percent. Rules used: report "lower in n of 6 seeds",
treat changes under about +-30% on small counts as chance, and re-run with more
seeds before believing a surprise. The method caught its own mistakes: a "home
trips are 2.4x longer" regression turned out to be noise (the old game's own
home time varied 462-1,559 samples between seeds); some early benches used ships
of the wrong team and were thrown away.

**Adversarial review of the ports.** The investigators' fixes lived in scratch
copies with test instrumentation. A second agent ported each set into the real
code and proved the port identical: the ported flight code matched the switch
copy in 15 of 15 audit lines and 52 of 52 counters; the minion port in 10 of 10
lines and 49 counters; pass 2's targeting port in 15 of 15 lines and 52
counters; pass 2's admiral port in 30 of 30 lines and 176 counters ("bit-
identical" = the same match event by event). A third agent then tried to break
each port.
- Pass 1 review found six real issues. The worst: the escape planner for trapped ships (fix U) could freeze the game (mean 85 ms per plan, up to 698 ms). It now has a counted work budget: mean 11 ms, worst 63 ms, never over 100 ms in real matches. The other five were wrong or missing documentation.
- Pass 2 review: all 10 ports faithful; 4 minor documentation slips (for example the turret rebuild lock is 60 s, not 25-30 s). The new line-of-sight checks cost about 0.1% of the simulation.

**Determinism, speed, checks.** Same seed and same build give the same match,
checked after pass 1 (two runs identical over 300 normal and 60 late lines of
the match fingerprint) and after pass 2. Because rock-gap sealing changes the
map from t=0, new fingerprint baselines were installed (old ones kept as
`_v2`). Pass 1 is not slower (346-366 ms per simulated second against 379-397
for the old build; pass 2: 326 vs 325). After every port the fast checks
(import, load_all, bot_pilot, support_probe, ui_pilot, ui_admiral) were all OK
and documentation coverage was 181 of 181 files.

---

## 3. Findings by domain

Verdict words: **kept** (in the game or queued), **dropped** (measured, no gain
or harm), **design call** (a taste decision, section 5), **optional** (small,
left out). All "effect" numbers are old vs new on the same seeds.

### 3.1 Flight and pathing

Measured with the flight probe on 6 matches of 15 min per arm, plus benches at
the recorded trap spots. Lower in "n of 6" = how many seeds improved.

| Problem found | Fix | Measured effect | Verdict |
|---|---|---|---|
| A short hop inside a lane flew straight at the goal even through rocks. The first jungler crashed into the same gate wall at 13 s in every match, and lance junglers wedged there. | **A** route around rocks when the straight line is blocked | Stuck seconds -56% (6 of 6). Lance stuck at the gate in 5 of 6 logs -> 0 of 6. Crash deaths -43%. Bench: lance arrivals 5 of 7 -> 7 of 7. | kept |
| The route graph's dots at The Crossing sat inside its rock field. | **B** split such a dot into two, 1,050 either side | Firing at hidden targets -31%, crash deaths -46%, rock contact while fighting -26% | kept (modest) |
| Big ships steered by the target while travelling to a firing spot behind them, so they never arrived; the stuck timer then reversed them mid-fight. | **D** keep travel heading until within 500 of the spot | Big ships not approaching 1,413 -> 367 (-74%, 6 of 6) | kept |
| A ship sliding tail-first into rock got reverse thrust, pushing it deeper. | **E** brake with the main engine | Stuck episodes -33% (6 of 6), crash deaths -57% | kept |
| Strike craft chased and fired at targets behind rocks. | **I** hold fire at a hidden target, drop it after 3 s | Firing at hidden targets 4,024 -> 209 (-95%), rock contact while fighting -47%, crash deaths -50% | kept |
| Ships wedged in rock notches stayed trapped (96-140 unsticks, 260-650 s each). | **U** escape planner (plus a work budget after review) | With I and M: trapped ships 24 -> 12. Bench: 11 of 12 trap spots escaped, was 8 of 12. | kept |
| 464 rock gaps of 17.5-34 units: a ship can enter, not leave. All recorded traps touched two rocks at once. | **M** grow the rocks so those gaps close | No jungle route closed (static check). Trapped ship-seconds fell with U. | kept |
| Boost-speed arrival at gate corners. | **O** speed cap on tight turns | Bench: lances arriving 3 of 5 -> 5 of 5, rock contact 82 s -> 0.5 s | kept (small) |
| Bombers circled jungle waypoints (turning circle 226 > reach 110). | **X** wider waypoint reach for bombers | Bench: 7 of 8 -> 8 of 8 arrive, unsticks 8 -> 4 | kept (small) |

Bundle `A B D E I U M O X`, 6 matches: stuck episodes 209 -> 64 (-69%, 6 of 6),
stuck seconds 3,274 -> 370, trapped ships 24 -> 7, rock contact 7,425 -> 2,895
s (-61%), crash deaths 28 -> 3, hidden-target firing 4,024 -> 135, big ships
not approaching 1,413 -> 356. Late game (3 matches): stuck episodes 69 -> 25,
rock contact 935 -> 140 s. Cost: pilot deaths +17% (more fighting, see 1).

Dropped or optional:
- **H** (route strike craft to a hidden target): rock contact while fighting x4.2 (693 -> 2,935 ship-seconds on 2 seeds); craft near walls took jungle routes and hovered. Replaced by I.
- **V** (retrace own path out of a trap): trapped ship-seconds 895 and 653 against 146 and 13 without it; the ship walked back in.
- **G** (extra route dot before a gate): worse (fighters 3 of 5 arrive, lances 4 of 5). **W** (reverse without sideways thrust) and **P** (bombers on lane-only routes): no gain.
- **R** (route cost = flying time, jungle shortcuts count double): orbits -91%, crash deaths -86%, long home trips -31%, but pilot deaths +8%. Optional; not ported. It changes pace.

### 3.2 Pilot behaviour

Behaviour probe, 3 matches of 15 min (kit, rally, routing, jfocus), long 40-minute runs for the Hyperspace fix.

| Problem found | Fix | Measured effect | Verdict |
|---|---|---|---|
| Repair-kit drones trailed a fast patient out of heal range. | **kit** drone adds the patient's velocity | Bench: kit at 450 u/s healed 0.9 -> 46.8 of 50 hp. Matches: drone-samples inside heal range 21% -> 71%. | kept (humans too) |
| After 10:00 the "odd seats" rally took the whole mid trio (seats 1, 5, 9) to the waypoint. | **rally** seats 4, 5, 6 (one per lane) + the flex | Mid lane with no pilot, after 10:00: 17 / 35 / 8% -> 0 / 2 / 0% of samples. Turret deaths 2 -> 7 (small ships now stand at the waypoint). | kept |
| Energy went to weapons for any target, also far or passed ones. | **routing** count real fights only | Weapons-routing while flying to a far target 2,942 -> 29 samples | kept (minor) |
| Junglers never angled shields at the monster hitting them. | **jfocus** | Shield angled when hit 3.8% -> 45% (only the high-skill seat does it). Jungler deaths 5 -> 2. | kept (minor) |
| The AI never used the Hyperspace Module the admiral builds. | **hyper** jump to the bay nearest the front | 15-minute matches: no change (the module is the last plan step). 40-minute matches: 11-54 jumps, about 1% of pilot time. | kept (minor) |

Dropped: **home** and **home2** (shoot while flying home): the suspected
"turns to fight, flies home slowly" mechanism was refuted in a one-ship test,
and over 3 matches the trigger was pulled on only 15 samples. **flex** (flex
pilot dwells longer): lane changes 110 -> 135, no gain. **retbig** (retreating
big ships look further): identical to the old game in all counters (only 429
samples). **jret** (jungler returns to jungle when camps respawn): the situation
never happens (0 samples in 7 matches of 15-40 min; 8.4 of 12 camps are up on
average).

Observations, not bugs: (a) 42% of flying time is "travel", mostly the commute
from the mothership to the lane (small ships 19.8 s per trip, frigates 121 s);
changing map size, base position or respawn moves it more than any combat
change. (b) Bombers are the whole bot lane and almost never kill pilots: 5
pilot kills in 3 matches against 139 by fighters. (c) 53% of retreating pilots
died before docking (81% in the late game, where big ships are slow).

### 3.3 Targeting and weapons

Round 1: 3 matches of 15 min per arm with a shot probe. Round 2: 3 matches (6
for stick and hp2), baseline = round 1's kept set.

| Problem found | Fix | Measured effect | Verdict |
|---|---|---|---|
| Beam weapons (Lance) aimed at a lead point, though beams hit instantly. | **beam** aim straight at the target | Lance beam ticks on target 48.7% -> 78.8% (85-88% in bundles) | kept |
| No line-of-sight check when picking targets. | **los** +700 score for a hidden target (hold fire comes from flight fix I) | Fighter rounds at hidden targets 8.9% -> 1.3%, into rocks 11.3% -> 3.6%. Bombers 17.8% -> 0.9% and 24.5% -> 5.2%. Pilot audit: hidden-target firing 2,216 -> 253, crashes 14 -> 3. | kept |
| The Lance never used its Overload (0 of 15,967 samples). | **ovl** use it while the beam is on | Mechanism fix, the number above is the measure | kept |
| The Ion Frigate's fixed burst beam (2 s on, 4 s off) fired with the nose off target. | **ion** fire only nose-on | Rare hull (3 bursts in 45 min of play): correctness | kept |
| Targets re-picked from scratch every think; "damaged" ignored shields (a fighter is 100 hull + 200 shield). | **stick** keep the pilot we shoot (+250, to 1.3x range) and **hp2** damage counts hull + shield | Target switches -18% (20,198 -> 16,515, lower in 6 of 6), flip-flops -21%, pilot kills +10% (5 of 6 up, noisy), deaths by minions 102 -> 61 | kept (small) |
| Bombers fired torpedoes (x0.35 vs small craft) at small minions: 76% of 2,167 torpedoes. | **bsm** bombers in a lane skip small non-structure targets | Torpedo hit rate 17.9% -> 39.2%, bomber damage 48,610 -> 82,959 (+71%), bombers idle in lane 48% -> 70% of the time | kept |

Dropped: **aim2** (each turret leads with its own round speed): flak hit rate
59.8% -> 53.2%, no gain. **bd** (+1,500 for turrets under backdoor protection):
identical to the old game in 3 seeds, never triggers. **focus** (prefer the pilot
an ally targets): allies already share a target in 82% of 19,503 pairs.
Refuted by numbers, no fix: fighters ignoring weak pilots (they shoot a pilot
under 35% hull 93.8% of the time), chasing into turrets (2.2% of fight time),
idling with enemies in sight. Design calls **eff** and **ms**: section 5.

Caveat: a 2-seed audit of round 2 showed slightly more stuck and rock contact
in every arm; with so few seeds that is unproven. Pass 2's 6-seed audit (which
does not include stick, hp2 or bsm) shows stuck and rock contact about unchanged
(section 1); pass 3 still needs the same 6-seed audit.

### 3.4 Minions

3 matches of 15 min; runs are deterministic, so differences are the fix.

| Problem found | Fix | Measured effect | Verdict |
|---|---|---|---|
| Fighter and bomber minions have fixed guns and compute a lead point, but faced the target. | **lead** face the aim point | Fighter bolts on a hitting path 19-22% -> 78-79%, hits 21-26% -> 59%. Bomber torpedoes 7.5-9% -> 47-48%, hits 13-14% -> 30%. Bolts into rocks 8-24% -> 1.5-1.8%. | kept |
| Fixed guns fired whenever in reach: 23-25% of torpedoes went off at 90+ degrees. | **gate** fire only when the nose is on the aim point | 23-25% -> 0.3-1% | kept |
| Minions started outside their lane flew straight through the jungle. | **route** fly to the lane first | Minor | kept |
| Minions kept targets behind rocks (5-20% of fighter fight time). | **los** drop blocked targets | 0.2-0.4% | kept |
| A minion never re-picked while its target was valid: 13.6% (fighters), 17.3% (bombers), 21.0% (corvettes) of fight time went on a target scoring 600+ worse than the best. | **retarget** re-pick when another scores 600+ better | Stale time 13.6 / 17.3 / 21.0% -> 1.6 / 1.3 / 1.5%. Minion damage to pilot ships 23,566 -> 16,982 (-28%). Pilot deaths by minions 86 -> 49. | kept (pass 3) |

Side effect of round 1, and how retarget answers it (3 matches summed):

| | Old game | 4 minion fixes | + retarget |
|---|---|---|---|
| Minion damage to pilot ships | 16,383 | 23,566 (+44%) | 16,982 (+4%) |
| Pilot deaths, all causes | 221 | 275 | 228 |
| Pilot deaths killed by minions | 56 | 86 | 49 |
| Pilot last hits on minions (income) | 766 | 603 | 525 (-31%) |

The cost of retarget: minions switch target about every 7 s instead of every
28 s (2 -> 7-9 switches per fighting minute) and pilots land a third fewer last
hits because waves kill each other sooner. Shots did not suffer (hit rate 59.1%
-> 60.1%). Measured clean: minions idle while walking 0.1-0.8% of the time,
inside rocks 0.1-0.3%; no side bias (the wave wiped first is team 0's in 54.2%
of 201 pairs, and the sign flips between builds). Design call **lanespawn**:
section 5.

### 3.5 The AI admiral

Probe `admiral_audit`: normal 1,800 s and late 900 s, seeds 7, 11, 13 (and 17,
19, 23 for the late baseline). Evidence for normal matches is 1-3 seeds.

| Problem found | Fix | Measured effect | Verdict |
|---|---|---|---|
| The push lane was picked by raw distance, but top/bot lanes are 44,200 long and mid 33,600, so mid was almost never chosen. | **lane** compare the fraction of the lane | Push on mid 8.3% -> 32.7%, waypoint on mid 11.8% -> 27.1% (6 matches, 30 min). Disagreement with the true front 21% -> 0%. | kept |
| Turret orders at a node whose turret just died were retried every second during the 60 s rebuild lock. | **guard** skip locked nodes | Failed turret orders per match 358 -> 0 (6 matches) | kept |
| Two drones could be ordered per think, and orders went into a full queue. | **drone** recount; never order into a full queue | Late game: 18-48 failed orders per team-match -> 0 | kept (trivial) |
| The defend alarm (7,000 from the hull) was tuned for a mothership at home; parked forward it reaches mid and blocks sieges. | **def** radius 4,000 once forward; **defs** during a siege only a push within 2,500 of our hull counts | Defending seconds 781 -> about 320 (-60%, late, 3 matches). Alone it does not help sieges. | kept |
| The siege lane was picked by fewest turrets, then re-aimed 1 s later; meanwhile our mothership sailed up the wrong lane (3 of 5 sieges). | **sl** declare the siege on the lane the parked enemy mothership is on | Late, 6 matches (def + defs + sl): assault seconds 173 -> 494 (x2.9), assault contact 102 -> 230 s, defending 731 -> 277 s, hull lost in assaults 0.7 -> 0.9 | kept |

Refuted: bays are placed on all three lanes (only 2 failures, for money). The
stall check works (sieges that did no damage were called off after 100-175 s).
Siege lane hopping has the same root as the wrong-lane sail.

Dropped: **def2** (a variant of the defend-alarm fix); **bayB** (not measured in time); **bayC** (1,800 off the
lane line: no bay could be placed at all); **bayE** (only behind the wave front:
bays alive 1.5 against 2.6, too little coverage); **mmid** (park on mid unless
sieging: the first siege still sent the mothership the wrong way).

Design calls (section 5): **mmid2**, **bayA**, the treasury pile-up, late drone
losses of 19-75 per team. Check on the integrated game (3 matches, pass 1 vs
pass 2, 30 min): push mid 7.7% -> 34.0%, waypoint mid 7.3% -> 29.6%, defending
108 -> 44 s, failed turret orders 141 -> 0, still 0 of 3 matches ended. Late
game: assault seconds 206 -> 648, assault contact 142 -> 305 s.

### 3.6 Residuals (last round)

Starting from the leftovers, on the game after passes 1 and 2 (3 matches of 15
min, 3 late matches of 300 s).

| Lead | Finding | Verdict |
|---|---|---|
| R-1 Retreat triggers on hull only | 340 pilot deaths, 334 (98%) in retreat; 457 retreats, 63% ended in death, 252 within 4 s. A fighter flees with about 17% of its total health left. **ret25** (also retreat below 25% of hull + shields) cut deaths 340 -> 264 (-22%, lower in 3 of 3 seeds) for -3% damage to enemy ships. **retsmall** limits it to ships smaller than a frigate. | kept; threshold is a design call |
| R-3 Big ships "trapped beside their mothership" | Pinned against a mothership hull: 4.6% of late pilot time touching, 2.1% pinned (battlecruisers 7%). **msa** slides ships along the hull: touching -86%, pinned -95%, stuck seconds 238 -> 40. | kept |
| R-2 Flak frigates in sieges | Flak did 16 points of damage to motherships in 3 matches; the real loss is that the mothership target blocks other targets. **flaksg**: fire at minions during sieges +273%, no effect on outcomes. | optional, skip |
| R-4 One dominant cause of the extra deaths? | No: 57% by pilots, 38% by minions, no map hot spot (largest cell 26 of 340), flat over time. | closed |
| R-6 Bombers in the south-rim pockets | One trapped bomber per 1-2 matches, about 0.1% of pilot time. Gaps are just over the 34-unit seal limit. | not fixed |

Side effect of msa: ships now arrive at sieges, so the stall rule (under 15%
hull lost in 120 s means the siege is called off) ends sieges sooner: siege
samples fell about 55%. Mothership damage did not change (27.7k -> 28.3k).
Combined retreat + msa run: pilot deaths 340 -> 255 (-25%), damage to enemy
ships -8% (lower in 3 of 3); with skill jitter 309 -> 247 (-20%); late 96 -> 82.

---

## 4. What is now in the game

**Pass 1 (in the game since 2026-10-16 02:20; 18 fixes, 20 files).**
- Flight. **A** short hops route around rocks if the straight line is blocked. **B** The Crossing's route dots are split around its rock field. **D** big ships keep their travel heading toward a far firing spot. **E** a ship sliding tail-first into rock brakes with the main engine. **I** pilots hold fire at a hidden target and drop it after 3 s. **U** an escape planner frees ships wedged in rock notches (new file `pilot_escape.gd`, with a work budget so it never stalls a frame). **M** rock gaps narrower than a ship are sealed when the map is built (464 gaps, about 720 rocks change by 6.5 units on average). **O** tight turns at gates and corners have a speed cap. **X** bombers use a wider reach at jungle waypoints.
- Behaviour. **kit** repair-kit drones follow a moving patient (also for human players). **rally** the late rally takes one seat per lane instead of the whole mid trio. **routing** energy goes to weapons only in real fights. **jfocus** junglers angle shields at the monster hitting them. **hyper** the AI uses the Hyperspace Module.
- Minions. **lead** fixed-gun minions aim at the lead point. **gate** they fire only when lined up. **route** they fly to their lane first if they start outside it. **los** they skip targets behind rocks.

**Pass 2 (ported and reviewed, being banked; 10 fixes, 12 files).**
- Targeting. **beam** beam weapons aim straight at the target (this also removes the lead from the battlecruiser's heavy cannon, which is a beam). **los** a target behind rocks scores 700 worse when picking targets. **ovl** the Lance uses Overload while its beam is on. **ion** the Ion Frigate fires its fixed burst only nose-on.
- Admiral. **lane** the push lane is compared by fraction of the lane, not raw distance. **guard** no turret orders at a node under rebuild lock. **drone** no second drone per think, no orders into a full queue. **def** the defend alarm radius is 4,000 once the mothership is forward. **defs** during a siege only a push within 2,500 of our hull raises the alarm. **sl** a siege is declared on the lane the parked enemy mothership is on.
- Also arrives with it: `tests/admiral_audit.gd`.

**Pass 3 (planned; 7 fixes).**
- Minions and targeting. **retarget** a minion switches to a target scoring 600+ better. **stick** keep shooting the enemy pilot we are on (+250, to 1.3x range). **hp2** "damaged" counts hull + shield, not hull alone. **bsm** bombers in lanes skip small non-structure targets.
- Residuals. **msa** ships slide along a mothership hull instead of pinning on it. **ret25** small ships also retreat below 25% of hull + shields and return at 70%. **retsmall** that soft retreat applies to ships smaller than a frigate only.

---

## 5. Decisions for you

None of these is a bug. Items 1-5 are opt-in variants that are not in the game.
Item 6 is queued in pass 3 as ret25 and needs your OK. Items 7-10 are tuning
questions. Items 11-12 are already in the game (pass 1). Per your 2026-10-15
rule, ideas that break a requirement are kept as variants and flagged
`REQ-CHANGE: <requirement>`.

### 1. mmid2: motherships always park on mid
- **What it changes.** The admiral advances the mothership only up the mid lane. Now each team parks on the lane it was pushing at 20:00, which the old lane bias made top or bot; the two motherships ended about 30,000 units apart.
- **Numbers.** Old game, normal 30 min: 0 of 3 matches ended, enemy mothership hull lost about 1%, motherships spent 953 s moving. With mmid2 (2 seeds, 1,800 s): both matches ended (1,504 s and 1,436 s, Cinder's mothership destroyed both times), moving time 299 s. With the milder "mmid" (1 seed): ended at 1,687 s. After pass 2's fixes alone: still 0 of 3 end in 30 minutes.
- **Caution.** Aurelian won both mmid2 matches; team 0 decides first. Check for a side bias on 6+ seeds before using it for the fun runs.
- **REQ-CHANGE (borderline): "pushing lanes to destroy the enemy mothership"**, and the admiral choosing where the mothership goes. Top and bot would no longer see a mothership advance.

### 2. lanespawn: late minions launch from the lane ends
- **What it changes.** After the mothership moves (from about 21:00) minions launch from it. The two lanes it is not on get their waves 30-75 s late and from the side. This makes launches use the lane's home end instead.
- **Numbers (late seed 7, 500 s, one match each).** Minion time more than 1,800 from the lane 25-37% -> 0% (in the 15-minute opening: 0.2-0.5%). Top and bot waves meet 65 s after launch, like the opening. Minion damage to turrets 45,083 -> 3,220. The match ran the full 500 s instead of ending at 372 s.
- **Why a call.** Without it, after 21:00 "lane waves" are really "mothership waves", a constant bias for every variant. With it, moving the mothership forward loses its value as a siege tool.
- **REQ-CHANGE: "minions ... spawn from the mothership regularly"** (and DESIGN.md says launches follow the moved mothership).

### 3. eff: weapon-aware target choice
- **What it changes.** Target score includes the weapon's damage table. The flak frigate chose a target with less than half the best multiplier in 39.4% of fight samples, battlecruisers 24.3%.
- **Numbers (late, 3 matches x 450 s).** Poor choices flak 39.4% -> 25.5%, battlecruiser 24.3 -> 16.3, ion 19.1 -> 9.3, destroyer 16.2 -> 7.8. Damage per fight second battlecruiser 170 -> 206, destroyer 110 -> 182. But all 3 matches ended 30-170 s earlier (1,778 / 1,801 / 1,921 s, the baseline reached its 1,950 s cut), and pilot kills per 100 game seconds fell 7.8 -> 6.1.
- **REQ-CHANGE:** none. It shortens sieges, so it changes how matches end.

### 4. ms: small craft stop sieging the mothership
- **What it changes.** Small non-bomber ships no longer attack the enemy mothership or push to it with 3+ minions there. Not measured on its own (it was only in the round 1 bundle).
- **REQ-CHANGE: "Larger ships should not be inherently better than smaller ships, both should be needed to push lanes".** It makes pushing the mothership a big-ship job.

### 5. bayA: repair bays placed further back
- **What it changes.** Bays go 0.22 down the lane instead of 0.33, where the first clash passes. Bays died after 154-189 s: 20 of 23 killed by enemy minions.
- **Numbers (late, 900 s).** Bay life 160 s (4 matches) -> 300 s (3 matches), bays dying per match 6.5 -> 4.0, credits spent on bays 5,500 -> 4,350 (-21%). Not tested in normal matches, where the poorer side spent 8,550 credits (13% of its spending) on bays that lived 81-93 s.
- **REQ-CHANGE:** none.

### 6. Retreat threshold: ret25, ret35 or the old rule
- **What it changes.** How careful AI pilots are. Old rule: retreat at 35% hull, which is about 12% of a fighter's total health.
- **Numbers (3 matches, paired).** Old 340 deaths, damage to enemy ships 122k. ret25: 264 deaths (-22%), 119k (-3%). ret35: 218 deaths (-36%), 108k (-12%, lower in 3 of 3). ret45 (seed 7 only): -41% deaths, -22% damage. Time spent in retreat 7.8% -> 10.6% -> 11.1% of flying time. Retreat deaths were lower in 12 of 12 paired runs. Applied to big ships too (late game): deaths -20% but damage -15% and battlecruiser siege samples -54%, which is why pass 3 uses retsmall.
- **Recommendation.** ret25 is where damage output is still unchanged; the choice between 25 and 35 is how deadly you want matches to be.
- **REQ-CHANGE:** none. Big ships keep the old rule, in line with "stepping out of position should be rewarded quickly with death".

### 7. Minion damage now that minions hit what they aim at
- **What it changes.** Minion damage was tuned when most shots missed. Now they land (section 3.4). With retarget, pilot damage is back to the old level (16,982 vs 16,383), but pilots get a third fewer last hits on minions (766 -> 525), because waves kill each other sooner.
- **Knobs.** `Rules.MINION_VS_SHIP_MULT` (0.6, minion damage against pilot ships), and `Rules.MINION_VS_MINION_MULT` (1.8) or the bounty if pilot income from minions matters for the fun score.
- **REQ-CHANGE:** none.

### 8. Bombers' role
- **Numbers.** Bombers die as often as fighters (2.1 vs 2.0 per 1,000 flying samples) but killed 5 pilots in 3 matches against 139 by fighters. They are the whole bot lane (seats 2, 6, 10); the bot lane's pilot kills per death is 0.38, against 0.71 top and 0.93 mid. They did 0 torpedo damage to a mothership in 3 late matches (71% of the assault they were more than 3 weapon-reaches away). bsm only stops wasted torpedoes; they still idle 70% of the time in lanes. Separately, the bomber minions do 11% of minion damage with 40% of the bodies (tuning).
- **Options.** Leave it; seat fewer bombers in the bot lane; raise torpedo damage against small craft (now x0.35).
- **REQ-CHANGE:** none.

### 9. Siege stall rule vs mothership durability
- **Numbers.** A siege is called off if the enemy mothership loses under 15% hull in 120 s after first contact. In 30-minute matches (2 matches, pass 2): 7 sieges declared, the 4 that ended were all called off after 305-400 s of assault with the enemy hull at 1.00 -> 1.00; the other 3 were still running. The fleet delivers about 115 damage/s while firing, and only about 240 firing seconds in 3 late matches of 300 s; the shield (6,000) soaks first. Damage to a mothership per late match is 22-32k. Pass 2 late game (3 matches, 900 s from 25:00): matches ended 3 of 3 before, 0 of 3 now (the investigator's own copy: 2 of 3); too few seeds to say if that is real, but siege assault time grew 206 -> 648 s while hull lost in assaults fell 0.99 -> 0.37.
- **Options.** Loosen the stall rule or measure it over the whole siege (AI change, no requirement impact); send more ships; or lower mothership hull or shields.
- **REQ-CHANGE (only if durability is lowered): "The mothership should have a lot of health" and "barely win" against several frigates.**

### 10. Treasury pile-up
- **Numbers.** Normal 30 min: average treasury 850-2,650, over 5,000 for up to 396 s (the leading side 270-396 s in 3 of 6 team-games), over 10,000 for 45-133 s in 2; the plan reached 38-44 of 46 steps at 30:00 (research-bound, so money waits for research). Late game: average 3,900-15,800, end 3,500-38,000, because drones, bays, turrets and wards are at their caps. The AI plan never builds Fleet Command.
- **Options.** Add sinks (more wards or turrets, let the AI buy Fleet Command), or accept it as a measurement of "AI admirals float money".
- **REQ-CHANGE:** none, but any fix must not weaken the mothership after big spends (you reversed that).

### 11. The kit fix also changes the game for humans
Repair kits now heal their designed 50 hp at speed (before: 19.8 of 50 at 300 u/s, 0.9 at 450 u/s). It is a bug fix for everyone, so human pilots notice it. **REQ-CHANGE:** none ("weaker at healing" is unchanged).

### 12. Rock-gap sealing slightly changes the map
Fix M grows rocks so 464 gaps of 17.5-34 units close (about 720 rocks, 6.5 units on average, 25 at most). Ore rocks and the 101-wide gate chokes are untouched, and no jungle route closes for a 17-unit ship. The map differs from t=0, so every earlier test baseline was replaced. **REQ-CHANGE:** none.

### Smaller options
- **R** (route cost = flying time): fewer orbits and crashes, 31% shorter long home trips, but pilot deaths +8%. Changes pace.
- **flaksg** (flak frigates shoot defenders in sieges): flak damage to minions +19%, no outcome effect. Skip.

---

## 6. What is left

All known and small. "Size" is the share of pilot time or deaths affected.

| Residual | Size | Why not fixed |
|---|---|---|
| Sieges end with the enemy mothership at full hull in 30-minute matches | 4 of 4 ended sieges | Design: item 9 |
| Treasury pile-up | 2,000-10,000 credits idle | Design: item 10 |
| Bombers deal no damage to a mothership | 0 in 3 late matches | Design: item 8 |
| Trapped bomber in the south-rim pockets | about 0.1% of pilot time, 1 per 1-2 matches | The gaps are just over the 34-unit seal limit; a rim-only seal to about 45 would likely do it, needs a route check |
| One wedged jungler (found in a perf run, seed 101): fighter slot 11 sat at (13672, 8708) from 79 s to the end of 900 s; the escape planner ran 98 times and never freed it | seen in 1 perf run | Found after pass 1 landed; worth a look with the next audit |
| Support corvettes survive 77 s per death in the late game | 16 deaths in 1,228 flying seconds | Balance |
| Pilots rarely kill turrets in 15 minutes | 1 turret kill in 3 matches (damage 16-26k) | Balance |
| Retreating big ships die (81% in the late game) | slow hulls cannot outrun anything | Design: item 6 |
| Commute is 42% of flying time; "no route while far" count 38 -> 157 (counts ships flying an escape route); turret deaths 11 -> 30 (small counts) | commute 10,000 pilot-seconds per match | Not AI faults; watch the turret deaths |

**How to re-measure.** Run a probe headless through the Godot console:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path "<project>" --fixed-fps 60 -- --all-ai --seed=7 --test=pilot_audit --secs=900
```

- Late game: add `--late` and use `--secs=300` (pilots) or `--secs=900` (admiral).
- Admiral: `--test=admiral_audit --secs=1800`. The file `tests/admiral_audit.gd` arrives with pass 2.
- Each probe prints a line every game minute and one `AUDIT_JSON` line at the end; compare the counters old vs new on the same seeds (use 6 seeds; 3 cannot resolve +-10%).
- The comparison scripts (`ab_compare.py`, `int2_summary.py`, `adm2_cmp.py`) are in the session scratchpad `deepdive\`, not yet in the project. Copy them if you want them kept.

**Healthy numbers for 6 matches of 15 min on the game with passes 1 and 2**
(a big drift means something regressed): stuck episodes about 33-37; stuck
seconds 250-360; rock contact about 2,000 ship-seconds; firing at hidden targets
about 100; crash deaths 2-3; pilot deaths about 660 (110 per match); deaths by
minions about 246 (before pass 3's retarget fix).
