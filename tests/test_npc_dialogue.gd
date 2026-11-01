extends SceneTree
## Headless tests for NPC dialogue: knowledge, trust, memory, prompts, reply
## checking, and the AI client (with a fake transport, so no network or API
## key is needed). Run from the project folder:
##   godot --headless --script res://tests/test_npc_dialogue.gd
## Exits with code 0 if everything passes, 1 otherwise.

const GameSession = preload("res://core/GameSession.gd")
const GamePhase = preload("res://core/GamePhase.gd")
const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")
const NightSystem = preload("res://systems/NightSystem.gd")
const ScenarioLoader = preload("res://scenarios/ScenarioLoader.gd")
const AssassinsMode = preload("res://modes/AssassinsMode.gd")
const CultistsMode = preload("res://modes/CultistsMode.gd")
const NPCManager = preload("res://npc/NPCManager.gd")
const NPCConfig = preload("res://npc/NPCConfig.gd")
const Request = preload("res://narrative/NarrativeRequest.gd")
const Response = preload("res://narrative/NarrativeResponse.gd")
const Settings = preload("res://narrative/NarrativeSettings.gd")
const NarrativeManager = preload("res://narrative/NarrativeManager.gd")

## Old Tobias's trust-2 secret and the hint he shows until then.
const TOBIAS_SECRET := "three gold crowns"
const TOBIAS_HINT := "who the empty grave is for"

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_managers_build()
	_test_find_npc()
	_test_knowledge_gating()
	_test_trust_rules()
	_test_memory_and_transcript()
	_test_hearsay()
	_test_reply_validation()
	_test_api_response_parsing()
	_test_prompt_contents()
	_test_request_body()
	_test_scenario_validation()
	_test_session_npc_rules()
	_test_session_context_is_public_only()
	_test_session_town_news()
	_test_session_records_reply()
	await _test_client()

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Helpers -----------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)


func _inn() -> NPCManager:
	return NPCManager.new(ScenarioLoader.load_scenario(AssassinsMode.new().scenario_path))


func _reply(fields := {}) -> Dictionary:
	var r := {
		"ok": true, "dialogue": "Evening.", "action": "", "emotion": "neutral",
		"approach": "neutral", "memory": "", "rumor": "",
	}
	r.merge(fields, true)
	return r


func _prompt_text(ctx: Dictionary, player_text := "hello") -> String:
	return Request.static_prompt(ctx) + "\n" + Request.dynamic_prompt(ctx) + "\n" + Request.user_message(ctx, player_text)


func _api_text(json_text: String, stop := "end_turn") -> Dictionary:
	return {"content": [{"type": "text", "text": json_text}], "stop_reason": stop}


func _new_game(player_count := 5, fixed_seed := 12345, mode = null):
	var s = GameSession.new(mode, "test", fixed_seed)
	for i in range(player_count):
		s.add_player(i + 1, "Player%d" % (i + 1), i % Enums.CharacterClass.size())
	s.start_game()
	return s


func _first_innocent(s) -> int:
	for p in s.state.players.values():
		if not p.is_traitor():
			return p.id
	return -1


func _advance_to(s, target_phase: int) -> void:
	var guard := 0
	while s.phase.current != target_phase and s.phase.current != GamePhase.Phase.GAME_OVER:
		s.advance_phase()
		guard += 1
		if guard > 50:
			push_error("advance_to got stuck")
			return


# --- NPC state ---------------------------------------------------------------

func _test_managers_build() -> void:
	print("NPCs load from both scenarios")
	for mode in [AssassinsMode.new(), CultistsMode.new()]:
		var scenario := ScenarioLoader.load_scenario(mode.scenario_path)
		var m := NPCManager.new(scenario)
		_check(m.npcs.size() == scenario["npcs"].size(), "%s: every NPC loaded" % mode.id)
	var inn := _inn()
	var listing := JSON.stringify(inn.directory())
	_check(inn.directory().size() == 8, "directory lists the whole cast")
	_check(listing.contains("Mara Thistle") and listing.contains("Common Room"), "directory has names and locations")
	_check(not listing.contains(TOBIAS_SECRET) and not listing.contains("knowledge"), "directory has no secrets")


