STATUS: 12:31 build finished; run_checks ALL OK; doc_check full; det_hash identical (normal 900 s and late 300 s); every idea has a smoke result below. Four extra queued smoke runs are still waiting for a day-time queue slot (see "Still queued" at the end); they are not needed for the checks.

# pacing_downtime (fork A): build report

Fork folder: `forks/pacing_downtime` (copy of `notate/int3`). Manifest with every file, shared edit, key, value and counter: `forks/pacing_downtime/FORK_MANIFEST.md`.
All keys default `off`. With every key at its default, no new code runs (det_hash identical, see checks).

## Ideas built (key:value, default off)

| idea | key:value | what the AI does with it | flag | usage counters | smoke result (seed 7) |
|---|---|---|---|---|---|
| A1 Lane Slipstream, size-scaled | `slipstream:on` | nothing new (its lane routes simply get faster; jungle-job pilots excluded, see notes) | none | `slip_seconds`, `slip_seconds_<size>` | 100 s: 925 pilot-seconds slipping; commute share of flying 0.537 (baseline) -> 0.378; no errors |
| A1b Slipstream, flat speed | `slipstream:flat` | same | REQ-CHANGE: "slowly pushing across the map" (heavier ships travel slower) | same + `big_arrivals`, `big_arrival_s_sum`, `big_arrival_s_sq` | 100 s: 925 slip-seconds, commute 0.368; no errors |
| (measure) | `slipstream:probe` | nothing: only measures big-ship trip times, so A1b can be compared with the normal game | none | `big_arrivals`, `big_arrival_s_sum`, `big_arrival_s_sq` | not run yet (queued, see "Still queued") |
| A2 Forward Redeploy | `redeploy:on` | docked pilots jump to a safe friendly bay or turret near their destination (siege stage/assault point for big ships and bombers in a siege, defend point, jungle camp, else lane front) when it is 6,000+ closer than the mothership; the admiral builds hyperspace right after the Frigate Facility and puts its next bay at 0.5 of the push/siege lane | none (owns the hyperspace-timing lever) | `hyperspace_launches`, `_team0/_team1`, `redeploy_turret_landings`, `redeploy_site_lost` | `--late` 100 s: 17 jumps (10 + 7), all to turrets (no bay had anchored yet); no errors |
| A3 Recall | `recall:on` (key T) | in retreat/home state, more than 9,000 from the mothership hull, no visible enemy pilot within 3,000, 4 s without damage: channels, holds still, shoots nothing | none | `recalls_started/completed/cancelled` | normal 480 s: 38 started, 24 completed, 13 cancelled; no errors |
| A4 Size-scaled respawn | `respawn:size` | nothing needed | none | `size_respawns` | normal 600 s: 75 scaled waits; `--late` 180 s: 10; no errors |
| A5 Respawn at a forward site | `respawn_site:bay` / `respawn_site:waypoint` | an AI pilot whose wait is over is launched next to the best safe forward bay (or inside the waypoint ring) instead of the mothership hangar; hull = last hull flown if affordable, else Fighter, else Scout; no modules, kits or gear until it shops later by the normal go-home rule | REQ-CHANGE: "pilots have to buy personal repair kits at the mothership" | `forward_respawns`, `_bay/_waypoint`, `shopless_respawns`, `kit_purchases` (all kit purchases, for kit purchases per death) | bay, normal 900 s (with bayA): 42 forward respawns; waypoint, `--late` 240 s: 2; no errors |
| A6 Kits and gear sold at bays | `bay_shop:on` | AI pilots hovering in a serving bay run their kit and gear wish list; a gear-only shopping trip goes to a bay that is 6,000+ closer than the mothership | REQ-CHANGE: same as A5 | `bay_purchases`, `bay_kit_purchases`, `bay_gear_purchases`, `bay_shop_trips` | normal 900 s (with bayA): 68 purchases (45 kits, 23 gear); `bay_shop_trips` was 0 (gear-only trips are rare); no errors |
| A7 Steeper late respawn curve | `respawn_curve:steep` | nothing needed | DESIGN (the research rejected it) | `steep_respawns` (waits over the old 50 s cap) | `--late` 120 s: 5; no errors |
| carry-over bayA | `bayA:on` | the AI admiral places repair bays at 0.22 of the lane instead of 0.33 | none | `bays_placed_back` | 6-7 bays placed in each run it was on; no errors |

