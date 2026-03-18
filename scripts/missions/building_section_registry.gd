extends RefCounted
class_name BuildingSectionRegistry

## Loads approved building sections from res://data/building_sections/*.json
## so procedural systems / AI can select thematic, logical sections.

static var _sections: Dictionary = {}
static var _loaded: bool = false


static func get_section(id: StringName) -> Dictionary:
	_ensure_loaded()
	if id in _sections:
		return _sections[id]
	return {}


static func get_all_section_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _sections.keys():
		out.append(key as StringName)
	return out


static func get_sections_by_theme(theme: String) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for section in _sections.values():
		if str(section.get("theme", "")) == theme:
			out.append(section as Dictionary)
	return out


static func get_sections_with_tag(tag: String) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for section in _sections.values():
		var tags: Variant = section.get("tags", [])
		if typeof(tags) == TYPE_ARRAY:
			for t in tags:
				if str(t) == tag:
					out.append(section as Dictionary)
					break
	return out


static func get_sections_by_theme_and_tag(theme: String, tag: String) -> Array[Dictionary]:
	var by_theme: Array[Dictionary] = get_sections_by_theme(theme)
	var out: Array[Dictionary] = []
	for section in by_theme:
		var tags: Variant = section.get("tags", [])
		if typeof(tags) == TYPE_ARRAY:
			for t in tags:
				if str(t) == tag:
					out.append(section)
					break
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var dir: DirAccess = DirAccess.open("res://data/building_sections")
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_section_file("res://data/building_sections/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


static func _load_section_file(path: String) -> void:
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

	var section_id: String = str(dict["id"])
	_sections[StringName(section_id)] = dict