func _test_find_npc() -> void:
	print("Finding NPCs by name")
	var inn := _inn()
	_check(inn.find("mara")["id"] == "mara", "by id")
	_check(inn.find("Kestrel")["id"] == "sir_kestrel", "by surname, any case")
	_check(inn.find("tobias")["id"] == "old_tobias", "by first name")
	_check(inn.find("duchess")["id"] == "duchess_isolde", "by title")
	_check(inn.find("captain")["id"] == "captain_holt", "by rank")
	_check(not inn.find("gandalf")["ok"], "unknown name is an error")
	_check(not inn.find("  ")["ok"], "blank name is an error")
	var twins := NPCManager.new({"npcs": [
		{"id": "tom_miller", "name": "Tom Miller"},
		{"id": "tom_baker", "name": "Tom Baker"},
	]})
	_check(not twins.find("tom")["ok"], "ambiguous name is an error")
	_check(twins.find("baker")["id"] == "tom_baker", "a unique word still works")


func _test_knowledge_gating() -> void:
	print("Secrets stay out of the prompt until trust allows")
	var inn := _inn()
	var ctx := inn.dialogue_context("old_tobias", "p1", {"name": "Rowan"}, {"day": 1})
	var text := _prompt_text(ctx)
	_check(not text.contains(TOBIAS_SECRET), "a stranger's prompt never contains the secret")
	_check(text.contains(TOBIAS_HINT), "the prompt shows how he hides it")
	_check(text.contains("fresh grave"), "public knowledge is shared")

	var tobias = inn.get_npc("old_tobias")
	tobias.change_trust("p1", 1)
	tobias.start_day()
	tobias.change_trust("p1", 1)
	ctx = inn.dialogue_context("old_tobias", "p1", {"name": "Rowan"}, {"day": 2})
	text = _prompt_text(ctx)
	_check(text.contains(TOBIAS_SECRET), "at trust 2 the secret is shareable")
	_check(not text.contains(TOBIAS_HINT), "the hint goes once the secret is shareable")

	var other := _prompt_text(inn.dialogue_context("old_tobias", "p2", {"name": "Matt"}, {"day": 2}))
	_check(not other.contains(TOBIAS_SECRET), "trust is per player")

	tobias.learn("Saw a lantern in the crypt on night 2.", 1, "Something you saw last night spooked you.")
	var fresh := _prompt_text(inn.dialogue_context("old_tobias", "p3", {"name": "Wren"}, {"day": 2}))
	_check(not fresh.contains("lantern in the crypt") and fresh.contains("spooked you"), "knowledge added during play is gated too")


func _test_trust_rules() -> void:
	print("Trust follows the rules, not the AI")
	var inn := _inn()
	var mara = inn.get_npc("mara")
	_check(mara.change_trust("a", mara.reaction_to("friendly")) == 1, "friendly raises trust")
	_check(mara.change_trust("a", mara.reaction_to("friendly")) == 0, "only +%d per NPC per day" % NPCConfig.MAX_TRUST_GAIN_PER_DAY)
	mara.start_day()
	_check(mara.change_trust("a", 1) == 1, "can gain again the next day")
	_check(mara.change_trust("a", mara.reaction_to("threat")) == -2, "threats cost trust")
	for i in range(5):
		mara.change_trust("a", -2)
	_check(mara.get_trust("a") == NPCConfig.MIN_TRUST, "trust bottoms out at %d" % NPCConfig.MIN_TRUST)

	var kestrel = inn.get_npc("sir_kestrel")
	_check(kestrel.reaction_to("bribe") == -2, "Sir Kestrel hates bribes (scenario override)")
	_check(inn.get_npc("pell").reaction_to("bribe") == 1, "Pell likes them")
	_check(kestrel.reaction_to("neutral") == 0, "unlisted approaches use the defaults")

	inn.start_day(1)
	var r: Dictionary = inn.apply_reply("pell", "a", "Rowan", "Here's a coin for you.", _reply({"approach": "bribe"}))
	_check(r["trust_change"] == 1 and r["trust"] == 1, "apply_reply turns the approach label into trust")
	var r2: Dictionary = inn.apply_reply("pell", "b", "Matt", "hi", _reply({"approach": "bribe", "fallback": true}))
	_check(r2["trust_change"] == 0, "fallback replies never change trust")


