extends Node
## Auto-update at launch (exported Windows build): asks GitHub for the latest
## release, and if it is newer than Game.GAME_VERSION downloads its zip, then a
## small PowerShell script swaps the files once the game has closed and
## relaunches it. Any failure (offline, no release...) is silent: the game just
## starts as usual.
##
## Incremental updates: when the release carries "FerroArena-patch-<installed>-to-<new>.fdl"
## (tools/release.ps1 builds one from each of the last 3 versions), only that patch (a few MB)
## is downloaded and applied to the exe; otherwise (older install, failed patch) the full zip.
##
## Publishing: create a GitHub release tagged "v<GAME_VERSION>" (e.g. v0.14.1)
## with the zip of the exported build attached (tools/release.ps1).
##
## Downloads come from the "bin" subfolder of the public Google Drive folder (ferroarena.jrjx.me
## redirects to it) when it holds this version's files, named "FerroArena-<version>.zip" and
## "FerroArena-patch-<installed>-to-<version>.fdl" (tools/release.ps1 prepares them in
## build/drive); GitHub only says which version is the latest. A file missing from the Drive, or
## a Drive download that fails (quota, warning page...), falls back to the GitHub asset.

const REPO := "Jorje13/ferroarena"
const API_URL := "https://api.github.com/repos/%s/releases/latest" % REPO
const DOWNLOAD_PREFIX := "https://github.com/" + REPO + "/"
const DRIVE_FOLDER := "1aaKtSDXoBh6joYYXSfmRHfP_pgy1-QNa"
## Public folder listing (no API key): one "entry-<file id>" block per file / subfolder, with its title.
const DRIVE_LIST := "https://drive.google.com/embeddedfolderview?id=%s"
## Subfolder (looked up by name) that holds the builds.
const DRIVE_BIN := "bin"
## Direct download; confirm=t skips the "too big to scan for viruses" page.
const DRIVE_FILE := "https://drive.usercontent.google.com/download?id=%s&export=download&confirm=t"
const DIR := "user://update"

var _http: HTTPRequest
var _layer: CanvasLayer
var _title: Label
var _sub: Label
var _bar: ProgressBar
var _zip_path := ""
var _downloading := false
var _new_version := ""
## Incremental update: a small FDL patch (see FdlSource) applied to the installed exe.
var _patch := false
var _patch_path := ""
## GitHub assets of the new version, the fallback when the Drive can't serve them.
var _gh_zip := ""
var _gh_patch := ""
var _from_drive := false
var _force_full := false
var _in_bin := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var debug := Game.debug
	if debug.has("no_update"):
		return
	# Only installed builds update themselves (the editor / `godot --path` runs source files).
	if not OS.has_feature("template") and not debug.has("update_test"):
		return
	if OS.get_name() != "Windows":
		return
	_http = HTTPRequest.new()
	# Threaded and without a timeout: the menu's background map is built on the main
	# thread right after launch and freezes it for a few seconds, which made a
	# main-thread request "time out" before its answer was even read.
	_http.use_threads = true
	_http.timeout = 0.0
	add_child(_http)
	_http.request_completed.connect(_on_release_info)
	var err := _http.request(API_URL, ["Accept: application/vnd.github+json", "User-Agent: FerroArena/%s" % Game.GAME_VERSION])
	if err != OK:
		print("[UPDATE] requête impossible (%d)" % err)


func _process(_delta: float) -> void:
	if _downloading and _http and _layer:
		var total := _http.get_body_size()
		var got := _http.get_downloaded_bytes()
		if total > 0:
			_bar.value = float(got) / total * 100.0
			_sub.text = "%.0f / %.0f Mo" % [got / 1048576.0, total / 1048576.0]
		else:
			_sub.text = "%.0f Mo" % (got / 1048576.0)


## "v0.14.1" / "0.14.1" -> [0, 14, 1]
static func parse_version(v: String) -> Array:
	var out := []
	for p in v.trim_prefix("v").split(".", false):
		out.append(int(p))
	while out.size() < 3:
		out.append(0)
	return out


static func is_newer(remote: String, local: String) -> bool:
	var a := parse_version(remote)
	var b := parse_version(local)
	for i in 3:
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


