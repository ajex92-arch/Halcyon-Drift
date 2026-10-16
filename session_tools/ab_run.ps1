# A/B runs of the deep-dive candidate fixes (salvaged from the stopped
# investigators), queued through run_batch.ps1 (3 matches at once by day,
# 6 at night). Seeds 7, 11, 13. Logs: deepdive\runs\ab\<tag>_seed<N>.txt.
# -Seq A = pilot audits (base, flight, behaviour, targeting; normal + late)
# -Seq B = minion audit and targeting shot probe (base vs fix)
param([string]$Seq = "A")
$sp = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rb = Join-Path $sp "run_batch.ps1"
$out = Join-Path $sp "deepdive\runs\ab"
New-Item -ItemType Directory -Force $out | Out-Null
$seeds = @(7, 11, 13)
$targ = "--ddfix=beam,ion,aim2,ovl,los,bd,ms"
if ($Seq -eq "A") {
	$jobs = @(
		@("dd_flight_fix", "ab_audit", "ab_base", @("--secs=900")),
		@("dd_flight_fix", "ab_audit", "ab_flight", @("--secs=900", "--ff=ABDEH")),
		@("dd_behavior_fix", "ab_audit", "ab_beh", @("--secs=900")),
		@("dd_targeting_fix", "ab_audit", "ab_targ", @("--secs=900", $targ)),
		@("dd_flight_fix", "ab_audit", "late_base", @("--late", "--secs=300")),
		@("dd_flight_fix", "ab_audit", "late_flight", @("--late", "--secs=300", "--ff=ABDEH")),
		@("dd_behavior_fix", "ab_audit", "late_beh", @("--late", "--secs=300")),
		@("dd_targeting_fix", "ab_audit", "late_targ", @("--late", "--secs=300", $targ)))
} else {
	$jobs = @(
		@("dd_minions_fix", "minion_audit", "mn_base", @("--secs=900")),
		@("dd_minions_fix", "minion_audit", "mn_fix", @("--secs=900", "--mfix=lead,gate,route,los")),
		@("dd_targeting_fix", "dd_target_probe", "tp_base", @("--secs=900")),
		@("dd_targeting_fix", "dd_target_probe", "tp_fix", @("--secs=900", $targ)))
}
foreach ($j in $jobs) {
	& $rb -Project (Join-Path $sp ("notate\" + $j[0])) -Seeds $seeds -OutDir $out -Tag $j[2] -Test $j[1] -Extra $j[3] | Out-Null
	Add-Content (Join-Path $out "progress.txt") ("{0} done {1}" -f (Get-Date -Format "HH:mm"), $j[2])
}
Add-Content (Join-Path $out "progress.txt") ("{0} SEQ {1} FINISHED" -f (Get-Date -Format "HH:mm"), $Seq)