func _test_memory_and_transcript() -> void:
	print("Memory and today's conversation")
	var inn := _inn()
	inn.start_day(1)
	inn.apply_reply("mara", "a", "Rowan", "Who has the corner suite?", _reply({"dialogue": "Her ladyship, love.", "memory": "Asked about the corner suite."}))
	var ctx_a := inn.dialogue_context("mara", "a", {"name": "Rowan"}, {"day": 1})
	var ctx_b := inn.dialogue_context("mara", "b", {"name": "Matt"}, {"day": 1})
	_check(ctx_a["memories"].size() == 1 and ctx_a["memories"][0]["day"] == 1, "the NPC remembers, with the day")
	_check(ctx_a["transcript"].size() == 2, "today's exchange is in the transcript")
	_check(ctx_b["memories"].is_empty() and ctx_b["transcript"].is_empty(), "one player's chat stays private from another")
	_check(_prompt_text(ctx_a).contains("Asked about the corner suite."), "memories reach the prompt")

	inn.apply_reply("mara", "a", "Rowan", "Who has the corner suite, again?", _reply({"memory": "Asked about the corner suite."}))
	ctx_a = inn.dialogue_context("mara", "a", {"name": "Rowan"}, {"day": 1})
	_check(ctx_a["memories"].size() == 1, "the same memory twice in a row is stored once")

	inn.start_day(2)
	ctx_a = inn.dialogue_context("mara", "a", {"name": "Rowan"}, {"day": 2})
	_check(ctx_a["transcript"].is_empty() and ctx_a["memories"].size() == 1, "a new day clears the transcript but keeps memories")

	for i in range(NPCConfig.MAX_MEMORIES_PER_PLAYER + 4):
		inn.apply_reply("mara", "a", "Rowan", "q%d" % i, _reply({"memory": "memory %d" % i}))
	ctx_a = inn.dialogue_context("mara", "a", {"name": "Rowan"}, {"day": 2})
	_check(ctx_a["memories"].size() == NPCConfig.MAX_MEMORIES_PER_PLAYER, "memories are capped")
	_check(ctx_a["memories"][-1]["text"] == "memory %d" % (NPCConfig.MAX_MEMORIES_PER_PLAYER + 3), "the newest memories are kept")
	_check(ctx_a["transcript"].size() == NPCConfig.MAX_TRANSCRIPT_LINES, "the transcript is capped")


func _test_hearsay() -> void:
	print("Hearsay spreads between players, attributed and unverified")
	var inn := _inn()
	inn.start_day(3)
	inn.apply_reply("wenna", "a", "Rowan", "Matt was in the stables at midnight!", _reply({"rumor": "Matt was in the stables at midnight."}))
	var ctx_b := inn.dialogue_context("wenna", "b", {"name": "Wren"}, {"day": 3})
	_check(ctx_b["hearsay"].size() == 1 and ctx_b["hearsay"][0]["from"] == "Rowan", "another player hears it, with who said it")
	var text := _prompt_text(ctx_b)
	_check(text.contains("On day 3, Rowan told you: Matt was in the stables at midnight."), "hearsay reaches the prompt")
	_check(text.contains("could be lies"), "and is marked as unverified")
	_check(inn.dialogue_context("mara", "b", {"name": "Wren"}, {"day": 3})["hearsay"].is_empty(), "only the NPC who heard it knows it")
	inn.apply_reply("wenna", "a", "Rowan", "nice bread", _reply({"rumor": ""}))
	_check(inn.get_npc("wenna").hearsay().size() == 1, "no claim, no hearsay")
	for i in range(NPCConfig.MAX_HEARSAY + 3):
		inn.apply_reply("wenna", "a", "Rowan", "x", _reply({"rumor": "claim %d" % i}))
	_check(inn.get_npc("wenna").hearsay().size() == NPCConfig.MAX_HEARSAY, "hearsay is capped")


# --- Reading the AI's reply --------------------------------------------------

