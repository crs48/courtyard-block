class_name CBLab
extends RefCounted
## One-hour, two-node thermal network and finite resource/accounting experiment.
## State is JSON data; caches are rebuilt from pinned definitions. No scenes or wall clock.

const RUNTIME := "warm-homes-1.0.0"
const YEAR_HOURS := 8760
const MONTH_DAYS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const NAMES := ["Maya & Leo", "Nora & Jules", "Amara & Sam", "Iris & Felix", "Ada & Noor", "Luca & Rosa", "Eli & Ines", "Theo & Yuki", "Kai & Robin", "Sofia & Oscar", "Mina & Ari", "Alma & Oliver"]
var catalog: CBLabCatalog
var design: Dictionary
var state: Dictionary
var zones: Array = []
var inverse: Array = []
var house: Dictionary
var plant: Dictionary
var climate: Dictionary
var policy: Dictionary
var capital := 0
var wall_carbon := 0.0

static func default_design() -> Dictionary:
	return {"layout": "core:courtyard", "home": "core:home", "assembly": "core:light_wall", "climate": "core:continental", "plant": "core:heat_pump", "policy": "core:metered", "overrides": {}, "solar_kw": 8.0, "battery_kwh": 20.0, "battery_kw": 6.0, "grid_kw": 18.0, "tank_l": 2000.0, "rain_tank_l": 0.0, "water_l_day": 2200.0, "sewage_l_day": 2200.0, "waste_kg": 60.0, "pickup_days": 3, "seed": 2406}

static func design_error(value: Variant, content: CBLabCatalog) -> String:
	if not value is Dictionary: return "Design must be an object."
	var defaults := default_design()
	if value.size() != defaults.size(): return "Design fields do not match this model."
	for key in defaults:
		if not value.has(key): return "Missing design field: " + key
	var families := {"layout": "layouts", "home": "homes", "assembly": "assemblies", "climate": "climates", "plant": "plants", "policy": "policies"}
	for key in families:
		if not value[key] is String or content.definition(families[key], value[key]).is_empty(): return "Unknown " + key + " definition."
	var bounds := {"solar_kw": [0, 50], "battery_kwh": [0, 200], "battery_kw": [0, 30], "grid_kw": [0, 100], "tank_l": [0, 10000], "rain_tank_l": [0, 10000], "water_l_day": [0, 10000], "sewage_l_day": [0, 10000], "waste_kg": [1, 1000], "pickup_days": [1, 14], "seed": [1, 1000000]}
	for key in bounds:
		if not CBValidation.number(value[key]) or value[key] < bounds[key][0] or value[key] > bounds[key][1]: return key + " is outside the supported range."
	for key in ["pickup_days", "seed"]:
		if float(value[key]) != floorf(float(value[key])): return key + " must be a whole number."
	if not value.overrides is Dictionary: return "Home overrides must be an object."
	var ids: Array = content.definition("layouts", value.layout).placements.map(func(p: Dictionary) -> String: return p.id)
	for id in value.overrides:
		if not id in ids or not value.overrides[id] is String or content.definition("assemblies", value.overrides[id]).is_empty(): return "Invalid home assembly override: " + str(id)
	return ""

static func create(content: CBLabCatalog, chosen: Dictionary) -> Dictionary:
	var issue := design_error(chosen, content)
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	var sim := CBLab.new()
	sim.catalog = content
	sim.design = chosen.duplicate(true)
	sim.house = content.definition("homes", chosen.home)
	sim.plant = content.definition("plants", chosen.plant)
	sim.climate = content.definition("climates", chosen.climate)
	sim.policy = content.definition("policies", chosen.policy)
	issue = sim._compile()
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	sim._initialize()
	return {"ok": true, "simulation": sim, "message": "Design ready."}

