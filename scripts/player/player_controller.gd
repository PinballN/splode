extends CharacterBody3D
class_name PlayerController

signal health_changed(current: float, max: float)
signal died()
signal bomb_planted(bomb: Node)
signal bomb_equipped(bomb_id: StringName)

enum ControlMode {
	HUMAN = 0,
	AI = 1,
	NETWORK = 2
}

@export var max_health: float = 100.0

@export var control_mode: ControlMode = ControlMode.HUMAN
@export var add_to_player_group: bool = true

@export var move_speed: float = 6.0
@export var turn_speed: float = 12.0
@export var bomb_scene: PackedScene
@export var bomb_offset: Vector3 = Vector3(0.0, 0.0, -0.8)

var equipped_bomb_id: StringName = &""

@export var enable_click_to_move: bool = true
@export var click_ground_y: float = 0.0
@export var click_stop_distance: float = 0.35

@export var pickup_interact_distance_m: float = 2.2

# How strongly the player pushes wall-debris rigidbodies when bumping into them.
# Only applies to chunks spawned by WallSurfaceDamage (meta: "wall_chunk").
@export var wall_debris_push_impulse: float = 6.0

var _click_target: Vector3
var _has_click_target := false
var _health: float
var _dead := false

var _body_material: StandardMaterial3D
const _color_healthy := Color(0.95, 0.95, 0.95)
const _color_yellow := Color(1.0, 0.95, 0.35)
const _color_red := Color(0.95, 0.2, 0.15)

var _ai_target: Node3D
@export var ai_stop_distance: float = 0.35

var _ai_offset: Vector3 = Vector3.ZERO
var _ai_goal_position: Vector3 = Vector3.ZERO
var _ai_has_goal_position := false

enum AICommand {
	FOLLOW = 0,
	STAY = 1,
	COME = 2,
	GOTO = 3,
	ESCAPE = 4
}

var _ai_command: AICommand = AICommand.FOLLOW

var _network_direction: Vector3 = Vector3.ZERO
var _has_network_direction := false
var _pending_plant_bomb := false


func set_ai_follow_target(target: Node3D, offset: Vector3 = Vector3.ZERO) -> void:
	_ai_command = AICommand.FOLLOW
	_ai_target = target
	_ai_offset = offset
	_ai_has_goal_position = false


func set_ai_stay() -> void:
	_ai_command = AICommand.STAY
	_ai_has_goal_position = false


func set_ai_come_target(target: Node3D) -> void:
	_ai_command = AICommand.COME
	_ai_target = target
	_ai_offset = Vector3.ZERO
	_ai_has_goal_position = false


func set_ai_goto_position(goal_position: Vector3) -> void:
	_ai_command = AICommand.GOTO
	_ai_goal_position = goal_position
	_ai_has_goal_position = true


func set_ai_escape_target(target: Node3D, offset: Vector3 = Vector3.ZERO) -> void:
	_ai_command = AICommand.ESCAPE
	_ai_target = target
	_ai_offset = offset
	_ai_has_goal_position = false


func set_network_move_direction(direction: Vector3) -> void:
	# Multiplayer hook: a net controller can push movement intent here.
	if direction == Vector3.ZERO:
		_has_network_direction = false
		_network_direction = Vector3.ZERO
	else:
		_has_network_direction = true
		_network_direction = direction


func request_plant_bomb() -> void:
	_pending_plant_bomb = true


func has_click_target() -> bool:
	return _has_click_target


func get_click_target() -> Vector3:
	return _click_target


func _ready() -> void:
	add_to_group("damageable")

	# Only the human-controlled operative drives Fog of War / "player" group logic.
	if add_to_player_group and control_mode == ControlMode.HUMAN:
		add_to_group("player")

	_health = max_health
	_dead = false
	_setup_body_material()
	_update_damage_color()
	emit_signal("health_changed", _health, max_health)


func get_health() -> float:
	return _health


func get_max_health() -> float:
	return max_health


func apply_damage(amount: float) -> void:
	if _dead:
		return
	if amount <= 0.0:
		return

	_health = maxf(_health - amount, 0.0)
	_update_damage_color()
	emit_signal("health_changed", _health, max_health)
	if _health <= 0.0:
		_die()


func apply_explosion_damage(concussion_value: float, fire_damage: float, damage_multiplier: float = 1.0) -> void:
	# concussion = blunt impact, fire = burn; damage_multiplier from cover (1.0 = no cover, <1 = behind wall/object).
	var raw := maxf(fire_damage * 2.0 + concussion_value * 10.0, 0.0)
	var damage := raw * clampf(damage_multiplier, 0.0, 1.0)
	apply_damage(damage)


func _setup_body_material() -> void:
	var mesh_inst: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh_inst == null:
		return
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.85
	_body_material.metallic = 0.0
	mesh_inst.material_override = _body_material


func _update_damage_color() -> void:
	if _body_material == null:
		return
	var ratio: float = _health / max_health if max_health > 0.0 else 1.0
	# Full health = neutral, mid = yellow, low = red
	if ratio > 0.5:
		_body_material.albedo_color = _color_healthy.lerp(_color_yellow, (1.0 - ratio) * 2.0)
	else:
		_body_material.albedo_color = _color_yellow.lerp(_color_red, 1.0 - ratio * 2.0)


func _die() -> void:
	_dead = true
	set_physics_process(false)
	emit_signal("died")


