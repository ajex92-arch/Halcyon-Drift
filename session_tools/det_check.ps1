param(
	[Parameter(Mandatory = $true)][string]$Project,
	[int]$Secs = 900,
	[int]$LateSecs = 300,
	[string]$Tag = "check"
)
# Behaviour check for refactors. Runs tests/det_hash.gd twice in $Project,
# side by side, with seed 7:
#   normal: the first $Secs seconds of a match (early and mid game)
#   late:   $LateSecs seconds from 25:00, fully teched (sieges, capitals)
# and compares the hash lines with the baselines made from the original
# remake. Prints one verdict per run:
#   "DET normal IDENTICAL over N lines"  or  "DET normal DIFFER at line ..."
# plus any SCRIPT ERROR lines. Takes several minutes: run it in the
# background and read the output when it finishes.
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = Join-Path $sp "godot-bin\Godot_v4.7.2-stable_win64_console.exe"
$id = [guid]::NewGuid().ToString("N").Substring(0, 6)
$runs = @(
	@{ Name = "normal"; Base = (Join-Path $sp "dh_base_1.txt"); Args = @("--secs=$Secs") },
	@{ Name = "late"; Base = (Join-Path $sp "dh_late_base.txt"); Args = @("--late", "--secs=$LateSecs") }
)
foreach ($r in $runs) {
	$r.Out = Join-Path $sp ("dh_" + $Tag + "_" + $r.Name + "_" + $id + ".txt")
	$r.Err = $r.Out -replace '\.txt$', '_err.txt'
	$a = @("--headless", "--path", "`"$Project`"", "--fixed-fps", "60", "--", "--all-ai", "--seed=7", "--test=det_hash") + $r.Args
	$r.Proc = Start-Process -FilePath $godot -ArgumentList $a -RedirectStandardOutput $r.Out -RedirectStandardError $r.Err -PassThru
}
$ok = $true
foreach ($r in $runs) {
	$r.Proc.WaitForExit(3000000) | Out-Null
	Get-Content $r.Err | Select-String "SCRIPT ERROR|Parse Error|ERROR:" | Select-Object -First 5 | ForEach-Object { "ERR ($($r.Name)): " + $_.Line }
	$a = Get-Content $r.Base | Select-String '^hash' | ForEach-Object { $_.Line }
	$b = Get-Content $r.Out | Select-String '^hash' | ForEach-Object { $_.Line }
	if ($b.Count -eq 0) { "DET $($r.Name) FAILED: no hash lines (see $($r.Out))"; $ok = $false; continue }
	$n = [Math]::Min($a.Count, $b.Count)
	$diff = -1
	for ($i = 0; $i -lt $n; $i++) { if ($a[$i] -ne $b[$i]) { $diff = $i; break } }
	if ($diff -ge 0) { "DET $($r.Name) DIFFER at line $diff : baseline [$($a[$diff])] vs this [$($b[$diff])]"; $ok = $false }
	else { "DET $($r.Name) IDENTICAL over $n lines" }
}
if ($ok) { "DET ALL IDENTICAL" } else { "DET FAILED" }