func _compile() -> String:
	var layout := catalog.definition("layouts", design.layout)
	var ids: Dictionary = {}
	var owner_costs := {"west": 0, "east": 0, "commons": 0}
	var placements: Array = layout.placements.duplicate()
	placements.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	for place in placements:
		var assembly_id: String = design.overrides.get(place.id, design.assembly)
		var wall := catalog.assembly(assembly_id)
		var area: float = 2 * (house.width_m + house.floor_m2 / house.width_m) * house.height_m - house.glazing_m2
		var mass: float = wall.mass_kg_m2 * area + house.floor_m2 * (house.base_mass_kg_m2 + 150.0)
		if mass > place.support_capacity_kg: return place.id + ": estimated dead + assumed live load exceeds declared support capacity. Choose a lighter assembly or a supported layout. This is not a structural certification."
		var cost := roundi(area * float(wall.cost_cents_m2)) + int(house.base_cost_cents)
		owner_costs[place.owner] += cost
		capital += cost
		wall_carbon += area * float(wall.carbon_kg_m2)
		var p: Array = place.position
		var rotated := str(place.rotation) in ["90", "270"]
		var width: float = house.floor_m2 / house.width_m if rotated else house.width_m
		var depth: float = house.width_m if rotated else house.floor_m2 / house.width_m
		ids[place.id] = zones.size()
		zones.append({"id": place.id, "owner": place.owner, "position": p.duplicate(), "width": width, "depth": depth, "wall": wall, "assembly": assembly_id, "wall_area": area, "exposed": area, "mass_kg": mass, "support_kg": place.support_capacity_kg, "capital": cost, "air_c": house.floor_m2 * house.internal_mass_j_m2k + house.floor_m2 * house.height_m * 1200.0, "mass_c": maxf(100000.0, area * float(wall.capacity_j_m2k) * 0.5 + house.floor_m2 * 16000.0)})
	for a in zones.size():
		for b in range(a + 1, zones.size()):
			if absf(float(zones[a].position[1]) - float(zones[b].position[1])) < house.height_m and absf(float(zones[a].position[0]) - float(zones[b].position[0])) < (zones[a].width + zones[b].width) / 2 - 0.001 and absf(float(zones[a].position[2]) - float(zones[b].position[2])) < (zones[a].depth + zones[b].depth) / 2 - 0.001:
				return "Homes overlap: " + str(zones[a].id) + " and " + str(zones[b].id)
	var count := zones.size() * 2
	var matrix: Array = []
	for i in count:
		var row: Array = []
		row.resize(count)
		row.fill(0.0)
		matrix.append(row)
	for link in layout.party_walls:
		var a: int = ids[link.a]
		var b: int = ids[link.b]
		var za: Dictionary = zones[a]
		var zb: Dictionary = zones[b]
		var dx := absf(float(za.position[0]) - float(zb.position[0]))
		var dz := absf(float(za.position[2]) - float(zb.position[2]))
		var contact := 0.0
		if is_equal_approx(dx, (za.width + zb.width) / 2.0): contact = maxf(0.0, minf(za.depth, zb.depth) - dz) * float(house.height_m)
		if is_equal_approx(dz, (za.depth + zb.depth) / 2.0): contact = maxf(contact, maxf(0.0, minf(za.width, zb.width) - dx) * float(house.height_m))
		if not is_equal_approx(float(za.position[1]), float(zb.position[1])) or link.area_m2 > contact + 0.001: return "Party wall must connect touching homes with sufficient shared area: " + str(link.a)
		za.exposed -= float(link.area_m2)
		zb.exposed -= float(link.area_m2)
		var conductance := float(link.area_m2) / (float(za.wall.r) + float(zb.wall.r))
		matrix[2 * a][2 * a] += conductance
		matrix[2 * b][2 * b] += conductance
		matrix[2 * a][2 * b] -= conductance
		matrix[2 * b][2 * a] -= conductance
	for i in zones.size():
		var z: Dictionary = zones[i]
		if z.exposed < 0: return z.id + ": shared walls exceed envelope area."
		z["air_h"] = house.window_u * house.glazing_m2 + 0.33 * house.infiltration_ach * house.floor_m2 * house.height_m
		z["mass_h"] = 2.0 * (z.wall.u * z.exposed + house.floor_m2 * (house.roof_u + house.floor_u))
		z["air_mass_h"] = z.mass_h
		matrix[2 * i][2 * i] += z.air_c / 3600.0 + z.air_h + z.air_mass_h
		matrix[2 * i][2 * i + 1] -= z.air_mass_h
		matrix[2 * i + 1][2 * i] -= z.air_mass_h
		matrix[2 * i + 1][2 * i + 1] += z.mass_c / 3600.0 + z.mass_h + z.air_mass_h
	for owner in owner_costs:
		if owner_costs[owner] > 25000000: return "Construction exceeds " + owner + "'s €250,000 initial capital budget."
	var infrastructure := infrastructure_cost()
	if infrastructure > 5000000: return "Shared equipment exceeds the €50,000 capital grant. Reduce storage or solar."
	capital += infrastructure
	inverse = invert(matrix)
	if inverse.is_empty(): return "Thermal network could not be solved."
	return ""

