extends RefCounted
## Loads scenario data (setting, NPC cast, locations) from JSON.
## Scenarios are data, not code, so new ones can be written without
## touching the rules engine.
##
## NPC fields the AI uses: personality, background, wants, speech, knowledge
## and reactions (see npc/NPCState.gd). "notes" is for designers only and is
## never sent to the AI, so it's safe to write secrets there.

const NPCConfig = preload("res://npc/NPCConfig.gd")


## Returns the parsed scenario, or {} if the file is missing or invalid.
static func load_scenario(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		push_error("Scenario not found: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Scenario is not a JSON object: %s" % path)
		return {}
	return parsed


## Checks that the references inside a scenario line up. Returns a list of
## problems (empty means valid).
static func validate(scenario: Dictionary) -> Array:
	var problems := []
	var npc_ids := {}
	for npc in scenario.get("npcs", []):
		npc_ids[npc.get("id", "")] = true
	var location_ids := {}
	for loc in scenario.get("locations", []):
		location_ids[loc.get("id", "")] = true

	var target: String = scenario.get("target_npc", "")
	if target != "" and not npc_ids.has(target):
		problems.append("target_npc '%s' is not in the NPC list" % target)
	for npc in scenario.get("npcs", []):
		var home: String = npc.get("location", "")
		if not location_ids.has(home):
			problems.append("NPC '%s' is at unknown location '%s'" % [npc.get("id", "?"), home])
		problems.append_array(_validate_npc_ai_fields(npc))
	for loc in scenario.get("locations", []):
		for link in loc.get("connections", []):
			if not location_ids.has(link):
				problems.append("Location '%s' connects to unknown '%s'" % [loc.get("id", "?"), link])
	return problems


## Checks the knowledge and reactions an NPC's dialogue is built from.
static func _validate_npc_ai_fields(npc: Dictionary) -> Array:
	var problems := []
	var npc_id: String = npc.get("id", "?")
	var knowledge = npc.get("knowledge", [])
	if typeof(knowledge) != TYPE_ARRAY:
		return ["NPC '%s' knowledge must be a list" % npc_id]
	for entry in knowledge:
		if typeof(entry) != TYPE_DICTIONARY or String(entry.get("text", "")).strip_edges() == "":
			problems.append("NPC '%s' has a knowledge entry with no text" % npc_id)
			continue
		var trust = entry.get("share_at_trust", 0)
		if not typeof(trust) in [TYPE_INT, TYPE_FLOAT] or trust < 0 or trust > NPCConfig.MAX_TRUST:
			problems.append("NPC '%s' has share_at_trust outside 0..%d" % [npc_id, NPCConfig.MAX_TRUST])
	var reactions = npc.get("reactions", {})
	if typeof(reactions) != TYPE_DICTIONARY:
		return problems + ["NPC '%s' reactions must be an object" % npc_id]
	for approach in reactions.keys():
		if not approach in NPCConfig.APPROACHES:
			problems.append("NPC '%s' reacts to unknown approach '%s'" % [npc_id, approach])
			continue
		var change = reactions[approach]
		if not typeof(change) in [TYPE_INT, TYPE_FLOAT] or change < NPCConfig.MIN_TRUST or change > NPCConfig.MAX_TRUST:
			problems.append("NPC '%s' reaction to '%s' is outside %d..%d" % [npc_id, approach, NPCConfig.MIN_TRUST, NPCConfig.MAX_TRUST])
	return problems
