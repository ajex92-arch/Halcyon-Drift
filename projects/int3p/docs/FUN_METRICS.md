# Measuring fun (tests/fun_probe.gd)

We can't ask a simulation whether it had fun. We can measure the things that
players of games like this say make a match fun or miserable. `fun_probe`
watches a whole AI-vs-AI match and prints one line, `FUN_JSON {...}`, with
these numbers.

Run it (one match, seed 11, up to 60 minutes):

```
godot --headless --path remake --fixed-fps 60 -- --all-ai --seed=11 --test=fun_probe --secs=3600
```

Use several seeds (11-16 is the baseline set) and compare averages: one
match on its own is mostly luck.

## The numbers

| Key | What it means |
|---|---|
| `ended`, `winner`, `minutes` | Did a mothership die, who won, and when. |
| `time_share.dead` | Share of pilot time spent dead (waiting to respawn). |
| `time_share.docked` | Share spent docked at the mothership (shopping, repairing). |
| `time_share.engaged` | Share spent fighting: took or dealt damage in the last 4 s. |
| `time_share.near` | Share spent close to enemies (2,500) without fighting. |
| `time_share.travel` | Share spent flying with no enemy near. |
| `ship_deaths`, `deaths_by` | Pilot ships destroyed, sorted by what killed them (pilot, minion, turret, mothership, derelict, rock, ...). |
| `pilot_kill_share` | Share of ship deaths caused by enemy pilots. Players accept losing to another player more easily than to scenery. |
| `kills_per_min`, `deaths_per_pilot_per_10min` | How bloody the match is. |
| `avg_dead_secs_per_death` | Average wait per death. |
| `first_death_min`, `first_blood_min` | When the first ship died (anything) and the first pilot-on-pilot kill. |
| `fights`, `fights_per_10min`, `fight_time_share`, `fight_max_pilots` | Team fights: 3+ pilots on each side within 2,500 and someone hurt in the last 4 s. Samples less than 20 s apart are one fight. |
| `lead_changes`, `leader_at` | Who was ahead every 30 s by "worth" (credits earned + ore delivered, 5% dead zone), how often that flipped, and the leader at 10/15/20 min (+1 Halcyon, -1 Cinder, 0 even). |
| `comeback` | The winner was behind at 15:00. |
| `max_worth_ratio` | The biggest gap between the teams after 5:00 (2.0 = one team had twice the worth). |
| `ms_first_hull_hit_min` | When each mothership's hull first took damage (-1 = never). |
| `close_out_secs` | Seconds from the loser's first hull damage to its death. |
| `turrets_destroyed`, `monsters_killed` | Objectives taken. |
| `hull_variety` | How evenly the hulls were flown (0 = everyone in one hull, 1 = every hull equally). |
| `money_30`, `money_end` | Average unspent pilot credits and both treasuries at 30:00 and at the end. |
| `worth` | The worth samples, [time, Halcyon, Cinder] every 30 s. |

## Baseline (the game before the fun experiments)

Seeds 11-16, 60-minute cap:

| Seed | Ended | Engaged | Travel | Dead | Fights /10 min | Lead changes | Pilot kill share | Hull variety |
|---|---|---|---|---|---|---|---|---|
| 11 | 29:35 (Halcyon) | 0.41 | 0.38 | 0.06 | 4.4 | 1 | 0.52 | 0.73 |
| 12 | no | 0.35 | 0.36 | 0.11 | 3.5 | 2 | 0.46 | 0.84 |
| 13 | 52:11 (Cinder) | 0.36 | 0.38 | 0.10 | 3.6 | 1 | 0.58 | 0.85 |
| 14 | no | 0.37 | 0.37 | 0.13 | 4.2 | 1 | 0.54 | 0.84 |
| 15 | 47:38 (Halcyon) | 0.34 | 0.39 | 0.09 | 4.4 | 1 | 0.59 | 0.83 |
| 16 | no | 0.34 | 0.41 | 0.10 | 4.0 | 2 | 0.52 | 0.85 |

3 of 6 ended within 60 minutes. No comebacks in any of them.
