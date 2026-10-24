extends SceneTree
func _init() -> void:
	for n in ["ual1", "ual2"]:
		var lib := CharacterModel.library(n)
		var names := []
		for a in lib.get_animation_list():
			names.append("%s(%.2f)" % [a, lib.get_animation(a).length])
		print(n, ": ", ", ".join(names))
	quit()