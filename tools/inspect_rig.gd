extends SceneTree
## Dev tool: dumps node tree, skeleton bones and animations of the Quaternius assets.

const FILES := [
	"res://assets/quaternius/characters/Superhero_Male_FullBody.gltf",
	"res://assets/quaternius/animations/UAL1_Standard.glb",
	"res://assets/quaternius/animations/UAL2_Standard.glb",
	"res://assets/quaternius/hair/Hair_Buzzed.gltf",
]


func _init() -> void:
	for path in FILES:
		print("\n######## ", path)
		var ps := load(path) as PackedScene
		var root := ps.instantiate()
		_tree(root, 0)
		for sk in root.find_children("*", "Skeleton3D", true, false):
			var s := sk as Skeleton3D
			var names := []
			for i in s.get_bone_count():
				names.append(s.get_bone_name(i))
			print("BONES(%d): %s" % [s.get_bone_count(), ", ".join(names)])
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			var p := ap as AnimationPlayer
			var list := []
			for a in p.get_animation_list():
				list.append("%s(%.2f%s)" % [a, p.get_animation(a).length, "L" if p.get_animation(a).loop_mode != 0 else ""])
			print("ANIMS(%d): %s" % [list.size(), ", ".join(list)])
			var first := p.get_animation(p.get_animation_list()[0])
			print("TRACK SAMPLE: ", first.track_get_path(0), " | ", first.track_get_path(1), " type=", first.track_get_type(0))
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var mats := []
			for i in m.mesh.get_surface_count():
				var mat := m.mesh.surface_get_material(i)
				mats.append(mat.resource_name if mat else "null")
			print("MESH %s aabb=%s skin=%s mats=%s" % [m.name, m.get_aabb(), m.skeleton, mats])
		root.free()
	quit()


func _tree(n: Node, d: int) -> void:
	if d > 4:
		return
	print("  ".repeat(d), n.name, " <", n.get_class(), ">")
	for c in n.get_children():
		if c is AnimationPlayer or c is Skeleton3D and d > 2:
			print("  ".repeat(d + 1), c.name, " <", c.get_class(), ">")
			continue
		_tree(c, d + 1)
