STATUS: 06:59 DONE. Keep rfix=ret25,retsmall,msa (flaksg optional). Verdict: further AI digging not worth it. Code diff: deepdive\residuals_fixes_diff.md

# Residuals round (investigator "resid"): findings

Copy: notate\dd_resid (current game with all fixes so far as permanent code; new switches read from Game.opt("rfix",""),
default OFF). Snapshots notate\dd_resid_s1..s5. Probe: tests\pilot_audit.gd extended (damage dealt/taken by AI pilots by target
kind and by hull via Events.damage_applied, retreat episodes, every death and every stuck episode listed, siege target/fire
counts per hull, siege distance buckets). Tool: deepdive\resid_compare.py <dir> <base tag> <tags...> (paired seeds), resid_deaths.py,
resid_stucks2.py. Runs: deepdive\runs\resid (ab_base/late_base = this game, seeds 7, 11, 13, 900 s / late 300 s).

## R-1 (lead 1): retreat trigger on hull only  [05:40]
Base (3 seeds x 900 s, this game): 340 pilot deaths, 334 of them (98%) in state "retreat". 457 retreat episodes, 287 end in death (63%),
252 of those within 4 s of the retreat starting (median ~1.5 s). Average health when the retreat starts: hull 22%, hull+shields 16.7%
(a fighter is 100 hull + 200 shield, so 35% hull is ~12% of its total health: ~0.25 s of fire from two fighters). The retreat is a
last-second reaction. Late game (3 seeds x 300 s): 96 deaths, 93 in retreat, 90 episodes -> 83 deaths (92%), most of them frigates and
capitals (large 29, capital 14, medium 16, small 31 episodes): slow hulls cannot outrun anything.
Switch rfix=ret<NN> (pilot_ai.gd _think step 1): ALSO retreat when hull + shields fall below NN% of the pool ("soft" retreat, the hull is
still over 35%); a soft retreat ends when hull+shields are back over 70% (shields regenerate in flight), a hull retreat as before (85% hull).
ret25, 3 seeds x 900 s (paired): pilot deaths 340 > 264 (-22%, lower in 3/3 seeds: 105>86, 118>89, 117>89); deaths in retreat 334 > 262;
retreat episodes 457 > 508 (275 of them soft), episodes ending in death 63% > 48%; deaths within 60 s of launch 138 > 97;
dead time (respawn) -24%; share of flying time in state retreat 7.8% > 10.6% (the price); fight samples -1%; damage dealt to enemy
ships -3% (+4.5%, -16%, +2.6% per seed: noise), to minions +2%, to monsters +1%, damage taken -3%; stuck episodes 19 > 5 (noise-level).
So: the same fighting output with a fifth fewer deaths. Higher thresholds: see below (ret35, ret45).

## R-4 (lead 4): do the integrated game's extra pilot deaths have one dominant cause?  [05:50]  VERDICT: no, drop
Base, 3 seeds x 900 s, 340 deaths (113 per match, one every ~8 s over 22-24 pilots, mean life 95 s, 7% of pilot time spent dead).
By killer: pilot 193 (57%: fighter 161, lance 22, flak 6, bomber 3, logistics 1), minion 129 (38%: minion fighter 99, corvette 27,
bomber 3), PD turret 13 (+1 torpedo turret), crash 2, mothership 1. By victim hull: fighter 230 (68%), bomber 63, lance 28, support 9,
scout 5, logistics 4, flak 1 (small ships 326 of 340). By place: no hot spot (largest 2,500-unit cell has 26 of 340 deaths, the
centre of the map; the 14 turret kills are spread over 7 spots, max 4 at one turret (11,000, 13,500)). By time: 21-32 per minute
from minute 2 on, flat. 98% die in state retreat (334), 6 in lane; before death only 23 had more than 30% of their health. 41% of the
deaths (138) come within 60 s of a launch (the ship has just arrived at the front). Minion share: 129 here vs 95/6 seeds = 16 per
seed in the old int1 audit: it is 43 per seed now (minions hit; the coming retarget fix takes ~40% of it back, see minions2_findings).
=> nothing new and concentrated; the deaths are ordinary fighter-vs-fighter and fighter-vs-minion deaths plus a last-second retreat (R-1).

