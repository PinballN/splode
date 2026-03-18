extends CanvasLayer
class_name HUD

@onready var objective_label: Label = $Panel/VBoxContainer/ObjectiveLabel
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var health_label: Label = $Panel/VBoxContainer/HealthLabel
@onready var equipped_label: Label = $Panel/VBoxContainer/EquippedLabel
@onready var controls_label: Label = $Panel/VBoxContainer/ControlsLabel
@onready var bomb_countdown_label: Label = $BombCountdownLabel


func set_objective(text: String) -> void:
	if objective_label:
		objective_label.text = text


func set_status(text: String) -> void:
	if status_label:
		status_label.text = text


func set_health(current: float, _max: float) -> void:
	if health_label == null:
		return
	var c := int(ceil(current))
	var m := int(ceil(_max))
	health_label.text = str("HP ", c, "/", m)


func set_equipped(display_text: String) -> void:
	if equipped_label:
		equipped_label.text = str("Equipped: ", display_text if display_text else "—")


func set_alarm(active: bool) -> void:
	if status_label:
		status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35) if active else Color(1.0, 1.0, 1.0))


func set_controls(text: String) -> void:
	if controls_label:
		controls_label.text = text


func set_bomb_countdown_seconds(time_left: float, active: bool) -> void:
	if bomb_countdown_label == null:
		return

	bomb_countdown_label.visible = active
	if not active:
		return

	# Digital countdown: show whole seconds remaining.
	var seconds_left: int = int(ceil(time_left))
	if seconds_left < 0:
		seconds_left = 0

	bomb_countdown_label.text = str(seconds_left)

