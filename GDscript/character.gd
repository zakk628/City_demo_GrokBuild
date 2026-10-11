extends CharacterBody3D

# Locomotion for the standard male.
# Model front is local +Z. ClimbRay points along that front.
# Climb starts only when Shift is held and ClimbRay hits the climb group.
# Climb-down that reaches the ground lets go. Climb jumps have no frames yet.
# Climb-up that brings the ray to the top of the climb volume sets the body on WallTop.
# Leaving that top falls. Landing cancels climb so walking works again.
# C toggles crouch. Middle mouse toggles lock. There is no target search and no snap.
# Alt slows the current crouch or stand-lock clip. Shift speeds that same clip.
# Unlocked crouch faces the move direction and plays the forward clip.
# Locked crouch faces the camera and plays crouch forward, back, left, or right.
# Stand lock faces the camera and plays lock idle, forward, back, left, or right.
# Climb cuts crouch and lock. Ctrl+Space with no direction does nothing.
# Direction already held, then Ctrl+Space: roll. Direction pressed together with Space: dodge.

const Anim := preload("res://GDscript/anime_controller.gd")

const SPEED_WALK := 1.45
const SPEED_RUN := 3.6
const SPEED_SPRINT := 6.4
const JUMP_SPEED := 6.2
const ROLL_PREHOLD := 0.18
const CLIMB_GROUND_Y := 0.45
const GROUND_MASK := 3
const CLIMB_MASK := 1

const DIR_KEYS: Array[int] = [
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
]

enum Phase { GROUND, JUMP_START, JUMP_AIR, JUMP_LAND, ROLL, DODGE, CLIMB }

var _phase: Phase = Phase.GROUND
var _anime: Anim
var _capsule_radius := 0.4
var _gravity := 9.8
var _saved_gait := ""
var _space_was := false
var _key_since := {}
var _climb_ray: RayCast3D
var _climb_wall: CSGBox3D
var _climb_face := 1.0
var _climb_left_floor := false
var _block_climb_until_shift_up := false
var _idle_until_dir_up := false
var _on_wall_top := false
var _wall_top_grounded := false
var _crouching := false
var _locked := false
var _c_was := false
var _middle_was := false
var _lock_label: Label

func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_anime = $Controller/AnimeController as Anim
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node and shape_node.shape is CylinderShape3D:
		_capsule_radius = (shape_node.shape as CylinderShape3D).radius
	_climb_ray = get_node_or_null("ClimbRay") as RayCast3D
	collision_mask = GROUND_MASK
	_build_lock_label()

func _physics_process(delta: float) -> void:
	if _anime == null or not _anime.ready_ok:
		return
	_update_key_times()
	_poll_toggles()
	_try_start_action()
	_prepare_facing()
	_anime.set_time_scale(_root_time_scale())
	_anime.advance(delta)
	var root_world := _anime.consume_root_motion(_phase == Phase.ROLL)
	match _phase:
		Phase.GROUND:
			_step_ground(delta, root_world)
		Phase.JUMP_START, Phase.JUMP_AIR, Phase.JUMP_LAND:
			_step_jump(delta, root_world)
		Phase.ROLL, Phase.DODGE:
			_step_oneshot(delta, root_world)
		Phase.CLIMB:
			_step_climb(delta, root_world)
	_space_was = Input.is_physical_key_pressed(KEY_SPACE)

func _try_start_action() -> void:
	if _block_climb_until_shift_up and not _shift_down():
		_block_climb_until_shift_up = false
	var space_just := Input.is_physical_key_pressed(KEY_SPACE) and not _space_was
	if _phase == Phase.GROUND:
		if _shift_down() and not _block_climb_until_shift_up and _find_climb_wall() != null:
			_cut_crouch_and_lock()
			_enter_climb()
			return
		if space_just and not _ctrl_down():
			_enter_jump()
			return
		if space_just and _ctrl_down():
			_enter_evade()
			return
		_update_ground_anim()
	elif _phase == Phase.CLIMB:
		if not _shift_down():
			_leave_climb()
			return
		# Climb jumps have no frames yet. Space stays on the wall.
		_update_climb_anim()

