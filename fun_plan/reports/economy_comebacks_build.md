STATUS: 12:28 BUILD DONE and handed back. All nine ideas built (13 variant values), run_checks ALL OK, doc_check 100%, det_hash identical to int3 (normal and late), 12/12 smokes PASS, allA natural run clean. Two queued runs (natural\allB_seed102, smoke\extractor240_seed7) had not started yet (queue starved by other builders); read them when they finish.

# economy_comebacks: build report

Fork: `FC\forks\economy_comebacks` (copy of `SP\notate\int3`). Manifest with every file, constant and shared-code change:
`FC\forks\economy_comebacks\FORK_MANIFEST.md`. Smoke tests: `tests/econ_smoke.gd` (new; late-game start plus a few
nudges, prints PASS/FAIL per usage counter). Logs: `SP\fun\logs\economy_comebacks\{det,smoke,natural}`.

## Checks

| Check | Result |
|---|---|
| `run_checks.ps1` | CHECKS ALL OK (import, load_all, bot_pilot, support_probe, ui_pilot, ui_admiral all 0 failures) |
| `doc_check.ps1` | TOTAL 195 files: headers 195/195, funcs 1140/1140 documented, members 1618/1618 noted |
| det_hash seed 7, normal `--secs=900`, no `--variant` | IDENTICAL to int3 (181 lines, END `t=900 230 units, 749aa6eb`); reference = `fun\logs\endgame_closure\smoke\d_int3_n_seed7.txt` (another builder's int3 run; equal hashes prove equal settings) |
| det_hash seed 7, `--late --secs=300`, no `--variant` | IDENTICAL to int3 (61 lines, END `t=1800 226 units, 4bccf106`); reference = `fun\logs\pacing_downtime\det\int3_late_seed7.txt` |
| ui_tour (pilot and admiral, headless `--force-hud`) with `gear_mk2, buyback, doctrine, bounties, morale` ON | done, no SCRIPT ERROR (hangar Gear tab, hangar Launch button, Mothership tab with the Doctrine button are built) |
| Smoke per idea (below) | all PASS, no SCRIPT ERROR |

The determinism runs and run_checks used the final shared-code state; afterwards only `econ_banner.gd` (draw order)
and `econ_smoke.gd` changed, and load_all and doc_check were re-run after those edits. The "ObjectDB instances leaked /
resources still in use at exit" lines also appear in int3 runs.

## Smoke runs

How: `tests/econ_smoke.gd`, seed 7, `--secs=100` from a 25:00 late-game start (`LateGame.apply`), with these nudges only
(they create situations and never touch the features): +0.5 s two Cinder turrets removed (Cinder deficit D = 4, "behind"
after 60 s); +8 s every pilot gets +15,000 credits (the late idle-money pile-up); +62.5 s Cinder's flex pilot and
jungler are moved 3,500 from a Halcyon turret, one more pilot 4,500; +66 s that turret is destroyed by Cinder; +67 s two
Halcyon pilot ships destroyed by Cinder (given an accrued bounty of 800 first) and the Halcyon mothership set to 55% hull;
+70 s Halcyon spends 2,500. The AI behaviour (diversion, buyback, Mk II upgrades, doctrine, trips to nodes, extractor
building) is the AI's own. The first six rows were run directly (before the lead's "everything through run_batch"
rule); the two multi runs went through `run_batch.ps1`.