## Checks

1. `run_checks.ps1` on the fork: `CHECKS ALL OK` (import, load_all, bot_pilot, support_probe, ui_pilot, ui_admiral).
2. `doc_check.ps1`: `TOTAL 192 files: headers 192/192, funcs 1108/1108 documented, members 1566/1566 noted`.
3. Determinism with every key at its default, seed 7, through the shared queue (`run_batch.ps1 -Test det_hash`): normal 900 s (181 hash lines) and `--late` 300 s (61 hash lines) are line-for-line IDENTICAL to int3 (normal reference: the int3 log `fun/logs/endgame_closure/smoke/d_int3_n_seed7.txt`; late reference: my own int3 run `fun/logs/pacing_downtime/det/int3_late_seed7.txt`). Final lines: `DET_HASH END t=900 230 units, 749aa6eb` and `DET_HASH END t=1800 226 units, 4bccf106` (late, counting from 25:00).
4. Smoke runs with the variant on: see the table; every usage counter is above zero (except `bay_shop_trips`, see below) and no SCRIPT ERROR in any log.

Note on process: my first short smoke runs (100-180 game seconds, tagged `dbg_*`) were started directly, before your rule change; everything after it (det_hash and the other smoke runs) went through `run_batch.ps1`. Logs: `fun/logs/pacing_downtime/{det,smoke}` and `dbg_*.txt`.

## Design decisions and deviations (please read)

- The brief says "today no AI pilot calls hyperspace_launch"; int3 already has an AI jump rule (`PilotAI._hyperspace_bay`, from the bfix=hyper). With `redeploy:on` that rule is REPLACED by `RedeployFeature.pick_site` (bays and turrets, 6,000-gain rule, safety check). With it off the int3 rule is untouched.
- The 4 s spool applies only through `redeploy` (`World.HYPERSPACE_SPOOL` is still 6). A human hangar jump to a bay also uses the 4 s spool and the 300-unit landing while `redeploy` is on; the hangar UI still lists bays only (the AI and `WorldHangar.hyperspace_launch` accept turrets).
- A1: AI pilots on a jungle job (state "jungle") never slip, because the AI brakes for jungle gates by a fraction of top speed and a doubled top speed would make it enter them too fast. A hit taken or dealt ends the slipstream within one tick; who slips is evaluated every 0.25 s. Slip needs: open space, within 1,600 of a lane line, 1,500+ behind that lane's front (own minions within 2,500 of the line, or own finished turrets of the lane's nodes + 1,500), quiet for 4 s, no visible enemy pilot within 2,500.
- A3: "thrust above 30%" is read as the main engine (forward) above 0.3; braking and strafing do not cancel. The human's key T is added in `install()`; the HUD bar only exists with a window.
- A5: only AI pilots are moved (a human keeps the hangar). For `waypoint` the ship appears 300 units inside the ring's edge on the mothership side. The site must be 3,000+ closer to the pilot's lane station than the mothership launch point; score = distance to the station minus half the distance to the nearest visible enemy pilot (capped at 5,000). Hull rule with a 120-credit reserve like `PilotShopping`.
- A6: "hovering" = inside the bay's module-swap circle (600). "Damaged" = `RepairBay.can_repair()` false (hull hit in the last 5 s). Hulls and modules are still bought only at the mothership. The human hangar's Kits and Gear tabs unlock inside a serving bay.
- `slipstream:probe` is an extra value (measurement only) so A1b's "big-ship arrival spread" has a baseline: mean = `big_arrival_s_sum / big_arrivals`, spread = sqrt(`big_arrival_s_sq / big_arrivals` - mean^2). `final_push_secs` and `siege_bite_rate` already exist in FUN_JSON.
- Not built: nothing from the brief was left out. Not verified: `bay_shop_trips` (the gear-only trip redirect) never fired in my runs; the code path is small but unproven. `recall` was exercised by the AI only; the human T key and the HUD bar were not clicked (headless; the code is straightforward).
- Risks to watch in the screens: A2 jumps count as "dead" in the fun probe (spooling pilots), so watch `dead_late`; A5 may collapse kit buying (`kit_purchases` per death); A1b can shorten the big-ship push window (watch `final_push_secs`, `siege_bite_rate`).

