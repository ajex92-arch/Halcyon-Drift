# User test fork: the plan for your 11 changes

Written Sat 2026-10-17 by the lead for your review. It covers the branch `local/user-test-fork` (68f477d, which is v0.1.0). **Nothing here is built yet.** Work starts only when you say go, and it goes one stage at a time.

## Your changes (verbatim, numbered)

1. "The map should be 20% taller (vertical length)"
2. "Remake the game to a 6v6 match, 5 player in the field and 1 admiral who can take the field if he wants."
3. "The non admiral players should be able to spend credits to purchase wingmen, beginning with 1 and increasing to 3 with admiral research."
4. "Scouts should be free as wingmen, with fighters, bombers, and Lance fighters buyable with credits."
5. "These wingman should be able to be commanded with simple commands by the player and ordered into simple formations by the player."
6. "the width of the top and bottom lanes should shrunk by 50% and the width of the middle lane increased by 50%"
7. "the perpendicular lane should be removed and replaced with more jungle"
8. "the resource points should be moved into the now larger jungle and out of the lanes."
9. "Resource points total, 4 in a line along the middle of the map (2 in the top jungle 2 in the bottom jungle), 2 in a line on the left side of the map (one in the top jungle one in the bottom), 2 in a line on the right side of the map (one in the top jungle one in the bottom). Rework resource nodes to give less resources each to stop economic inflation."
10. "Slow small craft movment speeds by about 20%."
11. "Minions should be very bad pilots. Ai players should be as good as the average human pilot, and wingman should be in between."

These override parts of `USER_REQUIREMENTS_2026-10-13.md`, such as 13v13, the lane layout and the Crossing, **in this fork only**. The requirements file itself stays as you wrote it.

## What the code does today (what each change touches)

| Area | Today | Where |
|---|---|---|
| Map size | 40,000 x 26,000. Aurelian's half is authored and mirrored for Cinder. | `MapLayout.W / H` |
| Lanes | Three corridors, each 3,600 wide: top at y 3,800, mid at y 13,000 (small bend near the centre), bottom at y 22,200 | `MapLayout.LANES` |
| The Crossing | A 3,200-wide lane down the centre line (x 20,000) from the top lane to the bottom lane. It has 2 jungle entrances on each side, and 3 ore nodes on it. | `MapLayout.CONNECTOR`, `ENTRANCES`, `NODES` |
| Ore nodes | 9: 3 "inner" per team beside the lanes, 3 "middle" on the Crossing. Each has 5 rocks x 1,600 ore x its value, regrowing 6 ore/s x value. Each also has 1-3 turret slots. **The admiral's turrets stand on node slots, so today's lane turrets are the node turrets.** | `MapLayout.NODES`, `ResourceNode` |
| Jungle | 12 monster camps (6 per side) and entrances with 86-wide chokes (strike craft only). **Monsters attack mining drones** (they skip only repair drones and wards). | `MapLayout.CAMPS`, `MapBuilderJungle`, `Derelict` |
| Teams | 12 pilots + 1 admiral per side. A human admiral already has a spare pilot profile and can launch a ship. The AI admiral never flies. | `Rules.PILOTS_PER_TEAM`, `WorldSetup` |
| Small craft | Size class 0. Top speeds: Scout 720, Fighter 640, Lance 600, Bomber 400. Minion fighters 480 and bombers 380, snub fighters 520, mining drones 460. Fighter Drive 1 and 2 research add +8% each. | `ships.gd`, `minions.gd`, `jungle.gd`, `structures.gd` |
| AI skill | AI pilots: one skill per seat, 0.5-0.95. It sets how often they think (every 0.23-0.35 s), aim error up to (1 - skill) x 0.12 rad, energy routing above 0.55 and shield focus above 0.6. Minions: only a fixed aim error (0.015-0.035 rad by type). | `PilotAI`, `PilotCombat`, `PilotSystems`, `minions.gd` |
| Wingmen | Nothing exists yet. Pieces to reuse: Ship and the AI pilot parts (flight, aim, targets, rocks), the Logistics corvette's escort drones (they already follow a ship), Fleet Command's minion orders, and the hangar shop. | |

## Your decisions (Sat 2026-10-17, ~11:35, verbatim)

