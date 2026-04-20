class_name WCPool

# =============================================================
# WCPool: offline pools for white-collar listings + interview
# gauntlet. Pure data. GigBoard reads these when the LLM path
# is unavailable (no API key, HTTP failure, malformed response).
#
# When LLMManager.request_wc_gauntlet returns a valid payload,
# GigBoard uses the LLM output instead — these pools are the
# fallback, not the primary. See docs/04-player/gigs.md.
# =============================================================

const TITLES: Array[String] = [
	"Associate Brand Strategist",
	"Junior Compliance Analyst",
	"Content Moderator (Temp, 90-day)",
	"Assistant Director of Vibes",
	"Senior Junior Product Evangelist",
	"Growth Enablement Specialist",
	"Revenue Operations Generalist",
	"Customer Outcomes Coordinator",
	"People & Culture Analyst",
	"Strategic Initiatives Fellow",
	"Digital Transformation Consultant (Contract)",
	"Head of Adjacency (Individual Contributor)",
]

const COMPANIES: Array[String] = [
	"Vextol Capital Partners",
	"Krynne Systems Group",
	"Aurelius Wellness Holdings",
	"Paperclip & Thorne, LLP",
	"Convergent Harmony Consulting",
	"OpticalLatitude Inc.",
	"Ascendant Logistics Co-op",
	"Meridian Compliance Bureau",
	"Fifth-Wave Outcomes",
	"Gant Trust & Fiduciary",
	"Monarch Parallel Ventures",
	"Quantum Lattice Research Foundation",
]

const DESCRIPTIONS: Array[String] = [
	"Drive cross-functional alignment across high-leverage workstreams. Travel 15%. Snacks.",
	"Own the compliance story end-to-end. Move fast without breaking the audit trail.",
	"Seeking a self-starter who thrives in ambiguity and can pivot without complaining.",
	"Hybrid role. Six days in-office, one day 'flex'. Laptop provided (recovered at separation).",
	"Build the future of [BLANK]. We'll figure out what [BLANK] means together.",
	"Non-traditional compensation structure. Equity-leaning. Ask in round two.",
	"Looking for a 'founder mindset'. This is not a founder role.",
	"Report to three directors. Priority-negotiate across all three weekly.",
	"Expected: 50 hours. Billed: 40. 'Growth mindset' essential.",
	"The successful candidate will be humble, hungry, smart — and 'unreasonably available'.",
]