func _on_release_info(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_release_info)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[UPDATE] pas de version récupérée (résultat %d, code %d)" % [result, code])
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary):
		return
	var tag := str(info.get("tag_name", ""))
	if not is_newer(tag, Game.GAME_VERSION):
		print("[UPDATE] à jour (%s, dernière version %s)" % [Game.GAME_VERSION, tag])
		return
	var url := ""
	var patch_url := ""
	var want_patch := "-patch-%s-to-%s.fdl" % [Game.GAME_VERSION, tag.trim_prefix("v")]
	for a in info.get("assets", []):
		var n := str(a.get("name", ""))
		var u := str(a.get("browser_download_url", ""))
		if not u.begins_with(DOWNLOAD_PREFIX):
			continue
		if n.to_lower().ends_with(".zip") and url == "":
			url = u
		elif n.ends_with(want_patch):
			patch_url = u
	# A patch that failed once is not tried again: the full zip is downloaded instead.
	var flag := ProjectSettings.globalize_path(DIR + "/force_full")
	if FileAccess.file_exists(flag):
		DirAccess.remove_absolute(flag)
		patch_url = ""
		_force_full = true
	_gh_zip = url
	_gh_patch = patch_url
	_new_version = tag
	# Same choice on the Drive: this version's patch from the installed one, else its zip.
	_drive_get(DRIVE_FOLDER)


func _drive_get(folder: String) -> void:
	_http.request_completed.connect(_on_drive_list)
	if _http.request(DRIVE_LIST % folder, ["User-Agent: Mozilla/5.0 FerroArena/%s" % Game.GAME_VERSION]) != OK:
		_http.request_completed.disconnect(_on_drive_list)
		_on_drive_list(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


## Drive folder listing -> {file name: file id}.
static func parse_drive_folder(html: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string("id=\"entry-([A-Za-z0-9_-]+)\".*?flip-entry-title\">([^<]+)<")
	for m in re.search_all(html):
		out[m.get_string(2).strip_edges()] = m.get_string(1)
	return out


func _on_drive_list(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _http.request_completed.is_connected(_on_drive_list):
		_http.request_completed.disconnect(_on_drive_list)
	var files := parse_drive_folder(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else {}
	if not _in_bin:
		_in_bin = true
		if files.has(DRIVE_BIN):
			_drive_get(files[DRIVE_BIN])
			return
		files = {}
	var ver := _new_version.trim_prefix("v")
	var drive_patch: String = files.get("FerroArena-patch-%s-to-%s.fdl" % [Game.GAME_VERSION, ver], "")
	var drive_zip: String = files.get("FerroArena-%s.zip" % ver, "")
	if _force_full:
		drive_patch = ""
	var url := ""
	if _gh_patch != "" or drive_patch != "":
		_patch = true
		url = DRIVE_FILE % drive_patch if drive_patch != "" else _gh_patch
	else:
		url = DRIVE_FILE % drive_zip if drive_zip != "" else _gh_zip
	_from_drive = url.begins_with("https://drive.")
	if url == "":
		print("[UPDATE] %s n'a pas de zip téléchargeable" % _new_version)
		return
	print("[UPDATE] nouvelle version %s -> téléchargement %s (%s)" % [_new_version, "du patch" if _patch else "complet", "Google Drive" if _from_drive else "GitHub"])
	_build_overlay(_new_version)
	_download(url)


func _download(url: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_zip_path = ProjectSettings.globalize_path(DIR + ("/patch.fdl" if _patch else "/FerroArena.zip"))
	_http.download_file = _zip_path
	_http.timeout = 0.0
	_http.body_size_limit = -1
	if not _http.request_completed.is_connected(_on_downloaded):
		_http.request_completed.connect(_on_downloaded)
	_downloading = true
	var err := _http.request(url, ["User-Agent: Mozilla/5.0 FerroArena/%s" % Game.GAME_VERSION])
	if err != OK:
		_fail("téléchargement impossible (%d)" % err)


## The file really is a zip ("PK") / an FDL patch (gzip stream, 1F 8B; "FDL1" is inside it), not a
## Drive error or warning page.
func _valid_download() -> bool:
	var f := FileAccess.open(_zip_path, FileAccess.READ)
	if f == null or f.get_length() < 16:
		return false
	var head := f.get_buffer(4)
	f.close()
	if _patch:
		return head[0] == 0x1F and head[1] == 0x8B
	return head[0] == 0x50 and head[1] == 0x4B


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_downloading = false
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200 and _valid_download()
	if not ok and _from_drive:
		# Drive refused (quota, removed file, warning page): same file from GitHub instead.
		var gh := _gh_patch if _patch else _gh_zip
		if _patch and gh == "":
			_patch = false
			gh = _gh_zip
		print("[UPDATE] Google Drive indisponible (résultat %d, code %d) -> GitHub" % [result, code])
		_from_drive = false
		if gh != "":
			_download(gh)
			return
	if not ok:
		_fail("téléchargement échoué (résultat %d, code %d)" % [result, code])
		return
	_title.text = "INSTALLATION…"
	_sub.text = "Le jeu va redémarrer"
	_bar.value = 100.0
	var script := ProjectSettings.globalize_path(DIR + "/apply_update.ps1")
	var f := FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		_fail("script d'installation impossible à écrire")
		return
	f.store_string(APPLY_SCRIPT)
	f.close()
	var args := ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script,
		"-GamePid", str(OS.get_process_id()), "-Install", OS.get_executable_path().get_base_dir(), "-Exe", OS.get_executable_path()]
	if _patch:
		var cs_path := ProjectSettings.globalize_path(DIR + "/fdl.cs")
		var cf := FileAccess.open(cs_path, FileAccess.WRITE)
		if cf == null:
			_fail("patch impossible à préparer")
			return
		cf.store_string(FdlSource.SOURCE)
		cf.close()
		args.append_array(["-Delta", _zip_path, "-Cs", cs_path])
	else:
		args.append_array(["-Zip", _zip_path])
	var exe := OS.get_executable_path()
	var pid := OS.create_process("powershell.exe", args)
	if pid <= 0:
		_fail("installation impossible à lancer")
		return
	print("[UPDATE] installation de %s (script %d)" % [_new_version, pid])
	# Give the overlay a frame, then close so the script can replace the exe.
	await get_tree().create_timer(0.6).timeout
	get_tree().quit()


func _fail(msg: String) -> void:
	print("[UPDATE] ", msg)
	_downloading = false
	if _layer:
		_layer.queue_free()
		_layer = null
	var f := ProjectSettings.globalize_path(_zip_path) if _zip_path != "" else ""
	if f != "" and FileAccess.file_exists(f):
		DirAccess.remove_absolute(f)


func _build_overlay(tag: String) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.03, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 12)
	bg.add_child(box)
	_title = Label.new()
	_title.text = "MISE À JOUR %s" % tag.to_upper()
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.98, 0.74, 0.22))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 14)
	_bar.show_percentage = false
	box.add_child(_bar)
	_sub = Label.new()
	_sub.text = "Téléchargement…"
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	box.add_child(_sub)


