extends SceneTree
## Prints the Ferro's bounds in the gun frame (forward -Z, origin near the pistol grip).
## Usage: -s tools/gun_bounds.gd


func _init() -> void:
	var model := (load("res://assets/sketchfab/izh27/scene.gltf") as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.05, 0.115))
	model.transform = xf
	var total := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var gb := model.global_transform.affine_inverse() * mi.global_transform
		var bb := gb * mi.get_aabb()
		bb = xf * bb
		print("%s  pos=%s size=%s" % [mi.name, bb.position.snapped(Vector3.ONE * 0.01), bb.size.snapped(Vector3.ONE * 0.01)])
		total = bb if first else total.merge(bb)
		first = false
	print("TOTAL pos=%s size=%s" % [total.position.snapped(Vector3.ONE * 0.01), total.size.snapped(Vector3.ONE * 0.01)])
	quit()