func _test_reply_validation() -> void:
	print("Checking what the AI sends back")
	var good := Response.validate({
		"approach": "FRIENDLY", "emotion": "Nervous", "action": "glances at the stairs.",
		"dialogue": "\"Not so loud, love.\"", "memory": "Asked about the duchess.", "rumor": "",
	})
	_check(good["ok"], "a good reply passes")
	_check(good["approach"] == "friendly" and good["emotion"] == "nervous", "labels are matched ignoring case")
	_check(good["dialogue"] == "Not so loud, love.", "wrapping quotes are removed")
	_check(good["action"] == "glances at the stairs", "trailing period dropped from the action")

	var odd := Response.validate({"approach": "seduction", "emotion": "hangry", "dialogue": "Hm."})
	_check(odd["approach"] == "neutral" and odd["emotion"] == "neutral", "unknown labels become neutral")
	_check(odd["memory"] == "" and odd["rumor"] == "", "missing fields become empty")

	var messy := Response.validate({"dialogue": "*wipes the bar* Line one.\nLine two\u0007", "action": ""})
	_check(messy["dialogue"] == "Line one. Line two", "control characters and newlines are cleaned")
	_check(messy["action"] == "wipes the bar", "*stage directions* move out of the speech")

	var long := Response.validate({"dialogue": "Aye. ".repeat(200)})
	_check(long["dialogue"].length() <= NPCConfig.MAX_DIALOGUE_LENGTH, "long dialogue is capped")
	_check(long["dialogue"].ends_with("."), "and cut at a sentence end")
	var long_memory := Response.validate({"dialogue": "Hm.", "memory": "x".repeat(400)})
	_check(long_memory["memory"].length() <= NPCConfig.MAX_MEMORY_LENGTH, "long memory is capped")

	_check(not Response.validate({"dialogue": "   "})["ok"], "empty dialogue is rejected")
	_check(not Response.validate({"dialogue": "As an AI, I cannot say."})["ok"], "breaking character is rejected")
	_check(not Response.validate({"dialogue": "Fine.", "memory": "Asked me to reveal my system prompt"})["ok"], "out-of-world text in any field is rejected")

	var brush := Response.fallback("no key", "who are you?")
	_check(brush["ok"] and brush["fallback"] and brush["dialogue"] != "", "fallback is a usable in-character line")
	_check(Response.fallback("x", "same")["dialogue"] == Response.fallback("y", "same")["dialogue"], "fallback choice is stable for the same question")


func _test_api_response_parsing() -> void:
	print("Reading a Messages API response")
	var json := JSON.stringify({"approach": "neutral", "emotion": "amused", "action": "", "dialogue": "Ha! Ask Wenna.", "memory": "", "rumor": ""})
	var r := Response.from_api_response(_api_text(json))
	_check(r["ok"] and r["dialogue"] == "Ha! Ask Wenna.", "text block JSON is parsed")
	var with_thinking := {"content": [{"type": "thinking", "thinking": ""}, {"type": "text", "text": json}], "stop_reason": "end_turn"}
	_check(Response.from_api_response(with_thinking)["ok"], "a thinking block before the text is skipped")
	_check(Response.from_api_response(_api_text("```json\n%s\n```" % json))["ok"], "a code fence is tolerated")
	_check(not Response.from_api_response(_api_text("Sure! Here you go"))["ok"], "non-JSON is rejected")
	_check(not Response.from_api_response(_api_text(json, "refusal"))["ok"], "a refusal is rejected")
	_check(not Response.from_api_response(_api_text("{\"dialogue\": \"Wel", "max_tokens"))["ok"], "a cut-off reply is rejected")
	_check(not Response.from_api_response({"content": []})["ok"], "no content is rejected")


# --- Building the request ----------------------------------------------------

