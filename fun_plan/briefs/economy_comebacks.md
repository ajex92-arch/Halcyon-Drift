# Fork brief: economy_comebacks (fork C)

Game: Halcyon Drift, a Godot 4.7 space MOBA (13 v 13: 12 pilots + 1 admiral per team; pilots have their own credits and 6 gear
slots, the admiral spends a team treasury; ore comes from mining drones, not from pilots). You work ONLY in
`forks/economy_comebacks/` (a copy of `remake/`). Read first: `scripts/features/feature_registry.gd`,
`scripts/features/escort_wing.gd`, `scripts/team/economy.gd`, `scripts/data/rules.gd` (the TUNABLES list),
`scripts/ai/pilot_shopping.gd`. Docs style: docs/CODE_STYLE.md. Shared rules repeated in section 4; README.md has the full set.

## 1. Goal and ingredients
Make money follow play: skill and objectives move the economy, a trailing team has an EARNED way back, and both seats always have
something worth buying.
- **S9 Economy reflects play (weight 6), the main target:** play_income_share (pilot credits from kills, assists, minions,
  turrets, derelicts, bays, drones, wards, repair drones and new bounty reasons / all PilotProfile.earned; T 0.20/0.45/0.70/0.90),
  earn_spread (median over seeds of p75/p25 of AI pilots' earned; T 1.05/1.3/2.0/3.0), pilot_float_30 (average unspent pilot
  credits at 30:00; 100 at <= 1,200, 0 at >= 3,500), treasury_float_late (mean treasury after 30:00; 100 at <= 3,000, 0 at >=
  20,000). Also report corr(skill, earned). Baseline about 25 (play share ~0.30, spread ~1.1, float 2.7k, treasuries 17-89k).
- **S3 Suspense and earned comebacks (weight 13), the second target:** adv_lead_changes per seed T(0,2,5,9), comeback15 (the
  winner trailed at 15:00) T(0.05,0.20,0.35,0.50), even15_share T(0.10,0.30,0.50,0.75), decided_to_end (100 at <= 8 min, 0 at >=
  20). Baseline about 55, low confidence. S3 is scored on the probe's own adv_index; game code must NEVER read
  `tests/lib/adv_index.gd`.
- Secondary/guards: S7 skill_rho_small (not below baseline), S1 (median minutes, ended_rate), snowball risk (even15, comeback15
  must not fall below 15%).
- Context (AI deep dive): minions now hit what they aim at, so pilots get about a third fewer minion last hits (766 -> 525);
  `minion_bounty_growth` (and MINION_VS_MINION_MULT) are legitimate knobs for C1 if pilot income from minions matters. The
  treasury pile-up (2,000-10,000 idle) is partly an admiral-fork topic: you own the PILOT-side sinks (C3, C4); the admiral-side
  sinks (Fleet Command, more assets) belong to the admiral fork.