1. **Turrets:** "Lane turrets stay and follow the nodes, with the nodes in the jungle only ever having one PD turret slot".
   - All of today's lane turret sites stay in the lanes. There are 9: the 3 inner sites per team plus the 3 centre sites on the lanes, refitted to the new lane widths. They keep their slot rules: torpedo turrets only at a team's own inner sites.
   - Each of the 8 jungle nodes gets exactly ONE point-defense slot.
2. **Admiral:** "Human and AI".
   - A human admiral launches from the board and keeps the Admiral board (Tab) while flying.
   - The AI admiral flies only to defend the mothership, or when 2 or more of its pilots are down, and then returns.
3. **Wingmen:** "Lost on death, rebuy. But keep in mind the cost of the wingman so players can actually have enough money to buy them while still buying their own upgrades. Though there should be some tradeoff between self improvement and having many good wingmen".
   - A destroyed wingman is gone. Scouts are free, so the slot can always be refilled.
   - When the pilot dies, the wingmen fly home and relaunch with the pilot.
   - Prices are a tuning target (stage 4 and stage 5): see the price targets in stage 4.
4. **Compute:** "Both. PC and the Cloud".
   - The cloud runs the 12- and 40-match measurements. Its copy of the fork's code goes onto the public `cloud-runs` branch, scrubbed and checked by the push guard.
   - This PC runs the quick checks, the duel ladder, performance on your own hardware (including the 60 fps window check) and your playtests.
   - Cloud (Linux) and PC (Windows) runs never get compared with each other. Each comparison stays on one platform.

Smaller defaults that I will use unless you say otherwise:
- "Small craft" means the strike craft: Scout, Fighter, Lance and Bomber (and so the wingmen), minion fighters and bombers, and snub fighters. Mining and repair drones keep their speed.
- 5 field seats per team: top 1, mid 2, bottom 1, jungle 1. This will be measured.
- Wing Command 1 and 2 research in the admiral's Fighter column raises the wingman cap from 1 to 2 and 3.
- Wingman commands: Follow, Attack my target, Defend me, Hold here, Regroup. Formations: Line abreast, Wedge (V), Column, Loose escort. Keys are picked from free ones and shown in the help panel and the key reminder.

## How every stage is built and checked

- **One stage at a time.** Each stage gets its own branch (`local/utf-<stage>`) and is merged into `local/user-test-fork` only after its gates pass. Every change is a commit, and each finished stage gets a local tag `utf/stage-<n>`. Nothing is pushed.
- **Tests run on a fresh export of the stage's commit**, never on the fork folder you open in Godot.
- **The gates for every stage:**
  1. run_checks is ALL OK (load_all, bot_pilot, support_probe and the HUD tours), with the checks updated where the stage changes the screens.
  2. The stage's own pass/fail test (listed with each stage below).
  3. **The AI stays decent**, measured on 12 full matches with pilot_audit and admiral_audit:
     - stuck episodes, rock contacts, shots into rocks and crash deaths;
     - admiral decisions per minute (band 0.5-3), drone losses and idle drones.
     - None may be worse than the stage before by more than 10% unless the change explains it, and then I tell you.
  4. **Match health:** the share of matches that end, the median length, and the side split. The map stays mirrored, so the split should be 50/50 ± 10. No script errors.
  5. **Performance**, measured with perf_probe in a busy late game, worst case:
     - the mean computer time per game second must stay within v0.1.0 + 15%;
     - the worst single tick must stay at or below 33 ms (two frames at 60 fps);
     - plus a 60 fps check in a window, in a big late fight.
  6. **The fun meter** (fun_probe), for information: FUN and its 11 ingredients against the stage before. Any ingredient that falls by more than 15 points is reported to you, never hidden.
- **Every stage ends with a short report to you.** After stages 2, 4 and 6 I offer you a playtest build or a video pack, so you can judge the feel before I go on.

## The stages (in order; each one builds on the one before)

### Stage 0: yardsticks and new test tools (no game change)

- **The v0.1.0 yardstick on this PC:** 12 full matches with fun_probe and both audits, plus perf_probe.
- **New `map_check` test**, which checks:
  - the map size and the lane widths;
  - that the chokes still stop big ships;
  - that strike craft can reach every camp and every node;
  - that every node has a drone route home that stays clear of the camps;
  - that no node overlaps a rock, and that the mirror is exact.
