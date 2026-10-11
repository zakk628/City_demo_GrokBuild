extends Node

# Locomotion states for the standard male.
# Walk, run and sprint do not translate a control bone. Dodge, climb, roll and crouch do.
# Roll's travel is on main_control_Lv02. Everything else uses main_control_Lv01.
# Forward and back crouch clips ship with a single zero key on that bone.
# Their cycle distance is copied from the left crouch clip so root motion still drives them.
# Left and right crouch are 19 frames; forward and back are 39. TimeScale evens that speed gap.
# Stand-lock forward and back also have a single zero key. Their stride is copied from lock-left.
# Lock left and right are 14 frames; lock forward and back are 39. TimeScale evens that speed gap.
# Blends stay at zero: climb-down starts at Y=6, and a capture blend cancels that descent.

const ANIM_IDLE := "stdman_move00_idle_01"
const ANIM_WALK := "stdman_move01_walk"
const ANIM_RUN := "stdman_move02_run"
const ANIM_SPRINT := "stdman_move03_sprint"
const ANIM_JUMP_START := "stdman_move04_jump_01_start"
const ANIM_JUMP_AIR := "stdman_move04_jump_02_air"
const ANIM_JUMP_LAND := "stdman_move04_jump_03_land"
const ANIM_ROLL := "stdman_move05_roll"
const ANIM_DODGE_F := "stdman_move06_dodge01_forward"
const ANIM_DODGE_B := "stdman_move06_dodge02_backward"
const ANIM_DODGE_L := "stdman_move06_dodge03_left"
const ANIM_DODGE_R := "stdman_move06_dodge04_right"
const ANIM_CLIMB_IDLE := "stdman_prk00_climb_idle_01"
const ANIM_CLIMB_UP := "stdman_prk01_climb_up"
const ANIM_CLIMB_DOWN := "stdman_prk02_climb_down"
const ANIM_CLIMB_L := "stdman_prk03_climb_shimmy_01_L"
const ANIM_CLIMB_R := "stdman_prk03_climb_shimmy_02_R"
const ANIM_CROUCH_IDLE := "stdman_move07_crouch00_idle"
const ANIM_CROUCH_F := "stdman_move07_crouch01_forward"
const ANIM_CROUCH_B := "stdman_move07_crouch02_backward"
const ANIM_CROUCH_L := "stdman_move07_crouch03_left"
const ANIM_CROUCH_R := "stdman_move07_crouch04_right"
const ANIM_LOCK_IDLE := "stdman_move08_lock00_idle"
const ANIM_LOCK_F := "stdman_move08_lock01_forward"
const ANIM_LOCK_B := "stdman_move08_lock02_backward"
const ANIM_LOCK_L := "stdman_move08_lock03_left"
const ANIM_LOCK_R := "stdman_move08_lock04_right"

const CROUCH_CLIPS: Array[String] = [
	ANIM_CROUCH_IDLE, ANIM_CROUCH_F, ANIM_CROUCH_B, ANIM_CROUCH_L, ANIM_CROUCH_R,
]
const LOCK_CLIPS: Array[String] = [
	ANIM_LOCK_IDLE, ANIM_LOCK_F, ANIM_LOCK_B, ANIM_LOCK_L, ANIM_LOCK_R,
]

const STAGE1_CLIPS: Array[String] = [
	ANIM_IDLE, ANIM_WALK, ANIM_RUN, ANIM_SPRINT,
	ANIM_JUMP_START, ANIM_JUMP_AIR, ANIM_JUMP_LAND,
	ANIM_ROLL, ANIM_DODGE_F, ANIM_DODGE_B, ANIM_DODGE_L, ANIM_DODGE_R,
	ANIM_CLIMB_IDLE, ANIM_CLIMB_UP, ANIM_CLIMB_DOWN, ANIM_CLIMB_L, ANIM_CLIMB_R,
]

var ready_ok := false

