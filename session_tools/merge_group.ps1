param(
	[Parameter(Mandatory = $true)][string]$Group,
	# Wildcard patterns (relative paths) the group is allowed to change or add.
	[Parameter(Mandatory = $true)][string[]]$Allowed,
	[switch]$DryRun,
	# The snapshot the group's copy started from (default: the pre-notation
	# snapshot scratchpad\original). A copy made later from main needs its
	# own snapshot of main taken at the same moment.
	[string]$Base = ""
)
# Copies one group's changed and new files (.gd, .tscn, .tres, .py, .md)
# from its scratch copy into the main remake, and deletes the ones it
# removed. A file counts as changed by the group when it
# differs from the untouched snapshot of the remake taken before the
# notation pass (scratchpad\original). Refuses (and lists) any change
# outside the group's allowed paths, so a stray edit can't sneak in.
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = (Get-Item "$sp\notate\$Group").FullName
$orig = (Get-Item $(if ($Base -ne "") { $Base } else { "$sp\original" })).FullName
$dst = "<FC>\remake"
$ok = @(); $stray = @()
# Scripts, scenes and docs: GDScript, Godot scenes and resources (.tscn,
# .tres), Python tools (tools/*.py) and Markdown (docs/*.md, README.md).
# Python's cache folders are skipped.
$kinds = @('*.gd', '*.tscn', '*.tres', '*.py', '*.md')
Get-ChildItem $src -Recurse -File -Include $kinds | Where-Object { $_.FullName -notmatch '\\\.godot\\|\\__pycache__\\' } | ForEach-Object {
	$rel = $_.FullName.Substring($src.Length + 1)
	$o = Join-Path $orig $rel
	$differs = (-not (Test-Path $o)) -or ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $o).Hash)
	if ($differs) {
		$hit = $false
		foreach ($p in $Allowed) { if ($rel -like ($p -replace '/', '\')) { $hit = $true } }
		if ($hit) { $ok += $rel } else { $stray += $rel }
	}
}
# Deleted files: in the base snapshot but gone from the copy.
$gone = @()
Get-ChildItem $orig -Recurse -File -Include $kinds | Where-Object { $_.FullName -notmatch '\\\.godot\\|\\__pycache__\\' } | ForEach-Object {
	$rel = $_.FullName.Substring($orig.Length + 1)
	if (-not (Test-Path (Join-Path $src $rel))) {
		$hit = $false
		foreach ($p in $Allowed) { if ($rel -like ($p -replace '/', '\')) { $hit = $true } }
		if ($hit) { $gone += $rel } else { $stray += "$rel (deleted)" }
	}
}
if ($stray.Count -gt 0) { "REFUSED: changes outside the group's files:"; $stray | ForEach-Object { "  $_" }; exit 1 }
# Conflicts: main's copy of the file was ALSO changed since the snapshot
# (by another agent's bank) and is not what we are about to write. Copying
# would erase that other change, so refuse; the agent must copy main's
# version into its copy, re-apply its own change on top and bank again.
# The ledger remembers which group banked which file version, so a group
# may overwrite ITS OWN earlier bank (a re-bank after a fix) but never
# another group's.
$ledger = Join-Path $sp "bank_ledger.txt"
$mine = @{}
if (Test-Path $ledger) { Get-Content $ledger | ForEach-Object { $p = $_ -split '\|'; if ($p[0] -eq $Group) { $mine[$p[1]] = $p[2] } } }
$conflicts = @()
foreach ($rel in $ok) {
	$o = Join-Path $orig $rel
	$m = Join-Path $dst $rel
	if (-not (Test-Path $m)) { continue }
	$mh = (Get-FileHash $m).Hash
	if ($mh -eq (Get-FileHash (Join-Path $src $rel)).Hash) { continue }
	$mainChanged = (-not (Test-Path $o)) -or ($mh -ne (Get-FileHash $o).Hash)
	if ($mainChanged -and $mine[$rel] -ne $mh) { $conflicts += $rel }
}
if ($conflicts.Count -gt 0) { "REFUSED: CONFLICT - main already has other changes in:"; $conflicts | ForEach-Object { "  $_" }; exit 1 }
foreach ($rel in $ok) {
	if (-not $DryRun) {
		# A new file may sit in a folder main doesn't have yet (tests/lib).
		$dir = Split-Path (Join-Path $dst $rel) -Parent
		if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
		Copy-Item (Join-Path $src $rel) (Join-Path $dst $rel) -Force
		Add-Content $ledger ("{0}|{1}|{2}" -f $Group, $rel, (Get-FileHash (Join-Path $dst $rel)).Hash)
	}
	"copied $rel"
}
foreach ($rel in $gone) {
	$m = Join-Path $dst $rel
	if (-not $DryRun -and (Test-Path $m)) {
		[IO.File]::Delete($m)
		# Godot keeps a ".uid" file next to each script; it goes too.
		if (Test-Path "$m.uid") { [IO.File]::Delete("$m.uid") }
	}
	"deleted $rel"
}
"MERGED $($ok.Count) files (and deleted $($gone.Count)) from $Group$(if ($DryRun) { ' (dry run)' })"
