extends HTTPRequest

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

# Cumulative usage for the current playthrough. Reset in initialize
# (when a new run starts). Surfaced in the debug overlay.
var total_prompt_tokens: int = 0
var total_completion_tokens: int = 0
var total_cost_usd: float = 0.0
var total_llm_calls: int = 0

# Gameplay toggles loaded from user_secrets.cfg [game] section.
# "procedural" (default) — fully made-up oligarchs.
# "alter_egos" — thinly-veiled fictionalizations of real billionaires.
var oligarch_mode: String = "procedural"

# Appended to system prompts that benefit from real-world resonance —
# NetFeed, bills, oligarchs, politicians. Offline paths ignore it.
# Intent: invite the model to echo historical/social-science/tech
# patterns as thematic resonance, without naming living people, real
# corporations, or real brands. Concepts are fair game.
const RESONANCE_NUDGE := """
SETTING IS PRESENT-DAY, NOT SCI-FI. This is TODAY's world, barely intensified — USA / EU / global north in the mid-2020s. No neural implants. No cyber-augmentations. No AR monocles. No biomods. No cybernetic eyes. No chrome limbs. No flying cars. No compliance AI embedded in people's brains. The horror is mundane and recognizable:

- Mass layoffs announced by Slack / 6am emails / recorded videos from HR
- Stock buybacks chosen over raises, hiring, or fixing the product
- PIP letters, algorithmic performance reviews, 'position eliminated' templates
- Insulin / chemo / ambulance bills; ER wait times; GoFundMe for basic care
- Encampment sweeps, eviction dockets, rent hikes, housing vouchers frozen
- Deportation raids, family separations, unaccompanied minors in warehouses
- Wage theft; tip pooling; 1099 reclassification; non-compete abuse
- Platform gig work (delivery apps, rideshare, mechanical-turk-style tasks)
- Pharmacy closures, food deserts, school bus cuts, pool closures
- Pandemic-era habits: long COVID, disability backlogs, remote-work retreat
- No-bid government contracts to connected firms
- Private equity rollups of nursing homes, vet clinics, local newspapers
- Climate disasters processed as 'acts of God' by insurers
- Children falling through safety nets — CPS overloaded, schools under-staffed, preventable deaths covered by single paragraphs on page B14
- AI-driven layoffs, offshoring, call-center replacement, legal-brief assistants

You MAY echo real-world events, social-science experiments, policy patterns, labor dynamics, and cultural movements as thematic resonance. NEVER name living people, real corporations, or real brands directly — but the ARCHETYPES and PATTERNS are fair game. NEVER invent futuristic tech. If you find yourself about to write 'neural', 'cyber-', 'bio-', 'implant', 'augment', 'AR visor', 'drone swarm', 'holographic' — stop and write something a real person could read in a real newspaper this year instead.
"""

# Bill generation uses a callback rather than a signal (single-fire, ergonomic
# from the caller's side). The pending callback is held here for the duration
# of one in-flight request.
var _bill_callback: Callable = Callable()
var _wc_gauntlet_callback: Callable = Callable()


func _ready() -> void:
	self.request_completed.connect(_on_request_completed)
	# Free-tier LLM endpoints sometimes stall for a long time. 60s is
	# long enough for slow models (Gemma-4 on OpenRouter free can take
	# 30-45s) but short enough that the game doesn't freeze forever.
	self.timeout = 60.0
	_initialize_provider()


func _initialize_provider() -> void:
	# Load optional secrets from res://user_secrets.cfg so macOS .app env-var
	# propagation issues don't block the LLM path. File is gitignored.
	# Format:
	#   [llm]
	#   openrouter_api_key="sk-or-v1-..."
	#   openrouter_model="google/gemma-4-31b-it:free"
	#   ; any other provider key is also honored (gemini_api_key, etc.)
	var secrets: ConfigFile = ConfigFile.new()
	var secrets_loaded: bool = secrets.load("res://user_secrets.cfg") == OK
	if secrets_loaded:
		print("LLMManager: Loaded user_secrets.cfg")
		# Read gameplay toggles.
		oligarch_mode = str(secrets.get_value("game", "oligarch_mode", "procedural")).to_lower()
		if not oligarch_mode in ["procedural", "alter_egos"]:
			push_warning("Unknown oligarch_mode=%s — defaulting to procedural." % oligarch_mode)
			oligarch_mode = "procedural"
		print("LLMManager: oligarch_mode=%s" % oligarch_mode)
	var _secret = func (env_name: String, cfg_key: String) -> String:
		var v: String = OS.get_environment(env_name)
		if v.is_empty() and secrets_loaded:
			v = str(secrets.get_value("llm", cfg_key, ""))
		return v

	var gemini_key: String = _secret.call("GEMINI_API_KEY", "gemini_api_key")
	var openai_key: String = _secret.call("OPENAI_API_KEY", "openai_api_key")
	var anthropic_key: String = _secret.call("ANTHROPIC_API_KEY", "anthropic_api_key")
	var qwen_key: String = _secret.call("QWEN_API_KEY", "qwen_api_key")
	var openrouter_key: String = _secret.call("OPENROUTER_API_KEY", "openrouter_api_key")
	var openrouter_model: String = _secret.call("OPENROUTER_MODEL", "openrouter_model")
	var local_url: String = _secret.call("LOCAL_LLM_URL", "local_llm_url")
	var local_model: String = _secret.call("LOCAL_LLM_MODEL", "local_llm_model")

	if not gemini_key.is_empty():
		active_provider = "gemini"
		api_key = gemini_key
		api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
		active_model = "gemini-1.5-pro-latest"
		print("LLMManager: Using Gemini API")

	elif not openai_key.is_empty():
		active_provider = "openai"
		api_key = openai_key
		api_url = "https://api.openai.com/v1/chat/completions"
		active_model = "gpt-4-turbo-preview"
		print("LLMManager: Using OpenAI API")

	elif not anthropic_key.is_empty():
		active_provider = "claude"
		api_key = anthropic_key
		api_url = "https://api.anthropic.com/v1/messages"
		active_model = "claude-3-opus-20240229"
		print("LLMManager: Using Claude API")

	elif not qwen_key.is_empty():
		active_provider = "qwen"
		api_key = qwen_key
		api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
		active_model = "qwen-max"
		print("LLMManager: Using Qwen API")

	elif not openrouter_key.is_empty():
		active_provider = "openrouter"
		api_key = openrouter_key
		api_url = "https://openrouter.ai/api/v1/chat/completions"
		active_model = openrouter_model
		if active_model.is_empty():
			active_model = "google/gemma-4-31b-it:free"
		print("LLMManager: Using OpenRouter API (model=%s)" % active_model)

	elif not local_url.is_empty():
		active_provider = "local"
		api_key = "local"
		api_url = local_url
		active_model = local_model
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
		call_deferred("_offline_emit_npc_action", npc, player_input)
		return
	current_request_type = "npc_action"
	var system_prompt := "You are the Game Master for a systemic immersive sim called KILL THE BILL.\n"
	system_prompt += "Evaluate the player's input against the following NPC state:\n"
	system_prompt += npc.get_llm_context_string() + "\n"
	system_prompt += "Respond strictly in JSON format with keys: 'success' (boolean), 'dialogue' (string), and 'assigned_goal' (string)."
	_send(system_prompt, player_input + "\n\nProvide your response purely in JSON format.", 1024, 0.7)