## R-2 (lead 2): flak frigates in sieges  [05:55]  VERDICT: small; keep rfix=flaksg as a cheap correctness tweak (optional)
Late base, 3 seeds x 300 s: during the assault phase the flak frigate has the mothership as its target in 76% of its samples (1,101
of 1,450) but fires at it in 7% of those (74): it is out of reach (84% of its assault time is farther than 3 reach lengths from the hull;
BC 39%, bomber 71%, support 63%), and when in reach the flak does x0.3 to a mothership: total flak damage to the mothership = 16 points
in 3 matches (BC 25,224, destroyer 1,827, ion 536, support 58, lance 7, bomber 0). It fires at minions/ships in 93-99% of the samples
where those are its target. So the x0.6 matters little; the real loss is that the mothership target blocks pick_target() for every
target (the Mothership wins the `target` slot as soon as it is within reach 0.8 x engage range, +100 for big ships).
Switch rfix=flaksg (pilot_ai.skips_ms; pilot_targeting.pick_target step 4 and push_target step 2, pilot_goals.think_lane step 4): a flak
frigate never takes the mothership as target, it keeps the siege goal and shoots defenders. 3 seeds late (paired): flak fire samples at
minions during the assault 67 > 250 (+273%), at ships 144 > 172, damage by flak to minions 28.4k > 33.7k (+19%), to ships 6.5k > 5.4k;
flak deaths 15 > 13, pilot deaths 96 > 93; damage to the mothership 27.7k > 24.6k (-11%: 25.2k > 24.6k of it is the battlecruisers,
i.e. run-to-run noise), enemy mothership hull at the end 87/100/100% > 86/100/100%. No measurable effect on the siege outcome.
Other finding from the same counters (siege geometry, 2 seeds, 400 s late, dg_late): in the assault phase the big ships spend most of
the time FAR from the mothership: battlecruiser 18% inside 0.8 reach, 39% beyond 3 reach; bomber 2% inside reach and 71% beyond 3 reach
(bombers target the mothership 58% of the assault but fire at it in 5 samples of 1,059; torpedo damage to the mothership = 0 in 3 late
matches). All fire at the mothership only inside 1.05 reach (100% of the in-reach samples). So sieges are decided by travel time
and survival on the way (BC speed 150, bomber retreats to the mothership 20,000+ away after each death), not by aim or target choice.