- **A worst-case test switch:** every seat filled (later, with every wingman bought) for the performance runs.
- **A report script** that puts two runs side by side.
- **A stats recorder for your own matches** (only with your OK, local only). It writes your hit rate, damage per minute, deaths and kills to a file, for the skill calibration in stage 3.

### Stage 1: 6v6 and the admiral who can take the field (change 2)

- `PILOTS_PER_TEAM` 12 -> 5, with the seat roles for 5.
- **An audit of every number that assumes 12 pilots:**
  - respawn strain (4 respawns in 30 s, probably 2 for a team of 5);
  - defend calls and siege strength;
  - bounties, assists and the respawn stipend;
  - the pilots' 40% of the ore. Split 5 ways it is 2.4x more per pilot; stage 5 rebalances it.
  - minion waves (10 ships per lane every 35 s) against 5 defenders;
  - wards;
  - the scoreboard and admiral-board pilot lists, the callsign roster, and the tests' per-pilot numbers.
- **The admiral in the field (your decision 2):**
  - The human part mostly exists already: a human admiral has a spare pilot profile and can launch.
  - New: the AI admiral flies a ship (with an AI pilot brain) to defend the mothership, or when 2 or more of its pilots are down. It keeps its once-a-second admiral thinking going while it flies, and returns to the bridge when the trigger ends.
- **Test:** 5 + 1 seats per side with the human in either seat; the admiral launches and docks both ways; the AI admiral's field trips are logged.

### Stage 2: the new map (changes 1, 6, 7, 8 and the node layout of 9)

- **Size and lanes:**
  - the height goes 26,000 -> 31,200, and the lanes are laid out again (the motherships sit on the new centre line, y 15,600);
  - top and bottom lanes become 1,800 wide, the mid lane 5,400 wide.
- **The Crossing is removed:**
  - its entrances and its 3 nodes go;
  - the top-left and top-right jungles join into one top jungle (the bottom likewise);
  - the jungle generator gets paths, camps and rocks across the centre line.
- **8 ore nodes, all in the jungle:**
  - 4 on the centre line (x 20,000): two in the top jungle, two in the bottom. They sit on the mirror line, so each is made once.
  - 2 on the left (about x 11,000; one top, one bottom). These are Aurelian's "inner" nodes.
  - 2 on the right (mirrored). These are Cinder's.
  - Nodes and camps are kept far enough apart that drone routes do not pass through a camp's attack range.
- **Turrets (your decision 1):**
  - the 9 lane turret sites stay, moved to fit the narrower side lanes and the wider mid lane;
  - each jungle node has exactly one PD slot.
  - This means a turret site is no longer the same thing as an ore node. The admiral board's Build tab, the AI admiral's builder and the turret rules are changed to match.
- **Every hard-coded map position outside MapLayout** (labels, tests, decor) is found and moved.
- **Tests:**
  - map_check all green, and a full-map screenshot;
  - every node and camp reachable, big ships stopped at the chokes;
  - pilot_audit stuck and rock numbers on the narrow side lanes;
  - minion waves still reach the end of every lane;
  - drone losses. If monsters still eat drones, the fix is your call: move camps, or make monsters ignore mining drones.

### Stage 3: speed and skill (changes 10 and 11)

- **Small craft -20%:** top speed and acceleration, as defined above. Fighter Drive stays +8% each.
- **A skill ladder, measured in duels** (arena_matrix, same hull where possible). Target: an AI pilot beats a wingman in about 70-80% of 1v1s, and a wingman beats a minion fighter in about 70-80%.
- **Minions become very bad pilots:**
  - much larger aim error and poor or no lead;
  - slow target switches;
  - little dodging.
- **AI pilots = an average human:**
  - calibrated to your own numbers from 2-3 matches with the stats recorder;
  - without those numbers, to a fixed estimate that you judge by feel;
  - the per-seat spread narrows around that level.
- **The wingman skill:** a fixed level between the two, used in stage 4.
- **Tests:**
  - the duel ladder numbers;
  - match pacing: longer side lanes plus slower ships mean longer travel, so the wave timing and respawn waits are re-checked.

### Stage 4: wingmen (changes 3, 4 and 5)

- **Shop:**
  - a Wing tab in the hangar (B);
  - Scout free; Fighter, Lance and Bomber for credits;
  - Lance and Bomber need the same research as the hulls;
  - wingmen can be sold back;
  - a destroyed wingman is gone and must be rebought (your decision 3).
