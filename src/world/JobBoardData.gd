class_name JobBoardData

# =============================================================
# JobBoardData: data + pure helpers for the resistance/fixer job
# system. State (active_jobs, _next_job_index) and signals stay on
# WorldDirector because they're owned by the simulation's main
# cycle; this module holds what's genuinely static.
#
# - RESISTANCE_CELLS: the 10 underground cell names the game rolls
#   from when generating contracts. Adding or renaming a cell is a
#   one-line edit here.
# - post_headline / complete_headline: pure format functions for
#   NetFeed text, broken out so copy tweaks don't touch engine flow.
# =============================================================

const RESISTANCE_CELLS: Array[String] = [
	"The Red Circle",
	"Paper Street Crew",
	"The Ash Underground",
	"The Sinks Collective",
	"The Unlicensed Dispatch",
	"The Thirteenth Hour",
	"The Rust Coalition",
	"The Night Shift",
	"The Gutter Press",
	"The Unindexed",
]


static func post_headline(job: Dictionary) -> String:
	match str(job.get("source_type", "")):
		"resistance_cell":
			return "Underground broadcast on a pirate frequency — %s" % str(job.get("framing", ""))
		"npc_fixer":
			return "Fixer signal in the Sinks — %s" % str(job.get("framing", ""))
	return "Job posted."


static func complete_headline(job: Dictionary) -> String:
	match str(job.get("source_type", "")):
		"resistance_cell":
			return "%s broadcasts a thank-you on the pirate channel. The %s sector is audibly limping." % [
				str(job.get("source_name", "A resistance cell")),
				str(job.get("target_ref", "")),
			]
		"npc_fixer":
			return "%s quietly paid an unnamed operative. A debt acknowledged." % str(job.get("source_name", "Someone"))
	return "Job completed."
