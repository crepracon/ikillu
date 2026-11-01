extends RefCounted
## Reads the AI's reply and checks it before the game uses it. The AI's
## output gets the same treatment as player input: cleaned, capped, and
## rejected if it doesn't fit. Nothing here changes game state. A reply is
## just text plus labels, and NPCManager.apply_reply() decides by the rules
## what the labels are worth.
##
## A validated reply looks like:
##   { "ok": true, "dialogue", "action", "emotion", "approach", "memory", "rumor" }
## and a failure like { "ok": false, "error": "..." }.

const NPCConfig = preload("res://npc/NPCConfig.gd")

## Phrases that mean the AI stepped out of the world.
const OUT_OF_CHARACTER := ["as an ai", "language model", "system prompt", "anthropic", "openai", "chatgpt"]

## In-character brush-offs for when there's no AI or a call fails, so the
## game keeps working. They don't change trust or create memories.
const FALLBACKS := [
	{"action": "seems distracted", "dialogue": "Sorry, my mind's elsewhere. Ask me again in a bit."},
	{"action": "shakes their head", "dialogue": "Not now. I've too much on my plate."},
	{"action": "doesn't catch it over the din", "dialogue": "Eh? Ask me again later, I can't think straight just now."},
]

const QUOTE_CHARS := ["\"", "“", "”", "«", "»"]


## Parses a Messages API response body.
static func from_api_response(data: Dictionary) -> Dictionary:
	match String(data.get("stop_reason", "")):
		"refusal":
			return _fail("the model declined to answer")
		"max_tokens":
			return _fail("the reply was cut off")
	for block in data.get("content", []):
		if typeof(block) == TYPE_DICTIONARY and block.get("type", "") == "text":
			return from_json_text(String(block.get("text", "")))
	return _fail("no text in the reply")


static func from_json_text(text: String) -> Dictionary:
	var t := text.strip_edges()
	# Structured output shouldn't arrive in a code fence, but a proxy or
	# another model might wrap it in one.
	if t.begins_with("```"):
		var first_newline := t.find("\n")
		var last_fence := t.rfind("```")
		if first_newline != -1 and last_fence > first_newline:
			t = t.substr(first_newline + 1, last_fence - first_newline - 1).strip_edges()
	var parsed = parse_json_quietly(t)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("the reply wasn't JSON")
	return validate(parsed)


## Like JSON.parse_string(), but returns null on bad input instead of
## printing an engine error.
static func parse_json_quietly(text: String):
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func validate(raw: Dictionary) -> Dictionary:
	var dialogue := clean_text(raw.get("dialogue", ""))
	var action := clean_text(raw.get("action", ""))
	# Pull *stage directions* out of the speech.
	var stage := RegEx.create_from_string("\\*([^*]+)\\*")
	var found := stage.search(dialogue)
	if found != null:
		if action == "":
			action = found.get_string(1)
		dialogue = clean_text(stage.sub(dialogue, " ", true))
	dialogue = _strip_quotes(dialogue)
	action = _strip_wrapping(action)
	if dialogue == "":
		return _fail("empty dialogue")

	var memory := clean_text(raw.get("memory", ""))
	var rumor := clean_text(raw.get("rumor", ""))
	var everything := " ".join([dialogue, action, memory, rumor]).to_lower()
	for phrase in OUT_OF_CHARACTER:
		if phrase in everything:
			return _fail("out of character")

	return {
		"ok": true,
		"dialogue": cap(dialogue, NPCConfig.MAX_DIALOGUE_LENGTH),
		"action": cap(action, NPCConfig.MAX_ACTION_LENGTH),
		"emotion": _pick(raw.get("emotion", ""), NPCConfig.EMOTIONS),
		"approach": _pick(raw.get("approach", ""), NPCConfig.APPROACHES),
		"memory": cap(memory, NPCConfig.MAX_MEMORY_LENGTH),
		"rumor": cap(rumor, NPCConfig.MAX_RUMOR_LENGTH),
	}


## A short in-character brush-off. `variety` picks which one, so the same
## question always gets the same brush-off.
static func fallback(reason := "", variety := "") -> Dictionary:
	var pick: Dictionary = FALLBACKS[absi(variety.hash()) % FALLBACKS.size()]
	return {
		"ok": true,
		"fallback": true,
		"error": reason,
		"dialogue": pick["dialogue"],
		"action": pick["action"],
		"emotion": "neutral",
		"approach": "neutral",
		"memory": "",
		"rumor": "",
	}


## Control characters become spaces, runs of whitespace collapse.
static func clean_text(value) -> String:
	var raw := String(value) if value != null else ""
	var out := ""
	var last_space := true
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c < 32 or c == 127 or c == 32:
			if not last_space:
				out += " "
				last_space = true
		else:
			out += char(c)
			last_space = false
	return out.strip_edges()


## Shortens text to `limit` characters, ending on a full sentence if it can.
static func cap(text: String, limit: int) -> String:
	if text.length() <= limit:
		return text
	var cut := text.substr(0, limit)
	var best := -1
	for mark in [". ", "! ", "? "]:
		best = maxi(best, cut.rfind(mark))
	if best >= floori(limit / 3.0):
		return cut.substr(0, best + 1)
	return cut.substr(0, limit - 1).strip_edges() + "…"


static func _strip_quotes(text: String) -> String:
	var t := text
	while t.length() >= 2 and t.left(1) in QUOTE_CHARS and t.right(1) in QUOTE_CHARS:
		t = t.substr(1, t.length() - 2).strip_edges()
	return t


## "*glances at the door.*" -> "glances at the door"
static func _strip_wrapping(text: String) -> String:
	var t := text.strip_edges()
	for ch in ["*", "(", ")", "[", "]", "_"]:
		t = t.trim_prefix(ch).trim_suffix(ch).strip_edges()
	return t.trim_suffix(".").strip_edges()


static func _pick(value, allowed: Array) -> String:
	var v := String(value).strip_edges().to_lower() if value != null else ""
	return v if v in allowed else "neutral"


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