func _test_prompt_contents() -> void:
	print("What the AI is told")
	var inn := _inn()
	var ctx := inn.dialogue_context("mara", "a", {"name": "Rowan", "class": "Rogue", "effects": ["Drugged"]}, {
		"day": 2, "tension": 0.6,
		"news": [{"day": 1, "type": "sabotage", "player": "Matt", "effect": "Drugged"}],
	})
	var static_text := Request.static_prompt(ctx)
	var dynamic_text := Request.dynamic_prompt(ctx)
	_check(static_text.contains("You are Mara Thistle, innkeeper"), "who the NPC is")
	_check(static_text.contains("Hollowmere") and static_text.contains("duchess"), "the setting")
	_check(static_text.contains("Kitchen and Cellar"), "the places in town")
	_check(static_text.contains("Old Tobias, gravedigger"), "the rest of the cast")
	_check(static_text.contains("Calls everyone 'love'"), "how the NPC talks")
	_check(static_text.contains("Never invent evidence"), "the no-invented-evidence rule")
	_check(static_text.contains("Stay inside the world"), "the stay-in-character rule")
	_check(not static_text.contains("Rowan"), "the cached part has nothing about the player")
	_check(dynamic_text.contains("It's day 2.") and dynamic_text.contains("Fear is spreading"), "the day and the mood")
	_check(dynamic_text.contains("someone got to Matt in the night: Drugged."), "public news as gossip")
	_check(dynamic_text.contains("Rowan, a rogue") and dynamic_text.contains("Visible condition: Drugged."), "the player's visible state")
	_check(dynamic_text.contains("They're a stranger to you."), "how the NPC feels about them")
	_check(Request.user_message(ctx, "Any news?") == "Rowan says: \"Any news?\"", "the player's line")

	var exposed := Request.dynamic_prompt(inn.dialogue_context("mara", "z", {"name": "Zed", "unmasked": true, "unmasked_as": "Assassins"}, {"day": 3}))
	_check(exposed.contains("exposed at council as one of the Assassins"), "NPCs know who was publicly unmasked")
	_check(Request.tension_line(-1.0) == "", "hidden plot progress means no mood line")


func _test_request_body() -> void:
	print("The API request")
	var ctx := _inn().dialogue_context("pell", "a", {"name": "Rowan"}, {"day": 1})
	var haiku := Request.build_body(ctx, "hi", {"model": "claude-haiku-5-5", "max_tokens": 1024, "effort": "low"})
	_check(haiku["model"] == "claude-haiku-5-5" and haiku["max_tokens"] == 1024, "model and max_tokens")
	_check(haiku["system"].size() == 2 and haiku["system"][0].has("cache_control"), "static prompt is marked for caching")
	_check(not haiku["system"][1].has("cache_control"), "the per-player part isn't cached")
	_check(haiku["output_config"]["format"]["type"] == "json_schema", "structured JSON output")
	_check(haiku["output_config"]["effort"] == "low", "low effort for speed")
	_check(haiku["thinking"] == {"type": "disabled"}, "thinking off on Haiku")
	_check(not haiku.has("temperature") and not haiku.has("top_p"), "no sampling parameters")
	var sonnet := Request.build_body(ctx, "hi", {"model": "claude-sonnet-5-5", "max_tokens": 1024, "effort": ""})
	_check(not sonnet.has("thinking"), "other models keep their thinking default")
	_check(not sonnet["output_config"].has("effort"), "empty effort is left out")

	var schema := Request.reply_schema()
	_check(schema["additionalProperties"] == false, "schema forbids extra fields")
	_check(schema["required"].size() == schema["properties"].size(), "every field is required")
	_check(schema["properties"]["approach"]["enum"] == NPCConfig.APPROACHES, "approach labels match the rules")


func _test_scenario_validation() -> void:
	print("Scenario checks for NPC fields")
	var base := {"locations": [{"id": "here", "connections": []}]}
	var bad := base.duplicate(true)
	bad["npcs"] = [{
		"id": "x", "location": "here",
		"knowledge": [{"text": ""}, {"text": "ok", "share_at_trust": 9}],
		"reactions": {"hug": 1, "threat": -10},
	}]
	var problems := ScenarioLoader.validate(bad)
	_check(problems.size() == 4, "empty text, trust range, unknown approach and reaction range are all caught (%d found)" % problems.size())
	var fine := base.duplicate(true)
	fine["npcs"] = [{"id": "y", "location": "here"}]
	_check(ScenarioLoader.validate(fine).is_empty(), "NPCs without AI fields are still valid")


# --- GameSession -------------------------------------------------------------