func infrastructure_cost() -> int:
	return int(plant.capital_cents) + roundi(float(design.solar_kw) * 70000 + float(design.battery_kwh) * 15000 + float(design.tank_l) * 30 + float(design.rain_tank_l) * 35)

static func invert(matrix: Array) -> Array:
	var n := matrix.size()
	var rows: Array = []
	for i in n:
		var row: Array = matrix[i].duplicate()
		for j in n: row.append(1.0 if i == j else 0.0)
		rows.append(row)
	for col in n:
		var pivot := col
		for r in range(col + 1, n):
			if absf(rows[r][col]) > absf(rows[pivot][col]): pivot = r
		if absf(rows[pivot][col]) < 0.000000001: return []
		var old: Array = rows[col]
		rows[col] = rows[pivot]
		rows[pivot] = old
		var scale: float = rows[col][col]
		for j in 2 * n: rows[col][j] /= scale
		for r in n:
			if r == col: continue
			var factor: float = rows[r][col]
			for j in 2 * n: rows[r][j] -= factor * float(rows[col][j])
	var result: Array = []
	for row in rows: result.append(row.slice(n))
	return result

func _initialize() -> void:
	state = {"hour": 0, "homes": [], "owners": {"west": 25000000, "east": 25000000, "commons": 25000000}, "utility_cents": 500000, "shared_capital_cents": 5000000 - infrastructure_cost(), "water_l": float(design.tank_l), "rain_l": 0.0, "sewage_l": 0.0, "waste_kg": 0.0, "litter_kg": 0.0, "battery_kwh": 0.0, "next_service": int(plant.maintenance_days) * 24, "repair_until": 0, "awaiting_repair": false, "month_variable": 0, "month_fixed": 0, "month": 0, "history": [], "events": [], "ledger": [], "weather": weather(0), "grid_available": true, "totals": {"grid_kwh": 0.0, "solar_kwh": 0.0, "curtailed_kwh": 0.0, "electricity_served_kwh": 0.0, "battery_loss_kwh": 0.0, "unserved_kwh": 0.0, "heat_kwh": 0.0, "cool_kwh": 0.0, "water_import_l": 0.0, "rain_collected_l": 0.0, "rain_spill_l": 0.0, "rain_used_l": 0.0, "water_used_l": 0.0, "water_unserved_l": 0.0, "sewage_removed_l": 0.0, "sewage_overflow_l": 0.0, "waste_produced_kg": 0.0, "waste_collected_kg": 0.0, "operating_cents": 0, "income_cents": 0, "living_cents": 0, "owner_maintenance_cents": 0, "labor_hours": 0.0, "cold_person_hours": 0.0, "hot_person_hours": 0.0}}
	for i in zones.size():
		state.owners[zones[i].owner] -= zones[i].capital
		state.homes.append({"id": zones[i].id, "name": NAMES[i], "owner": zones[i].owner, "people": 3, "air_c": 20.0, "mass_c": 20.0, "min_c": 20.0, "max_c": 20.0, "cold_hours": 0.0, "hot_hours": 0.0, "occupied_hours": 0, "heat_kwh": 0.0, "cool_kwh": 0.0, "meter_kwh": 0.0, "month_meter": 0.0, "wallet_cents": 40000 if i % 3 == 0 else 90000, "billed_cents": 0, "paid_cents": 0, "arrears_cents": 0})
	state["initial_money"] = money() + capital
	_event("start", "A year to make room for everyone", "The same households face the same weather in both designs. All reference costs and weather are illustrative.")
	_record()