## Recommended screen commands

`$RUN = <SCRATCH>\run_batch.ps1`, `<fork>` = `<FC>\forks\pacing_downtime`. Brief order: A1, A2, A4, A3, A1b, A5, A6, A7 (then bayA and combos). Run each in the background:

```
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A1_on       -Tag A1_on       -Extra "--secs=3600","--skill-jitter","--variant=slipstream:on"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A2_on       -Tag A2_on       -Extra "--secs=3600","--skill-jitter","--variant=redeploy:on"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A4_size     -Tag A4_size     -Extra "--secs=3600","--skill-jitter","--variant=respawn:size"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A3_on       -Tag A3_on       -Extra "--secs=3600","--skill-jitter","--variant=recall:on"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A1b_flat    -Tag A1b_flat    -Extra "--secs=3600","--skill-jitter","--variant=slipstream:flat"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A1_probe    -Tag A1_probe    -Extra "--secs=3600","--skill-jitter","--variant=slipstream:probe"   # arrival-spread baseline for A1b
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A5_bay      -Tag A5_bay      -Extra "--secs=3600","--skill-jitter","--variant=respawn_site:bay"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A5_waypoint -Tag A5_waypoint -Extra "--secs=3600","--skill-jitter","--variant=respawn_site:waypoint"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A6_on       -Tag A6_on       -Extra "--secs=3600","--skill-jitter","--variant=bay_shop:on"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A7_steep    -Tag A7_steep    -Extra "--secs=3600","--skill-jitter","--variant=respawn_curve:steep"
# optional, last: A2 with surviving bays (only if baseline v2 lacks bayA), and a combination
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\A2_bayA     -Tag A2_bayA     -Extra "--secs=3600","--skill-jitter","--variant=redeploy:on,bayA:on"
& $RUN -Project <fork> -Seeds (101..106) -OutDir <logs>\combo_AB    -Tag combo_AB    -Extra "--secs=3600","--skill-jitter","--variant=slipstream:on,redeploy:on,recall:on,respawn:size,bayA:on"
```
Score each with `python tools/fun_score.py --dir <logs>\<tag> --vs <baseline v2 logs>`. Read the `usage` block in FUN_JSON first (usage near 0 = invalid, not negative). If A5 alone collapses kit buying, try `respawn_site:bay,bay_shop:on` together.

## Still queued (two background drivers, results land in fun/logs/pacing_downtime/smoke when a slot frees)

- `s_redeploy_seed7.txt`: normal 900 s, `redeploy:on` (shows hyperspace built early and jumps to bays in a normal match; the direct `--late` run already showed 17 jumps to turrets).
- `s_probe_seed7.txt`: `--late` 200 s, `slipstream:probe` (first check of the big-ship arrival counters).
- `s_all_seed7.txt`: `--late` 240 s, flat + redeploy + recall + size + respawn_site:bay + bay_shop + bayA + respawn_curve all on (interaction check; look for SCRIPT ERROR).
- `s_flat_late_seed7.txt`: `--late` 200 s, `slipstream:flat` (big ships exist from the start, so `big_arrivals` should be above 0).
Read the usage with `python -I fun/usage.py <log>`. If one of them shows a SCRIPT ERROR, the cause is in the interaction of two features; each feature alone ran clean.
