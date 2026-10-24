class_name VaultMath
## Vault timing and anchors, shared by the Player (path) and the rig (pose). No
## dependencies on purpose (Player <-> CharacterRig reference each other).
##
## Measured on the Mixamo "Vault Over Box" capture: hands land on the box 0.40 s
## in, 0.5 m ahead of the hips, on a top 1.05 m high; the feet touch down again at
## ~1.45 s. The vault plays the window T0 .. T0 + LEN of the clip.

const T0 := 0.2
const LEN := 1.35
const CONTACT := 0.4
const REACH := 0.5
const TOP := 1.05

## Raw hips forward travel (m) of the clip every 1/60 s; filled in by CharacterModel
## when it builds the animation library.
static var z := PackedFloat32Array()


static func z_at(t: float) -> float:
	if z.is_empty():
		return t
	var f := clampf(t * 60.0, 0.0, float(z.size() - 1))
	var i := int(f)
	return lerpf(z[i], z[mini(i + 1, z.size() - 1)], f - i)


## How far the root has moved along the vault line at clip time `tau`, so that
## the hands meet the obstacle's face (to_face m ahead) at the contact beat and
## the feet touch down on the landing (to_land m ahead) at the end: the clip's
## own forward travel sets the rhythm between those two anchors.
static func root_distance(tau: float, to_face: float, to_land: float) -> float:
	var z0 := z_at(T0)
	var zc := z_at(CONTACT)
	var z1 := z_at(T0 + LEN)
	var zt := z_at(tau)
	var contact_d := clampf(to_face - REACH, 0.0, to_land)
	if tau <= CONTACT:
		return contact_d * clampf((zt - z0) / maxf(zc - z0, 0.05), 0.0, 1.0)
	return contact_d + (to_land - contact_d) * clampf((zt - zc) / maxf(z1 - zc, 0.05), 0.0, 1.0)


## Vertical offset of the body so the clip (made for a 1.05 m top) clears an
## obstacle `h` metres high: none while the feet still push off and after the
## landing, full while the body is over the top.
static func lift(tau: float, h: float) -> float:
	var over := smoothstep(0.42, 0.72, tau) - smoothstep(1.2, 1.45, tau)
	return (h - TOP) * clampf(over, 0.0, 1.0)