func money() -> int:
	var total: int = state.utility_cents + state.shared_capital_cents
	for amount in state.owners.values(): total += int(amount)
	for household in state.homes: total += int(household.wallet_cents)
	return total

static func date_label(hour: int) -> String:
	if hour >= YEAR_HOURS: return "Year 1 complete"
	var day := clampi(hour / 24, 0, 364)
	var month := 0
	while day >= MONTH_DAYS[month]:
		day -= int(MONTH_DAYS[month])
		month += 1
	return "%s %d · %02d:00" % [MONTHS[month], day + 1, hour % 24]

func weather(hour: int) -> Dictionary:
	var day := hour / 24
	var h := hour % 24
	var outage := hour >= int(climate.outage_day) * 24 + 6 and hour < int(climate.outage_day) * 24 + 6 + int(climate.outage_hours)
	if climate.has("hourly"):
		var row: Array = climate.hourly[hour % YEAR_HOURS]
		return {"temperature_c": float(row[0]), "solar_w_m2": float(row[1]), "rain_mm": float(row[2]), "outage": outage}
	var seasonal := cos(TAU * (day - 15.0) / 365.0)
	var noise := float(((day + int(design.seed)) * 48271) % 101) / 25.0 - 2.0
	var temp: float = climate.mean_c - climate.seasonal_c * seasonal + climate.diurnal_c * sin(TAU * (h - 9.0) / 24.0) + noise
	if day >= climate.cold_snap_day and day < climate.cold_snap_day + 5: temp -= float(climate.cold_snap_drop_c)
	var solar := maxf(0.0, sin(PI * (h - 6.0) / 12.0)) * (420.0 - 230.0 * seasonal)
	var rain: float = climate.rain_mm_day * 1.5 if day % 6 == 0 and h >= 3 and h < 7 else 0.0
	return {"temperature_c": temp, "solar_w_m2": solar, "rain_mm": rain, "outage": outage}

static func allocate(requests: Array, available: float, rule: String = "proportional") -> Array:
	var total := 0.0
	for request in requests: total += float(request)
	if rule == "proportional" or available >= total:
		return requests.map(func(v: float) -> float: return v * minf(1.0, available / maxf(total, 0.0000001)))
	var result: Array = []
	result.resize(requests.size())
	result.fill(0.0)
	var remaining := available
	for _round in requests.size():
		var active := 0
		for i in requests.size():
			if requests[i] - result[i] > 0.000001: active += 1
		if active == 0 or remaining <= 0.000001: break
		var share := remaining / active
		for i in requests.size():
			var addition := minf(share, float(requests[i]) - float(result[i]))
			result[i] += addition
			remaining -= addition
	return result

