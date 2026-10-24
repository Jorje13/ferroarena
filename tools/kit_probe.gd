extends SceneTree
## Prints facade-kit openings and module parts (debug). Usage: -s tools/kit_probe.gd

func _init() -> void:
	for w in ["wall_standard_standard_01", "wall_window_centered_large_01", "wall_door_centered_large_01"]:
		print(w, " opening=", FacadeKit.opening("factory", w), " parts=", FacadeKit.module("factory", w, true).size())
		for p in FacadeKit.module("factory", w, true):
			var m: Mesh = p[0]
			print("   aabb=", (p[1] as Transform3D) * m.get_aabb(), " surfaces=", m.get_surface_count(), " mat=", m.surface_get_material(0).resource_name if m.surface_get_material(0) else "none",
				" cull=", (m.surface_get_material(0) as BaseMaterial3D).cull_mode if m.surface_get_material(0) is BaseMaterial3D else -1)
	quit()