## 2. Ideas to build (all keys default `off` in Rules.VARIANT_DEFAULTS; use `--variant=<key>:<value>`)
### C1 Income from play | `econ:play` | REQ-CHANGE: none
Through the tunables (`Rules.tune`, names in Rules.TUNABLES): passive_income 1.5 -> 1.0, ore_treasury_share 0.6 -> 0.75 (pilots'
ore split falls 40% -> 25%), kill_base 100 -> 150, kill_value_share 0.12 -> 0.15, turret_bounty 350 -> 500 (split among attackers)
PLUS 60 credits to every pilot of the team within 5,000 of the turret (new code in economy.gd), minion_bounty_growth 0.05 -> 0.10
per 5 min. PilotShopping reserve unchanged. Usage: `turret_proximity_payouts` (the other numbers change themselves; also print
total pilot credits by reason). Pass: S9 +8 (play_income_share 0.45-0.60, earn_spread up) with S3 not down; watch comeback15.
### C2 Accrued pilot bounties, and objective bounties for the trailing team | `bounties:on` and `bounties:equal` | alternative to F2 | REQ-CHANGE: none for `on`; `equal` = DESIGN (the research rejected an equal split as passive and unearned)
(a) `PilotProfile.bounty_acc` grows 1 per 3 credits earned from kills and assists and 1 per 20 from minions and derelicts, after a
100-credit buffer, cap 700; `Economy._ship_killed` pays bounty_acc instead of SHUTDOWN_PER_STREAK x streak (the Ace buff stays)
and resets it. (b) New world part `scripts/team/comeback_director.gd` with its OWN deficit from scoreboard numbers: D = (enemy
turrets alive - ours alive) + (enemy pilot kills - ours over the last 300 s)/4. From 14:00 a team with D >= 3 for 60 s is "behind"
(plus a 30 s linger). Every enemy turret or repair bay it destroys while behind pays 600 + 150 x D (cap 2,000): 60% split among
its pilots who damaged the structure in the last 15 s or were within 3,000; 40% split among all 12; +50% of the total to its
treasury. Gold ring and banner for both teams. While a team is behind, accrued-bounty payouts it earns on its victims are halved.
AI: add a weight x1.5 for bounty structures through `world.push_weight_hooks`; flex pilots and junglers within 8,000 divert to
them. `equal`: same, but the whole payout is split equally among all 12 pilots (alive or dead), no contributor share. Usage:
`bounty_structure_kills`, `bounty_acc_paid`. Pass: S3 +8 (comeback15 into 20-35%, lead changes >= 2) with decided_to_end not
longer; watch skill_rho_small.
### C3 Mk II gear tier | `gear_mk2:on` | REQ-CHANGE: none (repeatable sink: FLAG to the user at merge, PROGRESS left sinks as their decision)
Every gear item gets a Mk II upgrade bought while docked at the mothership and only if the pilot owns the Mk I: price 2.5 x Mk I
(1,000-3,750), stats x1.6, same slot and category (inventory entry `{'id','count','mk':2}`), sells back for 50% of the total paid;
the hangar shows "Upgrade to Mk II". AI: new step 6 in `PilotShopping`: once its gear list is full, upgrade items in
GEAR_SMALL/GEAR_BIG order whenever credits minus the price stay above the reserve. Usage: `mk2_purchases`. Pass: S9 +8 via
pilot_float_30 <= 1,200; watch TTK (pilots get tougher late) and size parity.
### C4 Buyback that strains the mothership | `buyback:on` | REQ-CHANGE: none (it strengthens respawn strain)
A dead pilot may pay to respawn at once: cost = 150 + 25 x match minute + 10% of the hull-and-modules value just lost, at most
once per 180 s; a bought respawn calls `TeamState.note_respawn()` twice. Humans get a death-screen button. AI buys back when its
team is defending or its mothership is below 60% hull and it holds cost + 500. Usage: `buybacks`. Pass: S9 +8 (pilot_float) or S3
+8 (final_push, comeback windows); watch ms_limbo (defenders refilling) and strain uptime.
### C5 Fleet Doctrine | `doctrine:on` | REQ-CHANGE: none (repeatable sink: FLAG to the user at merge)
A repeatable admiral research, `TeamState.doctrine_level` (max 10): cost 1,500 x 1.35^n, 45 s each; each level gives friendly
PILOT ships +2% max hull and +3% shield regen (read by ShipStats); minions, turrets and the mothership unaffected. The AI's
`AdmiralPlan` appends it after the main plan whenever the treasury exceeds the cost by 1,000. Usage: `doctrine_levels`. Pass: S9
+8 via treasury_float_late <= 5,000; watch late TTK and closure (both sides scale).
### C6 Catch-up income or shared team income | `catchup:income` / `catchup:share` | DESIGN (the research rejected them: passive, unearned, suppress the skill reward)
Use the same own-deficit D as C2 (share the helper). income: from 10:00 every pilot of the trailing team (D >= 3) earns +0.4
credits/s per point of D, cap +2 cr/s, no condition on play. share (HotS team-XP analogue): 30% of every credit a pilot earns from
kills, assists, minions and turrets goes into a team pool and is paid out equally to all 12 team pilots (alive or dead) at once.
Usage: `catchup_credits`, `shared_credits`. Pass: S3 +8 (lead changes, comeback15) while FUN does not fall; report corr(skill,
earned) and skill_rho_small, which are expected to drop.
### C7 Pilot mining | `pilot_mining:hold` / `pilot_mining:extractor` | REQ-CHANGE: "Resource nodes should not be able to be mined by players at hardpoints" and "Remove pilot independent extractors"
hold: a pilot ship below 40 u/s within 400 of an ore node with no enemy pilot within 2,500 earns 5 cr/s (600 per visit, then the
node is dry for that pilot for 120 s). extractor: a pilot pays 500 credits to anchor a personal extractor at a free node (max 1
per pilot; 600 hull; 3 cr/s to its owner; 150 bounty to its destroyer). AI: when idle (travel/idle bucket) within 3,000 of a node
with no enemy near, hold at it (`hold`); buy one when credits minus the reserve exceed 800 (`extractor`). Usage:
`pilot_mining_seconds`, `extractors_built`. Pass: S9 +8 (pilot_float_30, income spread); idle share must not rise elsewhere.
### C8 Mothership weakens after big spends | `ms_spend_weak:on` | REQ-CHANGE: "The mothership should no longer become weaker after large treasury spends"
The original brief's rule. A rolling 60 s treasury spend of 2,000+ sets `mothership.incoming_mults["spend"]` = 1 + 0.15 x
(spent/2,000), cap 1.45, decaying linearly over 90 s. Respawn strain is unchanged. The AI admiral is NOT told (so the penalty
bites). Usage: `weak_windows`, `weak_seconds`. Pass: S3 or S2 +8 (lead changes, onset); report treasury_float_late and
late_spend_ratio.
### C9 Push/morale meter | `morale:on` | DESIGN (the research rejected it: stronger minions are the opposite of the minion-dominance fix)
Per-team meter: +1 per enemy pilot kill, +3 per enemy turret kill, -1 per 20 s, cap 15. Each wave launched gets hull and damage
x(1 + 0.01 x meter) (up to +15%, against every target, as in Squadrons). Banner shows the meter. Automatic for the AI. Usage:
`morale_waves`. Pass: S3 decided_to_end +8 or S1 +8; report comeback15 (expected to fall) and pilot_kill_share_late.

