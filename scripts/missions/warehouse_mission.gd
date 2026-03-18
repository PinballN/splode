extends Node3D
class_name WarehouseMission

@onready var player: PlayerController = $Player
@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var camera_rig: CameraFollow = $CameraRig
@onready var hud: HUD = $HUD
@onready var alarm_light: OmniLight3D = $AlarmLight
@onready var start_zone: Area3D = $StartZone
@onready var escape_zone: Area3D = $EscapeZone
@onready var target_crate_stack: CrateStack = get_node_or_null("CrateStack") as CrateStack

@export var internal_wall_seed: int = 0
@export var internal_wall_count: int = 3
@export var crate_spawn_x_min: float = -10.0
@export var crate_spawn_x_max: float = 10.0
@export var crate_spawn_z_min: float = -10.0
@export var crate_spawn_z_max: float = 10.0
@export var crate_spawn_y: float = 0.9
@export var initial_loadout_id: StringName = &"default"
@export var facility_layout_id: StringName = &"warehouse_internal_v1"
@export var exterior_wall_segments: int = 4
@export var ai_agent_count: int = 0
@export var operative_scene: PackedScene = preload("res://scenes/player/player.tscn")

var alarm_active := false
var bomb_detonated := false
var mission_won := false
var _target_crate_destroyed := false
var _player_dead := false
var _squad: Array[PlayerController] = []

var _internal_wall_container: Node3D
var _last_concussion_value := 0.15


func _ready() -> void:
	_ensure_default_input()
	add_to_group("mission")

	_target_crate_destroyed = false
	_player_dead = false
	_squad.clear()

	if player:
		_squad.append(player)

		player.global_position = player_spawn.global_position
		player.control_mode = PlayerController.ControlMode.HUMAN
		player.add_to_player_group = true

		var bomb_scene: PackedScene = null

		# Cortex Command-style "loadout" surface: pick which bomb to spawn from data.
		var bomb_id: StringName = &"test_incendiary"
		if initial_loadout_id != &"":
			var loadout: Dictionary = LoadoutRegistry.get_loadout(initial_loadout_id)
			if loadout.has("bomb_id"):
				bomb_id = StringName(str(loadout["bomb_id"]))

		var bomb_def: Dictionary = BombRegistry.get_bomb(bomb_id)
		var scene_path_var: Variant = bomb_def.get("scene_path", "")
		if typeof(scene_path_var) == TYPE_STRING and String(scene_path_var) != "":
			bomb_scene = load(String(scene_path_var)) as PackedScene

		if bomb_scene == null:
			bomb_scene = preload("res://scenes/props/incendiary_bomb.tscn")

		player.bomb_scene = bomb_scene
		player.equipped_bomb_id = bomb_id

		# HUD + death handling (Cortex Command-like HP stat).
		if hud:
			hud.set_health(player.get_health(), player.get_max_health())
		player.health_changed.connect(_on_player_health_changed)
		player.died.connect(_on_player_died)
		player.bomb_equipped.connect(_on_bomb_equipped)

		_spawn_ai_squadmates()

	if camera_rig and player:
		camera_rig.target = player

	if hud:
		hud.set_objective("Destroy the target crate stack, then escape.")
		hud.set_controls("Move: WASD or Left Click | Pick/Plant Bomb: E | Restart: R | Squad: 1 Stay, 2 Come, 3 Goto, 4 Escape")
		hud.set_alarm(false)
		hud.set_status("Return to the green escape zone after detonation.")
		if player:
			hud.set_equipped(_equipped_display_name(player.equipped_bomb_id))

	if alarm_light:
		alarm_light.visible = false

	if escape_zone:
		escape_zone.body_entered.connect(_on_escape_zone_body_entered)

	_ensure_floor_collision()
	_spawn_internal_walls()
	_place_target_crate_random()
	_attach_exterior_walls_damageable()
	_spawn_entrance_pillars()
	_spawn_bomb_pickups()


func _spawn_ai_squadmates() -> void:
	if operative_scene == null:
		return

	var count: int = clampi(ai_agent_count, 0, 3)
	if count <= 0:
		return

	# Simple fixed formation offsets relative to the human player.
	var offsets: Array[Vector3] = [
		Vector3(-1.6, 0.0, 1.2),
		Vector3(1.6, 0.0, 1.2),
		Vector3(0.0, 0.0, -1.8),
	]

	for i in range(count):
		var agent := operative_scene.instantiate() as PlayerController
		if agent == null:
			continue

		# Configure as AI.
		agent.control_mode = PlayerController.ControlMode.AI
		agent.add_to_player_group = false
		agent.enable_click_to_move = false

		var offset := offsets[i] if i < offsets.size() else Vector3.ZERO
		agent.global_position = player.global_position + offset
		add_child(agent)

		agent.set_ai_follow_target(player, offset)

		_squad.append(agent)


