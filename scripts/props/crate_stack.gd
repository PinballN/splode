extends Node3D
class_name CrateStack

@export var objective_color: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var burn_color: Color = Color(1.0, 0.45, 0.15)

# Visual embers spawned when the stack ignites (fire spreads with small burning pieces).
@export var ember_color: Color = Color(1.0, 0.55, 0.15, 1.0)
@export var ember_count: int = 90
@export var ember_lifetime_sec: float = 1.4
@export var ember_spawn_radius_m: float = 0.95
@export var ember_spread_degrees: float = 32.0
@export var ember_velocity_min_mps: float = 2.5
@export var ember_velocity_max_mps: float = 7.0
@export var ember_gravity: Vector3 = Vector3(0.0, -6.0, 0.0)

# Small embers that stay lit on the floor for a few seconds.
@export var floor_ember_count: int = 10
@export var floor_ember_radius_m: float = 1.6
@export var floor_ember_min_lifetime_sec: float = 2.0
@export var floor_ember_max_lifetime_sec: float = 5.0

@export var fire_flicker_speed: float = 14.0
@export var fire_flicker_amount: float = 0.35
@export var fire_color_variance: float = 0.08

var ignited := false

@onready var crate_mesh: MeshInstance3D = $Crates
@onready var smoke: GPUParticles3D = get_node_or_null("Smoke") as GPUParticles3D
@onready var fire: GPUParticles3D = get_node_or_null("Fire") as GPUParticles3D
@onready var sparks: GPUParticles3D = get_node_or_null("Sparks") as GPUParticles3D

var _burn_material: StandardMaterial3D
var _burn_base_emission_energy_multiplier := 1.0
var _burn_phase: float = 0.0


func _ready() -> void:
	add_to_group("crate_stack")
	# Only run the emissive flicker while burning.
	set_process(false)

	# Make the crate stack readable as the mission objective.
	if crate_mesh:
		var material := StandardMaterial3D.new()
		material.albedo_color = objective_color
		material.emission_enabled = true
		material.emission = objective_color
		material.emission_energy_multiplier = 0.6
		crate_mesh.material_override = material

func ignite(fire_damage: float = 1.0) -> void:
	# Even if the stack is already burning, spawn a small ember pulse when
	# additional fire/explosion hits it. This matches "sparks when it ignites."
	if ignited:
		_burst_sparks()
		return

	ignited = true
	_burn_phase = randf() * TAU
	set_process(true)

	var material := StandardMaterial3D.new()
	material.albedo_color = burn_color
	material.emission_enabled = true
	material.emission = burn_color
	# Scale intensity by how "hot" the incoming fire damage is.
	material.emission_energy_multiplier = 1.0 + clampf(fire_damage, 0.0, 10.0) * 0.25
	_burn_base_emission_energy_multiplier = material.emission_energy_multiplier
	crate_mesh.material_override = material
	_burn_material = material

	if smoke:
		smoke.restart()
		smoke.emitting = true

	if fire:
		fire.restart()
		fire.emitting = true

	# Add a small ember burst right when the stack ignites.
	_burst_sparks()


func _burst_sparks() -> void:
	# Prefer the in-scene GPU particle node (most reliable in Godot).
	if sparks:
		sparks.restart()
		sparks.emitting = true
		_spawn_floor_embers()
		return
	# Fallback: if the node is missing, use the older CPU burst path.
	_spawn_embers(1.0)


func _spawn_floor_embers() -> void:
	var n: int = clampi(floor_ember_count, 0, 40)
	if n <= 0:
		return

	var center := crate_mesh.global_position if crate_mesh else global_position
	var floor_y: float = 0.03

	for i in range(n):
		var ember := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(randf_range(0.05, 0.1), randf_range(0.05, 0.1))
		ember.mesh = quad

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = ember_color
		mat.emission_enabled = true
		mat.emission = ember_color
		mat.emission_energy_multiplier = randf_range(1.5, 3.5)
		ember.material_override = mat

		get_tree().current_scene.add_child(ember)
		var r := randf_range(0.15, floor_ember_radius_m)
		var a := randf_range(0.0, TAU)
		ember.global_position = Vector3(center.x + cos(a) * r, floor_y, center.z + sin(a) * r)
		ember.rotation_degrees.x = -90.0
		ember.rotation_degrees.y = randf_range(0.0, 360.0)

		# Random lifetime; fade emission down then remove.
		var life := randf_range(floor_ember_min_lifetime_sec, floor_ember_max_lifetime_sec)
		var tmr: SceneTreeTimer = get_tree().create_timer(life)
		tmr.timeout.connect(_fade_and_free_floor_ember.bind(ember, mat))