## 3. Levers and alternatives
You own the economy numbers (the TUNABLES under "Economy"). Do NOT touch respawn waits (pacing fork), the turret rebuild lock
(teamfights fork), siege AI (endgame fork) or admiral assets (admiral fork). **At most one of C2(b) and F2 (admiral fork)
merges**; `bounties:equal` belongs to the C2 group. No fork reads another fork's variant keys.

## 4. Screening protocol and final report
Shared rules: each idea is a feature module `scripts/features/<name>.gd` + one line in `FeatureRegistry.FEATURES` + a default in
`Rules.VARIANT_DEFAULTS`; hooks only (`Rules.tune`, `unit.incoming_mults`, `world.push_weight_hooks`, `world.tick_hooks`, Events,
`Game.count_usage`); an off feature runs no code and draws no random numbers; AI use may not add a skill threshold. Checks first:
`load_all`, `det_hash` (900 s normal + 300 s `--late`) identical to main with every key at default, doc_check 100%, bot_pilot,
support_probe, ui_tour (hangar and death-screen buttons). Matches ONLY through `RUN =
<SCRATCH>\run_batch.ps1`.
- Screen each idea alone on seeds 101-106: `& $RUN -Project <fork folder> -Seeds (101..106) -OutDir <logs>\<tag> -Tag
  <key>_<value> -Extra "--secs=3600","--skill-jitter","--variant=<key>:<value>"`, then `python tools/fun_score.py --dir
  <logs>\<tag> --vs <baseline v2 logs>`. A screen only REJECTS: keep an idea if its target (S9 or S3 as stated) rises 8+ points
  and FUN does not fall; usage near 0 = INVALID, not negative.
- Order (about 6 match-equivalents per screen; of ~60 total, 20 go to the final, so about 6 screens fit): C1, C2, C5, C3, C4, C6,
  C9, C8, C7; drop from the end.
- Final: best combination on seeds 101-120 vs baseline v2. Acceptance: FUN +5 with a one-sided 90% paired-bootstrap lower bound >
  0 and no ingredient whose 80% CI is wholly below -15. Targets: play_income_share 0.45-0.65, earn_spread 1.3-2.0, pilot_float_30
  <= 1,500, pilots' money_end <= 2,000, treasury_float_late <= 5,000, lead changes median >= 2, decided_to_end median <= 10,
  skill_rho_small not below baseline, S9 >= 75, S3 up 10+.
- **Final report must contain:** S1-S11 median/IQR baseline v2 vs combination; FUN with 90% lower bound; every S9 and S3 piece;
  corr(skill, earned); comeback15 and even15 (confirmation on 101-140 is done at merge); usage counters; gate list; keep/drop per
  idea; the repeatable sinks (C3, C5, C7 extractor) flagged for the user; every REQ-CHANGE (C7, C8) and DESIGN note (C2 equal, C6,
  C9) in plain words.
