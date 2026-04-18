extends HTTPRequest
class_name LLMManager

# =============================================================
# LLMManager: Routes world generation through either a cloud
# LLM provider, a self-hosted local LLM, or offline fallbacks.
#
# Provider fallback order (initialized once at _ready):
#   1. GEMINI_API_KEY     → Gemini
#   2. OPENAI_API_KEY     → OpenAI
#   3. ANTHROPIC_API_KEY  → Claude
#   4. QWEN_API_KEY       → Qwen
#   5. OPENROUTER_API_KEY → OpenRouter
#   6. LOCAL_LLM_URL set  → local (Ollama / LMStudio / vLLM)
#   7. (none)             → OFFLINE — synthesize content locally
#
# Offline mode is the default when nothing is configured. It
# produces playable, thematic content so the game runs from a
# clean checkout with no keys, no network.
# =============================================================

signal llm_response_received(response_data: Dictionary)
signal llm_error_occurred(error_message: String)
signal netfeed_stream_received(events: Array)
signal oligarchs_generated(oligarch_data: Array)
signal npc_roster_generated(npc_data: Array)
signal world_regions_generated(region_data: Array)
signal politicians_generated(politician_data: Array)

var current_request_type: String = ""

var active_provider: String = ""
var api_url: String = ""
var api_key: String = ""
var active_model: String = ""
var use_offline_fallback: bool = false

# Bill generation uses a callback rather than a signal (single-fire, ergonomic
# from the caller's side). The pending callback is held here for the duration
# of one in-flight request.
var _bill_callback: Callable = Callable()


func _ready() -> void:
	self.request_completed.connect(_on_request_completed)
	_initialize_provider()


func _initialize_provider() -> void:
	if not OS.get_environment("GEMINI_API_KEY").is_empty():
		active_provider = "gemini"
		api_key = OS.get_environment("GEMINI_API_KEY")
		api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
		active_model = "gemini-1.5-pro-latest"
		print("LLMManager: Using Gemini API")

	elif not OS.get_environment("OPENAI_API_KEY").is_empty():
		active_provider = "openai"
		api_key = OS.get_environment("OPENAI_API_KEY")
		api_url = "https://api.openai.com/v1/chat/completions"
		active_model = "gpt-4-turbo-preview"
		print("LLMManager: Using OpenAI API")

	elif not OS.get_environment("ANTHROPIC_API_KEY").is_empty():
		active_provider = "claude"
		api_key = OS.get_environment("ANTHROPIC_API_KEY")
		api_url = "https://api.anthropic.com/v1/messages"
		active_model = "claude-3-opus-20240229"
		print("LLMManager: Using Claude API")

	elif not OS.get_environment("QWEN_API_KEY").is_empty():
		active_provider = "qwen"
		api_key = OS.get_environment("QWEN_API_KEY")
		api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
		active_model = "qwen-max"
		print("LLMManager: Using Qwen API")

	elif not OS.get_environment("OPENROUTER_API_KEY").is_empty():
		active_provider = "openrouter"
		api_key = OS.get_environment("OPENROUTER_API_KEY")
		api_url = "https://openrouter.ai/api/v1/chat/completions"
		active_model = "meta-llama/llama-3-70b-instruct"
		print("LLMManager: Using OpenRouter API")

	elif not OS.get_environment("LOCAL_LLM_URL").is_empty():
		# Only use local LLM if the user explicitly configured a URL.
		# Defaulting to localhost:11434 silently would hang the game
		# whenever Ollama isn't running.
		active_provider = "local"
		api_key = "local"
		api_url = OS.get_environment("LOCAL_LLM_URL")
		active_model = OS.get_environment("LOCAL_LLM_MODEL")
		if active_model.is_empty():
			active_model = "llama3"
		print("LLMManager: Using LOCAL model at ", api_url)

	else:
		active_provider = "offline"
		use_offline_fallback = true
		print("LLMManager: OFFLINE mode — synthesizing content locally. Set one of GEMINI_API_KEY / OPENAI_API_KEY / ANTHROPIC_API_KEY / QWEN_API_KEY / OPENROUTER_API_KEY / LOCAL_LLM_URL to enable live LLM generation.")


# =============================================================
# SHARED REQUEST BUILDER
# =============================================================
func _base_headers() -> Array:
	var headers: Array = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	]
	if active_provider == "openrouter":
		headers.append("HTTP-Referer: https://killthebill.game")
		headers.append("X-Title: Kill The Bill")
	elif active_provider == "claude":
		headers.append("x-api-key: " + api_key)
		headers.append("anthropic-version: 2023-06-01")
		headers[1] = "Authorization: "
	return headers


