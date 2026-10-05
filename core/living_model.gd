class_name CBLivingModel
extends CBLab
## Rooms compile into one thermal zone per home. Touching cells infer party walls.
## The original annual model and its replay equations remain unchanged.
var plans: Array = []

static func build(content: CBLabCatalog, chosen: Dictionary, blueprint: Array) -> Dictionary:
	var issue := CBLab.design_error(chosen, content)
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	issue = plan_error(blueprint, content)
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	var model := CBLivingModel.new()
	model.catalog = content
	model.design = chosen.duplicate(true)
	model.plans = blueprint.duplicate(true)
	model.house = content.definition("homes", chosen.home).duplicate(true)
	model.plant = content.definition("plants", chosen.plant)
	model.climate = content.definition("climates", chosen.climate)
	model.policy = content.definition("policies", chosen.policy)
	issue = model._compile()
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	model._initialize()
	return {"ok": true, "simulation": model, "message": "Blueprint is buildable."}

static func cells(plan: Dictionary) -> Dictionary:
	var result := {}
	for room in plan.rooms:
		for x in range(int(room[0]), int(room[0] + room[2])):
			for z in range(int(room[1]), int(room[1] + room[3])): result[Vector2i(int(plan.x) + x, int(plan.z) + z)] = true
	return result

static func plan_error(value: Variant, content: CBLabCatalog) -> String:
	if not value is Array or value.size() < 1 or value.size() > 12: return "Use 1–12 homes."
	var occupied := {}
	var ids := {}
	var rooms := 0
	for plan in value:
		if not plan is Dictionary or plan.size() != 6: return "Invalid home blueprint."
		for key in ["id", "x", "z", "rooms", "assembly", "owner"]:
			if not plan.has(key): return "Missing blueprint field: " + key
		if not plan.id is String or not CBModLoader.valid_pack_id(plan.id) or ids.has(plan.id): return "Invalid or repeated home ID."
		ids[plan.id] = true
		if not plan.assembly is String or content.definition("assemblies", plan.assembly).is_empty() or not plan.owner in ["west", "east", "commons"]: return "Unknown assembly or owner."
		for key in ["x", "z"]:
			if not CBValidation.number(plan[key]) or absf(plan[key]) > 30 or floorf(plan[key]) != plan[key]: return "Homes must snap to the metre grid inside the site."
		if not plan.rooms is Array or plan.rooms.size() < 3 or plan.rooms.size() > 6: return "Each home needs its three base rooms and at most three additions."
		var expected := 0
		for room in plan.rooms:
			if not room is Array or room.size() != 4: return "A room needs x, z, width and depth."
			for number in room:
				if not CBValidation.number(number) or absf(number) > 24 or floorf(number) != number: return "Room dimensions must be whole metres."
			if room[2] < 2 or room[2] > 8 or room[3] < 2 or room[3] > 8: return "Room sides must be 2–8 metres."
			expected += int(room[2] * room[3])
		var filled := cells(plan)
		if filled.size() != expected: return "Rooms overlap within " + str(plan.id)
		var frontier: Array = [filled.keys()[0]]
		var visited := {frontier[0]: true}
		while not frontier.is_empty():
			var p: Vector2i = frontier.pop_back()
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = p + direction
				if filled.has(next) and not visited.has(next):
					visited[next] = true
					frontier.append(next)
		if visited.size() != filled.size(): return "Rooms must connect along an edge."
		for p in filled:
			if absi(p.x) > 31 or absi(p.y) > 31: return "Construction crosses the site boundary."
			if occupied.has(p): return "This footprint overlaps another home."
			# Reserve a small common utility yard; paths elsewhere are visual only.
			if p.x >= -4 and p.x < 4 and p.y >= -4 and p.y < 4: return "Keep the common utility yard clear."
			occupied[p] = true
		rooms += plan.rooms.size()
	if rooms > 48: return "This prototype supports at most 48 rooms."
	return ""

