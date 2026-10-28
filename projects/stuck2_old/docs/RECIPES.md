# Recipes: where each common change lives

A one-page map for builders: find your change, edit the files in its entry, run the checks it names. Read it with
docs/PITFALLS.md. Paths are under `remake/`. A small change (a number, a name, a text) needs LOAD, plus one quick AI
match (`match_probe --secs=720`) if play changes; a bigger one needs everything its entry lists. Heavy checks
(reviewer models, dozens of AI matches) wait until a change heads for a release.

## The checks

- **LOAD**: commit, export the commit with `vc_export` (it imports, and fails on a script error), run `run_checks`
  on the export (`CHECKS ALL OK`), then `script_error_scan -Recurse` over your logs (`SCRIPT ERRORS: 0`). Run
  Godot only on exports of committed work.
- **DOCS**: `doc_check` clean for each `.gd` you touched; `python tools/api_index.py` when a public function or
  signal changed (commit `docs/API_INDEX.md` if it changes); a `PROGRESS.md` entry; and any number, rule or word
  that `DESIGN.md`, `CODE_GUIDE.md` (glossary), the README or the in-game help state and your change made untrue.
- **SAME**: the match must not change: `det_check -Full` against the baselines your brief names says IDENTICAL for
  normal and late (pictures, UI, colours, camera, sound). A change only in `tests/` or tools cannot change a
  match, so there the commit says so instead.
- **CHANGED**: the match changes on purpose: two `det_check -Full` runs identical to each other, the first
  differing line named, and the entry's probes. The lead decides the new baselines.

## The recipes

### A number, a name or a text
- **Lives in**: the tables in `scripts/data/` (`ships`, `weapons`, `items`, `modules`, `tech`, `minions`,
  `turret_data`, `structures`, `jungle`, `rules`; each header lists its fields).
- **Checks**: LOAD, DOCS (the number in `DESIGN.md`), the quick match; CHANGED if it moves play. One number per round.

### A hull (DESIGN.md A5)
- **Lives in**: `scripts/data/ships.gd` (a `HULLS` entry and its id in `ORDER`); its plain outline in `ShipVisual.HULLS`; Aurelian's steel drawing in `AurelianShapes.HULLS` (named pieces, each with its attach point; without one Aurelian draws the fighter);
  Vhorr's alien shape in `CinderShapes.HULLS` (without one Vhorr draws the fighter); its `unlock` (`""`,
  `fac:<facility>`, or a research id whose item in `tech.gd` has `"effect": {"unlock_ship": "<id>"}`); the AI's
  wish lists `PilotShopping.HULL_PREF` and `MOD_PREF` (a hull on no list is never bought); a new special in
  `ShipAbilities.use_special()` (called from `Ship._use_special()`).
- **Checks**: LOAD; `hull_gallery --check` and a gallery picture of both teams; an `arena` duel against a similar
  hull; `pilot_audit`; CHANGED if the AI buys it, else SAME.

### A weapon
- **Lives in**: an entry in `Weapons.WEAPONS` (`scripts/data/weapons.gd`; `kind` picks behaviour only). Give it
  to something: a hull's `mounts` in `ships.gd`, a minion's `weapons` in `minions.gd`, or `turret_data.gd`,
  `structures.gd`, `jungle.gd`. A new `kind` is a code change, not a recipe (`Rules.W_*`, `KIND_IDS`, and the code
  that reads kinds, such as `WeaponMount`, `Projectiles*`, `DamageInfo`). A gun that swings (a turret or an
  auto mount) is drawn as a turret: its silhouette comes from its weapon id in `TurretShapes.CLASS_BY_WEAPON` (else
  from its kind in `CLASS_BY_KIND`).
- **Checks**: LOAD; an `arena` duel with and without it (`--a=... --b=...`); `pilot_audit` or `fun_probe` for
  balance; a gallery picture if it draws new rounds; CHANGED.

### A wave
- **Lives in**: `Minions.OUTER_WAVE`, `MID_WAVE` and `WAVES` (`scripts/data/minions.gd`; list order is launch
  order; `FIRST_WAVE` and `WAVE_INTERVAL` set the timing); a type's numbers and name are in `Minions.TYPES`.
  Do not edit `MinionDirector` for a mix change. A fourth minion type is not a recipe: the ids `fighter`, `bomber`
  and `corvette` are used by name in the drawing, the Fleet Command board and `AdmiralFleetCommand.FLEET_MIX`.
- **Checks**: LOAD; `lane_probe`; `wave_shots` pictures; `opening_fix_check` with seeds 301 and 302 (the AI
  opening waits for the first wave); CHANGED.
- **DOCS**: the wave sizes quoted in the `CODE_GUIDE.md` glossary ("minion / wave") and in `DESIGN.md`.

### A difficulty level, or a new kind of income (DESIGN.md A7)
- **Lives in**: the levels and their enemy-income multipliers are the named constants and tables of
  `scripts/data/difficulty.gd` (`ORDER`, `INCOME`, `LABELS`); the start screen's buttons follow `ORDER`. Money goes in
  through three gates that apply the team's multiplier: `PilotProfile.earn()` (a payment with a message),
  `PilotProfile.earn_quietly()` (no message) and `TeamState.earn()` (a treasury). A new kind of income must use one of
  them, never `credits +=` or `treasury +=`, or the difficulty will not scale it; money given back (sales, trade-ins,
  refunds, insurance) is not income and adds to `credits` or `treasury` directly.
