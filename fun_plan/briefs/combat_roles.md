# Fork brief: combat_roles (fork E)

Game: Halcyon Drift, a Godot 4.7 space MOBA (13 v 13: 12 pilots + 1 admiral per team; ships are SMALL (fighter, bomber, lance),
MEDIUM (support and logistics corvettes), LARGE (flak and ion frigates) or CAPITAL (destroyer, battlecruiser); minions are
low-skill lane bots; pilot ships have a 4-zone shield and an energy mode switch weapons/shields/thrusters). You work ONLY in
`forks/combat_roles/` (a copy of `remake/`). Read first: `scripts/features/feature_registry.gd`,
`scripts/features/escort_wing.gd`, `scripts/world/combat.gd` and the combat-scaling part, `scripts/ai/pilot_targeting.gd`,
`pilot_systems.gd`, `scripts/entities/weapon_mount.gd`. Docs style: docs/CODE_STYLE.md. Shared rules repeated in section 4;
README.md has the full set.

## 1. Goal and ingredients
Pilots decide fights. Minions stop being the late-game killer, small ships reward flying skill, big ships reward positioning
(escorted means deadly, isolated means dead), so both sizes are needed.
- **S6 Pilots, not bots, decide fights (weight 10):** pilot_kill_share (0 at <= 0.40, 100 at >= 0.65), pilot_kill_share_late after
  30:00 (0 at <= 0.30, 100 at >= 0.55), pilot_involved_death_share (an enemy pilot did >= 10% of the victim's damage in 15 s; 0 at
  <= 0.50, 100 at >= 0.80), unattended_turret_loss_share (100 at <= 0.10, 0 at >= 0.35). Baseline about 60 (minions kill 16% of
  pilots before 10:00 and 42-43% after 30:00).
- **S7 Skill expression and readable TTK in small ships (weight 9):** skill_rho_small (Spearman of PilotAI.skill vs small-hull
  score; T 0.10/0.35/0.65/0.85), duel_skill_winrate (20 fighter duels, skill 0.90 vs 0.55; T 0.50/0.70/0.85/0.97), ttk_small_med_s
  (T 1.5/4/10/20, never below the baseline median), burst_death_share_small (deaths with ttk < 1.5 s; 100 at <= 0.05, 0 at >=
  0.25). Baseline about 60, unmeasured.
- **S8 Both sizes needed (weight 8):** size_parity |log2(I_small/I_big)| (100 at <= 0.58, 0 at >= 2.0), arena_small_winrate (4
  equal-credit match-ups, T 0.15/0.40/0.60/0.85), big_flak_pd_kill_share (big-ship kills with a flak or point-defence killing
  blow; T 0.05/0.25/0.60/0.85), big_pos_gap (median TTK of isolated big-ship deaths / supported ones; 100 at <= 0.5, 0 at >= 1.0),
  small_late_kill_share (small hulls' share of pilot kills after 25:00; T 0.10/0.30/0.60/0.80). Baseline about 60, mostly
  unmeasured.
- Arena metrics are computed ONCE PER BUILD (about 0.5 h): `tests/arena_matrix.gd` prints a `DUEL_JSON` line that `fun_score.py`
  reads when it sits in the same log folder as the FUN_JSON logs. Run it for every idea that touches S7/S8, via the queue with
  `-Test arena_matrix -Seeds 1 -Extra "--auto","--no-pilots","--no-jungle","--no-admiral-ai","--variant=<key>:<value>"` (add
  `--only=duel` or `--only=matrix` to save time). Arena regressions that must hold: 3 fighters beat 3 lances; 2 bombers beat a
  lone flak frigate; ion beats flak (`tests/arena.gd`).
- Context (AI deep dive): minion damage was tuned when most shots missed; they now land, and pilots get a third fewer minion last
  hits. Only E1 may change how hard minions hit pilots (`MINION_VS_SHIP_MULT` stays 0.6). Bombers are the whole bot lane (seats 2,
  6, 10), kill 5 pilots to the fighters' 139 in 3 matches and dealt 0 torpedo damage to a mothership in 3 late matches (deep-dive
  item 8); hull choice is scripted per seat (`PilotShopping.HULL_PREF`), so judge hull roles on size-class numbers, not per-hull
  kill rates.

