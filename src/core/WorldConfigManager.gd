extends Node
class_name WorldConfigManager

# =============================================================
# WorldConfigManager: save, load, and share world configs.
#
# A "world config" is the procedural INPUT to a playthrough —
# regions, oligarchs, politicians, and NPCs — captured at the
# moment the generator finishes. It is *not* a save-game; it
# doesn't include current cycle, scandals, bills passed, etc.
#
# Loading a config skips LLM generation entirely and injects
# the exact roster into WorldDirector / RegionGenerator /
# PopulationDirector. Two players with the same config see the
# same world.
#
# Files live in user://world_configs/<slug>.json.
# Desktop users can share via their OS file manager; the in-game
# paste-to-import box accepts raw JSON too.
# =============================================================

signal saved(filepath: String)
signal loaded(name: String)
signal save_failed(reason: String)
signal load_failed(reason: String)

const SAVE_DIR := "user://world_configs"
const FORMAT_VERSION := 1

# Set before reloading the scene when the player picks a saved config.
# Main._ready() reads and clears this, passing to initialize_playthrough.
var pending_config: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	# Also try the user-dir relative form (DirAccess supports user://).
	var d := DirAccess.open("user://")
	if d and not d.dir_exists("world_configs"):
		d.make_dir("world_configs")


# =============================================================
# SAVE
# =============================================================

func save_current(display_name: String, description: String = "") -> String:
	if WorldDirector.oligarchs.is_empty() and WorldDirector.politicians.is_empty():
		save_failed.emit("World not fully generated yet — wait for setup to complete.")
		return ""

	var config := serialize_current(display_name, description)
	var slug := _slug(display_name)
	if slug == "":
		slug = "world_%d" % Time.get_unix_time_from_system()
	var filepath := "%s/%s.json" % [SAVE_DIR, slug]

	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		save_failed.emit("Could not open %s for writing (err %d)." % [filepath, FileAccess.get_open_error()])
		return ""

	file.store_string(JSON.stringify(config, "  "))
	file.close()

	saved.emit(filepath)
	print("WorldConfigManager: saved '%s' → %s" % [display_name, filepath])
	return filepath


func serialize_current(display_name: String, description: String) -> Dictionary:
	var regions_out: Array = []
	var region_gen := get_node_or_null("/root/RegionGenerator")
	var starting_region_name: String = ""
	if region_gen:
		starting_region_name = region_gen.starting_region
		for r in region_gen.regions:
			# r is already a Dictionary — copy to avoid mutation at save time.
			regions_out.append(r.duplicate(true))

	var oligarchs_out: Array = []
	for o in WorldDirector.oligarchs:
		oligarchs_out.append(_oligarch_to_dict(o))

	var politicians_out: Array = []
	for p in WorldDirector.politicians:
		politicians_out.append(_politician_to_dict(p))

	var npcs_out: Array = []
	var pop_dir := get_node_or_null("/root/PopulationDirector")
	if pop_dir:
		for n in pop_dir.roster:
			npcs_out.append(_npc_to_dict(n))

	return {
		"format_version": FORMAT_VERSION,
		"name": display_name,
		"description": description,
		"created_at": Time.get_datetime_string_from_system(),
		"starting_region_name": starting_region_name,
		"regions": regions_out,
		"oligarchs": oligarchs_out,
		"politicians": politicians_out,
		"npcs": npcs_out,
	}


# =============================================================
# LOAD
# =============================================================

