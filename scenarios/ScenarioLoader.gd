extends RefCounted
## Loads scenario data (setting, NPC cast, locations) from JSON.
## Scenarios are data, not code, so new ones can be written without
## touching the rules engine.


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
	for loc in scenario.get("locations", []):
		for link in loc.get("connections", []):
			if not location_ids.has(link):
				problems.append("Location '%s' connects to unknown '%s'" % [loc.get("id", "?"), link])
	return problems