| Idea | Variant string | Usage counters (all above 0 = PASS) |
|---|---|---|
| C1 | `econ:play` | turret_proximity_payouts 4, credits_kill 1522, credits_assist 117, credits_minion 182, credits_ore 2870, credits_derelict 1185, credits_escort 2228, credits_turret zone 240 |
| C2 on | `bounties:on` | bounty_structure_kills 1, bounty_structure_credits 1200 (= 600 + 150 x D 4), bounty_acc_paid 700 (2 victims, halved because the killer's team was behind), bounty_diverts 2 |
| C2 equal | `bounties:equal` (run together with C6 share, C7 extractor) | bounty_structure_kills 1, bounty_structure_credits 1200, bounty_acc_paid 700, bounty_diverts 2 |
| C3 | `gear_mk2:on` | mk2_purchases 16 (AI upgrades) |
| C4 | `buyback:on` | buybacks 2, buyback_credits 2259 (AI, mothership under 60% hull) |
| C5 | `doctrine:on` | doctrine_levels 2, doctrine_credits 3000 (AI admiral) |
| C6 income | `catchup:income` (run together with hold, morale) | catchup_credits 1199 |
| C6 share | `catchup:share` | shared_credits 557 |
| C7 hold | `pilot_mining:hold` | pilot_mining_seconds 33 (AI trips to nodes) |
| C7 extractor | `pilot_mining:extractor` | extractors_built 2, extractor_credits 157 (AI builds) |
| C8 | `ms_spend_weak:on` | weak_windows 2, weak_seconds 197 |
| C9 | `morale:on` | morale_waves 2, morale_minions 48 |

## Natural-play run (not a screen; one match, no baseline, only to catch crashes and see the AI use the mechanics)

`natural\allA_seed101.txt`: fun_probe seed 101, `--skill-jitter`, with `econ:play, bounties:on, gear_mk2:on, buyback:on,
doctrine:on, catchup:income, pilot_mining:extractor, ms_spend_weak:on, morale:on` ALL ON together. No SCRIPT ERROR; the match
ended at 26.9 min (Cinder won). Usage: bounty_acc_paid 7,582, bounty_diverts 2, bounty_structure_kills 0 (no team was behind
when a structure fell), buybacks 7, catchup_credits 4,499, doctrine_levels 8 (19,896 credits), extractors_built 11,
extractor_credits 23,827 (about 9% of all pilot income: only 1 of 11 was destroyed, see the extractor note below),
extractors_killed 1, mk2_purchases 12, morale_waves 85, turret_proximity_payouts 46, weak_windows 4 (weak_seconds 2,918).
`natural\allB_seed102.txt` (bounties:equal, gear_mk2, buyback, doctrine, catchup:share, pilot_mining:hold, morale) and the
240-second extractor smoke `smoke\extractor240_seed7.txt` were still waiting for a free queue slot when this report was
written; read them there (look for SCRIPT ERROR and the usage line).

Extractor note: in allA the enemy rarely shot extractors (1 of 11), so a pilot extractor is close to a free 3 cr/s. I added
an AI rule after allA (an AI pilot with at least 60% hull and nothing but minions to shoot attacks an enemy extractor its
team can see within 3,000: usage `extractor_hunts`). It passed load_all and doc_check, but it was added after allA ran and
only the queued 240-second smoke exercises it; if that smoke shows a SCRIPT ERROR, remove the `_hunt_extractor` call in
`PilotMiningFeature._ai_think`.

## The ideas (key: values, AI use, flag)

Every key is `off` by default (`Rules.VARIANT_DEFAULTS`); one line each in `FeatureRegistry.FEATURES`. Full constants in
the manifest.

1. **C1 `econ:play`** (REQ-CHANGE: none). Tunables: passive_income 1.5->1.0, ore_treasury_share 0.6->0.75, kill_base
   100->150, kill_value_share 0.12->0.15, turret_bounty 350->500, minion_bounty_growth 0.05->0.10; plus 60 credits (reason
   "turret zone") to every pilot of the destroying team within 5,000 of a destroyed turret (`Events.turret_destroyed`, so
   no economy.gd edit was needed for it). PilotShopping reserve unchanged. AI: earns more for what it already does.
   Usage: turret_proximity_payouts, and `credits_<reason>` totals (credits paid to pilots by reason).
2. **C2 `bounties:on` / `bounties:equal`** (`on`: REQ-CHANGE none; `equal`: DESIGN, the research rejected an equal split as
   unearned; alternative to the admiral fork's F2: at most one of C2(b) / F2 merges). (a) Accrued bounty (+1 per 3 credits
   of kill/assist pay, +1 per 20 of minion/derelict pay, 100 buffer, cap 700), paid through the new `World.bounty_hooks`
   (3 lines in economy.gd) instead of 50 x streak (`shutdown_per_streak` tuned to 0, ace buff unchanged), reset on death,
   halved while the killer's team is behind. (b) New `comeback_director.gd` (own D from turret counts and 300-s pilot
   kills; behind = D >= 3 for 60 s from 14:00, +30 s linger) and structure bounties 600 + 150 D (cap 2,000): 60% to
   helpers (hit it in the last 15 s or within 3,000), 40% to all 12, +50% to the treasury; `equal` splits everything
   equally among the 12. Gold ring (`bounty_ring.gd`), news line and banner (`econ_banner.gd`) for both teams (none are
   made headless). AI: `push_weight_hooks` score / 1.5 for paying turrets; the flex pilot and junglers within 8,000 divert
   to the nearest paying structure through the new `World.pilot_think_hooks` (a ship that cannot enter the jungle only
   picks open-lane structures). Usage: bounty_structure_kills, bounty_structure_credits, bounty_acc_paid, bounty_diverts.
