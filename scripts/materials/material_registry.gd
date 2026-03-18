extends RefCounted
class_name MaterialRegistry

static var _materials: Dictionary = {}
static var _loaded: bool = false

# Data-driven material stats.
# Loaded from `res://data/materials/*.json`.
#
# Expected JSON schema (example):
# {
#   "id": "concrete",
#   "category": "concrete",
#   "strength": 60.0,
#   "flammability": 0.05,
#   "visibility_transparency": 0.0,
#   "sound": { "break": "res://..." },
#   "destruction": { "model": "shatter", "debris_scene": "res://..." }
# }

static func get_material(id: StringName) -> Dictionary:
	_ensure_loaded()
	if id in _materials:
		return _materials[id]
	if "default" in _materials:
		return _materials["default"]
	return {}


static func get_all_material_ids() -> Array[StringName]:
	_ensure_loaded()
	return _materials.keys()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var dir: DirAccess = DirAccess.open("res://data/materials")
	if dir == null:
		# Can't load materials; keep system empty.
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".json"):
				var path := "res://data/materials/%s" % file_name
				_load_material_file(path)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Provide a default fallback.
	if not ("default" in _materials):
		_materials["default"] = _make_default_material()


static func _load_material_file(path: String) -> void:
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

	var mat_id: String = str(dict["id"])
	if typeof(mat_id) != TYPE_STRING:
		return

	_materials[StringName(mat_id)] = dict


static func _make_default_material() -> Dictionary:
	return {
		"id": "default",
		"category": "generic",
		"strength": 10.0,
		"flammability": 0.1,
		"visibility_transparency": 0.0,
		"sound": {
			"break": "",
			"burn": ""
		},
		"destruction": {
			"model": "shatter"
		}
	}

