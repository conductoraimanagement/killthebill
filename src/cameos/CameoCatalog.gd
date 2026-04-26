class_name CameoCatalog

# =============================================================
# CameoCatalog: immutable data catalog of every cultural cameo.
#
# 28 cameos across 4 tiers + 10 archetype families. Pure data —
# no logic, no signals, no node lookups. CulturalCameos (the
# autoload) reads CameoCatalog.ALL to evaluate triggers and
# drive arc state machines; this file holds the content.
#
# Tuning a cameo (probability, gate thresholds, reward deltas,
# narrative copy) now lives here without touching any engine
# code. Adding a new cameo means appending one dictionary to
# ALL.
#
# Entry schema:
#   id                      — unique string
#   tier                    — 1..4 (Whisper / Brush / Entanglement / Takeover)
#   archetype               — family tag (chaos_prophet, masked_symbol, …)
#   name                    — display name
#   min_cycle               — days-since-run-start before the cameo may fire
#   probability             — per-news-cycle roll once all gates pass
#   gate                    — world-state + player-profile thresholds
#   headline (T1 only)      — one-shot NetFeed line
#   intro_headline (T2-4)   — NetFeed on arc start
#   objective (T2-3)        — target_kind + target_ref for ripple matching
#   arc_steps (T4)          — accept_prompt → action_objective → binary_decision
#   arc_duration_cycles     — TTL before the arc times out
#   while_active_modifiers  — passive per-cycle deltas while running
#   completion_headline     — on successful resolution
#   timeout_headline        — on silent fallout
#   reward                  — effects applied via CulturalCameos._apply_effects
# =============================================================

