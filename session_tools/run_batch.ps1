param(
	# Godot project folder to run (a fork, the council branch or main).
	[Parameter(Mandatory = $true)][string]$Project,
	# Seeds to run, e.g. 101,102,103 (each is one match).
	[Parameter(Mandatory = $true)][int[]]$Seeds,
	# Where the per-seed logs go (created if missing).
	[Parameter(Mandatory = $true)][string]$OutDir,
	# Name used in log file names, e.g. "A1_on" -> A1_on_seed101.txt.
	[Parameter(Mandatory = $true)][string]$Tag,
	# The test to run (tests/<name>.gd).
	[string]$Test = "fun_probe",
	# Extra game options, e.g. "--secs=3600","--skill-jitter","--variant=slip:on".
	[string[]]$Extra = @("--secs=3600")
)
# SHARED SIMULATION QUEUE. Every agent that runs full matches goes through
# this script so the whole machine never runs more than 6 batch matches at
# once (6 cores; more processes only make every match slower), and only 3
# between 06:00 and 18:00, when the user needs the PC (the user allows full
# use from 18:00 to 06:00).
#
# How it works: there are 6 "slot" files in scratchpad\slots. To start a
# match the script must create one of them (only one process can create a
# given file). The slot file holds the Godot process id; when that process
# has ended (or the slot is older than 3 hours) the slot is free again.
# The script starts each seed as soon as a slot is free, waits for all of
# its seeds, then prints one line per seed:
#   "<tag> seed <n>: ok" when the log has a result line (FUN_JSON, ARENA RESULT,
#   DUEL_JSON, AUDIT_JSON or PROBE_JSON), else "...: no result line, see <file>"
# and finally "BATCH DONE <tag>: <ok>/<total> ok".
# It can take hours: run it in the background and poll its output.
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = Join-Path $sp "godot-bin\Godot_v4.7.2-stable_win64_console.exe"
$slots = Join-Path $sp "slots"
New-Item -ItemType Directory -Force $slots | Out-Null
New-Item -ItemType Directory -Force $OutDir | Out-Null
$MAX = 6
# How many slots may be used right now: all 6 on Saturdays and Sundays and
# on weekdays from 18:00 to 07:30 (the user's free-PC window, 2026-10-16),
# else 3.
function Get-Limit {
	$d = Get-Date
	if ($d.DayOfWeek -eq [DayOfWeek]::Saturday -or $d.DayOfWeek -eq [DayOfWeek]::Sunday) { return $MAX }
	$m = $d.Hour * 60 + $d.Minute
	if ($m -ge 18 * 60 -or $m -lt 7 * 60 + 30) { return $MAX } else { return 3 }
}

function Get-FreeSlot {
	for ($i = 1; $i -le (Get-Limit); $i++) {
		$f = Join-Path $slots "slot_$i.lock"
		if (Test-Path $f) {
			# Free it if its process is gone or it is ancient.
			$content = Get-Content $f -ErrorAction SilentlyContinue
			$procId = 0; [int]::TryParse(($content | Select-Object -First 1), [ref]$procId) | Out-Null
			$age = (Get-Date) - (Get-Item $f -ErrorAction SilentlyContinue).LastWriteTime
			$alive = $procId -gt 0 -and (Get-Process -Id $procId -ErrorAction SilentlyContinue)
			if ($procId -eq 0 -and $age.TotalMinutes -lt 2) { continue }  # being claimed right now
			if (-not $alive -or $age.TotalHours -gt 3) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
			else { continue }
		}
		try {
			$fs = [IO.File]::Open($f, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
			$fs.Close()
			return $f
		} catch { continue }
	}
	return $null
}

$pending = [System.Collections.Generic.Queue[int]]::new()
$Seeds | ForEach-Object { $pending.Enqueue($_) }
$running = @()
while ($pending.Count -gt 0 -or $running.Count -gt 0) {
	# Start seeds while slots are free.
	while ($pending.Count -gt 0) {
		$slot = Get-FreeSlot
		if ($null -eq $slot) { break }
		$seed = $pending.Dequeue()
		$out = Join-Path $OutDir "${Tag}_seed$seed.txt"
		$err = Join-Path $OutDir "${Tag}_seed${seed}_err.txt"
		$a = @("--headless", "--path", "`"$Project`"", "--fixed-fps", "60", "--", "--all-ai", "--seed=$seed", "--test=$Test") + $Extra
		$p = Start-Process -FilePath $godot -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
		Set-Content $slot $p.Id
		$running += [pscustomobject]@{ Seed = $seed; Proc = $p; Slot = $slot; Out = $out }
	}
	Start-Sleep 15
	# Keep every Godot process at below-normal priority, so the user's own
	# programs stay responsive (the console wrapper starts the game as a
	# child, so the priority is set here for all of them, every 15 s).
	Get-Process -Name "Godot*" -ErrorAction SilentlyContinue | ForEach-Object { try { if ($_.PriorityClass -ne "BelowNormal") { $_.PriorityClass = "BelowNormal" } } catch {} }
	# Release slots of finished matches.
	$still = @()
	foreach ($r in $running) {
		# Only delete the slot file if it still holds OUR process id: another
		# batch may already have reclaimed it (it saw our process gone during
		# our 15 s sleep), and deleting its claim let a 4th-6th match start by day.
		if ($r.Proc.HasExited) {
			$cur = Get-Content $r.Slot -TotalCount 1 -ErrorAction SilentlyContinue
			if ("$cur".Trim() -eq "$($r.Proc.Id)") { Remove-Item $r.Slot -Force -ErrorAction SilentlyContinue }
		} else { $still += $r }
	}
	$running = $still
}
$ok = 0
foreach ($seed in $Seeds) {
	$out = Join-Path $OutDir "${Tag}_seed$seed.txt"
	if (Get-Content $out -ErrorAction SilentlyContinue | Select-String "FUN_JSON|ARENA RESULT|DUEL_JSON|AUDIT_JSON|PROBE_JSON") { $ok++; "$Tag seed ${seed}: ok" }
	else { "$Tag seed ${seed}: no result line, see $out" }
}
"BATCH DONE ${Tag}: $ok/$($Seeds.Count) ok"
