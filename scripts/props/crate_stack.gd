extends Node3D
class_name CrateStack

@export var objective_color: Color = Color(0.2, 1.0, 0.2, 1.0)
@export var burn_color: Color = Color(1.0, 0.45, 0.15)

@export var fire_flicker_speed: float = 14.0
@export var fire_flicker_amount: float = 0.35
@export var fire_color_variance: float = 0.08

var ignited := false

@onready var crate_mesh: MeshInstance3D = $Crates
@onready var smoke: GPUParticles3D = get_node_or_null("Smoke") as GPUParticles3D
@onready var fire: GPUParticles3D = get_node_or_null("Fire") as GPUParticles3D

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
	if ignited:
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

