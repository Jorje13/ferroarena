# Une commande pour livrer : (version) -> commit + push du code -> export Windows -> zip -> release GitHub.
# Les joueurs recoivent la nouvelle version au prochain lancement (voir scripts/autoload/updater.gd).
#
#   powershell -File tools/release.ps1 -Version 0.14.1 -Message "Correctifs vault"
#
# -Version  nouvelle version (ecrite dans Game.GAME_VERSION). Sans elle, la version actuelle est reutilisee
#           (la release est alors remplacee si elle existe deja).
# -Message  message du commit et notes de la release.
# -SkipExport  republie le dernier export sans reexporter.
# Prerequis : Git, GitHub CLI connecte (gh auth login), modeles d'export Godot installes.

param(
	[string]$Version = "",
	[string]$Message = "",
	[switch]$SkipExport
)

$ErrorActionPreference = 'Stop'
$proj = Split-Path $PSScriptRoot -Parent
$build = Join-Path (Split-Path $proj -Parent) 'build\release'  # dossier a part : l'exe de test peut etre ouvert (verrouille)
$godot = if ($env:GODOT) { $env:GODOT } else { (Get-Command godot -ErrorAction SilentlyContinue).Source }
$git = (Get-Command git -ErrorAction SilentlyContinue).Source
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
$repo = [regex]::Match((& git -C $proj remote get-url origin), 'github\.com[:/](.+?)(\.git)?$').Groups[1].Value
foreach ($tool in @($godot, $git, $gh)) { if (-not (Test-Path $tool)) { throw "Introuvable : $tool" } }
Set-Location $proj

# 1. Version
$gd = Join-Path $proj 'scripts/autoload/game.gd'
$text = [System.IO.File]::ReadAllText($gd)
if ($Version -ne "") {
	$text = [regex]::Replace($text, 'GAME_VERSION := "[^"]+"', "GAME_VERSION := `"$Version`"")
	[System.IO.File]::WriteAllText($gd, $text, (New-Object System.Text.UTF8Encoding($false)))
}
if ($text -notmatch 'GAME_VERSION := "([^"]+)"') { throw "GAME_VERSION introuvable dans game.gd" }
$ver = $Matches[1]
$tag = "v$ver"
if ($Message -eq "") { $Message = "Ferro Arena $ver" }
"== Version $ver =="

# 2. Code -> GitHub (le tag de la release pointera sur ce commit)
& $git add -A
& $git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
	$msgFile = Join-Path $env:TEMP 'ferro_release_msg.txt'
	[System.IO.File]::WriteAllText($msgFile, "$Message`n`nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`n", (New-Object System.Text.UTF8Encoding($false)))
	& $git commit -q -F $msgFile
	if ($LASTEXITCODE -ne 0) { throw "git commit a echoue" }
}
# (git ecrit sa progression sur stderr : ne pas y voir une erreur fatale)
$ErrorActionPreference = 'Continue'
& $git push origin main 2>&1 | ForEach-Object { "$_" }
$pushed = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($pushed -ne 0) { throw "git push a echoue" }

# 3. Export
$exe = Join-Path $build 'FerroArena.exe'
if (-not $SkipExport) {
	"== Export =="
	New-Item -ItemType Directory -Force $build | Out-Null
	# Start-Process -Wait : l'exe Godot est une appli fenetree, PowerShell ne l'attendrait pas sinon.
	Start-Process -FilePath $godot -ArgumentList '--headless','--path',"""$proj""",'--import' -Wait -NoNewWindow
	$p = Start-Process -FilePath $godot -ArgumentList '--headless','--path',"""$proj""",'--export-release','Windows',"""$exe""" -Wait -NoNewWindow -PassThru
	if ($p.ExitCode -ne 0 -or -not (Test-Path $exe)) { throw "L'export a echoue (code $($p.ExitCode))" }
	if (((Get-Date) - (Get-Item $exe).LastWriteTime).TotalMinutes -gt 10) { throw "L'export n'a pas produit de nouvel exe" }
}
if (-not (Test-Path $exe)) { throw "Pas d'exe : $exe" }

# 4. Zip
$zip = Join-Path $build 'FerroArena-windows.zip'
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -LiteralPath $exe -DestinationPath $zip -CompressionLevel Optimal
"{0} -> {1:N0} Mo" -f $zip, ((Get-Item $zip).Length / 1MB)

# 4b. Patchs incrementaux (FDL) : de chacune des 12 dernieres versions publiees vers celle-ci.
# Un joueur a jour d'une de ces versions telecharge quelques Mo au lieu de ~1 Go (voir updater.gd).
$archive = Join-Path (Split-Path $build -Parent) 'archive'
New-Item -ItemType Directory -Force $archive | Out-Null
$patches = @()
try {
	$src = [System.IO.File]::ReadAllText((Join-Path $proj 'scripts/util/fdl_source.gd'))
	$cs = [regex]::Match($src, 'r"""(.*?)"""', [System.Text.RegularExpressions.RegexOptions]::Singleline).Groups[1].Value
	$csPath = Join-Path $env:TEMP 'ferro_fdl.cs'
	[System.IO.File]::WriteAllText($csPath, $cs)
	if (-not ('Fdl' -as [type])) { Add-Type -Path $csPath }
	$olds = Get-ChildItem $archive -Filter 'FerroArena-*.exe' | Where-Object { $_.BaseName -ne "FerroArena-$ver" } |
		Sort-Object { [version]($_.BaseName -replace '^FerroArena-', '') } -Descending | Select-Object -First 12
	foreach ($o in $olds) {
		$from = $o.BaseName -replace '^FerroArena-', ''
		$out = Join-Path $build "FerroArena-patch-$from-to-$ver.fdl"
		"Patch $from -> $ver : " + [Fdl]::Create($o.FullName, $exe, $out)
		$patches += $out
	}
} catch { "Patchs incrementaux ignores : $($_.Exception.Message)" }
# Garde cette version comme base des prochains patchs (les 12 plus recentes).
Copy-Item -LiteralPath $exe -Destination (Join-Path $archive "FerroArena-$ver.exe") -Force
Get-ChildItem $archive -Filter 'FerroArena-*.exe' | Sort-Object { [version]($_.BaseName -replace '^FerroArena-', '') } -Descending | Select-Object -Skip 12 | Remove-Item -Force

# 5. Release GitHub (remplace celle du meme tag si elle existe)
# (gh ecrit sur stderr quand la release n'existe pas : ne pas laisser PowerShell y voir une erreur fatale)
$ErrorActionPreference = 'Continue'
& $gh release view $tag --repo $repo 2>$null | Out-Null
$exists = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = 'Stop'
if ($exists) {
	"== Release $tag existante : zip remplace =="
	& $gh release upload $tag $zip @patches --repo $repo --clobber
} else {
	"== Creation de la release $tag =="
	& $gh release create $tag $zip @patches --repo $repo --target main --title "Ferro Arena $tag" --notes $Message
}
if ($LASTEXITCODE -ne 0) { throw "La release a echoue" }
"Livre : https://github.com/$repo/releases/tag/$tag"