func _build_payload(system_prompt: String, user_prompt: String, max_tokens: int, temperature: float, json_mode: bool = true) -> Dictionary:
	if active_provider == "claude":
		return {
			"model": active_model,
			"max_tokens": max_tokens,
			"system": system_prompt,
			"messages": [{"role": "user", "content": user_prompt}],
		}
	var p: Dictionary = {
		"model": active_model,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
		"temperature": temperature,
	}
	if json_mode:
		p["response_format"] = {"type": "json_object"}
	return p


# =============================================================
# PUBLIC REQUEST METHODS
# =============================================================

func request_npc_action(npc, player_input: String) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_npc_action", player_input)
		return
	current_request_type = "npc_action"
	var system_prompt := "You are the Game Master for a systemic immersive sim called KILL THE BILL.\n"
	system_prompt += "Evaluate the player's input against the following NPC state:\n"
	system_prompt += npc.get_llm_context_string() + "\n"
	system_prompt += "Respond strictly in JSON format with keys: 'success' (boolean), 'dialogue' (string), and 'assigned_goal' (string)."
	_send(system_prompt, player_input + "\n\nProvide your response purely in JSON format.", 1024, 0.7)


func request_netfeed_events(world_state: Dictionary, oligarchs: Dictionary) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_netfeed", world_state, oligarchs)
		return
	current_request_type = "netfeed_stream"
	var system_prompt := "You are the Game Master for a systemic immersive sim called KILL THE BILL.\n"
	system_prompt += "Evaluate the complex conjecture of the current world state:\n"
	system_prompt += "Global Economy: " + JSON.stringify(world_state) + "\n"
	system_prompt += "Oligarchs: " + JSON.stringify(oligarchs) + "\n"
	system_prompt += "Generate an organic stream of events, number varying with gravity of the situation.\n"
	system_prompt += "Events can be public news, or invisible systemic shifts with no headline.\n"
	system_prompt += "Respond STRICTLY in JSON with key 'events': array of {type: 'NEWS_TICKER'|'SILENT_RIPPLE', headline: string, systemic_impact: string}."
	_send(system_prompt, "Generate the event stream in JSON.", 1024, 0.8)


func request_oligarch_generation(count: int) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_oligarchs", count)
		return
	current_request_type = "oligarch_generation"
	var system_prompt := "You are the Architect for a systemic immersive sim called KILL THE BILL.\n"
	system_prompt += "Generate " + str(count) + " unique corporate oligarchs for a 'Corporate Brutalist / Slum Cyberpunk' dystopia.\n"
	system_prompt += "Each must be a fully realized character. Provide: first_name, last_name, title (CEO, Chairman, Director-General, Founder, Chief Architect), sector (Food, Tech, Security, Media, Pharma, Energy), 2-3 ambitions, 2-3 quirks.\n"
	system_prompt += "High diversity. Some ideological, some greedy, some paranoid, some vain.\n"
	system_prompt += "Respond STRICTLY in JSON with key 'oligarchs' containing an array of objects."
	_send(system_prompt, "Generate the oligarch roster in JSON.", 2048, 0.9)


func request_npc_roster_generation(count: int) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_npcs", count)
		return
	current_request_type = "npc_roster_generation"
	var system_prompt := "You are the Population Architect for KILL THE BILL.\n"
	system_prompt += "Generate " + str(count) + " unique citizens of a cyberpunk dystopia. They live in 'The Sinks' or 'The Spire'.\n"
	system_prompt += "Provide: first_name, last_name, 2-3 quirks. Avoid clichés.\n"
	system_prompt += "Respond STRICTLY in JSON with key 'npcs' containing an array of objects."
	_send(system_prompt, "Generate the population in JSON.", 4096, 1.0)


func request_world_regions_generation(distribution: Dictionary) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_regions", distribution)
		return
	current_request_type = "world_regions_generation"
	var system_prompt := "You are the World Architect for KILL THE BILL.\n"
	system_prompt += "Generate unique region names for a cyberpunk dystopia based on the count distribution:\n"
	system_prompt += JSON.stringify(distribution) + "\n"
	system_prompt += "Gritty, brutalist, atmospheric names. Avoid 'Neon City' / 'Cyber-X' clichés.\n"
	system_prompt += "Respond STRICTLY in JSON with key 'regions' containing objects: {name, type, short_description}."
	_send(system_prompt, "Generate the regions in JSON.", 1024, 1.0)


