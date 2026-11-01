extends Node
## Multiplayer connection and the chat room. Autoloaded as "Network", so it
## lives at /root/Network on every peer (RPCs need the same node path
## everywhere).
##
## The server is authoritative. Clients only send requests ("I'd like this
## name", "I said this"); the server validates them and decides what each
## player receives. Server-to-client messages only go to players who have
## joined, never to a peer that has merely connected.
##
## Three ways to run:
##   Host:      a player clicks Host. They're the server and a player.
##   Join:      a player connects to a host or server by address.
##   Dedicated: godot --headless -- --server [--port=8910]

const ChatRules = preload("res://chat/ChatRules.gd")
const RateLimiter = preload("res://chat/RateLimiter.gd")
const Config = preload("res://core/GameConfig.gd")
const ScenarioLoader = preload("res://scenarios/ScenarioLoader.gd")
const AssassinsMode = preload("res://modes/AssassinsMode.gd")
const NPCManagerScript = preload("res://npc/NPCManager.gd")
const NPCConfig = preload("res://npc/NPCConfig.gd")
const NarrativeManagerScript = preload("res://narrative/NarrativeManager.gd")

const DEFAULT_PORT := 8910
const SERVER_ID := 1
const BAD_NAME_TEXT := "Pick a name using letters, numbers, - or _ (no spaces)."

## We've been accepted into the room.
signal connected(assigned_name: String)
## We've left or been disconnected. `reason` is shown to the player.
signal disconnected(reason: String)
signal roster_changed(names: Array)
signal chat_received(from_name: String, text: String)
signal whisper_received(from_name: String, to_name: String, text: String)
signal system_message(text: String)
## We asked an NPC something (echoed back by the server once accepted).
signal npc_asked(npc_name: String, text: String)
## An NPC answered us. `action` is a short stage direction, maybe empty.
signal npc_replied(npc_name: String, action: String, text: String)
## The list of NPCs we can talk to: [{ id, alias, name, occupation, location }].
signal npc_directory_changed(npcs: Array)

var is_dedicated_server := false
## Our name once the server has accepted us; "" when not in a room.
var my_name := ""
var roster: Array = []
var npc_directory: Array = []

## Server only: peer_id -> name, for players who have joined.
var _players := {}
var _limiter := RateLimiter.new(ChatRules.RATE_LIMIT_COUNT, ChatRules.RATE_LIMIT_WINDOW_MS)
var _pending_name := ""