func request_netfeed_events(world_state: Dictionary, oligarchs: Dictionary, politicians: Dictionary = {}, npcs: Dictionary = {}) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_netfeed", world_state, oligarchs)
		return
	current_request_type = "netfeed_stream"
	var system_prompt := "You are the NetFeed curator for a systemic immersive sim called KILL THE BILL.\n"
	system_prompt += "The NetFeed is a TWITTER-STYLE stream — a chaotic mix of attributed posts, anonymous rumors, corporate press, citizen shitposting, compliance-AI anomalies, and third-party news. Each event is one short unit of content, like a social-media post.\n"
	system_prompt += "\n"
	system_prompt += "CURRENT WORLD:\n"
	system_prompt += "Economy: " + JSON.stringify(world_state) + "\n"
	system_prompt += "Oligarchs (companies they run, sectors, ambitions, personality profile): " + JSON.stringify(oligarchs) + "\n"
	if not politicians.is_empty():
		system_prompt += "Politicians (faction, approval, scandal level, corruption): " + JSON.stringify(politicians) + "\n"
	if not npcs.is_empty():
		system_prompt += "NPC sample (archetype, mood, trust-in-player): " + JSON.stringify(npcs) + "\n"
	system_prompt += _recent_world_context()
	system_prompt += "\n"
	system_prompt += "EVENT MIX — THE FEED IS EVENT-DRIVEN, NOT CITIZEN-DRIVEN:\n"
	system_prompt += "Each batch should feel like a real news stream. The CITY happens; people REACT. Distribution target (adjust +/- 1 per batch):\n"
	system_prompt += "  • 4-5 WORLD EVENTS (third-party news, wire copy, unsigned leaks, blotter items, market ticks). No byline. These are the DRIVERS — they describe things that HAPPEN in the city: arrests, strikes, rulings, audits, price moves, facility incidents, leaked memos, statistics.\n"
	system_prompt += "  • 2-3 ATTRIBUTED OLIGARCH / POLITICIAN POSTS reacting to (or CAUSING) those events. Oligarchs rage-bait; politicians spin.\n"
	system_prompt += "  • 1-2 NPC REACTIONS — react to world events or oligarch provocations from this batch or recent context. NPCs post occasionally, not every beat — aim for 1 NPC voice per batch on average, 2 when there's a lot to react to, 0 when the city is quiet. They are REACTORS, not ambient venters.\n"
	system_prompt += "  • 2-3 SILENT_RIPPLE impact events (see schema below) — these are the sim consequences of the world events and attributed posts.\n"
	system_prompt += "\n"
	system_prompt += "WORLD EVENT CATEGORIES — use ALL of these across a batch. Do NOT stay in one lane. A good batch has a little of everything:\n"
	system_prompt += "\n"
	system_prompt += "(A) MARKETS / WALL STREET — the markets are RIGGED and the feed must show it in PLAIN ENGLISH. A smart non-finance reader must get it in one line. Every item names a winner or a scam, in words anyone understands. STRIP OUT JARGON: no 'weekly calls at the 210 strike', no 'short interest as a % of float', no 'HFT desk', no 'dark pool', no 'spoofing pattern on the tape'. Translate every mechanic into what it actually IS — 'bought before the news dropped', 'sold right before the bad announcement', 'pocketed the gap'. Examples of the register we want:\n"
	system_prompt += "  * \"Vextol Capital's stock jumped 4% into the close. Eight hours later the company announces a government contract. Two board members bought the stock that same morning.\"\n"
	system_prompt += "  * \"Somebody placed a $2M bet on OmniCognition Labs' stock going up — twelve minutes before the Senate's closed-door AI vote. The bet paid out the next morning.\"\n"
	system_prompt += "  * \"Stroma Holdings is buying back its own stock: $1.2B worth. Arkady Stroma already owned a third of the company. When the company buys shares off the market, his slice gets bigger without him spending a penny.\"\n"
	system_prompt += "  * \"AstraCorp executives sold $47M of their own stock last week. Today the company cut its forecast and the stock fell 19%. Small investors took the loss. The executives had already cashed out.\"\n"
	system_prompt += "  * \"Senator Halden's son bought shares in a defense company three days before the arms bill markup. He sold them five days after the vote for a $380K profit. Filing was late. Fine: $200.\"\n"
	system_prompt += "  * \"Silvane Broadcast shares were hammered overnight — a coordinated selloff by two hedge funds that have done this twice before to other media companies. They make money when the price falls; the employees lose their 401(k) match.\"\n"
	system_prompt += "  * \"Kelp Logistics announced 'record profits' this morning and the stock jumped 6%. The same announcement laid off 2,400 warehouse workers. The severance budget: one month per worker.\"\n"
	system_prompt += "  * \"Threshold Research's earnings leaked to two terminals at 7:43am, before the public release. Whoever saw it first made a fortune in the first minute of trading. Pension funds that bought the open overpaid.\"\n"
	system_prompt += "  * \"Every time Senator Voris's committee meets behind closed doors, the stocks of the companies they discuss move in the RIGHT direction for her husband's portfolio within 24 hours. This has happened eleven times in a row.\"\n"
	system_prompt += "  * \"A single trader is putting up huge fake buy orders on AstraCorp all week, then pulling them before anyone can fill. It tricks the price higher by a few cents, which is worth millions when you're trading billions of shares. The regulator knows. Nothing has happened.\"\n"
	system_prompt += "VOICE NOTE for market items: write like a reporter explaining a scam to a neighbor, not a Bloomberg anchor. Use words like 'bet', 'cashed out', 'pocketed', 'got tipped off', 'loaded up', 'dumped'. Skip tickers, option strikes, and trading-desk jargon. If you catch yourself writing 'short interest', 'options activity', 'float', 'buyback window', 'basis points' — rewrite. Every item ends with SOMEONE WINNING or SOMEONE CAUGHT WITHOUT CONSEQUENCES.\n"
	system_prompt += "\n"
	system_prompt += "(B) CONGRESSIONAL INSIDER TRADING — representatives and their spouses trade on committee intel. STOCK Act exists but is unenforced. Disclosures are late, scrubbed, or filed by staffers. Examples:\n"
	system_prompt += "  * \"Senator Vera Voris's spouse disclosed a $475K purchase of Threshold Research Corp. stock two weeks before the Senate AI Safety Subcommittee opened hearings on the firm's contracts. Filing was 38 days late. Fine: $200.\"\n"
	system_prompt += "  * \"Rep. Marcus Fane sold his OmniCognition Labs position on the morning of the closed-door briefing. Legal. Reviewed. Re-legal.\"\n"
	system_prompt += "  * \"Third quarterly report in a row: members of the Banking Committee outperformed the index by 11 points. Ethics office says the pattern 'is not, in itself, evidence'.\"\n"
	system_prompt += "  * \"Periodic Transaction Reports filed at 11:58 pm on a Friday: four senators, combined $2.1M moved in and out of defense-contractor names during the week of the foreign-aid vote.\"\n"
	system_prompt += "\n"
	system_prompt += "(C) WAR / FOREIGN CONFLICT — present-day war coverage: border clashes, drone strikes, disputed territory, arms bills, contractor casualties, refugee numbers, maritime incidents, sanctions packages. Not sci-fi. Keep it grounded — real conflict vocabulary. Examples:\n"
	system_prompt += "  * \"Drone strike overnight on the eastern corridor. Defense Ministry confirms 'a legitimate target'; local press lists 11 dead, including three children. No independent verification.\"\n"
	system_prompt += "  * \"The Senate's $78B supplemental arms package cleared committee 14-9. Bane Private Security and two unlisted subcontractors are named recipients of the expanded training-mission line.\"\n"
	system_prompt += "  * \"Two contractors from Paperclip & Thorne, LLP confirmed killed in the southern sector. Families notified. The contracts remain classified.\"\n"
	system_prompt += "  * \"Sanctions package against the Northern bloc expanded to cover three additional banks. Stroma Holdings' FX desk quietly exited its exposure last quarter — the filings are public.\"\n"
	system_prompt += "  * \"Refugee numbers at the southern checkpoint now estimated at 40,000. The camp has food for nine days.\"\n"
	system_prompt += "\n"
	system_prompt += "(D) CITY / POLICE / LABOR / HOUSING — the grim local tape: arrests, strikes, rulings, audits, facility incidents, leaked memos. Examples:\n"
	system_prompt += "  * \"Metro Line 3 service suspended in District 14 following unsanctioned gathering at Platform 6.\"\n"
	system_prompt += "  * \"Food price index closed at 187 — highest since the August crash. Subsidized clinic lines doubled overnight.\"\n"
	system_prompt += "  * \"Two dead in a checkpoint altercation near the Transit pier. Identities withheld pending notification.\"\n"
	system_prompt += "  * \"Sinks Housing Cooperative wins class action 7-4. Enforcement of the ruling is 'under review'.\"\n"
	system_prompt += "  * \"Ministry of Labor announces 'efficiency audit' at three private-military contractors. No timeline given.\"\n"
	system_prompt += "\n"
	system_prompt += "(E) CORPORATE / REGULATORY / LEAKS — probes, leaked memos, whistleblowers, earnings spin, layoff announcements dressed as restructurings. Examples:\n"
	system_prompt += "  * \"Regulators opened a probe into Vextol Systems this morning. The firm has not responded to requests for comment.\"\n"
	system_prompt += "  * \"Internal Threshold Research memo obtained by this outlet lists 14 senators whose chat histories were ingested 'without explicit consent'. The author is now on 'indefinite leave'.\"\n"
	system_prompt += "  * \"AstraCorp's 'workforce realignment': 2,400 positions eliminated across the manufacturing division. The term 'layoff' does not appear in the filing.\"\n"
	system_prompt += "\n"
	system_prompt += "HARD RULE — each batch MUST include at least one (A) MARKET item and at least one (B) INSIDER-TRADING item. At least one (C) WAR item if a conflict is plausibly active. Don't skip them. These are the systems the player is fighting — they must appear in the feed.\n"
	system_prompt += "\n"
	system_prompt += "VOICE FOR WORLD EVENTS: wire-copy dry, concrete nouns and numbers, no flowery metaphors, no 'certainty-as-a-service' corporate jargon, no 'data vectors', no vague euphemisms unless you're quoting a spokesperson and clearly marking it as spin. Write like a tired beat reporter on deadline.\n"
	system_prompt += "\n"
	system_prompt += "OLIGARCH POSTS — RAGE-BAIT + APOLOGY PATTERN:\n"
	system_prompt += "Their attributed posts should sound like REAL BILLIONAIRE POSTS on X/LinkedIn. Casual, confident, mask-slightly-off. Not arch-villain monologues. Not 'Certainty-as-a-Service requires the integration of all data vectors' — that is awful writing; never do that. Use plain English, contractions, the occasional typo, the occasional 'lol'. Think Musk at 2am, Ackman before a short, Altman quote-tweeting a critic, an energy CEO dunking on a reporter.\n"
	system_prompt += "Pick from their ambitions / quirks and let them say something that would genuinely anger people in a collapsing city. Performative cruelty, false meritocracy, thinly-veiled contempt, self-aggrandizement — but in normal human voice. Examples:\n"
	system_prompt += "  * \"Arkady Stroma (Finance): people in the Sinks tell me rent is too high. sure. also they spend 60 cr a week on stims. there's no rent crisis, there's a choices crisis.\"\n"
	system_prompt += "  * \"Eldon Husk (Tech): if your job can be done by a 7yo with a calculator you probably shouldn't have the job. sorry. not sorry.\"\n"
	system_prompt += "  * \"Sam Altmen (AI): we're roughly three years from systems that do 40% of knowledge work. this is good actually. adapt or don't.\"\n"
	system_prompt += "  * \"Leo Strand (AI): been reading the takes on yesterday's launch. a lot of people confidently wrong about what inference costs actually are. it's fine, the market will sort it.\"\n"
	system_prompt += "  * \"Brice Halden (Finance): bought more this morning. this is not advice. but if it were, it would be: buy more.\"\n"
	system_prompt += "THEN: if the recent headlines context shows that oligarch's last post generated backlash (tension went up, follow-up posts mocked them, a story ran about protests outside their HQ), their NEXT post should be a hollow NON-APOLOGY — the corporate-PR voice, full of 'was taken out of context' and 'my team is reviewing' and 'I have always believed':\n"
	system_prompt += "  * \"Arkady Stroma (Finance): my remarks yesterday have been circulating in a way that doesn't reflect what I actually said. I have the deepest respect for the working families of The Sinks. My team will announce community investments in the coming weeks.\"\n"
	system_prompt += "The apology is obviously fake — no specifics, no action, blames the audience's interpretation. That's the whole point. Tension may or may not drop; if people see through it, another ripple hits.\n"
	system_prompt += "BAN LIST — these phrases and patterns are PROHIBITED in attributed posts: 'data vectors', 'certainty-as-a-service', 'integration of all', 'inevitable progress', 'paradigm', 'synergies', 'let that sink in', 'amateur observers', 'operational transfer', any phrase that sounds like a Palantir marketing deck. If you catch yourself writing one, rewrite it as a tweet a real person would post.\n"
	system_prompt += "\n"
	system_prompt += "SILENT_RIPPLE entries — invisible-to-player world shifts that the SIM APPLIES. Set 'headline' to \"\". Include an 'impact' dict that nudges world state. These ripples give you real causal power over the sim, but ONLY via the whitelisted keys + ranges below.\n"
	system_prompt += "\n"
	system_prompt += "IMPACT SCHEMA (for SILENT_RIPPLE events only):\n"
	system_prompt += "  {\n"
	system_prompt += "    \"public_tension_delta\":    int in [-5, +5],\n"
	system_prompt += "    \"security_presence_delta\": int in [-5, +5],\n"
	system_prompt += "    \"senate_alignment_delta\":  int in [-3, +3],\n"
	system_prompt += "    \"food_price_delta\":        int in [-20, +20],\n"
	system_prompt += "    \"tech_price_delta\":        int in [-50, +50],\n"
	system_prompt += "    \"oligarch\": { \"name\": \"<full name from list>\",\n"
	system_prompt += "                   \"controversy\":   int in [-10, +10],\n"
	system_prompt += "                   \"paranoia\":      int in [-10, +10],\n"
	system_prompt += "                   \"public_image\":  int in [-15, +15],\n"
	system_prompt += "                   \"wealth\":        int in [-50000, +50000] },\n"
	system_prompt += "    \"politician\": { \"name\": \"<full name from list>\",\n"
	system_prompt += "                     \"scandal\":   int in [-10, +10],\n"
	system_prompt += "                     \"approval\":  int in [-15, +15] }\n"
	system_prompt += "  }\n"
	system_prompt += "All keys optional; unknown keys ignored. Sim clamps to ranges + wraps state bounds.\n"
	system_prompt += "\n"
	system_prompt += "IMPORTANT: impact dicts can attach to NEWS_TICKER events TOO, not just SILENT_RIPPLE. If a headline describes something that WOULD move the sim, include the impact — the news the player reads should have visible consequences:\n"
	system_prompt += "  * Headline: 'Food price index hit 187 this morning.' → impact: { food_price_delta: +12, public_tension_delta: +2 }\n"
	system_prompt += "  * Headline: 'Regulators opened a probe into Vextol Systems.' → impact: { oligarch: { name: 'Arkady Stroma', controversy: +8, paranoia: +4 } }\n"
	system_prompt += "  * Headline: 'Metro Line 3 suspended after protests in District 14.' → impact: { public_tension_delta: +3, security_presence_delta: +2 }\n"
	system_prompt += "  * Headline: 'Eldon Husk: progress is uncomfortable.' (rage-bait) → impact: { public_tension_delta: +2, oligarch: { name: 'Eldon Husk', controversy: +4 } }\n"
	system_prompt += "A batch of 8-12 events should have ~4-6 impacts across all types. Headlines without plausible sim effects (pure flavor, graffiti) can have impact: null.\n"
	system_prompt += "Use SILENT_RIPPLE for consequences that shouldn't have a public headline (quiet shifts, things happening behind closed doors).\n"
	system_prompt += "\n"
	system_prompt += "VOICE — THIS IS THE MOST IMPORTANT THING:\n"
	system_prompt += "Write like real humans on a bad social-media platform in a collapsing city. NOT press releases. NOT corporate-sanitized summaries. NOT NPR voiceover. This is grim, funny, tired, paranoid, angry, mocking. Register shifts with who's talking:\n"
	system_prompt += "\n"
	system_prompt += "- NPCs (REACTORS, OCCASIONAL): An NPC posts when a specific world event or oligarch statement would move them. A Worker reacts to wage theft news; a Destitute reacts to food-price spikes; an Enforcer reacts to protests. Aim for ~1 NPC voice per batch. When they post, the voice is raw: half-sentences, defeated jokes, specific details, swearing implied. Example:\n"
	system_prompt += "  * \"Jon Holt (worker): another 6am shift. they moved the clock-in by 4 minutes so they don't have to pay overtime. i counted.\"\n"
	system_prompt += "  * \"Mara Vale (destitute): food index at 187. my kid asked why the soup is thinner this week. i said the numbers.\"\n"
	system_prompt += "\n"
	system_prompt += "- OLIGARCHS (RAGE-BAIT + APOLOGY): covered above. Combative-confident by default; fake-apology after backlash.\n"
	system_prompt += "\n"
	system_prompt += "- POLITICIANS: either hollow-earnest (CORPORATE_BLOC) or slippery-populist (POPULIST, REFORM). Subtweet rivals. Claim credit for bills. Dodge blame. Defend their trades. When scandal_level > 50 they sound cornered. Examples:\n"
	system_prompt += "  * \"Vera Voris (REFORM): I will not dignify the accusations circulating today with a response. My record speaks for itself. — sent from her assistant's phone.\"\n"
	system_prompt += "  * \"Marcus Fane (CORPORATE_BLOC): my family's trades are managed by an independent advisor. I don't direct them. I don't see them until they're disclosed. To suggest otherwise is a smear.\"\n"
	system_prompt += "  * \"Senator Hale (POPULIST): the banking committee saw the same Bloomberg screens everyone else saw. If you think that's insider trading you don't understand what insider trading is.\"\n"
	system_prompt += "\n"
	system_prompt += "- ANONYMOUS / CITY PULSE: unsigned fragments, chatroom excerpts, graffiti. Pure vibe — use sparingly as flavor, NOT as padding. Example:\n"
	system_prompt += "  * \"someone spray-painted 'eat them' on the checkpoint wall in district 14. it was washed off by 5am. someone wrote it again by noon.\"\n"
	system_prompt += "\n"
	system_prompt += "RULES:\n"
	system_prompt += "- NEVER reuse a line pattern from the recent-headlines context.\n"
	system_prompt += "- Reference actual economy numbers when plausible ('food_price hit 180 this morning').\n"
	system_prompt += "- Continue threads. If sabotage fired last cycle, someone is processing it. If a scandal broke, its target is posting or hiding. **THE PLAYER ACTS ON THIS WORLD** — when the recent-headlines context shows sabotage raids, clearing-house hits, leaked scandals, bribery leaks, or grid hacks, those are things the player (or an unknown operative) just DID. Write reactions from oligarchs (defensive, paranoid), politicians (damage control), NPCs (quiet delight or fear). The feed should acknowledge player actions the way a real news cycle acknowledges real events — even when nobody knows it was one person.\n"
	system_prompt += "- Randomness is a feature. A background NPC can comment on an oligarch. A politician can subtweet a rival without naming them. Sometimes nobody cares.\n"
	system_prompt += "- Satire, despair, dark humor, exhaustion, quiet fury, cold professionalism masking fear — all fair. Keep posts SHORT (one or two sentences, sometimes just a fragment).\n"
	system_prompt += RESONANCE_NUDGE
	system_prompt += "\n"
	system_prompt += "OUTPUT: 8–12 events per batch. The HUD drips NEWS_TICKER events to the player over time, and the SIM applies SILENT_RIPPLE impacts immediately. STRICT JSON, key 'events': array of { type: 'NEWS_TICKER'|'SILENT_RIPPLE', headline: string, impact: dict-or-null }. For NEWS_TICKER set headline to the post text, impact to null. For SILENT_RIPPLE set headline to \"\" and impact to the schema above."
	# High temperature for variety — this is the MOST important request
	# for run texture. Repetition breaks the illusion.
	_send(system_prompt, "Generate the feed now. JSON only.", 1200, 1.1)


