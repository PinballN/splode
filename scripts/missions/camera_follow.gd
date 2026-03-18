extends Node3D
class_name CameraFollow

@export var target_path: NodePath
@export var follow_offset: Vector3 = Vector3(0.0, 14.0, 14.0)
@export var lerp_speed: float = 8.0
@export var look_at_height: float = 0.5

@onready var camera: Camera3D = $Camera3D
var target: Node3D
var initialized := false

var _camera_base_local_pos: Vector3

var _shake_time_left := 0.0
var _shake_duration := 0.0
var _shake_magnitude := 0.0
var _shake_frequency := 25.0
var _shake_phase := 0.0

const _NEUTRAL_BG := Color(0.22, 0.22, 0.22, 1.0)


func _ready() -> void:
	if target_path != NodePath():
		target = get_node_or_null(target_path) as Node3D

	if camera:
		camera.current = true
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		# Smaller size = less "zoomed out"
		camera.size = 12.0
		_camera_base_local_pos = camera.position


func _process(delta: float) -> void:
	# Force neutral background every frame so 3D view never shows red when camera moves.
	var world_env: WorldEnvironment = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		world_env.environment.background_color = _NEUTRAL_BG
		world_env.environment.background_mode = Environment.BG_COLOR

	if target == null:
		return

	var desired_position := target.global_position + follow_offset

	# Snap once we have a valid target so the camera doesn't "drift away"
	# before it catches up.
	if not initialized:
		global_position = desired_position
		initialized = true
	else:
		global_position = global_position.lerp(
			desired_position,
			clampf(lerp_speed * delta, 0.0, 1.0)
		)

	# Ensure camera orientation always points at the player.
	if camera:
		camera.look_at(target.global_position + Vector3.UP * look_at_height, Vector3.UP)

	# Apply concussion-style shake as a local camera offset.
	if _shake_time_left > 0.0 and camera:
		var t := (_shake_duration - _shake_time_left)
		var decay := clampf(_shake_time_left / _shake_duration, 0.0, 1.0)

		var x := sin(t * _shake_frequency + _shake_phase) * _shake_magnitude * decay
		var y := cos(t * (_shake_frequency * 1.13) + _shake_phase * 0.7) * (_shake_magnitude * 0.35) * decay

		camera.position = _camera_base_local_pos + Vector3(x, y, 0.0)
		_shake_time_left -= delta
		if _shake_time_left <= 0.0:
			_shake_time_left = 0.0
			camera.position = _camera_base_local_pos
	else:
		if camera:
			camera.position = _camera_base_local_pos


func start_concussion_shake(duration: float = 0.35, magnitude: float = 0.6, frequency: float = 25.0) -> void:
	_shake_duration = maxf(duration, 0.01)
	_shake_time_left = _shake_duration
	_shake_magnitude = magnitude
	_shake_frequency = frequency
	_shake_phase = randf() * 1000.0