- **Price targets (your decision 3):** players must be able to afford wingmen and still buy their own upgrades, with a real trade-off between the two. This is measured on the AI pilots and on your stats:
  - by about 10:00 a typical pilot can fly their own Fighter and keep 1 paid wingman;
  - around 20:00 a pilot can afford a big upgrade (corvette or frigate) **or** a full wing of good wingmen, but not both at once;
  - over a match, roughly a third to a half of a pilot's spending goes on wingmen, counting rebuys after losses;
  - starting prices are the hull prices (Fighter 150, Lance 300, Bomber 350), then tuned up or down in stage 5 together with the ore yields.
- **Cap:** 1 wingman, raised to 2 and 3 by Wing Command 1 and 2. The AI admiral researches them at a set point in its plan.
- **Commands and formations:**
  - formation slots are set relative to the leader's heading;
  - wingmen match the leader's speed;
  - they keep the formation in lanes and switch to a tight column in the jungle.
- **Wingman brain:** a light WingmanAI. It reuses the AI pilot's flight, aim and rock-dodging parts at the wingman skill level, but thinks only about its leader and its order. It is built to stay cheap with up to 30 wingmen on the map.
- **AI pilots use wingmen too:**
  - they take free scouts at once and buy better hulls when they can afford them, by role;
  - their usual order is Follow + Attack, switching to Defend me while retreating.
- **A small bounty for killing a wingman** (like a minion's), so wingmen do not feed the enemy's economy.
- **Tests:**
  - **wing_probe, pass/fail:**
    - buy and sell, the cap by research, the prices;
    - every command;
    - every formation settles within a few seconds and holds while flying a lane and the jungle;
    - no wingman gets stuck in rocks or blocks its leader.
  - **Performance worst case:** every pilot with 3 wingmen.

### Stage 5: the economy (change 9: smaller yields)

- **Less ore per node, so the economy stops inflating.** Measured at 10, 20 and 30 minutes:
  - the treasury and the pilot credits left unspent;
  - research timing;
  - the share of pilots in capital ships late in the match.
- **What changed since v0.1.0 and feeds into it:**
  - 8 nodes instead of 9;
  - drones flying through the jungle;
  - the pilots' ore share split 5 ways;
  - wingmen as a new place to spend.
- **Tuning:** node value, ore per rock and regrowth. Two or three settings, 12 matches each.

### Stage 6: putting it together, and your sign-off

- **40 full matches on the final build:** every gate, the fun meter against v0.1.0, the performance worst case and AI health.
- **Your feel check:** a Windows playtest build of the fork (local only) and a video pack, then a last tuning round from your notes.
- **Docs in the fork:**
  - a "User test fork" section in DESIGN.md: each change and what it overrides;
  - PROGRESS.md entries and the API index.

## Compute and cost

- **Both, as you chose:**
  - The cloud does the 12- and 40-match measurements, about 30 minutes each. The fork's code goes onto the public `cloud-runs` branch, scrubbed of personal details and checked by the push guard.
  - This PC does the quick checks, the duel ladder, performance on your hardware and your playtests. Fork runs here go ahead of the weekend queue's filler work.
- **Agent work:** Sonnet builds each stage, Opus reviews it, Sonnet measures it.
  - About 45 points of 5-hour windows in all (about 6-7 weekly points), spread over several sessions.
  - Big launches happen only in your online hours.
  - By stage: 0 about 4, 1 about 6, 2 about 8, 3 about 5, 4 about 13, 5 about 4, 6 about 5.
- **Calendar time:** with the cloud doing the measurements, about 1-2 days of work spread over your online hours. The stage reviews and your feel checks set the pace more than the computers do.

## Risks I will watch

- **Lanes without turrets** (if the turrets follow the nodes into the jungle): minion waves would run straight to the motherships, so matches could end too fast or stall at the hull.
- **Monsters eating mining drones** at the jungle nodes.
- **Crowding on the 1,800-wide side lanes:** 10-minion waves, collisions, stuck ships.
- **Performance with up to 30 wingmen**, plus clutter on screen.
- **Longer, slower matches:** a taller map and slower ships.
- **Hidden team-size assumptions** in tuning numbers.
- **Calibrating "average human" without human data.**