3. **C3 `gear_mk2:on`** (REQ-CHANGE: none; repeatable sink: FLAG to the user at merge). Upgrade for 2.5 x price, stats
   x1.6, entry `{id, count, mk: 2}`, sells for 50% of everything paid. Hangar: an owned gear card shows "Upgrade to Mk II:
   N credits" and a click upgrades; slots read "<item> Mk II". AI: new step 6 in `PilotShopping.shop()` (GEAR_SMALL /
   GEAR_BIG order while credits - price > 120 reserve, once the gear list is bought or the slots are full) plus a trip
   home for an upgrade with the same big-bank rule as new gear. Usage: mk2_purchases.
4. **C4 `buyback:on`** (REQ-CHANGE: none; strengthens respawn strain). Cost 150 + 25 x minute + 10% of the hull+modules
   value just lost, once per 180 s, `note_respawn()` twice, refused if the mothership is down with no bay. Human: the
   hangar Launch button while dead becomes "Buy back now: N credits", and the death banner shows it. AI: every 0.5 s a
   dead AI pilot buys when its team is defending or its mothership is under 60% hull, it holds cost + 500, and the timer
   has more than 5 s left. Usage: buybacks, buyback_credits.
5. **C5 `doctrine:on`** (REQ-CHANGE: none; repeatable sink: FLAG to the user at merge). `TeamState.doctrine_level` max 10,
   cost 1,500 x 1.35^n, 45 s, needs the Research Module; pilot ships +2% max hull and +3% shield regen per level (read in
   `ShipStats`, 4 lines). Human: a button under the Flagship cards of the Mothership tab. AI admiral: buys when the
   treasury minus its next plan step's cost is at least cost + 1,000 (the plan keeps priority). Usage: doctrine_levels,
   doctrine_credits.
6. **C6 `catchup:income` / `catchup:share`** (DESIGN: the research rejected both). Shares the C2 deficit helper
   (`ComebackDirector.ensure`). income: from 10:00 every pilot of a team with D >= 3 gets +0.4 cr/s per point of D, cap
   +2 cr/s, into credits and `earned`. share: 30% of every kill/assist/minion/turret credit goes to a pool paid out equally
   to all 12 pilots at once. Automatic for the AI. Usage: catchup_credits, shared_credits. Expect corr(skill, earned) and
   skill_rho_small to drop.