func _fade_and_free_floor_ember(ember: Node3D, mat: StandardMaterial3D) -> void:
	if not is_instance_valid(ember):
		return
	var tw := get_tree().create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.35)
	tw.tween_callback(_queue_free_if_valid.bind(ember))


func _queue_free_if_valid(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


func _spawn_embers(fire_damage: float) -> void:
	# Blinking embers/sparks:
	# spawn a few short one-shot bursts so they visibly "pulse" orange.
	var burst_count := 5
	for i in range(burst_count):
		var delay := float(i) * 0.10
		var count_scale := lerpf(1.0, 0.55, float(i) / float(burst_count - 1))
		var lifetime_scale := lerpf(1.0, 0.75, float(i) / float(burst_count - 1))

		get_tree().create_timer(delay).timeout.connect(func() -> void:
			_spawn_ember_burst(
				fire_damage,
				int(round(float(ember_count) * count_scale)),
				max(0.05, ember_lifetime_sec * lifetime_scale),
			)
		)


func _spawn_ember_burst(fire_damage: float, count: int, lifetime_sec: float) -> void:
	if count <= 0:
		return

	# Match the wall dust particle setup so embers reliably render.
	var particles: CPUParticles3D = CPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime_sec
	particles.one_shot = true
	particles.explosiveness = 0.75
	particles.gravity = ember_gravity
	particles.emitting = true

	# Emission: box around the crate stack.
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var e: float = maxf(0.05, ember_spawn_radius_m)
	particles.emission_box_extents = Vector3(e * 0.6, e * 0.25, e * 0.6)

	# Upwards embers with cone spread.
	particles.direction = Vector3(0, 0, 1)
	particles.spread = ember_spread_degrees

	# Scale velocity by how hot it is.
	var heat := clampf(fire_damage, 0.0, 10.0) / 10.0
	var vmin := ember_velocity_min_mps * (1.0 + heat * 0.6)
	var vmax := ember_velocity_max_mps * (1.0 + heat * 0.8)
	particles.initial_velocity_min = vmin
	particles.initial_velocity_max = vmax

	# Unshaded material; use particle vertex color as albedo (same approach as wall dust).
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ember_color
	mat.vertex_color_use_as_albedo = true
	particles.material_override = mat

	# Add to tree before setting global_position/basis.
	get_tree().current_scene.add_child(particles)
	var center := crate_mesh.global_position if crate_mesh else global_position
	particles.global_position = center + Vector3(0.0, 0.85, 0.0)

	# Orient so local direction (+Z) goes upward.
	var normal: Vector3 = Vector3.UP
	var up2: Vector3 = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right2: Vector3 = normal.cross(up2).normalized()
	var up3: Vector3 = right2.cross(normal).normalized()
	particles.basis = Basis(right2, up3, normal)

	# Auto cleanup.
	var timer: SceneTreeTimer = get_tree().create_timer(lifetime_sec + 0.5)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)


func _process(_delta: float) -> void:
	if not ignited or not _burn_material:
		return

	# Cortex-like "alive" fire: modulate emissive energy and slightly vary color.
	var t := Time.get_ticks_msec() / 1000.0
	var flicker := 1.0 + (
		sin(t * fire_flicker_speed + _burn_phase) * fire_flicker_amount +
		sin(t * fire_flicker_speed * 0.53 + _burn_phase * 1.7) * fire_flicker_amount * 0.5
	)
	flicker = clampf(flicker, 1.0 - fire_flicker_amount * 1.2, 1.0 + fire_flicker_amount)

	_burn_material.emission_energy_multiplier = _burn_base_emission_energy_multiplier * flicker

	var color_shift := sin(t * (fire_flicker_speed * 0.6) + _burn_phase) * fire_color_variance
	var shifted := Color(
		clampf(burn_color.r + color_shift, 0.0, 1.0),
		clampf(burn_color.g - color_shift * 0.6, 0.0, 1.0),
		clampf(burn_color.b - color_shift * 0.2, 0.0, 1.0),
		burn_color.a
	)
	_burn_material.emission = shifted