var _player: AnimationPlayer
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _playback: AnimationNodeStateMachinePlayback
var _bone_lv01 := -1
var _bone_lv02 := -1
var _current := ""
var _root_valid := false
var _root_prev := Vector3.ZERO
var _root_time := 0.0
var _span := {}
var _time_scale := 1.0
var _crouch_clip_scale := {}
var _lock_clip_scale := {}

func _ready() -> void:
	var body := get_parent().get_parent()
	_player = body.get_node_or_null("standardman_panties/AnimationPlayer") as AnimationPlayer
	_skeleton = body.get_node_or_null("standardman_panties/meta_human_rig/Skeleton3D") as Skeleton3D
	_tree = body.get_node_or_null("AnimationTree") as AnimationTree
	if _player == null or _skeleton == null or _tree == null:
		push_error("anime_controller: AnimationPlayer, Skeleton3D or AnimationTree missing")
		return
	_bone_lv01 = _skeleton.find_bone("main_control_Lv01")
	_bone_lv02 = _skeleton.find_bone("main_control_Lv02")
	if _bone_lv01 < 0 or _bone_lv02 < 0:
		push_error("anime_controller: main_control bones missing")
		return
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.playback_auto_capture = false
	_player.playback_default_blend_time = 0.0
	_tree.active = false
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.anim_player = _tree.get_path_to(_player)
	_ensure_states()
	_fill_missing_crouch_root()
	_fill_missing_lock_root()
	_cache_root_spans()
	_apply_crouch_key_spans()
	_apply_lock_key_spans()
	_cache_crouch_scales()
	_cache_lock_scales()
	_tree.active = true
	_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback == null:
		_tree.advance(0.0)
		_playback = _tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _playback == null:
		push_error("anime_controller: AnimationTree playback missing")
		return
	play(ANIM_IDLE, true)
	advance(0.0)
	ready_ok = true

func play(anim_name: String, looping: bool) -> void:
	var animation := _find_animation(anim_name)
	if animation == null:
		push_error("missing animation %s" % anim_name)
		return
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	if _current == anim_name and _is_playing():
		return
	if _playback:
		_playback.start(anim_name, true)
	else:
		_player.play(anim_name, 0.0)
	_current = anim_name
	_root_valid = false

func set_time_scale(scale: float) -> void:
	_time_scale = maxf(scale, 0.05)

func crouch_clip_scale(anim_name: String) -> float:
	return float(_crouch_clip_scale.get(anim_name, 1.0))

func root_clip_scale(anim_name: String) -> float:
	if _lock_clip_scale.has(anim_name):
		return float(_lock_clip_scale[anim_name])
	return crouch_clip_scale(anim_name)

func advance(delta: float) -> void:
	var scaled := delta * _time_scale
	if _tree != null and _tree.active:
		_tree.advance(scaled)
	elif _player != null:
		_player.advance(scaled)

func animation_position() -> float:
	if _playback:
		return _playback.get_current_play_position()
	if _player == null:
		return 0.0
	return _player.current_animation_position

func current_animation() -> String:
	if _playback:
		var node_name := String(_playback.get_current_node())
		if node_name != "":
			return node_name
	return _current

func oneshot_done() -> bool:
	if _playback:
		if not _playback.is_playing():
			return true
		var length := _playback.get_current_length()
		return length > 0.0 and _playback.get_current_play_position() >= length - 0.001
	if _player == null or not _player.is_playing():
		return true
	var length := _player.current_animation_length
	return length > 0.0 and _player.current_animation_position >= length - 0.001

func consume_root_motion(prefer_lv02: bool) -> Vector3:
	var bone := _bone_lv02 if (prefer_lv02 or _current == ANIM_ROLL) else _bone_lv01
	if bone < 0 or _skeleton == null:
		return Vector3.ZERO
	_skeleton.force_update_all_bone_transforms()
	var pos := _skeleton.get_bone_global_pose(bone).origin
	var time := animation_position()
	var delta := Vector3.ZERO
	if _root_valid:
		delta = pos - _root_prev
		if time + 0.0001 < _root_time:
			delta += _span.get(_current, Vector3.ZERO)
	_root_prev = pos
	_root_time = time
	_root_valid = true
	var rest := _skeleton.get_bone_rest(bone)
	_skeleton.set_bone_pose_position(bone, rest.origin)
	return _skeleton.global_transform.basis * delta