const INTERVIEW_QUESTIONS: Array[Dictionary] = [
	{
		"prompt": "Describe a time you exceeded expectations without extra compensation. What did you learn about yourself?",
		"options": [
			{"label": "I stayed late on a launch. Learned I can do more.", "rejection_fragment": "we found your response at (1) to lean excessively on time-based heroics, which is orthogonal to our culture of sustainable overperformance"},
			{"label": "I reframed the problem and avoided scope creep.", "rejection_fragment": "your answer at (1) revealed a preference for boundary-setting that does not align with the adjacency model we're building toward"},
			{"label": "I don't believe in unpaid labor.", "rejection_fragment": "your candor on (1) was refreshing, but we require a certain flexibility around the compensation conversation"},
			{"label": "I delegated upward to create visibility.", "rejection_fragment": "on (1), 'delegating upward' reads to our panel as misreading your lane — a common failure mode"},
		],
	},
	{
		"prompt": "Estimate the number of pigeons currently residing within The Enclave. Show your reasoning.",
		"options": [
			{"label": "~5,000. Back-of-envelope: 1 per 4 residents, minus nets.", "rejection_fragment": "the 5,000 figure at (2) reveals insufficient top-down calibration — a senior hire would have started with airspace volume, not resident density"},
			{"label": "Uncountable — we'd need a stratified sampling method first.", "rejection_fragment": "declining to estimate at (2) signaled a risk aversion our team does not value at this level"},
			{"label": "Zero. Pigeons are prohibited by ordinance 41-C.", "rejection_fragment": "technically correct on (2), but pedantic answers rarely survive the room in a pitch"},
			{"label": "Why is this relevant to the role?", "rejection_fragment": "challenging the premise on (2) was brave — and, in this case, misread"},
		],
	},
	{
		"prompt": "If you were a currently-disrupting consumer brand, which would you be, and why?",
		"options": [
			{"label": "Soap Man Broadcast — grassroots, viral, unapologetic.", "rejection_fragment": "naming Soap Man at (3) raised compliance flags we cannot ignore post-hire"},
			{"label": "Indexed Debt — transparent, accountable, unstoppable.", "rejection_fragment": "the Indexed Debt reference at (3) is not one our brand legal team wants adjacent to us"},
			{"label": "Paperclip & Thorne — steady, trusted, adult.", "rejection_fragment": "on (3) you cited our own company, which reads as either sycophancy or a lack of imagination"},
			{"label": "The concept of 'disruption' is downstream of late-capital exhaustion.", "rejection_fragment": "your answer at (3) was 'thought-provoking', per the panel — which is a polite red flag"},
		],
	},
	{
		"prompt": "What's your biggest weakness? (Note: answers framed as strengths will be penalized.)",
		"options": [
			{"label": "I work too hard and burn out others.", "rejection_fragment": "on (4) you violated the preamble of the question itself, which the panel found self-diagnostic"},
			{"label": "I struggle to let go when a project isn't right.", "rejection_fragment": "(4) telegraphed a perfectionism that at our stage reads as risk-averse"},
			{"label": "I'm not good at performing enthusiasm I don't feel.", "rejection_fragment": "the honesty on (4) was appreciated — and, candidly, disqualifying"},
			{"label": "I don't have a meaningful weakness I'd disclose in an interview.", "rejection_fragment": "refusing to disclose on (4) is a tell the panel found louder than any admission"},
		],
	},
	{
		"prompt": "Why do you want to work here specifically, as opposed to a competitor?",
		"options": [
			{"label": "I've followed your work for years — it sets the standard.", "rejection_fragment": "on (5) you could not name a specific initiative beyond generalities, which broke the spell"},
			{"label": "Your compensation band is more aligned with my situation.", "rejection_fragment": "framing (5) around compensation was received as transactional in a way the panel does not reward"},
			{"label": "This is the role that was open when I needed one.", "rejection_fragment": "(5) was admirably honest. This is an unseeded culture; honest signal is a rare mistake here"},
			{"label": "I don't, particularly — I want the role, not the brand.", "rejection_fragment": "drawing the distinction at (5) was a structural misread of what we interview for"},
		],
	},
	{
		"prompt": "Walk us through a disagreement with a previous manager. What was the outcome?",
		"options": [
			{"label": "I escalated through proper channels. The policy changed.", "rejection_fragment": "'escalating through proper channels' at (6) reads as un-collaborative in our matrix"},
			{"label": "I presented data, they overruled me, we moved on.", "rejection_fragment": "the stoic acceptance at (6) suggested passivity where we need friction"},
			{"label": "I was right, they were wrong, I left.", "rejection_fragment": "the framing of (6) as binary right/wrong revealed a conflict-resolution style we've historically found incompatible"},
			{"label": "I haven't disagreed with a manager. That's how I work.", "rejection_fragment": "on (6) you presented as non-confrontational to a degree that concerned the debrief panel"},
		],
	},
]

const REJECTION_PREAMBLES: Array[String] = [
	"After careful consideration from the full hiring panel, we regret to inform you that we've decided to move forward with other candidates.",
	"Thank you for your time today. While your background is impressive, we've elected to pursue other applicants who more closely match what we are looking for right now.",
	"We appreciate you taking the time to interview with us. Unfortunately, we will not be moving forward with your candidacy at this time.",
	"After internal deliberation, the team has opted to continue its search.",
]

const REJECTION_CLOSINGS: Array[String] = [
	"We encourage you to re-apply in 12 months once you've had more time to grow in your current role.",
	"We wish you the very best in your ongoing search and future career.",
	"Please do keep us in mind for roles that may be more aligned with your profile in the future.",
	"We appreciate your interest in our organization and wish you continued success.",
]
