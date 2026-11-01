extends RefCounted
## Pure validation rules for the chat room. Kept separate from the
## networking code so they can be tested headlessly.

const MAX_NAME_LENGTH := 20
const MAX_MESSAGE_LENGTH := 300
## A player can send at most RATE_LIMIT_COUNT messages per RATE_LIMIT_WINDOW_MS.
const RATE_LIMIT_COUNT := 5
const RATE_LIMIT_WINDOW_MS := 3000


## Letters, digits, underscore and hyphen only. No spaces keeps
## "/w name message" unambiguous.
static func clean_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if _is_name_char(c):
			out += char(c)
	return out.substr(0, MAX_NAME_LENGTH)


## Strips control characters and surrounding whitespace, then caps the length.
static func clean_message(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c >= 32 and c != 127:
			out += char(c)
	return out.strip_edges().substr(0, MAX_MESSAGE_LENGTH)


## Returns `wanted`, or `wanted` with a number added if that name is taken
## (case-insensitive).
static func unique_name(wanted: String, taken: Array) -> String:
	var lower := []
	for t in taken:
		lower.append(String(t).to_lower())
	if not wanted.to_lower() in lower:
		return wanted
	var n := 2
	while ("%s%d" % [wanted, n]).to_lower() in lower:
		n += 1
	return "%s%d" % [wanted, n]


## Turns raw input into a command:
##   { "type": "say", "text": ... }
##   { "type": "whisper", "target": ..., "text": ... }
##   { "type": "team", "text": ... }                 (/a: private chat with your allies)
##   { "type": "ask", "target": ..., "text": ... }   talk to an NPC
##   { "type": "npcs" }                              list the NPCs
##   { "type": "error", "text": ... }
##   { "type": "empty" }
static func parse(raw: String) -> Dictionary:
	var text := clean_message(raw)
	if text == "":
		return {"type": "empty"}
	if not text.begins_with("/"):
		return {"type": "say", "text": text}

	var space := text.find(" ")
	var command := text.substr(1, space - 1 if space > 0 else -1).to_lower()
	var rest := text.substr(space + 1).strip_edges() if space > 0 else ""
	if command == "w" or command == "whisper":
		return _target_and_text("whisper", rest, "Usage: /w name message")
	if command == "ask" or command == "talk":
		return _target_and_text("ask", rest, "Usage: /ask name question  (/npcs lists the townsfolk)")
	if command == "npcs" or command == "townsfolk":
		return {"type": "npcs"}
	if command == "a":
		if rest == "":
			return {"type": "error", "text": "Usage: /a message"}
		return {"type": "team", "text": rest}
	return {"type": "error", "text": unknown_command_text(command)}


## Shared so the server can answer "/a" from a non-traitor exactly like any
## unknown command, without revealing that the command exists.
static func unknown_command_text(command: String) -> String:
	return "Unknown command /%s. Try /w name message, /ask name question, or /npcs." % command


## "name the rest of the message" -> { type, target, text }, or a usage error.
static func _target_and_text(kind: String, rest: String, usage: String) -> Dictionary:
	var split := rest.find(" ")
	if split <= 0:
		return {"type": "error", "text": usage}
	var body := rest.substr(split + 1).strip_edges()
	if body == "":
		return {"type": "error", "text": usage}
	return {"type": kind, "target": rest.substr(0, split), "text": body}


## Makes player text safe to show in a RichTextLabel with BBCode on, so
## nobody can inject formatting, images or links.
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


static func _is_name_char(c: int) -> bool:
	return (c >= 48 and c <= 57) \
		or (c >= 65 and c <= 90) \
		or (c >= 97 and c <= 122) \
		or c == 95 or c == 45