func _step_ground(delta: float, root_world: Vector3) -> void:
	if _crouching or _locked:
		_step_root_motion(delta, root_world)
		return
	var wish := _wish_dir()
	if _idle_until_dir_up and wish.length_squared() > 0.01:
		wish = Vector3.ZERO
	var gait := _ground_gait(wish.length_squared() > 0.01)
	var speed := _gait_speed(gait)
	if speed > 0.0 and wish.length_squared() > 0.01:
		var dir := wish.normalized()
		_face_direction(dir)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.x += root_world.x / delta
	velocity.z += root_world.z / delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	motion_mode = MOTION_MODE_GROUNDED
	move_and_slide()
	if _on_wall_top:
		if is_on_floor():
			_wall_top_grounded = true
		elif _wall_top_grounded:
			_begin_fall_from_top()

func _step_jump(delta: float, _root_world: Vector3) -> void:
	var wish := _wish_dir()
	var speed := _gait_speed(_saved_gait if _saved_gait != "" else "run")
	if wish.length_squared() > 0.01:
		var dir := wish.normalized()
		_face_direction(dir)
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= _gravity * delta
	motion_mode = MOTION_MODE_GROUNDED
	move_and_slide()
	if _phase == Phase.JUMP_START:
		if not is_on_floor() and _anime.animation_position() > 0.28:
			_phase = Phase.JUMP_AIR
			_anime.play(Anim.ANIM_JUMP_AIR, true)
		elif _anime.oneshot_done():
			_begin_land()
	elif _phase == Phase.JUMP_AIR:
		if is_on_floor():
			_begin_land()
	elif _phase == Phase.JUMP_LAND:
		if is_on_floor():
			velocity.y = 0.0
		if _anime.oneshot_done():
			_phase = Phase.GROUND
			_update_ground_anim()

func _step_oneshot(delta: float, root_world: Vector3) -> void:
	velocity = root_world / delta
	motion_mode = MOTION_MODE_GROUNDED
	move_and_slide()
	if _anime.oneshot_done():
		_phase = Phase.GROUND
		velocity = Vector3.ZERO
		_update_ground_anim()

func _step_climb(delta: float, root_world: Vector3) -> void:
	if _climb_wall == null or not is_instance_valid(_climb_wall):
		_leave_climb()
		return
	velocity = root_world / delta
	motion_mode = MOTION_MODE_FLOATING
	move_and_slide()
	_clamp_to_climb_wall()
	if _should_mantle():
		_mantle_to_wall_top()
		return
	if not _is_at_climb_bottom():
		_climb_left_floor = true
	elif _should_drop_to_ground():
		_drop_from_climb()

func _enter_jump() -> void:
	_saved_gait = _current_gait_name()
	if _saved_gait == "idle":
		_saved_gait = "run"
	_phase = Phase.JUMP_START
	velocity.y = JUMP_SPEED
	_anime.play(Anim.ANIM_JUMP_START, false)

func _begin_land() -> void:
	if _phase == Phase.JUMP_LAND:
		return
	_phase = Phase.JUMP_LAND
	velocity.y = 0.0
	_anime.play(Anim.ANIM_JUMP_LAND, false)

func _enter_evade() -> void:
	var key := _newest_dir_key()
	if key == 0:
		return
	var age := _key_age(key)
	if age >= ROLL_PREHOLD:
		_face_direction(_wish_dir())
		_phase = Phase.ROLL
		velocity = Vector3.ZERO
		_anime.play(Anim.ANIM_ROLL, false)
	else:
		_face_camera_forward()
		_phase = Phase.DODGE
		velocity = Vector3.ZERO
		_anime.play(_dodge_anim(key), false)

func _enter_climb() -> void:
	var wall := _find_climb_wall()
	if wall == null:
		return
	_climb_wall = wall
	_phase = Phase.CLIMB
	collision_mask = CLIMB_MASK
	velocity = Vector3.ZERO
	_snap_to_climb_wall()
	_climb_left_floor = not _is_at_climb_bottom()
	_anime.play(Anim.ANIM_CLIMB_IDLE, true)

func _leave_climb() -> void:
	_phase = Phase.GROUND
	collision_mask = GROUND_MASK
	_climb_wall = null
	_climb_left_floor = false
	motion_mode = MOTION_MODE_GROUNDED
	velocity = Vector3.ZERO
	_update_ground_anim()

func _drop_from_climb() -> void:
	_block_climb_until_shift_up = true
	_idle_until_dir_up = true
	_phase = Phase.GROUND
	collision_mask = GROUND_MASK
	_climb_wall = null
	_climb_left_floor = false
	motion_mode = MOTION_MODE_GROUNDED
	velocity = Vector3.ZERO
	if global_position.y < 0.2:
		global_position.y = 0.2
	_anime.play(Anim.ANIM_IDLE, true)

