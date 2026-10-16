STATUS: 04:50 DONE (stopped: new findings small and rare). KEEP stick+hp2 (T-1, small gain) and bsm (T-3); eff = design call (T-2); pilot audit (2 seeds) shows more rock contact/stuck in every arm, inconclusive (see Audit). Fix code: deepdive\targeting2_fixes_diff.md, copy notate\dd_targeting2.

# Targeting round 2: findings (appended as proven)

Baseline = --ddfix=beam,los,ovl,ion. Probe: tests/dd_target_probe.gd in notate\dd_targeting2 (extra counters: switch classes, flip-flops, idle with enemies in sight, focus pairs, weak pilots ignored, fight distance from goal, eff2 = best eligible target).

## Method (applies to every number below)
Baseline = `--ddfix=beam,los,ovl,ion`, tag tg2_base (normal, seeds 7, 11, 13, 900 s) and tg2_lbase (`--late`, 450 s, same seeds). Each fix arm = the same plus the new switch, same seeds. Probe: tests/dd_target_probe.gd (extended: switch classes, flip-flops, idle, focus, weak/near pilots, eff2, fight distance). Tool: `python -I deepdive\tools_targeting\ana2.py det|cmp ...`. Logs: deepdive\runs\tg2\.

## Baseline facts (3 seeds, 2,700 s, kept set on)
- Fighters switch target 10.4 times per flying minute (6,772 in 3 matches); 52% of the targets are left within 1 s; 24% of switches are A-B-A flip-flops within 4 s; only 51% of switches leave a target that was gone/out of range/hidden/blocked (the rest are "valid": target still fine).
- Fighter engagements with an enemy pilot: 3,184 episodes, mean 2.2 s (lane) / 3.4 s (prey), 87% / 83% end in a switch, kill by us 3.4% / 5.8%. A fighter pilot has 300 hull+shield and fighter cannon hit 38% of the time against pilots, so a duel needs 15+ s of sustained fire; shield regenerates in between. Damage to pilot ships 105,063 for 176 kills = 1.68 kills per 1,000 damage (about 600 damage per kill for 300-health ships).
- 94% of pilot deaths (238 of 254) happen in state "retreat" (see note R at the end).

## Findings

### T-1 (major) Targets are re-picked from scratch every think; no stickiness, and "damaged" ignores shields
Code: pilot_goals.gd:111 `brain.target = brain.targeting.pick_target(ship, PilotTargeting.engage_range(ship))` runs every think (0.22-0.35 s, pilot_ai.gd:305) and pick_target (pilot_targeting.gd:101-105) starts from `var s := d` (distance) with `s += 200.0 - (1.0 - u.hull_frac()) * 600.0`; nothing prefers the pilot we are already shooting, and `hull_frac()` is hull only (unit.gd: `hull / hull_max`), so a pilot whose shield is gone but whose hull is 100% still scores as "undamaged" (a fighter has 100 hull, 200 shield). The header says "weak pilots are juicy"; with hull alone almost none are.
Evidence: see baseline facts. Weak enemy pilots (hull+shield <= 30%) in reach are shot only 89.9% of the time by fighters, 33.7% by bombers, 42.9% by battlecruisers (late), 57% ion, 67% destroyer.
Fix (switches `stick`, `hp2`, in notate\dd_targeting2\scripts\ai\pilot_targeting.gd): (a) `stick`: the enemy PILOT we are shooting now scores 250 better and stays a candidate out to 1.3 x the engage range; (b) `hp2`: "damaged" uses (hull + shield) / (hull_max + shield_max) in pick_target and prey. Minions are not sticky (they die in about 1 s and the last-hit bonus must stay free to switch).
Measured (3 seeds, 900 s, baseline vs +stick,hp2; tag tg2_stickhp2):
 - fighter switches per flying minute 10.4 -> 8.7; all switches 10,083 -> 8,286 (-18%); A-B-A flip-flops 2,396 -> 1,842 (-23%); fighter ship->ship valid switches 759 -> 505 (-33%).
 - fighter engagement with a pilot: mean 2.2 -> 3.4 s (lane), 3.4 -> 4.0 s (prey); kill by us 3.4% -> 5.7% and 5.8% -> 7.2%.
 - damage to pilot ships 105,063 -> 114,113 (+9%); pilot kills 176 -> 208 (+18%); kills per 1,000 damage 1.68 -> 1.82; pilot deaths 254 -> 252; deaths by minions 53 -> 32, by turrets 18 -> 6.
 - minion last hits 872 -> 871 (income unchanged); weak pilots (total health <= 30%) chosen: fighters 89.9% -> 94.1%, bombers 33.7% -> 58.2%.
