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

func register_content(kind: String, definition: Dictionary) -> bool:
	var id := str(definition.get("id", ""))
	if not id.contains(":") or id.split(":").size() != 2:
		errors.append("Content ID must be namespaced: " + id)
		return false
	if not definitions.has(kind):
		definitions[kind] = {}
	if definitions[kind].has(id):
		errors.append("Duplicate content ID: " + id)
		return false
	definitions[kind][id] = definition.duplicate(true)
	return true

func register_generator(id: String, callback: Callable) -> void:
	if generators.has(id):
		errors.append("Duplicate generator: " + id)
	else:
		generators[id] = callback

func register_system(id: String, callback: Callable, interval_minutes: int = 60) -> void:
	if interval_minutes < 1:
		errors.append("System interval must be positive: " + id)
		return
	for system in systems:
		if system.id == id:
			errors.append("Duplicate system: " + id)
			return
	systems.append({"id": id, "callback": callback, "interval": interval_minutes})
	systems.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)

func register_panel(id: String, callback: Callable) -> void:
	if panels.has(id):
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
