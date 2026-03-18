extends StaticBody3D
class_name GlassWindow

@export var material_id: StringName = &"glass"
@export var impact_damage_multiplier: float = 100.0
@export var shard_count: int = 10
@export var shard_lifetime: float = 1.0

@onready var pane_mesh: MeshInstance3D = $PaneMesh
@onready var blocker: MaterialBlocker = get_node_or_null("MaterialBlocker") as MaterialBlocker

var _strength: float = 10.0
var _shattered := false


func _ready() -> void:
	add_to_group("breakables")

	# Ensure the blocker matches the exported material id if present.
	if blocker:
		blocker.material_id = material_id
		_strength = blocker.get_strength()
	else:
		var fallback: Dictionary = MaterialRegistry.get_material(material_id)
		_strength = float(fallback.get("strength", 10.0))

	# Tint glass so it is easy to recognize at a glance.
	if pane_mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.8, 1.0, 0.55)  # light blue
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.05
		pane_mesh.material_override = mat


func apply_explosion(concussion_value: float, _fire_damage: float, _blast_origin: Vector3 = Vector3.ZERO) -> void:
	if _shattered:
		return

	# Simple mapping: concussion_value becomes "impact damage".
	var impact_damage := concussion_value * impact_damage_multiplier
	if impact_damage < _strength:
		return

	shatter()


func get_transparency() -> float:
	if blocker:
		return blocker.get_transparency()
	var fallback: Dictionary = MaterialRegistry.get_material(material_id)
	return float(fallback.get("visibility_transparency", 0.0))


func shatter() -> void:
	_shattered = true

	# Remove collider so fog can see through after shatter.
	collision_layer = 0
	collision_mask = 0

	if pane_mesh:
		pane_mesh.visible = false

	_spawn_shards()


func _spawn_shards() -> void:
	# Tiny shard visuals (cheap CPU-driven blocks).
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(shard_count):
		var shard := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(
			rng.randf_range(0.03, 0.12),
			rng.randf_range(0.03, 0.12),
			rng.randf_range(0.01, 0.04)
		)
		shard.mesh = box
		# Godot 4 uses a ShadowCastingSetting enum (not a bool) for this property.
		shard.cast_shadow = GeometryInstance3D.ShadowCastingSetting.SHADOW_CASTING_SETTING_OFF

		var local_offset := Vector3(
			rng.randf_range(-1.0, 1.0) * 1.0,
			rng.randf_range(-1.0, 1.0) * 1.0,
			rng.randf_range(-1.0, 1.0) * 0.2
		)

		# Add first, then use local `position` to avoid calling `global_transform`
		# on a node that isn't in the scene tree yet.
		add_child(shard)
		shard.position = local_offset
		shard.scale = Vector3.ONE

		# Fade out by queue_free after lifetime (we skip physics in POC).
		shard.call_deferred("queue_free")
