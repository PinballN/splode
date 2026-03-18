extends Node3D
class_name SecurityCamera

signal player_spotted

@export var enabled := true

@onready var detection_area: Area3D = $DetectionArea


func _ready() -> void:
	if detection_area:
		detection_area.body_entered.connect(_on_detection_body_entered)


func _on_detection_body_entered(body: Node) -> void:
	if not enabled:
		return

	if body is PlayerController:
		enabled = false  # One-shot: don't re-trigger alarm when moving in/out of area
		player_spotted.emit()
		get_tree().call_group("mission", "on_security_spotted", self, body)

