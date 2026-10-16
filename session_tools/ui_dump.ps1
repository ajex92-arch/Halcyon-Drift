param(
	[Parameter(Mandatory = $true)][string]$Project,
	[Parameter(Mandatory = $true)][string]$Out,
	# A folder from an earlier run of this script to compare with.
	[string]$Before = ""
)
# Exact UI check without a window. Runs the UI tour headless with
# --force-hud --dump and a fixed frame step (--fixed-fps 60), for a pilot
# and for an admiral (side by side), and keeps only the "UIDUMP" lines:
# every control on screen at every picture step, with its class, place,
# size, text and resolved look (tests/ui_tour.gd _dump()). Writes
# $Out\pilot.txt and $Out\admiral.txt. With -Before, compares them line by
# line with that folder's files and shows the first differences.
# Ends with "DUMP DONE", or with -Before "DUMPS IDENTICAL" / "DUMPS DIFFER".
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = Join-Path $sp "godot-bin\Godot_v4.7.2-stable_win64_console.exe"
New-Item -ItemType Directory -Force $Out | Out-Null
$runs = @(
	@{ Name = "pilot"; Args = @("--role=pilot") },
	@{ Name = "admiral"; Args = @("--role=admiral") }
)
foreach ($r in $runs) {
	$r.Raw = Join-Path $Out "$($r.Name)_raw.txt"
	$a = @("--headless", "--path", "`"$Project`"", "--fixed-fps", "60", "--", "--auto", "--bot=tour", "--force-hud", "--seed=7", "--test=ui_tour", "--dump") + $r.Args
	$r.Proc = Start-Process -FilePath $godot -ArgumentList $a -RedirectStandardOutput $r.Raw -RedirectStandardError ($r.Raw -replace '\.txt$', '_err.txt') -PassThru
}
$ok = $true
foreach ($r in $runs) {
	if (-not $r.Proc.WaitForExit(300000)) { try { $r.Proc.Kill() } catch {}; "$($r.Name): killed after 300 s"; $ok = $false }
	$all = @(Get-Content $r.Raw, ($r.Raw -replace '\.txt$', '_err.txt') -Encoding UTF8 -ErrorAction SilentlyContinue)
	$all | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Nonexistent function' } | Select-Object -First 5 | ForEach-Object { "$($r.Name) ERROR: $_"; $ok = $false }
	$lines = @($all | Where-Object { $_ -match '^UIDUMP ' })
	$lines | Set-Content (Join-Path $Out "$($r.Name).txt") -Encoding utf8
	$steps = @($lines | ForEach-Object { ($_ -split ' ')[1] } | Select-Object -Unique)
	$done = [bool]($all | Where-Object { $_ -match '^ui_tour: done' })
	"$($r.Name): $($lines.Count) lines over $($steps.Count) steps; finished=$done"
	if (-not $done) { $ok = $false }
}
if ($Before -eq "") { if ($ok) { "DUMP DONE" } else { "DUMP FAILED" }; return }
$same = $ok
foreach ($r in $runs) {
	$a = @(Get-Content (Join-Path $Before "$($r.Name).txt") -Encoding UTF8)
	$b = @(Get-Content (Join-Path $Out "$($r.Name).txt") -Encoding UTF8)
	$first = -1
	for ($i = 0; $i -lt [Math]::Max($a.Count, $b.Count); $i++) {
		if ($i -ge $a.Count -or $i -ge $b.Count -or $a[$i] -ne $b[$i]) { $first = $i; break }
	}
	if ($first -lt 0) { "DUMP $($r.Name) IDENTICAL ($($a.Count) lines)"; continue }
	$same = $false
	$onlyA = @(Compare-Object $a $b | Where-Object { $_.SideIndicator -eq '<=' }).Count
	$onlyB = @(Compare-Object $a $b | Where-Object { $_.SideIndicator -eq '=>' }).Count
	"DUMP $($r.Name) DIFFERS: before $($a.Count) lines, now $($b.Count); $onlyA lines only before, $onlyB only now. First difference at line $($first + 1):"
	for ($i = $first; $i -lt [Math]::Min($first + 3, [Math]::Max($a.Count, $b.Count)); $i++) {
		"  before: " + $(if ($i -lt $a.Count) { $a[$i] } else { "(end)" })
		"  now:    " + $(if ($i -lt $b.Count) { $b[$i] } else { "(end)" })
	}
}
if ($same) { "DUMPS IDENTICAL" } else { "DUMPS DIFFER" }
