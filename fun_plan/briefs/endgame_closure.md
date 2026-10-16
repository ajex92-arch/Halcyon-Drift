# Fork brief: endgame_closure (fork B)

Game: Halcyon Drift, a Godot 4.7 space MOBA (13 v 13: 12 pilots + 1 admiral per team, 3 lanes joined by a middle connector, a
small-ship jungle, a movable mothership; ONLY a mothership kill ends a match). You work ONLY in `forks/endgame_closure/` (a copy
of `remake/`). Read first: `scripts/features/feature_registry.gd`, `escort_wing.gd`, `scripts/ai/admiral_siege.gd`,
`scripts/team/team_siege.gd`, `scripts/entities/mothership.gd`. Docs style: docs/CODE_STYLE.md. Shared rules: section 4 and
README.md.

## 1. Goal and ingredients
Turn a won game into a readable, defendable close of 3-7 minutes: earlier visible pressure on the mothership, sieges that land, no
limbo, no 60-minute timeouts, closed by big ships.
- **S1 Decisive match arc (weight 12):** per seed T(minutes; 18, 28, 42, 58), unended = 0 (target median 30-40 min, ended_rate >=
  95%, <= 5% under 20 min). Baseline about 56 (3 of 6 seeds hit the cap).
- **S2 Endgame arc (weight 10), the main target:** ms_pressure_onset_min (first time a mothership hull < 0.95; T 15/22/34/46),
  final_push_secs (end minus last time the loser was >= 0.75 hull; T 45/120/420/900), ms_limbo_secs (longest stretch at <= 0.70
  hull with < 0.02 lost in 120 s; 100 at <= 180 s, 0 at >= 900), siege_bite_rate (share of assault phases >= 20 s whose target
  lost >= 0.10 hull; T 0.10/0.35/0.70/0.95), ms_big_damage_share (share of the losing mothership's hull damage dealt by
  LARGE/CAPITAL pilot ships; 0 at <= 0.30, 100 at >= 0.60). Baseline about 45 (onset median ~41 min, push ~65 s).
- Secondary: S3 (decided_to_end <= 8 min, lead changes, comeback15 >= 15%), S5 fight_p90_late, S6 pilot_kill_share_late.
- Context: "always park on mid" is going into main (the mothership advances only up the mid lane from 20:00), so the siege lane is
  mid after 20:00 and baseline v2 includes it. The accidental-assault waypoint bug is already fixed in main.