## 2. Ideas to build (all keys default `off` in Rules.VARIANT_DEFAULTS; use `--variant=<key>:<value>`)
### E1 Minions stop out-scaling pilots | `minion_cap:on` | REQ-CHANGE: none
Through `world.combat.minion_scale_hook`: when a minion's hit lands on a pilot ship (`Unit.K_SHIP`) the effective scale is
min(Minions.scaling(t), 1.15) and `TeamState.minion_buff` (Reinforced Waves) is ignored for that hit (today stat_scale is passed
into the minion's mount updates, minion.gd:134, so Combat divides it out and applies the capped value). Scaling and buffs still
apply to minion hull and to damage against minions, turrets, bays and the mothership. MINION_VS_SHIP_MULT stays 0.6; turret
multipliers untouched. AI: none needed. Usage: `capped_minion_hits` (minion hits on pilot ships where the cap lowered damage).
Pass: S6 +8 (pilot_kill_share_late up to >= 0.55, involved share up); unattended turret losses and minutes must not worsen.
### E2 Escorts make big ships deadly | `escort_pd:on` | REQ-CHANGE: none
Every 0.5 s each LARGE or CAPITAL ship caches support_n = friendly pilot ships within 2,500 (not itself) + floor(friendly minions
within 2,500 / 3), capped at 3. Its anti-strike-craft guns fire at x(0.6 + 0.2 x support_n): every PD gun, the destroyer and
battlecruiser `flak_auto` mounts, and the Flak Frigate's aimed flak battery (a turret mount, ships.gd:113). Main batteries
unaffected. With support_n == 0 shield regen is also x0.7. The ship status panel shows ESCORTED or ISOLATED. AI: none (the fix is
the ship rule). Usage: `big_isolated_seconds`, `big_escorted_seconds`. Pass: S8 +8 (big_pos_gap <= 0.5, big_flak_pd_kill_share up,
size_parity down); watch minutes and the arena result 2 bombers beat a lone flak frigate.
### E3 The Lance hunts isolated big ships | `lance_role:on` | REQ-CHANGE: none
In Combat, lance-beam hits on LARGE or CAPITAL targets that land in the target's REAR shield zone deal x1.35. No arc change (mount
arcs are half-angles: destroyer heavy cannons +/-150 degrees already leave a 60-degree rear gap, battlecruiser ion turrets +/-140
leave 80). AI: pilots flying a Lance (the lancer before 20:00 and the junglers) treat a visible enemy big ship within 6,000 with
support_n == 0 (or, if E2 is off, no friendly within 2,500) as prey and approach its rear arc; flak still punishes them if the
ship is escorted. Usage: `rear_lance_hits`. Judge on size parity, big_pos_gap, small_late_kill_share and skill_rho_small, NOT the
Lance's own kill rate (junglers farm camps). Pass: S8 +8; 3 fighters still beat 3 lances.
### E4 A payoff for holding an energy-routing mode | `routing_payoff:on` | REQ-CHANGE: none
Each ship tracks how long its current energy mode has been held; after 3 s (SMALL), 4 s (MEDIUM), 6 s (LARGE) or 8 s (CAPITAL) it
is "charged" and a HUD pip lights. Weapons charged: the next shot opens a 2 s overcharge at x1.4 damage, then the charge resets.
Shields charged: the focused zone gains an overshield of +40% of its capacity, lost when absorbed or after 6 s. Thrusters charged:
the next boost costs no energy and has +20% thrust for 1.5 s. Mode-switch cooldowns unchanged. AI (`PilotSystems`): every pilot
that ALREADY routes energy (the existing skill > 0.55 rule) holds Weapons when its target is 1.2-2x its weapon range away; NO new
skill threshold (that would raise rho by construction). Usage: `charges_spent`. Pass: S7 +8 (skill_rho_small up toward 0.35-0.65,
duel_skill_winrate 0.70-0.85) with burst deaths <= 5% and ttk_small_med not below baseline.
### E5 Big ships in the jungle | `jungle_big:medium` / `jungle_big:all` | REQ-CHANGE: "a jungle ... that only small ships can travel through"
Find where "only small ships fit" is enforced (the 101-wide gate chokes and the jungle path graph in `map_builder_jungle.gd`, size
checks in PilotFlight route costs, the human flight barrier) and, only under the variant, relax it: `medium` lets MEDIUM hulls in,
`all` also LARGE and CAPITAL hulls (they take the existing forgiving asteroid collision damage). The map must be identical when
the key is off. AI: big-ship pilots may take a jungle route when its route cost (flying time) is lower; junglers unchanged. Usage:
`big_jungle_seconds`. Pass: S8 or S6 +8 (isolated big ships die to small ships); report who farms the camps (credits by size
class) and the effect on ms_big_damage_share.
### E6 Wider maximum zoom | `zoom_max:wide` / `zoom_max:xwide` | REQ-CHANGE: "lock players to a max zoom that is close to their ship ... scales with ship size"
Multiply the per-size zoom limit by 1.5 (`wide`) or 2.0 (`xwide`) for the human camera. The AI does not use the camera, so
headless screens will show no change: build it, prove det_hash is unchanged, find out whether any gameplay number (vision,
minimap) reads the zoom and measure that if so, add a ui_tour screenshot pair at both zooms, and hand it to the council as a
human-playtest item (ingredient 12). Usage: `zoom_wide_frames` (human camera frames beyond the old limit; 0 headless, so the
screen is NOT evaluable: mark it "not screenable", do not call it negative).
### Optional deep-dive carry-overs (screen last, only if budget remains)
`bomber_role:seats` (seats 6 and 10 fly Fighters instead of Bombers in `PilotShopping.HULL_PREF`) and `bomber_role:torp` (torpedo
damage vs small craft x0.35 -> x0.6 via a new tunable; DAMAGE table row W_TORPEDO). Both REQ-CHANGE: none. Usage
`bomber_seat_swaps`, `torpedo_small_hits`. Pass: S8 small_late_kill_share/size_parity +8.