## Server only: the townsfolk. The chat room doesn't run a game yet, so it
## uses the default mode's scenario and opens conversations for free.
var _npcs = null
var _narrator: Node = null
## peer_id -> true while that player waits on an NPC's answer.
var _npc_busy := {}
## player name -> NPC messages sent this session (see NPCConfig.SANDBOX_MESSAGE_LIMIT).
var _npc_usage := {}
## player names already told the NPCs are on scripted lines.
var _npc_notice_sent := {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	var args := _parse_user_args()
	if args.has("server"):
		is_dedicated_server = true
		var port := String(args.get("port", str(DEFAULT_PORT))).to_int()
		var err := _start_server(port)
		if err == OK:
			print("Dedicated chat server listening on port %d" % port)
		else:
			push_error("Couldn't start server on port %d (error %d)" % [port, err])
			get_tree().quit(1)


func is_in_room() -> bool:
	return my_name != ""


# --- Public API (called by the UI) -------------------------------------------

## Host a room and join it as a player. Returns "" on success or an error.
func host(player_name: String, port := DEFAULT_PORT) -> String:
	var clean := ChatRules.clean_name(player_name)
	if clean == "":
		return BAD_NAME_TEXT
	var err := _start_server(port)
	if err != OK:
		return "Couldn't host on port %d (error %d). Is something else using it?" % [port, err]
	_handle_join(SERVER_ID, clean)
	return ""


## Connect to a host or dedicated server. Returns "" if the attempt started.
## The `connected` or `disconnected` signal reports how it went.
func join(player_name: String, address: String, port := DEFAULT_PORT) -> String:
	var clean := ChatRules.clean_name(player_name)
	if clean == "":
		return BAD_NAME_TEXT
	if address == "":
		return "Enter the server address."
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client("ws://%s:%d" % [address, port])
	if err != OK:
		return "Couldn't connect (error %d)." % err
	multiplayer.multiplayer_peer = peer
	_disable_relay()
	_pending_name = clean
	return ""


func leave() -> void:
	_reset()
	disconnected.emit("You left the room.")


func send(text: String) -> void:
	if not is_in_room():
		return
	if multiplayer.is_server():
		_handle_message(SERVER_ID, text)
	else:
		_rpc_send.rpc_id(SERVER_ID, text)


# --- Client -> server RPCs ---------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_request_join(requested_name: String) -> void:
	if not multiplayer.is_server():
		return
	_handle_join(multiplayer.get_remote_sender_id(), requested_name)


@rpc("any_peer", "reliable")
func _rpc_send(text: String) -> void:
	if not multiplayer.is_server():
		return
	_handle_message(multiplayer.get_remote_sender_id(), text)


# --- Server -> client RPCs ---------------------------------------------------

@rpc("authority", "reliable")
func _rpc_welcome(assigned_name: String) -> void:
	my_name = assigned_name
	connected.emit(assigned_name)


@rpc("authority", "reliable")
func _rpc_rejected(reason: String) -> void:
	_reset.call_deferred()
	disconnected.emit(reason)


@rpc("authority", "reliable")
func _rpc_roster(names: Array) -> void:
	roster = names
	roster_changed.emit(names)


@rpc("authority", "reliable")
func _rpc_chat(from_name: String, text: String) -> void:
	chat_received.emit(from_name, text)


@rpc("authority", "reliable")
func _rpc_whisper(from_name: String, to_name: String, text: String) -> void:
	whisper_received.emit(from_name, to_name, text)


@rpc("authority", "reliable")
func _rpc_system(text: String) -> void:
	system_message.emit(text)


@rpc("authority", "reliable")
func _rpc_npc_directory(npcs: Array) -> void:
	npc_directory = npcs
	npc_directory_changed.emit(npcs)


@rpc("authority", "reliable")
func _rpc_npc_asked(npc_name: String, text: String) -> void:
	npc_asked.emit(npc_name, text)


@rpc("authority", "reliable")
func _rpc_npc_reply(npc_name: String, action: String, text: String) -> void:
	npc_replied.emit(npc_name, action, text)


# --- Server logic ------------------------------------------------------------

func _handle_join(peer_id: int, requested_name: String) -> void:
	if _players.has(peer_id):
		return
	if _players.size() >= Config.MAX_PLAYERS:
		_reject(peer_id, "The room is full.")
		return
	var clean := ChatRules.clean_name(requested_name)
	if clean == "":
		_reject(peer_id, BAD_NAME_TEXT)
		return

	var assigned := ChatRules.unique_name(clean, _players.values())
	_players[peer_id] = assigned
	_send_to(peer_id, "_rpc_welcome", [assigned])
	if assigned != clean:
		_send_to(peer_id, "_rpc_system", ["%s was taken, so you're %s." % [clean, assigned]])
	if _npcs != null:
		_send_to(peer_id, "_rpc_npc_directory", [_npcs.directory()])
	_broadcast("_rpc_roster", [_players.values()])
	_broadcast("_rpc_system", ["%s joined the room." % assigned])
	_log("%s joined (peer %d)" % [assigned, peer_id])


func _handle_message(peer_id: int, raw: String) -> void:
	if not _players.has(peer_id):
		return
	if not _limiter.allow(peer_id, Time.get_ticks_msec()):
		_send_to(peer_id, "_rpc_system", ["You're sending messages too fast."])
		return

	var sender: String = _players[peer_id]
	var cmd := ChatRules.parse(raw)
	var kind: String = cmd["type"]
	if kind == "say":
		_broadcast("_rpc_chat", [sender, cmd["text"]])
		_log("%s: %s" % [sender, cmd["text"]])
	elif kind == "whisper":
		var target_id := _find_peer(cmd["target"])
		if target_id == -1:
			_send_to(peer_id, "_rpc_system", ["Nobody named %s is here." % cmd["target"]])
		elif target_id == peer_id:
			_send_to(peer_id, "_rpc_system", ["You can't whisper to yourself."])
		else:
			var target_name: String = _players[target_id]
			_send_to(peer_id, "_rpc_whisper", [sender, target_name, cmd["text"]])
			_send_to(target_id, "_rpc_whisper", [sender, target_name, cmd["text"]])
	elif kind == "ask":
		_handle_ask(peer_id, sender, cmd["target"], cmd["text"])
	elif kind == "npcs":
		_send_to(peer_id, "_rpc_system", [_npc_list_text()])
	elif kind == "error":
		_send_to(peer_id, "_rpc_system", [cmd["text"]])


## A player asks an NPC something. The answer is private: only the asker
## sees it, so they can share it truthfully, twist it, or keep it secret.
## Runs as a coroutine while the AI answers.
func _handle_ask(peer_id: int, sender: String, target: String, text: String) -> void:
	if _npcs == null or _narrator == null:
		return
	var found: Dictionary = _npcs.find(target)
	if not found["ok"]:
		_send_to(peer_id, "_rpc_system", [found["error"]])
		return
	if _npc_busy.has(peer_id):
		_send_to(peer_id, "_rpc_system", ["Wait for an answer before asking again."])
		return
	var used: int = _npc_usage.get(sender, 0)
	if used >= NPCConfig.SANDBOX_MESSAGE_LIMIT:
		_send_to(peer_id, "_rpc_system", ["You've talked the townsfolk's ears off for one session."])
		return
	_npc_usage[sender] = used + 1

	var npc_id: String = found["id"]
	var npc_name: String = _npcs.get_npc(npc_id).name
	_send_to(peer_id, "_rpc_npc_asked", [npc_name, text])
	if not _narrator.is_enabled() and not _npc_notice_sent.has(sender):
		_npc_notice_sent[sender] = true
		_send_to(peer_id, "_rpc_system", ["(The townsfolk are on scripted lines: the server has no API key set. See the README.)"])

	_npc_busy[peer_id] = true
	var npcs = _npcs
	var context: Dictionary = npcs.dialogue_context(npc_id, sender, {"name": sender}, {"day": 1})
	var reply: Dictionary = await _narrator.reply(context, text)
	_npc_busy.erase(peer_id)
	# The room may have closed, or the player left, while the NPC was thinking.
	if _npcs != npcs or _players.get(peer_id, "") != sender:
		return
	npcs.apply_reply(npc_id, sender, sender, text, reply)
	_send_to(peer_id, "_rpc_npc_reply", [npc_name, reply["action"], reply["dialogue"]])
	_log("%s asked %s: %s -> %s" % [sender, npc_name, text, reply["dialogue"]])


func _npc_list_text() -> String:
	if _npcs == null:
		return "There's nobody to talk to here."
	var lines := ["Townsfolk (talk with /ask name question):"]
	for npc in _npcs.directory():
		lines.append("  %s: %s, %s (%s)" % [npc["alias"], npc["name"], String(npc["occupation"]).to_lower(), npc["location"]])
	return "\n".join(lines)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or not _players.has(peer_id):
		return
	var left_name: String = _players[peer_id]
	_players.erase(peer_id)
	_limiter.forget(peer_id)
	_npc_busy.erase(peer_id)
	_broadcast("_rpc_roster", [_players.values()])
	_broadcast("_rpc_system", ["%s left the room." % left_name])
	_log("%s left (peer %d)" % [left_name, peer_id])


func _reject(peer_id: int, reason: String) -> void:
	_send_to(peer_id, "_rpc_rejected", [reason])
	# Give the rejection a moment to arrive before cutting the connection.
	get_tree().create_timer(0.5).timeout.connect(func():
		var peer := multiplayer.multiplayer_peer
		if peer != null and peer is WebSocketMultiplayerPeer:
			peer.disconnect_peer(peer_id)
	)


## Delivers an RPC to one player. If that player is us (the host), the
## method is called directly instead of over the network.
func _send_to(peer_id: int, method: String, args: Array) -> void:
	if peer_id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer_id, method] + args)


