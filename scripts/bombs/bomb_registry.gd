extends RefCounted
class_name BombRegistry

static var _bombs: Dictionary = {}
static var _loaded: bool = false

# Data-driven bomb stats loaded from:
#   res://data/bombs/*.json
#
# Required JSON fields (example):
# {
#   "id": "test_incendiary",
#   "fuse_time": 10.0,
#   "blast_radius": 5.0,
#   "concussion_value": 0.2,
#   "fire_damage": 1.5,
#   "fire_radius": 5.0
# }

static func get_bomb(id: StringName) -> Dictionary:
	_ensure_loaded()
	if id in _bombs:
		return _bombs[id]
	if "default" in _bombs:
		return _bombs["default"]
	return {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var dir: DirAccess = DirAccess.open("res://data/bombs")
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".json"):
				_load_bomb_file("res://data/bombs/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if not ("default" in _bombs):
		_bombs["default"] = {
			"id": "default",
			"fuse_time": 2.0,
			"blast_radius": 4.0,
			"concussion_value": 1.0,
			"fire_damage": 1.0,
			"fire_radius": 4.0,
		}


static func _load_bomb_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var dict: Dictionary = parsed as Dictionary
	if not dict.has("id"):
		return

	var bomb_id: String = str(dict["id"])
	if typeof(bomb_id) != TYPE_STRING:
		return

	_bombs[StringName(bomb_id)] = dict
