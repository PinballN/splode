extends Area3D
class_name RoofCutaway

@export var roof_path: NodePath
@export var roof_visible_on_start: bool = true

var _roof: Node
var _human_inside_count: int = 0


func _ready() -> void:
	add_to_group("roof_cutaway")

	_roof = get_node_or_null(roof_path)
	if _roof:
		_roof.visible = roof_visible_on_start

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _is_human_player(body: Node) -> bool:
	if body is PlayerController:
		var p := body as PlayerController
		return p.control_mode == PlayerController.ControlMode.HUMAN
	return false


func _set_roof_visible(show_roof: bool) -> void:
	if not _roof:
		return
	_roof.visible = show_roof


func _on_body_entered(body: Node) -> void:
	if not _is_human_player(body):
		return

	_human_inside_count += 1
	_set_roof_visible(false)


func _on_body_exited(body: Node) -> void:
	if not _is_human_player(body):
		return

	_human_inside_count = max(_human_inside_count - 1, 0)
	if _human_inside_count <= 0:
		_set_roof_visible(roof_visible_on_start)

