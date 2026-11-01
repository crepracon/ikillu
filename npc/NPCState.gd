extends RefCounted
## One NPC in one game session: who they are (from scenario data), what they
## know, and what they think of each player. Lives only on the server.
## The AI never sees this object, only the filtered context NPCManager
## builds from it.
##
## Players are identified by a string key: the player id in a game, or the
## player's name in the chat room.

const Config = preload("res://npc/NPCConfig.gd")

var id := ""
var name := ""
var occupation := ""
## Location id where this NPC is usually found.
var location := ""
var personality := ""
var background := ""
var wants := ""
var speech := ""
## What this NPC knows. Each entry: { "text", "share_at_trust", "hint" }.
## share_at_trust: the trust a player needs before the NPC will tell them.
## hint: how the NPC behaves while keeping it to themselves (optional).
var knowledge := []
## approach -> trust change: the defaults merged with this NPC's overrides.
var reactions := {}

## player key -> trust (int)
var _trust := {}
## player key -> trust gained today, for the daily cap
var _gained_today := {}
## player key -> Array of { "day", "text" }, oldest first
var _memories := {}
## player key -> Array of { "speaker": "player" or "npc", "text" } for today
var _transcript := {}
## Claims travelers have made to this NPC. Beliefs, not facts.
## Each: { "day", "from", "claim" }
var _hearsay := []


func _init(data: Dictionary) -> void:
	id = String(data.get("id", ""))
	name = String(data.get("name", id))
	occupation = String(data.get("occupation", ""))
	location = String(data.get("location", ""))
	personality = String(data.get("personality", ""))
	background = String(data.get("background", ""))
	wants = String(data.get("wants", ""))
	speech = String(data.get("speech", ""))
	for entry in data.get("knowledge", []):
		if typeof(entry) == TYPE_DICTIONARY:
			learn(String(entry.get("text", "")), int(entry.get("share_at_trust", 0)), String(entry.get("hint", "")))
	reactions = Config.DEFAULT_REACTIONS.duplicate()
	var overrides = data.get("reactions", {})
	if typeof(overrides) == TYPE_DICTIONARY:
		for approach in overrides.keys():
			if approach in Config.APPROACHES:
				reactions[approach] = Config.clamp_trust(int(overrides[approach]))


## Every word someone might use to mean this NPC: "mara", "kestrel", "sir",
## "old_tobias", "tobias"...
func aliases() -> Array:
	var out := [id.to_lower(), id.to_lower().replace("_", ""), short_alias()]
	for word in name.to_lower().split(" ", false):
		var clean := ""
		for i in word.length():
			var c := word.unicode_at(i)
			if (c >= 97 and c <= 122) or (c >= 48 and c <= 57):
				clean += char(c)
		if clean != "" and not clean in out:
			out.append(clean)
	return out


## One word to type after /ask: the last part of the id ("sir_kestrel" -> "kestrel").
func short_alias() -> String:
	var parts := id.to_lower().split("_", false)
	return parts[parts.size() - 1] if parts.size() > 0 else id.to_lower()


# --- Knowledge ---------------------------------------------------------------

## Adds something this NPC knows. Game code can call this during play, for
## example to give a witness what they saw at night.
func learn(text: String, share_at_trust := 0, hint := "") -> void:
	var clean := text.strip_edges()
	if clean == "":
		return
	knowledge.append({
		"text": clean,
		"share_at_trust": clampi(share_at_trust, 0, Config.MAX_TRUST),
		"hint": hint.strip_edges(),
	})


## What this NPC is willing to tell this player right now.
func shareable_knowledge(player_key: String) -> Array:
	var out := []
	var t := get_trust(player_key)
	for k in knowledge:
		if t >= k["share_at_trust"]:
			out.append(k["text"])
	return out


## How the NPC acts while keeping their other secrets from this player.
## Only the hints, never the secrets themselves.
func withheld_hints(player_key: String) -> Array:
	var out := []
	var t := get_trust(player_key)
	for k in knowledge:
		if t < k["share_at_trust"] and k["hint"] != "" and not k["hint"] in out:
			out.append(k["hint"])
	return out


# --- Trust -------------------------------------------------------------------

func get_trust(player_key: String) -> int:
	return _trust.get(player_key, 0)


## Applies a trust change, respecting the daily gain cap and the trust range.
## Returns the change that actually happened.
func change_trust(player_key: String, delta: int) -> int:
	var before := get_trust(player_key)
	var allowed := delta
	if delta > 0:
		var room: int = Config.MAX_TRUST_GAIN_PER_DAY - _gained_today.get(player_key, 0)
		allowed = mini(delta, maxi(room, 0))
	var after := Config.clamp_trust(before + allowed)
	_trust[player_key] = after
	var applied := after - before
	if applied > 0:
		_gained_today[player_key] = _gained_today.get(player_key, 0) + applied
	return applied


## Trust change for an approach label, using this NPC's reactions.
func reaction_to(approach: String) -> int:
	return reactions.get(approach, 0)


# --- Memory ------------------------------------------------------------------

func remember(player_key: String, day: int, text: String) -> void:
	var clean := text.strip_edges()
	if clean == "":
		return
	var list: Array = _memories.get(player_key, [])
	if not list.is_empty() and list[-1]["text"] == clean:
		return # Same as the last memory: nothing new to remember.
	list.append({"day": day, "text": clean})
	while list.size() > Config.MAX_MEMORIES_PER_PLAYER:
		list.pop_front()
	_memories[player_key] = list


func memories_of(player_key: String) -> Array:
	return _memories.get(player_key, []).duplicate(true)


func add_line(player_key: String, speaker: String, text: String) -> void:
	var list: Array = _transcript.get(player_key, [])
	list.append({"speaker": speaker, "text": text})
	while list.size() > Config.MAX_TRANSCRIPT_LINES:
		list.pop_front()
	_transcript[player_key] = list


func transcript_with(player_key: String) -> Array:
	return _transcript.get(player_key, []).duplicate(true)


func hear(day: int, from_name: String, claim: String) -> void:
	var clean := claim.strip_edges()
	if clean == "":
		return
	_hearsay.append({"day": day, "from": from_name, "claim": clean})
	while _hearsay.size() > Config.MAX_HEARSAY:
		_hearsay.pop_front()


func hearsay() -> Array:
	return _hearsay.duplicate(true)


## Called at the start of each day: today's talk is over, memories remain.
func start_day() -> void:
	_gained_today.clear()
	_transcript.clear()
