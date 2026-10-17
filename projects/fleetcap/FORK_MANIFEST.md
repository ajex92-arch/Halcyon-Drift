# Council branch manifest (docs/FUN_PLAN.md section 6)

The council build = the newest base (notate\int3 as banked for pass 3) merged with all six fun
forks. Every idea of every fork is here behind its own variant key; every key defaults to
today's game. The six forks' own manifests are kept unchanged in `docs/fork_manifests/<fork>.md`
(keys, values, usage counters, shared-file edits of each fork).

Local-only git repo (no remote): branches `forkbase`, `fork/<name>`, `base`, `council`.
Notes, key table and presets: `SP\fun\council\` (PREWARM.md, keys.md, presets.md).

## Keys that refuse to run together (FUN_PLAN 4.5)

`FeatureRegistry.CONFLICTS` lists the pairs; a match with both keys of a pair on prints
`FEATURE CONFLICT: ...` and quits at match start (exit code 3). See the list in
`scripts/features/feature_registry.gd`.