func request_politician_generation(count: int) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_politicians", count)
		return
	current_request_type = "politician_generation"
	var system_prompt := "You are the Political Architect for KILL THE BILL.\n"
	system_prompt += "Generate " + str(count) + " procedural senators for a cyberpunk dystopia. They sit in a %d-seat chamber that votes on corporate and populist bills.\n" % count
	system_prompt += "Target faction split (not rigid): CORPORATE_BLOC 3-4, POPULIST 2-3, REFORM 2-3, INDEPENDENT 2-3.\n"
	system_prompt += "For each: first_name, last_name, title (Senator/Representative/Speaker/Chair), faction, cause (signature issue like 'labor', 'law_and_order'), seat_district, 1-2 quirks.\n"
	system_prompt += "Respond STRICTLY in JSON with key 'politicians' containing an array of objects."
	_send(system_prompt, "Generate the Senate roster in JSON.", 2048, 0.9)


func request_bill(request: Dictionary, callback: Callable) -> void:
	# request keys: sponsor_context, world_snapshot, recent_netfeed,
	# active_oligarch_ambitions, forbidden_topics, effect_whitelist.
	if use_offline_fallback:
		call_deferred("_offline_emit_bill", request, callback)
		return
	current_request_type = "bill_generation"
	_bill_callback = callback
	var system_prompt := "You are the Bill Drafter for KILL THE BILL's Senate.\n"
	system_prompt += "Generate ONE bill this sponsor would propose this week, given world state and active oligarch ambitions.\n"
	system_prompt += "Sponsor: " + str(request.get("sponsor_context", "")) + "\n"
	system_prompt += "World: " + JSON.stringify(request.get("world_snapshot", {})) + "\n"
	system_prompt += "Recent NetFeed: " + JSON.stringify(request.get("recent_netfeed", [])) + "\n"
	system_prompt += "Active oligarch ambitions: " + JSON.stringify(request.get("active_oligarch_ambitions", [])) + "\n"
	system_prompt += "Forbidden (don't repeat): " + JSON.stringify(request.get("forbidden_topics", [])) + "\n"
	system_prompt += "Effect whitelist (stay in range): " + JSON.stringify(request.get("effect_whitelist", {})) + "\n"
	system_prompt += "Respond STRICTLY in JSON with keys: title, summary, stated_rationale, honest_rationale, ideological_score (-1..+1), faction_preferences (all 4 factions, -1..+1), proposed_effects (only whitelisted keys), scandal_hooks (array), netfeed_flavor."
	_send(system_prompt, "Draft the bill in JSON. Specific, concrete framing — not generic policy-speak.", 1024, 0.85)


# =============================================================
# HTTP pipeline
# =============================================================

func _send(system_prompt: String, user_prompt: String, max_tokens: int, temperature: float) -> void:
	if active_provider == "":
		llm_error_occurred.emit("LLM Provider not initialized.")
		return
	var headers: Array = _base_headers()
	var payload: Dictionary = _build_payload(system_prompt, user_prompt, max_tokens, temperature, true)
	var json_payload: String = JSON.stringify(payload)
	var error: int = request(api_url, headers, HTTPClient.METHOD_POST, json_payload)
	if error != OK:
		llm_error_occurred.emit("Failed to send HTTP request (%s). Error: %s" % [current_request_type, str(error)])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		llm_error_occurred.emit("HTTP Request failed. Response code: %d Body: %s" % [response_code, body.get_string_from_utf8()])
		if current_request_type == "bill_generation" and _bill_callback.is_valid():
			_bill_callback.call({})
			_bill_callback = Callable()
		return

	var outer := JSON.new()
	if outer.parse(body.get_string_from_utf8()) != OK:
		llm_error_occurred.emit("Failed to parse outer API response.")
		return

	var data = outer.get_data()
	var message_content: String = ""
	if active_provider == "claude":
		if data.has("content") and data["content"].size() > 0:
			message_content = data["content"][0].get("text", "")
	else:
		if data.has("choices") and data["choices"].size() > 0:
			message_content = data["choices"][0].get("message", {}).get("content", "")

	if message_content == "":
		llm_error_occurred.emit("Unexpected LLM response format.")
		return

	var inner := JSON.new()
	if inner.parse(message_content) != OK:
		llm_error_occurred.emit("Failed to parse LLM nested JSON. Raw: " + message_content)
		if current_request_type == "bill_generation" and _bill_callback.is_valid():
			_bill_callback.call({})
			_bill_callback = Callable()
		return

	var parsed = inner.get_data()
	match current_request_type:
		"npc_action":
			llm_response_received.emit(parsed)
		"netfeed_stream":
			if parsed.has("events"):
				netfeed_stream_received.emit(parsed["events"])
			else:
				llm_error_occurred.emit("NetFeed response missing 'events' array.")
		"oligarch_generation":
			if parsed.has("oligarchs"):
				oligarchs_generated.emit(parsed["oligarchs"])
			else:
				llm_error_occurred.emit("Oligarch response missing 'oligarchs' array.")
		"npc_roster_generation":
			if parsed.has("npcs"):
				npc_roster_generated.emit(parsed["npcs"])
			else:
				llm_error_occurred.emit("NPC response missing 'npcs' array.")
		"world_regions_generation":
			if parsed.has("regions"):
				world_regions_generated.emit(parsed["regions"])
			else:
				llm_error_occurred.emit("Region response missing 'regions' array.")
		"politician_generation":
			if parsed.has("politicians"):
				politicians_generated.emit(parsed["politicians"])
			else:
				llm_error_occurred.emit("Politician response missing 'politicians' array.")
		"bill_generation":
			if _bill_callback.is_valid():
				_bill_callback.call(parsed)
				_bill_callback = Callable()


