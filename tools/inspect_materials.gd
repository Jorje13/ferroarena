extends SceneTree
## Prints each mesh surface's material name / type / albedo texture of a scene.
## Usage: -s tools/inspect_materials.gd -- --scene=res://...

func _init() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.substr(8)
	var scene := (load(path) as PackedScene).instantiate()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var tex := ""
			if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
				tex = (m as BaseMaterial3D).albedo_texture.resource_path
			print("%s surf%d mat=%s (%s) tex=%s tris=%d" % [mi.name, s, m.resource_name if m else "-", m.get_class() if m else "-", tex, mi.mesh.surface_get_array_index_len(s) / 3])
	quit()
