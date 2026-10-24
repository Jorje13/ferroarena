class_name ArmorKit
## Customisable raider outfit: catalogue, colour palettes, and the builders that
## assemble each armour piece on a CharacterRig (bone attachments).
## Pieces are authored in model space relative to their bone: +Z = front,
## +Y = up, -X = the raider's right side. Team colour stays on the glowing
## accents (helmet, chest light, armband, pack) so teams remain readable.

const HELMETS := ["Aucun", "Éclaireur", "Intégral", "Capuche & masque", "Casque radio"]
const CHESTS := ["Harnais", "Porte-plaques", "Armure lourde", "Gilet tactique"]
const PACKS := ["Aucun", "Sac à armature", "Sac d'assaut", "Bonbonnes"]
const LEGS := ["Légères", "Standard", "Blindées"]
const BODIES := ["Homme", "Femme"]
const PATTERNS := ["Uni", "Usé", "Camouflage", "Digital", "Rayures"]

const SUIT_COLORS := [
	["Ocre", Color(0.86, 0.58, 0.14)], ["Sable", Color(0.72, 0.62, 0.44)], ["Olive", Color(0.36, 0.4, 0.22)],
	["Bleu nuit", Color(0.15, 0.22, 0.38)], ["Brique", Color(0.55, 0.2, 0.14)], ["Blanc cassé", Color(0.85, 0.83, 0.78)],
	["Anthracite", Color(0.18, 0.18, 0.19)], ["Sarcelle", Color(0.12, 0.38, 0.4)], ["Orange", Color(0.95, 0.42, 0.1)],
	["Gris", Color(0.45, 0.46, 0.47)],
]
const ARMOR_COLORS := [
	["Crème", Color(0.82, 0.76, 0.62)], ["Acier", Color(0.42, 0.44, 0.46)], ["Noir", Color(0.1, 0.1, 0.11)],
	["Olive", Color(0.33, 0.36, 0.22)], ["Sable", Color(0.7, 0.6, 0.42)], ["Rouge", Color(0.6, 0.15, 0.12)],
	["Bleu", Color(0.2, 0.3, 0.5)], ["Jaune", Color(0.9, 0.72, 0.15)], ["Blanc", Color(0.9, 0.9, 0.88)],
	["Orange", Color(0.9, 0.45, 0.12)],
]
const FABRIC_COLORS := [
	["Toile", Color(0.78, 0.72, 0.5)], ["Olive", Color(0.5, 0.54, 0.35)], ["Noir", Color(0.22, 0.22, 0.22)],
	["Gris", Color(0.52, 0.52, 0.52)], ["Coyote", Color(0.62, 0.48, 0.32)], ["Bleu", Color(0.3, 0.38, 0.52)],
]

## Slot key -> number of options (for UI / validation).
const SLOTS := {
	"body": 2, "helmet": 5, "chest": 4, "pack": 4, "legs": 3,
	"suit": 10, "fabric": 6, "armor": 10, "pattern": 5,
	"skin": 6, "weapon": 3,
}
const SKINS := ["Soldat", "Cybernétique", "Sentinelle", "Rôdeur", "Spectre", "Porteur"]
const WEAPONS := ["Longshot", "IZH-27", "Fusil à vapeur"]


static func default_loadout() -> Dictionary:
	return {"body": 0, "helmet": 1, "chest": 1, "pack": 1, "legs": 1, "suit": 0, "fabric": 0, "armor": 0, "pattern": 1,
		"skin": 0, "weapon": 0}


static func sanitize(l: Variant) -> Dictionary:
	var out := default_loadout()
	if l is Dictionary:
		for k in SLOTS:
			if l.has(k):
				out[k] = clampi(int(l[k]), 0, SLOTS[k] - 1)
	return out