func _compile() -> String:
	var occupancy := {}
	var footprints: Array = []
	var total_floor := 0.0
	for i in plans.size():
		var footprint := cells(plans[i])
		footprints.append(footprint)
		for p in footprint: occupancy[p] = i
	var matrix: Array = []
	for i in plans.size() * 2:
		var row: Array = []
		row.resize(plans.size() * 2)
		row.fill(0.0)
		matrix.append(row)
	for i in plans.size():
		var plan: Dictionary = plans[i]
		var footprint: Dictionary = footprints[i]
		var floor_area := float(footprint.size())
		total_floor += floor_area
		var boundary := 0.0
		var exposed := 0.0
		var low := Vector2i(100, 100)
		var high := Vector2i(-100, -100)
		var wall := catalog.assembly(plan.assembly)
		for p: Vector2i in footprint:
			low = low.min(p)
			high = high.max(p + Vector2i.ONE)
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = p + direction
				if footprint.has(next): continue
				boundary += float(house.height_m)
				if not occupancy.has(next): exposed += float(house.height_m)
				else:
					var other := int(occupancy[next])
					var other_wall := catalog.assembly(plans[other].assembly)
					var conductance: float = house.height_m / (wall.r + other_wall.r)
					matrix[2 * i][2 * i] += conductance
					matrix[2 * i][2 * other] -= conductance
		var glazing := minf(8.0, exposed * 0.25)
		var area := boundary - glazing
		var cost := roundi(area * float(wall.cost_cents_m2) + floor_area * house.base_cost_cents / 48.0)
		var z := {"id": plan.id, "owner": plan.owner, "position": [(low.x + high.x) / 2.0, 0, (low.y + high.y) / 2.0], "width": high.x - low.x, "depth": high.y - low.y, "wall": wall, "assembly": plan.assembly, "wall_area": area, "exposed": exposed - glazing, "floor_m2": floor_area, "glazing_m2": glazing, "mass_kg": area * wall.mass_kg_m2 + floor_area * (house.base_mass_kg_m2 + 150.0), "support_kg": 300000.0, "capital": cost, "air_c": floor_area * (house.internal_mass_j_m2k + house.height_m * 1200.0), "mass_c": maxf(100000, area * wall.capacity_j_m2k * 0.5 + floor_area * 16000.0)}
		if z.mass_kg > z.support_kg: return "Declared support capacity exceeded."
		z.air_h = house.window_u * glazing + 0.33 * house.infiltration_ach * floor_area * house.height_m
		z.mass_h = 2.0 * (wall.u * z.exposed + floor_area * (house.roof_u + house.floor_u))
		z.air_mass_h = z.mass_h
		matrix[2 * i][2 * i] += z.air_c / 3600.0 + z.air_h + z.air_mass_h
		matrix[2 * i][2 * i + 1] -= z.air_mass_h
		matrix[2 * i + 1][2 * i] -= z.air_mass_h
		matrix[2 * i + 1][2 * i + 1] += z.mass_c / 3600.0 + z.mass_h + z.air_mass_h
		zones.append(z)
		capital += cost
		wall_carbon += area * float(wall.carbon_kg_m2)
	house.floor_m2 = total_floor / plans.size()
	capital += infrastructure_cost()
	inverse = invert(matrix)
	return "" if not inverse.is_empty() else "Thermal network could not be solved."

func _thermal(outside_c: float, solar: float, heating: Array, cooling: Array, essential_ratio: float = 1.0) -> Array:
	var rhs: Array = []
	var h: int = int(state.hour) % 24
	for i in zones.size():
		var z: Dictionary = zones[i]
		var s: Dictionary = state.homes[i]
		var occupied := h < 8 or h >= 16 + (i % 3) or int(state.hour / 24) % 7 in [5, 6]
		var gains: float = (240.0 if occupied else 60.0) + house.power_kwh_person_day * 3.0 / 24.0 * 700.0 * essential_ratio
		var solar_gain: float = solar * z.glazing_m2 * house.solar_gain * 0.5
		rhs.append(z.air_c / 3600.0 * s.air_c + z.air_h * outside_c + gains + solar_gain * 0.7 + (float(heating[i]) - float(cooling[i])) * 1000.0)
		rhs.append(z.mass_c / 3600.0 * s.mass_c + z.mass_h * outside_c + solar_gain * 0.3)
	var result: Array = []
	for row in inverse:
		var total := 0.0
		for j in rhs.size(): total += float(row[j]) * float(rhs[j])
		result.append(total)
	return result
