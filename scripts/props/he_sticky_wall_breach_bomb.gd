extends IncendiaryBomb
class_name HeStickyWallBreachBomb

# Overrides which data entry BombRegistry loads for this scene.
@export var stick_collision_mask: int = 1  # matches mission walls' collision_layer=1
@export var stick_search_distance: float = 1.0
@export var stick_offset: float = 0.03

var _is_stuck: bool = false


func _ready() -> void:
	# Must be set before `super._ready()` loads bomb stats.
	bomb_id = &"test_he_sticky_breach"
	super._ready()
	_attempt_stick()


func _attempt_stick() -> void:
	if _is_stuck:
		return

	var world_3d := get_viewport().get_world_3d()
	if world_3d == null:
		return

	var space_state := world_3d.direct_space_state
	var origin := global_position

	# Try to find the closest wall in cardinal directions and snap to it.
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
	]

	var self_rid: RID = get_rid()
	var best_dist: float = INF
	var best_pos := origin
	var best_normal := Vector3.ZERO

	for dir in dirs:
		var to := origin + dir * stick_search_distance
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, to)
		params.collision_mask = stick_collision_mask
		params.exclude = [self_rid]
		params.collide_with_areas = false

		var hit: Variant = space_state.intersect_ray(params)
		if hit == null:
			continue
		if typeof(hit) != TYPE_DICTIONARY:
			continue

		var pos: Variant = hit.get("position")
		var normal: Variant = hit.get("normal")
		if pos == null:
			continue

		var dist: float = origin.distance_to(pos as Vector3)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos as Vector3
			if normal != null and typeof(normal) == TYPE_VECTOR3:
				best_normal = normal as Vector3
			else:
				best_normal = dir

	if best_dist <= stick_search_distance and best_normal != Vector3.ZERO:
		var n := best_normal.normalized()
		global_position = best_pos + n * stick_offset
		# Make the bomb face the surface normal (mesh is -Z facing by default).
		look_at(global_position + n, Vector3.UP)
		_is_stuck = true


# Same visuals/audio as the incendiary bomb, but use blast radius for explosion
# so wall breach actually affects a wider area.
func _detonate() -> void:
	_beep_visual_time_left = 0.0

	_start_explosion()
	detonated.emit(global_position, blast_radius, concussion_value, fire_damage)
	get_tree().call_group("mission", "register_explosion", global_position, blast_radius, concussion_value, fire_damage)
	get_tree().call_group("mission", "on_bomb_detonated")

	if flash_light:
		flash_light.visible = true

	await get_tree().create_timer(explosion_duration).timeout
	queue_free()