func on_security_spotted(_camera: Node, _body: Node) -> void:
	trigger_alarm("Security camera spotted you!")


func register_explosion(origin: Vector3, radius: float, concussion_value: float, fire_damage: float) -> void:
	_last_concussion_value = concussion_value
	for crate in get_tree().get_nodes_in_group("crate_stack"):
		if crate is CrateStack and crate.global_position.distance_to(origin) <= radius:
			crate.ignite(fire_damage)
			# Win requires the target crate stack to actually be affected.
			if target_crate_stack != null:
				if crate == target_crate_stack:
					_target_crate_destroyed = true
			else:
				_target_crate_destroyed = true

	for b in get_tree().get_nodes_in_group("breakables"):
		if b is Node3D and b.global_position.distance_to(origin) <= radius:
			if b.has_method("apply_explosion"):
				b.call("apply_explosion", concussion_value, fire_damage, origin)

	# Visual progressive cracking for internal walls.
	for w in get_tree().get_nodes_in_group("wall_damageable"):
		if w is Node3D:
			var dist: float = w.global_position.distance_to(origin)
			if dist <= radius:
				var t := 1.0 - clampf(dist / radius, 0.0, 1.0)
				# Scale using both concussion and fire so different damage types can show visibly.
				var raw := concussion_value * 0.6 + fire_damage * 0.25
				var damage_amount := raw * t
				if w.has_method("apply_surface_damage"):
					w.call("apply_surface_damage", damage_amount, origin)

	# Damage the player if caught in the blast; reduce by cover (walls/objects between blast and player).
	if player and not _player_dead:
		if player.global_position.distance_to(origin) <= radius:
			var mult: float = _get_cover_damage_multiplier(origin, player)
			player.apply_explosion_damage(concussion_value, fire_damage, mult)

	# Recompute fog immediately since occluders may have changed (glass shatter).
	get_tree().call_group("fog_of_war", "force_update")

	# Damage squadmates caught in the blast (with cover).
	for s in _squad:
		if is_instance_valid(s) and not _player_dead:
			if s.global_position.distance_to(origin) <= radius:
				var mult: float = _get_cover_damage_multiplier(origin, s)
				s.apply_explosion_damage(concussion_value, fire_damage, mult)

	trigger_alarm("Explosion detected!")


func trigger_alarm(message: String) -> void:
	alarm_active = true

	if hud:
		hud.set_alarm(true)
		hud.set_status(message)

	if alarm_light:
		# Use a soft warm light so the scene isn’t washed red when alarm is on.
		alarm_light.visible = false


func request_restart() -> void:
	get_tree().reload_current_scene()


func on_bomb_armed(fuse_time: float) -> void:
	if hud:
		hud.set_bomb_countdown_seconds(fuse_time, true)


func on_bomb_countdown(time_left: float) -> void:
	if hud:
		hud.set_bomb_countdown_seconds(time_left, time_left >= 0.0)


func request_camera_shake(duration: float = 0.4, magnitude: float = 0.55) -> void:
	if camera_rig and camera_rig.has_method("start_concussion_shake"):
		camera_rig.start_concussion_shake(duration, magnitude, 22.0)


func on_bomb_detonated() -> void:
	if hud:
		hud.set_bomb_countdown_seconds(0.0, false)

	# Add a short concussion delay so the player sees the blast first.
	if camera_rig and camera_rig.has_method("start_concussion_shake"):
		await get_tree().create_timer(0.12).timeout
		# Low concussion bombs should feel weaker; high concussion bombs feel more violent.
		var magnitude := clampf(0.15 + _last_concussion_value * 1.2, 0.05, 0.9)
		var duration := clampf(0.18 + _last_concussion_value * 0.25, 0.12, 0.6)
		camera_rig.start_concussion_shake(duration, magnitude, 28.0)

	bomb_detonated = true

	if hud:
		hud.set_objective("Bomb detonated. Return to the green zone.")
		hud.set_status("Get back to the safe zone!")