func _should_mantle() -> bool:
	if _anime.current_animation() != Anim.ANIM_CLIMB_UP:
		return false
	if _find_wall_top() == null:
		return false
	return _ray_at_volume_top()

func _ray_at_volume_top() -> bool:
	if _climb_wall == null or _climb_ray == null:
		return false
	var volume := _climb_wall.get_node_or_null("ClimbVolume") as Area3D
	if volume == null:
		return false
	var shape_node := volume.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null or not (shape_node.shape is BoxShape3D):
		return false
	var half_y := (shape_node.shape as BoxShape3D).size.y * 0.5
	half_y *= shape_node.global_transform.basis.get_scale().y
	var top_y := shape_node.global_position.y + half_y
	return _climb_ray.global_position.y >= top_y - 0.08

func _find_wall_top() -> CSGBox3D:
	var host := get_parent()
	if host == null:
		return null
	var node := host.find_child("WallTop", true, false)
	if node is CSGBox3D:
		return node as CSGBox3D
	return null

func _mantle_to_wall_top() -> void:
	var top := _find_wall_top()
	if top == null:
		return
	var half := top.size * 0.5
	var local := Vector3.ZERO
	local.x = clampf((top.global_transform.affine_inverse() * global_position).x, -half.x + 0.4, half.x - 0.4)
	local.y = half.y
	local.z = 0.0
	global_position = top.global_transform * local
	global_position.y += 0.02
	_phase = Phase.GROUND
	collision_mask = GROUND_MASK
	_climb_wall = null
	_climb_left_floor = false
	_on_wall_top = true
	_wall_top_grounded = false
	_idle_until_dir_up = true
	motion_mode = MOTION_MODE_GROUNDED
	velocity = Vector3.ZERO
	_anime.play(Anim.ANIM_IDLE, true)

func _begin_fall_from_top() -> void:
	_on_wall_top = false
	_wall_top_grounded = false
	_block_climb_until_shift_up = true
	_phase = Phase.JUMP_AIR
	_saved_gait = ""
	if velocity.y > 0.0:
		velocity.y = 0.0
	_anime.play(Anim.ANIM_JUMP_AIR, true)

func _should_drop_to_ground() -> bool:
	if _anime.current_animation() != Anim.ANIM_CLIMB_DOWN:
		return false
	if _climb_left_floor:
		return true
	return _anime.animation_position() > 0.2

func _is_at_climb_bottom() -> bool:
	return global_position.y <= CLIMB_GROUND_Y

func _update_ground_anim() -> void:
	if _phase != Phase.GROUND:
		return
	if _crouching:
		_update_crouch_anim()
		return
	if _locked:
		_update_lock_anim()
		return
	if _idle_until_dir_up:
		if _wish_dir().length_squared() > 0.01:
			_anime.play(Anim.ANIM_IDLE, true)
			return
		_idle_until_dir_up = false
	var moving := _wish_dir().length_squared() > 0.01
	var gait := _ground_gait(moving)
	_anime.play(_gait_anim(gait), true)

func _poll_toggles() -> void:
	var c_down := Input.is_physical_key_pressed(KEY_C)
	if c_down and not _c_was and _phase == Phase.GROUND:
		_crouching = not _crouching
	_c_was = c_down
	var middle_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	if middle_down and not _middle_was and _phase == Phase.GROUND:
		_locked = not _locked
		if _lock_label:
			_lock_label.text = "鎖定狀態" if _locked else "鎖定狀態解除"
		if _locked:
			_face_camera_forward()
	_middle_was = middle_down

func _cut_crouch_and_lock() -> void:
	_crouching = false
	if _locked:
		_locked = false
		if _lock_label:
			_lock_label.text = ""

func _crouch_wish() -> Vector3:
	var wish := _wish_dir()
	if _idle_until_dir_up and wish.length_squared() > 0.01:
		return Vector3.ZERO
	return wish

func _prepare_facing() -> void:
	if _phase != Phase.GROUND:
		return
	if _locked:
		_face_camera_forward()
		return
	if not _crouching:
		return
	var wish := _crouch_wish()
	if wish.length_squared() <= 0.01:
		return
	_face_direction(wish.normalized())

func _root_time_scale() -> float:
	if _phase != Phase.GROUND or not (_crouching or _locked):
		return 1.0
	var gait := 1.0
	if _shift_down() and _find_climb_wall() == null:
		gait = SPEED_SPRINT / SPEED_RUN
	elif _alt_down():
		gait = SPEED_WALK / SPEED_RUN
	return gait * _anime.root_clip_scale(_anime.current_animation())

