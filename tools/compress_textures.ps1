# Passe les textures 3D importees en compression GPU (S3TC + mipmaps, 2048 max, normal maps en RGTC)
# et force leur reimport. Sans ca, Godot les garde "Lossless" (non compressees en memoire video)
# tant que l'editeur ne les a pas vues en 3D : x6 a x8 de VRAM.
#
#   powershell -File tools/compress_textures.ps1 [-Dir assets\props]
#   puis : Godot --headless --path . --import

param([string]$Dir = "assets")

$proj = Split-Path $PSScriptRoot -Parent
$n = 0
Get-ChildItem (Join-Path $proj $Dir) -Recurse -Filter *.import | Where-Object { $_.Name -match '\.(png|jpg|jpeg|webp)\.import$' -and $_.FullName -notmatch '\\mixamo\\textures\\' } | ForEach-Object {
	$c = [IO.File]::ReadAllText($_.FullName)
	if ($c -notmatch 'importer="texture"' -or $c -match '(?m)^compress/mode=2\s*$') { return }
	$src = $_.Name -replace '\.import$', ''
	$isNormal = $src -match '(?i)normal|_nor_gl|_nor_dx|_nrm'
	$set = @{ 'compress/mode' = '2'; 'compress/high_quality' = 'false'; 'mipmaps/generate' = 'true'; 'process/size_limit' = '2048'; 'compress/normal_map' = $(if ($isNormal) { '1' } else { '0' }); 'detect_3d/compress_to' = '0' }
	foreach ($k in $set.Keys) {
		$re = '(?m)^' + [regex]::Escape($k) + '=.*$'
		if ($c -match $re) { $c = [regex]::Replace($c, $re, "$k=$($set[$k])") } else { $c = $c -replace '(?m)^\[params\]\s*$', "[params]`n$k=$($set[$k])" }
	}
	[IO.File]::WriteAllText($_.FullName, $c, (New-Object Text.UTF8Encoding($false)))
	# Old import results out, so the next --import rebuilds them.
	foreach ($m in [regex]::Matches($c, 'res://\.godot/imported/[^"]+')) {
		$f = Join-Path $proj ($m.Value -replace '^res://', '' -replace '/', '\')
		foreach ($x in @($f, ($f -replace '\.[^.]+$', '.md5'))) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } }
	}
	$n++
}
"$n textures passees en compression GPU"