- **Checks**: LOAD; `difficulty_check` for every level with a human seat (`--role=pilot`, `--role=admiral`) and with
  `--all-ai`; `difficulty_probe` (one human seat, source by source); SAME: all-AI runs and Medium must stay IDENTICAL to
  the baselines (the multiplier is exactly 1.0 there); CHANGED for the human-seat match at any other level.
- **DOCS**: the `DESIGN.md` A7 paragraph, the CODE_GUIDE glossary ("difficulty"), the README and `FORK_MANIFEST.md`.

### A research item (DESIGN.md A13)
- **Lives in**: a `Tech.TECHS` entry in `scripts/data/tech.gd` (its `column` is one of `COLUMNS`) and its id in
  `Tech.ORDER`. An existing `effect` key is applied by `TeamTech.apply_effect()`; a new key needs a case there
  and a field on `TeamState`. The AI buys it only if it is in `AdmiralPlan.PLAN`. The board draws it by itself.
- **Checks**: LOAD (its admiral tour draws the board); `admiral_audit`; CHANGED.

### A HUD panel
- **Lives in**: a small widget is `scenes/ui/hud_<name>.tscn` plus `scripts/ui/hud_<name>.gd`, instanced in
  `scenes/ui/hud.tscn` (anchors place it; later children draw on top) and refreshed from `Hud._refresh()`;
  `HudLayout` keeps it clear of its neighbours. A big panel is made by `HudPanels` and opened by a key in
  `HudInput`. Looks come from `UiKit` (a box look in `PANEL_LOOKS`, or a theme variation), colours from `Palette`,
  never from the scene. A scrolling menu sets `mouse_force_pass_scroll_events = false` on its root (PITFALLS).
- **Checks**: LOAD (it includes both tours and both wheel checks); `display_check`; `tools/ui_layout_check.py` on
  `ui_tour --dump-layout --ui-size=WxH` at several sizes (1280x720, 1366x657, 1920x1080); 3 to 6 windowed
  `ui_tour` screenshots; SAME.
- **DOCS**: the HUD paragraphs of `CODE_GUIDE.md`; the help pages and the README controls table if keys change.

### A test
- **Lives in**: a new `tests/<name>.gd` (`extends Node`, `func setup(w: World)`; helpers in `tests/lib/`), run
  with `--test=<name>`. Copy the header shape of `tests/load_all.gd`. Print `<name>: N failures` for a check or
  one JSON line for a probe, quit when done, read the game and never change it. A windowed test needs the
  off-screen flags and the screenshot rules (PITFALLS). A new option goes in the list at the top of
  `scripts/autoload/game.gd`.
- **Checks**: LOAD (`load_all` parses every file under `tests/`); run your test once on the export and scan its
  log; no det run (a change only in `tests/` cannot change a match: say so in the commit). Adding it to
  `run_checks` is the lead's call.
- **DOCS**: the README Tests block and the tests paragraph of `CODE_GUIDE.md`.

### A palette colour
- **Lives in**: a `const NAME := Color(...)` with a `##` note in `scripts/data/palette.gd`, used as
  `Palette.NAME`. Scenes never hold colours: `UiKit` builds the named looks from `Palette` (a new box look goes
  in `UiKit.PANEL_LOOKS`).
- **Checks**: LOAD; a few windowed `ui_tour` screenshots (a `hull_gallery` picture for a ship colour); SAME.

## Files you never touch

- **The checkers and baselines**: `run_checks`, `det_check`, `doc_check`, `vc_export`, `run_batch`, `session_tools/`
  and the determinism baselines are the lead's (if one is wrong, say so in your hand-back). `tests/det_hash.gd`
  is the fingerprint itself: change what it hashes and every baseline is useless.
- **What makes a match repeat**: the tick order in `World._physics_process`, the map builder's step order and
  seeds (`MapBuilder`, `Mulberry`, `MapLayout.SEED`), and the order of `randf()` and `randi()` calls.
- **Names other tools read**: the hull and minion ids, `Rules.TEAM_NAMES` (Halcyon, Cinder), the lines
  `MainReport` prints, a script that a scene points at (do not move or rename it) and a `class_name` that
  another file uses.
- **What tools write**: `docs/API_INDEX.md` (run `tools/api_index.py`), the `.uid` and `.import` files (Godot
  writes them; commit them, never edit them) and the `.godot` folder.
- **Records**: `docs/USER_REQUIREMENTS_2026-10-13.md`, `docs/prompt1_original_brief.txt`,
  `docs/prompt2_amendments.txt`, `docs/fork_manifests/`, `fun_plan/`, `deep_dive/` and `release_notes/`.
- **Release and build files**: `.github/`, `export_presets.cfg`, the root `README.md` and
  `docs/RELEASE_NOTES.md` (the lead writes them at release).
- **Only when your brief names them**: `project.godot` (autoloads, stretch and window settings) and
  `FORK_MANIFEST.md` (update it when you add or change a variant key).
- **Not yours to write in**: the user's own play folders and the repo clone's own checkout (your brief names
  them); never write there and never run Godot there.

Every change: one commit, its subject starting with the item ID; match the surrounding code (tabs, typed GDScript,
the WHAT THIS IS / HOW IT WORKS / WHO USES IT blocks of `docs/CODE_STYLE.md`); a new script gets a unique
PascalCase `class_name` and its `.uid` file in the same commit.
