extends RefCounted
class_name GribblyRegistry

## Loads gribbly definitions from res://data/gribblies/*.json so procedural
## systems can attach surface details (vents, pipes, panels) to structural sections.

static var _gribblies: Dictionary = {}
static var _loaded: bool = false


static func get_gribbly(id: StringName) -> Dictionary:
	_ensure_loaded()
	if id in _gribblies:
		return _gribblies[id]
	return {}


static func get_all_gribbly_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _gribblies.keys():
		out.append(key as StringName)
	return out


static func get_gribblies_by_theme(theme: String) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for g in _gribblies.values():
		if str(g.get("theme", "")) == theme:
			out.append(g as Dictionary)
	return out


static func get_gribblies_with_tag(tag: String) -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for g in _gribblies.values():
		var tags: Variant = g.get("tags", [])
		if typeof(tags) == TYPE_ARRAY:
			for t in tags:
				if str(t) == tag:
					out.append(g as Dictionary)
					break
	return out


static func get_gribblies_by_theme_and_tag(theme: String, tag: String) -> Array[Dictionary]:
	var by_theme: Array[Dictionary] = get_gribblies_by_theme(theme)
	var out: Array[Dictionary] = []
	for g in by_theme:
		var tags: Variant = g.get("tags", [])
		if typeof(tags) == TYPE_ARRAY:
			for t in tags:
				if str(t) == tag:
					out.append(g)
					break
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var dir: DirAccess = DirAccess.open("res://data/gribblies")
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_gribbly_file("res://data/gribblies/%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


## Spawns all gribblies defined in a building section under parent, in section local space.
## section_dict: full section data (must have "gribblies" array).
## parent: Node3D to attach instances to (e.g. section root or wall node).
## section_transform: Transform3D of the section in world space; gribbly positions are applied in section space then transformed.
## Returns array of spawned node references (empty if section has no gribblies or scene load fails).
static func spawn_section_gribblies(section_dict: Dictionary, parent: Node3D, section_transform: Transform3D) -> Array[Node]:
	var out: Array[Node] = []
	var gribblies: Variant = section_dict.get("gribblies", [])
	if typeof(gribblies) != TYPE_ARRAY:
		return out

	for placement in gribblies:
		if typeof(placement) != TYPE_DICTIONARY:
			continue
		var gid: Variant = placement.get("gribbly_id", "")
		if gid == null or str(gid).is_empty():
			continue
		var gribbly: Dictionary = get_gribbly(StringName(str(gid)))
		if gribbly.is_empty():
			continue
		var scene_path: String = str(gribbly.get("scene", ""))
		if scene_path.is_empty():
			continue
		var packed: Resource = load(scene_path) as Resource
		if packed == null:
			continue
		var instance: Node = packed.instantiate()
		if not instance is Node3D:
			instance.queue_free()
			continue
		var n: Node3D = instance as Node3D
		var pos: Vector3 = _vec3_from_array(placement.get("pos", [0, 0, 0]))
		var rot_y: float = float(placement.get("rot_y", 0))
		var scale_arr: Variant = placement.get("scale", null)
		var s: Vector3 = Vector3.ONE
		if scale_arr != null and typeof(scale_arr) == TYPE_ARRAY:
			s = _vec3_from_array(scale_arr)
		else:
			var def_scale: Variant = gribbly.get("default_scale", null)
			if def_scale != null and typeof(def_scale) == TYPE_ARRAY:
				s = _vec3_from_array(def_scale)
		var local := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(rot_y), 0)).scaled(s), pos)
		n.transform = section_transform * local
		parent.add_child(n)
		out.append(n)
	return out


static func _vec3_from_array(arr: Variant) -> Vector3:
	if typeof(arr) != TYPE_ARRAY or (arr as Array).size() < 3:
		return Vector3.ZERO
	var a: Array = arr as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
