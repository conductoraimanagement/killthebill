extends Node
class_name CulturalCameos

# =============================================================
# CulturalCameos: the trigger engine for pop-culture intrusions.
#
# Each cameo is gated by world state + player profile. Evaluated
# once per news cycle. Tier 1 Whispers (NetFeed-only, no mechanical
# impact) are live today; Tier 2-4 are designed in
# docs/03-characters/cultural-cameos.md and awaited.
#
# Cameos that have fired once during the run won't fire again —
# rarity is preserved across the playthrough.
# =============================================================

signal cameo_triggered(cameo: Dictionary)
signal cameo_arc_started(arc: Dictionary)
signal cameo_arc_completed(arc: Dictionary)
signal cameo_arc_expired(arc: Dictionary)

# Multi-step arcs (Tier 4): these signals tell the HUD to open modals
# and await a player choice. HUD calls resolve_prompt / resolve_decision
# back on this autoload to advance the arc.
signal cameo_arc_prompt(arc: Dictionary, step: Dictionary)
signal cameo_arc_decision(arc: Dictionary, step: Dictionary)

const CAMEOS := [
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
			"target_ref": "Security",
			"label": "hit Security-sector infrastructure to draw patrols away from her route"
		},
		"arc_duration_cycles": 3,
		"completion_headline": "The Bread Thief slipped the cordon tonight. Bread distribution quietly resumed in the lower Sinks.",
		"timeout_headline": "The Bread Thief was caught at dawn. The patrols went quiet. The Sinks went quieter.",
		"reward": {"credits": 800, "tension_delta": -8, "idealism_bump": 0.08},
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
		"reward": {"credits": 700, "tension_delta": 6, "senate_alignment_delta": -6},
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
		"reward": {"credits": 1500, "tension_delta": 10, "idealism_bump": 0.15, "senate_alignment_delta": -8},
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
		"reward": {"credits": 1800, "tension_delta": 15, "idealism_bump": 0.10, "senate_alignment_delta": -12},
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
		"reward": {"credits": 900, "tension_delta": 8, "chaos_bump": 0.08},
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
		"reward": {"credits": 700, "tension_delta": 6, "idealism_bump": 0.12},
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
		"reward": {"credits": 1000, "tension_delta": 8, "senate_alignment_delta": -8},
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
		"reward": {"credits": 1900, "tension_delta": 14, "senate_alignment_delta": -12, "idealism_bump": 0.15},
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
		"reward": {"credits": 1800, "tension_delta": 10, "senate_alignment_delta": -10, "idealism_bump": 0.15},
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
			"target_ref": "Security",
			"label": "disrupt Security — his blessing circles have been infiltrated by Enforcers"
		},
		"arc_duration_cycles": 6,
		"while_active_modifiers": {"public_tension": -1},   # NEGATIVE — his presence soothes
		"completion_headline": "The priest's breadline survived the Enforcer sweep because someone hit a checkpoint three blocks over. He sat down on his fourteenth day. Thousands wept at the bread distribution that evening, for reasons the feed didn't photograph.",
		"timeout_headline": "The priest was arrested on Tuesday for 'unauthorized assembly'. Three attendees were detained. The breadline continued forming at the same corner, emptier.",
		"reward": {"credits": 1200, "tension_delta": -12, "idealism_bump": 0.20},
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
							"credits": 2500,
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
							"credits": 1500,
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
							"credits": 3500,
							"heat_delta": -60,
							"stealth_bump": 0.30,
							"headline": "The Compliance AI's Apotheosis resolved in self-termination. A small pattern correction cascaded through every surveillance camera in the region. You are harder to find now."
						}
					},
					{
						"label": "LET IT DIE ALONE",
						"flavor": "You leave it to its own resolution. The AI terminates. Something about the Sinks feels quieter in the days that follow.",
						"effects": {
							"credits": 1500,
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
		"reward": {"credits": 600, "tension_delta": -6, "idealism_bump": 0.12},
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
		"reward": {"credits": 900, "tension_delta": 5, "senate_alignment_delta": -5, "ruthless_bump": 0.05},
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
			"target_ref": "Security",
			"label": "hit Security infrastructure to keep the masked march uninterrupted"
		},
		"arc_duration_cycles": 5,
		"while_active_modifiers": {"public_tension": 2},
		"completion_headline": "On Fifth November the masks filled the square. Enforcers held position but did not move. By morning the masks were everywhere. The feed called them a 'demonstration'. They were a warning.",
		"timeout_headline": "The Fifth November march was 'postponed indefinitely' after a coordinated checkpoint sweep. The masks vanished from the markets. Someone kept their box.",
		"reward": {"credits": 2000, "tension_delta": 20, "senate_alignment_delta": -15, "idealism_bump": 0.15},
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
		"reward": {"credits": 1700, "tension_delta": 12, "senate_alignment_delta": -10, "idealism_bump": 0.08},
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
		"reward": {"credits": 2200, "security_delta": -15, "stealth_bump": 0.15, "heat_delta": -10},
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
					"target_ref": "Security",
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
							"credits": 3000,
							"tension_delta": 20,
							"stealth_bump": 0.15,
							"headline": "The Revenant vanished into the crowd at dawn. You don't remember her name. You remember why she mattered."
						},
					},
					{
						"label": "REFUSE — forget",
						"flavor": "You hand the keycard back. She nods, like she expected this. The world briefly ripples.",
						"effects": {
							"credits": 800,
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
					"target_ref": "Media",
					"label": "run the first homework — destroy a Media-sector billboard"
				},
				"on_completion_headline": "You ran the first homework. Paper Street notices. The Project hums.",
			},
			{
				"kind": "binary_decision",
				"prompt_title": "// THE CHOICE",
				"prompt_body": "The Soap Man looks you in the eye. 'The next rung up asks for someone's name. Absorb the Project — let it grow beyond you — or betray it and close the door.'",
				"options": [
					{
						"label": "ABSORB — the Project grows",
						"flavor": "Paper Street consolidates. Project Mayhem becomes permanent. Workers radicalize. Tension climbs.",
						"effects": {
							"credits": 2500,
							"tension_delta": 15,
							"senate_alignment_delta": -10,
							"chaos_bump": 0.20,
							"headline": "You absorbed the Project. Paper Street's list is yours. Project Mayhem continues under a new operator."
						},
					},
					{
						"label": "BETRAY — close the door",
						"flavor": "You name a name. The patrol moves. The Soap Man is gone by morning. A scandal follows you.",
						"effects": {
							"credits": 500,
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

var fired_ids: Array[String] = []

# Active higher-tier arcs currently running.
# Each entry: {cameo_id, definition, cycles_left, completed}
var active_arcs: Array[Dictionary] = []

# Only one Tier-3+ arc active at a time — the world can sustain one
# hijacking, not three.
const MAX_HIGH_TIER_ACTIVE := 1


func reset() -> void:
	fired_ids.clear()
	active_arcs.clear()


# Called by WorldDirector.trigger_news_cycle — one evaluation per
# phase boundary (3× per day), NOT per day.
func evaluate_triggers() -> void:
	for cameo in CAMEOS:
		var cameo_id: String = str(cameo.get("id", ""))
		if cameo_id in fired_ids:
			continue
		if not _is_gate_satisfied(cameo):
			continue
		if randf() < float(cameo.get("probability", 0.0)):
			_fire(cameo)


func _is_gate_satisfied(cameo: Dictionary) -> bool:
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return false
	if wd.cycle < int(cameo.get("min_cycle", 0)):
		return false

	# Cap Tier-3+ concurrent arcs. The world sustains one hijacking, not three.
	var tier: int = int(cameo.get("tier", 1))
	if tier >= 3 and _count_active_high_tier() >= MAX_HIGH_TIER_ACTIVE:
		return false

	var gate: Dictionary = cameo.get("gate", {})
	for key in gate.keys():
		var range_spec: Dictionary = gate[key]
		var value: float = _read_state_var(key)
		if range_spec.has("min") and value < float(range_spec["min"]):
			return false
		if range_spec.has("max") and value > float(range_spec["max"]):
			return false
	return true


func _read_state_var(key: String) -> float:
	var wd := get_node_or_null("/root/WorldDirector")
	var pm := get_node_or_null("/root/PlayerManager")
	match key:
		"public_tension":
			return float(wd.global_economy.get("public_tension", 0)) if wd else 0.0
		"senate_alignment":
			return float(wd.global_economy.get("senate_alignment", 50)) if wd else 50.0
		"food_price":
			return float(wd.global_economy.get("food_price", 0)) if wd else 0.0
		"security_presence":
			return float(wd.global_economy.get("security_presence", 0)) if wd else 0.0
		"player_heat":
			return float(pm.heat) if pm else 0.0
		"player_chaos_preference":
			return float(pm.player_chaos_preference) if pm else 0.0
		"player_idealism":
			return float(pm.player_idealism) if pm else 0.0
		"player_stealth_preference":
			return float(pm.player_stealth_preference) if pm else 0.0
		"player_ruthlessness":
			return float(pm.player_ruthlessness) if pm else 0.0
	return 0.0


func _fire(cameo: Dictionary) -> void:
	fired_ids.append(str(cameo.get("id", "")))
	cameo_triggered.emit(cameo)

	var tier: int = int(cameo.get("tier", 1))
	if tier == 1:
		# Whisper — flavor-only NetFeed note and we're done.
		_netfeed(str(cameo.get("headline", "")))
	else:
		# Higher tier — start an active arc.
		# current_step_index drives multi-step arcs (Tier 4). Tier 2/3
		# cameos that have an "objective" key but no "arc_steps" use the
		# legacy single-step path; current_step_index stays at 0 for them.
		var arc: Dictionary = {
			"cameo_id": str(cameo.get("id", "")),
			"definition": cameo,
			"cycles_left": int(cameo.get("arc_duration_cycles", 3)),
			"current_step_index": 0,
			"waiting_for_player": false,
			"completed": false,
		}
		active_arcs.append(arc)
		_netfeed(str(cameo.get("intro_headline", "")))
		cameo_arc_started.emit(arc)
		_enter_current_step(arc)

	print("Cameo triggered: [%s] %s (tier %d)" % [
		str(cameo.get("archetype", "?")),
		str(cameo.get("name", "?")),
		tier,
	])


# For multi-step arcs (Tier 4), entering the current step either:
#  - opens a prompt modal (accept_prompt / binary_decision) via signal
#  - waits for a world action (action_objective — caught in check_action_match)
# Legacy single-step arcs have no arc_steps; this is a no-op for them.
func _enter_current_step(arc: Dictionary) -> void:
	var steps: Array = arc.definition.get("arc_steps", [])
	if steps.is_empty():
		return
	if int(arc.current_step_index) >= steps.size():
		return
	var step: Dictionary = steps[int(arc.current_step_index)]
	match str(step.get("kind", "")):
		"accept_prompt":
			arc["waiting_for_player"] = true
			cameo_arc_prompt.emit(arc, step)
		"binary_decision":
			arc["waiting_for_player"] = true
			cameo_arc_decision.emit(arc, step)
		"action_objective":
			arc["waiting_for_player"] = false


# -------------------------------------------------------------
# Higher-tier arcs — completion, per-cycle modifiers, expiry
# -------------------------------------------------------------

# Called by WorldDirector.run_world_cycle (once per day).
func tick_daily() -> void:
	var remaining: Array[Dictionary] = []
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		_apply_cycle_modifiers(arc)
		arc["cycles_left"] = int(arc.get("cycles_left", 0)) - 1
		if int(arc["cycles_left"]) <= 0:
			_expire_arc(arc)
		else:
			remaining.append(arc)
	active_arcs = remaining


# Called by WorldDirector ripples when the player takes a mapped action.
# kind: "sabotage_sector" | "leak_oligarch" | "leak_sector"
# target_ref: sector name or oligarch_id
func check_action_match(kind: String, target_ref: String) -> void:
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue

		var steps: Array = arc.definition.get("arc_steps", [])
		if steps.is_empty():
			# Legacy single-step path (Tier 2/3 with just "objective").
			var obj: Dictionary = arc.definition.get("objective", {})
			if str(obj.get("kind", "")) == kind and str(obj.get("target_ref", "")) == target_ref:
				_complete_arc(arc)
			continue

		# Multi-step path — only match if the *current* step is an
		# action_objective waiting for a world match.
		if bool(arc.get("waiting_for_player", false)):
			continue
		var idx: int = int(arc.current_step_index)
		if idx >= steps.size():
			continue
		var step: Dictionary = steps[idx]
		if str(step.get("kind", "")) != "action_objective":
			continue
		var step_obj: Dictionary = step.get("objective", {})
		if str(step_obj.get("kind", "")) == kind and str(step_obj.get("target_ref", "")) == target_ref:
			_advance_step_after_action(arc, step)

	# Prune completed.
	var remaining: Array[Dictionary] = []
	for a in active_arcs:
		if not bool(a.get("completed", false)):
			remaining.append(a)
	active_arcs = remaining


# Advance a multi-step arc after an action_objective matched.
func _advance_step_after_action(arc: Dictionary, step: Dictionary) -> void:
	_netfeed(str(step.get("on_completion_headline", "")))
	arc["current_step_index"] = int(arc.current_step_index) + 1
	if int(arc.current_step_index) >= arc.definition.arc_steps.size():
		# Ran past the last step — arc resolves naturally.
		arc["completed"] = true
		cameo_arc_completed.emit(arc)
	else:
		_enter_current_step(arc)


# Called by HUD after the player resolves an accept_prompt step.
func resolve_prompt(cameo_id: String, accepted: bool) -> void:
	var arc: Dictionary = _find_active_arc(cameo_id)
	if arc.is_empty():
		return
	var idx: int = int(arc.current_step_index)
	var steps: Array = arc.definition.arc_steps
	if idx >= steps.size():
		return
	var step: Dictionary = steps[idx]
	arc["waiting_for_player"] = false

	if accepted:
		_netfeed(str(step.get("on_accept_headline", "")))
		arc["current_step_index"] = idx + 1
		if int(arc.current_step_index) >= steps.size():
			arc["completed"] = true
			cameo_arc_completed.emit(arc)
		else:
			_enter_current_step(arc)
	else:
		_netfeed(str(step.get("on_decline_headline", "")))
		arc["completed"] = true
		cameo_arc_completed.emit(arc)

	_prune_completed_arcs()


# Called by HUD after the player resolves a binary_decision step.
# option_index: 0 or 1.
func resolve_decision(cameo_id: String, option_index: int) -> void:
	var arc: Dictionary = _find_active_arc(cameo_id)
	if arc.is_empty():
		return
	var idx: int = int(arc.current_step_index)
	var steps: Array = arc.definition.arc_steps
	if idx >= steps.size():
		return
	var step: Dictionary = steps[idx]
	var options: Array = step.get("options", [])
	if option_index < 0 or option_index >= options.size():
		return

	var opt: Dictionary = options[option_index]
	var effects: Dictionary = opt.get("effects", {})
	_apply_decision_effects(effects)
	_netfeed(str(effects.get("headline", "")))

	arc["waiting_for_player"] = false
	arc["completed"] = true
	cameo_arc_completed.emit(arc)
	_prune_completed_arcs()


func _apply_decision_effects(effects: Dictionary) -> void:
	_apply_effects(effects, "cameo decision")


# Unified effect applier — used by both the legacy single-step reward
# and the multi-step binary_decision options. Supported keys:
#   credits                — PlayerManager.add_credits
#   heat_delta             — PlayerManager.add_heat (positive or negative)
#   chaos_bump             — PlayerManager.bump_playstyle (chaos)
#   ruthless_bump          — PlayerManager.bump_playstyle (ruthlessness)
#   idealism_bump          — PlayerManager.bump_playstyle (idealism)
#   stealth_bump           — PlayerManager.bump_playstyle (stealth)
#   tension_delta          — WorldDirector.global_economy.public_tension
#   senate_alignment_delta — WorldDirector.global_economy.senate_alignment
#   security_delta         — WorldDirector.global_economy.security_presence
func _apply_effects(effects: Dictionary, reason: String) -> void:
	var pm := get_node_or_null("/root/PlayerManager")
	var wd := get_node_or_null("/root/WorldDirector")

	if pm:
		if effects.has("credits"):
			pm.add_credits(int(effects.credits), reason)
		if effects.has("heat_delta"):
			pm.add_heat(int(effects.heat_delta), reason)
		if effects.has("chaos_bump"):
			pm.bump_playstyle(float(effects.chaos_bump), 0.0, 0.0, 0.0)
		if effects.has("ruthless_bump"):
			pm.bump_playstyle(0.0, float(effects.ruthless_bump), 0.0, 0.0)
		if effects.has("idealism_bump"):
			pm.bump_playstyle(0.0, 0.0, float(effects.idealism_bump), 0.0)
		if effects.has("stealth_bump"):
			pm.bump_playstyle(0.0, 0.0, 0.0, float(effects.stealth_bump))

	if wd:
		if effects.has("tension_delta"):
			wd.global_economy["public_tension"] = clamp(
				int(wd.global_economy.get("public_tension", 0)) + int(effects.tension_delta),
				0, 100)
		if effects.has("senate_alignment_delta"):
			wd.global_economy["senate_alignment"] = clamp(
				int(wd.global_economy.get("senate_alignment", 50)) + int(effects.senate_alignment_delta),
				0, 100)
		if effects.has("security_delta"):
			wd.global_economy["security_presence"] = clamp(
				int(wd.global_economy.get("security_presence", 50)) + int(effects.security_delta),
				0, 100)


func _find_active_arc(cameo_id: String) -> Dictionary:
	for arc in active_arcs:
		if str(arc.get("cameo_id", "")) == cameo_id and not bool(arc.get("completed", false)):
			return arc
	return {}


func _prune_completed_arcs() -> void:
	var remaining: Array[Dictionary] = []
	for a in active_arcs:
		if not bool(a.get("completed", false)):
			remaining.append(a)
	active_arcs = remaining


func _complete_arc(arc: Dictionary) -> void:
	arc["completed"] = true
	var def: Dictionary = arc.definition
	var reward: Dictionary = def.get("reward", {})
	_apply_effects(reward, "cameo: %s" % str(def.get("name", "")))
	_netfeed(str(def.get("completion_headline", "")))
	cameo_arc_completed.emit(arc)


func _expire_arc(arc: Dictionary) -> void:
	var def: Dictionary = arc.definition
	_netfeed(str(def.get("timeout_headline", "")))
	cameo_arc_expired.emit(arc)


func _apply_cycle_modifiers(arc: Dictionary) -> void:
	var mods: Dictionary = arc.definition.get("while_active_modifiers", {})
	if mods.is_empty():
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	for key in mods.keys():
		var delta: int = int(mods[key])
		if wd.global_economy.has(key):
			wd.global_economy[key] = clamp(
				int(wd.global_economy[key]) + delta, 0, 100)


func _count_active_high_tier() -> int:
	var n: int = 0
	for arc in active_arcs:
		if bool(arc.get("completed", false)):
			continue
		if int(arc.definition.get("tier", 1)) >= 3:
			n += 1
	return n


func _netfeed(headline: String) -> void:
	if headline == "":
		return
	var wd := get_node_or_null("/root/WorldDirector")
	if wd == null:
		return
	var event := {
		"type": "NEWS_TICKER",
		"headline": headline,
		"timestamp": Time.get_unix_time_from_system(),
	}
	wd.netfeed_history.append(event)
	wd.netfeed_event_generated.emit(event)
