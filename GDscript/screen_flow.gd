extends Node

# Title, briefing, then the street. Pause exists only during play.
# Esc is taken here so the camera keeps its own input script.

const GAME_SCENE := "res://Scene/Scene/stage_1928_street.tscn"
const BRIEF_SECONDS := 15.0

enum Phase { TITLE, BRIEF, GAME }

var _phase := Phase.TITLE
var _brief_left := 0.0
var _title_revealed := false
var _game: Node
var _font: Font

var _game_holder: Node
var _curtain: ColorRect
var _title: Control
var _title_buttons: Control
var _title_notice: Label
var _brief: Control
var _pause: Control
var _pause_notice: Label

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft JhengHei"])
	_game_holder = Node.new()
	_game_holder.name = "GameHolder"
	_game_holder.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_game_holder)
	var ui := CanvasLayer.new()
	ui.name = "FlowUI"
	ui.layer = 128
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var root := Control.new()
	root.name = "FlowRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = Color(0, 0, 0, 1)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_curtain)
	_title = _build_title(root)
	_brief = _build_brief(root)
	_pause = _build_pause(root)
	_show_title()

func _process(delta: float) -> void:
	if _phase != Phase.BRIEF:
		return
	_brief_left -= delta
	if _brief_left <= 0.0:
		_enter_game()

func _input(event: InputEvent) -> void:
	if _phase == Phase.TITLE and not _title_revealed and _is_reveal_event(event):
		_reveal_title_buttons()
		get_viewport().set_input_as_handled()
		return
	if _phase == Phase.GAME and _is_escape(event):
		if not get_tree().paused:
			_open_pause()
		get_viewport().set_input_as_handled()

func _build_title(parent: Control) -> Control:
	var center := CenterContainer.new()
	center.name = "Title"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.name = "TitleBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "Game Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(title, 48)
	box.add_child(title)
	var buttons := VBoxContainer.new()
	buttons.name = "TitleButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.visible = false
	box.add_child(buttons)
	_title_buttons = buttons
	_add_menu_button(buttons, "StartButton", "開始遊戲 Start", _enter_brief)
	_add_menu_button(buttons, "ContinueButton", "繼續遊戲 Continue", _show_title_closed)
	_add_menu_button(buttons, "LoadButton", "讀取遊戲 Load", _show_title_closed)
	_add_menu_button(buttons, "QuitButton", "離開遊戲 Quit", _quit_game)
	_title_notice = Label.new()
	_title_notice.name = "TitleNotice"
	_title_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_title_notice, 24)
	buttons.add_child(_title_notice)
	return center

func _build_brief(parent: Control) -> Control:
	var brief := Control.new()
	brief.name = "Brief"
	brief.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brief.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brief.visible = false
	parent.add_child(brief)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brief.add_child(center)
	var label := Label.new()
	label.name = "BriefLabel"
	label.text = "說明內容建構中"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(label, 36)
	center.add_child(label)
	var button := _make_button("繼續遊戲", 18)
	button.name = "BriefContinue"
	button.custom_minimum_size = Vector2(140, 36)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = -164.0
	button.offset_top = -60.0
	button.offset_right = -24.0
	button.offset_bottom = -20.0
	button.pressed.connect(_enter_game)
	brief.add_child(button)
	return brief

func _build_pause(parent: Control) -> Control:
	var center := CenterContainer.new()
	center.name = "PauseMenu"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.name = "PauseBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	_add_menu_button(box, "ResumeButton", "返回遊戲 Resume", _resume_game)
	_add_menu_button(box, "SaveButton", "紀錄遊戲 Save", _show_pause_closed)
	_add_menu_button(box, "PauseLoadButton", "讀取遊戲 Load", _show_pause_closed)
	_add_menu_button(box, "PauseQuitButton", "離開遊戲 Quit", _quit_game)
	_add_menu_button(box, "TitleButton", "回到封面 Title", _show_title)
	_pause_notice = Label.new()
	_pause_notice.name = "PauseNotice"
	_pause_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(_pause_notice, 24)
	box.add_child(_pause_notice)
	return center

func _add_menu_button(parent: Node, node_name: String, text: String, callback: Callable) -> void:
	var button := _make_button(text, 28)
	button.name = node_name
	button.custom_minimum_size = Vector2(360, 0)
	button.pressed.connect(callback)
	parent.add_child(button)

func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 1)
	normal.border_color = Color(1, 1, 1, 1)
	normal.set_border_width_all(1)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.16, 0.16, 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", normal)
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	return button

func _style_label(label: Label, font_size: int) -> void:
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _show_title() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_free_game()
	_phase = Phase.TITLE
	_brief_left = 0.0
	_title_revealed = false
	_title_notice.text = ""
	_pause_notice.text = ""
	_title_buttons.visible = false
	_title.visible = true
	_brief.visible = false
	_pause.visible = false
	_curtain.visible = true

func _reveal_title_buttons() -> void:
	_title_revealed = true
	_title_notice.text = ""
	_title_buttons.visible = true

func _show_title_closed() -> void:
	_title_notice.text = "功能未開放"

func _show_pause_closed() -> void:
	_pause_notice.text = "功能未開放"

func _enter_brief() -> void:
	_phase = Phase.BRIEF
	_brief_left = BRIEF_SECONDS
	_title_revealed = false
	_title_notice.text = ""
	_title.visible = false
	_brief.visible = true
	_pause.visible = false
	_curtain.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _enter_game() -> void:
	if _phase == Phase.GAME:
		return
	_phase = Phase.GAME
	_brief_left = 0.0
	_title.visible = false
	_brief.visible = false
	_pause.visible = false
	_curtain.visible = false
	_pause_notice.text = ""
	if _game == null:
		var packed := load(GAME_SCENE) as PackedScene
		_game = packed.instantiate()
		_game.process_mode = Node.PROCESS_MODE_PAUSABLE
		_game_holder.add_child(_game)

func _open_pause() -> void:
	_pause_notice.text = ""
	_pause.visible = true
	_curtain.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume_game() -> void:
	_pause.visible = false
	_curtain.visible = false
	_pause_notice.text = ""
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _free_game() -> void:
	if _game == null:
		return
	_game.queue_free()
	_game = null

func _quit_game() -> void:
	get_tree().quit()

func _is_reveal_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return button.pressed
	return false

func _is_escape(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	return false