Risks: pilots commit longer to a duel (kill rate up, so match tempo changes a little); the odds test of prey() is not re-run while the target stays sticky.
### T-2 (design call) Target choice ignores the weapon's damage table; worst for flak frigates, then capitals
Code: pilot_targeting.gd:82 `var heavy_hitter := ship.hull_id in ["bomber", "ion", "destroyer", "battlecruiser", "lance"]` and :105-112 (the "2+ size classes up" rule, the bomber +800 for small pilots) are hand-made stand-ins for the damage table (rules.gd DAMAGE); the flak frigate is in none of them. The comment says "Much bigger hulls ... are a poor match, unless our weapons are made for them".
Evidence (late runs, kept set, 3 seeds x 450 s; probe eff2 = best ELIGIBLE target for the first gun, tanked turrets only, no rock): flak frigate chose a target with less than half the best multiplier in 39.4% of fight samples (chosen 0.60 vs best 0.99): 496 times a pilot ship (x0.25 / x0.20 for flak) over a minion (x1.03), 165 times the mothership (x0.6); its damage to pilot ships has eff 0.25 (final/raw). Battlecruiser 24.3% (mining drones over pilot ships 362x; its first gun is an ion turret), ion 19.1%, bomber 18.5% (late), destroyer 16.2%.
Fix tried (switch `eff`): `s += (1 - Rules.damage_mult(first gun kind, target size) * small_bonus) * 400` for every candidate. Result (late, 3 seeds): poor choices flak 39.4% -> 25.5%, BC 24.3 -> 16.3, ion 19.1 -> 9.3, destroyer 16.2 -> 7.8, bomber 18.5 -> 13.2; damage per fight second: BC 170 -> 206, ion 55 -> 70, destroyer 110 -> 182, flak 36 -> 33 (no gain, flak still goes for ships and the mothership); BUT all three late matches ended 30-170 s earlier than the baseline ones (baseline 3/3 ran the full 450 s; eff ended at 1778, 1801, 1921 s), pilot kills per 100 game s 7.8 -> 6.1.
Verdict: DESIGN CALL / do not bundle. It works as a preference, but it changes how sieges end (the mothership dies sooner) and the flak frigate, the clearest case, is not fixed by it (its job is assigned by the admiral's siege and push, see goals). A flak-only rule (flak frigate: pilot ships of size large/capital +500, as for strike craft vs frigates) is cheap if the user wants it; not measured.

### Suspects refuted by numbers (baseline, 3 seeds): do not fix
- Not focusing: nearby allied pilots that both target a pilot share the target in 82% of 19,503 pairs (late 74.5%); fighters: 63% of pilot-target samples have 1+ ally on the same target. A `focus` bonus (-150 for a pilot an ally targets) was written (switch `focus`) but not worth runs.
- Ignoring weak pilots: fighters shoot an enemy pilot with hull <= 35% in reach 93.8% of the time (lance 95.6%); bombers 23% (they avoid small pilots by design, see T-3).
- Pilot next to us ignored because of the turret-cover rule (pilot_targeting.gd:114-118): 322 of 6,044 near-pilot samples (5.3%) for fighters.
- Idle with enemies in sight: fighters have no target in 37% of lane samples, but an enemy minion is within 3 engage ranges in only 21% of those (pilot: 11%); no case for a longer engage range.
- Chasing too far / into turrets: fighters fight under an enemy turret 2.2% (prey 1.0%) of the time; prey fights are 96.6% within 3,500 of the goal; deaths by turret 18 in 3 matches.
- Fighter pilots on tanked turrets (push): 1,476 samples (8.5% of fight time), episodes of 4.8 s, 0.6% kills: low volume, not harmful.
- Low-health enemy pilot ignored for a minion: fighters ignore it 6% (22 of 1,157 samples) in favour of a minion.
### T-3 (major for the bot lane) Bombers shoot small minions and drones with torpedoes (x0.35, 15% hit rate); only small PILOTS are penalised
Code: pilot_targeting.gd:110-112 `# Torpedoes are wasted on strike craft (x0.35 damage, easy to dodge). if ship.hull_id == "bomber" and u.size_class == Rules.SIZE_SMALL: s += 800.0` applies to K_SHIP only; the K_MINION case (:113-123) gives a small minion `s += 250.0` (and a -700 "last hit" bonus under 60 health) with no penalty, and mining drones even get `s -= 200.0`. Strike-craft minions are as small and as easy to dodge as pilots. The hull's own blurb (ships.gd) says: "Plan attack runs on big ships, turrets and motherships."
Evidence (baseline, 3 seeds, 900 s): bombers spend 80.7% of their fight time on minions (+4.9% mining drones, 1.6% repair drones); 76% of the 2,167 torpedoes (1,652) are aimed at minions; torpedo hit rate 17.9% (15.1% at minions, 19.1% at pilots; 63.9% simply expire); last-hit attempts 868, success 5.4% (fighters 34.5%); the probe's eff2 shows 30.0% of bomber fight samples with a target that had at least 2x the multiplier available (2,267 of the 2,478 poor ones are small minions chosen over a medium minion, x1.0 against x0.35). Bomber damage 48,610 (eff 0.87), of which turrets 13,926 and pilot ships 5,689.
Fix (switch `bsm`): a bomber in the lane state skips every SIZE_SMALL candidate that is not a structure (small pilots, minions, drones, wards). It keeps medium minions (escort corvettes), large and capital pilots, tanked turrets, bays and the mothership; push and siege targets are unchanged.
Measured (3 seeds, 900 s, baseline vs +bsm, tag tg2_bsm):
 - torpedoes fired 2,167 -> 1,691 (-22%); torpedo hit rate 17.9% -> 39.2%; bomber total damage 48,610 -> 82,959 (+71%; minion damage 26,843 -> 61,451 because the medium minions it now picks are hit at x1.0 and take real damage); bomber eff 0.87 -> 0.97; bomber last-hit success 5.4% -> 19.3%; bomber time with a target 43.6% -> 23.0% (no target in lane 47.8% -> 70.1%).
 - no cost elsewhere: bomber deaths 42 -> 37; all pilot deaths 254 -> 235; pilot kills 176 -> 166 (noise, fighters 150 -> 145); minion last hits 872 -> 864 (income unchanged); deaths by turret 18 -> 6.
Risks: bombers sit idle in the lane 70% of the time (they did 48% before) and are a weaker anti-minion presence; they never kill small pilots either way (kills of pilots 3 -> 1 in 3 matches), so the "bot lane is bombers" imbalance (behavior note N-3) is not fixed by this, only their torpedoes are no longer wasted. Late game not run (late bombers mostly shoot ships and the mothership already).
### Update, 6 seeds (7, 11, 13, 17, 19, 23; 900 s each) and the recommended bundle
T-1 `stick`+`hp2`, baseline vs fix, summed over the 6 seeds (tags tg2_base, tg2_stickhp2):
 - target switches 20,198 -> 16,515 (-18%; lower in 6 of 6 seeds, -12% to -28%); A-B-A flip-flops 4,575 -> 3,595 (-21%); fighter switches per flying minute 10.4 -> 8.6.
 - damage to pilot ships 212,038 -> 221,393 (+4%); pilot kills 348 -> 382 (+10%; per seed 54/57/65/70/52/50 -> 70/57/81/43/65/66, so 5 of 6 up, seed 17 down with fewer deaths too); pilot deaths 494 -> 486; kills per 1,000 damage 1.64 -> 1.73; deaths by minions 102 -> 61, by turrets 28 -> 16; minion last hits 1,714 -> 1,735 (income unchanged); allied pairs on the same pilot target 84.2% -> 86.3%.
 - Honest size of it: the mechanism (fewer, longer engagements) is robust; the kill gain is within seed noise (+18% on the first three seeds, +1% on 17/19/23). It is a small correctness gain, not a big balance change.
Bundle `stick,hp2,bsm` (tag tg2_set, seeds 7, 11, 13) vs baseline on the same seeds: switches per fighter minute 10.4 -> 8.4; bomber torpedo hit rate 17.9% -> 34.9%, bomber damage 48,610 -> 83,746 (+72%); pilot kills 176 -> 185, pilot deaths 254 -> 262; minion last hits 872 -> 849 (-3%); deaths by minions 53 -> 54. The two fixes add up without interfering.
## Audit (ab_audit, seeds 7 and 11, 900 s, summed; tag dirs deepdive\runs\tg2a; base has only the round-1 targeting set, NOT main's flight fixes)
| | base | stick+hp2 | bsm | stick+hp2+bsm |
|---|---|---|---|---|
| target switches | 6,058 | 5,031 | 4,468 | 4,325 |
| pilot deaths | 165 | 156 | 143 | 162 |
| crash deaths | 3 | 2 | 1 | 5 |
| stuck episodes | 31 | 57 | 42 | 84 (31 of them one repeating stuck_home burst on seed 7) |
| rock contact while fighting, s | 684 | 948 | 1,076 | 1,223 |
| occluded while firing | 176 | n/a | n/a | 126 |
Reading: switches and deaths behave as in the probe. The flight numbers (stuck, rock contact) are higher in every arm, including bsm that only stops bombers shooting; with two seeds and a chaotic simulation (a different target choice changes every later trajectory) this is NOT proven to be caused by the fixes, but it is not proven harmless either. The base run here also has unusually low stuck counts (14 and 17; the lead's earlier seed-7 audit had 37). To settle it: run ab_audit for 4+ more seeds of base vs set ON TOP OF main's flight fixes (ABDEIUMOX cut rock contact by 61% and stuck by 69%); pursuing a target around rocks is exactly what the flight fixes handle. Until then T-1 and T-3 are "keep, with this caveat".

## Notes for other domains (not fixed here)
- R (behavior): pilot_ai.gd:316-323 `var hp := ship.hull_frac() ... if hp < 0.35 or (state == "retreat" and hp < 0.85)` retreats on hull alone, so a fighter (100 hull + 200 shield) flees only when about 88% of its total health is gone; 238 of 254 pilot deaths (94%) happen in state "retreat". A retreat trigger that also counts shields (for example hull < 0.35 OR hull+shield < 0.2) is the obvious thing to test in the behavior copy.
- Flak frigates join sieges and pushes on the mothership at x0.6 (flak vs mothership 0.3 x attacker 2.0) while ion and shell ships do x3.0 (x1.5 table times x2.0 attacker): late seed 7 (450 s) flak spent 26.5% of its fight time on the mothership and did 613 damage there against 8,001 on minions. Admiral/goals domain (siege membership), not a targeting bug.

## Recommended set and verdicts
KEEP --ddfix=beam,los,ovl,ion (round 1) + stick,hp2,bsm (round 2), with the audit caveat above. DROP focus (already 82% shared), eff (design call, changes siege length), stick500 (written, not run), idle/chase/weak-pilot ideas (refuted).