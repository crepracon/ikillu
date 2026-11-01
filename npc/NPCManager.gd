extends RefCounted
## Every NPC in one session, built from scenario data, plus the rules for
## talking to them. Server only.
##
## The core rule: the AI only ever sees what this NPC knows and is willing to
## tell this particular player. A secret the NPC isn't ready to share never
## goes into the prompt at all, so no clever question can talk it out of the
## AI. The same goes for player roles: NPCs are never told who the traitors
## are, so they can't give it away.

const NPCStateScript = preload("res://npc/NPCState.gd")
const Config = preload("res://npc/NPCConfig.gd")

var scenario := {}
var day := 1
## npc id -> NPCState
var npcs := {}
## "player_key|npc_id" -> messages left in today's conversation
var _conversations := {}


func _init(p_scenario: Dictionary) -> void:
	scenario = p_scenario
	for data in scenario.get("npcs", []):
		if typeof(data) != TYPE_DICTIONARY or String(data.get("id", "")) == "":
			continue
		var npc = NPCStateScript.new(data)
		npcs[npc.id] = npc


func has_npc(npc_id: String) -> bool:
	return npcs.has(npc_id)


func get_npc(npc_id: String):
	return npcs.get(npc_id)


## Who can be talked to. Safe to send to every player.
func directory() -> Array:
	var out := []
	for npc in npcs.values():
		out.append({
			"id": npc.id,
			"alias": npc.short_alias(),
			"name": npc.name,
			"occupation": npc.occupation,
			"location": location_name(npc.location),
		})
	return out


## Finds an NPC by id or by any word of their name ("mara", "kestrel",
## "tobias"). Returns { "ok": true, "id": ... } or { "ok": false, "error": ... }.
func find(query: String) -> Dictionary:
	var q := query.strip_edges().to_lower()
	if q == "":
		return {"ok": false, "error": "Who do you want to talk to? /npcs lists the townsfolk."}
	if npcs.has(q):
		return {"ok": true, "id": q}
	var matches := []
	for npc in npcs.values():
		if q in npc.aliases():
			matches.append(npc.id)
	if matches.size() == 1:
		return {"ok": true, "id": matches[0]}
	if matches.size() > 1:
		return {"ok": false, "error": "More than one person answers to \"%s\". /npcs shows who's who." % query}
	return {"ok": false, "error": "Nobody called \"%s\" is around. /npcs lists the townsfolk." % query}


func location_name(location_id: String) -> String:
	for loc in scenario.get("locations", []):
		if loc.get("id", "") == location_id:
			return String(loc.get("name", location_id))
	return location_id


## Called at the start of each game day. Conversations close; NPCs keep
## their memories, hearsay and trust.
func start_day(new_day: int) -> void:
	day = new_day
	_conversations.clear()
	for npc in npcs.values():
		npc.start_day()


# --- Conversations -----------------------------------------------------------
# A conversation is a budget of messages with one NPC for the rest of the day.
# GameSession charges action points to open one; the chat room opens them free.

func has_open_conversation(player_key: String, npc_id: String) -> bool:
	return _conversations.get(_conv_key(player_key, npc_id), 0) > 0


func open_conversation(player_key: String, npc_id: String, messages := Config.MESSAGES_PER_CONVERSATION) -> void:
	_conversations[_conv_key(player_key, npc_id)] = messages


## Uses up one message. Returns how many are left in this conversation.
func use_message(player_key: String, npc_id: String) -> int:
	var key := _conv_key(player_key, npc_id)
	var left: int = maxi(_conversations.get(key, 0) - 1, 0)
	_conversations[key] = left
	return left


func _conv_key(player_key: String, npc_id: String) -> String:
	return "%s|%s" % [player_key, npc_id]


# --- Dialogue ----------------------------------------------------------------

## Everything the AI is allowed to know for one reply.
##   player: PUBLIC information only: name, plus optionally class, effects,
##           unmasked and unmasked_as.
##   town:   PUBLIC information only: day, tension (0..1, or -1 if hidden),
##           news (public events), faction labels.
## GameSession.npc_dialogue_context() builds both from public state.
func dialogue_context(npc_id: String, player_key: String, player: Dictionary, town: Dictionary) -> Dictionary:
	var npc = npcs.get(npc_id)
	if npc == null:
		return {}
	var cast := []
	for other in npcs.values():
		if other.id != npc.id:
			cast.append({
				"name": other.name,
				"occupation": other.occupation,
				"location": location_name(other.location),
			})
	var places := []
	for loc in scenario.get("locations", []):
		places.append({"name": String(loc.get("name", "")), "description": String(loc.get("description", ""))})
	var setting: Dictionary = scenario.get("setting", {})
	return {
		"setting": {
			"name": String(setting.get("name", "")),
			"town": String(setting.get("town", "")),
			"summary": String(setting.get("summary", "")),
			"tone": String(setting.get("tone", "")),
		},
		"places": places,
		"cast": cast,
		"npc": {
			"id": npc.id,
			"name": npc.name,
			"occupation": npc.occupation,
			"location": location_name(npc.location),
			"personality": npc.personality,
			"background": npc.background,
			"wants": npc.wants,
			"speech": npc.speech,
		},
		"shareable": npc.shareable_knowledge(player_key),
		"withheld_hints": npc.withheld_hints(player_key),
		"hearsay": npc.hearsay(),
		"town": town.duplicate(true),
		"player": player.duplicate(true),
		"trust": npc.get_trust(player_key),
		"memories": npc.memories_of(player_key),
		"transcript": npc.transcript_with(player_key),
	}


## Applies a validated reply (see NarrativeResponse) after the NPC has
## answered: remembers the exchange, records hearsay, and changes trust by
## the rules. The AI only labels the player's approach; this decides what
## that label is worth. Fallback replies change nothing but the transcript.
## Returns { "trust_change": int, "trust": int }.
func apply_reply(npc_id: String, player_key: String, player_name: String, player_text: String, reply: Dictionary) -> Dictionary:
	var npc = npcs.get(npc_id)
	if npc == null:
		return {"trust_change": 0, "trust": 0}
	npc.add_line(player_key, "player", player_text)
	npc.add_line(player_key, "npc", String(reply.get("dialogue", "")))
	if reply.get("fallback", false):
		return {"trust_change": 0, "trust": npc.get_trust(player_key)}
	npc.remember(player_key, day, String(reply.get("memory", "")))
	npc.hear(day, player_name, String(reply.get("rumor", "")))
	var change: int = npc.change_trust(player_key, npc.reaction_to(String(reply.get("approach", "neutral"))))
	return {"trust_change": change, "trust": npc.get_trust(player_key)}