func _ensure_states() -> void:
	var machine := _tree.tree_root as AnimationNodeStateMachine
	if machine == null or not _machine_has_stage1(machine):
		machine = _build_machine()
		_tree.tree_root = machine
	_ensure_named_states(machine, CROUCH_CLIPS, 620.0)
	_ensure_named_states(machine, LOCK_CLIPS, 760.0)

func _ensure_named_states(machine: AnimationNodeStateMachine, clips: Array[String], row_y: float) -> void:
	var column := 0
	for clip in clips:
		if machine.has_node(clip):
			continue
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		machine.add_node(clip, node, Vector2(280 + column * 220, row_y))
		column += 1

func _machine_has_stage1(machine: AnimationNodeStateMachine) -> bool:
	for clip in STAGE1_CLIPS:
		if not machine.has_node(clip):
			return false
	return true

func _build_machine() -> AnimationNodeStateMachine:
	var machine := AnimationNodeStateMachine.new()
	var column := 0
	var row := 0
	for clip in STAGE1_CLIPS:
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		machine.add_node(clip, node, Vector2(280 + column * 240, 140 + row * 120))
		column += 1
		if column >= 4:
			column = 0
			row += 1
	var enter := AnimationNodeStateMachineTransition.new()
	enter.xfade_time = 0.0
	enter.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	enter.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	machine.add_transition("Start", ANIM_IDLE, enter)
	return machine

func _cache_root_spans() -> void:
	var names: Array[String] = [
		ANIM_CLIMB_UP, ANIM_CLIMB_DOWN, ANIM_CLIMB_L, ANIM_CLIMB_R,
		ANIM_DODGE_F, ANIM_DODGE_B, ANIM_DODGE_L, ANIM_DODGE_R, ANIM_ROLL,
		ANIM_CROUCH_F, ANIM_CROUCH_B, ANIM_CROUCH_L, ANIM_CROUCH_R,
		ANIM_LOCK_F, ANIM_LOCK_B, ANIM_LOCK_L, ANIM_LOCK_R,
	]
	for anim_name in names:
		if _find_animation(anim_name) == null:
			continue
		var bone := _bone_lv02 if anim_name == ANIM_ROLL else _bone_lv01
		_player.play(anim_name)
		_player.seek(0.0, true)
		_player.advance(0.0)
		_skeleton.force_update_all_bone_transforms()
		var start: Vector3 = _skeleton.get_bone_global_pose(bone).origin
		var length := _find_animation(anim_name).length
		_player.seek(maxf(length - 0.0001, 0.0), true)
		_player.advance(0.0)
		_skeleton.force_update_all_bone_transforms()
		var ending: Vector3 = _skeleton.get_bone_global_pose(bone).origin
		_span[anim_name] = ending - start
	_player.stop()

func _fill_missing_crouch_root() -> void:
	var stride := _key_span(ANIM_CROUCH_L).x
	if absf(stride) < 0.05:
		stride = -_key_span(ANIM_CROUCH_R).x
	if absf(stride) < 0.05:
		return
	stride = absf(stride)
	_write_linear_root(ANIM_CROUCH_F, Vector3(0.0, 0.0, stride))
	_write_linear_root(ANIM_CROUCH_B, Vector3(0.0, 0.0, -stride))

func _fill_missing_lock_root() -> void:
	var stride := absf(_key_span(ANIM_LOCK_L).x)
	if stride < 0.05:
		stride = absf(_key_span(ANIM_LOCK_R).x)
	if stride < 0.05:
		return
	_write_linear_root(ANIM_LOCK_F, Vector3(0.0, 0.0, stride))
	_write_linear_root(ANIM_LOCK_B, Vector3(0.0, 0.0, -stride))