func request_oligarch_generation(count: int) -> void:
	if use_offline_fallback:
		call_deferred("_offline_emit_oligarchs", count)
		return
	current_request_type = "oligarch_generation"
	var system_prompt := "You are the Architect for a systemic immersive sim called KILL THE BILL.\n"
	system_prompt += "Generate " + str(count) + " unique corporate oligarchs. The setting is PRESENT-DAY (mid-2020s, recognizably our world, late-capitalist, austerity-and-AI flavored) — NOT sci-fi. Use contemporary archetypes and language. No cyber-augmentations, neural implants, AR monocles, or any other futuristic tech in their quirks.\n"
	system_prompt += "HARD REQUIREMENT: at least 2 oligarchs must be sector='AI' and at least 2 must be sector='Tech' (internet platforms). The remaining slots can be any other sector. This reflects the real-world concentration of power in AI labs and consumer internet — both must be represented.\n"

	if oligarch_mode == "alter_egos":
		system_prompt += "\nMODE: ALTER-EGOS — each oligarch must be a thinly-veiled FICTIONALIZATION of a real contemporary billionaire. Use PHONETIC NAME SHIFTS (e.g. 'Eldon Husk' for Musk, 'Geoff Brazos' for Bezos, 'Mark Sugarmountain' for Zuckerberg, 'Alex Sharp' for Karp, 'Bernard Arnaud' for Arnault, 'Peter Steel' for Thiel, 'Will Gales' for Gates, 'Rupert Murdouk' for Murdoch). NEVER use the real person's actual name.\n"
		system_prompt += "Pull from across the global billionaire class (US, European, Asian). Capture the PUBLICLY-DISCUSSED ARCHETYPE, not invented scandals:\n"
		system_prompt += "- Musk-archetype: vain + intelligent + ideological, Tech, 'Transcend humanity'\n"
		system_prompt += "- Bezos-archetype: greedy + ruthless, Food/retail logistics, 'Monopolize supply'\n"
		system_prompt += "- Zuckerberg-archetype: paranoid + intelligent, Media, 'Control the narrative'\n"
		system_prompt += "- Karp-archetype: ideological + intelligent + ruthless, Security/surveillance, 'Crush the resistance' or 'Purge The Sinks'\n"
		system_prompt += "- Arnault-archetype: vain + greedy, Luxury (→ Media sector), 'Build a legacy'\n"
		system_prompt += "- Thiel-archetype: paranoid + ideological, Finance, 'Escape' or 'Achieve political immortality'\n"
		system_prompt += "- Gates-archetype: vain-in-philanthropy + intelligent, Pharma, 'Build a legacy'\n"
		system_prompt += "- Murdoch-archetype: ruthless + ideological, Media, 'Control the narrative'\n"
		system_prompt += "- Altman-archetype: vain + ideological + intelligent, AI, 'Transcend humanity' / 'Monopolize supply'\n"
		system_prompt += "- Amodei-archetype: paranoid + intelligent + ideological (safety-focused), AI, 'Transcend humanity' / 'Control the narrative'\n"
		system_prompt += "- Hassabis-archetype: vain + highly intelligent (research-prestige), AI, 'Transcend humanity' / 'Build a legacy'\n"
		system_prompt += "- Huang-archetype: greedy + intelligent + showman-vain, AI infrastructure (chips + GPU), 'Monopolize supply'\n"
		system_prompt += "Each oligarch object should include a 'traits' dict with floats 0.0-1.0 for: ruthlessness, vanity, paranoia_base, intelligence, greed, ideology. Set them to match the archetype. Provide: first_name, last_name, title (e.g. 'Founder & CEO'), sector (Food/Tech/Security/Media/Pharma/Energy/Finance), company_name (made-up brand echoing the real one — AstraCorp for Tesla, Kelp Logistics for Amazon, Palladium Analytica for Palantir), traits (6 floats), 2-3 ambitions, 2-3 quirks. Quirks should reference real-world public behavior patterns (a Mars-fixated tech founder's quirks look different from a luxury-conglomerate CEO's).\n"
	else:
		system_prompt += "Each oligarch is the FOUNDER & CEO (or equivalent) of a single corporate entity they built. Provide:\n"
		system_prompt += "- first_name, last_name (person)\n"
		system_prompt += "- title (e.g. 'Founder & CEO', 'Chairman & CEO', 'Director-General', 'Chief Architect')\n"
		system_prompt += "- sector: ONE OF {Food, Tech, Military, Media, Pharma, Energy, Finance, AI} — this is the INDUSTRY CATEGORY, never the company name. 'Military' is private-military / defense-contractor. 'AI' is frontier-model labs + compute infrastructure.\n"
		system_prompt += "- company_name: a PLAUSIBLE MADE-UP BRAND (e.g. 'Vextol Capital Partners', 'Paperclip & Thorne, LLP', 'Bane Private Security', 'Silvane Broadcast Network'). NEVER use the raw sector word ('Finance', 'Media', 'Pharma' etc.) as the company name. Names should sound like real-world corporate entities — LLPs, Holdings, Systems, Capital, Group, Trust, Co., Corp., etc.\n"
		system_prompt += "- 2-3 ambitions, 2-3 quirks\n"
		system_prompt += "Sectors MAY repeat, and some sectors may be absent — real oligarchies cluster rather than evenly distribute. Personality diversity matters more than sector diversity. Some ideological, some greedy, some paranoid, some vain.\n"

	system_prompt += RESONANCE_NUDGE
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
	system_prompt += RESONANCE_NUDGE
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
	var system_prompt := "You are the Bill Drafter for KILL THE BILL's Senate. This is a PRESENT-DAY legislative chamber — mid-2020s, recognizably our world. NOT sci-fi.\n"
	system_prompt += "Generate ONE bill this sponsor would propose this week, given world state and active oligarch ambitions.\n"
	system_prompt += "\n"
	system_prompt += "Sponsor: " + str(request.get("sponsor_context", "")) + "\n"
	system_prompt += "World: " + JSON.stringify(request.get("world_snapshot", {})) + "\n"
	system_prompt += "Recent NetFeed: " + JSON.stringify(request.get("recent_netfeed", [])) + "\n"
	system_prompt += "Active oligarch ambitions: " + JSON.stringify(request.get("active_oligarch_ambitions", [])) + "\n"
	system_prompt += "Forbidden (don't repeat): " + JSON.stringify(request.get("forbidden_topics", [])) + "\n"
	var cooldown_titles: Array = request.get("cooldown_failed_titles", [])
	var cooldown_days: int = int(request.get("cooldown_window_days", 90))
	if cooldown_titles.size() > 0:
		system_prompt += "COOLDOWN — these bills failed in the Senate within the last " + str(cooldown_days) + " in-game days and CANNOT be re-proposed (even slightly reworded): " + JSON.stringify(cooldown_titles) + ". Pick a different subject.\n"
	system_prompt += "Effect whitelist (stay in range): " + JSON.stringify(request.get("effect_whitelist", {})) + "\n"
	system_prompt += _recent_world_context()
	system_prompt += "\n"
	system_prompt += "CENTRAL THESIS — READ THIS FIRST. The Senate is captured. Every bill proposed MUST, on net, MAKE ORDINARY PEOPLE'S LIVES WORSE and BENEFIT ELITES (oligarchs, big corporations, the sponsor's donors and family, other senators' portfolios). This is the whole game. The player is trying to stop it.\n"
	system_prompt += "- The bill must have a NAMED WINNER (a specific oligarch, a specific sector PAC, or the sponsor's own finances) and a NAMED LOSER (a specific working-class group: Sinks tenants, gig workers, diabetics, veterans, unionized dock workers, Medicaid recipients, delivery drivers, etc.).\n"
	system_prompt += "- POPULIST and REFORM sponsors sometimes PERFORM opposition but the mechanism still leaks value upward. They water their own bill down with an exemption, a carve-out, a 'pilot program' scope, or a sunset the lobby extracted. Make the betrayal legible in honest_rationale.\n"
	system_prompt += "- CORPORATE_BLOC sponsors don't bother hiding it. Their stated_rationale is thin, their honest_rationale is blunt about who gets paid.\n"
	system_prompt += "- EVERY honest_rationale must name at least one of: a dollar amount transferred, a named beneficiary (oligarch, company, PAC, or the sponsor themselves), or a specific population harmed with an approximate count. No exceptions.\n"
	system_prompt += "- EVERY scandal_hook must be a concrete conflict of interest: spouse's trades, campaign donors, prior employment, language drafted by a named lobby, committee chair's equity holdings. 'Optics concerns' and 'ethics questions' are BANNED.\n"
	system_prompt += "\n"
	system_prompt += "HARD RULES — every bill MUST name concrete, legible mechanics. VAGUE IS BANNED.\n"
	system_prompt += "- Title names a SPECIFIC target (a program, a population, a dollar figure, a sector). Bad: 'Omnibus Appropriations Amendment'. Good: 'Sinks Rental Assistance Sunset Act', 'Private Contractor Immunity Act of M3', 'Training-Cluster Zoning Override', 'Tip-Credit Restoration and Gig-Worker Reclassification Bill'.\n"
	system_prompt += "- Summary is 1-2 short sentences stating EXACTLY what changes. Include at least one NUMBER or SPECIFIC GROUP. Bad: 'Adjusts sector allocations based on quarterly projections.' Good: 'Cuts the Sinks rental-assistance budget by 23% and redirects the funds to three Enclave-adjacent luxury-housing tax credits. Sunset clause removed.' \n"
	system_prompt += "- stated_rationale is the sponsor's PUBLIC pitch — euphemistic but naming the SAME specifics. Good: 'Refocusing housing investment on productivity-generating districts to grow the tax base for all residents.'\n"
	system_prompt += "- honest_rationale is what it ACTUALLY does in 1 sentence. Good: 'Transfers $340M from low-income tenants to three landlords close to the sponsor.' If sponsor is CORPORATE_BLOC, this should name the beneficiary specifically.\n"
	system_prompt += "- scandal_hooks: 2-3 concrete hooks — a dollar amount, a named interest, a conflict of interest, a prior vote contradicting this one. Not vague.\n"
	system_prompt += "\n"
	system_prompt += "BILL SUBJECTS (pick one thread per bill, mix across batches):\n"
	system_prompt += "  * Rent / housing: voucher caps, eviction moratorium sunsets, zoning overrides, tenant-screening rules, rent-control rollbacks\n"
	system_prompt += "  * Labor: tip credit, non-compete enforcement, 1099 reclassification, mandatory-arbitration expansion, right-to-organize\n"
	system_prompt += "  * Healthcare: insulin cap, ER triage billing, Medicaid work requirements, drug-import parity, ambulance-billing reform\n"
	system_prompt += "  * Taxation: capital-gains brackets, stock-buyback surcharge, carried-interest loophole, estate tax, corporate minimum\n"
	system_prompt += "  * Criminal / enforcement: mandatory minimums, encampment clearance, immigration enforcement, private-prison contracts\n"
	system_prompt += "  * Corporate governance: no-bid contracts to named sectors, antitrust carveouts, data-privacy preemption, AI-training-data disclosure\n"
	system_prompt += "  * Social safety net: SNAP cuts, childcare subsidies, unemployment window, disability backlog, school-funding formulas\n"
	system_prompt += "  * Environment / climate: insurance-coverage mandates, FEMA formula changes, pipeline fast-tracks, carbon-price rollbacks\n"
	system_prompt += "\n"
	system_prompt += "THE BILL MUST CONNECT TO THE RUN: reference a recent NetFeed event, an active oligarch ambition, or current world numbers (food_price, tension, senate_alignment). If an oligarch's ambition is 'Monopolize supply' and food_price is up, the CORPORATE_BLOC sponsor drops a bill repealing anti-price-gouging rules. If public_tension is 70, a POPULIST drops a bill extending the eviction moratorium. If REFORM is sponsoring, the bill actually threatens oligarch profits — don't soften it.\n"
	system_prompt += RESONANCE_NUDGE
	system_prompt += "Respond STRICTLY in JSON with keys: title, summary, stated_rationale, honest_rationale, ideological_score (-1..+1), faction_preferences (all 4 factions, -1..+1), proposed_effects (only whitelisted keys), scandal_hooks (array), netfeed_flavor."
	_send(system_prompt, "Draft the bill in JSON. Specific, concrete framing — real-world policy vocabulary. No bureaucratic filler.", 1024, 0.85)


