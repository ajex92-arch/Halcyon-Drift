STATUS: 12:30 Part 1 (--sim-only) done and quick-checked identical (150 s seed 7); Part 2 hot-spot work in progress; proof runs wait in the shared queue (all 3 slots held by other agents until ~12:30+).

# Performance findings (agent "perf")

Working copy: `scratchpad\notate\perf` (from `notate\int3`); untouched baseline copy: `scratchpad\perf_base`.
Tools I added in `scratchpad\deepdive`: `perf_cpumon.ps1` (records total CPU seconds of every Godot match process into `perf_runs\cpu_log.csv`), `perf_quick.ps1` (one direct short run with CPU time), `perf_patch_prof.py` (builds the profiling copy `notate\perf_prof`, not to be ported).
Test change (both trees): `tests/perf_probe.gd` got `--late` (starts at 25:00 like det_hash) and `--noprof` (profiling off, cleanest speed number).

## 1. Where the time goes (before any change)

Measured first minute of a normal match, seed 101, 24 pilots, ~110 units (quick direct runs, loaded PC, CPU seconds of the whole Godot process):

| run (65 game s) | process CPU | startup (map build) | CPU per sim-s |
|---|---|---|---|
| perf_base | 26.9 s | 3.4 s | 361 ms |
| perf --sim-only | 14.5 s | 3.3 s | 172 ms |

The "sim ms/sim-s" line printed by main.gd only times World._physics_process (181 ms of the 361). The other ~180 ms per sim-second were presentation that runs even without a window:
every unit's `Visual` node ran `_process` + `queue_redraw` + `_draw` every frame (UnitVisual / ShipVisual: polygons, bars, text), 3 CPUParticles2D flame emitters per pilot ship (72 emitters simulated every frame), the Projectiles node redrew every frame, Effects aged and redrew particles every frame, ResourceNode redrew every tick, FogView / CameraRig `_process`, and the sound cues / effects were built (Events.cue.emit with no listener, Effects.puff, Palette colours).

## 2. Part 1: --sim-only (see perf_diff.md for the exact code)

`Game.sim_only` (read once from `--sim-only` in `Game._parse_options`; `--sim-only=0|false` turns it off). With it:
- UnitVisual / ShipVisual: hide themselves, `set_process(false)`, no flame emitters.
- Effects: hidden, `set_process(false)`, `puff/spark/explosion/flak_burst/pulse` return at once (own RNG, so exact); `explosion` also skips its sound cue.
- Projectiles: hidden, no `_process`; `add_beam` keeps no lines (only ever drawn).
- AsteroidField chunks, MapDecor, FogView, ResourceNode: hidden / no redraw; CameraRig `set_process(false)`.
- Combat hit / shield_hit cues and WeaponMount shot cues are not emitted.
- WorldVisibility.refresh skips `apply_draw_visibility`; main.gd builds no HUD and no Sfx.

A LEAK that was found by det_hash (first version differed from t=20 s): Godot's `CPUParticles2D` takes one number from the GLOBAL random sequence (the same one `randf()` uses for AI and guns) when it is created. Skipping the three flame emitters shifted every later dice roll. Fix: in sim-only mode `ShipVisual._ready` draws three numbers (`randi()` x3) in the same place. (Verified in a scratch project: 3 emitters = exactly 3 `randi()` steps; adding to the tree / emitting costs none.) After the fix det_hash seed 7, 150 s: 31/31 hash lines identical to perf_base.

## 3. Part 2: hot spots

(profile numbers and changes are appended below as they are done)