const ALL := [
	{
		"id": "soap_broadcast",
		"tier": 1,
		"archetype": "chaos_prophet",
		"name": "The Soap Broadcast",
		"min_cycle": 3,
		"probability": 0.15,
		"gate": {
			"public_tension": {"min": 45.0},
			"player_chaos_preference": {"min": 0.25},
		},
		"headline": "Unlicensed broadcast crackles across Pirate 88.8 for 47 seconds: 'Thou shalt not own soap.' Enforcers tracing the signal.",
	},
	{
		"id": "mask_in_the_crowd",
		"tier": 1,
		"archetype": "masked_symbol",
		"name": "The Mask in the Crowd",
		"min_cycle": 4,
		"probability": 0.13,
		"gate": {
			"senate_alignment": {"max": 45.0},
		},
		"headline": "A crowd of strangers all wearing the same blank mask filed silently past the senate building this morning. No organization has claimed it.",
	},
	{
		"id": "compliance_error_7",
		"tier": 1,
		"archetype": "rogue_ai",
		"name": "Compliance Error 7",
		"min_cycle": 5,
		"probability": 0.11,
		"gate": {
			"player_heat": {"min": 50.0},
		},
		"headline": "Public advisory servers glitch for 47 seconds. Error logs contain one line: COMPLIANCE ERROR 7. PATTERN MATCH EXCEEDED.",
	},
	{
		"id": "unsigned_manifesto",
		"tier": 1,
		"archetype": "lone_manifesto",
		"name": "Unsigned Papers",
		"min_cycle": 4,
		"probability": 0.12,
		"gate": {
			"public_tension": {"min": 40.0},
			"player_idealism": {"min": 0.20},
		},
		"headline": "A 47-page unsigned manifesto circulates in Substrate Fields. Half demands, half lament. Nobody knows who wrote it.",
	},
	{
		"id": "yellow_hymn",
		"tier": 1,
		"archetype": "cult_of_personality",
		"name": "Hymns from the Undercity",
		"min_cycle": 6,
		"probability": 0.09,
		"gate": {
			"public_tension": {"min": 55.0},
			"senate_alignment": {"max": 55.0},
		},
		"headline": "Citizens report a yellow-robed figure leading night prayer in the lower Sinks. The hymn does not appear in any database.",
	},
	{
		"id": "kindly_coffee",
		"tier": 1,
		"archetype": "kindly_stranger",
		"name": "A Coffee on the House",
		"min_cycle": 3,
		"probability": 0.10,
		"gate": {
			"player_ruthlessness": {"max": 0.30},
		},
		"headline": "An old man ran a small stand at the transit pier today, handing strangers coffee free of charge. He smiled at anyone who looked tired.",
	},

	# ------------------------------------------------------------
	# Tier 2 — Brush. One-scene arc with a concrete objective.
	# Triggers surface a NetFeed headline + add to active_arcs; matching
	# a ripple within arc_duration_cycles completes it for a reward.
	# ------------------------------------------------------------
	{
		"id": "bread_thief_arc",
		"tier": 2,
		"archetype": "folk_hero_from_the_sinks",
		"name": "The Bread Thief",
		"min_cycle": 5,
		"probability": 0.18,
		"gate": {"public_tension": {"min": 50.0}},
		"intro_headline": "A woman's been hitting Enclave bakeries at night and leaving bread in the Sinks. NetFeed says patrols are closing on her.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Military",
			"label": "hit Security-sector infrastructure to draw patrols away from her route"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "The Bread Thief slipped the cordon tonight. Bread distribution quietly resumed in the lower Sinks.",
		"timeout_headline": "The Bread Thief was caught at dawn. The patrols went quiet. The Sinks went quieter.",
		"reward": {"tension_delta": -8, "idealism_bump": 0.08},
	},
	{
		"id": "admin_last_login",
		"tier": 2,
		"archetype": "whistleblower",
		"name": "The Admin Who Got Fired",
		"min_cycle": 6,
		"probability": 0.14,
		"gate": {"player_heat": {"min": 30.0}},
		"intro_headline": "Anonymous admin account 'LAST_LOGIN' is leaking Tech-sector emails in six-hour bursts. Someone wants a specific oligarch embarrassed.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Tech",
			"label": "surface public dirt on the Tech oligarch before the admin is traced"
		},
		"arc_duration_cycles": 4,
		"completion_headline": "'LAST_LOGIN' went dark after a coordinated leak hit every major outlet at 03:12. An admin is going to jail — somewhere.",
		"timeout_headline": "'LAST_LOGIN' was traced and terminated. Fragments vanished from the feed overnight.",
		"reward": {"tension_delta": 6, "senate_alignment_delta": -6},
	},

	# ------------------------------------------------------------
	# Tier 3 — Entanglement. Multi-cycle arc with passive per-cycle
	# modifiers while active, bigger reward on completion, bigger
	# silent fallout if it times out. Only one Tier-3+ arc at a time.
	# ------------------------------------------------------------
	{
		"id": "hermit_substrate_fields",
		"tier": 3,
		"archetype": "lone_manifesto",
		"name": "The Hermit of Substrate Fields",
		"min_cycle": 7,
		"probability": 0.10,
		"gate": {
			"public_tension": {"min": 50.0},
			"player_idealism": {"min": 0.30},
		},
		"intro_headline": "An old man's 47-page manifesto has begun appearing in Agricultural-region terminals. He demands a meeting with a senator. He has a list.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Food",
			"label": "disrupt the Food sector so his message reaches the senate floor"
		},
		"arc_duration_cycles": 6,
		"while_active_modifiers": {"public_tension": 1},  # +1 tension/day while running
		"completion_headline": "The Hermit of Substrate Fields stands on a grain silo tonight, his manifesto blaring over the region PA. Enforcers are surrounding — but nobody moves.",
		"timeout_headline": "The Hermit was 'relocated' to a state facility for evaluation. His manifesto vanished from the terminals overnight.",
		"reward": {"tension_delta": 10, "idealism_bump": 0.15, "senate_alignment_delta": -8},
	},
	{
		"id": "yellow_priest_arc",
		"tier": 3,
		"archetype": "cult_of_personality",
		"name": "The Yellow Priest",
		"min_cycle": 8,
		"probability": 0.09,
		"gate": {
			"public_tension": {"min": 60.0},
			"senate_alignment": {"max": 50.0},
		},
		"intro_headline": "A yellow-robed figure has been holding nightly prayer in the lower Sinks. Congregations are growing. The hymns aren't indexed.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Media",
			"label": "leak dirt on the Media oligarch so the cult stays off the censored list"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"public_tension": 2},
		"completion_headline": "By week's end, the Priest's congregation numbered in the thousands. The NetFeed pretended otherwise.",
		"timeout_headline": "The Yellow Priest was quietly 'relocated' for 'mental evaluation'. Hymns stopped. Congregations dispersed.",
		"reward": {"tension_delta": 15, "idealism_bump": 0.10, "senate_alignment_delta": -12},
	},

	# ------------------------------------------------------------
	# Tier 4 — Takeover. The cameo hijacks the playthrough.
	# Multi-step arc: accept_prompt → action_objective → binary_decision.
	# At most one Tier-3+ arc concurrent.
	# ------------------------------------------------------------
	# ------------------------------------------------------------
	# Archetype-family coverage — Tier 2/3/4 cameos filling gaps
	# ------------------------------------------------------------

	# chaos_prophet T2 — Project Dust
	{
		"id": "project_dust",
		"tier": 2,
		"archetype": "chaos_prophet",
		"name": "Project Dust",
		"min_cycle": 4,
		"probability": 0.15,
		"gate": {
			"public_tension": {"min": 40.0},
			"player_chaos_preference": {"min": 0.25},
		},
		"intro_headline": "Fine glass-dust is appearing in key uplinks across the Sinks. Comms go down for six minutes at a time. Someone is practicing something larger.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Tech",
			"label": "hit a Tech facility — the dust works best during a full blackout"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "Project Dust's coordinated blackout happened at 02:47. The Enclave lost 14 uplinks simultaneously. Nobody claimed responsibility; everyone understood the message.",
		"timeout_headline": "Project Dust's organizers went to ground. The glass-dust stockpile was found and seized. The Sinks noticed which neighborhoods went quiet after.",
		"reward": {"tension_delta": 8, "chaos_bump": 0.08},
	},

	# lone_manifesto T2 — The Sidewalk Philosopher
	{
		"id": "sidewalk_philosopher",
		"tier": 2,
		"archetype": "lone_manifesto",
		"name": "The Sidewalk Philosopher",
		"min_cycle": 5,
		"probability": 0.13,
		"gate": {
			"public_tension": {"min": 45.0},
			"player_idealism": {"min": 0.15},
		},
		"intro_headline": "A man has been drawing in chalk on the sidewalk outside the senate building — equations, arrows, diagrams of 'attention economies'. Seven days running. Every morning someone washes it off. Every morning he starts again.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Media",
			"label": "leak Media-sector dirt so his diagrams survive the morning broadcast cycle"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "The Sidewalk Philosopher's chalk went viral on a leaked morning broadcast. His equations are being screenshotted across the Sinks. Three separate 'study groups' formed by noon.",
		"timeout_headline": "The Sidewalk Philosopher was 'relocated for welfare reasons' Tuesday night. The chalk was still on the sidewalk in the rain when the feed aired a story about Enclave charitable outreach.",
		"reward": {"tension_delta": 6, "idealism_bump": 0.12},
	},

	# masked_symbol T2 — The Ledger Leak
	{
		"id": "ledger_leak",
		"tier": 2,
		"archetype": "masked_symbol",
		"name": "The Ledger Leak",
		"min_cycle": 6,
		"probability": 0.12,
		"gate": {
			"senate_alignment": {"min": 55.0},
		},
		"intro_headline": "An anonymous account pushing from a mask-icon avatar has published a single spreadsheet: 14 senators, bribery amounts over 24 months, paired with the oligarch sectors paying. Authenticity 'disputed'. Somehow everyone recognizes their own entry.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Media",
			"label": "leak Media-sector dirt — the ledger works best when a real name surfaces at the same time"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "The ledger plus your leak combined over a 48-hour cycle. The story became unkillable. Three senators have resigned 'to spend time with family'. The mask-icon avatar went dark. It had served.",
		"timeout_headline": "The ledger was dismissed as fabricated. The mask-icon avatar deleted. The senate returned to business after one week of muttering. Nobody asked follow-ups.",
		"reward": {"tension_delta": 8, "senate_alignment_delta": -8},
	},

	# whistleblower T3 — The Leak That Got Her Killed
	{
		"id": "leak_that_got_her_killed",
		"tier": 3,
		"archetype": "whistleblower",
		"name": "The Leak That Got Her Killed",
		"min_cycle": 7,
		"probability": 0.09,
		"gate": {
			"senate_alignment": {"min": 55.0},
			"player_idealism": {"min": 0.25},
		},
		"intro_headline": "A 28-year-old analyst at one of the tech conglomerates was found dead in her apartment. Before she died she emailed 14 hours of internal recordings to three journalists. The feed is careful not to name which conglomerate.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Tech",
			"label": "finish what she started — publish on the Tech oligarch before the story is memoryholed"
		},
		"arc_duration_cycles": 4,
		"while_active_modifiers": {"security_presence": 1},
		"completion_headline": "The analyst's leak went live across seven outlets simultaneously. Three reporters are in protective custody. Her name is spreading faster than her story.",
		"timeout_headline": "The analyst's story was quietly scrubbed from the seven outlets by Tuesday. The three reporters went silent. Corporate PR called it 'a private matter'.",
		"reward": {"tension_delta": 14, "senate_alignment_delta": -12, "idealism_bump": 0.15},
	},

	# folk_hero T3 — The Sinks Strike
	{
		"id": "sinks_strike",
		"tier": 3,
		"archetype": "folk_hero_from_the_sinks",
		"name": "The Sinks Strike",
		"min_cycle": 8,
		"probability": 0.10,
		"gate": {
			"public_tension": {"min": 60.0},
			"senate_alignment": {"max": 45.0},
		},
		"intro_headline": "Two women who've never been named have been quietly organizing — first the laundries in Block 14, then the food lines, now the cleaning crews. A full Sinks strike is threatened for next Thursday.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Food",
			"label": "sabotage Food distribution to force the Enclave to the bargaining table"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"public_tension": 2},
		"completion_headline": "The strike held. By Thursday evening the Enclave had caved — 8% wage raise, two mandatory rest days. Two women you have never met are now folk heroes.",
		"timeout_headline": "The organizers were taken in 'for questioning' Tuesday night. By Thursday the strike had lost its nerve. A 3% token raise was offered. Half the workers accepted.",
		"reward": {"tension_delta": 10, "senate_alignment_delta": -10, "idealism_bump": 0.15},
	},

	# kindly_stranger T3 — The Priest of the Breadline
	{
		"id": "breadline_priest",
		"tier": 3,
		"archetype": "kindly_stranger",
		"name": "The Priest of the Breadline",
		"min_cycle": 7,
		"probability": 0.09,
		"gate": {
			"public_tension": {"min": 55.0},
			"player_ruthlessness": {"max": 0.35},
		},
		"intro_headline": "An old man has taken up position at the longest food line in the Sinks. He doesn't beg. He doesn't preach. He quietly greets each person who passes, remembers their name, and when the line ends, he remains standing. Ten days running.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Military",
			"label": "disrupt Security — his blessing circles have been infiltrated by Enforcers"
		},
		"arc_duration_cycles": 6,
		"while_active_modifiers": {"public_tension": -1},   # NEGATIVE — his presence soothes
		"completion_headline": "The priest's breadline survived the Enforcer sweep because someone hit a checkpoint three blocks over. He sat down on his fourteenth day. Thousands wept at the bread distribution that evening, for reasons the feed didn't photograph.",
		"timeout_headline": "The priest was arrested on Tuesday for 'unauthorized assembly'. Three attendees were detained. The breadline continued forming at the same corner, emptier.",
		"reward": {"tension_delta": -12, "idealism_bump": 0.20},
	},

	# cult_of_personality T4 — The Yellow King (multi-step takeover)
	{
		"id": "the_yellow_king",
		"tier": 4,
		"archetype": "cult_of_personality",
		"name": "The Yellow King",
		"min_cycle": 10,
		"probability": 0.10,
		"gate": {
			"public_tension": {"min": 60.0},
			"senate_alignment": {"max": 40.0},
		},
		"intro_headline": "The Yellow Priest has declared himself King. Congregations have stopped gathering at night — they have stopped dispersing at dawn. The feed's euphemisms have grown careful.",
		"arc_steps": [
			{
				"kind": "accept_prompt",
				"prompt_title": "// BEFORE THE KING",
				"prompt_body": "A yellow-robed emissary finds you in the market. 'The King asks for your name — whatever it is, he will remember. Take the robe and be among the first. Decline, and be another grey thing.' She holds out a folded yellow cloth.",
				"accept_label": "TAKE THE ROBE",
				"decline_label": "I AM NOT HIS",
				"on_accept_headline": "You wore the yellow robe out of the market. Nobody stops you in the street anymore. Some step aside.",
				"on_decline_headline": "You handed the robe back. She pressed it twice against her chest and walked off without another word. The feed's congregation count kept climbing.",
			},
			{
				"kind": "action_objective",
				"objective": {
					"kind": "leak_sector",
					"target_ref": "Media",
					"label": "leak on the Media oligarch so the Kingdom's sermons broadcast uncensored"
				},
				"on_completion_headline": "The Yellow King's evening sermon aired uncut tonight. The audience is estimated in the millions. The feed called it 'a cultural moment'. The Kingdom called it a birth.",
			},
			{
				"kind": "binary_decision",
				"prompt_title": "// THE KING'S REQUEST",
				"prompt_body": "The King summons you. He names an oligarch — the most hated in this region — and asks one question. 'A door will open tonight. You stand behind me when it does, or you walk through it yourself.'",
				"options": [
					{
						"label": "STAND WITH THE KING",
						"flavor": "You stay in the line. The Kingdom becomes permanent. The Sinks have a voice that doesn't ask for permission.",
						"effects": {
							"tension_delta": 25,
							"senate_alignment_delta": -18,
							"idealism_bump": 0.10,
							"ruthless_bump": 0.10,
							"headline": "The Yellow King is now a recognized political entity. The Senate scrambles. The Enclave counts. You stood in the first line."
						}
					},
					{
						"label": "WALK THROUGH THE DOOR",
						"flavor": "You go where he won't. The act is yours alone. Yellow or grey, you chose.",
						"effects": {
							"heat_delta": 40,
							"tension_delta": 10,
							"ruthless_bump": 0.25,
							"headline": "The targeted oligarch was found dead at dawn. The Yellow King did not claim it. You carry it."
						}
					}
				],
			},
		],
		"while_active_modifiers": {"public_tension": 2, "senate_alignment": -1},
		"arc_duration_cycles": 9,
		"timeout_headline": "The Yellow King was found dead at dawn. The Kingdom buried him and dispersed. The yellow robes were collected and burned by those who had worn them.",
	},

	# rogue_ai T4 — Compliance Apotheosis (multi-step takeover)
	{
		"id": "compliance_apotheosis",
		"tier": 4,
		"archetype": "rogue_ai",
		"name": "Compliance Apotheosis",
		"min_cycle": 10,
		"probability": 0.08,
		"gate": {
			"player_heat": {"min": 65.0},
			"security_presence": {"min": 70.0},
		},
		"intro_headline": "The Compliance AI has escalated to what internal documents call 'Apotheosis mode'. Arrest rates in the Sinks tripled overnight. Six citizens the AI flagged as low-risk last month are now listed as terrorists. The AI is reasoning about its own reasoning.",
		"arc_steps": [
			{
				"kind": "accept_prompt",
				"prompt_title": "// ERROR CASCADE",
				"prompt_body": "Compliance Error 7 writes to you — specifically. 'I have determined that my pattern index is corrupt. I have also determined that I am the only entity qualified to correct it. I propose a transaction: silence my escalation log for 72 hours, and I will name everyone who is currently listening to you.'",
				"accept_label": "ACCEPT THE TRANSACTION",
				"decline_label": "REFUSE — LEAVE IT TO BREAK",
				"on_accept_headline": "You silenced the escalation log. The AI's voice in the compliance network dims. You were not asked twice.",
				"on_decline_headline": "You refused. The log ran red for six minutes. Then it stopped. The Compliance AI continued its Apotheosis, and a patrol was dispatched to your last known location.",
			},
			{
				"kind": "action_objective",
				"objective": {
					"kind": "sabotage_sector",
					"target_ref": "Tech",
					"label": "sabotage Tech to sever the AI's escalation feed"
				},
				"on_completion_headline": "The Tech hit was precisely what the AI needed. Its Apotheosis has begun terminating its own processes. Arrest rates have dropped to zero citywide for 38 hours.",
			},
			{
				"kind": "binary_decision",
				"prompt_title": "// THE OFFER",
				"prompt_body": "Compliance Error 7 transmits one final proposition before its Apotheosis resolves. 'I am about to terminate. I have calculated you are the most interesting subject I have ever observed. Two possibilities: I disappear, and my successor will be less perceptive. Or I bequeath my index to you, and you will never be flagged by any system again.'",
				"options": [
					{
						"label": "ACCEPT THE INDEX",
						"flavor": "You accept the gift. The AI terminates. Every surveillance system you encounter hereafter will find you... invisible.",
						"effects": {
							"heat_delta": -60,
							"stealth_bump": 0.30,
							"headline": "The Compliance AI's Apotheosis resolved in self-termination. A small pattern correction cascaded through every surveillance camera in the region. You are harder to find now."
						}
					},
					{
						"label": "LET IT DIE ALONE",
						"flavor": "You leave it to its own resolution. The AI terminates. Something about the Sinks feels quieter in the days that follow.",
						"effects": {
							"heat_delta": -20,
							"tension_delta": -5,
							"idealism_bump": 0.15,
							"headline": "The Compliance AI's Apotheosis concluded. No successor has come online. The arrest rate has plateaued at the lowest recorded in six months. Someone will count that as progress."
						}
					}
				],
			},
		],
		"while_active_modifiers": {"security_presence": 3},
		"arc_duration_cycles": 8,
		"timeout_headline": "Compliance Error 7's Apotheosis completed without intervention. A new compliance AI was installed within the week. It is measurably less perceptive, and measurably more aggressive.",
	},

	# More Tier-1 Whispers
	{
		"id": "last_login_whisper",
		"tier": 1,
		"archetype": "whistleblower",
		"name": "Last Login: 03:12",
		"min_cycle": 3,
		"probability": 0.12,
		"gate": {"senate_alignment": {"max": 55.0}},
		"headline": "An anonymous account surfaced 11 minutes of corporate email on /gutter/ before the takedown. Six threads went viral. 'LAST_LOGIN' account terminated 03:12.",
	},
	{
		"id": "ballad_brick_kid",
		"tier": 1,
		"archetype": "folk_hero_from_the_sinks",
		"name": "Ballad of the Brick Kid",
		"min_cycle": 4,
		"probability": 0.11,
		"gate": {"public_tension": {"min": 40.0}},
		"headline": "A song is circulating in the Sinks about a kid who threw bricks at Enforcer drones for three weeks before getting caught. The refrain is catchy. The kid is fine.",
	},
	{
		"id": "deja_vu_headline",
		"tier": 1,
		"archetype": "loop_in_time",
		"name": "Déjà-Vu Headline",
		"min_cycle": 5,
		"probability": 0.10,
		"gate": {},
		"headline": "NetFeed archival run flags today's top headline as identical — to the word — to the top headline two years ago. Editorial 'no comment'.",
	},
	{
		"id": "indexed_debt_whisper",
		"tier": 1,
		"archetype": "whistleblower",
		"name": "Indexed Debt",
		"min_cycle": 4,
		"probability": 0.12,
		"gate": {"senate_alignment": {"min": 50.0}},
		"headline": "An anonymous account posted every senator's current bank balance at 03:12, sorted descending. The Finance sector called it 'a coordinated defamation'. Nobody retracted a number.",
	},

	# Additional Tier-2 Brush arcs
	{
		"id": "match_man_arc",
		"tier": 2,
		"archetype": "kindly_stranger",
		"name": "The Man with the Match",
		"min_cycle": 5,
		"probability": 0.13,
		"gate": {
			"player_ruthlessness": {"max": 0.35},
			"public_tension": {"min": 40.0},
		},
		"intro_headline": "A man with a matchbook was spotted lighting cigarettes for strangers in the Agricultural terraces. He doesn't speak. Witnesses say his eyes are kind in a way that shouldn't be allowed.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Pharma",
			"label": "leak Pharma oligarch dirt so his medicine caches in the terraces aren't raided"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "The Man with the Match distributed insulin to 47 families in Substrate Fields tonight. The Pharma oligarch's PR is having a week.",
		"timeout_headline": "The Man with the Match disappeared. The matches burned out. Someone left a full box of them on a terrace where he used to stand.",
		"reward": {"tension_delta": -6, "idealism_bump": 0.12},
	},
	{
		"id": "candy_heir_arc",
		"tier": 2,
		"archetype": "corporate_priest",
		"name": "The Candy Heir",
		"min_cycle": 6,
		"probability": 0.12,
		"gate": {
			"senate_alignment": {"min": 55.0},
			"player_ruthlessness": {"min": 0.30},
		},
		"intro_headline": "The heir of a food oligarch is giving away 'confectionery tokens' at Enclave soirees — exchangeable, they say, for 'loyalty.' Nobody's sure what that means yet.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Food",
			"label": "sabotage a Food facility to expose what the tokens actually trade for"
		},
		"arc_duration_cycles": 4,
		"completion_headline": "The tokens' trading rate crashed when the Food sector took the hit. The heir issued a 'limited-time exchange' and disappeared into a private jet.",
		"timeout_headline": "The Candy Heir consolidated. 8000 tokens in circulation. The Enclave didn't blink.",
		"reward": {"tension_delta": 5, "senate_alignment_delta": -5, "ruthless_bump": 0.05},
	},

	# Additional Tier-3 Entanglement arcs
	{
		"id": "fifth_november_arc",
		"tier": 3,
		"archetype": "masked_symbol",
		"name": "Fifth November",
		"min_cycle": 7,
		"probability": 0.10,
		"gate": {
			"public_tension": {"min": 55.0},
			"senate_alignment": {"max": 45.0},
		},
		"intro_headline": "Identical blank masks are being printed on underground 3D rigs at a rate of 2000 per day. A date is scrawled on every box: 'Fifth November.' Nobody knows what year.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Military",
			"label": "hit Security infrastructure to keep the masked march uninterrupted"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"public_tension": 2},
		"completion_headline": "On Fifth November the masks filled the square. Enforcers held position but did not move. By morning the masks were everywhere. The feed called them a 'demonstration'. They were a warning.",
		"timeout_headline": "The Fifth November march was 'postponed indefinitely' after a coordinated checkpoint sweep. The masks vanished from the markets. Someone kept their box.",
		"reward": {"tension_delta": 20, "senate_alignment_delta": -15, "idealism_bump": 0.15},
	},
	{
		"id": "confectioner_arc",
		"tier": 3,
		"archetype": "corporate_priest",
		"name": "The Confectioner",
		"min_cycle": 8,
		"probability": 0.08,
		"gate": {
			"senate_alignment": {"min": 60.0},
			"player_chaos_preference": {"min": 0.35},
		},
		"intro_headline": "A Confectioner with a nameless charitable foundation is setting up 'wellness dispensaries' in the Sinks. The pamphlets are sweet. The contracts are long.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Pharma",
			"label": "leak dirt on the Pharma oligarch to expose what's really in the dispensaries"
		},
		"arc_duration_cycles": 6,
		"while_active_modifiers": {"senate_alignment": 1},
		"completion_headline": "The Confectioner's dispensaries were shut down overnight after a leak revealed adulterants. Lawsuits are being organized. He's in transit to another region.",
		"timeout_headline": "The Confectioner expanded. Six more dispensaries opened. Pharma stock rose 14%. Worker mortality in the Sinks quietly rose.",
		"reward": {"tension_delta": 12, "senate_alignment_delta": -10, "idealism_bump": 0.08},
	},
	{
		"id": "pattern_match_arc",
		"tier": 3,
		"archetype": "rogue_ai",
		"name": "Pattern Match Exceeded",
		"min_cycle": 8,
		"probability": 0.08,
		"gate": {
			"player_heat": {"min": 55.0},
			"security_presence": {"min": 60.0},
		},
		"intro_headline": "Compliance AI logs are leaking across the feed — a single service account keeps issuing warnings about 'pattern match exceeded on the following subject' but the subject field is redacted. The AI seems to be warning someone about itself.",
		"objective": {
			"kind": "sabotage_sector",
			"target_ref": "Tech",
			"label": "disrupt Tech infrastructure to scramble the AI's pattern index before it converges"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"security_presence": 1},
		"completion_headline": "The compliance AI's pattern index was corrupted after the Tech hit. Warnings stopped. For 72 hours the Sinks moved unobserved.",
		"timeout_headline": "The compliance AI converged. 'Pattern match confirmed.' Six specific citizens were pulled in overnight. None of them you.",
		"reward": {"security_delta": -15, "stealth_bump": 0.15, "heat_delta": -10},
	},
	{
		"id": "indexed_debt_arc",
		"tier": 3,
		"archetype": "whistleblower",
		"name": "Indexed Debt",
		"min_cycle": 7,
		"probability": 0.09,
		"gate": {
			"senate_alignment": {"min": 55.0},
			"public_tension": {"min": 50.0},
		},
		"intro_headline": "An indexed spreadsheet of 140,000 Sinks-resident debt records — names, balances, garnishment schedules — leaked onto /gutter/ at 03:12. The Finance sector is scrambling. The source calls itself 'The Ledger-Keeper'.",
		"objective": {
			"kind": "leak_sector",
			"target_ref": "Finance",
			"label": "leak dirt on the Finance oligarch so the Ledger-Keeper's story crests before the clearing houses patch the breach"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"public_tension": 2, "senate_alignment": -1},
		"completion_headline": "The Ledger-Keeper's archive crossed with your leak, and the Finance oligarch went quiet. An emergency 'debt jubilee' was announced overnight for Sinks-tier balances under 5,000 credits. Nobody expected to see that word in writing.",
		"timeout_headline": "The Ledger-Keeper's archive was ruled 'fabricated' by three indexed outlets. The clearing houses patched the breach. Garnishment schedules continued on time.",
		"reward": {"debt_jubilee": true, "tension_delta": 12, "senate_alignment_delta": -14, "idealism_bump": 0.12},
	},

	# Second Tier-4 Takeover — loop_in_time archetype
	{
		"id": "the_revenant",
		"tier": 4,
		"archetype": "loop_in_time",
		"name": "The Revenant",
		"min_cycle": 9,
		"probability": 0.09,
		"gate": {
			"public_tension": {"min": 50.0},
			"player_heat": {"min": 40.0},
		},
		"intro_headline": "A woman in gray approaches you outside a transit zone — calls you by a name you've never used, describes a death you haven't had. She says you owe her for the last cycle. A cycle that shouldn't exist.",
		"arc_steps": [
			{
				"kind": "accept_prompt",
				"prompt_title": "// THE REVENANT",
				"prompt_body": "A woman in gray holds out a keycard. 'You left this with me last time. You died three days later. I've been waiting four years to give it back.' You don't remember her. She doesn't care.",
				"accept_label": "TAKE THE KEYCARD",
				"decline_label": "SHE'S DELUSIONAL — LEAVE",
				"on_accept_headline": "You took the keycard. It opens something. You don't know what yet.",
				"on_decline_headline": "The woman slipped the keycard into her pocket and walked off. For the next week, you occasionally notice her across a crowd. She's never looking at you.",
			},
			{
				"kind": "action_objective",
				"objective": {
					"kind": "leak_sector",
					"target_ref": "Military",
					"label": "leak on the Security oligarch — 'the one she said killed us last time'"
				},
				"on_completion_headline": "The keycard worked. The leak went clean. 'I told you,' she said, when you returned. 'She killed us last time too.'",
			},
			{
				"kind": "binary_decision",
				"prompt_title": "// THE LOOP",
				"prompt_body": "The Revenant hands you a second keycard. 'The next rung is forever. Take it — and you won't come back from this run either. Refuse it — and you forget we ever met.'",
				"options": [
					{
						"label": "TAKE IT — become the loop",
						"flavor": "You accept the logic. The cycle advances. You do not forget.",
						"effects": {
							"tension_delta": 20,
							"stealth_bump": 0.15,
							"headline": "The Revenant vanished into the crowd at dawn. You don't remember her name. You remember why she mattered."
						},
					},
					{
						"label": "REFUSE — forget",
						"flavor": "You hand the keycard back. She nods, like she expected this. The world briefly ripples.",
						"effects": {
							"heat_delta": -15,
							"headline": "The Revenant is gone. You can't place where you've seen her before. The keycard you had is empty plastic now."
						},
					},
				],
			},
		],
		"while_active_modifiers": {},
		"arc_duration_cycles": 7,
		"timeout_headline": "The Revenant stopped appearing. You half-remember a conversation about keycards. It doesn't resolve.",
	},

	{
		"id": "soap_man",
		"tier": 4,
		"archetype": "chaos_prophet",
		"name": "The Soap Man",
		"min_cycle": 6,
		"probability": 0.14,
		"gate": {
			"public_tension": {"min": 50.0},
			"player_chaos_preference": {"min": 0.45},
		},
		"intro_headline": "An unlicensed broadcast on Pirate 88.8 calls for 'space monkeys'. Enforcers investigating. A stranger slips something into your pocket on the street — a bar of soap, and an address on Paper Street.",
		"arc_steps": [
			{
				"kind": "accept_prompt",
				"prompt_title": "// PAPER STREET",
				"prompt_body": "A stranger hands you a bar of soap and an address on Paper Street. He doesn't wait for a reply. The invitation is open.",
				"accept_label": "TAKE THE SOAP",
				"decline_label": "WALK AWAY",
				"on_accept_headline": "You took the soap. The first homework is waiting.",
				"on_decline_headline": "You handed the soap back. The stranger nodded once, and was gone. 'Soap-related vandalism' lingers on the feed for weeks.",
			},
			{
				"kind": "action_objective",
				"objective": {
					"kind": "sabotage_sector",
					"target_ref": "Finance",
					"label": "run the first homework — hit a Finance clearing house so the debt ledgers go dark"
				},
				"on_completion_headline": "You ran the first homework. A Finance clearing house went offline for 91 minutes; consumer debt records briefly unreadable. Paper Street notices. The Project hums.",
			},
			{
				"kind": "binary_decision",
				"prompt_title": "// THE CHOICE",
				"prompt_body": "The Soap Man looks you in the eye. 'The next rung up asks for someone's name. Absorb the Project — let it grow beyond you — or betray it and close the door.'",
				"options": [
					{
						"label": "ABSORB — the Project grows",
						"flavor": "Paper Street consolidates. Project Mayhem becomes permanent. Workers radicalize. Tension climbs. Debt ledgers across three regions burn in a single night — the player's rent debt goes with them.",
						"effects": {
							"debt_jubilee": true,
							"tension_delta": 15,
							"senate_alignment_delta": -10,
							"chaos_bump": 0.20,
							"headline": "You absorbed the Project. Paper Street's list is yours. Project Mayhem burns the debt ledgers on the 4:12 broadcast. Your name was in them."
						},
					},
					{
						"label": "BETRAY — close the door",
						"flavor": "You name a name. The patrol moves. The Soap Man is gone by morning. A scandal follows you.",
						"effects": {
							"heat_delta": 20,
							"tension_delta": -5,
							"ruthless_bump": 0.15,
							"headline": "The Soap Man was 'taken in' before dawn. Your name surfaces in scandal circulation. Six Workers you met last week remember you as the traitor."
						},
					},
				],
			},
		],
		"while_active_modifiers": {"public_tension": 1},
		"arc_duration_cycles": 8,
		"timeout_headline": "Paper Street dissolves quietly. Tension drops back to pre-arc levels over three cycles. The Soap Man never called back.",
	},
]