func load_from_file(filepath: String) -> Dictionary:
	if not FileAccess.file_exists(filepath):
		load_failed.emit("File not found: %s" % filepath)
		return {}
	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		load_failed.emit("Could not open %s (err %d)." % [filepath, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	return load_from_string(text)


func load_from_string(json_text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(json_text) != OK:
		load_failed.emit("Invalid JSON: %s" % parser.get_error_message())
		return {}
	var data = parser.get_data()
	if not (data is Dictionary):
		load_failed.emit("Config root must be an object.")
		return {}
	if int(data.get("format_version", 0)) != FORMAT_VERSION:
		load_failed.emit("Unsupported format_version (expected %d)." % FORMAT_VERSION)
		return {}
	for key in ["regions", "oligarchs", "politicians", "npcs"]:
		if not data.has(key):
			load_failed.emit("Config missing key: %s" % key)
			return {}
	loaded.emit(str(data.get("name", "Unknown")))
	return data


# =============================================================
# APPLY (called from WorldDirector.initialize_playthrough when preloaded)
# =============================================================

func rehydrate_oligarch(o_dict: Dictionary) -> OligarchData:
	var o := OligarchData.new()
	o.oligarch_id = str(o_dict.get("oligarch_id", ""))
	o.oligarch_name = str(o_dict.get("oligarch_name", ""))
	o.title = str(o_dict.get("title", ""))
	o.sector_of_influence = str(o_dict.get("sector_of_influence", ""))
	o.alive = bool(o_dict.get("alive", true))
	o.ruthlessness = float(o_dict.get("ruthlessness", 0.5))
	o.vanity = float(o_dict.get("vanity", 0.5))
	o.paranoia_base = float(o_dict.get("paranoia_base", 0.5))
	o.intelligence = float(o_dict.get("intelligence", 0.5))
	o.greed = float(o_dict.get("greed", 0.5))
	o.ideology = float(o_dict.get("ideology", 0.5))
	o.ambitions = Array(o_dict.get("ambitions", []), TYPE_STRING, &"", null)
	o.quirks = Array(o_dict.get("quirks", []), TYPE_STRING, &"", null)
	o.wealth = int(o_dict.get("wealth", 1000000))
	o.paranoia = float(o_dict.get("paranoia", o.paranoia_base * 30.0))
	o.public_image = float(o_dict.get("public_image", 10.0))
	o.controversy_level = float(o_dict.get("controversy_level", 5.0))
	o.political_influence = float(o_dict.get("political_influence", 50.0))
	o.awareness_of_player = float(o_dict.get("awareness_of_player", 0.0))
	o.threat_assessment = float(o_dict.get("threat_assessment", 0.0))
	# Seed ambition_progress from keys
	for ambition in o.ambitions:
		o.ambition_progress[ambition] = 0.0
	# Restore ambition evolution bookkeeping if present
	var last_adv = o_dict.get("ambition_last_advance", {})
	if last_adv is Dictionary:
		o.ambition_last_advance = last_adv.duplicate(true)
	var abandoned = o_dict.get("abandoned_ambitions", [])
	if abandoned is Array:
		o.abandoned_ambitions = Array(abandoned, TYPE_STRING, &"", null)
	return o


func rehydrate_politician(p_dict: Dictionary) -> PoliticianData:
	var p := PoliticianData.new()
	p.politician_id = str(p_dict.get("politician_id", ""))
	p.politician_name = str(p_dict.get("politician_name", ""))
	p.title = str(p_dict.get("title", "Senator"))
	p.faction = str(p_dict.get("faction", "INDEPENDENT"))
	p.cause = str(p_dict.get("cause", ""))
	p.seat_district = str(p_dict.get("seat_district", "At-Large"))
	p.alive = bool(p_dict.get("alive", true))
	p.integrity = float(p_dict.get("integrity", 0.5))
	p.corruption = float(p_dict.get("corruption", 0.5))
	p.populism = float(p_dict.get("populism", 0.5))
	p.ambition = float(p_dict.get("ambition", 0.5))
	p.conviction = float(p_dict.get("conviction", 0.5))
	p.charisma = float(p_dict.get("charisma", 0.5))
	p.public_approval = float(p_dict.get("public_approval", 0.0))
	p.re_election_proximity = int(p_dict.get("re_election_proximity", 20))
	p.position_consistency = float(p_dict.get("position_consistency", 0.5))
	p.quirks = Array(p_dict.get("quirks", []), TYPE_STRING, &"", null)
	return p


func rehydrate_npc(n_dict: Dictionary) -> NPCData:
	var n := NPCData.new()
	n.npc_id = str(n_dict.get("npc_id", ""))
	n.npc_name = str(n_dict.get("npc_name", ""))
	n.social_class = int(n_dict.get("social_class", 2))
	n.resilience = float(n_dict.get("resilience", 0.5))
	n.aggression = float(n_dict.get("aggression", 0.3))
	n.empathy = float(n_dict.get("empathy", 0.5))
	n.idealism = float(n_dict.get("idealism", 0.3))
	n.greed = float(n_dict.get("greed", 0.2))
	n.conformity = float(n_dict.get("conformity", 0.5))
	n.quirks = Array(n_dict.get("quirks", []), TYPE_STRING, &"", null)
	n.current_mood = str(n_dict.get("current_mood", "Anxious"))
	n.stress_level = float(n_dict.get("stress_level", 30.0))
	n.hope = float(n_dict.get("hope", 50.0))
	n.radicalization = float(n_dict.get("radicalization", 0.0))
	n.personal_wealth = int(n_dict.get("personal_wealth", 50))
	n.immediate_need = str(n_dict.get("immediate_need", "Stability"))
	n.trust = float(n_dict.get("trust", 0.0))
	n.relationship_type = int(n_dict.get("relationship_type", 0))
	n.active_phase = str(n_dict.get("active_phase", "both"))
	n.alive = bool(n_dict.get("alive", true))
	n.death_cause = str(n_dict.get("death_cause", ""))
	n.died_on_cycle = int(n_dict.get("died_on_cycle", -1))
	return n


# =============================================================
# LIST / DELETE
# =============================================================

func list_saved() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	while true:
		var file_name := d.get_next()
		if file_name == "":
			break
		if d.current_is_dir():
			continue
		if not file_name.ends_with(".json"):
			continue
		var filepath := "%s/%s" % [SAVE_DIR, file_name]
		var meta := _read_metadata(filepath)
		meta["filepath"] = filepath
		out.append(meta)
	d.list_dir_end()
	out.sort_custom(func(a, b): return str(a.get("created_at", "")) > str(b.get("created_at", "")))
	return out


func delete_config(filepath: String) -> bool:
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return false
	var name_part: String = filepath.get_file()
	return d.remove(name_part) == OK


func _read_metadata(filepath: String) -> Dictionary:
	var file := FileAccess.open(filepath, FileAccess.READ)
	if file == null:
		return {"name": filepath.get_file(), "description": "", "created_at": ""}
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"name": filepath.get_file(), "description": "[corrupt]", "created_at": ""}
	var data = parser.get_data()
	return {
		"name": str(data.get("name", filepath.get_file())),
		"description": str(data.get("description", "")),
		"created_at": str(data.get("created_at", "")),
		"region_count": (data.get("regions", []) as Array).size(),
		"oligarch_count": (data.get("oligarchs", []) as Array).size(),
		"politician_count": (data.get("politicians", []) as Array).size(),
	}


# =============================================================
# SERIALIZERS (private)
# =============================================================

func _oligarch_to_dict(o: OligarchData) -> Dictionary:
	return {
		"oligarch_id": o.oligarch_id,
		"oligarch_name": o.oligarch_name,
		"title": o.title,
		"sector_of_influence": o.sector_of_influence,
		"alive": o.alive,
		"ruthlessness": o.ruthlessness,
		"vanity": o.vanity,
		"paranoia_base": o.paranoia_base,
		"intelligence": o.intelligence,
		"greed": o.greed,
		"ideology": o.ideology,
		"ambitions": Array(o.ambitions),
		"quirks": Array(o.quirks),
		"wealth": o.wealth,
		"paranoia": o.paranoia,
		"public_image": o.public_image,
		"controversy_level": o.controversy_level,
		"political_influence": o.political_influence,
		"awareness_of_player": o.awareness_of_player,
		"threat_assessment": o.threat_assessment,
		"ambition_last_advance": o.ambition_last_advance,
		"abandoned_ambitions": Array(o.abandoned_ambitions),
	}


func _politician_to_dict(p: PoliticianData) -> Dictionary:
	return {
		"politician_id": p.politician_id,
		"politician_name": p.politician_name,
		"title": p.title,
		"faction": p.faction,
		"cause": p.cause,
		"seat_district": p.seat_district,
		"alive": p.alive,
		"integrity": p.integrity,
		"corruption": p.corruption,
		"populism": p.populism,
		"ambition": p.ambition,
		"conviction": p.conviction,
		"charisma": p.charisma,
		"public_approval": p.public_approval,
		"re_election_proximity": p.re_election_proximity,
		"position_consistency": p.position_consistency,
		"quirks": Array(p.quirks),
	}


func _npc_to_dict(n: NPCData) -> Dictionary:
	return {
		"npc_id": n.npc_id,
		"npc_name": n.npc_name,
		"social_class": n.social_class,
		"resilience": n.resilience,
		"aggression": n.aggression,
		"empathy": n.empathy,
		"idealism": n.idealism,
		"greed": n.greed,
		"conformity": n.conformity,
		"quirks": Array(n.quirks),
		"current_mood": n.current_mood,
		"stress_level": n.stress_level,
		"hope": n.hope,
		"radicalization": n.radicalization,
		"personal_wealth": n.personal_wealth,
		"immediate_need": n.immediate_need,
		"trust": n.trust,
		"relationship_type": n.relationship_type,
		"active_phase": n.active_phase,
		"alive": n.alive,
		"death_cause": n.death_cause,
		"died_on_cycle": n.died_on_cycle,
	}


# =============================================================
# UTILITIES
# =============================================================

func _slug(s: String) -> String:
	var out := s.strip_edges().to_lower()
	var clean := ""
	for c in out:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			clean += c
		elif c == " " or c == "-" or c == "_":
			clean += "_"
	while "__" in clean:
		clean = clean.replace("__", "_")
	clean = clean.strip_edges().lstrip("_").rstrip("_")
	return clean.left(48)


func apply_and_restart(config: Dictionary) -> void:
	# Hand off to Main._ready via pending_config; reload scene for a clean init.
	pending_config = config
	get_tree().reload_current_scene()


func suggest_name() -> String:
	var tension: int = int(WorldDirector.global_economy.get("public_tension", 0))
	var senate: int = int(WorldDirector.global_economy.get("senate_alignment", 50))
	var region := WorldDirector.current_region if WorldDirector.current_region != "" else "Untitled Region"
	var mood := "Crisis" if tension > 60 else ("Reform" if senate < 30 else "Standoff")
	var date := Time.get_date_string_from_system().replace("-", "")
	return "%s %s %s" % [region, mood, date]