func _thermal(outside_c: float, solar: float, heating: Array, cooling: Array, essential_ratio: float = 1.0) -> Array:
	var rhs: Array = []
	var h: int = int(state.hour) % 24
	for i in zones.size():
		var z: Dictionary = zones[i]
		var s: Dictionary = state.homes[i]
		var occupied := h < 8 or h >= 16 + (i % 3) or int(state.hour / 24) % 7 in [5, 6]
		var gains: float = (240.0 if occupied else 60.0) + house.power_kwh_person_day * 3.0 / 24.0 * 700.0 * essential_ratio
		var solar_gain: float = solar * house.glazing_m2 * house.solar_gain * 0.5
		rhs.append(z.air_c / 3600.0 * s.air_c + z.air_h * outside_c + gains + solar_gain * 0.7 + (float(heating[i]) - float(cooling[i])) * 1000.0)
		rhs.append(z.mass_c / 3600.0 * s.mass_c + z.mass_h * outside_c + solar_gain * 0.3)
	var result: Array = []
	for row in inverse:
		var total := 0.0
		for j in rhs.size(): total += float(row[j]) * float(rhs[j])
		result.append(total)
	return result

func step() -> void:
	if state.hour >= YEAR_HOURS: return
	var hour := int(state.hour)
	var day := hour / 24
	var h := hour % 24
	var w := weather(hour)
	state.weather = w
	state.grid_available = not w.outage
	if w.outage and (hour == 0 or not weather(hour - 1).outage): _event("outage", "The grid went down", "Stored electricity and local generation now cover essential loads before heating and cooling.")
	if not w.outage and hour > 0 and weather(hour - 1).outage: _event("recovery", "Grid supply restored", "Check each household's cold hours and the wastewater backlog.")
	if not climate.has("hourly") and climate.cold_snap_drop_c > 0 and day == int(climate.cold_snap_day) and h == 0: _event("weather", "A cold spell begins", "Five cold days test insulation, heat capacity and the shared plant.")
	_maintenance()
	var n := zones.size()
	var zero: Array = []
	zero.resize(n)
	zero.fill(0.0)
	var unheated := _thermal(w.temperature_c, w.solar_w_m2, zero, zero)
	var heat_request: Array = []
	var cool_request: Array = []
	var total_heat := 0.0
	var total_cool := 0.0
	for i in n:
		heat_request.append(maxf(0.0, (20.0 - float(unheated[2 * i])) / float(inverse[2 * i][2 * i]) / 1000.0))
		cool_request.append(maxf(0.0, (float(unheated[2 * i]) - 26.0) / float(inverse[2 * i][2 * i]) / 1000.0))
		total_heat += float(heat_request.back())
		total_cool += float(cool_request.back())
	# A reversible shared plant has one mode per interval, not simultaneous heat/cool.
	if total_heat >= total_cool: cool_request.fill(0.0)
	else: heat_request.fill(0.0)
	var plant_ready: bool = not state.awaiting_repair and hour >= int(state.repair_until)
	var heating := allocate(heat_request, float(plant.heat_kw) if plant_ready else 0.0, policy.allocation)
	var cooling := allocate(cool_request, float(plant.cool_kw) if plant_ready else 0.0, policy.allocation)
	var cop := lerpf(float(plant.cold_cop), float(plant.cop), clampf((float(w.temperature_c) + 10.0) / 20.0, 0.0, 1.0))
	var base_kwh: float = house.power_kwh_person_day * 3.0 * n / 24.0
	var water_demand: float = house.water_l_person_day * 3.0 * n / 24.0
	var rain_capture: float = w.rain_mm * house.floor_m2 * n * 0.8 if design.rain_tank_l > 0 else 0.0
	var rain_added := minf(rain_capture, float(design.rain_tank_l) - float(state.rain_l))
	state.rain_l += rain_added
	state.totals.rain_collected_l += rain_capture
	state.totals.rain_spill_l += rain_capture - rain_added
	var rain_used := minf(float(state.rain_l), water_demand * 0.3)
	var potable_demand := water_demand - rain_used
	var water_possible := minf(float(design.water_l_day) / 24.0, maxf(0.0, float(design.tank_l) - float(state.water_l) + potable_demand))
	# Pumps and ordinary electrical use take priority over discretionary thermal loads.
	var pump_kwh := water_possible * 0.0003 + float(design.sewage_l_day) / 24.0 * 0.0002
	var essential := base_kwh + pump_kwh
	var thermal_requests: Array = []
	var thermal_demand := 0.0
	for i in n:
		var requested: float = heating[i] / cop + cooling[i] / float(plant.cool_cop)
		thermal_requests.append(requested)
		thermal_demand += requested
	var power := _dispatch(essential + thermal_demand, w)
	var essential_served := minf(essential, float(power.served))
	var essential_ratio := essential_served / maxf(essential, 0.000001)
	var allocated := allocate(thermal_requests, maxf(0, float(power.served) - essential_served), policy.allocation)
	for i in n:
		var ratio := float(allocated[i]) / maxf(0.0000001, float(thermal_requests[i]))
		heating[i] *= ratio
		cooling[i] *= ratio
		var electricity := float(allocated[i]) + essential_served / n
		state.homes[i].meter_kwh += electricity
		state.homes[i].month_meter += electricity
		state.homes[i].heat_kwh += heating[i]
		state.homes[i].cool_kwh += cooling[i]
		state.totals.heat_kwh += heating[i]
		state.totals.cool_kwh += cooling[i]
	var next := _thermal(w.temperature_c, w.solar_w_m2, heating, cooling, essential_ratio)
	for i in n:
		var home: Dictionary = state.homes[i]
		home.air_c = next[2 * i]
		home.mass_c = next[2 * i + 1]
		home.min_c = minf(home.min_c, home.air_c)
		home.max_c = maxf(home.max_c, home.air_c)
		if h < 8 or h >= 16 + (i % 3) or day % 7 in [5, 6]:
			home.occupied_hours += 1
			if home.air_c < 18:
				home.cold_hours += 1
				state.totals.cold_person_hours += 3
			if home.air_c > 28:
				home.hot_hours += 1
				state.totals.hot_person_hours += 3
	_resources(water_possible * essential_ratio, potable_demand, rain_used, essential_ratio)
	if h == 10 and day % int(design.pickup_days) == 0 and day > 0:
		var charge := 2000 + ceili(float(state.litter_kg) * 100)
		if _expense(charge, "Waste collection and street cleanup", false):
			state.totals.waste_collected_kg += state.waste_kg + state.litter_kg
			state.waste_kg = 0.0
			state.litter_kg = 0.0
			state.totals.labor_hours += 2.0
		else: _event("funds", "Waste collection missed", "The utility association could not pay the collector. Outstanding bills and the reserve contribution affect available funds.")
	state.hour += 1
	if int(state.hour) % 24 == 0:
		var month_end := 0
		for month in range(int(state.month) + 1): month_end += int(MONTH_DAYS[month])
		if int(state.hour) / 24 == month_end: _settle_month()
		_record()
	if state.hour == YEAR_HOURS: _event("complete", "A full year, ready to compare", "Review comfort, costs, resource shortages and the households carrying the largest bills. Try a change with the same weather.")

