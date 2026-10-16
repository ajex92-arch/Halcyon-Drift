param(
	[Parameter(Mandatory = $true)][string]$Group,
	[Parameter(Mandatory = $true)][string[]]$Allowed,
	# The snapshot the group's copy started from (see merge_group.ps1);
	# rollbacks also restore from it. Default: scratchpad\original.
	[string]$Base = ""
)
# Banks one finished group into the main remake, safely when several agents
# finish at once:
#   1. waits for the main-project lock (one bank at a time; a lock older
#      than 40 minutes is treated as left behind by a dead agent)
#   2. merge_group.ps1: first a dry run (the list of files it will change,
#      kept for a rollback), then the real merge (copies only the group's
#      own changed/new files and deletes the ones it removed)
#   3. run_checks.ps1 on main
#   4. if the merge stopped halfway or main fails its checks: restores the
#      listed files from the base snapshot (deleting files that are new),
#      re-runs the main checks, reports BANK FAILED
#   5. releases the lock
# Ends with "BANK OK" or "BANK FAILED".
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$main = "<FC>\remake"
$lock = Join-Path $sp "main.lock"
if ($Base -eq "") { $Base = "$sp\original" }
$orig = (Get-Item $Base).FullName

# 1. Take the lock.
while ($true) {
	try {
		$fs = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
		$bytes = [Text.Encoding]::UTF8.GetBytes("$Group $(Get-Date -Format o)")
		$fs.Write($bytes, 0, $bytes.Length); $fs.Close()
		break
	} catch {
		$age = (Get-Date) - (Get-Item $lock -ErrorAction SilentlyContinue).LastWriteTime
		if ($age.TotalMinutes -gt 40) { Remove-Item $lock -Force -ErrorAction SilentlyContinue; continue }
		"waiting for main lock (held by: $(Get-Content $lock -ErrorAction SilentlyContinue))"
		Start-Sleep 20
	}
}
try {
	# 2. Merge: the dry run gives the list of files (and refuses strays and
	# conflicts before anything is touched); then the real merge.
	$plan = & "$sp\merge_group.ps1" -Group $Group -Allowed $Allowed -Base $Base -DryRun
	if (-not ($plan | Where-Object { $_ -match '^MERGED' })) { $plan; "BANK FAILED (merge refused)"; return }
	$copied = @($plan | Where-Object { $_ -match '^copied ' } | ForEach-Object { $_.Substring(7) })
	$deleted = @($plan | Where-Object { $_ -match '^deleted ' } | ForEach-Object { $_.Substring(8) })
	$merged = $false
	try {
		$m = & "$sp\merge_group.ps1" -Group $Group -Allowed $Allowed -Base $Base -ErrorAction Stop
		$m
		$merged = [bool]($m | Where-Object { $_ -match '^MERGED' })
	} catch {
		"merge stopped halfway: $_"
	}
	# 3. Check main (only after a complete merge).
	if ($merged) {
		$c = & powershell -NoProfile -ExecutionPolicy Bypass -File "$sp\run_checks.ps1" -Project $main
		$c
		if ($c | Where-Object { $_ -eq 'CHECKS ALL OK' }) { "BANK OK ($($copied.Count) files, $($deleted.Count) deleted)"; return }
		"main checks failed: rolling back $($copied.Count) files and $($deleted.Count) deletions"
	} else {
		"rolling back the partial merge: $($copied.Count) files and $($deleted.Count) deletions"
	}
	# 4. Roll back: put back the base versions of what we changed, delete
	# what we added, and restore what we deleted.
	foreach ($rel in $copied) {
		$o = Join-Path $orig $rel
		$d = Join-Path $main $rel
		if (Test-Path $o) { Copy-Item $o $d -Force } else { Remove-Item $d -Force -ErrorAction SilentlyContinue }
	}
	foreach ($rel in $deleted) {
		$o = Join-Path $orig $rel
		if (Test-Path $o) { Copy-Item $o (Join-Path $main $rel) -Force }
		if (Test-Path "$o.uid") { Copy-Item "$o.uid" (Join-Path $main "$rel.uid") -Force }
	}
	& powershell -NoProfile -ExecutionPolicy Bypass -File "$sp\run_checks.ps1" -Project $main
	"BANK FAILED (rolled back)"
} finally {
	# 5. Release the lock.
	Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