func _write_linear_root(anim_name: String, end_value: Vector3) -> void:
	var anim := _find_animation(anim_name)
	if anim == null:
		return
	var track := _position_track(anim, "main_control_Lv01")
	if track < 0 or _track_horizontal_range(anim, track) > 0.05:
		return
	var editable := anim.duplicate() as Animation
	track = _position_track(editable, "main_control_Lv01")
	editable.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	while editable.track_get_key_count(track) > 0:
		editable.track_remove_key(track, 0)
	var length := maxf(editable.length - 0.0001, 0.0)
	editable.track_insert_key(track, 0.0, Vector3.ZERO)
	editable.track_insert_key(track, length, end_value)
	_replace_animation(anim_name, editable)

func _apply_crouch_key_spans() -> void:
	for clip in [ANIM_CROUCH_F, ANIM_CROUCH_B, ANIM_CROUCH_L, ANIM_CROUCH_R]:
		var span := _key_span(clip)
		if span.length() > 0.001:
			_span[clip] = span

func _apply_lock_key_spans() -> void:
	for clip in [ANIM_LOCK_F, ANIM_LOCK_B, ANIM_LOCK_L, ANIM_LOCK_R]:
		var span := _key_span(clip)
		if span.length() > 0.001:
			_span[clip] = span

func _cache_crouch_scales() -> void:
	_cache_side_scales(ANIM_CROUCH_F, [ANIM_CROUCH_L, ANIM_CROUCH_R], 19.0 / 39.0, _crouch_clip_scale)

func _cache_lock_scales() -> void:
	_cache_side_scales(ANIM_LOCK_F, [ANIM_LOCK_L, ANIM_LOCK_R], 14.0 / 39.0, _lock_clip_scale)

func _cache_side_scales(forward_name: String, sides: Array, fallback: float, store: Dictionary) -> void:
	var forward_rate := _horizontal_rate(forward_name)
	for clip in sides:
		var rate := _horizontal_rate(String(clip))
		if forward_rate > 0.0001 and rate > 0.0001:
			store[clip] = forward_rate / rate
		else:
			store[clip] = fallback

func _horizontal_rate(anim_name: String) -> float:
	var length := 0.0
	var anim := _find_animation(anim_name)
	if anim:
		length = anim.length
	if length <= 0.0001:
		return 0.0
	var span: Vector3 = _span.get(anim_name, Vector3.ZERO)
	return Vector2(span.x, span.z).length() / length

func _key_span(anim_name: String) -> Vector3:
	var anim := _find_animation(anim_name)
	if anim == null:
		return Vector3.ZERO
	var track := _position_track(anim, "main_control_Lv01")
	if track < 0 or anim.track_get_key_count(track) == 0:
		return Vector3.ZERO
	var first: Vector3 = anim.track_get_key_value(track, 0)
	var last: Vector3 = anim.track_get_key_value(track, anim.track_get_key_count(track) - 1)
	return last - first

func _position_track(anim: Animation, bone_name: String) -> int:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		if String(anim.track_get_path(i)).ends_with(bone_name):
			return i
	return -1

func _track_horizontal_range(anim: Animation, track: int) -> float:
	var min_p := Vector3(INF, INF, INF)
	var max_p := Vector3(-INF, -INF, -INF)
	for k in anim.track_get_key_count(track):
		var value: Vector3 = anim.track_get_key_value(track, k)
		min_p = min_p.min(value)
		max_p = max_p.max(value)
	var span := max_p - min_p
	return Vector2(span.x, span.z).length()

func _replace_animation(anim_name: String, anim: Animation) -> void:
	for lib_name in _player.get_animation_library_list():
		var lib := _player.get_animation_library(lib_name)
		if not lib.has_animation(anim_name):
			continue
		lib.remove_animation(anim_name)
		lib.add_animation(anim_name, anim)
		return

func _find_animation(anim_name: String) -> Animation:
	if _player == null:
		return null
	for lib_name in _player.get_animation_library_list():
		var lib := _player.get_animation_library(lib_name)
		if lib.has_animation(anim_name):
			return lib.get_animation(anim_name)
	return null

func _is_playing() -> bool:
	if _playback:
		return _playback.is_playing()
	return _player != null and _player.is_playing()
