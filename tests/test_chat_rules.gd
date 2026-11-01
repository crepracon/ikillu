extends SceneTree
## Headless tests for chat validation rules. Run from the project folder:
##   godot --headless --script res://tests/test_chat_rules.gd

const ChatRules = preload("res://chat/ChatRules.gd")
const RateLimiter = preload("res://chat/RateLimiter.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_names()
	_test_unique_names()
	_test_messages()
	_test_parse()
	_test_escape()
	_test_rate_limiter()

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)


func _test_names() -> void:
	print("Names")
	_check(ChatRules.clean_name("Chris") == "Chris", "plain name kept")
	_check(ChatRules.clean_name("  Sir Kestrel!  ") == "SirKestrel", "spaces and symbols removed")
	_check(ChatRules.clean_name("[b]bad[/b]") == "bbadb", "bbcode brackets removed")
	_check(ChatRules.clean_name("!!!") == "", "nothing usable gives empty name")
	_check(ChatRules.clean_name("a".repeat(50)).length() == ChatRules.MAX_NAME_LENGTH, "name length capped")


func _test_unique_names() -> void:
	print("Unique names")
	_check(ChatRules.unique_name("Chris", ["Matt"]) == "Chris", "free name unchanged")
	_check(ChatRules.unique_name("chris", ["Chris"]) == "chris2", "taken name gets a number (case-insensitive)")
	_check(ChatRules.unique_name("Chris", ["Chris", "Chris2"]) == "Chris3", "skips numbers already taken")


func _test_messages() -> void:
	print("Messages")
	_check(ChatRules.clean_message("  hello  ") == "hello", "whitespace trimmed")
	_check(ChatRules.clean_message("a\nb\tc") == "abc", "control characters removed")
	_check(ChatRules.clean_message("x".repeat(1000)).length() == ChatRules.MAX_MESSAGE_LENGTH, "message length capped")


func _test_parse() -> void:
	print("Commands")
	_check(ChatRules.parse("   ")["type"] == "empty", "blank message is empty")
	var say := ChatRules.parse("Who ordered the stew?")
	_check(say["type"] == "say" and say["text"] == "Who ordered the stew?", "plain text is say")
	var w := ChatRules.parse("/w Matt meet me in the stables")
	_check(w["type"] == "whisper", "/w is a whisper")
	_check(w.get("target") == "Matt", "whisper target parsed")
	_check(w.get("text") == "meet me in the stables", "whisper text parsed")
	_check(ChatRules.parse("/whisper Matt hi")["type"] == "whisper", "/whisper also works")
	_check(ChatRules.parse("/w Matt")["type"] == "error", "whisper without text is an error")
	_check(ChatRules.parse("/w")["type"] == "error", "bare /w is an error")
	_check(ChatRules.parse("/dance")["type"] == "error", "unknown command is an error")
	var team := ChatRules.parse("/a she's in the corner suite")
	_check(team["type"] == "team" and team.get("text") == "she's in the corner suite", "/a is ally chat")
	_check(ChatRules.parse("/a")["type"] == "error", "/a without text is an error")
	_check(ChatRules.unknown_command_text("a") == ChatRules.parse("/zzz")["text"].replace("zzz", "a"), "/a rejection looks like any unknown command")


func _test_escape() -> void:
	print("BBCode escaping")
	_check(ChatRules.escape_bbcode("[img]x[/img]") == "[lb]img]x[lb]/img]", "brackets escaped")
	_check(ChatRules.escape_bbcode("no tags") == "no tags", "plain text unchanged")


func _test_rate_limiter() -> void:
	print("Rate limiter")
	var limiter := RateLimiter.new(3, 1000)
	_check(limiter.allow(7, 0), "1st message allowed")
	_check(limiter.allow(7, 100), "2nd message allowed")
	_check(limiter.allow(7, 200), "3rd message allowed")
	_check(not limiter.allow(7, 300), "4th message inside the window blocked")
	_check(limiter.allow(8, 300), "other players aren't affected")
	_check(limiter.allow(7, 1050), "allowed again once the window passes")
	limiter.forget(7)
	_check(limiter.allow(7, 1060), "forget clears history")
