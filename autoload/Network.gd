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
## Private chat between allies (/a), e.g. the assassins.
signal team_received(from_name: String, text: String)
signal system_message(text: String)

## Server only: a player finished joining / a joined player left.
signal player_joined(peer_id: int)
signal player_left(peer_id: int)

var is_dedicated_server := false
## Server only: when not "", new players are turned away with this reason
## (set by the Game autoload while a game is running).
var join_locked_reason := ""
## Our name once the server has accepted us; "" when not in a room.
var my_name := ""
var roster: Array = []

## Server only: peer_id -> name, for players who have joined.
var _players := {}
var _limiter := RateLimiter.new(ChatRules.RATE_LIMIT_COUNT, ChatRules.RATE_LIMIT_WINDOW_MS)
var _pending_name := ""


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


# --- Server-side helpers for other autoloads ----------------------------------

## Peer ids of joined players, in the order they joined.
func player_ids() -> Array:
	return _players.keys()


func player_name(peer_id: int) -> String:
	return _players.get(peer_id, "")


## The room leader is whoever has been in the room longest. They start
## games and move phases along.
func leader_id() -> int:
	return _players.keys()[0] if not _players.is_empty() else -1


## Sends a system message to one player.
func notify(peer_id: int, text: String) -> void:
	if _players.has(peer_id):
		_send_to(peer_id, "_rpc_system", [text])


# --- Public API (called by the UI) -------------------------------------------

## Host a room and join it as a player. Returns "" on success or an error.
func host(wanted_name: String, port := DEFAULT_PORT) -> String:
	var clean := ChatRules.clean_name(wanted_name)
	if clean == "":
		return BAD_NAME_TEXT
	var err := _start_server(port)
	if err != OK:
		return "Couldn't host on port %d (error %d). Is something else using it?" % [port, err]
	_handle_join(SERVER_ID, clean)
	return ""


## Connect to a host or dedicated server. Returns "" if the attempt started.
## The `connected` or `disconnected` signal reports how it went.
func join(wanted_name: String, address: String, port := DEFAULT_PORT) -> String:
	var clean := ChatRules.clean_name(wanted_name)
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
func _rpc_team(from_name: String, text: String) -> void:
	team_received.emit(from_name, text)


@rpc("authority", "reliable")
func _rpc_system(text: String) -> void:
	system_message.emit(text)


# --- Server logic ------------------------------------------------------------

func _handle_join(peer_id: int, requested_name: String) -> void:
	if _players.has(peer_id):
		return
	if join_locked_reason != "":
		_reject(peer_id, join_locked_reason)
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
	_broadcast("_rpc_roster", [_players.values()])
	_broadcast("_rpc_system", ["%s joined the room." % assigned])
	_log("%s joined (peer %d)" % [assigned, peer_id])
	player_joined.emit(peer_id)


func _handle_message(peer_id: int, raw: String) -> void:
	if not _players.has(peer_id):
		return
	if not _limiter.allow(peer_id, Time.get_ticks_msec()):
		_send_to(peer_id, "_rpc_system", ["You're sending messages too fast."])
		return

	var sender: String = _players[peer_id]
	var cmd := ChatRules.parse(raw)
	var kind: String = cmd["type"]
	if kind == "empty":
		return
	if kind == "error":
		_send_to(peer_id, "_rpc_system", [cmd["text"]])
		return

	# The game can restrict chat (e.g. public chat closes at night).
	var block: String = Game.chat_block_reason(peer_id, kind)
	if block != "":
		_send_to(peer_id, "_rpc_system", [block])
		return

	if kind == "team":
		var allies: Array = Game.team_recipients(peer_id)
		if allies.is_empty():
			# Same reply as any unknown command, so /a doesn't reveal anything.
			_send_to(peer_id, "_rpc_system", [ChatRules.unknown_command_text("a")])
			return
		for ally_id in allies:
			if _players.has(ally_id):
				_send_to(ally_id, "_rpc_team", [sender, cmd["text"]])
	elif kind == "say":
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


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server() or not _players.has(peer_id):
		return
	var left_name: String = _players[peer_id]
	_players.erase(peer_id)
	_limiter.forget(peer_id)
	_broadcast("_rpc_roster", [_players.values()])
	_broadcast("_rpc_system", ["%s left the room." % left_name])
	_log("%s left (peer %d)" % [left_name, peer_id])
	player_left.emit(peer_id)


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


func _find_peer(wanted_name: String) -> int:
	for peer_id in _players.keys():
		if String(_players[peer_id]).to_lower() == wanted_name.to_lower():
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
	return OK


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
	_pending_name = ""
	_players.clear()
	join_locked_reason = ""


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
