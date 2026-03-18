extends RefCounted
class_name FacilityLayoutRegistry

static var _layouts: Dictionary = {}
static var _loaded: bool = false

# Facility layout definitions loaded from: `res://data/facility_layouts/*.json`
#
# Minimal expected schema:
# {
#   "id": "warehouse_internal_v1",
#   "templates": [
#     { "pos": [x,y,z], "size": [sx,sy,sz] }
#   ],
#   "material_ids": ["concrete", "wood", ...]
# }
static func get_layout(id: StringName) -> Dictionary:
	_ensure_loaded()
	if id in _layouts:
		return _layouts[id]
	if &"default" in _layouts:
		return _layouts[&"default"]
	return {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var dir: DirAccess = DirAccess.open("res://data/facility_layouts")
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			if file_name.ends_with(".json"):
				_load_layout_file("res://data/facility_layouts/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	if not (&"default" in _layouts):
		_layouts[&"default"] = { "id": "default", "templates": [] }


static func _load_layout_file(path: String) -> void:
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

	var layout_id: String = str(dict["id"])
	if typeof(layout_id) != TYPE_STRING:
		return

	_layouts[StringName(layout_id)] = dict

