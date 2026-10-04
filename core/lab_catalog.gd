class_name CBLabCatalog
extends RefCounted
## Portable API v2: JSON definitions only. No callbacks, resource loads or code entries.

const MODEL := "warm-homes-1"
const FAMILIES := ["evidence", "materials", "assemblies", "homes", "layouts", "climates", "plants", "policies"]
static var schema: Dictionary = {}
var packs: Array = []
var definitions: Dictionary = {}

static func canonical(value: Variant) -> String:
	# Normalize JSON numbers so a parsed bundle and an in-memory draft hash identically.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)

static func digest(value: Variant) -> String:
	return canonical(value).sha256_text()

static func builtin_packs() -> Array:
	return [JSON.parse_string(FileAccess.get_file_as_string("res://content/lab/manifest.json")), JSON.parse_string(FileAccess.get_file_as_string("res://mods/lab_hemp/manifest.json"))]

static func fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func compile(input: Variant) -> Dictionary:
	if not input is Array or input.is_empty() or input.size() > 24: return fail("Use 1–24 data packs.")
	if schema.is_empty(): schema = JSON.parse_string(FileAccess.get_file_as_string("res://schemas/lab-pack.schema.json"))
	var catalog := CBLabCatalog.new()
	var versions: Dictionary = {}
	for pack in input:
		var issue := validate(pack, schema, "pack")
		if not issue.is_empty(): return fail(issue)
		if not CBModLoader.valid_pack_id(pack.id) or versions.has(pack.id): return fail("Invalid or duplicate pack ID: " + str(pack.id))
		versions[pack.id] = pack.version
		catalog.packs.append(pack.duplicate(true))
		for family in pack.content:
			if not catalog.definitions.has(family): catalog.definitions[family] = {}
			for definition in pack.content[family]:
				var id := str(definition.id)
				if id.get_slice_count(":") != 2 or id.get_slice(":", 0) != pack.id or not CBModLoader.valid_pack_id(id.get_slice(":", 1)):
					return fail("Definition must use its pack namespace: " + id)
				if catalog.definitions[family].has(id): return fail("Duplicate definition: " + id)
				catalog.definitions[family][id] = definition.duplicate(true)
	var pending := catalog.packs.duplicate()
	var ready: Dictionary = {}
	while not pending.is_empty():
		var progressed := false
		for pack in pending.duplicate():
			var available := true
			for dependency in pack.dependencies:
				if versions.get(dependency, "") != pack.dependencies[dependency]: return fail("Missing or incompatible dependency: " + str(dependency))
				if not ready.has(dependency): available = false
			if available:
				ready[pack.id] = true
				pending.erase(pack)
				progressed = true
		if not progressed: return fail("Cyclic pack dependencies.")
	for family in FAMILIES:
		if catalog.list_content(family).is_empty(): return fail("The experiment needs definitions for " + family + ".")
	var issue := catalog._semantic_error()
	if not issue.is_empty(): return fail(issue)
	catalog.packs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"ok": true, "catalog": catalog, "message": "Data packs compiled."}

static func validate(value: Variant, spec: Dictionary, path: String, depth: int = 0) -> String:
	if depth > 24: return path + ": definition nesting exceeds the limit."
	if spec.has("$ref"): return validate(value, schema["$defs"][str(spec["$ref"]).get_slice("/", 2)], path, depth + 1)
	if spec.has("const") and value != spec["const"]: return path + ": requires " + str(spec["const"]) + "."
	if spec.has("enum") and not value in spec.enum: return path + ": choose " + str(spec.enum) + "."
	match spec.get("type", ""):
		"object":
			if not value is Dictionary: return path + ": expected an object."
			for key in spec.get("required", []):
				if not value.has(key): return path + ": missing " + str(key) + "."
			for key in value:
				var properties: Dictionary = spec.get("properties", {})
				var field: Variant = properties.get(key, spec.get("additionalProperties", true))
				if field is bool:
					if not field: return path + ": unsupported field " + str(key) + "."
				else:
					var issue := validate(value[key], field, path + "." + str(key), depth + 1)
					if not issue.is_empty(): return issue
		"array":
			if not value is Array or value.size() < spec.get("minItems", 0) or value.size() > spec.get("maxItems", 10000): return path + ": invalid array size."
			for i in value.size():
				var issue := validate(value[i], spec.items, path + "[%d]" % i, depth + 1)
				if not issue.is_empty(): return issue
		"number", "integer":
			if not CBValidation.number(value): return path + ": expected a finite number."
			if spec.type == "integer" and float(value) != floorf(float(value)): return path + ": expected a whole number."
			if value < spec.get("minimum", -INF) or value > spec.get("maximum", INF): return path + ": outside the supported range."
		"string":
			if not value is String or value.length() < spec.get("minLength", 0) or value.length() > spec.get("maxLength", 10000): return path + ": invalid text length."
	return ""

