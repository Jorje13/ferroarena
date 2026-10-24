class_name Items
## Loot item registry. Inventory = 4 slots, each {"id": String, "n": int} or {}.
## Supplies (bandage, shield cell) go straight to their counters; attachments
## (silencer, stock) are fitted to the Ferro and kept until the round ends.

const SLOTS := 4
const DEFS := {
	"frag": {"name": "GRENADE", "short": "FRAG", "max": 2, "color": Color(0.95, 0.42, 0.25)},
	"smoke": {"name": "FUMIGÈNE", "short": "FUMI", "max": 2, "color": Color(0.75, 0.8, 0.85)},
	"barricade": {"name": "BARRICADE", "short": "BARR", "max": 1, "color": Color(0.98, 0.78, 0.25)},
	"defib": {"name": "DÉFIBRILLATEUR", "short": "DÉFIB", "max": 1, "color": Color(0.35, 0.95, 0.55)},
}
## Not inventory items: they top up a counter on the player.
const SUPPLIES := {
	"bandage": {"name": "BANDAGE", "max": 4, "color": Color(0.95, 0.95, 0.9)},
	"cell": {"name": "CELLULE DE BOUCLIER", "max": 2, "color": Color(0.35, 0.75, 1.0)},
}
## Fitted to the Ferro. Found in one special crate pair per round (cyan beacon).
const ATTACHMENTS := {
	"silencer": {"name": "SILENCIEUX", "info": "tirs discrets", "color": Color(0.55, 0.85, 1.0)},
	"stock": {"name": "CROSSE ERGONOMIQUE", "info": "rechargement plus rapide", "color": Color(1.0, 0.78, 0.35)},
}
## Loot table weights.
const WEIGHTS := {"frag": 4, "smoke": 3, "barricade": 2, "defib": 2, "bandage": 4, "cell": 2}

## Stock: the reload runs this much faster.
const STOCK_RELOAD_SPEED := 1.1
## Silenced shots are only heard this close by bots (m); a bare Ferro carries 90 m.
const SILENCED_HEAR_RANGE := 14.0

## Frag: wide blast, moderate damage (shield first). Full damage inside
## FRAG_FULL_RADIUS, falling to FRAG_MIN_DAMAGE at FRAG_RADIUS.
const FRAG_FUSE := 2.4
const FRAG_RADIUS := 10.0
const FRAG_FULL_RADIUS := 1.8
const FRAG_MAX_DAMAGE := 65.0
const FRAG_MIN_DAMAGE := 12.0
## Smoke
const SMOKE_DURATION := 16.0
const SMOKE_RADIUS := 5.0
## Barricade
const BARRICADE_HP := 150.0
const BARRICADE_RANGE := 3.5
## Throw
const THROW_SPEED := 17.0


static func empty_inventory() -> Array:
	var a := []
	for i in SLOTS:
		a.append({})
	return a


static func roll(rng: RandomNumberGenerator) -> String:
	var total := 0
	for k in WEIGHTS:
		total += WEIGHTS[k]
	var r := rng.randi_range(1, total)
	for k in WEIGHTS:
		r -= WEIGHTS[k]
		if r <= 0:
			return k
	return "frag"


static func name_of(id: String) -> String:
	if DEFS.has(id):
		return DEFS[id].name
	if SUPPLIES.has(id):
		return SUPPLIES[id].name
	if ATTACHMENTS.has(id):
		return ATTACHMENTS[id].name
	return id


## Adds `n` items into an inventory copy; returns how many fit.
static func add(inv: Array, id: String, n: int) -> int:
	var left := n
	var mx: int = DEFS[id].max
	for s in inv:
		if left > 0 and not s.is_empty() and s.id == id and s.n < mx:
			var take := mini(left, mx - int(s.n))
			s.n += take
			left -= take
	for i in inv.size():
		if left > 0 and inv[i].is_empty():
			var take := mini(left, mx)
			inv[i] = {"id": id, "n": take}
			left -= take
	return n - left


static func color_of(id: String) -> Color:
	if DEFS.has(id):
		return DEFS[id].color
	if SUPPLIES.has(id):
		return SUPPLIES[id].color
	if ATTACHMENTS.has(id):
		return ATTACHMENTS[id].color
	return Color.WHITE