# =============================================================
# OFFLINE FALLBACK CONTENT POOLS
# =============================================================

const _OLIGARCH_FIRST := ["Veldra", "Korr", "Lysandra", "Arkady", "Mara", "Thessaly", "Orlan", "Verity", "Cyrus", "Nadia", "Erastus", "Felina", "Roderic", "Indra", "Sevrin", "Mabel", "Yusef", "Ophira", "Callum", "Delphine"]
const _OLIGARCH_LAST := ["Vextol", "Krynne", "Aurelius", "Stroma", "Bane", "Oksmarra", "Gant", "Throne", "Varik", "Silvane", "Okonjo", "Trell", "Verhovskiy", "Quell", "Drax", "Zhao-Pax", "Hollis", "Karst", "Dain", "Wyler"]
const _OLIGARCH_TITLES := ["CEO", "Chairman", "Director-General", "Founder", "Chief Architect"]
const _OLIGARCH_SECTORS := ["Food", "Tech", "Security", "Media", "Pharma", "Energy"]
const _OLIGARCH_AMBITIONS := ["Monopolize supply", "Achieve political immortality", "Build a legacy", "Escape", "Crush the resistance", "Control the narrative", "Transcend humanity", "Purge The Sinks"]
const _OLIGARCH_QUIRKS := [
	"Refuses to use the word 'poor' — substitutes 'unfortunate' or 'inefficient'.",
	"Keeps an antique typewriter on the desk. Hates screens.",
	"Speaks in third person when angry.",
	"Has a prosthetic eye that visibly recalibrates when lying.",
	"Drinks only hand-bottled water from a single aquifer they personally own.",
	"Refers to every employee under 40 as 'the intern'.",
	"Wears the same three-piece suit every public appearance — custom-fit, seventy identical copies.",
	"Ends every phone call with 'Grow.'",
	"Collects first editions of books they've never read.",
	"Never sits down in meetings; stands at the head of a long table.",
	"Has a tremor in their left hand that worsens under scrutiny.",
	"Insists on being addressed by title, never by name, even by family.",
	"Keeps a private journal in a language they invented at age twelve.",
	"Named their private jet after their mother. Refuses to explain.",
	"Laughs with a short, dry bark; always once, never twice.",
]

const _NPC_FIRST := ["Jon", "Mara", "Kez", "Sasha", "Nimo", "Lex", "Ari", "Talon", "Briar", "Cress", "Dov", "Ember", "Fen", "Goro", "Hester", "Ivo", "Jory", "Kael", "Linna", "Mira", "Noa", "Oren", "Pax", "Quin", "Ro"]
const _NPC_LAST := ["Holt", "Varga", "Krill", "Strand", "Maelin", "Okonwe", "Pryce", "Shaw", "Teller", "Unger", "Vale", "Wexley", "Yarrow", "Zane", "Aker", "Brenn", "Cole", "Drake", "Ellery", "Faust", "Greene", "Hale", "Iman", "Juno", "Korr"]
const _NPC_QUIRKS := [
	"Keeps a notebook of every Enforcer badge number seen in the neighborhood.",
	"Prays before eating, even when there's nothing to eat.",
	"Voice is hoarse from a decade of factory fumes.",
	"Sleeps in the old hospital. Says the walls remember.",
	"Has a scar from a protest in their teens; touches it when lying.",
	"Whittles small wooden figures from scavenged planks.",
	"Reads old paperbacks in a language they can't fully understand.",
	"Remembers everyone's birthday. Writes them on their arm.",
	"Lost a sibling to a factory accident. Won't say which one.",
	"Hums the same melody when anxious — an ad jingle from before the Crisis.",
	"Brews their own black-market antibiotics in a squat kitchen.",
	"Carries a photograph of a neighborhood that no longer exists.",
	"Can name every kind of bird the Sinks used to have.",
	"Has memorized the name of every Enforcer who ever hit them.",
	"Runs a clandestine library in their apartment. 400 books.",
	"Was briefly a minor media personality. Now delivers packages.",
	"Keeps a list of politicians they would testify against.",
	"Speaks three languages; none of them are the official one.",
	"Saved a child from a roof collapse and never told anyone.",
	"Wears gloves indoors. Refuses to explain.",
	"Collects Enforcer propaganda and annotates it in red pen.",
	"Has a dog named after a dead resistance leader.",
	"Cried only once this decade. The NetFeed caught it.",
	"Shares a one-room apartment with five others. Knows them better than family.",
	"Teaches neighborhood kids to read in exchange for food.",
	"Has never been above the 15th floor of a building in their life.",
	"Knows every fire exit in a six-block radius by heart.",
	"Has a secret garden on a rooftop. Four plants, all wilting.",
	"Collects the Enclave's discarded luxury food wrappers.",
	"Paints graffiti of exact Senate vote tallies on alley walls.",
]

