extends Node3D
class_name WallSurfaceDamage

@export var damage_to_crack_multiplier: float = 0.25
@export var block_size_meters: float = 0.35  # typical concrete block
@export var chunk_count_min: int = 14
@export var chunk_count_max: int = 22
@export var chunk_impulse_min: float = 3.0
@export var chunk_impulse_max: float = 12.0
@export var persistent_chunk_count: int = 12
@export var chunk_freeze_after_sec: float = 2.5
@export var chunk_remove_after_sec: float = 8.0
@export var dust_amount: int = 28
@export var dust_lifetime: float = 1.5
@export var destroy_crack_level_threshold: float = 0.8

var _shader_mat: ShaderMaterial
var _crack_level: float = 0.0
var _strength: float = 60.0
var _mesh_inst: MeshInstance3D
var _material_id: StringName = &"concrete"
var _destroyed: bool = false

func _ready() -> void:
	# Walls call `setup()` before the parent body is added to the scene tree.
	# Add to group here so explosions can reliably find us.
	add_to_group("wall_damageable")


func get_strength() -> float:
	return _strength


func get_crack_level() -> float:
	return _crack_level


func setup(
	mesh_inst: MeshInstance3D,
	material_strength: float,
	base_color: Color,
	crack_color: Color,
	material_id: StringName = &"concrete"
) -> void:
	_strength = max(material_strength, 0.1)
	_crack_level = 0.0
	_destroyed = false
	_mesh_inst = mesh_inst
	_material_id = material_id

	var shader: Shader = preload("res://shaders/wall_concrete_damage.gdshader")
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader

	_shader_mat.set_shader_parameter("base_color", Vector3(base_color.r, base_color.g, base_color.b))
	_shader_mat.set_shader_parameter("crack_color", Vector3(crack_color.r, crack_color.g, crack_color.b))
	_shader_mat.set_shader_parameter("crack_level", _crack_level)
	# `global_position` is unsafe here because the node may not be inside the scene tree yet.
	# `impact_pos` is updated on each `apply_surface_damage()` call anyway.
	_shader_mat.set_shader_parameter("impact_pos", Vector3.ZERO)

	# Procedural variety: block grid from wall size, random seed
	var block_count: Vector2 = Vector2(12.0, 8.0)
	if mesh_inst and mesh_inst.mesh is BoxMesh:
		var bs: Vector3 = (mesh_inst.mesh as BoxMesh).size
		block_count.x = max(4.0, bs.x / block_size_meters)
		block_count.y = max(4.0, bs.y / block_size_meters)
	elif mesh_inst and mesh_inst.mesh is CylinderMesh:
		var c: CylinderMesh = mesh_inst.mesh as CylinderMesh
		var r: float = maxf(c.top_radius, c.bottom_radius)
		block_count.x = max(4.0, r * 2.0 / block_size_meters)
		block_count.y = max(4.0, c.height / block_size_meters)
	_shader_mat.set_shader_parameter("block_count", block_count)
	_shader_mat.set_shader_parameter("seed", randf() * 1000.0)

	if mesh_inst:
		mesh_inst.material_override = _shader_mat


func apply_surface_damage(damage_amount: float, impact_world_pos: Vector3) -> void:
	if _shader_mat == null or _destroyed:
		return

	var t: float = clampf(damage_amount, 0.0, 1.0)
	var strength_factor: float = 1.0 + 50.0 / _strength
	_crack_level = clampf(_crack_level + t * damage_to_crack_multiplier * strength_factor, 0.0, 1.0)

	_shader_mat.set_shader_parameter("crack_level", _crack_level)
	_shader_mat.set_shader_parameter("impact_pos", impact_world_pos)

	# Strength controls how quickly cracks progress, so destruction triggers once
	# cracks become "visually critical".
	var destroy_threshold: float = clampf(destroy_crack_level_threshold, 0.55, 0.95)
	var strength_mod: float = clampf(_strength / 100.0, 0.3, 1.2)
	destroy_threshold = clampf(destroy_threshold * (0.75 + 0.25 * strength_mod), 0.55, 0.95)

	if _crack_level >= destroy_threshold:
		_destroy_wall(impact_world_pos)