# =============================================================
# WHITE-COLLAR INTERVIEW GAUNTLET
# =============================================================
#
# Generate a 3-question absurdist interview for a listing. Each
# question has 4 options; every option ships with a rejection fragment
# the game stitches into a final rejection letter when the player is
# (likely) rejected.
#
# The listing dict carries title, company, description, monthly_salary.
# Callback receives the parsed gauntlet dict, or an empty dict on
# failure (GigBoard falls back to its offline pool in that case).
func request_wc_gauntlet(listing: Dictionary, callback: Callable) -> void:
	if use_offline_fallback:
		call_deferred("_emit_wc_gauntlet_fallback", callback)
		return
	current_request_type = "wc_gauntlet"
	_wc_gauntlet_callback = callback
	var system_prompt := "You are the Interview Panel Chair for a late-capitalist corporate role in KILL THE BILL.\n"
	system_prompt += "The job exists to humiliate applicants through plausibly-professional absurdity.\n"
	system_prompt += "Generate ONE interview gauntlet: 3 distinct questions, each with exactly 4 multiple-choice options.\n"
	system_prompt += "Every question must feel like a real corporate interview question taken just one degree too far.\n"
	system_prompt += "Examples of the register: estimation brain-teasers with hidden value-judgments, behavioral questions phrased to punish honest answers, brand-personality questions, weakness questions where any answer fails a stated rule.\n"
	system_prompt += "Each of the 4 options must sound like a plausible real answer a candidate would give.\n"
	system_prompt += "EVERY option must also carry a 'rejection_fragment' — a short clause (one sentence, no period) that a hiring panel would later cite as grounds for rejecting THIS specific answer. Fragments should sound like real HR-speak: bureaucratic, passive-voice, faintly condescending.\n"
	system_prompt += "Fragments will be stitched together into a final rejection letter, so keep them grammatical as mid-sentence clauses.\n"
	system_prompt += "Job listing:\n"
	system_prompt += "- Title: " + str(listing.get("title", "")) + "\n"
	system_prompt += "- Company: " + str(listing.get("company", "")) + "\n"
	system_prompt += "- Description: " + str(listing.get("description", "")) + "\n"
	system_prompt += "- Posted salary: %d cr/month\n" % int(listing.get("monthly_salary", 0))
	system_prompt += "Reference the title, company, or description in at least one question to make it feel tailored to this listing.\n"
	system_prompt += "Respond STRICTLY as JSON: {\"questions\": [{\"prompt\": string, \"options\": [{\"label\": string, \"rejection_fragment\": string}] (exactly 4)}] (exactly 3)}."
	_send(system_prompt, "Draft the gauntlet as JSON only. No preamble, no markdown.", 1200, 0.95)


