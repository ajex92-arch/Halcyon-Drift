param(
	[Parameter(Mandatory = $true)][string]$Project,
	[string[]]$Files = @(),
	[switch]$ListMissing
)
# Documentation coverage for the CODE_STYLE.md rules, per script:
#   header   the first 30 lines contain "WHAT THIS IS"
#   funcs    functions with a "##" doc comment directly above (or above
#            their decorators) / all functions
#   members  class-level var/const/signal/enum lines with a note (a "##"
#            line above or a "#" comment on the same line) / all of them
#   cmt%     comment lines as a share of non-blank lines
# -Files limits the check to those relative paths (default: every .gd
# outside .godot). -ListMissing names each undocumented func/member.
$Project = (Get-Item $Project).FullName
$all = Get-ChildItem $Project -Recurse -Filter *.gd | Where-Object { $_.FullName -notmatch '\\\.godot\\' }
if ($Files.Count -gt 0) {
	$want = $Files | ForEach-Object { ($_ -replace '/', '\').ToLower() }
	$all = $all | Where-Object { $want -contains $_.FullName.Substring($Project.TrimEnd('\').Length + 1).ToLower() }
}
$tot = @{ f = 0; fd = 0; m = 0; md = 0; hdr = 0; n = 0 }
foreach ($file in ($all | Sort-Object FullName)) {
	$rel = $file.FullName.Substring($Project.TrimEnd('\').Length + 1)
	$L = Get-Content $file.FullName
	$hdr = [bool]($L | Select-Object -First 30 | Where-Object { $_ -match 'WHAT THIS IS' })
	$funcs = 0; $fdoc = 0; $mem = 0; $mdoc = 0; $cmt = 0; $nonblank = 0
	$missing = @()
	for ($i = 0; $i -lt $L.Count; $i++) {
		$line = $L[$i]
		if ($line.Trim() -ne '') { $nonblank++ }
		if ($line.Trim().StartsWith('#')) { $cmt++ }
		# Previous non-decorator, non-blank line.
		$j = $i - 1
		while ($j -ge 0 -and ($L[$j].Trim() -eq '' -or $L[$j].Trim().StartsWith('@'))) { if ($L[$j].Trim() -eq '') { $j = -2; break }; $j-- }
		$prevDoc = ($j -ge 0 -and $L[$j].Trim().StartsWith('##'))
		if ($line -match '^\s*(static\s+)?func\s+(\w+)') {
			$funcs++
			if ($prevDoc) { $fdoc++ } else { $missing += "func $($matches[2]) (line $($i+1))" }
		}
		elseif ($line -match '^(@\w+(\(.*?\))?\s+)*(var|const|signal|enum)\s+(\w+)') {
			$mem++
			if ($prevDoc -or $line -match '#') { $mdoc++ } else { $missing += "$($matches[3]) $($matches[4]) (line $($i+1))" }
		}
	}
	$tot.n++; if ($hdr) { $tot.hdr++ }; $tot.f += $funcs; $tot.fd += $fdoc; $tot.m += $mem; $tot.md += $mdoc
	"{0,-46} {1,5} lines  header {2,-3}  funcs {3,3}/{4,-3}  members {5,3}/{6,-3}  cmt {7,3}%" -f $rel, $L.Count, $(if ($hdr) { "ok" } else { "NO" }), $fdoc, $funcs, $mdoc, $mem, [int](100 * $cmt / [Math]::Max(1, $nonblank))
	if ($ListMissing -and $missing.Count -gt 0) { $missing | ForEach-Object { "      missing: $_" } }
}
"TOTAL {0} files: headers {1}/{0}, funcs {2}/{3} documented, members {4}/{5} noted" -f $tot.n, $tot.hdr, $tot.fd, $tot.f, $tot.md, $tot.m