static func random_loadout(seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var l := {}
	for k in SLOTS:
		l[k] = r.randi_range(0, SLOTS[k] - 1)
	if r.randf() < 0.85 and l.helmet == 0:
		l.helmet = r.randi_range(1, 4)
	return l


static func option_name(slot: String, idx: int) -> String:
	match slot:
		"body": return BODIES[idx]
		"skin": return SKINS[idx]
		"weapon": return WEAPONS[idx]
		"helmet": return HELMETS[idx]
		"chest": return CHESTS[idx]
		"pack": return PACKS[idx]
		"legs": return LEGS[idx]
		"pattern": return PATTERNS[idx]
		"suit": return SUIT_COLORS[idx][0]
		"armor": return ARMOR_COLORS[idx][0]
		"fabric": return FABRIC_COLORS[idx][0]
	return str(idx)


static func suit_color(l: Dictionary) -> Color:
	return SUIT_COLORS[l.suit][1]


static func armor_color(l: Dictionary) -> Color:
	return ARMOR_COLORS[l.armor][1]


static func fabric_color(l: Dictionary) -> Color:
	return FABRIC_COLORS[l.fabric][1]


# ================================================================ building

class Kit:
	var r # CharacterRig (untyped: avoids a cyclic class reference)
	var armor: Material
	var armor_dark: Material
	var fabric: Material
	var fabric_dark: Material
	var leather: Material
	var metal: Material
	var rubber: Material
	var glow: Material
	var glass: Material
	var team_cloth: Material


static func build(rig: Node3D, l: Dictionary, accent: Color) -> void:
	var k := Kit.new()
	k.r = rig
	var ac: Color = ARMOR_COLORS[l.armor][1]
	var fc: Color = FABRIC_COLORS[l.fabric][1]
	k.armor = Mats.armor(ac, l.pattern)
	k.armor_dark = Mats.armor(ac.darkened(0.45), 0)
	k.fabric = Mats.pbr_local("rough_linen", fc, 4.0, "fab_%s" % fc.to_html())
	k.fabric_dark = Mats.pbr_local("rough_linen", fc.darkened(0.35), 4.0, "fabd_%s" % fc.to_html())
	k.leather = Mats.pbr_local("brown_leather", Color(0.42, 0.36, 0.3), 3.0, "strap")
	k.metal = Mats.gun_metal()
	k.rubber = Mats.rubber()
	k.glow = Mats.emissive("glow_%s" % accent.to_html(), accent, 2.5, false)
	k.glass = Mats.flat("visor_glass", Color(0.03, 0.04, 0.05), 0.08, 0.7)
	k.team_cloth = Mats.canvas("teamcloth_%s" % accent.to_html(), accent)
	_base(k)
	match int(l.helmet):
		1: _helmet_scout(k)
		2: _helmet_full(k)
		3: _helmet_hood(k)
		4: _helmet_radio(k)
	match int(l.chest):
		0: _chest_harness(k)
		1: _chest_carrier(k)
		2: _chest_heavy(k)
		3: _chest_vest(k)
	match int(l.legs):
		0: _legs_light(k)
		1: _legs_standard(k)
		2: _legs_armored(k)
	rig.pack = Node3D.new()
	rig.pack.top_level = true
	rig.add_child(rig.pack)
	var p := Node3D.new()
	rig.pack.add_child(p)
	match int(l.pack):
		1: _pack_frame(k, p)
		2: _pack_assault(k, p)
		3: _pack_tanks(k, p)


static func _rb(size: Vector3, rad: float) -> ArrayMesh:
	return Shapes.rounded_box(size, rad)


## Always worn: boots, neck gaiter, team armband.
static func _base(k: Kit) -> void:
	var r = k.r
	for side in ["r", "l"]:
		var foot = r._attach("foot_" + side)
		r._mesh(foot, _rb(Vector3(0.125, 0.12, 0.29), 0.035), Mats.pbr_local("brown_leather", Color(0.28, 0.24, 0.2), 3.0, "boot"), Vector3(0, -0.035, 0.045))
		r._mesh(foot, _rb(Vector3(0.13, 0.03, 0.3), 0.012), k.rubber, Vector3(0, -0.095, 0.045))
		r._mesh(foot, _rb(Vector3(0.115, 0.05, 0.03), 0.01), k.leather, Vector3(0, 0.005, 0.12))
	var neck = r._attach("neck_01")
	r._mesh(neck, r._cyl(0.072, 0.09), k.fabric, Vector3(0, 0.02, 0.005), Vector3(1.0, 1.0, 1.1))
	var arm = r._attach("upperarm_r")
	r._mesh(arm, r._cyl(0.066, 0.06), k.team_cloth, Vector3(-0.15, 0.0, 0.0), Vector3.ONE, Basis(Vector3.BACK, PI / 2))


# ---------------------------------------------------------------- helmets

static func _helmet_scout(k: Kit) -> void:
	var r = k.r
	var head = r._attach("Head")
	r._mesh(head, Shapes.shell(Vector3(0.142, 0.135, 0.158), -PI, PI, 0.0, 1.5, 0.012, 28, 9), k.armor, Vector3(0, 0.095, -0.01))
	r._mesh(head, Shapes.shell(Vector3(0.165, 0.04, 0.18), -PI, PI, 1.42, 1.62, 0.01, 28, 2), k.armor, Vector3(0, 0.1, -0.01))
	r._mesh(head, _rb(Vector3(0.022, 0.012, 0.2), 0.005), k.glow, Vector3(0, 0.232, -0.02))
	for x in [-0.125, 0.125]:
		r._mesh(head, r._cyl(0.052, 0.04), k.fabric_dark, Vector3(x, 0.06, -0.005), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
		r._mesh(head, r._cyl(0.03, 0.045), k.metal, Vector3(x * 1.06, 0.06, -0.005), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
	# Goggles pushed up on the shell
	r._mesh(head, _rb(Vector3(0.22, 0.028, 0.03), 0.01), k.leather, Vector3(0, 0.168, 0.1), Vector3.ONE, Basis(Vector3.RIGHT, -0.5))
	for x in [-0.045, 0.045]:
		r._mesh(head, r._cyl(0.028, 0.03), k.metal, Vector3(x, 0.178, 0.122), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2 - 0.5))
		r._mesh(head, r._cyl(0.022, 0.032), k.glass, Vector3(x, 0.182, 0.128), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2 - 0.5))


static func _helmet_full(k: Kit) -> void:
	var r = k.r
	var head = r._attach("Head")
	var rad := Vector3(0.152, 0.16, 0.168)
	var c := Vector3(0, 0.1, -0.005)
	r._mesh(head, Shapes.shell(rad, -PI, PI, 0.0, 1.5, 0.014, 28, 9), k.armor, c)
	r._mesh(head, Shapes.shell(rad, 0.95, TAU - 0.95, 1.5, 2.3, 0.014, 20, 5), k.armor, c)
	# Jaw guard + visor
	r._mesh(head, Shapes.shell(rad * 1.02, -0.95, 0.95, 1.95, 2.3, 0.012, 12, 3), k.armor_dark, c)
	r._mesh(head, Shapes.shell(rad * 1.04, -0.95, 0.95, 1.08, 1.95, 0.008, 14, 6), k.glass, c)
	r._mesh(head, Shapes.shell(rad * 1.05, -0.97, 0.97, 1.03, 1.09, 0.006, 14, 1), k.glow, c)
	r._mesh(head, _rb(Vector3(0.035, 0.03, 0.26), 0.012), k.armor_dark, Vector3(0, 0.255, -0.02))
	r._mesh(head, r._cyl(0.035, 0.05), k.armor_dark, Vector3(-0.155, 0.08, -0.01), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
	r._mesh(head, r._sphere(0.012), k.glow, Vector3(-0.182, 0.08, -0.01))


static func _helmet_hood(k: Kit) -> void:
	var r = k.r
	var head = r._attach("Head")
	r._mesh(head, Shapes.shell(Vector3(0.168, 0.182, 0.178), 0.8, TAU - 0.8, 0.0, 2.2, 0.012, 24, 10), k.fabric, Vector3(0, 0.085, -0.02))
	r._mesh(head, Shapes.shell(Vector3(0.22, 0.13, 0.2), 1.25, TAU - 1.25, 1.55, 2.3, 0.012, 16, 4), k.fabric, Vector3(0, -0.04, -0.03))
	# Respirator
	r._mesh(head, _rb(Vector3(0.1, 0.075, 0.07), 0.025), k.rubber, Vector3(0, 0.035, 0.1))
	for x in [-0.058, 0.058]:
		var f := Basis(Vector3.UP, 0.6 * signf(x)) * Basis(Vector3.RIGHT, PI / 2)
		r._mesh(head, r._cyl(0.03, 0.05), k.armor, Vector3(x, 0.02, 0.125), Vector3.ONE, f)
		r._mesh(head, r._cyl(0.026, 0.008), k.metal, Vector3(x * 1.2, 0.02, 0.145), Vector3.ONE, f)
		# Eye lenses
		var lens := Basis(Vector3.RIGHT, PI / 2)
		r._mesh(head, r._cyl(0.03, 0.016), k.metal, Vector3(x * 0.62, 0.11, 0.1), Vector3.ONE, lens)
		r._mesh(head, r._cyl(0.025, 0.018), k.glass, Vector3(x * 0.62, 0.11, 0.104), Vector3.ONE, lens)
	r._mesh(head, r._sphere(0.01), k.glow, Vector3(0, 0.075, 0.137))


static func _helmet_radio(k: Kit) -> void:
	var r = k.r
	var head = r._attach("Head")
	r._mesh(head, Shapes.shell(Vector3(0.132, 0.125, 0.145), -PI, PI, 0.0, 1.42, 0.01, 24, 8), k.fabric_dark, Vector3(0, 0.1, -0.01))
	r._mesh(head, _rb(Vector3(0.15, 0.012, 0.085), 0.006), k.fabric_dark, Vector3(0, 0.115, 0.15), Vector3.ONE, Basis(Vector3.RIGHT, 0.18))
	r._mesh(head, Shapes.shell(Vector3(0.15, 0.15, 0.03), -PI, PI, 0.0, 1.45, 0.012, 20, 6), k.armor, Vector3(0, 0.07, 0.0), Vector3.ONE, Basis(Vector3.UP, PI / 2))
	for x in [-0.13, 0.13]:
		r._mesh(head, r._cyl(0.06, 0.05), k.armor, Vector3(x, 0.07, 0.0), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
		r._mesh(head, r._cyl(0.045, 0.052), k.rubber, Vector3(x * 0.97, 0.07, 0.0), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
		r._mesh(head, r._sphere(0.01), k.glow, Vector3(x * 1.2, 0.1, 0.03))
	# Mic boom + antenna
	r._mesh(head, r._cyl(0.006, 0.16), k.metal, Vector3(-0.13, 0.035, 0.075), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.FORWARD, 0.2))
	r._mesh(head, r._sphere(0.014), k.rubber, Vector3(-0.115, 0.02, 0.155))
	r._mesh(head, r._cyl(0.004, 0.32), k.metal, Vector3(0.16, 0.24, -0.04), Vector3.ONE, Basis(Vector3.BACK, -0.15))
	r._mesh(head, r._sphere(0.008), k.glow, Vector3(0.184, 0.4, -0.04))


# ---------------------------------------------------------------- chests

const TORSO_R := Vector3(0.19, 0.28, 0.16)
const TORSO_C := Vector3(0, 0.05, 0.0)


static func _shoulder_straps(k: Kit, chest: Node3D) -> void:
	var r = k.r
	for x in [-0.1, 0.1]:
		r._mesh(chest, _rb(Vector3(0.055, 0.03, 0.3), 0.01), k.leather, Vector3(x, 0.2, 0.02), Vector3.ONE, Basis(Vector3.RIGHT, 0.25))


static func _belt(k: Kit, pouches: bool) -> void:
	var r = k.r
	var hips = r._attach("pelvis")
	r._mesh(hips, Shapes.shell(Vector3(0.19, 0.05, 0.15), -PI, PI, 1.35, 1.8, 0.012, 24, 2), k.leather, Vector3(0, 0.07, -0.01))
	r._mesh(hips, _rb(Vector3(0.05, 0.035, 0.02), 0.006), k.metal, Vector3(0, 0.07, 0.145))
	if pouches:
		for x in [-0.17, 0.17]:
			r._mesh(hips, _rb(Vector3(0.06, 0.1, 0.11), 0.018), k.fabric_dark, Vector3(x, -0.0, 0.0))
		r._mesh(hips, r._cyl(0.045, 0.14), k.metal, Vector3(-0.13, -0.01, -0.12))


static func _chest_harness(k: Kit) -> void:
	var r = k.r
	var chest = r._attach("spine_03")
	_shoulder_straps(k, chest)
	r._mesh(chest, _rb(Vector3(0.3, 0.035, 0.02), 0.008), k.leather, Vector3(0, -0.02, 0.13))
	r._mesh(chest, _rb(Vector3(0.07, 0.1, 0.045), 0.015), k.fabric_dark, Vector3(0.1, 0.06, 0.155))
	r._mesh(chest, r._sphere(0.012), k.glow, Vector3(-0.08, 0.08, 0.145))
	_belt(k, true)


static func _chest_carrier(k: Kit) -> void:
	var r = k.r
	var chest = r._attach("spine_03")
	r._mesh(chest, Shapes.shell(TORSO_R + Vector3(0.0, 0.0, 0.01), -0.85, 0.85, 1.05, 2.05, 0.018, 14, 9), k.armor, TORSO_C)
	r._mesh(chest, Shapes.shell(TORSO_R + Vector3(0.0, 0.0, 0.01), PI - 0.85, PI + 0.85, 1.05, 2.05, 0.018, 14, 9), k.armor, TORSO_C)
	r._mesh(chest, Shapes.shell(TORSO_R, 0.85, PI - 0.85, 1.45, 2.05, 0.02, 8, 4), k.fabric_dark, TORSO_C)
	r._mesh(chest, Shapes.shell(TORSO_R, PI + 0.85, TAU - 0.85, 1.45, 2.05, 0.02, 8, 4), k.fabric_dark, TORSO_C)
	for x in [-0.09, 0.0, 0.09]:
		r._mesh(chest, _rb(Vector3(0.075, 0.1, 0.05), 0.014), k.fabric, Vector3(x, -0.13, 0.17))
		r._mesh(chest, _rb(Vector3(0.078, 0.025, 0.055), 0.008), k.fabric_dark, Vector3(x, -0.085, 0.172))
	r._mesh(chest, _rb(Vector3(0.05, 0.015, 0.012), 0.004), k.glow, Vector3(0.0, 0.16, 0.168))
	_shoulder_straps(k, chest)
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var arm = r._attach("upperarm_" + side)
		r._mesh(arm, _rb(Vector3(0.11, 0.05, 0.13), 0.022), k.armor, Vector3(0.07 * sx, 0.06, 0.0))
	_belt(k, true)


static func _chest_heavy(k: Kit) -> void:
	var r = k.r
	var chest = r._attach("spine_03")
	var tr := TORSO_R + Vector3(0.015, 0.01, 0.02)
	r._mesh(chest, Shapes.shell(tr, -0.95, 0.95, 1.0, 1.95, 0.022, 16, 9), k.armor, TORSO_C)
	r._mesh(chest, Shapes.shell(tr * 1.04, -0.75, 0.75, 1.0, 1.4, 0.016, 12, 4), k.armor_dark, TORSO_C)
	r._mesh(chest, Shapes.shell(tr, PI - 0.95, PI + 0.95, 1.0, 1.95, 0.022, 16, 9), k.armor, TORSO_C)
	for i in 2:
		var t0 := 1.97 + i * 0.13
		r._mesh(chest, Shapes.shell(tr * (0.98 - i * 0.02), -0.8, 0.8, t0, t0 + 0.11, 0.014, 12, 2), k.armor_dark, TORSO_C)
	r._mesh(chest, Shapes.shell(TORSO_R, 0.95, PI - 0.95, 1.2, 2.0, 0.02, 8, 5), k.fabric_dark, TORSO_C)
	r._mesh(chest, Shapes.shell(TORSO_R, PI + 0.95, TAU - 0.95, 1.2, 2.0, 0.02, 8, 5), k.fabric_dark, TORSO_C)
	r._mesh(chest, _rb(Vector3(0.12, 0.02, 0.012), 0.006), k.glow, Vector3(0.0, 0.0, 0.205))
	var neck = r._attach("neck_01")
	var collar := TorusMesh.new()
	collar.inner_radius = 0.075
	collar.outer_radius = 0.11
	collar.rings = 20
	collar.ring_segments = 8
	r._mesh(neck, collar, k.armor_dark, Vector3(0, -0.03, 0.0), Vector3(1.05, 0.6, 1.0))
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var arm = r._attach("upperarm_" + side)
		var tilt := Basis(Vector3.FORWARD, 0.45 * sx)
		r._mesh(arm, Shapes.shell(Vector3(0.11, 0.09, 0.115), -PI, PI, 0.0, 1.35, 0.015, 18, 6), k.armor, Vector3(0.06 * sx, 0.035, 0.0), Vector3.ONE, tilt)
		r._mesh(arm, Shapes.shell(Vector3(0.105, 0.07, 0.11), -PI, PI, 1.0, 1.55, 0.012, 18, 2), k.armor_dark, Vector3(0.1 * sx, -0.005, 0.0), Vector3.ONE, tilt)
		var fore = r._attach("lowerarm_" + side)
		r._mesh(fore, Shapes.shell(Vector3(0.055, 0.12, 0.055), -PI, PI, 0.6, 2.5, 0.01, 14, 6), k.armor_dark, Vector3(0.12 * sx, 0.0, 0.0), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
	_belt(k, true)


static func _chest_vest(k: Kit) -> void:
	var r = k.r
	var chest = r._attach("spine_03")
	var vr := TORSO_R + Vector3(0.0, 0.0, 0.02)
	r._mesh(chest, Shapes.shell(vr, -1.25, 1.25, 1.0, 2.15, 0.03, 14, 9), k.fabric, TORSO_C)
	r._mesh(chest, Shapes.shell(vr, PI - 1.25, PI + 1.25, 1.0, 2.15, 0.03, 14, 9), k.fabric, TORSO_C)
	for row in 2:
		for x in [-0.11, -0.04, 0.04, 0.11]:
			r._mesh(chest, _rb(Vector3(0.06, 0.085, 0.045), 0.012), k.fabric_dark, Vector3(x, -0.15 + row * 0.1, 0.17 - row * 0.005))
	r._mesh(chest, _rb(Vector3(0.12, 0.08, 0.03), 0.01), k.armor, Vector3(0, 0.12, 0.17))
	r._mesh(chest, _rb(Vector3(0.05, 0.12, 0.04), 0.012), k.armor_dark, Vector3(0.13, 0.17, 0.12))
	r._mesh(chest, r._cyl(0.004, 0.25), k.metal, Vector3(0.145, 0.33, 0.12))
	r._mesh(chest, r._cyl(0.018, 0.09), k.metal, Vector3(-0.1, 0.2, 0.16), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2))
	r._mesh(chest, r._cyl(0.015, 0.005), k.glow, Vector3(-0.1, 0.2, 0.207), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2))
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var arm = r._attach("upperarm_" + side)
		r._mesh(arm, _rb(Vector3(0.1, 0.045, 0.12), 0.02), k.fabric_dark, Vector3(0.07 * sx, 0.06, 0.0))
	_belt(k, true)


# ---------------------------------------------------------------- legs

static func _kneepads(k: Kit, mat: Material) -> void:
	var r = k.r
	for side in ["r", "l"]:
		var knee = r._attach("calf_" + side)
		r._mesh(knee, _rb(Vector3(0.1, 0.12, 0.05), 0.022), mat, Vector3(0, -0.02, 0.07))


static func _gaiters(k: Kit) -> void:
	var r = k.r
	for side in ["r", "l"]:
		var calf = r._attach("calf_" + side)
		r._mesh(calf, r._cyl(0.068, 0.16), k.fabric_dark, Vector3(0, -0.33, 0.0))
		for y in [-0.27, -0.37]:
			r._mesh(calf, r._cyl(0.071, 0.018), k.leather, Vector3(0, y, 0.0))


static func _legs_light(k: Kit) -> void:
	_kneepads(k, k.rubber)
	_gaiters(k)


static func _legs_standard(k: Kit) -> void:
	var r = k.r
	_kneepads(k, k.armor_dark)
	_gaiters(k)
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var thigh = r._attach("thigh_" + side)
		r._mesh(thigh, _rb(Vector3(0.05, 0.15, 0.13), 0.02), k.fabric, Vector3(0.09 * sx, -0.22, 0.01))
		r._mesh(thigh, _rb(Vector3(0.052, 0.035, 0.135), 0.01), k.fabric_dark, Vector3(0.091 * sx, -0.15, 0.01))
		var fore = r._attach("lowerarm_" + side)
		r._mesh(fore, _rb(Vector3(0.09, 0.06, 0.1), 0.02), k.fabric_dark, Vector3(0.02 * sx, 0.0, -0.035))


static func _legs_armored(k: Kit) -> void:
	var r = k.r
	_gaiters(k)
	for side in ["r", "l"]:
		var sx := -1.0 if side == "r" else 1.0
		var thigh = r._attach("thigh_" + side)
		# Thigh plate wraps the front/outside of the thigh (bone runs down -Y).
		r._mesh(thigh, Shapes.shell(Vector3(0.095, 0.17, 0.09), -1.0 + 0.4 * sx, 1.0 + 0.4 * sx, 1.0, 2.1, 0.012, 12, 6), k.armor, Vector3(0, -0.2, 0.0))
		r._mesh(thigh, _rb(Vector3(0.05, 0.03, 0.15), 0.01), k.leather, Vector3(0.0, -0.08, 0.0), Vector3(1.9, 1, 1))
		var calf = r._attach("calf_" + side)
		r._mesh(calf, Shapes.shell(Vector3(0.075, 0.075, 0.08), -1.3, 1.3, 0.3, 2.2, 0.014, 12, 6), k.armor_dark, Vector3(0, 0.0, 0.0))
		r._mesh(calf, Shapes.shell(Vector3(0.07, 0.2, 0.075), -1.1, 1.1, 1.15, 2.2, 0.012, 12, 6), k.armor, Vector3(0, -0.24, 0.0))
		var fore = r._attach("lowerarm_" + side)
		r._mesh(fore, Shapes.shell(Vector3(0.06, 0.06, 0.065), -1.4, 1.4, 0.4, 2.4, 0.012, 10, 5), k.armor_dark, Vector3(0.0, 0.0, -0.01), Vector3.ONE, Basis(Vector3.UP, PI))


# ---------------------------------------------------------------- packs (model space at spine_03, back = -Z)

static func _pack_frame(k: Kit, p: Node3D) -> void:
	var r = k.r
	r._mesh(p, _rb(Vector3(0.34, 0.42, 0.2), 0.05), k.fabric, Vector3(0, 0.0, -0.22))
	r._mesh(p, _rb(Vector3(0.36, 0.09, 0.23), 0.035), k.fabric_dark, Vector3(0, 0.2, -0.22))
	for x in [-0.205, 0.205]:
		r._mesh(p, _rb(Vector3(0.07, 0.2, 0.14), 0.03), k.fabric_dark, Vector3(x, -0.06, -0.22))
	r._mesh(p, _rb(Vector3(0.26, 0.18, 0.07), 0.03), k.fabric, Vector3(0, -0.08, -0.34))
	r._mesh(p, _rb(Vector3(0.27, 0.025, 0.075), 0.01), k.leather, Vector3(0, 0.0, -0.345))
	r._mesh(p, r._cyl(0.072, 0.44), k.fabric_dark, Vector3(0, 0.3, -0.2), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
	for x in [-0.12, 0.12]:
		r._mesh(p, r._cyl(0.076, 0.02), k.leather, Vector3(x, 0.3, -0.2), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
	for x in [-0.215, 0.215]:
		r._mesh(p, r._cyl(0.012, 0.66), k.metal, Vector3(x, 0.06, -0.1))
	r._mesh(p, r._cyl(0.012, 0.44), k.metal, Vector3(0, 0.39, -0.1), Vector3.ONE, Basis(Vector3.BACK, PI / 2))
	r._mesh(p, r._cyl(0.004, 0.55), k.metal, Vector3(-0.15, 0.5, -0.28), Vector3.ONE, Basis(Vector3.BACK, 0.12))
	r._mesh(p, _rb(Vector3(0.06, 0.03, 0.03), 0.01), k.glow, Vector3(0.14, 0.16, -0.335))
	var drone := Node3D.new()
	drone.position = Vector3(0.0, 0.405, -0.22)
	p.add_child(drone)
	r._mesh(drone, _rb(Vector3(0.12, 0.04, 0.1), 0.015), k.armor, Vector3.ZERO)
	for d in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
		r._mesh(drone, r._cyl(0.006, 0.09), k.metal, d * 0.045, Vector3.ONE, Basis(d.cross(Vector3.UP).normalized(), PI / 2))
		r._mesh(drone, r._cyl(0.035, 0.006), Mats.gun_metal_dark(), d * 0.075 + Vector3(0, 0.012, 0))
	r._mesh(drone, r._sphere(0.018), k.glow, Vector3(0, -0.01, 0.05))


static func _pack_assault(k: Kit, p: Node3D) -> void:
	var r = k.r
	r._mesh(p, _rb(Vector3(0.3, 0.36, 0.15), 0.06), k.fabric, Vector3(0, 0.02, -0.2))
	r._mesh(p, _rb(Vector3(0.24, 0.16, 0.06), 0.03), k.fabric_dark, Vector3(0, -0.05, -0.29))
	for y in [-0.1, 0.0, 0.1]:
		r._mesh(p, _rb(Vector3(0.31, 0.018, 0.155), 0.006), k.fabric_dark, Vector3(0, y + 0.06, -0.2))
	r._mesh(p, r._cyl(0.04, 0.2), k.metal, Vector3(0.19, -0.02, -0.2))
	r._mesh(p, r._cyl(0.025, 0.04), k.armor, Vector3(0.19, 0.1, -0.2))
	r._mesh(p, _rb(Vector3(0.12, 0.1, 0.02), 0.01), k.armor, Vector3(0, 0.12, -0.282))
	r._mesh(p, _rb(Vector3(0.08, 0.015, 0.01), 0.004), k.glow, Vector3(0, 0.12, -0.294))
	r._mesh(p, r._cyl(0.004, 0.4), k.metal, Vector3(-0.12, 0.38, -0.2), Vector3.ONE, Basis(Vector3.BACK, 0.1))


static func _pack_tanks(k: Kit, p: Node3D) -> void:
	var r = k.r
	r._mesh(p, _rb(Vector3(0.3, 0.46, 0.05), 0.02), k.armor_dark, Vector3(0, 0.02, -0.16))
	for x in [-0.085, 0.085]:
		r._mesh(p, r._cyl(0.075, 0.42), k.armor, Vector3(x, 0.03, -0.25))
		r._mesh(p, r._sphere(0.075), k.armor, Vector3(x, 0.24, -0.25), Vector3(1, 0.6, 1))
		r._mesh(p, r._sphere(0.075), k.armor, Vector3(x, -0.18, -0.25), Vector3(1, 0.6, 1))
		r._mesh(p, r._cyl(0.077, 0.03), k.metal, Vector3(x, 0.12, -0.25))
		r._mesh(p, r._cyl(0.077, 0.03), k.metal, Vector3(x, -0.06, -0.25))
		r._mesh(p, r._cyl(0.015, 0.06), k.metal, Vector3(x, 0.3, -0.25))
	# Hose arching over the right shoulder
	var pts := [Vector3(-0.085, 0.33, -0.25), Vector3(-0.1, 0.42, -0.15), Vector3(-0.13, 0.38, 0.0), Vector3(-0.15, 0.24, 0.12)]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := Node3D.new()
		p.add_child(seg)
		seg.position = (a + b) * 0.5
		var y := (b - a).normalized()
		var x := y.cross(Vector3.FORWARD).normalized()
		seg.basis = Basis(x, y, x.cross(y))
		r._mesh(seg, r._cyl(0.014, a.distance_to(b) + 0.02), k.rubber, Vector3.ZERO)
	r._mesh(p, r._cyl(0.04, 0.02), k.metal, Vector3(0, 0.1, -0.33), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2))
	r._mesh(p, r._cyl(0.032, 0.022), k.glow, Vector3(0, 0.1, -0.335), Vector3.ONE, Basis(Vector3.RIGHT, PI / 2))
