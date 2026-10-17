# Halcyon Drift

A space MOBA built in Godot 4.7.2 (GDScript), fought in the Halcyon Drift, an
asteroid belt. This repository holds the game and the tools and notes used to
test and improve it.

## Layout

- `remake/`: the game (a Godot project). Start with `remake/README.md`.
  The design is `remake/docs/DESIGN.md`, the work log is
  `remake/docs/PROGRESS.md`, the code map is `remake/docs/CODE_GUIDE.md`, the
  user's requirements are `remake/docs/USER_REQUIREMENTS_2026-10-13.md`, and
  the AI deep dive report is `remake/docs/AI_DEEP_DIVE.md`.
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

## Branches

- `main`: the game as banked after each verified step.
- `fork/<name>`: one branch per fun-experiment fork, added as they are
  rebased onto main.
- `council`: the council's combination, added later.
