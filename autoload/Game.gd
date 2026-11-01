extends Node
## Runs the game over the network. Autoloaded as "Game".
##
## Server: owns the GameSession. Players send requests ("start", "next
## phase", "vote for X", "sabotage Y"); the server checks them, applies them
## to the session, then sends every player their own filtered view of the
## game. Nobody ever receives another player's secrets.
##
## Client: keeps the latest view in `state`, turns new events into readable
## lines for the chat log, and emits state_changed for the UI.

const GameSessionScript = preload("res://core/GameSession.gd")
const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")
const EventText = preload("res://game/EventText.gd")

const SERVER_ID := 1

## The latest view of the game for this player.
signal state_changed(view: Dictionary)
## A line of narration for the chat log ("Day 2 dawns...").
signal game_log(text: String)

## Client: our current view. {} until the server sends one.
var state := {}

## Server: the running session, or null in the lobby.
var _session = null
var _game_counter := 0

## Client: narration bookkeeping.
var _seen_events := 0
var _last_phase := ""
var _last_session_id := ""


func _ready() -> void:
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.disconnected.connect(_on_disconnected)


func in_game() -> bool:
	return state.get("in_game", false)


## Players needed to start a game. Lower in the editor so you can test with
## a couple of windows.
static func min_players() -> int:
	return Config.TEST_MIN_PLAYERS if OS.is_debug_build() else Config.MIN_PLAYERS


# --- Requests (called by the UI) -----------------------------------------------

func request_start() -> void:
	_ask("_rpc_req_start", "_server_start", [])


func request_advance() -> void:
	_ask("_rpc_req_advance", "_server_advance", [])


func request_vote(target_id: int) -> void:
	_ask("_rpc_req_vote", "_server_vote", [target_id])


func request_traitor_action(action: int, target_id: int, effect: int) -> void:
	_ask("_rpc_req_traitor_action", "_server_traitor_action", [action, target_id, effect])


func request_end() -> void:
	_ask("_rpc_req_end", "_server_end", [])


## Sends a request to the server, or handles it directly if we are the host.
func _ask(rpc_method: String, server_method: String, args: Array) -> void:
	if not Network.is_in_room():
		return
	if multiplayer.is_server():
		callv(server_method, [SERVER_ID] + args)
	else:
		callv("rpc_id", [SERVER_ID, rpc_method] + args)