7. **C7 `pilot_mining:hold` / `pilot_mining:extractor`** (REQ-CHANGE: "Resource nodes should not be able to be mined by
   players at hardpoints" and "Remove pilot independent extractors"; the extractor is a repeatable sink, FLAG). hold:
   slower than 40 u/s within 400 of a node, no enemy pilot within 2,500: 5 cr/s, 600 per visit then dry 120 s. extractor:
   500 credits anchors a `PilotExtractor` (new Unit kind `K_EXTRACTOR` = 10, 600 hull, 3 cr/s to the owner, 150 to its
   destroyer, one per pilot and node). AI: an idle pilot (lane/jungle state, nothing to shoot, no enemy within 2,500,
   slower than 40% of top speed) within 3,000 of a suitable node flies to it (hold: not dry for it; extractor: only when
   credits - 120 > 800 and it has none) and builds; it quits the trip on an enemy, hull < 50%, defend call, siege (big
   ships), a dry node, or after 150 s. Usage: pilot_mining_seconds, extractors_built, extractor_credits, extractors_killed.
8. **C8 `ms_spend_weak:on`** (REQ-CHANGE: "The mothership should no longer become weaker after large treasury spends").
   2,000+ spent in a rolling 60 s sets `mothership.incoming_mults["spend"]` = 1 + 0.15 x spent/2,000, cap 1.45, fading
   linearly over 90 s (hook: `TeamState.spend_hook`, 3 lines). The AI admiral is not told. Usage: weak_windows,
   weak_seconds.
9. **C9 `morale:on`** (DESIGN: the research rejected it). Per-team meter 0-15: +1 per enemy pilot ship destroyed, +3 per
   enemy turret destroyed, -1 per 20 s. Each minion launched gets hull x(1 + 0.01 x meter) (applied the tick it appears)
   and damage through `Combat.minion_scale_hook` (all targets). Banner shows both meters. Automatic for the AI. Usage:
   morale_waves, morale_minions.

## Shared code changed (all inert when every key is at its default)

rules.gd (9 default keys), feature_registry.gd (9 lines), world.gd (two empty hook lists `pilot_think_hooks`,
`bounty_hooks`), pilot_ai.gd (run `pilot_think_hooks` in `_think`), economy.gd (run `bounty_hooks` in `_ship_killed`),
team_state.gd (`spend_hook`, `doctrine_level`), ship_stats.gd (doctrine, behind `doctrine_level > 0`), unit.gd
(`K_EXTRACTOR`), pilot_profile.gd + pilot_profile_shop.gd (Mk II entries; only entries with an `mk` key), pilot_shopping.gd
(step 6 and trip, behind `world.features.has("gear_mk2")`), hangar_gear.gd, hangar_launch.gd, hud_banner.gd,
admiral_board_mothership.gd (UI bits behind the feature checks). Details in the manifest.

## Things to know / not built

- **C7 extractor has no button for a human pilot** (the AI builds; a human gets the hold pay when flying onto a node). Not
  wired because the brief only names AI use.
- The accrued bounty is not shown anywhere on the HUD or scoreboard.
- **Visuals were not checked with a window** (no windowed run: the lead said no screens, and daytime runs are headless).
  The gold ring, the top banner (C2, C9), the hangar Mk II footer, the buyback button text, the Doctrine button and the
  extractor drawing are written and parse (load_all, headless ui_tour with the features on), but nobody has looked at
  them. A windowed `ui_tour --shots` pass with `--variant=gear_mk2:on,buyback:on,doctrine:on` would be the quick look.
- Interpretations of the brief: "after a 100-credit buffer" = payout is the score above 100 (cap 700); "behind" is the
  director's own state, not a probe number; the AI "idle" for C7 = the probe's idle definition (slow, nothing near, not
  fighting); morale's hull bonus is applied at the tick a minion appears (a wave is counted once per team per 10 s).
- C4 AI use is conditional by the brief (team defending or mothership < 60% hull), so its usage in a natural match may
  be low; if a screen shows `buybacks` near 0 treat it as INVALID, not negative.
- Not built from the brief: nothing. All nine ideas and the 13 values exist.

## Screen commands I recommend (brief order: C1, C2, C5, C3, C4, C6, C9, C8, C7; drop from the end)

```powershell
$SP  = "<SCRATCH>"
$RUN = "$SP\run_batch.ps1"
$FORK = "<FC>\forks\economy_comebacks"
$LOGS = "$SP\fun\logs\economy_comebacks"
# one call per idea, each started in the background (6 matches of 3,600 game seconds):
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\econ_play"          -Tag econ_play          -Extra "--secs=3600","--skill-jitter","--variant=econ:play"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\bounties_on"        -Tag bounties_on        -Extra "--secs=3600","--skill-jitter","--variant=bounties:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\doctrine_on"        -Tag doctrine_on        -Extra "--secs=3600","--skill-jitter","--variant=doctrine:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\gear_mk2_on"        -Tag gear_mk2_on        -Extra "--secs=3600","--skill-jitter","--variant=gear_mk2:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\buyback_on"         -Tag buyback_on         -Extra "--secs=3600","--skill-jitter","--variant=buyback:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\catchup_income"     -Tag catchup_income     -Extra "--secs=3600","--skill-jitter","--variant=catchup:income"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\catchup_share"      -Tag catchup_share      -Extra "--secs=3600","--skill-jitter","--variant=catchup:share"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\morale_on"          -Tag morale_on          -Extra "--secs=3600","--skill-jitter","--variant=morale:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\ms_spend_weak_on"   -Tag ms_spend_weak_on   -Extra "--secs=3600","--skill-jitter","--variant=ms_spend_weak:on"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\pilot_mining_hold"  -Tag pilot_mining_hold  -Extra "--secs=3600","--skill-jitter","--variant=pilot_mining:hold"
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\pilot_mining_extractor" -Tag pilot_mining_extractor -Extra "--secs=3600","--skill-jitter","--variant=pilot_mining:extractor"
# only if the budget allows (the DESIGN alternative of C2):
& $RUN -Project $FORK -Seeds (101..106) -OutDir "$LOGS\bounties_equal"     -Tag bounties_equal     -Extra "--secs=3600","--skill-jitter","--variant=bounties:equal"
# then score each:  python tools/fun_score.py --dir "$LOGS\<tag>" --vs <baseline v2 logs>
```
Look at these usage keys in each FUN_JSON before reading any score (near 0 = INVALID): C1 turret_proximity_payouts; C2
bounty_structure_kills (needs a team that is behind from 14:00; a match with no comeback window shows 0 and is not
informative), bounty_acc_paid; C3 mk2_purchases; C4 buybacks; C5 doctrine_levels; C6 catchup_credits / shared_credits;
C7 pilot_mining_seconds / extractors_built; C8 weak_windows; C9 morale_waves.
Combination for the final (suggestion, adjust to the screens): `--variant=econ:play,bounties:on,doctrine:on,gear_mk2:on`
(the keys are independent, so any comma list works; `bounties` and the admiral fork's F2 must not both merge).
