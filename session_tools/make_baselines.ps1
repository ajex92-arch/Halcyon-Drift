param(
	[Parameter(Mandatory = $true)][string]$Project,
	[int]$Secs = 1500,
	[int]$LateSecs = 300,
	[string]$Tag = "nb"
)
# Makes new det_hash baselines for $Project, for a change that is MEANT to
# alter the game. Runs the normal match ($Secs) and the late setup
# ($LateSecs) twice each, all four side by side, with seed 7. Then:
#   - the two runs of each must be identical (the build is deterministic);
#   - prints where the new hashes first differ from the current baselines
#     (dh_base_1.txt, dh_late_base.txt), as a sanity check of when the
#     change first shows.
# It never replaces the baselines: it prints the files to copy.
# Ends with "NB OK" or "NB FAILED".
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = Join-Path $sp "godot-bin\Godot_v4.7.2-stable_win64_console.exe"
$id = [guid]::NewGuid().ToString("N").Substring(0, 6)
$runs = @()
foreach ($kind in @(@{ Name = "normal"; Base = "dh_base_1.txt"; Args = @("--secs=$Secs") }, @{ Name = "late"; Base = "dh_late_base.txt"; Args = @("--late", "--secs=$LateSecs") })) {
	foreach ($n in 1, 2) {
		$out = Join-Path $sp ("dh_" + $Tag + "_" + $kind.Name + "_" + $n + "_" + $id + ".txt")
		$a = @("--headless", "--path", "`"$Project`"", "--fixed-fps", "60", "--", "--all-ai", "--seed=7", "--test=det_hash") + $kind.Args
		$p = Start-Process -FilePath $godot -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError ($out -replace '\.txt$', '_err.txt') -PassThru
		$runs += @{ Name = $kind.Name; Base = (Join-Path $sp $kind.Base); Out = $out; Proc = $p }
	}
}
foreach ($r in $runs) { $r.Proc.WaitForExit(5400000) | Out-Null }
$ok = $true
foreach ($name in "normal", "late") {
	$pair = @($runs | Where-Object { $_.Name -eq $name })
	$a = @(Get-Content $pair[0].Out | Where-Object { $_ -match '^hash ' })
	$b = @(Get-Content $pair[1].Out | Where-Object { $_ -match '^hash ' })
	if ($a.Count -eq 0) { "NB $name FAILED: no hash lines in $($pair[0].Out)"; $ok = $false; continue }
	$same = ($a.Count -eq $b.Count) -and (@(Compare-Object $a $b -SyncWindow 0).Count -eq 0)
	if (-not $same) { "NB $name FAILED: the two runs differ ($($pair[0].Out) vs $($pair[1].Out))"; $ok = $false; continue }
	$old = @(Get-Content $pair[0].Base | Where-Object { $_ -match '^hash ' })
	$k = -1
	for ($i = 0; $i -lt [Math]::Min($a.Count, $old.Count); $i++) { if ($a[$i] -ne $old[$i]) { $k = $i; break } }
	$first = if ($k -ge 0) { "first differs from the old baseline at line $k [$($a[$k])]" } else { "same as the old baseline over $([Math]::Min($a.Count, $old.Count)) lines" }
	"NB $name : two runs IDENTICAL over $($a.Count) lines; $first"
	"NB $name file: $($pair[0].Out)"
}
if ($ok) { "NB OK" } else { "NB FAILED" }
