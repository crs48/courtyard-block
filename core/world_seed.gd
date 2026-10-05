class_name CBWorldSeed
extends RefCounted
## Independent keyed streams: adding a draw in one layer never changes another.
const LAYERS := ["layout", "climate", "resources", "people"]
const VERSION := "living-seeds-1"

static func sample(seed_value: int, key: String, count: int) -> int:
	return int((str(seed_value) + ":" + key).sha256_text().substr(0, 8).hex_to_int() % count)

static func seeds(root_seed: int) -> Dictionary:
	var result := {}
	for layer in LAYERS: result[layer] = 1 + sample(root_seed, layer, 999999)
	return result

static func seed_error(value: Variant) -> String:
	if not value is Dictionary or value.size() != LAYERS.size(): return "A seed is required for each world layer."
	for layer in LAYERS:
		if not value.has(layer) or not CBValidation.number(value[layer]) or value[layer] < 1 or value[layer] > 1000000 or floorf(value[layer]) != value[layer]: return "Invalid " + layer + " seed."
	return ""

static func generate(layer_seeds: Dictionary, packs: Array) -> Dictionary:
	var issue := seed_error(layer_seeds)
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	var base := CBLabCatalog.compile(packs)
	if not base.ok: return base
	var content: CBLabCatalog = base.catalog
	for family in ["layouts", "climates", "homes", "plants", "policies", "assemblies"]:
		var required: String = {"layouts": "core:courtyard", "climates": "core:continental", "homes": "core:home", "plants": "core:heat_pump", "policies": "core:metered", "assemblies": "core:light_wall"}[family]
		if content.definition(family, required).is_empty(): return CBLabCatalog.fail("Living worlds require the reference kit.")
	if content.definition("assemblies", "core:warm_wall").is_empty(): return CBLabCatalog.fail("The reference insulated wall is required by the resident planner.")
	for pack in packs:
		if pack.id == "seeded": return CBLabCatalog.fail("The seeded namespace is reserved for generation.")
	var layout_seed := int(layer_seeds.layout)
	var climate_seed := int(layer_seeds.climate)
	var resource_seed := int(layer_seeds.resources)
	var kind := sample(layout_seed, "pattern", 3)
	var count := 6 + 2 * sample(layout_seed, "population", 2)
	var plans: Array = []
	var placements: Array = []
	var profiles: Array = []
	var gap := 2 + sample(layout_seed, "gap", 4)
	for i in count:
		var x: int = (-1 if i % 2 == 0 else 1) * (8 + gap)
		var z: int = (i / 2) * 10 - (count / 2 - 1) * 5
		if kind == 0: z = (i / 2) * 8 - (count / 2 - 1) * 4
		if kind == 2:
			var angle := i * TAU / count
			x = roundi(cos(angle) * (16 + gap)) + sample(layout_seed, "x%d" % i, 3) - 1
			z = roundi(sin(angle) * (16 + gap)) + sample(layout_seed, "z%d" % i, 3) - 1
		var id := "home_%02d" % (i + 1)
		var owner: String = ["west", "east", "commons"][i % 3]
		plans.append({"id": id, "x": x - 3, "z": z - 4, "rooms": [[0, 0, 6, 4], [0, 4, 4, 4], [4, 4, 2, 4]], "assembly": "core:light_wall", "owner": owner})
		placements.append({"id": id, "position": [x, 0, z], "rotation": "0", "owner": owner, "support": "ground", "support_capacity_kg": 300000})
		profiles.append({"space_index": sample(int(layer_seeds.people), "space%d" % i, 3), "priority": sample(int(layer_seeds.people), "priority%d" % i, 3)})
	var climates := ["Cool and wet", "Continental seasons", "Hot and dry"]
	var climate_kind := sample(climate_seed, "region", 3)
	var weather := content.definition("climates", "core:continental").duplicate(true)
	weather.merge({"id": "seeded:weather", "name": climates[climate_kind], "mean_c": [8, 12, 23][climate_kind] + sample(climate_seed, "mean", 5) - 2, "seasonal_c": [9, 17, 10][climate_kind], "rain_mm_day": [4.0, 2.0, 0.3][climate_kind], "diurnal_c": [3, 6, 8][climate_kind], "cold_snap_day": 2 + sample(climate_seed, "snap", 35), "outage_day": 3 + sample(climate_seed, "outage", 28), "outage_hours": 6 + sample(climate_seed, "duration", 19)}, true)
	var layout := {"id": "seeded:layout", "name": ["Courtyard neighbours", "Garden lanes", "Scattered gardens"][kind], "placements": placements, "party_walls": [], "evidence": "core:assumptions"}
	var generated := {"api_version": 2, "model": CBLabCatalog.MODEL, "id": "seeded", "name": "Seeded starting conditions", "version": "1.0.0", "dependencies": {"core": "1.0.0"}, "content": {"climates": [weather], "layouts": [layout]}}
	var all_packs := packs.duplicate(true)
	all_packs.append(generated)
	var compiled := CBLabCatalog.compile(all_packs)
	if not compiled.ok: return compiled
	var chosen := CBLab.default_design()
	chosen.merge({"layout": "seeded:layout", "climate": "seeded:weather", "seed": climate_seed, "solar_kw": float(2 + sample(resource_seed, "solar", 5) * 2), "battery_kwh": float(sample(resource_seed, "battery", 3) * 10), "water_l_day": float(count * 3 * 90 * (0.65 + sample(resource_seed, "water", 5) * 0.12)), "sewage_l_day": float(count * 3 * 72 * (0.7 + sample(resource_seed, "sewer", 5) * 0.12)), "waste_kg": float(20 + sample(resource_seed, "bins", 5) * 10), "grid_kw": float(10 + sample(resource_seed, "grid", 5) * 3)}, true)
	return {"ok": true, "catalog": compiled.catalog, "design": chosen, "plans": plans, "profiles": profiles, "title": layout.name + " · " + weather.name, "message": "A new community is ready."}