func _step_root_motion(delta: float, root_world: Vector3) -> void:
	velocity.x = root_world.x / delta
	velocity.z = root_world.z / delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	motion_mode = MOTION_MODE_GROUNDED
	move_and_slide()
	if _on_wall_top:
		if is_on_floor():
			_wall_top_grounded = true
		elif _wall_top_grounded:
			_begin_fall_from_top()

func _update_crouch_anim() -> void:
	var wish := _crouch_wish()
	var anim_name := Anim.ANIM_CROUCH_IDLE
	if _locked and wish.length_squared() > 0.01:
		var forward := _key_held(KEY_W) or _key_held(KEY_UP)
		var back := _key_held(KEY_S) or _key_held(KEY_DOWN)
		var left := _key_held(KEY_A) or _key_held(KEY_LEFT)
		var right := _key_held(KEY_D) or _key_held(KEY_RIGHT)
		if forward and not back:
			anim_name = Anim.ANIM_CROUCH_F
		elif back and not forward:
			anim_name = Anim.ANIM_CROUCH_B
		elif left and not right:
			anim_name = Anim.ANIM_CROUCH_L
		elif right and not left:
			anim_name = Anim.ANIM_CROUCH_R
	elif wish.length_squared() > 0.01:
		anim_name = Anim.ANIM_CROUCH_F
	_anime.play(anim_name, true)

func _update_lock_anim() -> void:
	var wish := _crouch_wish()
	var anim_name := Anim.ANIM_LOCK_IDLE
	if wish.length_squared() > 0.01:
		var forward := _key_held(KEY_W) or _key_held(KEY_UP)
		var back := _key_held(KEY_S) or _key_held(KEY_DOWN)
		var left := _key_held(KEY_A) or _key_held(KEY_LEFT)
		var right := _key_held(KEY_D) or _key_held(KEY_RIGHT)
		if forward and not back:
			anim_name = Anim.ANIM_LOCK_F
		elif back and not forward:
			anim_name = Anim.ANIM_LOCK_B
		elif left and not right:
			anim_name = Anim.ANIM_LOCK_L
		elif right and not left:
			anim_name = Anim.ANIM_LOCK_R
	_anime.play(anim_name, true)

func _build_lock_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LockNotice"
	layer.layer = 20
	add_child(layer)
	_lock_label = Label.new()
	_lock_label.name = "LockLabel"
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft JhengHei", "PMingLiU", "Microsoft YaHei"])
	var settings := LabelSettings.new()
	settings.font = font
	settings.font_size = 36
	settings.font_color = Color(1, 1, 1, 1)
	settings.outline_size = 10
	settings.outline_color = Color(0, 0, 0, 0.9)
	_lock_label.label_settings = settings
	layer.add_child(_lock_label)
	_lock_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_lock_label.offset_top = 24.0
	_lock_label.offset_bottom = 88.0

func _update_climb_anim() -> void:
	var anim_name := Anim.ANIM_CLIMB_IDLE
	var up := _key_held(KEY_W) or _key_held(KEY_UP)
	var down := _key_held(KEY_S) or _key_held(KEY_DOWN)
	var left := _key_held(KEY_A) or _key_held(KEY_LEFT)
	var right := _key_held(KEY_D) or _key_held(KEY_RIGHT)
	if up and not down:
		anim_name = Anim.ANIM_CLIMB_UP
	elif down and not up:
		anim_name = Anim.ANIM_CLIMB_DOWN
	elif left and not right:
		anim_name = Anim.ANIM_CLIMB_L
	elif right and not left:
		anim_name = Anim.ANIM_CLIMB_R
	_anime.play(anim_name, true)

func _ground_gait(moving: bool) -> String:
	if not moving:
		_saved_gait = ""
		return "idle"
	if _shift_down() and _find_climb_wall() == null:
		_saved_gait = ""
		return "sprint"
	if _alt_down():
		_saved_gait = ""
		return "walk"
	if _saved_gait == "walk" or _saved_gait == "run" or _saved_gait == "sprint":
		return _saved_gait
	return "run"

func _current_gait_name() -> String:
	return _ground_gait(_wish_dir().length_squared() > 0.01)

func _gait_speed(gait: String) -> float:
	match gait:
		"walk":
			return SPEED_WALK
		"run":
			return SPEED_RUN
		"sprint":
			return SPEED_SPRINT
		_:
			return 0.0

