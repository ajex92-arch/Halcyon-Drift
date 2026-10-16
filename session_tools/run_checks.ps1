param(
	[Parameter(Mandatory = $true)][string]$Project,
	[switch]$NoImport
)
# Fast checks for a refactored copy of the game (a few minutes in total):
#   import       re-register class_names (needed after adding scripts)
#   load_all     every script parses
#   bot_pilot    the human pilot's controls, hangar, docking, kits
#   support_probe  wards, repair bays, drones, admiral orders
#   ui_pilot / ui_admiral  the real HUD clicked through headless (--force-hud)
# Prints one line per check: "OK <name>: ..." or "FAIL <name>: ...", any
# SCRIPT ERROR lines, then "CHECKS ALL OK" or "CHECKS FAILED".
$sp = Split-Path -Parent $MyInvocation.MyCommand.Path
$godot = Join-Path $sp "godot-bin\Godot_v4.7.2-stable_win64_console.exe"
$id = [guid]::NewGuid().ToString("N").Substring(0, 6)

function Invoke-Godot([string]$name, [string[]]$a, [int]$waitMs = 590000) {
	$out = Join-Path $sp "rc_${name}_$id.txt"
	$err = Join-Path $sp "rc_${name}_${id}_err.txt"
	$p = Start-Process -FilePath $godot -ArgumentList (@("--headless", "--path", "`"$Project`"") + $a) -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
	if (-not $p.WaitForExit($waitMs)) { try { $p.Kill() } catch {} }
	return @{ Out = (Get-Content $out -ErrorAction SilentlyContinue); Err = (Get-Content $err -ErrorAction SilentlyContinue) }
}

function Get-ScriptErrors($r) {
	return @(($r.Out + $r.Err) | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Invalid call|Invalid access|Nonexistent function|Identifier .* not declared' })
}

$all = $true
if (-not $NoImport) {
	$r = Invoke-Godot "import" @("--import") 300000
	$e = Get-ScriptErrors $r
	if ($e.Count -gt 0) { "FAIL import:"; $e | Select-Object -First 8 | ForEach-Object { "  " + $_ }; $all = $false } else { "OK import" }
}

$checks = @(
	@{ Name = "load_all"; Args = @("--", "--auto", "--all-ai", "--test=load_all"); Want = "load_all: 0 failures" },
	@{ Name = "bot_pilot"; Args = @("--fixed-fps", "60", "--", "--auto", "--role=pilot", "--bot=input", "--no-pilots", "--no-admiral-ai", "--test=bot_pilot"); Want = "bot_pilot: 0 failures" },
	@{ Name = "support_probe"; Args = @("--fixed-fps", "60", "--", "--auto", "--all-ai", "--no-pilots", "--no-jungle", "--no-admiral-ai", "--test=support_probe"); Want = "support_probe: 0 failures" },
	@{ Name = "ui_pilot"; Args = @("--", "--auto", "--role=pilot", "--bot=tour", "--force-hud", "--test=ui_tour"); Want = "ui_tour: done (pilot)" },
	@{ Name = "ui_admiral"; Args = @("--", "--auto", "--role=admiral", "--bot=tour", "--force-hud", "--test=ui_tour"); Want = "ui_tour: done (admiral)" }
)
foreach ($c in $checks) {
	$r = Invoke-Godot $c.Name $c.Args
	$e = Get-ScriptErrors $r
	$hit = @($r.Out | Where-Object { $_ -match [regex]::Escape($c.Want) })
	if ($hit.Count -gt 0 -and $e.Count -eq 0) { "OK $($c.Name): $($hit[0].Trim())" }
	else {
		$all = $false
		$fails = @($r.Out | Where-Object { $_ -match 'FAIL|failures' })
		"FAIL $($c.Name): wanted '$($c.Want)'; got: " + (($fails | Select-Object -First 3) -join ' | ')
		$e | Select-Object -First 8 | ForEach-Object { "  " + $_ }
	}
}
if ($all) { "CHECKS ALL OK" } else { "CHECKS FAILED" }
