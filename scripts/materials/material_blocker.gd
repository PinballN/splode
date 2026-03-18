extends Node
class_name MaterialBlocker

@export var material_id: StringName = &"reinforced_concrete"

var _stats: Dictionary


func _ready() -> void:
	_stats = MaterialRegistry.get_material(material_id)


func get_strength() -> float:
	return float(_stats.get("strength", 10.0))


func get_flamability() -> float:
	# Note: property is called flammability in data, keep API tolerant.
	return float(_stats.get("flammability", _stats.get("flamability", 0.1)))


func get_transparency() -> float:
	# 0 = opaque, 1 = fully transparent
	return clampf(float(_stats.get("visibility_transparency", 0.0)), 0.0, 1.0)


func get_destruction_model() -> String:
	var d: Dictionary = _stats.get("destruction", {})
	return str(d.get("model", "shatter"))