const _POLITICIAN_FIRST := ["Helena", "Marcus", "Oren", "Rafe", "Talia", "Vera", "Nolan", "Constance", "Ezra", "Dahlia", "Roman", "Sienna", "Julian", "Celia", "Garrick", "Maeve", "Hollis", "Phaedra", "Bastien", "Rosalind"]
const _POLITICIAN_LAST := ["Cain", "Oksana", "Krell", "Mirev", "Staub", "Voris", "Penrose", "Kastor", "Lindenmeyer", "Osric", "Wend", "Quaid", "Vernier", "Brassel", "Dorne", "Heath", "Marek", "Salinas", "Thorne", "Ulrich"]
const _POLITICIAN_TITLES := ["Senator", "Representative", "Speaker", "Committee Chair"]
const _POLITICIAN_CAUSES := ["labor", "law_and_order", "surveillance", "press_freedom", "austerity", "reform", "security", "economic_liberty", "public_health", "traditional_values"]
const _POLITICIAN_QUIRKS := [
	"Refers to constituents as 'the taxpayers' — never 'the people'.",
	"Ends every floor speech with the same line: 'And that is the will of the people.'",
	"Wears the same red tie to every vote. A staffer says it's for luck.",
	"Calls every opposing senator 'my distinguished friend' while voting against them.",
	"Has a tell — touches their left cuff before lying.",
	"Brings their own coffee to every committee. Refuses staff brews.",
	"Claps once, loudly, when they agree with a point. Otherwise stone-faced.",
	"Memorized the first amendment in seven languages; quotes it out of context.",
	"Speaks slowly on camera, fast in private. Noticeable.",
	"Wears a Sinks-made watch despite their salary.",
	"Has never voted against their own party; points this out often.",
	"Breaks pencils when irritated. Keeps a box on the desk.",
	"Smells faintly of tobacco despite public anti-smoking stance.",
	"Laughs politely at every joke, even the unfunny ones.",
	"Refers to the media as 'our friends in the balcony' — sincerely or sarcastically, never clear.",
]
# Faction distribution pool for 11 politicians (3-4 CORP, 2-3 POP, 2-3 REFORM, 2-3 IND)
const _POLITICIAN_FACTION_POOL := [
	"CORPORATE_BLOC", "CORPORATE_BLOC", "CORPORATE_BLOC", "CORPORATE_BLOC",
	"POPULIST", "POPULIST", "POPULIST",
	"REFORM", "REFORM",
	"INDEPENDENT", "INDEPENDENT",
]

# Region name pools per type
const _REGION_NAME_POOLS := {
	"URBAN_SLUM":     {"prefix": ["Rust", "Ash", "Gray", "Brine", "Soot", "Tar", "Ember", "Grit"], "suffix": ["Row", "Hollow", "Depths", "End", "Basin", "Warren", "Tier", "Court"]},
	"URBAN_ELITE":    {"prefix": ["Crystal", "Silver", "Solar", "Obsidian", "Marble", "Platinum", "Aurum", "Ivory"], "suffix": ["Heights", "Spire", "Plaza", "Court", "Terrace", "Gardens", "Arcade", "Promenade"]},
	"INDUSTRIAL":     {"prefix": ["Foundry", "Slag", "Iron", "Cinder", "Forge", "Torque", "Kiln", "Anvil"], "suffix": ["Basin", "Works", "Yard", "Pit", "Sprawl", "Mill", "Flats", "Junction"]},
	"AGRICULTURAL":   {"prefix": ["Substrate", "Root", "Loam", "Seedbank", "Hydro", "Fallow", "Husk", "Silage"], "suffix": ["Fields", "Beds", "Vaults", "Terraces", "Strip", "Reach", "Dome", "Acres"]},
	"ISLAND_RETREAT": {"prefix": ["Haven", "Obsidian", "Coral", "Pearl", "Azure", "Ember"], "suffix": ["Cay", "Atoll", "Isle", "Shoal", "Reef", "Point"]},
	"TRANSIT":        {"prefix": ["Checkpoint", "Border", "Passage", "Gate", "Corridor", "Marker"], "suffix": ["Nexus", "Point", "Lock", "Junction", "Pylon", "Stanza"]},
}