func _destroy_wall(impact_origin: Vector3) -> void:
	if _destroyed:
		return
	_destroyed = true

	var body: StaticBody3D = get_parent() as StaticBody3D
	if body == null:
		return

	var wall_size: Vector3 = Vector3(2.0, 2.0, 0.5)
	if _mesh_inst and _mesh_inst.mesh is BoxMesh:
		wall_size = (_mesh_inst.mesh as BoxMesh).size
	elif _mesh_inst and _mesh_inst.mesh is CylinderMesh:
		var c: CylinderMesh = _mesh_inst.mesh as CylinderMesh
		var r: float = maxf(c.top_radius, c.bottom_radius)
		wall_size = Vector3(r * 2.0, c.height, r * 2.0)

	var wall_global: Transform3D = body.global_transform
	var wall_center: Vector3 = wall_global.origin
	var wall_normal: Vector3 = -wall_global.basis.z  # outward from front face
	var wall_right: Vector3 = wall_global.basis.x
	var wall_up: Vector3 = wall_global.basis.y

	# Disable collision and hide mesh
	body.collision_layer = 0
	body.collision_mask = 0
	if _mesh_inst:
		_mesh_inst.visible = false

	# Material-based destruction (Cortex Command-style: crumble, shatter, deform, splinter)
	var destruction_model: String = "crumble"
	var mat_dict: Dictionary = MaterialRegistry.get_material(_material_id)
	if mat_dict.has("destruction"):
		var d: Variant = mat_dict.get("destruction")
		if typeof(d) == TYPE_DICTIONARY:
			destruction_model = str((d as Dictionary).get("model", "crumble"))

	var params: Dictionary = _get_destruction_params(destruction_model)
	var count_min: int = int(params.get("chunk_count_min", chunk_count_min))
	var count_max: int = int(params.get("chunk_count_max", chunk_count_max))
	var persist_count: int = int(params.get("persistent_chunk_count", persistent_chunk_count))
	var chunk_count: int = min(randi_range(count_min, count_max), 32)
	for i in range(chunk_count):
		_spawn_chunk(wall_global, wall_size, wall_center, wall_normal, wall_right, wall_up, impact_origin, i < persist_count, params)

	_spawn_dust(wall_center, wall_normal, wall_right, wall_up, wall_size, params)

	if destruction_model == "reinforced":
		_spawn_rebar_skeleton(wall_center, wall_normal, wall_right, wall_up, wall_size)

	# Remove wall after a short delay so chunks/dust are parented to tree
	body.call_deferred("queue_free")