func _physics_process(_delta: float) -> void:
	if _dead:
		return
	var direction := Vector3.ZERO

	match control_mode:
		ControlMode.HUMAN:
			# Keyboard movement (WASD) has priority over click-to-move.
			var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			direction = Vector3(input_vector.x, 0.0, input_vector.y)

			if direction.length() > 1.0:
				direction = direction.normalized()

			if direction != Vector3.ZERO:
				velocity.x = direction.x * move_speed
				velocity.z = direction.z * move_speed
				velocity.y = 0.0
			else:
				# Click-to-move (project mouse ray onto the ground plane).
				if enable_click_to_move and _has_click_target:
					var to_target := _click_target - global_position
					to_target.y = 0.0

					if to_target.length() <= click_stop_distance:
						_has_click_target = false
						velocity.x = 0.0
						velocity.z = 0.0
						velocity.y = 0.0
						direction = Vector3.ZERO
					else:
						direction = to_target.normalized()
						velocity.x = direction.x * move_speed
						velocity.z = direction.z * move_speed
						velocity.y = 0.0
				else:
					velocity.x = 0.0
					velocity.z = 0.0
					velocity.y = 0.0

		ControlMode.AI:
			var desired := Vector3.ZERO
			match _ai_command:
				AICommand.FOLLOW:
					if _ai_target:
						desired = _ai_target.global_position + _ai_offset
				AICommand.COME:
					if _ai_target:
						desired = _ai_target.global_position
				AICommand.STAY:
					direction = Vector3.ZERO
				AICommand.GOTO:
					if _ai_has_goal_position:
						desired = _ai_goal_position
				AICommand.ESCAPE:
					if _ai_target:
						desired = _ai_target.global_position + _ai_offset

			if direction == Vector3.ZERO and _ai_command != AICommand.STAY:
				desired.y = global_position.y
				var to_target := desired - global_position
				to_target.y = 0.0
				if to_target.length() <= ai_stop_distance:
					direction = Vector3.ZERO
				else:
					direction = to_target.normalized()
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			velocity.y = 0.0

		ControlMode.NETWORK:
			if _has_network_direction:
				var dir := _network_direction
				dir.y = 0.0
				if dir.length() > 1.0:
					dir = dir.normalized()
				direction = dir
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			velocity.y = 0.0

	move_and_slide()

	# Push wall-debris out of the way when bumping into it.
	# PlayerController is a kinematic CharacterBody3D, so by default it won't
	# impart momentum to rigid bodies. We apply a small impulse ourselves
	# to the rigid bodies created by WallSurfaceDamage chunks.
	if wall_debris_push_impulse > 0.0:
		var speed: float = velocity.length()
		if speed > 0.01:
			for i in range(get_slide_collision_count()):
				var col = get_slide_collision(i)
				var collider = col.get_collider()
				if collider is RigidBody3D and (collider as Node).has_meta("wall_chunk"):
					var rb: RigidBody3D = collider as RigidBody3D
					var n: Vector3 = col.get_normal()
					if n != Vector3.ZERO:
						var push_dir: Vector3 = -n
						# Use speed so faster movement pushes more.
						var impulse: Vector3 = push_dir * wall_debris_push_impulse * clampf(speed, 0.0, move_speed)
						var local_hit_pos: Vector3 = rb.to_local(col.get_position())
						rb.apply_impulse(impulse, local_hit_pos)

	if direction != Vector3.ZERO:
		look_at(global_position + direction, Vector3.UP)

	if control_mode == ControlMode.HUMAN:
		if Input.is_action_just_pressed("plant_bomb"):
			# Context-sensitive `E`:
			# - near a bomb pickup: equip
			# - otherwise: plant the currently equipped bomb
			if not try_pickup_bomb():
				plant_bomb()
		if Input.is_action_just_pressed("restart"):
			get_tree().reload_current_scene()
	else:
		if _pending_plant_bomb:
			_pending_plant_bomb = false
			plant_bomb()


func plant_bomb() -> void:
	if bomb_scene == null:
		return

	var bomb := bomb_scene.instantiate()
	get_tree().current_scene.add_child(bomb)
	bomb.global_position = global_position + (-global_transform.basis.z * absf(bomb_offset.z))
	bomb_planted.emit(bomb)


func try_pickup_bomb() -> bool:
	if control_mode != ControlMode.HUMAN:
		return false

	var best_pickup: BombPickup = null
	var best_dist: float = pickup_interact_distance_m

	for n in get_tree().get_nodes_in_group("bomb_pickups"):
		if not is_instance_valid(n):
			continue
		var p: BombPickup = n as BombPickup
		if p == null:
			continue
		var d := global_position.distance_to(p.global_position)
		if d <= best_dist:
			best_dist = d
			best_pickup = p

	if best_pickup == null:
		return false

	# If we're already equipped with the same bomb type, allow planting.
	if equipped_bomb_id == best_pickup.bomb_id and bomb_scene != null:
		return false

	var scene := best_pickup.get_bomb_scene()
	if scene == null:
		return false

	bomb_scene = scene
	equipped_bomb_id = best_pickup.bomb_id
	bomb_equipped.emit(equipped_bomb_id)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if control_mode != ControlMode.HUMAN:
		return
	if not enable_click_to_move:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_set_click_target(mb.position)


func _set_click_target(screen_pos: Vector2) -> void:
	var cam := get_viewport().get_camera_3d() as Camera3D
	if cam == null:
		return

	var ray_origin := cam.project_ray_origin(screen_pos)
	var ray_dir := cam.project_ray_normal(screen_pos)

	# Intersect the ray with the horizontal plane: y = click_ground_y.
	if absf(ray_dir.y) < 0.00001:
		return
	var t := (click_ground_y - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return

	var hit := ray_origin + ray_dir * t
	_click_target = Vector3(hit.x, global_position.y, hit.z)
	_has_click_target = true

	# Force fog to refresh next frame so no stale tint or shape lingers after click.
	var fog := get_tree().get_first_node_in_group("fog_of_war")
	if fog and fog.has_method("force_update"):
		fog.force_update()