func _dispatch(requested: float, w: Dictionary) -> Dictionary:
	var solar: float = float(design.solar_kw) * float(w.solar_w_m2) / 1000.0
	state.totals.solar_kwh += solar
	var direct := minf(requested, solar)
	var remaining := requested - direct
	var discharged := minf(remaining, minf(float(design.battery_kw), float(state.battery_kwh) * 0.95))
	state.battery_kwh -= discharged / 0.95
	state.totals.battery_loss_kwh += discharged / 0.95 - discharged
	remaining -= discharged
	var grid := minf(remaining, minf(float(design.grid_kw), maxf(0, float(state.utility_cents) - 1.0) / 35.0)) if not w.outage else 0.0
	if grid > 0: _expense(ceili(grid * 35.0), "Electricity imports", true, false)
	state.totals.grid_kwh += grid
	var surplus := solar - direct
	var charging := minf(surplus, minf(float(design.battery_kw), maxf(0, float(design.battery_kwh) - float(state.battery_kwh)) / 0.95))
	state.battery_kwh += charging * 0.95
	state.totals.battery_loss_kwh += charging * 0.05
	state.totals.curtailed_kwh += surplus - charging
	var served := direct + discharged + grid
	state.totals.electricity_served_kwh += served
	state.totals.unserved_kwh += maxf(0.0, requested - served)
	return {"served": served}