func list_content(family: String) -> Array:
	var items: Array = definitions.get(family, {}).values()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return items

func definition(family: String, id: String) -> Dictionary:
	return definitions.get(family, {}).get(id, {})

func lock() -> Array:
	var result: Array = []
	for pack in packs: result.append({"id": pack.id, "version": pack.version, "sha256": digest(pack)})
	return result

func _reference_error(owner: String, family: String, id: String) -> String:
	if definition(family, id).is_empty(): return "Missing " + family + " reference: " + id
	var source := owner.get_slice(":", 0)
	var target := id.get_slice(":", 0)
	if source == target: return ""
	for pack in packs:
		if pack.id == source and pack.dependencies.has(target): return ""
	return owner + " must declare its dependency on " + target + "."

func _semantic_error() -> String:
	for family in FAMILIES:
		for item in list_content(family):
			if family == "evidence":
				if item.status == "measured" and not str(item.source).begins_with("https://"): return item.id + ": measured inputs need a source URL. This is an author claim, not certification."
				continue
			var issue := _reference_error(item.id, "evidence", item.evidence)
			if not issue.is_empty(): return issue
			if family == "materials" and not Color.html_is_valid(item.color): return item.id + ": invalid color."
			if family == "assemblies":
				var thickness := 0.0
				for layer in item.layers:
					issue = _reference_error(item.id, "materials", layer.material)
					if not issue.is_empty(): return issue
					thickness += float(layer.thickness_m)
				if thickness > 1.0: return item.id + ": total wall thickness exceeds 1 m."
			if family == "homes" and item.glazing_m2 >= 2 * (item.width_m + item.floor_m2 / item.width_m) * item.height_m: return item.id + ": windows exceed wall area."
			if family == "layouts":
				var places: Dictionary = {}
				for place in item.placements:
					if not CBModLoader.valid_pack_id(place.id) or places.has(place.id): return item.id + ": invalid or duplicate home identity."
					if place.position[1] < 0 or place.position[1] > 12: return item.id + ": elevation must be 0–12 m."
					if (place.position[1] > 0) != (place.support == "anchors"): return item.id + ": elevated homes require declared anchors."
					places[place.id] = true
				var links: Dictionary = {}
				for link in item.party_walls:
					if link.a == link.b or not places.has(link.a) or not places.has(link.b): return item.id + ": party wall references an unknown home."
					var pair := [str(link.a), str(link.b)]
					pair.sort()
					var key := ":".join(pair)
					if links.has(key): return item.id + ": repeated party wall."
					links[key] = true
			if family == "plants" and item.cold_cop > item.cop: return item.id + ": cold COP must not exceed the nominal COP in this model."
			if family == "climates" and item.has("hourly"):
				for row in item.hourly:
					if row[0] < -80 or row[0] > 60 or row[1] < 0 or row[1] > 1400 or row[2] < 0 or row[2] > 200: return item.id + ": hourly rows need °C (-80–60), solar W/m² (0–1400), and rain mm (0–200)."
	return ""

func assembly(id: String) -> Dictionary:
	var item := definition("assemblies", id)
	var result := {"r": 0.17, "mass_kg_m2": 0.0, "capacity_j_m2k": 0.0, "cost_cents_m2": float(item.labor_cents_m2), "carbon_kg_m2": 0.0, "thickness_m": 0.0, "color": "#c89869"}
	for layer in item.layers:
		var material := definition("materials", layer.material)
		var thickness: float = layer.thickness_m
		result.r += thickness / float(material.conductivity_w_mk)
		result.mass_kg_m2 += thickness * float(material.density_kg_m3)
		result.capacity_j_m2k += thickness * float(material.density_kg_m3) * float(material.heat_capacity_j_kgk)
		result.cost_cents_m2 += thickness * float(material.price_cents_m3)
		result.carbon_kg_m2 += thickness * float(material.carbon_kg_m3)
		result.thickness_m += thickness
	result.color = definition("materials", str(item.layers[0].material)).color
	result["u"] = 1.0 / float(result.r)
	return result