func _get_destruction_params(model: String) -> Dictionary:
	# Cortex Command-style material destruction: crumble, shatter, deform, splinter
	match model:
		"shatter":
			# Glass / brittle: many small shards, light color, less dust
			return {
				"chunk_count_min": 20,
				"chunk_count_max": 36,
				"persistent_chunk_count": 8,
				"chunk_size_min": Vector3(0.08, 0.08, 0.03),
				"chunk_size_max": Vector3(0.22, 0.22, 0.08),
				"impulse_min": 4.0,
				"impulse_max": 14.0,
				"chunk_color": Color(0.82, 0.85, 0.88),
				"dust_amount": 16,
				"dust_lifetime": 1.0,
				"dust_color": Color(0.9, 0.9, 0.92, 0.5),
			}
		"crumble":
			# Concrete / brick: blocks and rubble, grey, dusty
			return {
				"chunk_count_min": 14,
				"chunk_count_max": 22,
				"persistent_chunk_count": 12,
				"chunk_size_min": Vector3(0.18, 0.18, 0.08),
				"chunk_size_max": Vector3(0.42, 0.42, 0.22),
				"impulse_min": 3.0,
				"impulse_max": 12.0,
				"chunk_color": Color(0.68, 0.66, 0.64),
				"dust_amount": 28,
				"dust_lifetime": 1.5,
				"dust_color": Color(0.75, 0.72, 0.68, 0.6),
			}
		"reinforced":
			# Reinforced concrete: same as crumble, plus exposed rebar skeleton (rust-colored rods)
			return {
				"chunk_count_min": 14,
				"chunk_count_max": 22,
				"persistent_chunk_count": 12,
				"chunk_size_min": Vector3(0.18, 0.18, 0.08),
				"chunk_size_max": Vector3(0.42, 0.42, 0.22),
				"impulse_min": 3.0,
				"impulse_max": 12.0,
				"chunk_color": Color(0.62, 0.60, 0.58),
				"dust_amount": 28,
				"dust_lifetime": 1.5,
				"dust_color": Color(0.75, 0.72, 0.68, 0.6),
			}
		"deform":
			# Metal: fewer, heavier pieces, metallic look, stronger impulse
			return {
				"chunk_count_min": 5,
				"chunk_count_max": 12,
				"persistent_chunk_count": 5,
				"chunk_size_min": Vector3(0.28, 0.28, 0.1),
				"chunk_size_max": Vector3(0.55, 0.55, 0.2),
				"impulse_min": 8.0,
				"impulse_max": 18.0,
				"chunk_color": Color(0.52, 0.52, 0.55),
				"dust_amount": 12,
				"dust_lifetime": 1.0,
				"dust_color": Color(0.6, 0.6, 0.62, 0.5),
			}
		"splinter":
			# Wood: medium chunks, brown, some dust
			return {
				"chunk_count_min": 12,
				"chunk_count_max": 22,
				"persistent_chunk_count": 10,
				"chunk_size_min": Vector3(0.12, 0.2, 0.06),
				"chunk_size_max": Vector3(0.38, 0.45, 0.18),
				"impulse_min": 4.0,
				"impulse_max": 13.0,
				"chunk_color": Color(0.42, 0.28, 0.14),
				"dust_amount": 22,
				"dust_lifetime": 1.2,
				"dust_color": Color(0.35, 0.25, 0.15, 0.55),
			}
		_:
			return {
				"chunk_count_min": chunk_count_min,
				"chunk_count_max": chunk_count_max,
				"persistent_chunk_count": persistent_chunk_count,
				"chunk_size_min": Vector3(0.18, 0.18, 0.08),
				"chunk_size_max": Vector3(0.42, 0.42, 0.22),
				"impulse_min": chunk_impulse_min,
				"impulse_max": chunk_impulse_max,
				"chunk_color": Color(0.68, 0.66, 0.64),
				"dust_amount": dust_amount,
				"dust_lifetime": dust_lifetime,
				"dust_color": Color(0.75, 0.72, 0.68, 0.6),
			}


func _spawn_chunk(
	_wall_tr: Transform3D,
	wall_size: Vector3,
	wall_center: Vector3,
	wall_normal: Vector3,
	wall_right: Vector3,
	wall_up: Vector3,
	impact_origin: Vector3,
	persistent: bool = false,
	params: Dictionary = {}
) -> void:
	var size_min: Vector3 = _destruction_coerce_vec3(params.get("chunk_size_min", Vector3(0.18, 0.18, 0.08)))
	var size_max: Vector3 = _destruction_coerce_vec3(params.get("chunk_size_max", Vector3(0.42, 0.42, 0.22)))
	var chunk_color: Color = params.get("chunk_color", Color(0.68, 0.66, 0.64)) as Color
	var imp_min: float = float(params.get("impulse_min", chunk_impulse_min))
	var imp_max: float = float(params.get("impulse_max", chunk_impulse_max))

	var chunk: RigidBody3D = RigidBody3D.new()
	chunk.collision_layer = 1
	chunk.collision_mask = 1
	chunk.gravity_scale = 1.0

	var chunk_size: Vector3 = Vector3(
		randf_range(size_min.x, size_max.x),
		randf_range(size_min.y, size_max.y),
		randf_range(size_min.z, size_max.z)
	)
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = chunk_size
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	chunk.add_child(col)

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = chunk_size
	mesh_inst.mesh = box
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = chunk_color
	mat.roughness = 0.95
	if _material_id == &"metal":
		mat.metallic = 0.65
	mesh_inst.material_override = mat
	chunk.add_child(mesh_inst)

	# Position on wall face (local -0.5..0.5 then transform)
	var local_x: float = randf_range(-0.5, 0.5) * wall_size.x
	var local_y: float = randf_range(-0.5, 0.5) * wall_size.y
	var pos: Vector3 = wall_center + wall_right * local_x + wall_up * local_y + wall_normal * 0.1

	get_tree().current_scene.add_child(chunk)
	chunk.global_position = pos

	var to_chunk: Vector3 = (pos - impact_origin).normalized()
	var outward: Vector3 = wall_normal
	if (pos - impact_origin).length_squared() > 0.01:
		outward = (outward + to_chunk * 0.6).normalized()
	var impulse_mag: float = randf_range(imp_min, imp_max)
	chunk.apply_central_impulse(outward * impulse_mag)

	chunk.set_meta("wall_chunk", true)
	if persistent:
		# Freeze after a short time so they stay visible but stop simulating (CPU efficient)
		var freeze_timer: SceneTreeTimer = get_tree().create_timer(chunk_freeze_after_sec)
		freeze_timer.timeout.connect(_freeze_chunk_if_valid.bind(chunk))
	else:
		var timer: SceneTreeTimer = get_tree().create_timer(chunk_remove_after_sec)
		timer.timeout.connect(_queue_free_if_valid.bind(chunk))


