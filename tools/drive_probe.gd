extends Node
## Lists the public Google Drive folder the updater downloads from, then its "bin" subfolder
## (name -> file id).
## Usage: Godot --path . -- --no_update --run_tool=res://tools/drive_probe.gd

const Updater := preload("res://scripts/autoload/updater.gd")


func _ready() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var folder: String = Updater.DRIVE_FOLDER
	for step in 2:
		http.request(Updater.DRIVE_LIST % folder, ["User-Agent: Mozilla/5.0"])
		var r: Array = await http.request_completed
		var files := Updater.parse_drive_folder((r[3] as PackedByteArray).get_string_from_utf8())
		print("[DRIVE] dossier %s (code %d) : %s" % [folder, r[1], str(files)])
		if not files.has(Updater.DRIVE_BIN):
			break
		folder = files[Updater.DRIVE_BIN]
	get_tree().quit()