const _REGION_DESCRIPTIONS := {
	"URBAN_SLUM": "Concrete stacks under permanent fog. Barrel fires. Barter economy.",
	"URBAN_ELITE": "Glass spires fed by private utilities. Doormen check ID. Silence.",
	"INDUSTRIAL": "Refineries running three shifts. The air bends the light. Workers don't look up.",
	"AGRICULTURAL": "Monocrop terraces under grow lamps. Half the population is indentured.",
	"ISLAND_RETREAT": "Only reachable by private craft. The NetFeed pretends it doesn't exist.",
	"TRANSIT": "Checkpoints and scanners. The corridors everyone needs and nobody controls.",
}

# Bill templates grouped by faction for offline play
const _BILL_TEMPLATES := [
	{
		"_faction": "CORPORATE_BLOC",
		"title": "The Public Safety and Sanitation Directive",
		"summary": "Authorizes Enforcer units to clear non-compliant structures in designated urban zones, citing public health risk.",
		"stated_rationale": "Protecting citizens from the hazards of unregulated housing.",
		"honest_rationale": "Clears land in The Sinks for Enclave-adjacent logistics expansion.",
		"ideological_score": 0.7,
		"faction_preferences": {"CORPORATE_BLOC": 0.8, "POPULIST": -0.9, "REFORM": -0.6, "INDEPENDENT": 0.0},
		"proposed_effects": {"public_tension": 25, "security_presence": 15, "senate_alignment": 8},
		"scandal_hooks": ["Sponsor's family trust holds 40% of the land slated for 'clearance'."],
		"netfeed_flavor": "security-state framing; dissent cast as criminality",
	},
	{
		"_faction": "CORPORATE_BLOC",
		"title": "The Innovation and Competitiveness Act",
		"summary": "Caps corporate tax rates at pre-Crisis levels and extends R&D credits through the next decade.",
		"stated_rationale": "Restoring the conditions that made our companies global leaders.",
		"honest_rationale": "Direct transfer of public revenue to six private entities.",
		"ideological_score": 0.6,
		"faction_preferences": {"CORPORATE_BLOC": 0.9, "POPULIST": -0.7, "REFORM": -0.5, "INDEPENDENT": 0.1},
		"proposed_effects": {"senate_alignment": 10, "public_tension": 10, "food_price": 20},
		"scandal_hooks": ["Sponsor received large 'speaking fees' from the four largest beneficiaries."],
		"netfeed_flavor": "dry policy language; buried lede on who benefits",
	},
	{
		"_faction": "POPULIST",
		"title": "The Worker Relief Emergency Act",
		"summary": "Caps basic food prices and mandates minimum housing wages across all regions.",
		"stated_rationale": "Preventing mass starvation and displacement during the ongoing crisis.",
		"honest_rationale": "",
		"ideological_score": -0.6,
		"faction_preferences": {"CORPORATE_BLOC": -0.9, "POPULIST": 0.9, "REFORM": 0.5, "INDEPENDENT": 0.0},
		"proposed_effects": {"public_tension": -20, "food_price": -50, "senate_alignment": -8},
		"scandal_hooks": [],
		"netfeed_flavor": "populist rally language; framed as common-sense",
	},
	{
		"_faction": "POPULIST",
		"title": "The Citizen Oversight Commission Act",
		"summary": "Establishes a non-governmental oversight body to audit Enforcer conduct in the Sinks.",
		"stated_rationale": "Public confidence in enforcement requires transparency.",
		"honest_rationale": "",
		"ideological_score": -0.4,
		"faction_preferences": {"CORPORATE_BLOC": -0.6, "POPULIST": 0.8, "REFORM": 0.7, "INDEPENDENT": 0.1},
		"proposed_effects": {"security_presence": -10, "public_tension": -10, "senate_alignment": -5},
		"scandal_hooks": [],
		"netfeed_flavor": "civic-virtue framing",
	},
	{
		"_faction": "REFORM",
		"title": "The Corporate Transparency and Disclosure Act",
		"summary": "Requires publicly traded corporations to disclose all lobbying expenditures within 48 hours.",
		"stated_rationale": "Sunlight is the best disinfectant for public institutions.",
		"honest_rationale": "",
		"ideological_score": -0.3,
		"faction_preferences": {"CORPORATE_BLOC": -0.7, "POPULIST": 0.4, "REFORM": 0.9, "INDEPENDENT": 0.2},
		"proposed_effects": {"senate_alignment": -8, "public_tension": -5},
		"scandal_hooks": [],
		"netfeed_flavor": "measured reform tone; policy-wonkish",
	},
	{
		"_faction": "REFORM",
		"title": "The Independent Media Protection Act",
		"summary": "Creates legal shields for journalists reporting on corporate or governmental misconduct.",
		"stated_rationale": "A functioning democracy requires a press that cannot be silenced.",
		"honest_rationale": "",
		"ideological_score": -0.2,
		"faction_preferences": {"CORPORATE_BLOC": -0.8, "POPULIST": 0.5, "REFORM": 0.9, "INDEPENDENT": 0.3},
		"proposed_effects": {"senate_alignment": -6, "public_tension": -5},
		"scandal_hooks": [],
		"netfeed_flavor": "defensive procedural tone; quotes from press-rights advocates",
	},
	{
		"_faction": "INDEPENDENT",
		"title": "Omnibus Appropriations Amendment",
		"summary": "Adjusts sector allocations across the fiscal year based on quarterly projections.",
		"stated_rationale": "Routine fiscal responsibility.",
		"honest_rationale": "",
		"ideological_score": 0.1,
		"faction_preferences": {"CORPORATE_BLOC": 0.4, "POPULIST": -0.2, "REFORM": -0.1, "INDEPENDENT": 0.3},
		"proposed_effects": {"senate_alignment": 2},
		"scandal_hooks": [],
		"netfeed_flavor": "procedural; small print",
	},
	{
		"_faction": "INDEPENDENT",
		"title": "The Regional Stability Initiative",
		"summary": "Authorizes discretionary grants to regions experiencing unusual unrest or disruption.",
		"stated_rationale": "Maintaining basic order during a volatile period.",
		"honest_rationale": "",
		"ideological_score": 0.0,
		"faction_preferences": {"CORPORATE_BLOC": 0.2, "POPULIST": 0.2, "REFORM": 0.1, "INDEPENDENT": 0.5},
		"proposed_effects": {"public_tension": -5, "security_presence": 5},
		"scandal_hooks": [],
		"netfeed_flavor": "centrist; vaguely worded",
	},
]


