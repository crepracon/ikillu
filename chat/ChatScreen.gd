extends Control
## The chat room screen. Built in code so there's no hand-maintained scene
## layout yet; it can move into a proper .tscn once the UI settles.
## All networking goes through the Network autoload.

const ChatRules = preload("res://chat/ChatRules.gd")

const COLOR_SYSTEM := "#9a9a9a"
const COLOR_WHISPER := "#c99be0"
const COLOR_NAME := "#e8c37a"
const COLOR_NPC := "#7fd1c2"
const COLOR_NPC_QUIET := "#9fbfb9"

var _connect_panel: VBoxContainer
var _name_input: LineEdit
var _address_input: LineEdit
var _port_input: LineEdit
var _status: Label

var _chat_panel: VBoxContainer
var _log: RichTextLabel
var _roster_list: ItemList
var _npc_list: ItemList
var _input: LineEdit


func _ready() -> void:
	if Network.is_dedicated_server:
		return # Headless server: nothing to show.
	_build_ui()
	Network.connected.connect(_on_connected)
	Network.disconnected.connect(_on_disconnected)
	Network.roster_changed.connect(_on_roster_changed)
	Network.chat_received.connect(_on_chat)
	Network.whisper_received.connect(_on_whisper)
	Network.system_message.connect(_on_system)
	Network.npc_directory_changed.connect(_on_npc_directory)
	Network.npc_asked.connect(_on_npc_asked)
	Network.npc_replied.connect(_on_npc_replied)
	_show_connect_panel()


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "The Wayward Lantern: Common Room"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	# Connect panel
	_connect_panel = VBoxContainer.new()
	_connect_panel.add_theme_constant_override("separation", 8)
	root.add_child(_connect_panel)

	_name_input = _add_field(_connect_panel, "Your name", "", "Letters, numbers, - or _")
	_address_input = _add_field(_connect_panel, "Server address", "127.0.0.1", "")
	_port_input = _add_field(_connect_panel, "Port", str(Network.DEFAULT_PORT), "")
	_name_input.max_length = ChatRules.MAX_NAME_LENGTH
	_name_input.text_submitted.connect(func(_t): _on_join_pressed())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_connect_panel.add_child(buttons)
	var host_button := Button.new()
	host_button.text = "Host a room"
	host_button.pressed.connect(_on_host_pressed)
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join_pressed)
	buttons.add_child(join_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_connect_panel.add_child(_status)

	# Chat panel
	_chat_panel = VBoxContainer.new()
	_chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_panel.add_theme_constant_override("separation", 8)
	root.add_child(_chat_panel)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_chat_panel.add_child(body)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_log)

	var side_panel := VBoxContainer.new()
	side_panel.custom_minimum_size = Vector2(210, 0)
	body.add_child(side_panel)
	var roster_label := Label.new()
	roster_label.text = "In the room"
	side_panel.add_child(roster_label)
	_roster_list = ItemList.new()
	_roster_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_list.item_activated.connect(_on_roster_activated)
	side_panel.add_child(_roster_list)
	var npc_label := Label.new()
	npc_label.text = "Townsfolk (double-click to ask)"
	side_panel.add_child(npc_label)
	_npc_list = ItemList.new()
	_npc_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_npc_list.item_activated.connect(_on_npc_activated)
	side_panel.add_child(_npc_list)
	var leave_button := Button.new()
	leave_button.text = "Leave"
	leave_button.pressed.connect(func(): Network.leave())
	side_panel.add_child(leave_button)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	_chat_panel.add_child(input_row)
	_input = LineEdit.new()
	_input.placeholder_text = "Say something...   /w name message to whisper   /ask name question to talk to the townsfolk"
	_input.max_length = ChatRules.MAX_MESSAGE_LENGTH
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_text_submitted)
	input_row.add_child(_input)
	var send_button := Button.new()
	send_button.text = "Send"
	send_button.pressed.connect(func(): _on_text_submitted(_input.text))
	input_row.add_child(send_button)