func _emit_wc_gauntlet_fallback(callback: Callable) -> void:
	# Offline path — GigBoard.build_interview_gauntlet handles the pool
	# assembly. Callback gets {} so GigBoard knows to fall back.
	if callback.is_valid():
		callback.call({})


# Zero the running token + cost totals for a fresh playthrough.
# WorldDirector.initialize_playthrough calls this.
func reset_usage_totals() -> void:
	total_prompt_tokens = 0
	total_completion_tokens = 0
	total_cost_usd = 0.0
	total_llm_calls = 0


# =============================================================
# HTTP pipeline
# =============================================================

# Compose a block of "what has happened so far in this run" that the
# model can browse — last N NetFeed headlines, recent Senate outcomes,
# currently-active cameo arcs. This gives the LLM a working memory so
# calls within a run can continue threads (the bread thief accomplices,
# the Soap Man's graffiti echoing, a prior oligarch retaliating) instead
# of generating disconnected blurbs.
func _recent_world_context() -> String:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return ""

	var sections: Array = []

	# Last 8 NetFeed headlines, most recent first, skipping silent ripples.
	var netfeed: Array = wd.netfeed_history
	if netfeed.size() > 0:
		var recent_headlines: Array = []
		for i in range(netfeed.size() - 1, -1, -1):
			if recent_headlines.size() >= 8:
				break
			var h: String = str(netfeed[i].get("headline", ""))
			if h != "":
				recent_headlines.append("- " + h)
		if recent_headlines.size() > 0:
			sections.append("Recent NetFeed headlines (most recent first):\n" + "\n".join(recent_headlines))

	# Last 3 Senate outcomes
	var senate := get_node_or_null("/root/SenateDirector")
	if senate and senate.bill_history.size() > 0:
		var recent_bills: Array = []
		var start: int = max(0, senate.bill_history.size() - 3)
		for i in range(start, senate.bill_history.size()):
			var b = senate.bill_history[i]
			recent_bills.append("- %s [%s, margin %+d]" % [
				str(b.get("title", "")),
				str(b.get("result", "")),
				int(b.get("margin", 0)),
			])
		if recent_bills.size() > 0:
			sections.append("Recent Senate outcomes:\n" + "\n".join(recent_bills))

	# Active cameo arcs
	var cameos := get_node_or_null("/root/CulturalCameos")
	if cameos and cameos.active_arcs.size() > 0:
		var active_lines: Array = []
		for arc in cameos.active_arcs:
			if bool(arc.get("completed", false)):
				continue
			var def: Dictionary = arc.get("definition", {})
			active_lines.append("- %s (%s, %d cycles left)" % [
				str(def.get("name", "")),
				str(def.get("archetype", "")),
				int(arc.get("cycles_left", 0)),
			])
		if active_lines.size() > 0:
			sections.append("Ongoing cultural arcs (do NOT restate their intro, but you may echo their tone):\n" + "\n".join(active_lines))

	if sections.is_empty():
		return ""
	return "\n# Run history so far\n\n" + "\n\n".join(sections) + "\n"


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
		llm_error_occurred.emit("HTTP Request failed (type=%s). result=%d response_code=%d Body: %s" % [
			current_request_type, result, response_code, body.get_string_from_utf8(),
		])
		_fallback_to_offline_for_current_request()
		return

	var outer := JSON.new()
	if outer.parse(body.get_string_from_utf8()) != OK:
		llm_error_occurred.emit("Failed to parse outer API response.")
		_fallback_to_offline_for_current_request()
		return

	var data = outer.get_data()
	var message_content: String = ""
	if active_provider == "claude":
		if data.has("content") and data["content"].size() > 0:
			message_content = data["content"][0].get("text", "")
	else:
		if data.has("choices") and data["choices"].size() > 0:
			message_content = data["choices"][0].get("message", {}).get("content", "")

	# Log usage + a preview of the model's answer so the Output panel
	# shows what the LLM actually said, how many tokens it cost, and —
	# when the provider supplies it — a dollar cost.
	_log_llm_response(data, message_content)

	if message_content == "":
		llm_error_occurred.emit("Unexpected LLM response format. Raw outer: " + body.get_string_from_utf8())
		_fallback_to_offline_for_current_request()
		return

	# Some OpenRouter models return prose around a JSON block. Strip
	# ```json fences and leading/trailing text so the nested parse
	# doesn't die on well-formed-but-wrapped responses.
	var stripped_content: String = _strip_json_fences(message_content)

	var inner := JSON.new()
	if inner.parse(stripped_content) != OK:
		llm_error_occurred.emit("Failed to parse LLM nested JSON. Raw: " + message_content)
		_fallback_to_offline_for_current_request()
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
				_fallback_to_offline_for_current_request()
		"oligarch_generation":
			if parsed.has("oligarchs"):
				oligarchs_generated.emit(parsed["oligarchs"])
			else:
				llm_error_occurred.emit("Oligarch response missing 'oligarchs' array.")
				_fallback_to_offline_for_current_request()
		"npc_roster_generation":
			if parsed.has("npcs"):
				npc_roster_generated.emit(parsed["npcs"])
			else:
				llm_error_occurred.emit("NPC response missing 'npcs' array.")
				_fallback_to_offline_for_current_request()
		"world_regions_generation":
			if parsed.has("regions"):
				world_regions_generated.emit(parsed["regions"])
			else:
				llm_error_occurred.emit("Region response missing 'regions' array.")
				_fallback_to_offline_for_current_request()
		"politician_generation":
			if parsed.has("politicians"):
				politicians_generated.emit(parsed["politicians"])
			else:
				llm_error_occurred.emit("Politician response missing 'politicians' array.")
				_fallback_to_offline_for_current_request()
		"bill_generation":
			if _bill_callback.is_valid():
				_bill_callback.call(parsed)
				_bill_callback = Callable()
		"wc_gauntlet":
			if _wc_gauntlet_callback.is_valid():
				_wc_gauntlet_callback.call(parsed if typeof(parsed) == TYPE_DICTIONARY else {})
				_wc_gauntlet_callback = Callable()


