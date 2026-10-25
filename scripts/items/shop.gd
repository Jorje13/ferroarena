class_name Shop
## Zombie survival workbench: what scrap ("ferraille") buys between waves. Scrap comes from
## kills (per monster kind) and from every wave held. Upgrades are kept for the whole match,
## even through a death; items and supplies go to the inventory / counters as usual.

const START_SCRAP := 60
## Per kill, by monster kind (Faucheur, Bondisseur, Rôdeur).
const KILL_SCRAP := [45, 15, 10]
const WAVE_SCRAP := 60
## Interaction range around the workbench (m).
const RANGE := 3.0

## cat: "item" (inventory / supplies), "weapon" (Ferro upgrades), "zombie" (this mode only).
## `cost` for one-off purchases, `levels` (cost of each level) for upgrades.
const ENTRIES := [
	{"id": "frag", "cat": "item", "name": "GRENADE", "info": "explosion à fragmentation", "cost": 35},
	{"id": "smoke", "cat": "item", "name": "FUMIGÈNE", "info": "écran de fumée", "cost": 20},
	{"id": "barricade", "cat": "item", "name": "BARRICADE", "info": "mur à poser", "cost": 45},
	{"id": "defib", "cat": "item", "name": "DÉFIBRILLATEUR", "info": "relève un allié à distance", "cost": 55},
	{"id": "bandage", "cat": "item", "name": "BANDAGE", "info": "+1 bandage", "cost": 15},
	{"id": "cell", "cat": "item", "name": "CELLULE DE BOUCLIER", "info": "+1 recharge de bouclier", "cost": 30},
	{"id": "silencer", "cat": "weapon", "name": "SILENCIEUX", "info": "tirs discrets", "levels": [60]},
	{"id": "stock", "cat": "weapon", "name": "CROSSE ERGONOMIQUE", "info": "rechargement +10 %", "levels": [70]},
	{"id": "barrel", "cat": "weapon", "name": "CANON RENFORCÉ", "info": "+20 % de dégâts par niveau", "levels": [100, 180, 280]},
	{"id": "action", "cat": "weapon", "name": "MÉCANISME GRAISSÉ", "info": "rechargement +15 % par niveau", "levels": [80, 150]},
	{"id": "hollow", "cat": "weapon", "name": "BALLES À POINTE CREUSE", "info": "tirs à la tête ×2,5 au lieu de ×2", "levels": [150]},
	{"id": "heal", "cat": "zombie", "name": "SOINS COMPLETS", "info": "santé et bouclier au maximum", "cost": 40},
	{"id": "armor", "cat": "zombie", "name": "BLINDAGE", "info": "−15 % de dégâts des monstres par niveau", "levels": [90, 170, 260]},
	{"id": "scavenger", "cat": "zombie", "name": "RÉCUPÉRATEUR", "info": "+50 % de ferraille par élimination", "levels": [90]},
]
const CATEGORIES := [["item", "OBJETS"], ["weapon", "AMÉLIORATIONS DU FERRO"], ["zombie", "SURVIE"]]


static func entry(id: String) -> Dictionary:
	for e in ENTRIES:
		if e.id == id:
			return e
	return {}


static func is_upgrade(e: Dictionary) -> bool:
	return e.has("levels")


## Price of the next purchase at `level` already owned; -1 when maxed out.
static func cost(e: Dictionary, level: int) -> int:
	if is_upgrade(e):
		var lv: Array = e.levels
		return int(lv[level]) if level < lv.size() else -1
	return int(e.cost)


static func max_level(e: Dictionary) -> int:
	return (e.levels as Array).size() if is_upgrade(e) else 0


## Effects, from a player's upgrade levels.
static func damage_mult(up: Dictionary) -> float:
	return 1.0 + 0.2 * int(up.get("barrel", 0))


static func headshot_mult(up: Dictionary) -> float:
	return 2.5 if int(up.get("hollow", 0)) > 0 else 2.0


static func reload_mult(up: Dictionary) -> float:
	return 1.0 + 0.15 * int(up.get("action", 0))


static func armor_mult(up: Dictionary) -> float:
	return 1.0 - 0.15 * int(up.get("armor", 0))


static func scrap_mult(up: Dictionary) -> float:
	return 1.5 if int(up.get("scavenger", 0)) > 0 else 1.0
