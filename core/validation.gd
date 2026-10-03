class_name CBValidation
extends RefCounted
## Pure schema and relationship checks; imported data never mutates live state.

static func fields(value: Variant, schema: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key in schema:
		if not value.has(key): return false
		match schema[key]:
			"number":
				if not number(value[key]): return false
			"string":
				if not value[key] is String: return false
			"array":
				if not value[key] is Array: return false
			"object":
				if not value[key] is Dictionary: return false
			"bool":
				if not value[key] is bool: return false
	return true

static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func vector(value: Variant, dimensions: int) -> bool:
	if not value is Array or value.size() != dimensions: return false
	for component in value:
		if not number(component): return false
	return true

static func layout_error(layout: Variant, catalog: CBCatalog) -> String:
	if not fields(layout, {"points": "array", "edges": "array", "spaces": "array", "floors": "number", "width": "number", "courtyard": "number", "kind": "string"}): return "Invalid building layout."
	if layout.points.is_empty() or layout.points.size() > 20000 or layout.spaces.size() > 10000 or layout.edges.size() > 100000: return "Building exceeds layout limits."
	if layout.floors < 1 or layout.floors > 200 or layout.width <= 0: return "Invalid building dimensions."
	var nodes: Dictionary = {}
	for point in layout.points:
		if not fields(point, {"id": "number", "position": "array"}) or not vector(point.position, 3): return "Invalid navigation point."
		if nodes.has(int(point.id)): return "Duplicate navigation point."
		nodes[int(point.id)] = true
	for edge in layout.edges:
		if not vector(edge, 2) or not nodes.has(int(edge[0])) or not nodes.has(int(edge[1])) or edge[0] == edge[1]: return "Invalid navigation edge."
	var spaces: Dictionary = {}
	var homes := 0
	for space in layout.spaces:
		if not fields(space, {"id": "string", "name": "string", "kind": "string", "floor": "number", "node": "number", "position": "array", "size": "array", "capacity": "number", "furniture": "array"}): return "Invalid space."
		if not vector(space.position, 3) or not vector(space.size, 2) or not nodes.has(int(space.node)): return "Invalid space geometry."
		if spaces.has(space.id) or space.capacity < 1 or space.floor < 0 or space.floor >= layout.floors or space.furniture.size() > 12: return "Invalid space capacity or duplicate ID."
		for item in space.furniture:
			if not fields(item, {"id": "string", "x": "number", "z": "number", "rotation": "number"}) or catalog.get_definition("furniture", item.id).is_empty(): return "Unknown or malformed furnishing."
		spaces[space.id] = space
		if space.kind == "home": homes += 1
	if not spaces.has("courtyard") or not spaces.has("city") or homes == 0: return "Generators must provide homes, courtyard and city spaces."
	var graph := CBSpatial.new()
	graph.rebuild(layout)
	for space in layout.spaces:
		if graph.route(int(spaces.courtyard.node), int(space.node)).is_empty(): return "Unreachable space: " + space.id
	return ""

static func save_error(saved: Dictionary, catalog: CBCatalog) -> String:
	if not fields(saved, {"name": "string", "layout": "object", "residents": "array", "households": "array", "shops": "array", "parameters": "object", "policies": "object", "services": "object", "packs": "array", "history": "array", "ledger": "array", "notices": "array", "totals": "object", "mod_state": "object", "branch": "object", "rng": "number", "minute": "number", "funds": "number"}): return "Incomplete or malformed community data."
	if saved.residents.is_empty() or saved.residents.size() > 10000 or saved.households.is_empty() or saved.households.size() > 10000: return "Invalid population."
	if not fields(saved.parameters, {"template": "string", "material": "string", "width": "number", "courtyard": "number", "floors": "number", "population": "number"}): return "Invalid building parameters."
	if not fields(saved.policies, {"contribution": "number", "shared_meals": "bool", "unlimited_funds": "bool"}) or saved.policies.contribution < 0: return "Invalid policies."
	if not fields(saved.services, {"water": "number", "sewage": "number", "power": "number", "waste": "number"}): return "Invalid services."
	if not fields(saved.totals, {"water_l": "number", "power_kwh": "number", "waste_kg": "number"}) or not fields(saved.branch, {"parent": "string", "origin_minute": "number"}): return "Invalid experiment data."
	if catalog.get_definition("materials", saved.parameters.material).is_empty(): return "Unknown building material."
	var error := layout_error(saved.layout, catalog)
	if not error.is_empty(): return error
	var spaces: Dictionary = {}
	var nodes: Dictionary = {}
	for space in saved.layout.spaces: spaces[space.id] = space
	for point in saved.layout.points: nodes[int(point.id)] = true
	for i in saved.households.size():
		var household: Variant = saved.households[i]
		if not fields(household, {"id": "string", "home": "string", "wallet": "number", "arrears": "number"}): return "Invalid household."
		if household.id != "household_" + str(i) or not spaces.has(household.home) or spaces[household.home].kind != "home": return "Invalid household assignment."
	for i in saved.residents.size():
		var person: Variant = saved.residents[i]
		if not fields(person, {"id": "string", "name": "string", "household": "string", "home": "string", "interest": "string", "skill": "string", "preference": "string", "income": "number", "needs": "object", "wellbeing": "number", "activity": "string", "node": "number", "target": "number", "position": "array", "path": "array", "travel_remaining": "number", "travel_total": "number", "unreachable": "bool", "reason": "string"}): return "Invalid resident."
		var household_index := int(str(person.household).get_slice("_", 1))
		if person.id != "resident_%03d" % i or household_index < 0 or household_index >= saved.households.size(): return "Invalid resident ID."
		if person.household != saved.households[household_index].id or person.home != saved.households[household_index].home: return "Invalid resident household."
		if not nodes.has(int(person.node)) or not nodes.has(int(person.target)) or not vector(person.position, 3): return "Invalid resident location."
		if not fields(person.needs, {"food": "number", "rest": "number", "social": "number", "comfort": "number"}): return "Invalid resident needs."
		for point in person.path:
			if not vector(point, 3): return "Invalid resident route."
	for shop in saved.shops:
		if not fields(shop, {"space": "string", "business": "string", "profit": "number", "wallet": "number", "visits": "number"}) or not spaces.has(shop.space) or spaces[shop.space].kind != "shop": return "Invalid shop."
		if shop.business != "" and catalog.get_definition("businesses", shop.business).is_empty(): return "Unknown business."
	for sample in saved.history:
		if not fields(sample, {"minute": "number", "wellbeing": "number", "bottom_decile": "number", "funds": "number", "water_l": "number", "power_kwh": "number", "waste_kg": "number"}): return "Invalid history."
	for entry in saved.ledger:
		if not fields(entry, {"minute": "number", "amount": "number", "reason": "string"}): return "Invalid ledger."
	for pack in saved.packs:
		if not fields(pack, {"id": "string", "version": "string", "digest": "string"}): return "Invalid pack fingerprint."
	return ""