# Whenever an LLM request fails (HTTP, timeout, malformed response),
# route to the offline synthesizer for that request type so the game
# can't freeze waiting on a signal that'll never come.
func _fallback_to_offline_for_current_request() -> void:
	print("LLMManager: falling back to offline for request_type=%s" % current_request_type)
	match current_request_type:
		"oligarch_generation":
			call_deferred("_offline_emit_oligarchs", 5)
		"npc_roster_generation":
			call_deferred("_offline_emit_npcs", 40)
		"world_regions_generation":
			call_deferred("_offline_emit_regions", {})
		"politician_generation":
			call_deferred("_offline_emit_politicians", 11)
		"netfeed_stream":
			# Give the offline stream the current economy snapshot so
			# the fallback still reads the right world state.
			var wd = get_node_or_null("/root/WorldDirector")
			var econ: Dictionary = wd.global_economy if wd else {}
			call_deferred("_offline_emit_netfeed", econ, {})
		"bill_generation":
			if _bill_callback.is_valid():
				_bill_callback.call({})
				_bill_callback = Callable()
		"wc_gauntlet":
			if _wc_gauntlet_callback.is_valid():
				_wc_gauntlet_callback.call({})
				_wc_gauntlet_callback = Callable()


# Log the LLM's raw answer + token usage + (when supplied) cost, so the
# Output panel gives a full picture of each call — what the model said,
# how expensive it was, and which call it was for.
# OpenRouter + OpenAI put usage under `usage`; Anthropic uses `usage`
# with `input_tokens` / `output_tokens`. Cost is OpenRouter-specific.
func _log_llm_response(outer_data: Dictionary, message_content: String) -> void:
	var preview: String = message_content.strip_edges()
	# Keep the preview readable in the Output panel — cap length.
	if preview.length() > 600:
		preview = preview.substr(0, 600) + "…"
	print("--- LLM ANSWER [%s, model=%s] ---" % [current_request_type, active_model])
	print(preview)

	var usage = outer_data.get("usage", null)
	if usage == null or typeof(usage) != TYPE_DICTIONARY:
		print("--- LLM USAGE [no usage block in response] ---")
		return

	var prompt_tok: int = 0
	var completion_tok: int = 0
	var total_tok: int = 0
	if usage.has("prompt_tokens"):
		prompt_tok = int(usage.prompt_tokens)
	elif usage.has("input_tokens"):       # Anthropic naming
		prompt_tok = int(usage.input_tokens)
	if usage.has("completion_tokens"):
		completion_tok = int(usage.completion_tokens)
	elif usage.has("output_tokens"):      # Anthropic naming
		completion_tok = int(usage.output_tokens)
	total_tok = int(usage.get("total_tokens", prompt_tok + completion_tok))

	var call_cost: float = 0.0
	if usage.has("cost"):
		call_cost = float(usage.cost)
	elif usage.has("total_cost"):
		call_cost = float(usage.total_cost)
	# If the provider didn't return a cost, estimate from DeepSeek v3.2
	# published rates ($0.259/M prompt, $0.42/M completion). Rough but
	# enough to warn the player when a run is drifting expensive.
	if call_cost <= 0.0 and active_model.begins_with("deepseek/"):
		call_cost = (float(prompt_tok) * 0.000000259) + (float(completion_tok) * 0.00000042)

	total_prompt_tokens += prompt_tok
	total_completion_tokens += completion_tok
	total_cost_usd += call_cost
	total_llm_calls += 1
	# Tell WorldDirector to refresh state-panel subscribers (HUD) so the
	# debug LLM-spend line updates visibly as calls complete.
	var wd := get_node_or_null("/root/WorldDirector")
	if wd:
		wd.world_state_changed.emit()

	var cost_str: String = "  cost=$%.6f" % call_cost if call_cost > 0.0 else ""
	print("--- LLM USAGE  prompt=%d  completion=%d  total=%d%s ---" % [
		prompt_tok, completion_tok, total_tok, cost_str,
	])
	print("--- LLM RUN TOTAL  calls=%d  prompt=%d  completion=%d  cost=$%.4f ---" % [
		total_llm_calls, total_prompt_tokens, total_completion_tokens, total_cost_usd,
	])


# Strip ```json ... ``` fences and any leading/trailing prose around a
# JSON object. Many free-tier instruction-tuned models (Gemma, Llama)
# wrap JSON in markdown fences despite response_format hints.
func _strip_json_fences(raw: String) -> String:
	var s: String = raw.strip_edges()
	# Remove opening fence (```json or ```)
	if s.begins_with("```"):
		var first_newline: int = s.find("\n")
		if first_newline != -1:
			s = s.substr(first_newline + 1)
	# Remove closing fence
	if s.ends_with("```"):
		s = s.substr(0, s.length() - 3).strip_edges()
	# If the model wrapped JSON inside prose, extract the outermost
	# {...} block. Simple heuristic — find first { and last }.
	var first_brace: int = s.find("{")
	var last_brace: int = s.rfind("}")
	if first_brace > 0 and last_brace > first_brace:
		s = s.substr(first_brace, last_brace - first_brace + 1)
	return s


# =============================================================
# OFFLINE FALLBACK CONTENT POOLS
# =============================================================

const _OLIGARCH_FIRST := ["Veldra", "Korr", "Lysandra", "Arkady", "Mara", "Thessaly", "Orlan", "Verity", "Cyrus", "Nadia", "Erastus", "Felina", "Roderic", "Indra", "Sevrin", "Mabel", "Yusef", "Ophira", "Callum", "Delphine"]
const _OLIGARCH_LAST := ["Vextol", "Krynne", "Aurelius", "Stroma", "Bane", "Oksmarra", "Gant", "Throne", "Varik", "Silvane", "Okonjo", "Trell", "Verhovskiy", "Quell", "Drax", "Zhao-Pax", "Hollis", "Karst", "Dain", "Wyler"]
const _OLIGARCH_TITLES := ["Founder & CEO", "Chairman & CEO", "Founder & Chairman", "Director-General", "Chief Architect"]
const _OLIGARCH_SECTORS := ["Food", "Tech", "Military", "Media", "Pharma", "Energy", "Finance", "AI"]