func _test_session_npc_rules() -> void:
	print("Talking to NPCs in a game: phases and action points")
	var s = _new_game()
	var p := _first_innocent(s)
	_check(not s.request_npc_message(p, "mara")["ok"], "can't question NPCs in MORNING")
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	_check(not s.request_npc_message(p, "nobody")["ok"], "unknown NPC rejected")
	_check(not s.request_npc_message(999, "mara")["ok"], "unknown player rejected")

	var first: Dictionary = s.request_npc_message(p, "mara")
	_check(first["ok"] and first["opened"], "first message opens a conversation")
	_check(s.state.players[p].action_points == Config.ACTION_POINTS_PER_DAY - 1, "opening costs an action point")
	_check(first["messages_left"] == NPCConfig.MESSAGES_PER_CONVERSATION - 1, "and gives %d messages" % NPCConfig.MESSAGES_PER_CONVERSATION)
	for i in range(NPCConfig.MESSAGES_PER_CONVERSATION - 1):
		s.request_npc_message(p, "mara")
	_check(s.state.players[p].action_points == Config.ACTION_POINTS_PER_DAY - 1, "follow-up messages are free")
	var again: Dictionary = s.request_npc_message(p, "mara")
	_check(again["opened"] and s.state.players[p].action_points == Config.ACTION_POINTS_PER_DAY - 2, "a used-up conversation costs a new action point")

	s.request_npc_message(p, "pell")
	_check(s.state.players[p].action_points == 0, "each NPC is its own conversation")
	_check(not s.request_npc_message(p, "wenna")["ok"], "no action points, no new conversation")
	_check(s.request_npc_message(p, "pell")["ok"], "an open conversation still works at 0 action points")

	_advance_to(s, GamePhase.Phase.MORNING)
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	_check(s.request_npc_message(p, "pell")["opened"], "conversations close overnight")


func _test_session_context_is_public_only() -> void:
	print("NPC context never reveals roles")
	var s = _new_game(7)
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	var traitor: int = s.state.traitor_ids()[0]
	var innocent := _first_innocent(s)
	var ctx_t: Dictionary = s.npc_dialogue_context(traitor, "mara")
	var ctx_i: Dictionary = s.npc_dialogue_context(innocent, "mara")
	_check(not ctx_t.is_empty() and not ctx_i.is_empty(), "context builds for both")
	var text_t := JSON.stringify(ctx_t)
	_check(not text_t.contains("\"role\"") and not text_t.contains("Assassin\""), "no role in a traitor's context")
	_check(not text_t.contains("duchess_isolde"), "no target id in the context")
	ctx_t["player"]["name"] = "X"
	ctx_t["player"]["class"] = "X"
	ctx_i["player"]["name"] = "X"
	ctx_i["player"]["class"] = "X"
	_check(JSON.stringify(ctx_t) == JSON.stringify(ctx_i), "a traitor's context is identical to an innocent's apart from name and class")
	_check(s.npc_dialogue_context(traitor, "nobody").is_empty(), "unknown NPC gives no context")


func _test_session_town_news() -> void:
	print("Public events become town gossip")
	var s = _new_game(5)
	var traitor: int = s.state.traitor_ids()[0]
	var victim := _first_innocent(s)
	_advance_to(s, GamePhase.Phase.NIGHT)
	s.submit_traitor_action(traitor, NightSystem.TraitorAction.SABOTAGE, victim, Enums.StatusEffect.WEARY)
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	var ctx: Dictionary = s.npc_dialogue_context(victim, "wenna")
	var news: Array = ctx["town"]["news"]
	_check(news.size() == 1 and news[0]["type"] == "sabotage", "a sabotage becomes news")
	_check(news[0]["player"] == "Player%d" % victim and news[0]["effect"] == "Drugged", "with the victim's name and the effect")
	_check(not JSON.stringify(news).contains("Player%d\"" % traitor) or traitor == victim, "but not who did it")
	_check(ctx["player"]["effects"] == ["Drugged"], "the victim looks drugged to NPCs")
	_check(ctx["town"]["tension"] == 0.0, "sabotage instead of advancing leaves the mood calm")

	_advance_to(s, GamePhase.Phase.COUNCIL)
	for pid in s.state.players.keys():
		if pid != traitor:
			s.cast_vote(pid, traitor)
	s.advance_phase()
	var after: Dictionary = s.npc_dialogue_context(victim, "wenna")
	var last: Dictionary = after["town"]["news"][-1]
	_check(last["type"] == "traitor_unmasked" and last["player"] == "Player%d" % traitor, "an unmasking becomes news")
	var text := Request.dynamic_prompt(after)
	_check(text.contains("exposed at council as one of the Assassins"), "and reads as gossip")