func _on_escape_zone_body_entered(body: Node) -> void:
	if mission_won or _player_dead:
		return

	if body == player and bomb_detonated and _target_crate_destroyed:
		mission_won = true
		if hud:
			hud.set_alarm(false)
			hud.set_status("MISSION COMPLETE! Safe extraction.")
		await get_tree().create_timer(2.0).timeout
		request_restart()


func _on_player_health_changed(current: float, _max: float) -> void:
	if hud:
		hud.set_health(current, _max)


func _on_player_died() -> void:
	if _player_dead:
		return
	_player_dead = true
	if hud:
		hud.set_alarm(true)
		hud.set_status("MISSION FAILED: Operative down.")
	await get_tree().create_timer(2.0).timeout
	request_restart()


func _on_bomb_equipped(bomb_id: StringName) -> void:
	if hud:
		hud.set_equipped(_equipped_display_name(bomb_id))


func _equipped_display_name(bomb_id: StringName) -> String:
	if bomb_id == &"":
		return ""
	var bomb_def: Dictionary = BombRegistry.get_bomb(bomb_id)
	var name_val: Variant = bomb_def.get("name", "")
	if typeof(name_val) == TYPE_STRING and String(name_val).strip_edges().length() > 0:
		return String(name_val).strip_edges()
	var s: String = String(bomb_id).replace("_", " ")
	if s.is_empty():
		return ""
	var parts: PackedStringArray = s.split(" ", false)
	for i in parts.size():
		if parts[i].length() > 0:
			parts[i] = parts[i][0].to_upper() + parts[i].substr(1).to_lower()
	return " ".join(parts)


func _ensure_default_input() -> void:
	_ensure_action("move_forward", [Key.KEY_W, Key.KEY_UP])
	_ensure_action("move_back", [Key.KEY_S, Key.KEY_DOWN])
	_ensure_action("move_left", [Key.KEY_A, Key.KEY_LEFT])
	_ensure_action("move_right", [Key.KEY_D, Key.KEY_RIGHT])
	_ensure_action("plant_bomb", [Key.KEY_E])
	_ensure_action("restart", [Key.KEY_R])
	# Basic squad commands (AI-only).
	_ensure_action("squad_stay", [Key.KEY_1])
	_ensure_action("squad_come", [Key.KEY_2])
	_ensure_action("squad_goto", [Key.KEY_3])
	_ensure_action("squad_escape", [Key.KEY_4])
	_ensure_action("toggle_fog_debug", [Key.KEY_F3])


func _process(_delta: float) -> void:
	if mission_won or _player_dead:
		return
	if player == null:
		return

	# Only react when we actually have AI agents.
	var has_ai := false
	for s in _squad:
		if s != player and s.control_mode == PlayerController.ControlMode.AI:
			has_ai = true
			break
	if not has_ai:
		return

	if Input.is_action_just_pressed("squad_stay"):
		for s in _squad:
			if s != player and s.control_mode == PlayerController.ControlMode.AI:
				s.set_ai_stay()

	elif Input.is_action_just_pressed("squad_come"):
		for s in _squad:
			if s != player and s.control_mode == PlayerController.ControlMode.AI:
				s.set_ai_come_target(player)

	elif Input.is_action_just_pressed("squad_goto"):
		var pos: Vector3 = player.global_position
		if player.has_click_target():
			pos = player.get_click_target()

		for s in _squad:
			if s != player and s.control_mode == PlayerController.ControlMode.AI:
				s.set_ai_goto_position(pos)

	elif Input.is_action_just_pressed("squad_escape"):
		if escape_zone == null:
			return
		for s in _squad:
			if s != player and s.control_mode == PlayerController.ControlMode.AI:
				s.set_ai_escape_target(escape_zone)