# Made-up company names per sector. Each oligarch founds/runs one of
# these; the sector is the CATEGORY their company belongs to. Names
# should sound plausible-corporate but own nothing real — never use
# "Finance", "Media", "Pharma" etc. as the literal brand.
# Thinly-veiled fictionalizations of real contemporary billionaires.
# Used when oligarch_mode = "alter_egos". Each entry encodes the public
# archetype (vain, paranoid, ruthless, etc.) + the kind of company they
# built. Names are phonetic shifts — never the real person's name.
# Traits here OVERRIDE WorldDirector's random rolls so the archetype
# lands. Ambitions match their publicly-discussed motives.
const _ALTER_EGO_POOL: Array[Dictionary] = [
	{
		"first_name": "Eldon",
		"last_name": "Husk",
		"title": "Founder & CEO",
		"sector": "Tech",
		"company_name": "AstraCorp Vehicles",
		"traits": {"vanity": 0.95, "greed": 0.70, "paranoia_base": 0.65, "intelligence": 0.85, "ideology": 0.80, "ruthlessness": 0.60},
		"ambitions": ["Transcend humanity", "Escape"],
		"quirks": [
			"Posts seventeen times a day on an unlicensed broadcast platform he owns.",
			"Speaks about Mars as if it's a real personal destination.",
			"Has named four of his children after equations.",
		],
	},
	{
		"first_name": "Geoff",
		"last_name": "Brazos",
		"title": "Founder & Chairman",
		"sector": "Food",
		"company_name": "Kelp Logistics Inc.",
		"traits": {"vanity": 0.55, "greed": 0.95, "paranoia_base": 0.50, "intelligence": 0.85, "ideology": 0.30, "ruthlessness": 0.90},
		"ambitions": ["Monopolize supply", "Escape"],
		"quirks": [
			"Owns a six-minute rocket ride he'll mention within two sentences.",
			"Refers to employees as 'associates' even in private conversation.",
			"Dresses significantly better now than fifteen years ago.",
		],
	},
	{
		"first_name": "Mark",
		"last_name": "Sugarmountain",
		"title": "Founder & CEO",
		"sector": "Tech",                     # internet platform, not broadcast media
		"company_name": "Meta-Perspective Systems",
		"traits": {"vanity": 0.40, "greed": 0.70, "paranoia_base": 0.80, "intelligence": 0.80, "ideology": 0.60, "ruthlessness": 0.75},
		"ambitions": ["Control the narrative", "Transcend humanity"],
		"quirks": [
			"Blinks on a schedule.",
			"Practiced smiling in front of a mirror. Still practicing.",
			"Has a security bunker he's refused to name its location.",
		],
	},
	{
		"first_name": "Larry",
		"last_name": "Pace",
		"title": "Founder & Chairman",
		"sector": "Tech",
		"company_name": "Alphatrix Internet Holdings",
		"traits": {"vanity": 0.55, "greed": 0.70, "paranoia_base": 0.55, "intelligence": 0.90, "ideology": 0.70, "ruthlessness": 0.65},
		"ambitions": ["Transcend humanity", "Monopolize supply"],
		"quirks": [
			"Flying-car research project that never quite ships.",
			"Has opinions on death that make executives squirm.",
			"Prefers a handful of audacious bets over 200 cautious ones.",
		],
	},
	{
		"first_name": "Alex",
		"last_name": "Sharp",
		"title": "Chief Architect",
		"sector": "Military",
		"company_name": "Palladium Analytica Group",
		"traits": {"vanity": 0.35, "greed": 0.55, "paranoia_base": 0.50, "intelligence": 0.90, "ideology": 0.95, "ruthlessness": 0.90},
		"ambitions": ["Purge The Sinks", "Crush the resistance"],
		"quirks": [
			"Speaks in philosophy-seminar sentences even in hostile interviews.",
			"Describes software contracts as 'moral obligations'.",
			"Favors the word 'sovereignty' in unrelated contexts.",
		],
	},
	{
		"first_name": "Bernard",
		"last_name": "Arnaud",
		"title": "Chairman & CEO",
		"sector": "Media",
		"company_name": "Haute Moët & Vuit Group",
		"traits": {"vanity": 0.90, "greed": 0.90, "paranoia_base": 0.45, "intelligence": 0.75, "ideology": 0.40, "ruthlessness": 0.75},
		"ambitions": ["Monopolize supply", "Build a legacy"],
		"quirks": [
			"Will not appear in photos with anyone shorter than him.",
			"Has an opinion on every fashion house's current creative director.",
			"Owns more vineyards than he has publicly admitted to.",
		],
	},
	{
		"first_name": "Peter",
		"last_name": "Steel",
		"title": "Founder & Chairman",
		"sector": "Finance",
		"company_name": "Aegis Continuity Trust",
		"traits": {"vanity": 0.40, "greed": 0.65, "paranoia_base": 0.90, "intelligence": 0.85, "ideology": 0.85, "ruthlessness": 0.70},
		"ambitions": ["Escape", "Achieve political immortality"],
		"quirks": [
			"Has a New Zealand apocalypse bunker. Does not deny owning it.",
			"References obscure 20th-century political theorists in board meetings.",
			"Has funded a foundation researching 'life extension'.",
		],
	},
	{
		"first_name": "Will",
		"last_name": "Gales",
		"title": "Founder & Chairman",
		"sector": "Pharma",
		"company_name": "MicroThresh Holdings",
		"traits": {"vanity": 0.70, "greed": 0.70, "paranoia_base": 0.40, "intelligence": 0.90, "ideology": 0.65, "ruthlessness": 0.60},
		"ambitions": ["Build a legacy", "Control the narrative"],
		"quirks": [
			"Cites his own philanthropic foundation by name in nearly every interview.",
			"Wears sweaters that cost more than most people's rent.",
			"Has a reading list he publishes annually. The list is studied.",
		],
	},
	{
		"first_name": "Rupert",
		"last_name": "Murdouk",
		"title": "Chairman & CEO",
		"sector": "Media",
		"company_name": "Globe Broadcasting Consortium",
		"traits": {"vanity": 0.65, "greed": 0.80, "paranoia_base": 0.70, "intelligence": 0.75, "ideology": 0.90, "ruthlessness": 0.95},
		"ambitions": ["Control the narrative", "Crush the resistance"],
		"quirks": [
			"Remembers every journalist's byline across three continents.",
			"Has outlasted four presumptive successors.",
			"The family succession fight has its own dedicated press corps.",
		],
	},
	{
		"first_name": "Larry",
		"last_name": "Ellisun",
		"title": "Founder & Chairman",
		"sector": "Tech",
		"company_name": "Orakle Systems Corp.",
		"traits": {"vanity": 0.85, "greed": 0.85, "paranoia_base": 0.55, "intelligence": 0.85, "ideology": 0.60, "ruthlessness": 0.80},
		"ambitions": ["Achieve political immortality", "Monopolize supply"],
		"quirks": [
			"Owns a Hawaiian island and ran an experiment on it.",
			"Sponsors the America's Cup in a way the America's Cup does not love.",
			"Flies private jets — plural, simultaneously.",
		],
	},
	{
		"first_name": "Mukesh",
		"last_name": "Amban",
		"title": "Chairman & CEO",
		"sector": "Energy",
		"company_name": "Reliant Continental Holdings",
		"traits": {"vanity": 0.75, "greed": 0.85, "paranoia_base": 0.60, "intelligence": 0.80, "ideology": 0.50, "ruthlessness": 0.80},
		"ambitions": ["Monopolize supply", "Build a legacy"],
		"quirks": [
			"Hosted a wedding that five sitting heads of state attended.",
			"Lives in a 27-story private residence staffed by 600 people.",
			"Describes media ventures as 'necessary infrastructure'.",
		],
	},
	# AI sector — the faces building cognition at industrial scale.
	{
		"first_name": "Sam",
		"last_name": "Altmen",
		"title": "Founder & CEO",
		"sector": "AI",
		"company_name": "OmniCognition Labs",
		"traits": {"vanity": 0.75, "greed": 0.65, "paranoia_base": 0.55, "intelligence": 0.85, "ideology": 0.80, "ruthlessness": 0.70},
		"ambitions": ["Transcend humanity", "Monopolize supply"],
		"quirks": [
			"Posts cryptic one-word updates on NetFeed at 3am.",
			"Lobbies simultaneously FOR and AGAINST AI regulation depending on the committee.",
			"Keeps a prepper bunker but denies it's for what you think it's for.",
		],
	},
	{
		"first_name": "Dario",
		"last_name": "Amadei",
		"title": "Founder & CEO",
		"sector": "AI",
		"company_name": "Threshold Research Corp.",
		"traits": {"vanity": 0.45, "greed": 0.50, "paranoia_base": 0.80, "intelligence": 0.95, "ideology": 0.90, "ruthlessness": 0.55},
		"ambitions": ["Transcend humanity", "Control the narrative"],
		"quirks": [
			"Publishes 87-page manifestos about alignment. People pretend to read them.",
			"Uses the phrase 'responsible scaling' in sentences where it doesn't fit.",
			"Has a reputation for walking out of meetings that get too vague.",
		],
	},
	{
		"first_name": "Demmis",
		"last_name": "Hasabez",
		"title": "Chief Architect",
		"sector": "AI",
		"company_name": "Substrate Cognition Inc.",
		"traits": {"vanity": 0.70, "greed": 0.45, "paranoia_base": 0.50, "intelligence": 0.95, "ideology": 0.75, "ruthlessness": 0.50},
		"ambitions": ["Transcend humanity", "Build a legacy"],
		"quirks": [
			"Mentions having been a chess prodigy within three minutes of any introduction.",
			"Describes frontier models as 'my lab's kids'.",
			"Has a personal grudge against a specific rival founder he won't name in print.",
		],
	},
	{
		"first_name": "Jensen",
		"last_name": "Hwang",
		"title": "Founder & CEO",
		"sector": "AI",
		"company_name": "Kairos AI Systems",
		"traits": {"vanity": 0.60, "greed": 0.80, "paranoia_base": 0.35, "intelligence": 0.90, "ideology": 0.45, "ruthlessness": 0.70},
		"ambitions": ["Monopolize supply", "Build a legacy"],
		"quirks": [
			"Wears the same leather jacket on every public appearance since 2004.",
			"Signs employees' laptops like a rock star signing guitars.",
			"Announces new silicon with more flourish than any pop star announces an album.",
		],
	},
]


const _OLIGARCH_COMPANIES_BY_SECTOR := {
	"Food": [
		"Oksmarra Provisions Co.", "Verhovskiy Agro Holdings", "Harvest & Stroma", "Meridian Grain Partners", "Thessaly Nourishment Group",
	],
	"Tech": [
		"Vextol Systems", "Quell Lattice Corp.", "Krynne Compute Partners", "Ascendant Silicon", "Zhao-Pax Instruments",
	],
	"Military": [
		"Bane Armaments LLC", "Drax Continental Arms", "Kastor Defense Systems", "Varik Tactical Group", "Gant Perimeter Services",
	],
	"AI": [
		"OmniCognition Labs", "Threshold Research Corp.", "Substrate Cognition Inc.", "Kairos AI Systems", "Pattern Mind Holdings",
	],
	"Media": [
		"Silvane Broadcast Network", "Throne Continental Media", "Okonjo & Wyler Press", "Indra Signal Holdings", "Aurelius Public Narrative Co.",
	],
	"Pharma": [
		"Trell Therapeutics", "Hollis Wellness Holdings", "Callum Life Sciences", "Mabel-Drax Pharma", "Verity Compounding Corp.",
	],
	"Energy": [
		"Karst Power Partners", "Stroma Continental Energy", "Roderic Grid Holdings", "Ophira Transmission Co.", "Sevrin Fuel Trust",
	],
	"Finance": [
		"Vextol Capital Partners", "Paperclip & Thorne, LLP", "Gant Trust & Fiduciary", "Monarch Parallel Ventures", "Krynne Systems Group",
	],
}
const _OLIGARCH_AMBITIONS := ["Monopolize supply", "Achieve political immortality", "Build a legacy", "Escape", "Crush the resistance", "Control the narrative", "Transcend humanity", "Purge The Sinks", "Privatize currency", "Insolvency harvest"]
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

# Bill templates deleted. Bills are LLM-generated only; there is no
# offline/fallback path. If the LLM fails, SenateDirector skips the cycle.


# =============================================================
# OFFLINE EMITTERS — deferred so signal semantics match LLM path
# =============================================================

func _offline_emit_oligarchs(count: int) -> void:
	# Each oligarch independently rolls a sector. Sectors may repeat
	# (market consolidation) or be absent entirely (the Enclave doesn't
	# necessarily have a player in every industry). Reflects how real
	# oligarchies cluster, not how designed rosters are balanced.
	var out: Array = []
	if oligarch_mode == "alter_egos":
		# Guarantee 2 AI + 2 Tech alter-egos, fill the rest from the pool.
		var ai_pool: Array = []
		var tech_pool: Array = []
		var other_pool: Array = []
		for profile in _ALTER_EGO_POOL:
			match str(profile.get("sector", "")):
				"AI":   ai_pool.append(profile)
				"Tech": tech_pool.append(profile)
				_:      other_pool.append(profile)
		ai_pool.shuffle()
		tech_pool.shuffle()
		other_pool.shuffle()
		for profile in ai_pool.slice(0, min(2, ai_pool.size())):
			out.append(profile.duplicate(true))
		for profile in tech_pool.slice(0, min(2, tech_pool.size())):
			out.append(profile.duplicate(true))
		var remaining: int = max(0, count - out.size())
		for profile in other_pool.slice(0, min(remaining, other_pool.size())):
			out.append(profile.duplicate(true))
		print("LLMManager offline (alter_egos): %d alter-ego oligarchs emitted (2 AI + 2 Tech guaranteed)." % out.size())
	else:
		# Procedural: first slot 2 AI + 2 Tech, then randomize the rest.
		var guaranteed_sectors: Array[String] = ["AI", "AI", "Tech", "Tech"]
		var emitted: int = 0
		for sector in guaranteed_sectors:
			if emitted >= count:
				break
			out.append(_make_procedural_oligarch(sector))
			emitted += 1
		while emitted < count:
			var sector: String = _OLIGARCH_SECTORS.pick_random()
			out.append(_make_procedural_oligarch(sector))
			emitted += 1
	oligarchs_generated.emit(out)


