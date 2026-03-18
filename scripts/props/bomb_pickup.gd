extends Node3D
class_name BombPickup

signal equipped(bomb_id: StringName)

@export var bomb_id: StringName = &"test_incendiary"
@export var interact_distance_m: float = 2.2

var _bomb_scene: PackedScene


func _ready() -> void:
	add_to_group("bomb_pickups")

	var bomb_def: Dictionary = BombRegistry.get_bomb(bomb_id)
	var scene_path_var: Variant = bomb_def.get("scene_path", "")
	if typeof(scene_path_var) == TYPE_STRING and String(scene_path_var) != "":
		_bomb_scene = load(String(scene_path_var)) as PackedScene


func get_bomb_scene() -> PackedScene:
	return _bomb_scene


func get_interact_distance_m() -> float:
	return interact_distance_m


func equip_to(player: PlayerController) -> void:
	if player == null:
		return
	if _bomb_scene == null:
		return

	player.bomb_scene = _bomb_scene
	equipped.emit(bomb_id)