func _ensure_action(action_name: StringName, keys: Array[Key]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	if InputMap.action_get_events(action_name).is_empty():
		for keycode in keys:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			event.keycode = keycode
			InputMap.action_add_event(action_name, event)


func _ensure_floor_collision() -> void:
	# So wall debris and physics objects land on the floor instead of falling through.
	if get_node_or_null("FloorBody") != null:
		return
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(24.0, 0.2, 24.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	floor_body.add_child(col)
	add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.1, 0.0)


func _place_target_crate_random() -> void:
	if target_crate_stack == null:
		return
	var rng := RandomNumberGenerator.new()
	if internal_wall_seed == 0:
		rng.seed = Time.get_ticks_msec()
	else:
		rng.seed = internal_wall_seed
	# Use a few randf calls so crate position doesn't match first wall template index
	rng.randf()
	rng.randf()
	var x_min: float = min(crate_spawn_x_min, crate_spawn_x_max)
	var x_max: float = max(crate_spawn_x_min, crate_spawn_x_max)
	var z_min: float = min(crate_spawn_z_min, crate_spawn_z_max)
	var z_max: float = max(crate_spawn_z_min, crate_spawn_z_max)
	var x: float = rng.randf_range(x_min, x_max)
	var z: float = rng.randf_range(z_min, z_max)
	target_crate_stack.global_position = Vector3(x, crate_spawn_y, z)


func _spawn_internal_walls() -> void:
	if _internal_wall_container:
		_internal_wall_container.queue_free()

	_internal_wall_container = Node3D.new()
	_internal_wall_container.name = "InternalWalls"
	add_child(_internal_wall_container)

	var rng := RandomNumberGenerator.new()
	if internal_wall_seed == 0:
		rng.seed = Time.get_ticks_msec()
	else:
		rng.seed = internal_wall_seed

	var layout: Dictionary = {}
	if facility_layout_id != &"":
		layout = FacilityLayoutRegistry.get_layout(facility_layout_id)

	# Data-driven templates (Cortex Command-like "scenes/levels" expansion surface).
	var templates: Array[Dictionary] = []
	var layout_templates_var: Variant = layout.get("templates", [])
	if typeof(layout_templates_var) == TYPE_ARRAY:
		for elem in layout_templates_var as Array:
			if typeof(elem) == TYPE_DICTIONARY:
				templates.append(elem as Dictionary)

	# Fallback: original hardcoded POC templates.
	if templates.is_empty():
		# Simple templates: a mix of vertical and horizontal interior walls.
		# Coordinates are in the same x/z space as the outer room.
		templates = [
			{"pos": Vector3(-4.5, 2.0, -1.5), "size": Vector3(0.6, 4.0, 6.0)},  # vertical
			{"pos": Vector3(4.5, 2.0, -1.5), "size": Vector3(0.6, 4.0, 6.0)},   # vertical
			{"pos": Vector3(0.0, 2.0, 3.8), "size": Vector3(6.0, 4.0, 0.6)},     # horizontal
			{"pos": Vector3(0.0, 2.0, -6.0), "size": Vector3(6.0, 4.0, 0.6)},    # horizontal
			{"pos": Vector3(-2.0, 2.0, 1.0), "size": Vector3(3.0, 4.0, 0.6)},     # small horizontal
		]

	internal_wall_count = clampi(internal_wall_count, 1, templates.size())

	var chosen: Array[int] = []
	while chosen.size() < internal_wall_count:
		var idx := rng.randi_range(0, templates.size() - 1)
		if not chosen.has(idx):
			chosen.append(idx)

	for idx in chosen:
		var t := templates[idx]
		var pos: Vector3 = _coerce_vec3(t.get("pos", []))
		var size: Vector3 = _coerce_vec3(t.get("size", []))

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		# Avoid `global_position` while the node is not yet in the scene tree.
		# `_internal_wall_container` is already parented, so convert to local space.
		if _internal_wall_container:
			body.position = _internal_wall_container.to_local(pos)
		else:
			body.position = pos

		var shape := BoxShape3D.new()
		shape.size = size

		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)

		# Visual mesh so internal walls are readable.
		var mesh_inst := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh_inst.mesh = mesh
		body.add_child(mesh_inst)

		# Add material + basic LOS blocking behavior.
		var material_ids: Array[StringName] = [
			&"reinforced_concrete",
			&"concrete",
			&"wood",
			&"metal",
			&"glass",
		]

		var layout_material_ids_var: Variant = layout.get("material_ids", [])
		if typeof(layout_material_ids_var) == TYPE_ARRAY and (layout_material_ids_var as Array).size() > 0:
			material_ids.clear()
			for m in layout_material_ids_var as Array:
				material_ids.append(StringName(str(m)))

		var mat_id: StringName = material_ids[rng.randi_range(0, material_ids.size() - 1)]
		if t.has("material_id"):
			mat_id = StringName(str(t["material_id"]))
		elif t.has("material_ids"):
			var pool_var: Variant = t["material_ids"]
			if typeof(pool_var) == TYPE_ARRAY and (pool_var as Array).size() > 0:
				var pool: Array[StringName] = []
				for pm in pool_var as Array:
					pool.append(StringName(str(pm)))
				if not pool.is_empty():
					mat_id = pool[rng.randi_range(0, pool.size() - 1)]

		var mb: MaterialBlocker = preload("res://scripts/materials/material_blocker.gd").new() as MaterialBlocker
		if mb:
			mb.material_id = mat_id
			body.add_child(mb)

		# Add visible progressive surface cracking (Cortex-like "damage readability").
		# This is separate from destruction/shattering; it only affects visuals.
		var material_stats: Dictionary = MaterialRegistry.get_material(mat_id)
		var strength: float = float(material_stats.get("strength", 60.0))

		var base_color := Color(0.72, 0.72, 0.72, 1.0)
		var crack_color := Color(0.06, 0.06, 0.06, 1.0)
		match mat_id:
			&"reinforced_concrete":
				base_color = Color(0.55, 0.55, 0.58, 1.0)
			&"concrete":
				base_color = Color(0.72, 0.72, 0.72, 1.0)
			&"wood":
				base_color = Color(0.42, 0.28, 0.14, 1.0)
				crack_color = Color(0.08, 0.06, 0.03, 1.0)
			&"metal":
				base_color = Color(0.6, 0.6, 0.62, 1.0)
				crack_color = Color(0.09, 0.09, 0.09, 1.0)
			&"glass":
				base_color = Color(0.55, 0.8, 1.0, 1.0)
				crack_color = Color(0.2, 0.25, 0.35, 1.0)

		var wall_dmg: WallSurfaceDamage = preload("res://scripts/destruction/wall_surface_damage.gd").new() as WallSurfaceDamage
		if wall_dmg:
			body.add_child(wall_dmg)
			wall_dmg.setup(mesh_inst, strength, base_color, crack_color, mat_id)

		_internal_wall_container.add_child(body)