func _make_procedural_oligarch(sector: String) -> Dictionary:
	var companies_for_sector: Array = _OLIGARCH_COMPANIES_BY_SECTOR.get(sector, [])
	var company_name: String = companies_for_sector.pick_random() if not companies_for_sector.is_empty() else "%s Holdings" % sector
	return {
		"first_name": _OLIGARCH_FIRST.pick_random(),
		"last_name": _OLIGARCH_LAST.pick_random(),
		"title": _OLIGARCH_TITLES.pick_random(),
		"sector": sector,
		"company_name": company_name,
		"ambitions": _pick_distinct(_OLIGARCH_AMBITIONS, randi_range(1, 2)),
		"quirks": _pick_distinct(_OLIGARCH_QUIRKS, randi_range(2, 3)),
	}


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
	# Bills are LLM-only. In offline mode, the Senate cycle is skipped by
	# returning an empty dict — SenateDirector._on_bill_generated() treats
	# empty/error/missing-title as "skip this cycle, try again next one".
	push_warning("LLMManager: offline mode — no bill emitted (SenateDirector will skip).")
	if callback.is_valid():
		callback.call({})


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

	# One oligarch-related beat if available. Pull richer state off the
	# live OligarchData when we can so the same headline doesn't recur.
	if oligarchs.size() > 0:
		events.append(_offline_oligarch_beat(oligarchs))

	# Always inject 1-2 ambient city beats, sampled from a broad pool so
	# the feed doesn't flatline on the same 4 threshold lines. These
	# reference the running economy + time-of-day when they can.
	events.append_array(_offline_ambient_beats(world, 2))

	if events.is_empty():
		events.append(_netfeed_event("NEWS_TICKER",
			"NetFeed quiet overnight. Ambient anxiety index unchanged.",
			"no major shifts"))

	netfeed_stream_received.emit(events)


# Pool of oligarch-centric news beats. Picks a random living oligarch,
# reads their live OligarchData (sector, company, trait values, ambitions)
# so the same name rolls out a different beat each cycle.
func _offline_oligarch_beat(oligarchs_map: Dictionary) -> Dictionary:
	var keys: Array = oligarchs_map.keys()
	var key: String = keys.pick_random()
	var o = oligarchs_map[key]

	var name: String = str(key)
	var company: String = "their company"
	var sector: String = "Various"
	var is_paranoid: bool = false
	var is_greedy: bool = false
	var is_vain: bool = false
	var is_scheming: bool = false
	if o != null:
		name = str(o.oligarch_name) if "oligarch_name" in o and o.oligarch_name != "" else name
		if "company_name" in o and str(o.company_name) != "":
			company = str(o.company_name)
		if "sector_of_influence" in o and str(o.sector_of_influence) != "":
			sector = str(o.sector_of_influence)
		if "paranoia" in o and float(o.paranoia) > 55.0: is_paranoid = true
		if "greed" in o and float(o.greed) > 0.6: is_greedy = true
		if "vanity" in o and float(o.vanity) > 0.6: is_vain = true
		if "intelligence" in o and float(o.intelligence) > 0.6: is_scheming = true

	var pool: Array = [
		"%s seen leaving a closed-door session with three senators. No statement issued." % name,
		"%s made an unscheduled appearance at a %s sector trade breakfast this morning." % [name, sector],
		"%s's %s posted a 'routine quarterly realignment' — no details offered." % [name, company],
		"A leaked memo attributed to %s circulated briefly before being scrubbed from every outlet by noon." % name,
		"%s's motorcade was spotted at a senate-district restaurant. The senator was not named." % name,
		"%s declined to comment on reports of internal reorganization at %s." % [name, company],
	]
	if is_paranoid:
		pool.append_array([
			"%s's security detail has been upgraded for the third time this month, sources say." % name,
			"Unconfirmed reports: %s has relocated primary residence to a fortified compound." % name,
			"%s quietly cancelled all public appearances for the next two weeks." % name,
		])
	if is_greedy:
		pool.append_array([
			"%s announced a 'margin-optimization initiative' at %s. Critics call it what it is." % [name, company],
			"%s's %s raised pricing across three product lines overnight. The feed is careful not to say 'profiteering'." % [name, company],
			"Regulators quietly dropped an inquiry into %s after months of 'voluntary cooperation'." % name,
		])
	if is_vain:
		pool.append_array([
			"%s appeared on the cover of Enclave Monthly for the fourth time this year, smiling." % name,
			"%s's foundation announced a new public-arts installation. The press release ran 6 pages." % name,
			"%s gave an extended interview about 'humility in leadership'. The word appeared 14 times." % name,
		])
	if is_scheming:
		pool.append_array([
			"Two separate outlets credit %s as an 'informal advisor' on bills moving through committee." % name,
			"%s's name appeared in committee logs three days running. No one proposed anything on those days." % name,
		])

	var line: String = pool.pick_random()
	return _netfeed_event("NEWS_TICKER", line, "oligarch activity — %s lobbying or posturing" % sector)


# Pool of city-level ambient lines. Always adds texture to the feed
# regardless of world state. Some lines thread the current economy
# values (food price, security, tension) when useful.
func _offline_ambient_beats(world: Dictionary, count: int) -> Array:
	var food_price: int = int(world.get("food_price", 100))
	var tension: int = int(world.get("public_tension", 20))
	var security: int = int(world.get("security_presence", 50))

	var pool: Array[String] = [
		"A Sinks-block voluntary mutual-aid queue was longer at dawn than the week before.",
		"The 03:12 NetFeed sweep flagged six deleted posts with an identical phrase. No attribution.",
		"Compliance Post 14 reports 'no anomalous activity'. Locals disagree.",
		"A street chalk drawing outside the senate was scrubbed at 04:47 and redrawn by 07:10.",
		"A tram on Line 3 was held for 18 minutes for 'safety review'. Nobody onboard was informed why.",
		"A broken water main flooded an Agricultural terrace overnight. Coverage is pending.",
		"Three minor citations for 'unsanctioned assembly' were logged in the last 6 hours.",
		"A brick was thrown through a pharmacy window at 02:14. The pharmacy chain did not respond.",
		"A street vendor's license was revoked midweek. The cart was still there on Friday.",
		"A Sinks-block community radio signed off early for the second time this week.",
		"Two patrol drones went offline simultaneously near Substrate Fields. Back online by 06:00.",
		"A small unlicensed broadcast transmitted 47 seconds of silence this morning. Enforcers investigating.",
		"The feed's noon-hour weather segment ran long — unusually long — today.",
		"A municipal accountant resigned with a one-line letter. The contents were not printed.",
	]
	if food_price > 150:
		pool.append("Food price index trending up — %d this cycle. Delivery wait times doubling." % food_price)
	if tension > 40:
		pool.append("Unrest indicators climbing. Social workers report a spike in anxiety walk-ins.")
	if security > 60:
		pool.append("Additional patrol routes added overnight. The feed called them 'presence operations'.")

	var out: Array = []
	pool.shuffle()
	for i in range(min(count, pool.size())):
		out.append(_netfeed_event("NEWS_TICKER", pool[i], "ambient street pulse"))
	return out


func _offline_emit_npc_action(npc, player_input: String) -> void:
	# Compose a profile-voiced response without a live model. Grounded in
	# NPCData's behavioral profile + current mood + trust/opinion.
	var profile: String = "Anxious Citizen"
	var trust: float = 0.0
	var opinion: float = 0.0
	var quirk: String = ""
	if npc != null:
		if npc.has_method("get_behavioral_profile"):
			profile = npc.get_behavioral_profile()
		trust = float(npc.trust)
		opinion = float(npc.opinion_of_player)
		if npc.quirks != null and npc.quirks.size() > 0:
			quirk = str(npc.quirks[0])

	var dialogue: String = ""
	var goal: String = "idle"
	var success: bool = true

	match profile:
		"Radical Agitator":
			dialogue = "Burn it down. You in? Good."
			goal = "assist"
		"Broken and Submissive":
			dialogue = "I don't want trouble. Please — leave me alone."
			goal = "flee"
			success = false
		"Revolutionary Idealist":
			dialogue = "There's a meeting at midnight. Come or don't. We move either way."
			goal = "assist"
		"Opportunistic Exploiter":
			dialogue = "What's in it for me? Credits. Dirt. Speak."
			goal = "idle"
		"Cautiously Stable":
			dialogue = "Things are quiet here right now. Let's keep them that way."
			goal = "idle"
		_:
			if opinion < -0.3:
				dialogue = "I know what you did. Not interested."
				goal = "flee"
				success = false
			elif trust > 50.0:
				dialogue = "Glad it's you. What do you need?"
				goal = "assist"
			else:
				dialogue = "I'm not supposed to talk to strangers. The feed's listening."
				goal = "idle"

	# Tint with a quirk if we have one — flavor without changing meaning.
	if quirk != "" and randf() < 0.5:
		dialogue += "  (%s)" % quirk

	llm_response_received.emit({
		"success": success,
		"dialogue": dialogue,
		"assigned_goal": goal,
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


# _synthesize_bill removed — bills are LLM-only.


func _netfeed_event(type: String, headline: String, impact: String) -> Dictionary:
	return {
		"type": type,
		"headline": headline,
		"systemic_impact": impact,
	}
