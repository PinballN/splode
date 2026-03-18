extends CanvasLayer
class_name FogOfWar

@export var reveal_radius: float = 12.0
@export var ray_count: int = 180
@export var ray_height: float = 1.2
@export var update_interval: float = 0.15
@export var collision_mask: int = 1
@export var occlusion_include_areas: bool = false

@export var polygon_color: Color = Color(1.0, 1.0, 1.0, 0.55)
@export var seen_polygon_color: Color = Color(1.0, 1.0, 1.0, 0.18)
@export var dark_alpha: float = 0.72
@export var debug_monitor: bool = false
## Off by default. Enable when you want line-of-sight (hide map until character views interior; procedural reveal for layout/enemy surprise). Add atmospheric fog separately for environmental effects.
@export var fog_disabled: bool = true

@onready var visible_polygon: Polygon2D = $FogVisiblePolygon
@onready var seen_polygon: Polygon2D = $FogSeenPolygon
@onready var dark_rect: ColorRect = $FogDarkRect

var _player: Node3D
var _camera: Camera3D
var _space_state: PhysicsDirectSpaceState3D
var _timer: float = 0.0
var _last_player_pos: Vector3 = Vector3(INF, INF, INF)
var _force_update := false
var _seen_distances: PackedFloat32Array = PackedFloat32Array()
var _seen_end_positions: PackedVector3Array = PackedVector3Array()
var _seen_points: PackedVector2Array = PackedVector2Array()
var _debug_label: Label
var _fog_updated_this_frame := false
var _debug_enabled: bool = false  # runtime toggle via F3; initial from export
var _visible_material: ShaderMaterial
var _seen_material: ShaderMaterial

const _FOG_POLYGON_SHADER := preload("res://shaders/fog_polygon.gdshader")


func _ready() -> void:
	add_to_group("fog_of_war")
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_camera = get_viewport().get_camera_3d() as Camera3D
	var world: World3D = get_viewport().world_3d
	_space_state = world.direct_space_state if world else null

	_init_seen()
	# Use shader materials so polygon color can't be overwritten by engine (fixes red when updating).
	if visible_polygon:
		_visible_material = ShaderMaterial.new()
		_visible_material.shader = _FOG_POLYGON_SHADER
		_visible_material.set_shader_parameter("draw_color", _FOG_VISIBLE)
		visible_polygon.material = _visible_material
	if seen_polygon:
		_seen_material = ShaderMaterial.new()
		_seen_material.shader = _FOG_POLYGON_SHADER
		_seen_material.set_shader_parameter("draw_color", _FOG_SEEN)
		seen_polygon.material = _seen_material
	_apply_fog_colors()
	call_deferred("_apply_fog_colors")
	visible = not fog_disabled
	_debug_enabled = debug_monitor
	if _debug_enabled:
		_setup_debug_monitor()


const _FOG_VISIBLE := Color(1.0, 1.0, 1.0, 0.55)
const _FOG_SEEN := Color(1.0, 1.0, 1.0, 0.18)


func _apply_fog_colors() -> void:
	if dark_rect:
		dark_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	if _visible_material:
		_visible_material.set_shader_parameter("draw_color", _FOG_VISIBLE)
	if _seen_material:
		_seen_material.set_shader_parameter("draw_color", _FOG_SEEN)


func _init_seen() -> void:
	if not seen_polygon:
		return

	if ray_count <= 0:
		return

	_seen_distances.resize(ray_count)
	_seen_end_positions.resize(ray_count)
	_seen_points.resize(ray_count)
	for i in range(ray_count):
		_seen_distances[i] = -1.0
		_seen_end_positions[i] = Vector3.ZERO
		_seen_points[i] = Vector2.ZERO


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("toggle_fog_debug"):
		_debug_enabled = not _debug_enabled
		if _debug_enabled and _debug_label == null:
			_setup_debug_monitor()
		if _debug_label:
			_debug_label.visible = _debug_enabled

	_fog_updated_this_frame = false
	# Only correct dark rect when wrong. Polygon colors are driven by shader (fog_polygon.gdshader).
	var target_dark := Color(0.0, 0.0, 0.0, 1.0)
	if dark_rect and dark_rect.color != target_dark:
		dark_rect.color = target_dark

	if _debug_enabled and _debug_label:
		_update_debug_monitor()

	_timer += _delta
	if _timer < update_interval:
		return
	_timer = 0.0

	if not _player or not _camera:
		return

	# Update only when player moved (or force_update); pulsing every interval caused red pulse.
	if not _force_update:
		if _player.global_position.distance_squared_to(_last_player_pos) < 0.05 * 0.05:
			return
	_last_player_pos = _player.global_position
	_force_update = false

	_apply_fog_colors()
	_update_visibility_polygon()
	# Re-apply colors next frame; the frame we set .polygon can get a wrong tint (red).
	call_deferred("_apply_fog_colors")
	_fog_updated_this_frame = true


func force_update() -> void:
	_force_update = true


func _setup_debug_monitor() -> void:
	if _debug_label != null:
		return
	_debug_label = Label.new()
	_debug_label.name = "FogDebugMonitor"
	_debug_label.position = Vector2(16.0, 140.0)
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0, 1, 0, 1))
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_debug_label.add_theme_constant_override("outline_size", 4)
	_debug_label.visible = _debug_enabled
	_debug_label.text = "Debug (F3 to toggle)"
	add_child(_debug_label)