func _spawn_bomb_pickups() -> void:
	# Simple "Cortex Command-style loadout surface": stand near a pickup and press E.
	var bomb_pickup_script: Script = preload("res://scripts/props/bomb_pickup.gd")

	# Place next to the start so you can swap immediately.
	var base_pos := player_spawn.global_position
	var pickup_y := base_pos.y - 0.45
	var left_pos := Vector3(base_pos.x - 1.2, pickup_y, base_pos.z - 0.4)
	var right_pos := Vector3(base_pos.x + 1.2, pickup_y, base_pos.z - 0.4)

	var pickup_defs: Array[Dictionary] = [
		{"id": &"test_incendiary", "pos": left_pos, "color": Color(1.0, 0.3, 0.3, 1.0)},
		{"id": &"test_he_sticky_breach", "pos": right_pos, "color": Color(0.2, 0.85, 0.25, 1.0)},
	]

	for d in pickup_defs:
		var pickup := bomb_pickup_script.new() as BombPickup
		pickup.bomb_id = d["id"] as StringName

		# Lightweight visual marker.
		var mi := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.14
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = (d["color"] as Color)
		mat.roughness = 0.95
		mi.material_override = mat
		pickup.add_child(mi)

		add_child(pickup)
		# Set transform only after the node is in the scene tree.
		pickup.global_position = d["pos"] as Vector3