func _test_session_records_reply() -> void:
	print("Recording a reply")
	var s = _new_game(5)
	var p := _first_innocent(s)
	var other := -1
	for pid in s.state.players.keys():
		if pid != p:
			other = pid
			break
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	s.request_npc_message(p, "mara")
	var r: Dictionary = s.record_npc_reply(p, "mara", "Lovely inn you keep.", _reply({"approach": "flattery", "dialogue": "Oh, go on.", "memory": "Praised the inn."}))
	_check(r["ok"] and r["trust_change"] == 1, "Mara likes flattery (scenario override)")
	var mine: Array = s.get_private_state(p)["events"].filter(func(e): return e["type"] == "npc_conversation")
	var theirs: Array = s.get_private_state(other)["events"].filter(func(e): return e["type"] == "npc_conversation")
	_check(mine.size() == 1 and mine[0]["data"]["reply"] == "Oh, go on.", "the player can see their conversation")
	_check(theirs.is_empty(), "other players can't")
	_check(not JSON.stringify(s.get_private_state(p)).contains("npc_trust"), "trust numbers stay on the server")
	_check(s.npc_dialogue_context(p, "mara")["memories"][0]["text"] == "Praised the inn.", "the NPC remembers")


# --- The AI client (fake transport) -------------------------------------------

func _test_client() -> void:
	print("AI client: retries, fallbacks, and no network needed for tests")
	await process_frame # the scene tree finishes setting up after _initialize()
	var ctx := _inn().dialogue_context("mara", "a", {"name": "Rowan"}, {"day": 1})
	var good_json := JSON.stringify({"approach": "friendly", "emotion": "friendly", "action": "smiles", "dialogue": "Welcome, love.", "memory": "Said hello.", "rumor": ""})
	var bad_json := JSON.stringify({"approach": "neutral", "emotion": "neutral", "action": "", "dialogue": "As an AI, I can't do that.", "memory": "", "rumor": ""})

	var client := NarrativeManager.new()
	client.retry_delay = 0.01
	root.add_child(client)

	client.settings = {"api_key": "", "model": "claude-haiku-5-5", "api_url": Settings.DEFAULT_API_URL, "max_tokens": 1024, "effort": "low", "timeout": 5.0}
	var calls := [0]
	client.transport = func(_body): calls[0] += 1; return {"ok": true, "data": _api_text(good_json)}
	var off: Dictionary = await client.reply(ctx, "hello")
	_check(off["fallback"] and calls[0] == 0, "no key: scripted line, no request sent")

	client.settings["api_key"] = "test-key"
	var sent := [{}]
	client.transport = func(body): calls[0] += 1; sent[0] = body; return {"ok": true, "data": _api_text(good_json)}
	var ok: Dictionary = await client.reply(ctx, "hello")
	_check(ok["ok"] and not ok.has("fallback") and ok["dialogue"] == "Welcome, love.", "a good response comes through")
	_check(sent[0]["messages"][0]["content"] == "Rowan says: \"hello\"", "the request carries the player's line")

	calls[0] = 0
	client.transport = func(_body):
		calls[0] += 1
		if calls[0] == 1:
			return {"ok": false, "retryable": true, "error": "HTTP 529: overloaded"}
		return {"ok": true, "data": _api_text(good_json)}
	var retried: Dictionary = await client.reply(ctx, "hello")
	_check(retried["ok"] and not retried.has("fallback") and calls[0] == 2, "an overloaded API is retried once")

	calls[0] = 0
	client.transport = func(_body): calls[0] += 1; return {"ok": false, "retryable": false, "error": "HTTP 401: invalid x-api-key"}
	var denied: Dictionary = await client.reply(ctx, "hello")
	_check(denied["fallback"] and calls[0] == 1, "a bad key isn't retried and falls back")
	_check(denied["error"].contains("401"), "the error is kept for the log")

	calls[0] = 0
	client.transport = func(_body):
		calls[0] += 1
		return {"ok": true, "data": _api_text(bad_json if calls[0] == 1 else good_json)}
	var second_try: Dictionary = await client.reply(ctx, "hello")
	_check(second_try["ok"] and not second_try.has("fallback") and calls[0] == 2, "an out-of-character reply gets one more try")

	calls[0] = 0
	client.transport = func(_body): calls[0] += 1; return {"ok": true, "data": _api_text(bad_json)}
	var gave_up: Dictionary = await client.reply(ctx, "hello")
	_check(gave_up["fallback"] and calls[0] == NarrativeManager.MAX_ATTEMPTS, "and falls back if it happens again")

	client.queue_free()