func _resources(potable_import: float, potable_demand: float, rain_used: float, pump_ratio: float) -> void:
	var water_cost := ceili(potable_import * 0.5)
	if not _expense(water_cost, "Municipal water", false, false): potable_import = 0.0
	state.water_l += potable_import
	state.totals.water_import_l += potable_import
	var potable := minf(potable_demand, float(state.water_l))
	state.water_l -= potable
	state.rain_l -= rain_used
	var used := potable + rain_used
	state.totals.rain_used_l += rain_used
	state.totals.water_used_l += used
	state.totals.water_unserved_l += maxf(0.0, potable_demand - potable)
	state.sewage_l += used * 0.8
	var removal := minf(float(state.sewage_l), float(design.sewage_l_day) / 24.0 * pump_ratio)
	if not _expense(ceili(removal * 0.3), "Wastewater removal", false, false): removal = 0.0
	state.sewage_l -= removal
	state.totals.sewage_removed_l += removal
	var overflow := maxf(0.0, float(state.sewage_l) - 1000.0)
	state.sewage_l -= overflow
	state.totals.sewage_overflow_l += overflow
	var waste: float = house.waste_kg_person_day * 3.0 * zones.size() / 24.0
	state.waste_kg += waste
	state.totals.waste_produced_kg += waste
	var litter := maxf(0.0, float(state.waste_kg) - float(design.waste_kg))
	state.waste_kg -= litter
	state.litter_kg += litter
	if int(state.hour) % 24 == 23:
		if potable < potable_demand - 0.01: _event("water", "Water demand was unmet", "Municipal flow, stored potable water, pump power and funds constrain supply. Rainwater only substitutes for flushing.")
		if overflow > 0: _event("sewage", "Wastewater storage overflowed", "Removal capacity or power was insufficient. Overflow is recorded as discharge, not silently deleted.")
		if litter > 0: _event("waste", "Bins filled before pickup", "Increase storage, collect more frequently or change the waste demand assumptions in a home pack.")

func _maintenance() -> void:
	if int(state.hour) < int(state.next_service): return
	if _expense(int(plant.maintenance_cents), "Plant maintenance", false):
		state.repair_until = int(state.hour) + int(plant.repair_hours)
		state.next_service = int(state.hour) + int(plant.maintenance_days) * 24
		state.awaiting_repair = false
		state.totals.labor_hours += float(plant.labor_hours)
		_event("repair", "The shared plant is being serviced", "%d hours offline; %.1f paid labor hours. The utility association pays €%.0f." % [plant.repair_hours, plant.labor_hours, plant.maintenance_cents / 100.0])
	else:
		if not state.awaiting_repair: _event("funds", "Maintenance is waiting for funds", "The plant remains unavailable until the association can pay. Compare bills, arrears and the reserve policy.")
		state.awaiting_repair = true

func _expense(cents: int, reason: String, variable: bool, record: bool = true) -> bool:
	if cents <= 0: return true
	if state.utility_cents < cents: return false
	state.utility_cents -= cents
	state.totals.operating_cents += cents
	state["month_variable" if variable else "month_fixed"] += cents
	if record: _ledger("utility", "outside", cents, reason)
	return true

