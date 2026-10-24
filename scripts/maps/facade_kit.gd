class_name FacadeKit
## Poly Haven modular facade kits (CC0): 3 x 3 m wall modules laid out in the
## glTF as an assembled showcase. Each module node's origin is its bottom-left
## corner on the facade plane; the front faces +Z, depth goes to -Z. A wall
## with an opening ("wall_window_centered_large_01") pairs with the window or
## door piece carrying the same family and number ("window_centered_large_01").
##
## Pieces are returned as [Mesh, Transform3D relative to the module origin].
## Everything is drawn through MultiMesh batches (see MapBase.batch).

const KITS := {
	"factory": "res://assets/polyhaven/models/modular_factory_facade/modular_factory_facade_2k.gltf",
	"apart": "res://assets/polyhaven/models/modular_urban_apartments_facade/modular_urban_apartments_facade_2k.gltf",
}
const MODULE := 3.0

## kit -> {node name: [Mesh, Transform3D (scene space)]}
static var _nodes := {}


static func _load(kit: String) -> Dictionary:
	if _nodes.has(kit):
		return _nodes[kit]
	var out := {}
	var ps := load(KITS[kit]) as PackedScene
	if ps:
		var inst := ps.instantiate()
		_collect(inst, Transform3D(), out)
		inst.free()
	_nodes[kit] = out
	return out


static func _collect(n: Node, xf: Transform3D, out: Dictionary) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out[String(n.name)] = [(n as MeshInstance3D).mesh, t]
	for c in n.get_children():
		_collect(c, t, out)


static func available(kit: String) -> bool:
	return not _load(kit).is_empty()


## Wall module + its infill (window / door piece) when `with_infill`.
static func module(kit: String, wall: String, with_infill := true) -> Array:
	var nodes := _load(kit)
	if not nodes.has(wall):
		return []
	var inv := _to_module(nodes, wall)
	var parts := [[nodes[wall][0], inv * (nodes[wall][1] as Transform3D)]]
	if with_infill:
		var infill := infill_name(wall)
		if infill != "" and nodes.has(infill):
			parts.append([nodes[infill][0], inv * (nodes[infill][1] as Transform3D)])
	return parts


## A strip piece (base / dado / cornice / crown) placed relative to its own origin.
static func piece(kit: String, name: String) -> Array:
	var nodes := _load(kit)
	if not nodes.has(name):
		return []
	return [[nodes[name][0], _to_module(nodes, name) * (nodes[name][1] as Transform3D)]]


static func infill_name(wall: String) -> String:
	return wall.trim_prefix("wall_") if wall.begins_with("wall_window") or wall.begins_with("wall_door") else ""


## Opening of a wall module in module space (x along the wall, y up), from its
## infill piece's bounds. Empty Rect2 when the module is solid.
static func opening(kit: String, wall: String) -> Rect2:
	var nodes := _load(kit)
	var infill := infill_name(wall)
	if infill == "" or not nodes.has(infill) or not nodes.has(wall):
		return Rect2()
	var b: AABB = _to_module(nodes, wall) * (nodes[infill][1] as Transform3D) * (nodes[infill][0] as Mesh).get_aabb()
	return Rect2(b.position.x, b.position.y, b.size.x, b.size.y)


## Scene space -> module space: the wall's bounds start at x = 0, y = 0
## (the kit's modules extend towards -X from their node origin).
static func _to_module(nodes: Dictionary, wall: String) -> Transform3D:
	var xf: Transform3D = nodes[wall][1]
	var b: AABB = xf * (nodes[wall][0] as Mesh).get_aabb()
	return Transform3D(Basis(), -Vector3(b.position.x, xf.origin.y, xf.origin.z))
