extends RefCounted
class_name LoadoutRegistry

static var _loadouts: Dictionary = {}
static var _loaded: bool = false

# Loadout definitions loaded from: `res://data/loadouts/*.json`
#
# Expected schema (minimal):
# {
#   "id": "default",
#   "bomb_id": "test_incendiary"
# }
static func get_loadout(id: StringName) -> Dictionary:
	_ensure_loaded()
	if id in _loadouts:
		return _loadouts[id]
	if &"default" in _loadouts:
		return _loadouts[&"default"]
	return {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var dir: DirAccess = DirAccess.open("res://data/loadouts")
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".json"):
				_load_loadout_file("res://data/loadouts/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if not (&"default" in _loadouts):
		_loadouts[&"default"] = {
			"id": "default",
			"bomb_id": "test_incendiary"
		}


static func _load_loadout_file(path: String) -> void:
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

	var loadout_id: String = str(dict["id"])
	if typeof(loadout_id) != TYPE_STRING:
		return

	_loadouts[StringName(loadout_id)] = dict

