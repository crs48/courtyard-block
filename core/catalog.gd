class_name CBCatalog
extends RefCounted
## Public v1 registry. Callbacks are trusted code, not a security boundary.

const API_VERSION := 1
var definitions: Dictionary = {}
var generators: Dictionary = {}
var systems: Array[Dictionary] = []
var panels: Dictionary = {}
var packs: Dictionary = {}
var errors: Array[String] = []
var active_pack := ""

func _valid_id(id: String) -> bool:
	return id.split(":").size() == 2 and not id.get_slice(":", 1).is_empty() and CBModLoader.valid_pack_id(id.get_slice(":", 0)) and (active_pack.is_empty() or id.begins_with(active_pack + ":"))

func register_content(kind: String, definition: Dictionary) -> bool:
	var id := str(definition.get("id", ""))
	if not _valid_id(id):
		errors.append("Content ID must be namespaced: " + id)
		return false
	var schema: Dictionary = {"id": "string", "name": "string"}
	match kind:
		"furniture": schema.merge({"cost": "number", "shape": "string", "benefit": "number"})
		"materials": schema.merge({"cost_multiplier": "number", "comfort": "number", "maintenance": "number", "color": "string"})
		"businesses": schema.merge({"kind": "string", "daily_revenue": "number", "daily_cost": "number", "jobs": "number", "color": "string"})
	if not CBValidation.fields(definition, schema) or float(definition.get("cost", 0)) < 0 or float(definition.get("cost_multiplier", 1)) <= 0 or float(definition.get("maintenance", 1)) < 0:
		errors.append("Invalid " + kind + " definition: " + id)
		return false
	if not definitions.has(kind):
		definitions[kind] = {}
	if definitions[kind].has(id):
		errors.append("Duplicate content ID: " + id)
		return false
	definitions[kind][id] = definition.duplicate(true)
	return true

func register_generator(id: String, callback: Callable) -> void:
	if not _valid_id(id) or not callback.is_valid():
		errors.append("Invalid generator: " + id)
	elif generators.has(id):
		errors.append("Duplicate generator: " + id)
	else:
		generators[id] = callback

func register_system(id: String, callback: Callable, interval_minutes: int = 60) -> void:
	if not _valid_id(id) or not callback.is_valid() or interval_minutes < 15 or interval_minutes % 15 != 0:
		errors.append("System needs a namespaced ID, callback and interval divisible by 15: " + id)
		return
	for system in systems:
		if system.id == id:
			errors.append("Duplicate system: " + id)
			return
	systems.append({"id": id, "callback": callback, "interval": interval_minutes})
	systems.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)

func register_panel(id: String, callback: Callable) -> void:
	if not _valid_id(id) or not callback.is_valid():
		errors.append("Invalid panel: " + id)
	elif panels.has(id):
		errors.append("Duplicate panel: " + id)
	else:
		panels[id] = callback

func get_definition(kind: String, id: String) -> Dictionary:
	return definitions.get(kind, {}).get(id, {})

func list_content(kind: String) -> Array:
	var result: Array = definitions.get(kind, {}).values()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return result

func pack_lock() -> Array:
	var result: Array = []
	var ids: Array = packs.keys()
	ids.sort()
	for id in ids:
		result.append({"id": id, "version": packs[id].version, "digest": packs[id].digest})
	return result