func _gait_anim(gait: String) -> String:
	match gait:
		"walk":
			return Anim.ANIM_WALK
		"run":
			return Anim.ANIM_RUN
		"sprint":
			return Anim.ANIM_SPRINT
		_:
			return Anim.ANIM_IDLE

func _dodge_anim(key: int) -> String:
	match key:
		KEY_S, KEY_DOWN:
			return Anim.ANIM_DODGE_B
		KEY_A, KEY_LEFT:
			return Anim.ANIM_DODGE_L
		KEY_D, KEY_RIGHT:
			return Anim.ANIM_DODGE_R
		_:
			return Anim.ANIM_DODGE_F

func _wish_dir() -> Vector3:
	var axes := _camera_axes()
	var fwd: Vector3 = axes[0]
	var right: Vector3 = axes[1]
	var x := 0.0
	var y := 0.0
	if _key_held(KEY_D) or _key_held(KEY_RIGHT):
		x += 1.0
	if _key_held(KEY_A) or _key_held(KEY_LEFT):
		x -= 1.0
	if _key_held(KEY_W) or _key_held(KEY_UP):
		y += 1.0
	if _key_held(KEY_S) or _key_held(KEY_DOWN):
		y -= 1.0
	return right * x + fwd * y

func _camera_axes() -> Array:
	var cam := get_viewport().get_camera_3d()
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	if cam:
		fwd = -cam.global_transform.basis.z
		right = cam.global_transform.basis.x
	fwd.y = 0.0
	right.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
	if right.length_squared() > 0.0001:
		right = right.normalized()
	return [fwd, right]

func _face_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	rotation.y = atan2(flat.x, flat.z)

func _face_camera_forward() -> void:
	var axes := _camera_axes()
	_face_direction(axes[0])

func _find_climb_wall() -> CSGBox3D:
	if _climb_ray == null:
		return null
	_climb_ray.force_raycast_update()
	if not _climb_ray.is_colliding():
		return null
	var collider := _climb_ray.get_collider() as Node
	if not _node_in_group(collider, "climb"):
		return null
	var node := collider
	while node:
		if node is CSGBox3D:
			return node as CSGBox3D
		node = node.get_parent()
	return null

func _node_in_group(node: Node, group_name: String) -> bool:
	var current := node
	while current:
		if current.is_in_group(group_name):
			return true
		current = current.get_parent()
	return false

func _snap_to_climb_wall() -> void:
	var wall := _climb_wall
	var inv: Transform3D = wall.global_transform.affine_inverse()
	var local: Vector3 = inv * global_position
	var half := wall.size * 0.5
	_climb_face = 1.0 if local.z >= 0.0 else -1.0
	local.z = _climb_face * (half.z + _capsule_radius)
	local.x = clampf(local.x, -half.x + 0.2, half.x - 0.2)
	global_position = wall.global_transform * local
	var outward: Vector3 = wall.global_transform.basis.z * _climb_face
	outward.y = 0.0
	if outward.length_squared() > 0.0001:
		_face_direction(-outward.normalized())

func _clamp_to_climb_wall() -> void:
	var wall := _climb_wall
	var inv: Transform3D = wall.global_transform.affine_inverse()
	var local: Vector3 = inv * global_position
	var half := wall.size * 0.5
	local.x = clampf(local.x, -half.x + 0.2, half.x - 0.2)
	local.y = clampf(local.y, -half.y, half.y - 0.15)
	local.z = _climb_face * (half.z + _capsule_radius)
	global_position = wall.global_transform * local

func _update_key_times() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for key in DIR_KEYS:
		var down := Input.is_physical_key_pressed(key)
		if down and not _key_since.has(key):
			_key_since[key] = now
		elif not down and _key_since.has(key):
			_key_since.erase(key)

func _key_held(key: int) -> bool:
	return _key_since.has(key)

func _key_age(key: int) -> float:
	if not _key_since.has(key):
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - float(_key_since[key])

func _newest_dir_key() -> int:
	var best := 0
	var best_since := -1.0
	for key in DIR_KEYS:
		if not _key_since.has(key):
			continue
		var since := float(_key_since[key])
		if since >= best_since:
			best_since = since
			best = key
	return best

func _shift_down() -> bool:
	return Input.is_physical_key_pressed(KEY_SHIFT)

func _ctrl_down() -> bool:
	return Input.is_physical_key_pressed(KEY_CTRL)

func _alt_down() -> bool:
	return Input.is_physical_key_pressed(KEY_ALT)