# --- Client -> server RPCs -------------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_req_start() -> void:
	if multiplayer.is_server():
		_server_start(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _rpc_req_advance() -> void:
	if multiplayer.is_server():
		_server_advance(multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _rpc_req_vote(target_id: int) -> void:
	if multiplayer.is_server():
		_server_vote(multiplayer.get_remote_sender_id(), target_id)


@rpc("any_peer", "reliable")
func _rpc_req_traitor_action(action: int, target_id: int, effect: int) -> void:
	if multiplayer.is_server():
		_server_traitor_action(multiplayer.get_remote_sender_id(), action, target_id, effect)


@rpc("any_peer", "reliable")
func _rpc_req_end() -> void:
	if multiplayer.is_server():
		_server_end(multiplayer.get_remote_sender_id())


# --- Server -> client RPCs -------------------------------------------------------

@rpc("authority", "reliable")
func _rpc_state(view: Dictionary) -> void:
	_apply_state(view)


# --- Server logic ------------------------------------------------------------------

func _server_start(peer_id: int) -> void:
	if not _require_leader(peer_id, "start the game"):
		return
	if _session != null:
		Network.notify(peer_id, "A game is already running.")
		return
	var ids: Array = Network.player_ids()
	if ids.size() < min_players():
		Network.notify(peer_id, "Need at least %d players to start." % min_players())
		return

	_game_counter += 1
	var session = GameSessionScript.new(null, "game-%d" % _game_counter)
	session.min_players = min_players()
	# Hand out classes so everyone gets a different one where possible.
	var classes := range(Enums.CharacterClass.size())
	classes.shuffle()
	for i in ids.size():
		session.add_player(ids[i], Network.player_name(ids[i]), classes[i % classes.size()])
	var result: Dictionary = session.start_game()
	if not result["ok"]:
		Network.notify(peer_id, result["error"])
		return

	_session = session
	Network.join_locked_reason = "A game is in progress. Try again when it's over."
	_push_all()


func _server_advance(peer_id: int) -> void:
	if not _require_leader(peer_id, "move to the next phase") or not _require_game(peer_id):
		return
	var result: Dictionary = _session.advance_phase()
	if not result["ok"]:
		Network.notify(peer_id, result["error"])
		return
	_push_all()


func _server_vote(peer_id: int, target_id: int) -> void:
	if not _require_game(peer_id):
		return
	var result: Dictionary = _session.cast_vote(peer_id, target_id)
	if not result["ok"]:
		Network.notify(peer_id, result["error"])
		return
	_push_all() # Everyone sees the vote count go up.


func _server_traitor_action(peer_id: int, action: int, target_id: int, effect: int) -> void:
	if not _require_game(peer_id):
		return
	var result: Dictionary = _session.submit_traitor_action(peer_id, action, target_id, effect)
	if not result["ok"]:
		Network.notify(peer_id, result["error"])
		return
	_push_all() # Allies see the updated plan.


func _server_end(peer_id: int) -> void:
	if not _require_leader(peer_id, "end the game") or not _require_game(peer_id):
		return
	_end_session()
	_push_all()


func _end_session() -> void:
	_session = null
	Network.join_locked_reason = ""


## Sends every joined player their own view.
func _push_all() -> void:
	for pid in Network.player_ids():
		_send_to(pid, "_rpc_state", [_view_for(pid)])


## What one player is allowed to see right now.
func _view_for(peer_id: int) -> Dictionary:
	var view := {}
	if _session == null:
		view = {
			"in_game": false,
			"player_count": Network.player_ids().size(),
			"min_players": min_players(),
		}
	elif _session.state.players.has(peer_id):
		view = _session.get_private_state(peer_id)
		view["in_game"] = true
	else:
		view = _session.get_public_state()
		view["in_game"] = true
	var leader := Network.leader_id()
	view["my_id"] = peer_id
	view["leader_id"] = leader
	view["leader_name"] = Network.player_name(leader)
	view["is_leader"] = peer_id == leader
	return view


func _require_leader(peer_id: int, doing: String) -> bool:
	if peer_id == Network.leader_id():
		return true
	Network.notify(peer_id, "Only %s (the room leader) can %s." % [
		Network.player_name(Network.leader_id()), doing])
	return false


func _require_game(peer_id: int) -> bool:
	if _session != null:
		return true
	Network.notify(peer_id, "No game is running.")
	return false


func _on_player_joined(_peer_id: int) -> void:
	_push_all()


func _on_player_left(_peer_id: int) -> void:
	if _session != null and Network.player_ids().is_empty():
		_end_session()
	_push_all() # Also tells everyone if the leader changed.


## Delivers an RPC to one player, or calls it directly if that's us.
func _send_to(peer_id: int, method: String, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)


# --- Chat rules (asked by Network on the server) ---------------------------------

## Why this player can't send this kind of message right now, or "".
func chat_block_reason(_peer_id: int, kind: String) -> String:
	if _session == null:
		return ""
	if _session.state.is_over():
		return ""
	if _session.phase.current == GameSessionScript.Phase.NIGHT and kind != "team":
		return "It's night and the inn is asleep. Chat opens again in the morning."
	return ""


## Who receives a /a message from this player: their allies (including them),
## or [] if they have none.
func team_recipients(peer_id: int) -> Array:
	if _session == null:
		return []
	var me = _session.state.players.get(peer_id)
	if me == null or not me.is_traitor():
		return []
	return _session.state.traitor_ids()


# --- NPC conversations (asked by Network on the server) ----------------------------
# Network runs the conversation (it owns the AI and the chat RPCs); the game
# decides whether a message is allowed and records what came of it.

## The running game's townsfolk, or null in the lobby (where Network lets
## everyone chat with its own cast for free).
func npc_manager():
	return _session.npcs if _session != null else null


## Applies the game's rules to one message to an NPC: the right phase, and an
## action point to open a conversation. {"ok": true} in the lobby.
func begin_npc_message(peer_id: int, npc_id: String) -> Dictionary:
	if _session == null:
		return {"ok": true}
	if not _session.state.players.has(peer_id):
		return {"ok": false, "error": "You're watching this game, so you can't question the townsfolk."}
	var result: Dictionary = _session.request_npc_message(peer_id, npc_id)
	if result["ok"] and result.get("opened", false):
		_send_to(peer_id, "_rpc_state", [_view_for(peer_id)]) # shows the spent action point
	return result


## What the AI may know for this NPC's reply, built from the game's public state.
func npc_context(peer_id: int, npc_id: String) -> Dictionary:
	return _session.npc_dialogue_context(peer_id, npc_id) if _session != null else {}


## Records a validated reply in the game: NPC memory, trust, and the event log.
func finish_npc_message(peer_id: int, npc_id: String, player_text: String, reply: Dictionary) -> void:
	if _session != null:
		_session.record_npc_reply(peer_id, npc_id, player_text, reply)


# --- Client logic ------------------------------------------------------------------

func _apply_state(view: Dictionary) -> void:
	var was_in_game := in_game()
	state = view

	if view.get("in_game", false):
		var session_id: String = view.get("session_id", "")
		if session_id != _last_session_id:
			_last_session_id = session_id
			_seen_events = 0
			_last_phase = ""
			game_log.emit("A new game begins at %s." % view.get("setting", {}).get("name", "the inn"))

		var events: Array = view.get("events", [])
		for i in range(_seen_events, events.size()):
			var line := EventText.format_event(events[i], view)
			if line != "":
				game_log.emit(line)
		_seen_events = events.size()

		var phase: String = view.get("phase", "")
		if phase != _last_phase:
			_last_phase = phase
			var hint := EventText.phase_text(phase)
			if hint != "":
				game_log.emit(hint)
	elif was_in_game:
		_last_session_id = ""
		game_log.emit("The game has ended. Back in the common room.")

	state_changed.emit(view)


func _on_disconnected(_reason: String) -> void:
	_end_session()
	state = {}
	_seen_events = 0
	_last_phase = ""
	_last_session_id = ""
	state_changed.emit(state)