## Delivers an RPC to every player who has joined.
func _broadcast(method: String, args: Array) -> void:
	for peer_id in _players.keys():
		_send_to(peer_id, method, args)


func _find_peer(player_name: String) -> int:
	for peer_id in _players.keys():
		if String(_players[peer_id]).to_lower() == player_name.to_lower():
			return peer_id
	return -1


func _log(text: String) -> void:
	if is_dedicated_server:
		print("[chat] " + text)


# --- Client logic ------------------------------------------------------------

func _on_connected_to_server() -> void:
	_rpc_request_join.rpc_id(SERVER_ID, _pending_name)


func _on_connection_failed() -> void:
	_reset.call_deferred()
	disconnected.emit("Couldn't reach the server. Check the address and port.")


func _on_server_disconnected() -> void:
	_reset.call_deferred()
	disconnected.emit("The server closed the connection.")


# --- Shared ------------------------------------------------------------------

func _start_server(port: int) -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_disable_relay()
	_start_npcs()
	return OK


## Server only: loads the townsfolk and the AI that voices them.
func _start_npcs() -> void:
	_npcs = NPCManagerScript.new(ScenarioLoader.load_scenario(AssassinsMode.new().scenario_path))
	_narrator = NarrativeManagerScript.new()
	_narrator.name = "Narrator"
	add_child(_narrator)
	if _narrator.is_enabled():
		print("NPC AI is on (model %s)." % _narrator.settings["model"])
	else:
		print("NPC AI is off: set ANTHROPIC_API_KEY on this machine to turn it on. NPCs will use scripted lines.")


## Stop clients from sending RPCs straight to each other through the server.
func _disable_relay() -> void:
	var scene_mp := multiplayer as SceneMultiplayer
	if scene_mp != null:
		scene_mp.server_relay = false


func _reset() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	my_name = ""
	roster = []
	npc_directory = []
	_pending_name = ""
	_players.clear()
	if _narrator != null:
		_narrator.queue_free()
		_narrator = null
	_npcs = null
	_npc_busy.clear()
	_npc_usage.clear()
	_npc_notice_sent.clear()


## Parses user args (everything after "--"): "--server" -> {"server": ""},
## "--port=9000" -> {"port": "9000"}.
func _parse_user_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv: String = arg.substr(2)
		var eq := kv.find("=")
		if eq == -1:
			out[kv] = ""
		else:
			out[kv.substr(0, eq)] = kv.substr(eq + 1)
	return out
