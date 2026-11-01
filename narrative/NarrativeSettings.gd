extends RefCounted
## Settings for the NPC AI. Only the server reads these; clients never need
## them and never receive the key.
##
## Set the key in ONE of two places on the machine that runs the server (the
## host, or the dedicated server):
##   1. Environment variables (these win):
##        ANTHROPIC_API_KEY    turns the AI on
##        HOLLOW_NPC_MODEL     optional, defaults to DEFAULT_MODEL
##        HOLLOW_NPC_API_URL   optional, e.g. a narrative service that adds
##                             the key itself (then no key is needed here)
##   2. user://narrative.cfg (Godot editor: Project > Open User Data Folder):
##        [narrative]
##        api_key="sk-ant-..."
##        model="claude-haiku-5-5"
##
## Never put the key in a project file: res:// files ship inside exported
## games, so every player would get a copy.

const CONFIG_PATH := "user://narrative.cfg"
const DEFAULT_API_URL := "https://api.anthropic.com/v1/messages"
const API_VERSION := "2023-06-01"
## Fastest current Claude model; NPC replies are short and latency matters.
const DEFAULT_MODEL := "claude-haiku-5-5"
## Plenty for one short reply. Billing is for tokens actually produced.
const MAX_TOKENS := 1024
## Low effort keeps replies quick. Set to "" to use the model's default.
const EFFORT := "low"
const TIMEOUT_SEC := 20.0


static func load_settings() -> Dictionary:
	var s := {
		"api_key": "",
		"model": DEFAULT_MODEL,
		"api_url": DEFAULT_API_URL,
		"max_tokens": MAX_TOKENS,
		"effort": EFFORT,
		"timeout": TIMEOUT_SEC,
	}
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_take(s, "api_key", cfg.get_value("narrative", "api_key", ""))
		_take(s, "model", cfg.get_value("narrative", "model", ""))
		_take(s, "api_url", cfg.get_value("narrative", "api_url", ""))
	_take(s, "api_key", OS.get_environment("ANTHROPIC_API_KEY"))
	_take(s, "model", OS.get_environment("HOLLOW_NPC_MODEL"))
	_take(s, "api_url", OS.get_environment("HOLLOW_NPC_API_URL"))
	return s


## On when there's a key, or when requests go to a custom service that
## holds the key itself.
static func is_enabled(s: Dictionary) -> bool:
	return String(s.get("api_key", "")) != "" or String(s.get("api_url", DEFAULT_API_URL)) != DEFAULT_API_URL


static func _take(s: Dictionary, key: String, value) -> void:
	var text := String(value).strip_edges()
	if text != "":
		s[key] = text