## Runs after the game has closed. Patch (-Delta): rebuild the exe from the old one with
## Fdl.Apply (checked by SHA-256), swap it in. Zip (-Zip): unpack and copy over the install
## folder. Either way the game is relaunched; if a patch fails the old exe is kept and
## "force_full" tells the next launch to download the whole zip instead.
const APPLY_SCRIPT := """param([int]$GamePid, [string]$Install, [string]$Exe, [string]$Zip = '', [string]$Delta = '', [string]$Cs = '')
$ErrorActionPreference = 'Continue'
$work = if ($Delta -ne '') { Split-Path $Delta } else { Split-Path $Zip }
$log = Join-Path $work 'update.log'
try { Wait-Process -Id $GamePid -Timeout 60 -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Milliseconds 700
try {
	if ($Delta -ne '') {
		Add-Type -Path $Cs
		$new = $Exe + '.new'
		[Fdl]::Apply($Exe, $Delta, $new)
		Move-Item -LiteralPath $Exe -Destination ($Exe + '.old') -Force
		Move-Item -LiteralPath $new -Destination $Exe -Force
		Remove-Item -LiteralPath ($Exe + '.old') -Force
		Remove-Item -LiteralPath $Delta -Force
		'ok patch ' + (Get-Date) | Out-File $log
	} else {
		$tmp = Join-Path $work 'extract'
		if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
		Expand-Archive -LiteralPath $Zip -DestinationPath $tmp -Force
		$src = $tmp
		$items = @(Get-ChildItem $tmp)
		if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $src = $items[0].FullName }
		Copy-Item -Path (Join-Path $src '*') -Destination $Install -Recurse -Force
		Remove-Item $tmp -Recurse -Force
		Remove-Item $Zip -Force
		'ok ' + (Get-Date) | Out-File $log
	}
} catch {
	('erreur: ' + $_.Exception.Message) | Out-File $log
	if ($Delta -ne '') {
		if (-not (Test-Path -LiteralPath $Exe) -and (Test-Path -LiteralPath ($Exe + '.old'))) { Move-Item -LiteralPath ($Exe + '.old') -Destination $Exe -Force }
		if (Test-Path -LiteralPath ($Exe + '.new')) { Remove-Item -LiteralPath ($Exe + '.new') -Force }
		'1' | Out-File (Join-Path $work 'force_full')
	}
}
Start-Process -FilePath $Exe
"""