## R-3 (lead 3): big ships "trapped beside their own mothership" = ships pinned against a MOTHERSHIP HULL  [06:03]  VERDICT: keep rfix=msa (late game; cheap)
What the remaining stuck episodes are. Normal game (3 seeds x 900 s): only 19 stuck episodes / 100 stuck seconds in 58,000 ship-seconds
(0.17%): fighters/bombers in the lanes and bombers retreating through the south part of the jungle (y 22,000-24,500; rocks near), spread
over 15 cells, nothing repeats: below the noise floor now, nothing worth fixing (concave notches included). Late game (3 seeds x 300 s):
35 episodes / 238 stuck seconds, 178 s of them battlecruisers; the probe now records what the ship's last move slid along: 12 of the
records (BC, flak, bomber, lance) are PINNED AGAINST A MOTHERSHIP (collider kind mothership, own team, 13-160 units from the hull,
speed 2-45 at full forward thrust, 3-20 s in a row).
Why: from 20:00 the mothership drives up the lane at 80 units/s and parks in the lane centre (mid: team 0 at x~15,300, team 1 at x~24,700,
both on y=13,000), so it lies across the straight line (and the route, which knows only rocks) of every ship that flies along the lane
past it, and it also rolls over the launch point. A ship's physics mask includes layer 4 (mothership, turrets), PilotFlight.avoid_rocks()
knows only rocks and returns under 60 units/s, so a BC (turn 0.32 rad/s, accel 55) that meets the hull stays against it; the stuck timer's
1 s reverse does not help. Measured with the new counters (msl_base, late, 3 seeds x 300 s, 35,861 pilot-samples = 17,900 ship-s):
ticks touching a mothership hull 49,985 = 833 ship-seconds (4.6% of all late pilot time); pinned (speed < 40) 22,845 = 381 s (2.1%);
by hull: battlecruiser 332 s touching / 157 s pinned (of ~4,300 BC-seconds), bomber 204 / 78, lance 216 / 110, flak 58 / 35.
Switch rfix=msa (pilot_flight.gd avoid_hulls(), called first in avoid_rocks()): a ship whose look-ahead (radius + 140 + speed x
1.2/turn rate, so slow turners start early) is within reach of a mothership hull (either team's) and whose heading points into it
(heading . outward normal < 0.25) turns along the hull toward the side it wants to go and thrusts; not when the goal itself is within
600 of the hull (docking, defending). msl_msa vs msl_base, 3 seeds x 300 s late: ticks touching a hull 49,985 > 6,897 (-86%), pinned
22,845 > 1,211 (-95%; BC 9,394 > 10), stuck episodes 35 > 14, stuck seconds 238 > 40 (-83%), rock contact -30%, pilot deaths 96 > 79
(-18%, 22 vs 37 on one seed: probably partly chance), no_route_far 23 > 16. Not changed (within the +-20% run-to-run noise of 300 s
late matches): damage to the mothership 27.7k > 28.3k, to ships 161k > 136k (70>50, 47>48, 44>39k per seed), to minions 142k > 179k.
Risk: the rule can swerve a ship that wants to pass close to a hull; docking and defending are exempt through the goal test.
Normal (pre-20:00) matches are not affected in practice (mothership at home, ships launch away from it); to be confirmed in the
combined run (ab_combo).

### R-1 update: the threshold curve and the late game  [06:10]
Normal, 3 seeds x 900 s, paired, base > ret25 > ret35 (seed 7 only for ret45):
  pilot deaths               340 > 264 (-22%) > 218 (-36%)    (ret45, seed 7: 105 > 62, -41%)
  deaths by pilots / minions 193/129 > 156/95 > 125/79
  episodes ending in death   63% > 48% > 40%
  time in state retreat      7.8% > 10.6% > 11.1% of flying time; dead (respawn) time -24% / -35%
  damage to enemy ships      122k > 119k (-3%) > 108k (-12%, lower on 3/3 seeds)  (ret45 seed 7: -22%)
  damage to minions          112k > 114k > 119k; damage taken 232k > 226k > 217k; fight samples -1% / 0%
  kills of pilot ships       193 > 156 > 125 (that is the deaths: every pilot death by a pilot is a pilot kill)
So each 10 points of threshold removes ~14 points of deaths and costs ~4-5% of the damage to enemy pilots from ret25 on; ret25 is where
the damage output is still unchanged. Recommended NN = 25 (design call between 25 and 35: how careful the AI pilots should be).
Late game, ret25 on all hulls (3 seeds x 300 s): pilot deaths 96 > 77 (-20%), episodes ending in death 92% > 82%, but damage to
enemy ships -15% (3/3 seeds lower), to the mothership -21%, battlecruiser assault samples -54%: the big ships leave the siege to retreat
and are slow, so a soft retreat does them little good. Hence the switch rfix=retsmall: the soft rule only for ships smaller than a
frigate (big ships keep the old hull-only trigger). Combined run in the queue (late_combo, ab_combo).

## R-5 (side effect to know about): with ships no longer pinned, sieges are called off sooner  [06:30]
Late runs, siege samples summed over all big ships and bombers (gather + assault, 3 seeds x 300 s, 0.5 s samples):
  base 2829 / 2872 / 2643 per seed;  msa 865 / 1376 / 1054;  combo (ret25,retsmall,flaksg,msa) 764 / 1410 / 1276;  flaksg alone
  2639 / 2985 / 2661 (no change);  ret25 alone 1165 / 602 / 2632.
Reason (admiral_siege.gd _run_siege step 1-2): a siege is called off when the enemy mothership lost less than 15% HULL in the 120 s after
our first big ship got within 3,000 of it (the shield, 6,000, soaks first), or when nobody got there in 300 s. In the base late runs the
pinned/late ships rarely made "contact" inside 300 s, so the siege simply stayed on; with msa they arrive, the force (about 115
damage/s to the mothership while it fires, only ~240 firing seconds in 3 x 300 s) cannot remove 15% hull in 120 s, and the siege ends
and is re-declared after the 60 s cooldown. Damage to the mothership is unchanged (27.7k base, 28.3k msa, 31.9k combo; run-to-run
spread 22-32k), final mothership hulls 100% in all (shield 20-100%). So the flight fixes do not make sieges worse; the stall rule +
piecemeal arrival is the limit on mothership damage (admiral/balance domain, already known as AD-13: "enemy mothership hull lost in
assaults ~0"; confirmed again in the new admiral audit below).

## Admiral audit, this game, 2 seeds x 30 min (adm_r, notate\dd_resid_s1; seeds 7, 11)  [06:12]
Admiral keep set behaves as designed: push by lane fraction (mid 20-47%), failed orders 0, treasury average 1.9-2.6k (max 8-11k, over
5,000 for 287-410 s per team: AD-6 pile-up still there), bays made 5-15 per team, defending 0-36 s. Sieges: 7 declared in 4 team-games
(2 per team, 1 for one team); the 4 that ended inside the 30 minutes were all called off by the stall rule after 305-400 s of assault with the enemy
mothership hull 1.00 > 1.00 (no damage at all), the other 3 were still running at 30:00; the ms_move of the siege-declaring team went to the wrong lane twice in the first minute after 20:00 (seed 7 team 0:
"ms_move lane bot, enemy_ms_lane top" at 1239 s, corrected at 1458 s; seed 11 team 0 similar at 1286 > 1420 s), because the enemy
mothership has only just left home when the siege is declared (the `sl` rule needs it parked > PARKED_DIST). Cost: the mothership is on the
wrong lane for ~3 minutes. No new problem beyond AD-10/AD-13; mmid2 (design call) remains the only thing that makes normal matches end.


## R-6 (lead 3, rest): bombers in the south-rim pockets  [06:50]  VERDICT: known, rare, not fixed (design of the fix is the flight domain's M2 seal)
The "stuck" episodes of the normal game (19 in the base, 29 in ab_combo, 3 seeds x 900 s) are 0.2-0.6% of ship time; what is left are
bombers (and a few fighters) in pockets of the south rim wall: a row of rocks at y ~ 24,180-24,270 whose 30-40 unit gaps a bomber
flies through into the pocket behind them (map renders deepdive\runs\resid_img\rim1.png, rim2.png). Sites seen: (14,723; 24,274) base
seed 11 (3 episodes in a row), (20,979; 24,558), (24,322; 24,180), (21,495; 24,184) twice in a row (same bomber, 100 s apart), (29,429;
24,180) 5 episodes in a row = ~250 s of ONE bomber in ab_combo seed 7. That single bomber is why "stuck seconds" read 100 > 356 in
ab_combo: it is not caused by the switches (the mothership is 27,000 away; ms_contact_ticks in normal matches = 5). A trapped bomber
is lost until it dies, about 100-250 s once in 1-2 matches: ~0.1% of pilot time. No fix tried (the gaps are just over the 34-unit
limit of fix M2: a rim-only extension of M2 to ~45 would likely do it; risk: jungle routes through the rim, needs the static route check).

## Combined run (rfix = ret25,retsmall,flaksg,msa), paired with the base  [06:45]
Normal, 3 seeds x 900 s (ab_combo vs ab_base): pilot deaths 340 > 255 (-25%, 3/3 seeds: 105>82, 118>93, 117>80); deaths by pilots
193 > 159, by minions 129 > 78; episodes ending in death 63% > 48%; deaths within 60 s of launch 138 > 92; dead time -25%; time in
state retreat 7.8% > 9.5%, home 1.8% > 2.0%; damage to enemy ships 122k > 112k (-8%, lower on 3/3 seeds: -18%, -2.5%, -4.4%), to minions
+1%, to turrets 16.6k > 26.1k (+58%), to monsters 0%; damage taken -6%; fight samples +2%. The mothership switches (msa, flaksg) are
inactive here (ms contact 5 ticks, no big ships), so this is ret25's effect: a fifth to a quarter fewer deaths for ~5-8% less damage to
pilots.
Late, 3 seeds x 300 s (late_combo vs late_base): pilot deaths 96 > 82 (-15%), stuck seconds 238 > 74 (-69%), ticks touching a
mothership 49,985 > 7,249, damage to ships 161k > 174k, to the mothership 27.7k > 31.9k, to minions 142k > 200k (+41%), flak damage to
minions +36%; ship-versus-ship numbers move +-20% with the match (see R-5).

## Robustness: skill-jitter (the fun probes use it), 3 seeds x 900 s, sj_combo vs sj_base  [06:59]
Same direction as without jitter: pilot deaths 309 > 247 (-20%, 3/3 seeds: 115>84, 91>84, 103>79), by pilots 199 > 158, by minions
99 > 74, episodes ending in death 62% > 48%, damage to enemy ships 116k > 104k (-10%, 3/3 lower), damage taken -6%, time in retreat
7.0% > 9.5%, stuck seconds 452 > 78 (the base had a trapped bomber).

# VERDICT ON FURTHER DIGGING  [07:00]

What this round found (all behind --rfix, default OFF):
  ret25 + retsmall  KEEP (design knob: how careful pilots are). Pilot deaths -20..-25% (3/3 seeds, normal, late and with jitter), 98% of
                    deaths were last-second retreats (a fighter fled with 17% of its total health left; 63% of retreats ended in
                    death, now 48%). Price: 5-8% less damage to enemy pilots, +2 points of flying time in retreat. ret35 = -36% deaths
                    and -12% damage; ret45 -41% / -22% (seed 7). Not for frigates and capitals (they cannot outrun anyone; ret25 on
                    them cut siege participation).
  msa               KEEP (late game). Ships pinned against a mothership hull: 4.6% of late pilot time (battlecruisers 7%) -> 0.6%
                    (-86%); stuck seconds -83%. Side effect to know: ships arriving at the siege earlier makes the admiral's stall rule
                    end sieges sooner (siege time -55%); damage to the mothership is unchanged (it is the limit, see R-5).
  flaksg            OPTIONAL, small. Flak did 16 points of damage to motherships in 3 matches; it now shoots defenders during
                    sieges (fire time at minions +273%, damage to minions +19%), flak deaths -13%; no measurable effect on outcomes.
  retbig/home etc.  not re-opened.
Leads closed without a fix: lead 4 (deaths by cause: no hot spot, no new dominant cause; minions 38% will drop with retarget),
rim notches (R-6: rare, ~0.1% of pilot time), concave notches elsewhere (below noise: 19 stuck episodes in 58,000 ship-seconds).
Fresh sweep (pilot_audit 3 seeds normal + 3 late, admiral_audit 2 seeds, damage per flying second by hull): nothing big and new.
Remaining items, all known and all design/balance rather than AI bugs: (1) sieges end by the stall rule with 0 hull damage in every
30-minute match (7 declared, 4 ended, 4/4 hull 1.00 > 1.00), motherships ~30,000 apart, mmid2 is the only thing that makes
normal matches end; (2) treasury pile-up 2-10k (AD-6); (3) bombers deal 0 damage to the mothership (torpedoes need to be
within 1.05 reach and the bombers spend 71% of the assault beyond 3 reach; bsm will help vs minions only); (4) support corvettes
survive 77 s per death in the late game (16 deaths in 1,228 flying seconds); (5) pilots never kill turrets in 15 minutes
(1 turret kill in 3 matches; damage to turrets 16-26k).
Size of what is left: all AI-level residuals together are below 1-2% of pilot time or 5% of deaths, i.e. below what 3 seeds of
900 s can resolve (run-to-run spread: deaths +-5%, damage to pilots +-5-10%, late 300 s damage numbers +-20%).
Is another round worth it? No. The returns have fallen off a cliff: round after round the findings went from "35% of the pilots
stuck" to "one trapped bomber per two matches", and the only sizeable AI item left this round (the retreat) is a taste/design choice,
not a defect. Further AI hunting costs more in tokens than its effect on a fun measurement could show; spend the next effort on
the design calls above (mmid2 / siege stall rule / mothership durability vs siege damage) and on the measurement itself.
Caveat on my evidence: 3 seeds per arm, 300 s late runs; the retreat result is robust (deaths lower in 12/12 paired seeds across
ret25, ret35, combo, jitter), the msa contact numbers are mechanism-level (counted ticks), the flaksg and the siege-length numbers
are not statistically solid.
