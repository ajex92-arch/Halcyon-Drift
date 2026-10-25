# Halcyon Drift

A space MOBA built in Godot 4.7.2 (GDScript), fought in the Halcyon Drift, an
asteroid belt. This repository holds the game and the tools and notes used to
test and improve it.

## Layout

- `remake/`: the game (a Godot project). Start with `remake/README.md`.
  The design is `remake/docs/DESIGN.md`, the work log is
  `remake/docs/PROGRESS.md`, the code map is `remake/docs/CODE_GUIDE.md`, the
  user's requirements are `remake/docs/USER_REQUIREMENTS_2026-10-13.md`, the
  release notes are `remake/docs/RELEASE_NOTES.md`, and the AI deep dive report
  is `remake/docs/AI_DEEP_DIVE.md`.
- `session_tools/`: the PowerShell and Python helpers used to run all-AI
  matches in batches and to merge work safely:
  - `run_batch.ps1`: the shared match queue. It runs 3 matches at once by
    day and 6 in the free-PC window, at below-normal priority.
  - `bank_group.ps1` and `merge_group.ps1`: merge a working copy into the
    game, run the checks, and roll back on failure.
  - `run_checks.ps1`: the quick checks.
  - `det_check.ps1` and `make_baselines.ps1`: the determinism check.
  - `doc_check.ps1`: documentation coverage.
  - `ab_compare.py` and `adm2_cmp.py`: compare A/B audit runs.

  The scripts expect the Godot console exe and a scratch folder. Their paths
  are set at the top of each script.
- `deep_dive/`: the notes of the AI deep dive (state, plan, preliminary
  findings and each investigator's findings).
- `fun_plan/`: the fun-experiment fork briefs and build reports. The
  binding plan is `remake/docs/FUN_PLAN.md`.

## Rules and teams

Since v0.3.0 every match plays the standard rules, which are the fun experiments'
"Council's pick" (v0.2.0 offered it as a rule set): the start screen has no rule-set row
any more. It has a TEAM row, to play Aurelian or Vhorr, and a DIFFICULTY row. For tests
and research the older rules are launch options: `--preset=none` plays the old
standard rules of v0.1.0, `--preset=within` and `--preset=pick` the two rule sets of
v0.2.0. `remake/docs/RELEASE_NOTES.md` says what each release changes, how it was tested
and what is still open.

## Branches

- `main`: the game as banked after each verified step. Releases are tags that
  start with `v` (for example `v0.2.0`) on main.
- `cloud-runs` and `cloud-results`: the branches the cloud match runs use (a
  request goes on `cloud-runs`, the logs come back on `cloud-results`).