func _add_field(parent: Control, label_text: String, value: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = placeholder
	field.custom_minimum_size = Vector2(260, 0)
	row.add_child(field)
	return field


func _show_connect_panel() -> void:
	_connect_panel.visible = true
	_chat_panel.visible = false
	_name_input.grab_focus()


func _show_chat_panel() -> void:
	_connect_panel.visible = false
	_chat_panel.visible = true
	_input.grab_focus()


# --- Connect panel -----------------------------------------------------------

func _on_host_pressed() -> void:
	var err := Network.host(_name_input.text, _port())
	if err != "":
		_status.text = err


func _on_join_pressed() -> void:
	var err := Network.join(_name_input.text, _address_input.text.strip_edges(), _port())
	_status.text = err if err != "" else "Connecting..."


func _port() -> int:
	var p := _port_input.text.strip_edges().to_int()
	return p if p > 0 and p < 65536 else Network.DEFAULT_PORT


# --- Network events ----------------------------------------------------------

func _on_connected(assigned_name: String) -> void:
	_log.clear()
	_status.text = ""
	_show_chat_panel()
	_append_system("Welcome to the Wayward Lantern, %s." % assigned_name)


func _on_disconnected(reason: String) -> void:
	_roster_list.clear()
	_npc_list.clear()
	_status.text = reason
	_show_connect_panel()


func _on_roster_changed(names: Array) -> void:
	_roster_list.clear()
	for n in names:
		_roster_list.add_item(n + ("  (you)" if n == Network.my_name else ""))


func _on_chat(from_name: String, text: String) -> void:
	_append("[color=%s][b]%s[/b][/color]: %s" % [
		COLOR_NAME, ChatRules.escape_bbcode(from_name), ChatRules.escape_bbcode(text)])


func _on_whisper(from_name: String, to_name: String, text: String) -> void:
	var header := ""
	if from_name == Network.my_name:
		header = "You whisper to %s" % ChatRules.escape_bbcode(to_name)
	else:
		header = "%s whispers to you" % ChatRules.escape_bbcode(from_name)
	_append("[color=%s][i]%s:[/i] %s[/color]" % [COLOR_WHISPER, header, ChatRules.escape_bbcode(text)])


func _on_system(text: String) -> void:
	_append_system(text)


func _on_npc_directory(npcs: Array) -> void:
	_npc_list.clear()
	for npc in npcs:
		var index := _npc_list.add_item(String(npc.get("name", "")))
		_npc_list.set_item_metadata(index, String(npc.get("alias", "")))
		_npc_list.set_item_tooltip(index, "%s, %s" % [npc.get("occupation", ""), npc.get("location", "")])


func _on_npc_asked(npc_name: String, text: String) -> void:
	_append("[color=%s][i]You ask %s:[/i] %s[/color]" % [
		COLOR_NPC_QUIET, ChatRules.escape_bbcode(npc_name), ChatRules.escape_bbcode(text)])


func _on_npc_replied(npc_name: String, action: String, text: String) -> void:
	var line := "[color=%s][b]%s[/b][/color]" % [COLOR_NPC, ChatRules.escape_bbcode(npc_name)]
	if action != "":
		line += " [color=%s][i](%s)[/i][/color]" % [COLOR_NPC_QUIET, ChatRules.escape_bbcode(action)]
	line += ": \"%s\"" % ChatRules.escape_bbcode(text)
	_append(line)


# --- Input -------------------------------------------------------------------

func _on_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	Network.send(text)
	_input.clear()
	_input.grab_focus()


## Double-clicking a name starts a whisper to them.
func _on_roster_activated(index: int) -> void:
	var target: String = _roster_list.get_item_text(index).replace("  (you)", "")
	if target == Network.my_name:
		return
	_input.text = "/w %s " % target
	_input.caret_column = _input.text.length()
	_input.grab_focus()


## Double-clicking an NPC starts a question to them.
func _on_npc_activated(index: int) -> void:
	_input.text = "/ask %s " % _npc_list.get_item_metadata(index)
	_input.caret_column = _input.text.length()
	_input.grab_focus()


# --- Log helpers -------------------------------------------------------------

func _append(bbcode_line: String) -> void:
	var stamp := Time.get_time_string_from_system().substr(0, 5)
	_log.append_text("[color=%s]%s[/color]  %s\n" % [COLOR_SYSTEM, stamp, bbcode_line])


func _append_system(text: String) -> void:
	_append("[color=%s][i]%s[/i][/color]" % [COLOR_SYSTEM, ChatRules.escape_bbcode(text)])