func _update_debug_monitor() -> void:
	if not _debug_label:
		return
	var dc: Color = dark_rect.color if dark_rect else Color.BLACK
	var vc: Color = visible_polygon.color if visible_polygon else Color.BLACK
	var sc: Color = seen_polygon.color if seen_polygon else Color.BLACK
	var moving := false
	if _player:
		moving = _player.global_position.distance_squared_to(_last_player_pos) >= 0.0025  # 0.05^2
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== DEBUG (F3 off) ===")
	lines.append("--- Fog ---")
	lines.append("moving: %s  fog_updated: %s" % [moving, _fog_updated_this_frame])
	lines.append("dark_rect  R:%.2f G:%.2f B:%.2f A:%.2f" % [dc.r, dc.g, dc.b, dc.a])
	lines.append("visible    R:%.2f G:%.2f B:%.2f A:%.2f" % [vc.r, vc.g, vc.b, vc.a])
	lines.append("seen       R:%.2f G:%.2f B:%.2f A:%.2f" % [sc.r, sc.g, sc.b, sc.a])
	# Only warn when color is red-tinted (R high and G,B low), not when white (1,1,1).
	var red_tint := (dc.r > 0.5 and dc.g < 0.5 and dc.b < 0.5) or (vc.r > 0.5 and vc.g < 0.5 and vc.b < 0.5) or (sc.r > 0.5 and sc.g < 0.5 and sc.b < 0.5)
	if red_tint:
		lines.append(">>> RED TINT (R high, G/B low) <<<")
	elif dc.r < 0.01 and vc.g > 0.99 and sc.g > 0.99:
		lines.append("(Fog colors OK; red likely blend/env/other layer)")
	# Character (player)
	var p = get_tree().get_first_node_in_group("player")
	if p != null:
		lines.append("--- Character ---")
		if p.has_method("get_health") and p.has_method("get_max_health"):
			lines.append("HP: %.0f / %.0f" % [p.get_health(), p.get_max_health()])
		if p is Node3D:
			var pos: Vector3 = (p as Node3D).global_position
			lines.append("pos: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z])
		if p is CharacterBody3D:
			var vel: Vector3 = (p as CharacterBody3D).velocity
			lines.append("vel: (%.2f, %.2f, %.2f)" % [vel.x, vel.y, vel.z])
	# Material / wall strength (first few wall_damageable)
	var walls = get_tree().get_nodes_in_group("wall_damageable")
	var n = mini(3, walls.size())
	if n > 0:
		lines.append("--- Wall/Material ---")
	for i in range(n):
		var w = walls[i]
		var parts: PackedStringArray = PackedStringArray()
		if w.has_method("get_strength"):
			parts.append("str:%.1f" % w.get_strength())
		if w.has_method("get_crack_level"):
			parts.append("crack:%.2f" % w.get_crack_level())
		if parts.size() > 0:
			lines.append("  [%d] %s" % [i, ", ".join(parts)])
		else:
			lines.append("  [%d] -" % i)
	_debug_label.text = "\n".join(lines)


func _update_visibility_polygon() -> void:
	if not _player or not visible_polygon or not _camera or not _space_state:
		return

	var origin: Vector3 = _player.global_position
	origin.y = ray_height

	var points: PackedVector2Array = PackedVector2Array()
	points.resize(ray_count)

	# We'll accumulate "seen" distance per ray so FoW never shrinks.
	if seen_polygon and _seen_distances.size() != ray_count:
		_init_seen()

	var exclude_rids: Array[RID] = []
	var player_collider := _player as CollisionObject3D
	if player_collider:
		exclude_rids.append(player_collider.get_rid())

	for i: int in range(ray_count):
		var angle: float = TAU * float(i) / float(ray_count)
		var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var from: Vector3 = origin
		var to: Vector3 = origin + dir * reveal_radius

		var remaining_alpha: float = 1.0
		var max_hits: int = 8
		var end_pos: Vector3 = to

		var current_from: Vector3 = from
		for _h in range(max_hits):
			var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(current_from, to)
			params.collision_mask = collision_mask
			params.exclude = exclude_rids
			params.collide_with_areas = occlusion_include_areas

			var hit: Variant = _space_state.intersect_ray(params)
			if not hit:
				end_pos = to
				break

			end_pos = hit.position

			# Material-based transparency: 0 = opaque, 1 = fully transparent.
			var transparency: float = 0.0
			var collider: Object = hit.collider
			if collider != null and collider.has_method("get_transparency"):
				transparency = float(collider.call("get_transparency"))

			# Vision passes proportionally to transparency.
			remaining_alpha *= (1.0 - clampf(transparency, 0.0, 1.0))
			if remaining_alpha <= 0.08:
				break

			# March forward just past the hit and try again.
			current_from = hit.position + dir * 0.05
		# end for hits

		# Convert world position on the ground to screen-space polygon points.
		var screen_pos: Vector2 = _camera.unproject_position(end_pos)
		points[i] = screen_pos

		if seen_polygon:
			var dist: float = origin.distance_to(end_pos)
			if dist > _seen_distances[i]:
				_seen_distances[i] = dist
				_seen_end_positions[i] = end_pos

	visible_polygon.polygon = points
	if seen_polygon:
		# Recompute screen-space points from stored world endpoints.
		for i in range(ray_count):
			if _seen_distances[i] >= 0.0:
				_seen_points[i] = _camera.unproject_position(_seen_end_positions[i])
			else:
				_seen_points[i] = points[i]
		seen_polygon.polygon = _seen_points
	_apply_fog_colors()