## 2. Ideas to build (all keys default `off` in Rules.VARIANT_DEFAULTS except `retreat`; use `--variant=<key>:<value>`)
### B1 Sieges that land | `siege_fix:gather3` / `siege_fix:full` / `siege_fix:stall` | OWNS siege AI | REQ-CHANGE: none
gather3: AdmiralSiege launches the assault when min(3, big ships alive) are within 3,000 of the staging point, or after 90 s with
2+ there (today 2 ships / 45 s; tunables siege_gather_count/time exist); bombers count as half a ship. PROGRESS records 3/90 s as
an earlier setting replaced in round 3, so measure against current. full = gather3 + formation (during the approach
`TeamState.siege_speed_cap` = 1.1 x top speed of the slowest participant within 6,000 of the lead ship; `PilotFlight` throttles
participants more than 2,500 ahead of the group centroid) + base race (`TeamState._update_defense` also fires when 2+ seen enemy
big ships within 12,000 of our hull close in at > 40 u/s; it NEVER cancels our own siege once in assault: a static 14,000 radius
once kept both teams defending all match). stall (deep dive #9): the stall check (siege_stall_time 120 s, siege_stall_frac 0.15)
is judged over the whole siege (240 s, 0.10), since 4 of 4 ended sieges were called off at 1.00 hull. A human admiral still
declares a siege with the waypoint. Usage: `assaults_launched`, `assault_gather_ships`. Pass: S2 +8 (siege_bite_rate up) with
final_push not under 120 s.
### B2 Lane breach corvette | `breach:on` and `breach:fulldmg` | REQ-CHANGE: on = none; fulldmg = "weak to attacks by large ships" (minions would close games)
When the last turret at an enemy INNER node dies (`Events.turret_destroyed` with `node.turret_count(victim) == 0`) that lane is
breached for the attacker for 8 waves (about 280 s). Then that lane's single escort corvette spawns as `breach_corvette`: a
`Minions.TYPES` copy with hull 960, shield 320, cannon range +20%, no new mount; damage multipliers unchanged
(MOTHERSHIP_MINION_MULT 0.5, TURRET_MINION_MULT 0.35, MINION_VS_SHIP_MULT 0.6). Its job is to soak mothership and inner-turret
fire so big-ship sieges land. Stacks with main's `escort_wing:upgrade`. Do NOT touch the rebuild lock (teamfights fork owns it).
Feed line, HUD banner and minimap chevron for both teams. `fulldmg` (restored original): additionally MOTHERSHIP_MINION_MULT 1.0
for that corvette and a 1,700-range siege shell (0.5 shots/s x 70 damage, x1.5 vs mothership). Build the breach tracking as a
small helper shared with B7. Usage: `breach_waves`. Pass: S2 +8 (onset, bite) with ms_big_damage_share >= 0.60 (report only for
fulldmg), unattended_turret_loss_share not up.
### B3 Mothership damage-rate cap | `ms_cap:on` and `ms_cap:full` | alternative to B5 and F3 | REQ-CHANGE: none (gated by ms_duel); full = "a lot of health"/"barely" tuning at risk
Using the incoming-multiplier hook: the mothership keeps a 60-s ring buffer of hull damage; hull damage beyond 12% of hull_max in
the rolling 60 s is x0.5 (`on`) or x0.1 (`full`, the unsoftened hard-ish cap). Shields, the x2.0 large/capital multiplier and
point-defence weakness unchanged. AdmiralSiege's stall rule scales with it (15% -> 10% in the 120 s after contact). HUD hull bar
shows a "plating holding" tick. Must pass the ms_duel gate (same winners; upgraded wins end with <= 40% HP) for `on`; for `full`
report ms_duel, do not block. Usage: `ms_cap_seconds`. Pass: S2 final_push into 120-420 s (+8), minutes up at most 3.
### B4 Fleet attrition (last resort) | `attrition:on` | REQ-CHANGE: none (equal for both sides; touches "a lot of health" only after 40:00)
Screen it only if B1-B3 leave ended_rate < 90%. Feed banner at 38:00; from 40:00 damage taken by BOTH motherships and all turrets
x(1 + 0.04 per full minute past 40:00, cap 1.8) via the hook; mothership shield regen x max(0, 1 - 0.1/min past 40:00); pilots and
minions unaffected. Usage: `attrition_seconds`. Pass: S1 +8 (ended_rate >= 95%, p90 minutes <= 55) with ms_big_damage_share held.
### B5 Last Stand | `retreat:last_stand` (existing key; default `systems_failure`; the module must do nothing for `none`/`systems_failure`) | alternative to B3 and F3 | REQ-CHANGE: none
Once, at 35% hull: shields refill to max and guns fire x1.5 for 45 s; launching and respawning stay available with normal timers
and strain. After 45 s the mothership is "breached": incoming x1.25 for the rest of the match. Feed line and banner. Retune the
x1.5 against ms_duel (tuned with systems_failure). Compare with systems_failure on the same seeds. Usage: `last_stands`. Pass: S2
limbo and final_push +8.
### B6 Surrender vote | `surrender:vote` | REQ-CHANGE: "only destroying the mothership should end the match"
From 20:00, one vote per 5 min, 30 s long, passes at 80% of the team's 13 seats; a human gets a prompt. Every AI seat votes by the
SAME rule (never keyed to skill): yes when its team has 6+ fewer turrets alive AND 15+ fewer pilot kills over the last 600 s
(scoreboard numbers only; never the probe's adv_index). A pass ends the match as a loss for that team through the end path a
mothership kill uses, and FUN_JSON gets `ended_by` ("mothership" or "surrender"). Report S1 both ways (surrender counted as ended,
and as not ended); S2's mothership pieces are null for surrendered seeds (flag it). Usage: `surrender_votes`, `surrenders`. Pass:
S1 +8 with comeback15 not worse (report who led at the vote).
### B7 Extra siege minion after a breach | `breach_extra:on` | REQ-CHANGE: "wave of 10, with 5 fighters, 4 bombers, and 1 escort corvette" (gate 7 is expected to fail under this key)
Uses the same breach state as B2 (its own key, independent of `breach`): while a lane is breached for 8 waves, each free wave on
it carries an 11th unit, a super minion (corvette copy, hull 1,400, shield 250, cannon range +20%, normal damage multipliers).
Banner as B2. Usage: `super_minions`. Pass: S2 +8 (onset, decided_to_end) with ms_big_damage_share >= 0.60 reported.
### B8 Softer mothership | `ms_soft:hull` / `ms_soft:shield` / `ms_soft:mult` | REQ-CHANGE: "The mothership should have a lot of health", "weak to large ships" and the (barely) win against frigates
hull: hull_max x0.75. shield: shield_max x0.5. mult: Rules.MOTHERSHIP_ATTACKER large and capital 2.0 -> 3.0 (add a
`mothership_attacker_large` tunable to Rules.TUNABLES; do not use incoming_mults, which hits every attacker). Report the full
ms_duel table (winners, % HP left) for each value; it does not block. Usage: `ms_soft_hull_damage` (hull damage taken under the
modified numbers). Pass: S2 or S1 +8.
### B9 Fewer free waves late | `waves_late:slow` / `waves_late:none` | REQ-CHANGE: minions "spawn from the mothership regularly" (free waves)
slow: from 30:00 `wave_interval` doubles (35 -> 70 s); none: no free waves from 35:00 (waves already out live on; the paid
minion-control module is untouched). A tick hook sets `Game.tunables["wave_interval"]`; check MinionDirector reads it each wave.
Usage: `waves_skipped`. Pass: S2 ms_big_damage_share/closure +8 or S6 late +8 with S1 not worse.
### Optional deep-dive carry-overs (screen last, only if budget remains; skip any already in main as a variant)
`lanespawn:on` (late minions launch from the lane ends; REQ-CHANGE: minions "spawn from the mothership regularly"; turret damage
from minions fell 45k -> 3k and the match ran its full length), `eff:on` (weapon-aware target choice; matches ended 30-170 s
earlier; none), `ms:nosmall` (small non-bomber ships stop sieging the mothership; REQ-CHANGE: "both should be needed to push
lanes"). Counters `lanespawn_waves`, `eff_picks`, `small_siege_skips`.

## 3. Levers and alternatives
You own **siege AI** (B1). Do NOT change hyperspace timing (pacing fork), the turret rebuild lock (teamfights fork), economy
numbers or the admiral plan order. **At most one of B3, B5 and F3 (admiral fork) merges**, so screen B3 and B5 head to head. No
fork reads another fork's variant keys.

## 4. Screening protocol and final report
Shared rules: each idea is a feature module `scripts/features/<name>.gd` + one line in `FeatureRegistry.FEATURES` + a default in
`Rules.VARIANT_DEFAULTS`; hooks only (`Rules.tune`, `unit.incoming_mults`, `world.tick_hooks`, Events, `Game.count_usage`); an off
feature runs no code and draws no random numbers; game code never reads `tests/lib/adv_index.gd`. Checks first: `load_all`,
`det_hash` (900 s normal + 300 s `--late`) identical to main with every key at default, doc_check 100%, bot_pilot, support_probe,
ui_tour, and ms_duel for anything touching the mothership. Matches ONLY through `RUN =
<SCRATCH>\run_batch.ps1`.
- Screen each idea alone with 10 symmetric late runs: `& $RUN -Project <fork folder> -Seeds (101..110) -OutDir <logs>\<tag> -Tag
  <key>_<value> -Extra "--late","--symmetric","--secs=1200","--skill-jitter","--variant=<key>:<value>"`, then `python
  tools/fun_score.py --dir <logs>\<tag> --vs <baseline v2 late logs>`. Late logs score only S1, S2, S5 (fight_p90_late) and S6
  (pilot_kill_share_late). Keep an idea if its target rises 8+ points and FUN does not fall; usage near 0 = INVALID, not negative.
- Order (about 3.3 match-equivalents per screen; budget ~60 total, 20 for the final): B1, B2, B3, B5, B7, B6, B9, B8, B4, then
  carry-overs.
- Final: best combination on seeds 101-120, FULL matches (`--secs=3600 --skill-jitter`), vs baseline v2. Acceptance: FUN +5 with a
  one-sided 90% paired-bootstrap lower bound > 0, no ingredient whose 80% CI is wholly below -15. Targets: ended_rate >= 95%,
  median minutes 30-40 (p90 <= 52), onset 22-34, final_push 120-420 s, limbo p90 <= 180 s, bite >= 35%, ms_big_damage_share >=
  0.60, decided_to_end <= 10, comeback15 >= 15%, Halcyon win rate 40-60%, S1 >= 80, S2 >= 75.
- **Final report must contain:** S1-S11 median/IQR baseline v2 vs combination; FUN with 90% lower bound; every S2 piece; share of
  matches ending under 20 and 25 min (over-correction check); ms_duel table; usage counters; `ended_by` counts; gate list;
  keep/drop per idea; every REQ-CHANGE in plain words (B2 fulldmg, B6, B7, B8, B9, lanespawn, ms).