# =============================================================
# OFFLINE EMITTERS — deferred so signal semantics match LLM path
# =============================================================

func _offline_emit_oligarchs(count: int) -> void:
	var out: Array = []
	var sectors_used: Array = []
	for i in range(count):
		var sector: String = _OLIGARCH_SECTORS[i % _OLIGARCH_SECTORS.size()]
		sectors_used.append(sector)
		out.append({
			"first_name": _OLIGARCH_FIRST.pick_random(),
			"last_name": _OLIGARCH_LAST.pick_random(),
			"title": _OLIGARCH_TITLES.pick_random(),
			"sector": sector,
			"ambitions": _pick_distinct(_OLIGARCH_AMBITIONS, randi_range(1, 2)),
			"quirks": _pick_distinct(_OLIGARCH_QUIRKS, randi_range(2, 3)),
		})
	oligarchs_generated.emit(out)


func _offline_emit_npcs(count: int) -> void:
	var out: Array = []
	for i in range(count):
		out.append({
			"first_name": _NPC_FIRST.pick_random(),
			"last_name": _NPC_LAST.pick_random(),
			"quirks": _pick_distinct(_NPC_QUIRKS, randi_range(2, 3)),
		})
	npc_roster_generated.emit(out)


func _offline_emit_regions(distribution: Dictionary) -> void:
	var out: Array = []
	for region_type in distribution.keys():
		var count: int = int(distribution[region_type])
		var used: Array = []
		for i in range(count):
			var nm: String = _generate_region_name(region_type, used)
			used.append(nm)
			out.append({
				"name": nm,
				"type": region_type,
				"short_description": _REGION_DESCRIPTIONS.get(region_type, ""),
			})
	world_regions_generated.emit(out)


func _offline_emit_politicians(count: int) -> void:
	var out: Array = []
	var factions: Array = _POLITICIAN_FACTION_POOL.duplicate()
	factions.shuffle()
	# Trim / pad to count
	while factions.size() < count:
		factions.append("INDEPENDENT")
	factions = factions.slice(0, count)
	for i in range(count):
		out.append({
			"first_name": _POLITICIAN_FIRST.pick_random(),
			"last_name": _POLITICIAN_LAST.pick_random(),
			"title": _POLITICIAN_TITLES.pick_random(),
			"faction": factions[i],
			"cause": _POLITICIAN_CAUSES.pick_random(),
			"seat_district": "At-Large",
			"quirks": [_POLITICIAN_QUIRKS.pick_random()],
		})
	politicians_generated.emit(out)


