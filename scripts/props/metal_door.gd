extends StaticBody3D
class_name MetalDoor

## Weak metal door that blows off in a blast (deforms and flies away, no shatter).
## Triggers sound FX and camera shake when blown.

@export var strength: float = 20.0
@export var impact_multiplier: float = 80.0
@export var impulse_min: float = 8.0
@export var impulse_max: float = 18.0
@export var fly_lifetime: float = 6.0

@onready var door_mesh: MeshInstance3D = get_node_or_null("DoorMesh") as MeshInstance3D
@onready var door_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SfxPlayer") as AudioStreamPlayer

var _blown_off := false
var _sample_rate: float = 44100.0
var _playback: AudioStreamGeneratorPlayback
var _sound_active := false
var _sound_elapsed := 0.0
var _sound_duration := 0.0


func _ready() -> void:
	add_to_group("breakables")
	if door_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.52, 0.52, 0.55)
		mat.metallic = 0.7
		mat.roughness = 0.5
		door_mesh.material_override = mat
	if sfx_player and sfx_player.stream is AudioStreamGenerator:
		_sample_rate = float((sfx_player.stream as AudioStreamGenerator).mix_rate)


func _process(_delta: float) -> void:
	if not _sound_active or not sfx_player or not _playback:
		return
	var frames: int = _playback.get_frames_available()
	while frames > 0 and _sound_elapsed < _sound_duration:
		var t: float = _sound_elapsed / _sound_duration
		var env: float = (1.0 - t) * (1.0 - t)
		# Metal clang: noise + low thump
		var sample: float = randf_range(-1.0, 1.0) * 0.45 * env
		sample += sin(_sound_elapsed * 120.0 * TAU) * 0.25 * env
		sample += sin(_sound_elapsed * 45.0 * TAU) * 0.15 * env
		_playback.push_frame(Vector2(sample, sample))
		_sound_elapsed += 1.0 / _sample_rate
		frames -= 1
	if _sound_elapsed >= _sound_duration:
		_sound_active = false


func apply_explosion(concussion_value: float, _fire_damage: float, blast_origin: Vector3 = Vector3.ZERO) -> void:
	if _blown_off:
		return
	var impact: float = concussion_value * impact_multiplier
	if impact < strength:
		return
	_blow_off(blast_origin)


func _blow_off(blast_origin: Vector3) -> void:
	_blown_off = true
	var pos: Vector3 = global_position
	var door_basis: Basis = global_transform.basis

	# Spawn flying door as RigidBody3D (one piece, no shatter)
	var rb: RigidBody3D = RigidBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 1
	rb.gravity_scale = 1.0

	var size: Vector3 = Vector3(1.2, 2.0, 0.08)
	if door_mesh and door_mesh.mesh is BoxMesh:
		size = (door_mesh.mesh as BoxMesh).size

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	rb.add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.52, 0.55)
	mat.metallic = 0.7
	mat.roughness = 0.5
	mesh_inst.material_override = mat
	rb.add_child(mesh_inst)

	get_tree().current_scene.add_child(rb)
	rb.global_position = pos
	rb.global_transform.basis = door_basis

	var to_door: Vector3 = (pos - blast_origin).normalized()
	if blast_origin.distance_squared_to(pos) < 0.5:
		to_door = -door_basis.z
	var impulse_mag: float = randf_range(impulse_min, impulse_max)
	rb.apply_central_impulse(to_door * impulse_mag)
	# Slight upward and rotation
	rb.apply_impulse(door_basis.y * randf_range(1.0, 3.0), door_basis.x * randf_range(-1.0, 1.0))

	# Remove flying door after a while
	var timer: SceneTreeTimer = get_tree().create_timer(fly_lifetime)
	timer.timeout.connect(_queue_free_if_valid.bind(rb))

	# Hide original door
	collision_layer = 0
	collision_mask = 0
	if door_shape:
		door_shape.disabled = true
	if door_mesh:
		door_mesh.visible = false

	_play_metal_impact_sound()
	_request_camera_shake()


func _play_metal_impact_sound() -> void:
	if not sfx_player:
		return
	_sound_active = true
	_sound_elapsed = 0.0
	_sound_duration = 0.22
	sfx_player.play()
	_playback = sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _request_camera_shake() -> void:
	get_tree().call_group("mission", "request_camera_shake", 0.4, 0.55)


func _queue_free_if_valid(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