func _attach_exterior_walls_damageable() -> void:
	# Exterior walls: subdivide into segments so one breach creates a hole, not full destroy.
	var wall_dmg_script := preload("res://scripts/destruction/wall_surface_damage.gd")
	var material_blocker_script := preload("res://scripts/materials/material_blocker.gd")

	# Full walls (subdivided into segments). Window frame pieces use segments: 1 (no subdivision).
	var exterior: Array[Dictionary] = [
		{"body": "NorthWallBody", "mesh": "NorthWall"},
		{"body": "SouthWallRightBody", "mesh": "SouthWallRightSeg"},
		{"body": "WestWallBody", "mesh": "WestWall"},
		{"body": "EastWallBody", "mesh": "EastWall"},
		{"body": "SouthWallLeftPillarDoorLeftBody", "mesh": "SouthWallLeftPillarDoorLeft", "segments": 1},
		{"body": "SouthWallLeftPillarDoorRightBody", "mesh": "SouthWallLeftPillarDoorRight", "segments": 1},
		{"body": "SouthWallDoorLintelBody", "mesh": "SouthWallDoorLintel", "segments": 1},
		{"body": "SouthWallLeftPillarAboveBody", "mesh": "SouthWallLeftPillarAbove", "segments": 1},
		{"body": "SouthWallSillBody", "mesh": "SouthWallSill", "segments": 1},
		{"body": "SouthWallLintelBody", "mesh": "SouthWallLintel", "segments": 1},
		{"body": "SouthWallRightPillarBelowBody", "mesh": "SouthWallRightPillarBelow", "segments": 1},
		{"body": "SouthWallRightPillarAboveBody", "mesh": "SouthWallRightPillarAbove", "segments": 1},
	]

	for e in exterior:
		var body_node := get_node_or_null(e["body"] as String) as StaticBody3D
		if body_node == null:
			continue
		var mesh_node := get_node_or_null(e["mesh"] as String) as MeshInstance3D
		if mesh_node == null:
			continue

		var mat_id: StringName = &"concrete"
		for prop in body_node.get_property_list():
			if String(prop.name) == "material_id":
				var mid: Variant = body_node.get("material_id")
				if mid != null:
					mat_id = StringName(str(mid))
				break

		var use_segments: int = int(e.get("segments", exterior_wall_segments))
		var strength: float = 60.0
		if body_node.has_method("get_strength"):
			strength = float(body_node.call("get_strength"))
		var base_color: Color = _wall_base_color(mat_id)
		var crack_color: Color = _wall_crack_color(mat_id)

		if use_segments <= 1:
			# Window frame etc.: attach damage to existing body/mesh, no subdivision
			var wall_dmg: WallSurfaceDamage = wall_dmg_script.new() as WallSurfaceDamage
			if wall_dmg:
				body_node.add_child(wall_dmg)
				wall_dmg.setup(mesh_node, strength, base_color, crack_color, mat_id)
			continue

		var seg_count: int = clampi(use_segments, 2, 8)
		var wall_size: Vector3 = Vector3(2.0, 2.0, 0.5)
		if mesh_node.mesh is BoxMesh:
			wall_size = (mesh_node.mesh as BoxMesh).size

		var along_x: bool = wall_size.x >= wall_size.z
		var segment_size: Vector3
		var along_axis: Vector3
		var seg_length: float
		if along_x:
			seg_length = wall_size.x / float(seg_count)
			segment_size = Vector3(seg_length, wall_size.y, wall_size.z)
			along_axis = body_node.global_transform.basis.x
		else:
			seg_length = wall_size.z / float(seg_count)
			segment_size = Vector3(wall_size.x, wall_size.y, seg_length)
			along_axis = body_node.global_transform.basis.z

		var wall_center: Vector3 = body_node.global_position

		body_node.collision_layer = 0
		body_node.collision_mask = 0
		var orig_col: CollisionShape3D = body_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if orig_col:
			orig_col.disabled = true
		mesh_node.visible = false

		for i in range(seg_count):
			var offset_dist: float = (float(i) - (seg_count - 1) * 0.5) * seg_length
			var seg_center: Vector3 = wall_center + along_axis * offset_dist

			var seg_body: StaticBody3D = StaticBody3D.new()
			seg_body.name = str(body_node.name, "Seg", i)
			seg_body.collision_layer = 1
			seg_body.collision_mask = 1

			var shape: BoxShape3D = BoxShape3D.new()
			shape.size = segment_size
			var col: CollisionShape3D = CollisionShape3D.new()
			col.shape = shape
			seg_body.add_child(col)

			var seg_mesh_inst: MeshInstance3D = MeshInstance3D.new()
			var box: BoxMesh = BoxMesh.new()
			box.size = segment_size
			seg_mesh_inst.mesh = box
			seg_body.add_child(seg_mesh_inst)

			var mb: MaterialBlocker = material_blocker_script.new() as MaterialBlocker
			if mb:
				mb.material_id = mat_id
				seg_body.add_child(mb)

			var wall_dmg: WallSurfaceDamage = wall_dmg_script.new() as WallSurfaceDamage
			if wall_dmg:
				seg_body.add_child(wall_dmg)
				wall_dmg.setup(seg_mesh_inst, strength, base_color, crack_color, mat_id)

			add_child(seg_body)
			seg_body.global_position = seg_center
			seg_body.global_transform.basis = body_node.global_transform.basis


