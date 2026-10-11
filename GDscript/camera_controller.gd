extends Node

# Assassin's Creed Mirage orbit.
# CameraRig copies the body position and stays world-aligned, so it does not inherit facing.
# Cam_h yaws around world Y. Cam_v pitches on its own X, from -40 to 60 degrees.
# Camera3D sits on local +Z and is not rotated, so it looks down local -Z at the pivot.
# Negative pitch raises the camera: Rx(pitch) sends local +Z to (0, -sin(pitch), cos(pitch)).

@export var pivot_height := 1.4
@export var distance := 2.0
@export var min_distance := 2.0
@export var max_distance := 6.0
@export var default_pitch_deg := -18.0
@export var min_pitch_deg := -40.0
@export var max_pitch_deg := 60.0
@export var mouse_degrees_per_pixel := 0.12
@export var follow_sharpness := 22.0
@export var boom_sharpness := 18.0
@export var collision_margin := 0.25
@export var collision_mask := 1

var _yaw := 0.0
var _pitch_deg := -18.0
var _distance := 5.0
var _boom := 5.0
var _follow := Vector3.ZERO
var _has_follow := false
var _body: Node3D
var _rig: Node3D
var _horizontal: Node3D
var _vertical: Node3D
var _camera: Camera3D

func _ready() -> void:
	_body = get_parent().get_parent() as Node3D
	_rig = _body.get_node("CameraRig") as Node3D
	_horizontal = _rig.get_node("Cam_h") as Node3D
	_vertical = _rig.get_node("Cam_h/Cam_v") as Node3D
	_camera = _rig.get_node("Cam_h/Cam_v/Camera3D") as Camera3D
	_pitch_deg = clampf(default_pitch_deg, min_pitch_deg, max_pitch_deg)
	_distance = clampf(distance, min_distance, max_distance)
	_boom = _distance
	_apply_angles()
	_camera.rotation = Vector3.ZERO
	_camera.position = Vector3(0.0, 0.0, _boom)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var yaw_step := mouse_degrees_per_pixel * PI / 180.0
		# Mouse right orbits the camera clockwise from above, so the view turns right.
		_yaw -= motion.relative.x * yaw_step
		# Mouse up raises pitch (camera swings down and looks up).
		_pitch_deg -= motion.relative.y * mouse_degrees_per_pixel
		_apply_angles()
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.25, min_distance, max_distance)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.25, min_distance, max_distance)
		elif button.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if _body == null or _rig == null:
		return
	var goal := _body.global_position + Vector3(0.0, pivot_height, 0.0)
	if not _has_follow:
		_follow = goal
		_has_follow = true
	var blend := 1.0 - exp(-follow_sharpness * delta)
	_follow = _follow.lerp(goal, blend)
	_rig.global_transform = Transform3D(Basis.IDENTITY, _follow)
	_apply_angles()
	_update_boom(delta, _body)

func _apply_angles() -> void:
	_pitch_deg = clampf(_pitch_deg, min_pitch_deg, max_pitch_deg)
	_horizontal.rotation = Vector3(0.0, _yaw, 0.0)
	_vertical.rotation = Vector3(deg_to_rad(_pitch_deg), 0.0, 0.0)
	if _camera:
		_camera.rotation = Vector3.ZERO

func _update_boom(delta: float, body: Node3D) -> void:
	var origin := _vertical.global_position
	var back := _vertical.global_transform.basis.z
	if back.length_squared() < 0.0001:
		return
	back = back.normalized()
	var want := clampf(_distance, min_distance, max_distance)
	var dist := want
	var space := _rig.get_world_3d().direct_space_state
	if space and body is CollisionObject3D:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + back * want)
		query.exclude = [(body as CollisionObject3D).get_rid()]
		query.collision_mask = collision_mask
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var clear := origin.distance_to(hit.position) - collision_margin
			dist = min(want, max(0.15, clear))
	var blend := 1.0 - exp(-boom_sharpness * delta)
	_boom = lerpf(_boom, dist, blend)
	_camera.position = Vector3(0.0, 0.0, _boom)