## 3. Levers and alternatives
You own **minion damage vs pilot ships** (E1) and the **ship-rule hooks** (E2-E4). Do NOT change hyperspace timing, the turret
rebuild lock, siege AI, economy numbers or mothership numbers. No "at most one merges" group for this fork. No fork reads another
fork's variant keys (E3 may read E2's own state only inside this fork).

## 4. Screening protocol and final report
Shared rules: each idea is a feature module `scripts/features/<name>.gd` + one line in `FeatureRegistry.FEATURES` + a default in
`Rules.VARIANT_DEFAULTS`; hooks only (`Rules.tune`, `unit.incoming_mults`, `world.combat.minion_scale_hook`, `world.tick_hooks`,
Events, `Game.count_usage`); an off feature runs no code and draws no random numbers; AI use may not add a skill threshold. Checks
first: `load_all`, `det_hash` (900 s normal + 300 s `--late`) identical to main with every key at default, doc_check 100%,
bot_pilot (flight feel: A/D strafe and turn as labelled), support_probe, ui_tour. Matches ONLY through `RUN =
<SCRATCH>\run_batch.ps1`.
- Screen each idea alone on seeds 101-106: `& $RUN -Project <fork folder> -Seeds (101..106) -OutDir <logs>\<tag> -Tag
  <key>_<value> -Extra "--secs=3600","--skill-jitter","--variant=<key>:<value>"` plus its arena run, then `python
  tools/fun_score.py --dir <logs>\<tag> --vs <baseline v2 logs>`. A screen only REJECTS: keep an idea if its target rises 8+
  points and FUN does not fall; usage near 0 = INVALID, not negative.
- Order (about 6 match-equivalents per screen plus about 1 for arena; ~60 total, 20 for the final): E1, E2, E4, E3, E5, then
  carry-overs; E6 needs no screen.
- Final: best combination on seeds 101-120 vs baseline v2, plus one arena_matrix run. Acceptance: FUN +5 with a one-sided 90%
  paired-bootstrap lower bound > 0 and no ingredient whose 80% CI is wholly below -15. Targets: pilot_kill_share >= 0.62 and late
  >= 0.55, involved >= 0.75, size_parity <= 0.58, arena_small_winrate 0.40-0.60, big_pos_gap <= 0.6, big_flak_pd_kill_share
  0.25-0.60, small_late_kill_share >= 0.30, skill_rho_small >= 0.35, duel_skill_winrate 0.70-0.85, TTK median not below baseline
  with burst <= 5%, minutes up at most 5, S6 >= 80, S7 >= 75, S8 >= 70.
- **Final report must contain:** S1-S11 median/IQR baseline v2 vs combination; FUN with 90% lower bound; every S6, S7, S8 piece;
  the arena results and the three regressions; the cause-of-death table (pilot, minion, turret, mothership, derelict, rock); usage
  counters (isolated vs escorted seconds); gate list; keep/drop per idea; every REQ-CHANGE (E5, E6) in plain words.
