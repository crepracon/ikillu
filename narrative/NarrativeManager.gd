extends Node
## Server only: asks the Claude API what an NPC says, and hands back a
## validated reply. Clients never create this node, and the API key never
## leaves the server process.
##
## reply() always returns something usable. With no key, or when a call
## fails, the NPC gives a short in-character brush-off (marked "fallback")
## so the game keeps working, and a warning goes to the server log.

const Settings = preload("res://narrative/NarrativeSettings.gd")
const Request = preload("res://narrative/NarrativeRequest.gd")
const Response = preload("res://narrative/NarrativeResponse.gd")

## HTTP statuses worth one retry: rate limits, overload and server hiccups.
const RETRYABLE_STATUS := [408, 429, 500, 502, 503, 504, 529]
const MAX_ATTEMPTS := 2

var settings: Dictionary
var retry_delay := 1.0
## Sends one request body and returns { "ok": true, "data": Dictionary } or
## { "ok": false, "retryable": bool, "error": String }. Tests swap in a fake.
var transport: Callable


func _init() -> void:
	settings = Settings.load_settings()
	transport = _http_post


func is_enabled() -> bool:
	return Settings.is_enabled(settings)


## What the NPC says back to `player_text`, given a dialogue context from
## NPCManager.dialogue_context().
func reply(context: Dictionary, player_text: String) -> Dictionary:
	if not is_enabled():
		return Response.fallback("no API key set", player_text)
	var body := Request.build_body(context, player_text, settings)
	var error := ""
	for attempt in MAX_ATTEMPTS:
		if attempt > 0 and is_inside_tree():
			await get_tree().create_timer(retry_delay).timeout
		var result: Dictionary = await transport.call(body)
		if not result.get("ok", false):
			error = String(result.get("error", "request failed"))
			if not result.get("retryable", false):
				break
			continue
		var parsed: Dictionary = Response.from_api_response(result.get("data", {}))
		if parsed["ok"]:
			return parsed
		# A reply that broke character or wasn't valid JSON gets one more try.
		error = String(parsed["error"])
	var npc_name := String(context.get("npc", {}).get("name", "NPC"))
	push_warning("NPC AI: %s fell back to a scripted line (%s)" % [npc_name, error])
	return Response.fallback(error, player_text)


func _http_post(body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = float(settings.get("timeout", Settings.TIMEOUT_SEC))
	add_child(http)
	var headers := PackedStringArray([
		"content-type: application/json",
		"anthropic-version: " + Settings.API_VERSION,
	])
	var key := String(settings.get("api_key", ""))
	if key != "":
		headers.append("x-api-key: " + key)
	# sort_keys off: the reply schema's field order matters (see NarrativeRequest).
	var payload := JSON.stringify(body, "", false)
	var err := http.request(String(settings["api_url"]), headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "retryable": false, "error": "couldn't start the request (error %d)" % err}
	var done: Array = await http.request_completed
	http.queue_free()

	var result: int = done[0]
	var status: int = done[1]
	var text: String = (done[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "retryable": true, "error": "network error (result %d)" % result}
	var data = Response.parse_json_quietly(text)
	if status != 200:
		var message := text.left(200)
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("error")) == TYPE_DICTIONARY:
			message = String(data["error"].get("message", message))
		return {"ok": false, "retryable": status in RETRYABLE_STATUS, "error": "HTTP %d: %s" % [status, message]}
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "retryable": true, "error": "the API's response wasn't JSON"}
	return {"ok": true, "data": data}