func _spawn_entrance_pillars() -> void:
	# Reinforced concrete pillar row outside south entrance to deter vehicles.
	var wall_dmg_script := preload("res://scripts/destruction/wall_surface_damage.gd")
	var material_blocker_script := preload("res://scripts/materials/material_blocker.gd")
	var mat_id: StringName = &"reinforced_concrete"
	var strength: float = 90.0
	var mat_dict: Dictionary = MaterialRegistry.get_material(mat_id)
	if mat_dict.has("strength"):
		strength = float(mat_dict["strength"])
	var base_color: Color = _wall_base_color(mat_id)
	var crack_color: Color = _wall_crack_color(mat_id)

	var pillar_radius: float = 0.25
	var pillar_height: float = 1.2
	var south_z: float = 13.5
	var pillar_x_positions: Array[float] = [-13.0, -11.0, -7.0, -4.0, -1.0, 2.0, 5.0, 8.0]

	for x in pillar_x_positions:
		var seg_body: StaticBody3D = StaticBody3D.new()
		seg_body.name = "EntrancePillar_%d" % int(x)
		seg_body.collision_layer = 1
		seg_body.collision_mask = 1

		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.radius = pillar_radius
		shape.height = pillar_height
		var col: CollisionShape3D = CollisionShape3D.new()
		col.shape = shape
		seg_body.add_child(col)

		var seg_mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = pillar_radius
		cyl.bottom_radius = pillar_radius
		cyl.height = pillar_height
		seg_mesh_inst.mesh = cyl
		seg_body.add_child(seg_mesh_inst)

		var mb: MaterialBlocker = material_blocker_script.new() as MaterialBlocker
		if mb:
			mb.material_id = mat_id
			seg_body.add_child(mb)

		var wall_dmg: WallSurfaceDamage = wall_dmg_script.new() as WallSurfaceDamage
		if wall_dmg:
			seg_body.add_child(wall_dmg)
			wall_dmg.setup(seg_mesh_inst, strength, base_color, crack_color, mat_id)

		add_child(seg_body)
		seg_body.global_position = Vector3(x, pillar_height * 0.5, south_z)


func _wall_base_color(mat_id: StringName) -> Color:
	match mat_id:
		&"reinforced_concrete": return Color(0.55, 0.55, 0.58, 1.0)
		&"wood": return Color(0.42, 0.28, 0.14, 1.0)
		&"metal": return Color(0.6, 0.6, 0.62, 1.0)
		&"glass": return Color(0.55, 0.8, 1.0, 1.0)
	return Color(0.72, 0.72, 0.72, 1.0)


func _wall_crack_color(mat_id: StringName) -> Color:
	match mat_id:
		&"wood": return Color(0.08, 0.06, 0.03, 1.0)
		&"metal": return Color(0.09, 0.09, 0.09, 1.0)
		&"glass": return Color(0.2, 0.25, 0.35, 1.0)
	return Color(0.06, 0.06, 0.06, 1.0)


func _get_cover_damage_multiplier(explosion_origin: Vector3, target: Node3D) -> float:
	# Raycast from explosion to target; if we hit cover (wall/object) before target, reduce damage by cover strength.
	var space_state: PhysicsDirectSpaceState3D = target.get_world_3d().direct_space_state
	if space_state == null:
		return 1.0
	var to_target: Vector3 = (target.global_position + Vector3(0.0, 0.6, 0.0)) - explosion_origin
	var dist: float = to_target.length()
	if dist < 0.1:
		return 1.0
	var query := PhysicsRayQueryParameters3D.create(explosion_origin, explosion_origin + to_target)
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	var collider: Object = hit.get("collider", null)
	if collider == null:
		return 1.0
	# If we hit the target (or a child of target), no cover.
	var hit_node: Node = collider as Node
	if hit_node != null and (hit_node == target or target.is_ancestor_of(hit_node)):
		return 1.0
	# Hit something else = cover. Strength reduces damage; some always gets through.
	var strength: float = _get_cover_strength(hit_node)
	# damage_mult = 1 - (0.0..0.85) based on strength; e.g. strength 100 -> 15% damage, strength 0 -> 100% damage
	var reduction: float = minf(0.85, strength / 100.0 * 0.85)
	return 1.0 - reduction


func _get_cover_strength(node: Node) -> float:
	if node == null:
		return 0.0
	if node.has_method("get_strength"):
		return float(node.call("get_strength"))
	for c in node.get_children():
		if c.has_method("get_strength"):
			return float(c.call("get_strength"))
	return 0.0


func _coerce_vec3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_VECTOR3:
		return v as Vector3
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v as Array
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
