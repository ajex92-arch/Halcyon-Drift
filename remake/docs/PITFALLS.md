# Pitfalls: engine and tooling quirks we have hit

One entry per quirk: what you see, then what to do. Read this with docs/RECIPES.md before you change code or
run a check. When you meet a new quirk, add an entry in the commit that fixes or works around it. Keep the
entries plain and short. Dates, ticket IDs and who said what belong in PROGRESS.md, not here.

## Start here: the seven that bite first

- **The class cache and the import gate (invisible ships).** Symptom: a copy of the game with no `.godot`
  folder, or one older than its scripts, draws no ships (or does not start) and prints
  `Identifier "CinderPaint" not declared` and `Failed to load script`, yet `load_all` can say `0 failures`.
  Fix: import once before the first launch of any new or merged copy
  (`godot --headless --path remake --import`, about 15 s; `vc_export` and `try.ps1` do it for you), then scan the
  logs for script errors.
- **Windows clamps windows to the work area** (the screen less the taskbar). Symptom: a window asked to be as
  big as the monitor comes out smaller: on a 1080p monitor 1920x1080 opened at 1920x1061 and 2560x1080 at
  1924x1061; the game's own minimum also lifts small requests (1024x600 opens at 1280x720). Fix: report the size
  you measured (the picture's own size, or what `display_check` prints), never the size you asked for; test
  sizes the screen cannot show with the headless layout dump (`ui_tour --dump-layout --ui-size=WxH`), which
  needs no window.
- **`conhost --headless` leaves its children alive.** Symptom: a scheduled task started as
  `conhost.exe --headless powershell.exe ...` (so no window shows) is marked stopped when its time limit
  passes, but the PowerShell it started, and whatever that started, keep running until they end by themselves;
  conhost's own exit code is 0 whatever the child did. Fix: give the script its own deadline under the task's
  limit, stop any older copy of the script with its whole process tree (`taskkill /PID <id> /T /F`) before it
  takes its lock, and test for `--headless` support with a marker file, never with the exit code.
- **Freed instances in test scripts.** Symptom: a test stops with
  `Trying to assign invalid previously freed instance` because a loop reached a unit that was freed in the same
  frame; the spatial hashes (`World.unit_hash.query()`, `big_hash`) can still return one. Fix: loop with an
  untyped variable, test `is_instance_valid(obj)`, and only then assign it to a typed variable and read
  `.alive` (see `_busiest()` in `tests/spectate_shots.gd`). The typed loops in `tests/crossing_probe.gd`,
  `tests/pilot_audit.gd` and `tests/lib/fun_probe_time.gd` still lack the guard: do not copy them.
- **`frame_post_draw` timing for screenshots.** Symptom: a picture saved right after you move the camera or
  open a panel shows the previous frame, not yours. Fix: `await RenderingServer.frame_post_draw` first, then
  `get_viewport().get_texture().get_image().save_png(path)`. A headless run draws nothing, so return early when
  `DisplayServer.get_name() == "headless"`. Examples: `_shot()` in `tests/ui_tour.gd`, `tests/spectate_shots.gd`.
- **8.3 paths.** Symptom: Windows also knows a folder by a short name (`Program Files` is `PROGRA~1`), and a
  temp folder is often handed to a script in that form, so one folder has two spellings and a prefix test, a
  "does another Godot have this folder open?" search or a path compare says no. Fix: turn both sides into the
  long form (`[System.IO.Path]::GetFullPath`, then `GetLongPathName`, as `vc_export` does), lower-case them and
  drop the trailing slash before comparing. Never put a full local path, short or long, in a committed file: it
  carries a user name, and the privacy guards look for it.

## More about Godot, the tests and the checks

- **`godot --import` does not compile.** Symptom: it repairs the class cache but stays silent (exit code 0)
  about a script with a syntax error. Fix: the compile check is `load_all`; run it (`run_checks` does) after
  every import.
- **Script errors hide in the error output.** Symptom: `SCRIPT ERROR`, `Parse Error` and
  `Failed to load script` lines go to stderr, which a look at stdout misses. Fix: scan both with
  `script_error_scan -Recurse` (it must end `SCRIPT ERRORS: 0`) before you trust a number or a picture,
  windowed runs outside the queue included. `ERROR: N resources still in use at exit` and
  `WARNING: N ObjectDB instances leaked` end every run: harmless.
- **An exported game is not the project folder: converted scenes lose anchors.** Symptom: every check passes on
  the project folder, yet the exported game (the browser build, and the Windows preset's game data, which the exe
  carries) piles the HUD into the top-left corner: the controls hint, the "me" panel, the gear slots, the pop-up
  hint and the big message sit on top of one another and the top bar is at the left edge instead of the centre;
  the minimap and the ship readout keep their anchors. Cause: the export turns text scenes (`.tscn`) into binary ones, and the binary `hud.scn` stores
  `layout_mode = 0` (and mostly `anchors_preset = 0`, top left) on every instanced scene that `hud.tscn` does not
  give properties of its own, so loading it resets the anchors and offsets that the instanced scene's root sets.
  Fix: `editor/export/convert_text_resources_to_binary` is off in `project.godot`, so the export keeps the text
  scenes the checks run on. Check an export, not only the project folder: `ui_tour --dump-layout` on the exported
  data (`godot --headless --main-pack <index.pck> -- ... --test=ui_tour --dump-layout`; the web export of the
  `Web` preset leaves `tests/` out, so keep it in a copy of the preset) into `tools/ui_layout_check.py`, in a
  browser for the web build. The tour must end with `ui_tour: done`: the checker reads a timed-out tour's partial
  dump as clean.
- **Two Godot runs on one fresh folder race the first import.** Symptom: both fail to parse the scripts and
  hang until their timeout. Fix: import the folder once first (`vc_export` does); never start two runs on a
  folder that has no `.godot`.
- **New scripts need their `.uid` files committed.** Symptom: Godot writes `<name>.gd.uid` next to every
  script (and `.import` files) when it imports; if a commit lacks one, the first import of its export changes
  the files, the export no longer matches its stamp and `vc_export` fails. Fix: copy the `.uid` files that the
  import of an export wrote into your worktree and commit them with the script. `.gitattributes` keeps
  `*.import` files on LF endings, because the clone's `core.autocrlf` would give an export CRLF and the import
  would then change them.
- **An edited export is refused.** Symptom: changing a file inside an export (even a tool that writes into it)
  makes its stamp fail, and `run_batch` refuses the folder. Fix: change code only by committing, then export
  again.
- **The mouse wheel passes through menus.** Symptom: `Control.mouse_force_pass_scroll_events` is on by default,
  so a turn past the end of a menu's list, or over its frame, reaches the camera and zooms the map behind it.
  Fix: set the property to false on the root of every scrolling menu (the Admiral board, hangar, help,
  scoreboard and end screen do) and run `wheel_check`.
- **A fresh window reports the mouse at (0, 0).** Symptom: the free camera's edge panning drifts toward the
  top-left corner of the map, so a screenshot tour looks at nothing. Fix: switch the camera's own work off
  (`world.camera.set_process(false)`) and place it by hand until the picture is saved
  (see `tests/spectate_shots.gd`).
- **Frames are not seconds in a windowed run.** Symptom: without `--fixed-fps` a window runs at its own pace
  (about 11 fps at `--speed=4`), so "wait 20 frames" can mean 6 or 7 match seconds and the fight you meant to
  photograph is over. Fix: wait on match time, or freeze the match (`world.set_physics_process(false)`) while
  the pictures are taken, as `hull_gallery` does.
- **A particle node uses a random number.** Symptom: making a `CPUParticles2D` takes one number from the game's
  shared random sequence, so drawing code can change the whole match (in `--sim-only` runs `ShipVisual` takes
  the same numbers itself). Fix: give every new visual that makes particles, or calls `randf()`, the same
  treatment or its own generator, as `Effects` has, and prove it with `det_check -Full`.
- **Objects that point at each other are never freed.** Symptom: GDScript frees `RefCounted` objects by
  counting links, so two that hold each other strongly live forever (a memory leak). Fix: a part keeps its
  owner through `weakref` (see `PilotGoals._ai_ref`) and the owner holds the part normally.
- **`--sim-only` skips all drawing.** Symptom: the queue adds it to windowless runs, so a plain `det_check`
  never runs a picture, flame, sound, HUD or camera change. Fix: for drawing, UI, camera or sound work pass
  `-Full` (`--sim-only=0`); and give the baselines of the build you compare with (`-Base`, `-LateBase`),
  because without them `det_check` compares with v0.1.0.
- **A test that saves a setting writes the player's real file.** Symptom: the game keeps its remembered settings
  (the start screen's difficulty pick) in `user://halcyon_settings.cfg`, in the Windows user data folder that the
  player's own game reads, so a test run that presses a picker button changes what the player sees next time. Fix:
  start such a run with the environment variable `APPDATA` pointing at an empty scratch folder (`OS.get_user_data_dir()`
  then lives inside it), and let the test write only when that folder's name holds a marker it was given
  (`--settings-check=<text>` in `tests/difficulty_check.gd`). A run that only reads the settings, or a headless or
  `--auto` run, never opens the file: only the start screen reads it.
- **Windowed runs are paced by vsync.** Symptom: about 25 fps here, so speed numbers mean nothing. Fix: measure
  speed with `--disable-vsync`; park a window off-screen so nothing appears on the user's monitor:
  `--position 30000,30000 --disable-vsync --audio-driver Dummy`.
- **Movie Maker records one size.** Symptom: `--write-movie` always records at the project's 1280x720. Fix: for
  other sizes use `--shots=<dir>` in a windowed run.
- **Godot dies with the call that started it.** Symptom: a Godot started inside a foreground tool call ends
  when the call ends. Fix: start long runs through the queue (`run_batch`) with `run_in_background`, or from a
  detached launcher that waits 30 s first. Never run Godot in the repo clone's own checkout: it writes `.godot`
  and `.uid` files there and its branch can change under you; use a worktree export.
- **`Vector2` is single precision.** Symptom: a probe that halves an interval to find an edge (how big a target is, how close two ships can stand) prints noise such as 17.99902 for 18, because a position near 20,000 resolves only to about 0.002. Fix: round such answers to a hundredth and compare them with a tolerance of 0.01 or more (GDScript's own numbers are 64-bit, but a `Vector2` keeps 32-bit ones).
- **`run_batch` knows a few result markers only.** Symptom: a test that prints `<name>: N failures` shows `no result line, see <file>` although it passed. Fix: a probe whose run should count prints a line that holds a marker the script looks for (`PROBE_JSON`, `FUN_JSON`, `AUDIT_JSON` ...; the list is in `run_batch.ps1`); for a check, read the line in its log, or let `run_checks` look for the words.

## Windows, PowerShell and git

- **A `Start-Job` dies with the shell call that made it.** Symptom: the later seeds of a batch started as a `Start-Job` and left running never start, because the job was a child of the call's PowerShell (only the Godot matches already launched live on). Fix: start each batch with the tool's `run_in_background` (or a detached launcher), one call per batch.
- **`Start-Process -PassThru` leaves `ExitCode` empty.** Symptom: PowerShell 5.1 only fills it in if you touch
  the handle. Fix: `$null = $p.Handle` right after the start.
- **A one-item list becomes a bare string.** Symptom: `x | Sort-Object -Unique` on one item returns a string,
  and `@ids` or a native program then splats it one character per argument. Fix: wrap the result in `@(...)`
  wherever you pipe a list and then splat it or hand it to a native program.
- **PowerShell 5.1 syntax traps.** There is no `&&` or `||` (use `A; if ($?) { B }`); `$Matches` is overwritten
  by the next `-match`; variable names are case-insensitive (`$h` and `$H` are one variable, which once
  created stray folders).
- **Quotes and byte-order marks in commit messages.** Symptom: a message with double quotes breaks native
  argument passing, and PowerShell 5.1 writes a byte-order mark with `>`, `Out-File` and
  `Set-Content -Encoding utf8`, which became a stray first character in a commit subject. Fix: write the
  message to a file without a mark (the Write tool, or `[System.IO.File]::WriteAllText` with
  `New-Object System.Text.UTF8Encoding $false`) and use `git commit -F <file>`.
- **A file stored with CRLF is rewritten with LF by `git add`.** Symptom: after a small edit to
  `docs/CODE_GUIDE.md`, the only file of the repo whose stored copy has CRLF line endings, `git diff --numstat`
  shows every line changed, although `git diff --ignore-space-at-eol --numstat` shows the few lines you edited
  (the clone's `core.autocrlf=true` turns CRLF into LF on `git add`). A whole-file diff hides your change and
  makes every later merge of that file conflict. Fix: before each commit compare the two numstat outputs; to
  keep a file's own endings, build its new bytes from the base commit's bytes (replace only your lines), store
  them with `git hash-object -w --no-filters`, point the index at the blob with
  `git update-index --cacheinfo 100644,<blob>,<path>` and copy the same bytes into the work tree.
- **The agent shell may refuse the text `Remove-Item`.** Fix: delete with `[System.IO.File]::Delete` or
  `[System.IO.Directory]::Delete`.
- **Merges conflict in the same three logs.** Symptom: `PROGRESS.md`, `CODE_GUIDE.md` and `DESIGN.md` conflict
  on almost every merge between branches. Fix: keep both sides' sections (they only grow), and rebuild
  `docs/API_INDEX.md` with `python tools/api_index.py` instead of merging it by hand.

## Cloud runs

- **Linux and Windows runs are not bit-identical.** Symptom: a cloud run (Linux) and a local run (Windows) of
  the same seed print different hashes. Fix: compare only within one platform, paired by seed.
