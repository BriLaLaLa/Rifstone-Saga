class_name SkillEvents3D
extends RefCounted
## Tempi delle animazioni del warrior per i 3 stili (tabelle di SKILLS_WARRIOR.md), in secondi dall'inizio
## dell'animazione (velocità 1x: con le animazioni accelerate i tempi scalano da soli perché si leggono
## dalla posizione dell'animazione).
##
## Per ogni animazione (nome risolto, con prefisso dello stile):
##   eventi:   "hit" (float o lista di tempi), "hit1".."hit3", "on"
##   finestre: "dash" (Sibilare: il warrior scatta sul bersaglio), "spin" (Vortice: avanza di ~0.8 m),
##             "charge" (Volontà di Vivere: carica luminosa)
##   "trails": scie delle lame, [inizio, fine, lame] con lame "R" (mano destra), "L" (sinistra), "RL" (entrambe)

## skill del database -> animazione (Guardia e Grido di Battaglia dei loadout vecchi usano quelle del nuovo set)
const SKILL_ANIMS := {
	"hiss": "skill_hiss",
	"sword_vortex": "skill_sword_vortex",
	"three_way_slash": "skill_three_way_slash",
	"berserk": "skill_berserk",
	"battle_cry": "skill_berserk",
	"sword_aura": "skill_sword_aura",
	"guard": "skill_sword_aura",
	"life_force": "skill_life_force",
}

const EVENT_NAMES := ["hit", "hit1", "hit2", "hit3", "on"]
const WINDOW_NAMES := ["dash", "spin", "charge"]

const TABLE := {
	# ---------- spada + scudo ----------
	"attack1": {"hit": 0.30, "trails": [[0.17, 0.37, "R"]]},
	"attack2": {"hit": 0.37, "trails": [[0.24, 0.44, "R"]]},
	"skill_sword_aura": {"on": 0.400},
	"skill_berserk": {"on": 0.533},
	"skill_sword_vortex": {"hit": [0.400, 0.533, 0.667], "on": 0.900, "spin": [0.267, 0.800], "trails": [[0.267, 0.86, "R"]]},
	"skill_three_way_slash": {"hit1": 0.167, "hit2": 0.400, "hit3": 0.733,
		"trails": [[0.06, 0.22, "R"], [0.29, 0.45, "R"], [0.60, 0.80, "R"]]},
	"skill_hiss": {"hit": 0.333, "dash": [0.12, 0.32], "trails": [[0.12, 0.40, "R"]]},
	"skill_life_force": {"hit": 0.900, "charge": [0.05, 0.86], "trails": [[0.78, 1.00, "R"]]},
	# ---------- spadone (gs_) ----------
	"gs_attack1": {"hit": 0.500, "trails": [[0.36, 0.62, "R"]]},
	"gs_attack2": {"hit": 0.600, "trails": [[0.46, 0.72, "R"]]},
	"gs_skill_sword_aura": {"on": 0.467},
	"gs_skill_berserk": {"on": 0.600},
	"gs_skill_sword_vortex": {"hit": [0.500, 0.633, 0.767], "on": 1.067, "spin": [0.300, 0.933], "trails": [[0.30, 1.00, "R"]]},
	"gs_skill_three_way_slash": {"hit1": 0.233, "hit2": 0.533, "hit3": 1.000,
		"trails": [[0.08, 0.29, "R"], [0.40, 0.60, "R"], [0.86, 1.08, "R"]]},
	"gs_skill_hiss": {"hit": 0.400, "dash": [0.20, 0.40], "trails": [[0.20, 0.47, "R"]]},
	"gs_skill_life_force": {"hit": 1.067, "charge": [0.10, 1.00], "trails": [[0.90, 1.17, "R"]]},
	# ---------- due spade (dual_) ----------
	"dual_attack1": {"hit": 0.333, "trails": [[0.20, 0.40, "R"]]},
	"dual_attack2": {"hit": 0.333, "trails": [[0.20, 0.40, "L"]]},
	"dual_skill_sword_aura": {"on": 0.400},
	"dual_skill_berserk": {"on": 0.533},
	"dual_skill_sword_vortex": {"hit": [0.400, 0.533, 0.667], "on": 0.900, "spin": [0.233, 0.800], "trails": [[0.233, 0.86, "RL"]]},
	"dual_skill_three_way_slash": {"hit1": 0.167, "hit2": 0.400, "hit3": 0.733,
		"trails": [[0.05, 0.21, "R"], [0.28, 0.45, "L"], [0.62, 0.80, "RL"]]},
	"dual_skill_hiss": {"hit": 0.367, "dash": [0.20, 0.367], "trails": [[0.20, 0.43, "RL"]]},
	"dual_skill_life_force": {"hit": 0.933, "charge": [0.10, 0.86], "trails": [[0.84, 1.02, "RL"]]},
}


static func anim_for_skill(skill_id: String) -> String:
	return SKILL_ANIMS.get(skill_id, "attack1")


static func info(resolved_anim: String) -> Dictionary:
	return TABLE.get(resolved_anim, {})


## Nome base (senza prefisso dello stile)
static func base_name(anim_name: String) -> String:
	for p in ["dual_", "gs_"]:
		if anim_name.begins_with(p):
			return anim_name.substr(p.length())
	return anim_name


## Eventi di un'animazione in ordine di tempo: [[tempo, nome, indice], ...]
static func events(resolved_anim: String) -> Array:
	var out: Array = []
	var d := info(resolved_anim)
	for ev in EVENT_NAMES:
		if not d.has(ev):
			continue
		var times: Array = d[ev] if d[ev] is Array else [d[ev]]
		for i in times.size():
			out.append([float(times[i]), ev, i])
	out.sort_custom(func(a, b) -> bool: return a[0] < b[0])
	return out


## Avanzamento 0..1 di una finestra (dash/spin/charge) alla posizione t, -1 se fuori
static func window_progress(resolved_anim: String, window: String, t: float) -> float:
	var d := info(resolved_anim)
	if not d.has(window):
		return -1.0
	var w: Array = d[window]
	if t < w[0] or t > w[1]:
		return -1.0
	return clampf((t - w[0]) / maxf(w[1] - w[0], 0.001), 0.0, 1.0)


## Lame che devono lasciare la scia alla posizione t ("R", "L", "RL" o "")
static func trail_blades(resolved_anim: String, t: float) -> String:
	var out := ""
	for tr in info(resolved_anim).get("trails", []):
		if t >= tr[0] and t <= tr[1]:
			out += tr[2]
	return out