func _destruction_coerce_vec3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_VECTOR3:
		return v as Vector3
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v as Array
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3(0.2, 0.2, 0.1)


func _queue_free_if_valid(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()


func _freeze_chunk_if_valid(node: Node) -> void:
	if is_instance_valid(node) and node is RigidBody3D:
		var rb: RigidBody3D = node as RigidBody3D
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0


func _spawn_dust(center: Vector3, normal: Vector3, _right: Vector3, _up: Vector3, wall_size: Vector3, params: Dictionary = {}) -> void:
	var amount: int = int(params.get("dust_amount", dust_amount))
	var lifetime: float = float(params.get("dust_lifetime", dust_lifetime))
	var dust_color: Color = params.get("dust_color", Color(0.75, 0.72, 0.68, 0.6)) as Color

	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = normal
	particles.spread = 35.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 7.0
	particles.gravity = Vector3(0, -6.0, 0)
	particles.emitting = true

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = dust_color
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat

	# Box emission shape: slightly in front of wall; orient so direction (0,0,1) = normal
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(wall_size.x * 0.5, wall_size.y * 0.5, 0.2)
	particles.direction = Vector3(0, 0, 1)

	# Add to tree before setting global_position/basis (avoids !is_inside_tree() with Jolt).
	get_tree().current_scene.add_child(particles)
	particles.global_position = center + normal * 0.15
	var up2: Vector3 = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right2: Vector3 = normal.cross(up2).normalized()
	var up3: Vector3 = right2.cross(normal).normalized()
	particles.basis = Basis(right2, up3, normal)
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime + 0.5)
	timer.timeout.connect(_queue_free_if_valid.bind(particles))


func _spawn_rebar_skeleton(center: Vector3, normal: Vector3, _wall_right: Vector3, _wall_up: Vector3, wall_size: Vector3) -> void:
	# Exposed rebar: rust-colored vertical rods, slightly bent/twisted, left behind when concrete is destroyed.
	var rebar_root: Node3D = Node3D.new()
	rebar_root.name = "RebarSkeleton"
	get_tree().current_scene.add_child(rebar_root)
	rebar_root.global_position = center + normal * 0.2
	var up2: Vector3 = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right2: Vector3 = normal.cross(up2).normalized()
	var up3: Vector3 = right2.cross(normal).normalized()
	rebar_root.basis = Basis(right2, up3, normal)

	var rust_color: Color = Color(0.45, 0.28, 0.18)
	var rod_count: int = randi_range(4, 8)
	var rod_radius: float = 0.04
	var rod_height: float = minf(wall_size.y * 0.9, 2.5)
	var spread_x: float = wall_size.x * 0.4
	var spread_z: float = wall_size.z * 0.3

	for i in range(rod_count):
		var rod: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = rod_radius * randf_range(0.8, 1.2)
		cyl.bottom_radius = cyl.top_radius * randf_range(0.9, 1.1)
		cyl.height = rod_height * randf_range(0.7, 1.0)
		rod.mesh = cyl
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = rust_color
		mat.roughness = 0.9
		mat.metallic = 0.25
		rod.material_override = mat
		rebar_root.add_child(rod)
		rod.position = Vector3(
			randf_range(-spread_x, spread_x),
			randf_range(-wall_size.y * 0.35, wall_size.y * 0.35),
			randf_range(-spread_z, spread_z)
		)
		# Slight tilt/bend: rotate around local X and Z so rods aren't perfectly vertical
		rod.rotation.x = randf_range(-0.15, 0.15)
		rod.rotation.z = randf_range(-0.15, 0.15)

	var timer: SceneTreeTimer = get_tree().create_timer(12.0)
	timer.timeout.connect(_queue_free_if_valid.bind(rebar_root))