func _offline_emit_bill(request: Dictionary, callback: Callable) -> void:
	var bill: Dictionary = _synthesize_bill(request)
	if callback.is_valid():
		callback.call(bill)


func _offline_emit_netfeed(world: Dictionary, oligarchs: Dictionary) -> void:
	var events: Array = []
	var tension: int = int(world.get("public_tension", 50))
	var food_price: int = int(world.get("food_price", 100))
	var security: int = int(world.get("security_presence", 50))
	var senate: int = int(world.get("senate_alignment", 50))

	if tension > 60:
		events.append(_netfeed_event("NEWS_TICKER",
			"Unrest spreads across multiple Sinks blocks. Enforcer overtime authorized indefinitely.",
			"tension compounds; Sinks NPCs drift toward radicalization"))
	if food_price > 250:
		events.append(_netfeed_event("NEWS_TICKER",
			"Food price index hits %d. Lines at subsidized clinics double overnight." % food_price,
			"food-price driven desperation; workers more susceptible to extremist recruitment"))
	if security > 70:
		events.append(_netfeed_event("NEWS_TICKER",
			"Security saturation at historic highs. Officials deny curfew rumors.",
			"chilled street movement; sabotage harder, heat rises faster"))
	if senate < 30:
		events.append(_netfeed_event("NEWS_TICKER",
			"Senate swings against corporate interests in a late-night floor vote.",
			"political momentum shifts; oligarchs scramble to rebalance patronage"))
	elif senate > 70:
		events.append(_netfeed_event("NEWS_TICKER",
			"Senate passes industry-favorable measure by comfortable margin.",
			"corporate consolidation accelerates; worker NPCs trend toward despair"))

	# One oligarch-related beat if available
	if oligarchs.size() > 0:
		var name_key: String = oligarchs.keys().pick_random()
		events.append(_netfeed_event("NEWS_TICKER",
			"%s seen in private meeting with two senators. No statement issued." % name_key,
			"oligarch lobbying activity — patronage debt accruing"))

	if events.is_empty():
		events.append(_netfeed_event("NEWS_TICKER",
			"NetFeed quiet overnight. Ambient anxiety index unchanged.",
			"no major shifts"))

	netfeed_stream_received.emit(events)


func _offline_emit_npc_action(player_input: String) -> void:
	llm_response_received.emit({
		"success": false,
		"dialogue": "[offline mode] The NPC stares at you. 'What do you want.' ",
		"assigned_goal": "idle",
		"_player_input_echo": player_input,
	})


# =============================================================
# OFFLINE HELPERS
# =============================================================

func _pick_distinct(pool: Array, count: int) -> Array:
	var work: Array = pool.duplicate()
	work.shuffle()
	return work.slice(0, min(count, work.size()))


func _generate_region_name(region_type: String, already_used: Array) -> String:
	var pools: Dictionary = _REGION_NAME_POOLS.get(region_type, {})
	if pools.is_empty():
		return "Unknown Sector %d" % already_used.size()
	var prefixes: Array = pools.get("prefix", [])
	var suffixes: Array = pools.get("suffix", [])
	for _tries in range(24):
		var nm := "%s %s" % [prefixes.pick_random(), suffixes.pick_random()]
		if nm not in already_used:
			return nm
	return "%s %s %d" % [prefixes.pick_random(), suffixes.pick_random(), already_used.size()]


func _synthesize_bill(request: Dictionary) -> Dictionary:
	var sponsor_ctx: String = str(request.get("sponsor_context", ""))
	var faction: String = "INDEPENDENT"
	for f in ["CORPORATE_BLOC", "POPULIST", "REFORM", "INDEPENDENT"]:
		if f in sponsor_ctx:
			faction = f
			break

	var matching: Array = []
	for tpl in _BILL_TEMPLATES:
		if tpl.get("_faction", "") == faction:
			matching.append(tpl)
	if matching.is_empty():
		matching = _BILL_TEMPLATES

	var chosen: Dictionary = matching.pick_random().duplicate(true)
	chosen.erase("_faction")

	# Respect forbidden_topics — don't repeat a recent title.
	var forbidden: Array = request.get("forbidden_topics", [])
	if chosen.get("title", "") in forbidden and matching.size() > 1:
		var alternatives: Array = matching.duplicate()
		alternatives.shuffle()
		for alt in alternatives:
			if not (alt.get("title", "") in forbidden):
				chosen = alt.duplicate(true)
				chosen.erase("_faction")
				break

	return chosen


func _netfeed_event(type: String, headline: String, impact: String) -> Dictionary:
	return {
		"type": type,
		"headline": headline,
		"systemic_impact": impact,
	}
