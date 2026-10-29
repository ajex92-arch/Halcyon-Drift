# Fork economy_comebacks: manifest

This is the build manifest of one fun-experiment fork, kept as it was when the fork was merged into the game (v0.2.0), with only its paths, base names and a few notes (the user's later decisions, the API index) updated for this repository. Paths are relative to `remake/`.

Base: the game with every AI fix (the AI deep dive's pass 3, banked into `remake/` before v0.1.0). Nine
ideas (C1-C9), each a feature module behind its own
variant key, all `off` by default. With every key at its default no new code path runs, no random number is
drawn and no unit is made (the only shared-code additions are empty hook lists and branches that are false
when off; see "Shared code changed").

## Variant keys (all default `off`; use `--variant=<key>:<value>`)

| Key | Values | Idea | Flag | Module |
|---|---|---|---|---|
| `econ` | `play` | C1 income from play | none | `econ_play.gd` (EconPlayFeature) |
| `bounties` | `on`, `equal` | C2 accrued bounties + comeback structure bounties | `equal` = DESIGN (research rejected equal split); alternative to the admiral fork's F2 (at most one of C2(b) / F2 merges) | `comeback_bounties.gd` (ComebackBountiesFeature) + `comeback_director.gd`, `bounty_ring.gd`, `econ_banner.gd` |
| `gear_mk2` | `on` | C3 Mk II gear tier | none; repeatable money sink: flagged to the user at merge (the user approved it) | `gear_mk2.gd` (GearMk2Feature) |
| `buyback` | `on` | C4 buyback | none (strengthens respawn strain) | `buyback.gd` (BuybackFeature) |
| `doctrine` | `on` | C5 Fleet Doctrine | none; repeatable money sink: flagged to the user at merge (held by the user for now) | `doctrine.gd` (DoctrineFeature) |
| `catchup` | `income`, `share` | C6 catch-up income / shared team income | DESIGN (research rejected: passive, unearned, suppress the skill reward) | `catchup.gd` (CatchupFeature), shares `comeback_director.gd` |
| `pilot_mining` | `hold`, `extractor` | C7 pilots mine | REQ-CHANGE: "Resource nodes should not be able to be mined by players at hardpoints" and "Remove pilot independent extractors"; the extractor is a repeatable sink (FLAG) | `pilot_mining.gd` (PilotMiningFeature) + `pilot_extractor.gd` |
| `ms_spend_weak` | `on` | C8 mothership weakens after big spends | REQ-CHANGE: "The mothership should no longer become weaker after large treasury spends" | `ms_spend_weak.gd` (MsSpendWeakFeature) |
| `morale` | `on` | C9 push/morale meter | DESIGN (research rejected: stronger minions are the opposite of the minion-dominance fix) | `morale.gd` (MoraleFeature) |

Registered in `Rules.VARIANT_DEFAULTS` (all `"off"`) and `FeatureRegistry.FEATURES` (one line each). No new
`Rules.TUNABLES` entries were needed: C1 only sets existing ones (`passive_income`, `ore_treasury_share`,
`kill_base`, `kill_value_share`, `turret_bounty`, `minion_bounty_growth`) and C2 sets `shutdown_per_streak` = 0.

## What each idea does and its numbers (all constants are at the top of each module)

- **C1 `econ:play`**: passive_income 1.5 -> 1.0, ore_treasury_share 0.6 -> 0.75, kill_base 100 -> 150, kill_value_share
  0.12 -> 0.15, turret_bounty 350 -> 500, minion_bounty_growth 0.05 -> 0.10; plus 60 credits (reason "turret zone")
  to every pilot of the destroying team flying within 5,000 of a destroyed turret. AI: nothing new (it earns more for
  what it does). Usage: `turret_proximity_payouts`, and `credits_<reason>` (credits paid to pilots by reason).
- **C2 `bounties:on|equal`**: (a) accrued bounty: +1 point per 3 credits of kill/assist pay, +1 per 20 credits of
  minion/derelict pay, the first 100 points are a buffer, payout = points above 100, cap 700; paid on top of the kill
  bounty through `World.bounty_hooks` and reset on death; `shutdown_per_streak` = 0 (ace buff unchanged); halved while the
  killer's team is behind. (b) `ComebackDirector`: D = (enemy turrets alive - ours) + (enemy pilot kills - ours in the last
  300 s)/4 from scoreboard numbers only; from 14:00, D >= 3 for 60 s = "behind", +30 s linger. A destroyed enemy turret or
  repair bay while behind pays 600 + 150 x D (cap 2,000): 60% to the pilots who hit it in the last 15 s or are within
  3,000 (equal split), 40% to all 12, +50% of the total to the treasury (reason "comeback"). `equal`: the whole sum split
  equally among all 12 pilots. Gold ring around the paying structures, news line and top-of-screen banner (no window =
  none made). AI: `push_weight_hooks` divides the push score of paying turrets by 1.5; flex pilot and junglers within
  8,000 of a paying structure attack it (`pilot_think_hooks`; a ship that cannot enter the jungle only picks structures in
  open lanes). Usage: `bounty_structure_kills`, `bounty_structure_credits`, `bounty_acc_paid`, `bounty_diverts`.
  Interpretation note: "after a 100-credit buffer" is implemented as: payout = clamp(points - 100, 0, 700).
- **C3 `gear_mk2:on`**: upgrade an owned Mk I gear item to Mk II for 2.5 x price; entry becomes `{id, count, mk: 2}`;
  stats x1.6; sells back for 50% of price + upgrade; hangar Gear tab: clicking an owned item shows/does
  "Upgrade to Mk II: N credits"; slot cards show "Mk II". AI: new step 6 of `PilotShopping.shop()` (upgrade in
  GEAR_SMALL/GEAR_BIG order while credits - price > reserve 120, once the gear list is bought or no room), and a "gear:"
  trip home with the same big-bank rule as new gear. Usage: `mk2_purchases`.
- **C4 `buyback:on`**: dead pilot pays 150 + 25 x minute + 10% of the hull+modules value just lost (max once per 180 s) to
  respawn at once; `note_respawn()` twice; refused when the mothership is down with no bay. Human: the hangar Launch
  button while dead becomes "Buy back now: N credits", and the death banner mentions it. AI: every 0.5 s a dead AI pilot
  buys back when its team is defending or its mothership is under 60% hull, it holds cost + 500 and the timer has > 5 s
  left. Usage: `buybacks`, `buyback_credits`.
- **C5 `doctrine:on`**: repeatable admiral research, `TeamState.doctrine_level` max 10, level n+1 costs 1,500 x 1.35^n,
  45 s each (needs the Research Module); each level: pilot ships +2% max hull and +3% shield regeneration (read in
  `ShipStats`). Human: button at the bottom of the Mothership tab. AI admiral: buys when treasury - cost of its next plan
  step >= cost + 1,000. Usage: `doctrine_levels`, `doctrine_credits`.
- **C6 `catchup:income|share`**: uses `ComebackDirector` D. `income`: from 10:00 every pilot of a team with D >= 3 gets
  +0.4 cr/s per point of D, cap +2 cr/s. `share`: 30% of every credit earned from kills, assists, minions and turrets goes to
  a pool paid out equally to all 12 pilots at once. Usage: `catchup_credits`, `shared_credits`.
- **C7 `pilot_mining:hold|extractor`**: hold: speed < 40, within 400 of a node, no enemy pilot within 2,500: 5 cr/s,
  600 per visit then dry for that pilot 120 s. extractor: 500 credits anchors a `PilotExtractor` (new Unit kind
  `K_EXTRACTOR` = 10, 600 hull, 3 cr/s to its owner, 150 bounty to its destroyer, max 1 per pilot, one per node). AI:
  an idle pilot (lane/jungle state, nothing to shoot, no enemy within 2,500, slower than 40% of top speed) within 3,000 of
  a suitable node flies to it (hold: a node not dry for it; extractor: only when credits - 120 > 800 and it has no extractor)
  and builds there. Human: hold pay works for a human ship too; no button for the extractor (not wired).
  Usage: `pilot_mining_seconds`, `extractors_built`, `extractor_credits`, `extractors_killed`.
- **C8 `ms_spend_weak:on`**: 2,000+ spent from a treasury in 60 s sets that mothership's
  `incoming_mults["spend"]` = 1 + 0.15 x (spent / 2,000), cap 1.45, fading linearly over 90 s. Respawn strain unchanged.
  The AI admiral is not told. Usage: `weak_windows`, `weak_seconds`.
- **C9 `morale:on`**: per-team meter 0..15: +1 per enemy pilot ship destroyed, +3 per enemy turret destroyed, -1 per 20 s.
  Each minion launched gets hull and damage x(1 + 0.01 x meter) (hull when it appears; damage through
  `Combat.minion_scale_hook`, against every target). Banner shows both meters. Automatic for the AI. Usage:
  `morale_waves`, `morale_minions`.

## Files added

- `scripts/features/econ_play.gd`, `comeback_bounties.gd`, `comeback_director.gd`, `bounty_ring.gd`, `econ_banner.gd`,
  `gear_mk2.gd`, `buyback.gd`, `doctrine.gd`, `catchup.gd`, `pilot_mining.gd`, `pilot_extractor.gd`, `ms_spend_weak.gd`,
  `morale.gd` (+ their `.uid` files).
- `tests/econ_smoke.gd`: a 100-game-second smoke test (late-game start plus a few nudges; prints PASS/FAIL for the
  usage counters named in `--expect=`). Not part of run_checks.

## Shared code changed (small; every change does nothing when its feature is off)

| File | Change | Why |
|---|---|---|
| `scripts/data/rules.gd` | nine new keys in `VARIANT_DEFAULTS` (all "off") | registration |
| `scripts/features/feature_registry.gd` | nine lines in `FEATURES` | registration |
| `scripts/world/world.gd` | two new empty hook lists: `pilot_think_hooks`, `bounty_hooks` | AI use (C2, C7) and the accrued bounty (C2) |
| `scripts/ai/pilot_ai.gd` | `_think` runs `world.pilot_think_hooks` (empty loop) before step 7 | C2 diversion, C7 trips |
| `scripts/team/economy.gd` | `_ship_killed` adds `world.bounty_hooks` results to the bounty (empty loop) | C2 accrued bounty |
| `scripts/team/team_state.gd` | fields `spend_hook` (Callable, unset) and `doctrine_level` (0); `spend()` calls the hook when set | C8, C5 |
| `scripts/entities/ship_stats.gd` | `if t.doctrine_level > 0:` hull and shield regen x(1 + k x level) | C5 |
| `scripts/entities/unit.gd` | `K_EXTRACTOR = 10` and one more name in `KIND_NAMES` | C7 |
| `scripts/team/pilot_profile.gd` | `gear_stats()`: an inventory entry with an `mk` key counts x1.6 (never present when off) | C3 |
| `scripts/team/pilot_profile_shop.gd` | `sell_slot()`: `elif s.has("mk")` sells for half of price + upgrade | C3 |
| `scripts/ai/pilot_shopping.gd` | step 6 of `shop()` and one line in `wants_shopping()`, both behind `world.features.has("gear_mk2")` | C3 AI |
| `scripts/ui/hangar_gear.gd` | owned-item footer / click = "Upgrade to Mk II" and "Mk II" slot titles, behind `GearMk2Feature.is_on()` | C3 UI |
| `scripts/ui/hangar_launch.gd` | the Launch button of a dead pilot becomes the buyback button, behind `BuybackFeature.current() != null` | C4 UI |
| `scripts/ui/hud_banner.gd` | the death banner adds the buyback price, behind `BuybackFeature.current() != null` | C4 UI |
| `scripts/ui/admiral_board_mothership.gd` | the Fleet Doctrine button (build and refresh), behind `DoctrineFeature.current() != null` | C5 UI |

## Verification notes

See `../fun_plan/reports/economy_comebacks_build.md` (checks, determinism, smoke results, screen commands).