static func split_cents(cents: int, weights: Array) -> Array:
	var total := 0.0
	for weight in weights: total += float(weight)
	var result: Array = []
	var assigned := 0
	for i in weights.size():
		var share := floori(cents * float(weights[i]) / total) if total > 0 else cents / weights.size()
		result.append(share)
		assigned += share
	for i in cents - assigned: result[i % result.size()] += 1
	return result

func _settle_month() -> void:
	var weights: Array = state.homes.map(func(home: Dictionary) -> float: return float(home.month_meter) if policy.billing == "metered" else 1.0)
	var shares := split_cents(int(state.month_variable), weights)
	var fixed := split_cents(int(state.month_fixed), state.homes.map(func(_h: Dictionary) -> float: return 1.0))
	for i in state.homes.size():
		var home: Dictionary = state.homes[i]
		var income: int = 190000 + i % 3 * 40000
		var living: int = income - (6000 if i % 3 == 0 else 24000)
		home.wallet_cents += income - living
		state.totals.income_cents += income
		state.totals.living_cents += living
		var bill: int = shares[i] + fixed[i] + int(policy.reserve_cents_month)
		home.billed_cents += bill
		var owed: int = bill + int(home.arrears_cents)
		var paid := mini(int(home.wallet_cents), owed)
		home.wallet_cents -= paid
		home.arrears_cents = owed - paid
		home.paid_cents += paid
		home.month_meter = 0.0
		state.utility_cents += paid
		_ledger(home.id, "utility", paid, "%s utility bill and arrears" % MONTHS[int(state.month)])
		var upkeep := ceili(float(zones[i].capital) * 0.01 / 12.0)
		var available := mini(int(state.owners[home.owner]), upkeep)
		state.owners[home.owner] -= available
		state.totals.owner_maintenance_cents += available
		_ledger(home.owner, "outside", available, "Building upkeep")
	_event("bill", "%s accounts settled" % MONTHS[int(state.month)], "€%.0f operating costs, €%.0f outstanding household bills. %s allocation; reserve contribution €%.0f per household." % [(int(state.month_variable) + int(state.month_fixed)) / 100.0, arrears() / 100.0, policy.billing, policy.reserve_cents_month / 100.0])
	state.month += 1
	state.month_variable = 0
	state.month_fixed = 0

func arrears() -> int:
	var total := 0
	for home in state.homes: total += int(home.arrears_cents)
	return total

func _event(kind: String, title: String, detail: String) -> void:
	state.events.append({"hour": state.hour, "kind": kind, "title": title, "detail": detail})
	if state.events.size() > 160: state.events.pop_front()

func _ledger(from: String, to: String, cents: int, reason: String) -> void:
	state.ledger.append({"hour": state.hour, "from": from, "to": to, "cents": cents, "reason": reason})
	if state.ledger.size() > 320: state.ledger.pop_front()

func _record() -> void:
	var average := 0.0
	var minimum := INF
	for home in state.homes:
		average += float(home.air_c) / state.homes.size()
		minimum = minf(minimum, home.air_c)
	state.history.append({"hour": state.hour, "inside_c": average, "minimum_c": minimum, "outside_c": state.weather.temperature_c, "operating_cents": state.totals.operating_cents, "cold_hours": state.totals.cold_person_hours, "funds_cents": state.utility_cents})

func report() -> Dictionary:
	return {"hour": state.hour, "capital_cents": capital, "wall_carbon_kg": wall_carbon, "operating_cents": state.totals.operating_cents, "cold_person_hours": state.totals.cold_person_hours, "hot_person_hours": state.totals.hot_person_hours, "grid_kwh": state.totals.grid_kwh, "water_unserved_l": state.totals.water_unserved_l, "sewage_overflow_l": state.totals.sewage_overflow_l, "litter_kg": state.litter_kg, "arrears_cents": arrears(), "labor_hours": state.totals.labor_hours, "utility_cents": state.utility_cents, "homes": state.homes.duplicate(true), "totals": state.totals.duplicate(true)}
