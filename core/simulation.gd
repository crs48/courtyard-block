class_name CBSimulation
extends RefCounted
## Canonical state is data. No scene nodes or wall-clock randomness enter the model.

const STEP_MINUTES := 15
const SAVE_VERSION := 1
const FIRST_NAMES := ["Amara", "Leo", "Mina", "Oscar", "Sofia", "Jules", "Nora", "Theo", "Iris", "Felix", "Ada", "Sam", "Luca", "Rosa", "Eli", "Maya", "Noor", "Oliver", "Ari", "Ines", "Robin", "Yuki", "Alma", "Kai"]
const LAST_NAMES := ["Bauer", "Silva", "Chen", "Okafor", "Lind", "Martin", "Novak", "Ali", "Costa", "Park", "Singh", "Dubois"]
const INTERESTS := ["gardening", "music", "cooking", "books", "making", "art"]
var catalog: CBCatalog
var state: Dictionary = {}
var spatial := CBSpatial.new()
var spaces: Dictionary = {}
var household_incomes: Dictionary = {}
var last_step_usec := 0
var system_costs: Dictionary = {}

func _init(content: CBCatalog) -> void:
	catalog = content

func create(parameters: Dictionary = {}, seed: int = 2406) -> void:
	var config: Dictionary = {"floors": 6, "width": 36.0, "courtyard": 16.0, "population": 64, "material": "base:brick", "template": "base:courtyard"}
	config.merge(parameters, true)
	if config.get("scenario", "") == "evening":
		config.population = 24
		config.household_size = 3
	config.population = clampi(int(config.population), 1, 150)
	var layout: Dictionary = catalog.generators[config.template].call(config)
	state = {"schema_version": SAVE_VERSION, "name": "Our courtyard", "seed": seed, "rng": seed, "minute": 8 * 60, "parameters": config, "layout": layout, "residents": [], "households": [], "shops": [], "funds": 25000000, "policies": {"contribution": 90000, "shared_meals": false, "unlimited_funds": false}, "services": {"water": 1.0, "sewage": 1.0, "waste": 1.0, "power": 1.0}, "ledger": [], "history": [], "notices": [], "mod_state": {}, "packs": catalog.pack_lock(), "branch": {"parent": "", "origin_minute": 480}, "totals": {"water_l": 0.0, "power_kwh": 0.0, "waste_kg": 0.0}}
	_index_spaces()
	var homes: Array = layout.spaces.filter(func(space: Dictionary) -> bool: return space.kind == "home")
	var population := mini(int(config.population), homes.size() * 4)
	var household_size := clampi(int(config.get("household_size", maxi(2, ceili(float(population) / homes.size())))), 2, 4)
	state.parameters.population = population
	for i in population:
		var home: Dictionary = homes[i / household_size]
		var household_id := "household_" + str(i / household_size)
		if i % household_size == 0:
			state.households.append({"id": household_id, "home": home.id, "wallet": 350000, "arrears": 0})
		var interest: String = INTERESTS[_random(INTERESTS.size())]
		var personality := _random(3)
		state.residents.append({"id": "resident_%03d" % i, "name": FIRST_NAMES[i % FIRST_NAMES.size()] + " " + LAST_NAMES[(i / FIRST_NAMES.size() + _random(5)) % LAST_NAMES.size()], "household": household_id, "home": home.id, "interest": interest, "skill": ["craft", "care", "food", "design"][_random(4)], "preference": ["quiet", "community", "comfort"][personality], "income": 180000 + _random(180000), "needs": {"food": 80.0, "rest": 85.0, "social": 65.0, "comfort": 75.0}, "wellbeing": 76.0, "activity": "home", "node": home.node, "target": home.node, "position": home.position.duplicate(), "path": [], "travel_remaining": 0.0, "travel_total": 0.0, "unreachable": false, "reason": "Settling into a new home."})
	for home in homes:
		home.furniture = [{"id": "base:bed", "x": -1.5, "z": -1.0, "rotation": 0}, {"id": "base:table", "x": 1.0, "z": 0.7, "rotation": 0}, {"id": "base:plant", "x": 2.0, "z": -1.5, "rotation": 0}]
	var shop_spaces: Array = layout.spaces.filter(func(space: Dictionary) -> bool: return space.kind == "shop")
	var types := ["base:grocer", "base:cafe", "base:workshop", "base:studio"]
	for i in shop_spaces.size():
		state.shops.append({"space": shop_spaces[i].id, "business": types[i % types.size()] if i < 4 else "", "profit": 0, "wallet": 250000, "visits": 0})
	spatial.rebuild(layout)
	_index_incomes()
	_record_metrics()
	if config.get("scenario", "") == "evening": CBEvening.setup(self)

func _random(bound: int) -> int:
	state.rng = (int(state.rng) * 48271) % 2147483647
	return int(state.rng) % maxi(bound, 1)

func _index_spaces() -> void:
	spaces.clear()
	for space in state.layout.spaces:
		spaces[space.id] = space

func _index_incomes() -> void:
	household_incomes.clear()
	for person in state.residents:
		household_incomes[person.household] = float(household_incomes.get(person.household, 0)) + float(person.income)

func load_state(saved: Dictionary) -> Dictionary:
	var validation := validate_save(saved)
	if not validation.ok:
		return validation
	state = saved.duplicate(true)
	_index_spaces()
	_index_incomes()
	spatial.rebuild(state.layout)
	return {"ok": true, "message": "Community restored."}

func validate_save(saved: Dictionary) -> Dictionary:
	if int(saved.get("schema_version", 0)) != SAVE_VERSION:
		return {"ok": false, "message": "Unsupported save version."}
	var error := CBValidation.save_error(saved, catalog)
	if not error.is_empty(): return _result(false, error)
	if saved.has("evening") or saved.parameters.get("scenario", "") == "evening":
		error = CBEvening.save_error(saved, catalog)
		if not error.is_empty(): return _result(false, error)
	var pack_ids: Dictionary = {}
	for pack in saved.packs:
		if pack_ids.has(pack.id): return _result(false, "Duplicate pack fingerprint.")
		pack_ids[pack.id] = true
		if not catalog.packs.has(pack.id) or catalog.packs[pack.id].version != pack.version or catalog.packs[pack.id].digest != pack.digest:
			return {"ok": false, "message": "This save needs the matching pack: " + str(pack.id) + " " + str(pack.version)}
	if saved.packs.size() != catalog.packs.size():
		return {"ok": false, "message": "Installed pack set differs from this experiment. Restore the matching pack set."}
	if not catalog.generators.has(saved.parameters.template):
		return {"ok": false, "message": "Building generator is unavailable."}
	return {"ok": true, "message": "Valid save."}

func step() -> void:
	var started := Time.get_ticks_usec()
	if state.has("evening"):
		CBEvening.advance(self)
		last_step_usec = Time.get_ticks_usec() - started
		return
	state.minute = int(state.minute) + STEP_MINUTES
	var occupancy: Dictionary = {}
	for person in state.residents:
		_update_person(person, occupancy)
	for system in catalog.systems:
		if int(state.minute) % int(system.interval) == 0:
			var before := Time.get_ticks_usec()
			var effects: Variant = system.callback.call(state.duplicate(true))
			if effects is Array:
				_apply_effects(effects, str(system.id).get_slice(":", 0))
			system_costs[system.id] = Time.get_ticks_usec() - before
	if int(state.minute) % 1440 == 0:
		_settle_day()
	if int(state.minute) % 60 == 0:
		_record_metrics()
	last_step_usec = Time.get_ticks_usec() - started

func _update_person(person: Dictionary, occupancy: Dictionary) -> void:
	var hour := int(state.minute) % 1440 / 60
	var activity := "home"
	var destination: Dictionary = spaces[person.home]
	if hour < 7 or hour >= 23:
		activity = "rest"
	elif hour >= 9 and hour < 17:
		activity = "work"
		destination = spaces.city
		var index := int(str(person.id).get_slice("_", 1))
		if index < state.shops.size() * 2:
			var employer: Dictionary = state.shops[index / 2]
			if employer.business != "":
				destination = spaces[employer.space]
	elif hour >= 17 and hour < 19:
		var shopping_slot := int(str(person.id).get_slice("_", 1)) % 8
		if (int(state.minute) % 1440 - 17 * 60) / STEP_MINUTES == shopping_slot:
			activity = "shopping"
			destination = spaces.city
			for shop in state.shops:
				if catalog.get_definition("businesses", shop.business).get("kind") == "food":
					destination = spaces[shop.space]
					break
	elif hour >= 19 and hour < 21:
		activity = "social"
		destination = spaces.courtyard
	if int(person.target) != int(destination.node):
		var path := spatial.route(int(person.node), int(destination.node))
		person.unreachable = path.is_empty()
		if not person.unreachable:
			person.path = path
			person.target = destination.node
			var distance := 0.0
			for i in range(1, path.size()):
				distance += CBSpatial.vector(path[i - 1]).distance_to(CBSpatial.vector(path[i]))
			person.travel_total = maxf(STEP_MINUTES, ceilf(distance / 50.0))
			person.travel_remaining = person.travel_total
	person.activity = activity
	if float(person.travel_remaining) > 0.0:
		person.travel_remaining = maxf(0.0, float(person.travel_remaining) - STEP_MINUTES)
		if person.travel_remaining == 0.0:
			person.node = person.target
			person.position = destination.position.duplicate()
	var here: bool = int(person.node) == int(destination.node) and not person.unreachable
	var capacity := int(destination.capacity)
	if activity in ["shopping", "social"] and here:
		var used := int(occupancy.get(int(destination.node), 0))
		here = used < capacity
		if here:
			occupancy[int(destination.node)] = used + 1
	var needs: Dictionary = person.needs
	needs.food = clampf(float(needs.food) - 0.65, 0, 100)
	needs.rest = clampf(float(needs.rest) - 0.35, 0, 100)
	needs.social = clampf(float(needs.social) - 0.18, 0, 100)
	if here:
		if activity == "rest":
			needs.rest = minf(100, float(needs.rest) + 2.2)
		elif activity == "shopping":
			var household: Dictionary = state.households[int(str(person.household).get_slice("_", 1))]
			if household.wallet >= 600:
				household.wallet -= 600
				needs.food = minf(100, float(needs.food) + 55.0)
				for shop in state.shops:
					if shop.space == destination.id:
						shop.wallet += 600
						shop.visits += 1
		elif activity == "home":
			needs.food = minf(100, float(needs.food) + 1.8)
			needs.rest = minf(100, float(needs.rest) + 0.3)
		elif activity == "social":
			needs.social = minf(100, float(needs.social) + (3.0 if person.preference == "community" else 1.8))
	var material: Dictionary = catalog.get_definition("materials", state.parameters.material)
	var comfort := 52.0 + float(material.get("comfort", 0))
	for furniture in spaces[person.home].furniture:
		comfort += float(catalog.get_definition("furniture", furniture.id).get("benefit", 0))
	var reliability := 0.0
	for service in state.services:
		reliability += minf(1.0, float(state.services[service])) / 4.0
	needs.comfort = clampf(comfort * reliability, 0.0, 100.0)
	var social_weight := 1.6 if person.preference == "community" else 0.8
	var household_income := float(household_incomes.get(person.household, 0))
	var burden := float(state.policies.contribution) / maxf(household_income, 1.0)
	person.wellbeing = clampf((needs.food + needs.rest + needs.social * social_weight + needs.comfort) / (3.0 + social_weight) - maxf(0.0, burden - 0.3) * 35.0, 0, 100)
	var lowest := "food"
	for need in needs:
		if float(needs[need]) < float(needs[lowest]):
			lowest = need
	person.reason = "Would love more " + lowest + "." if float(needs[lowest]) < 65 else "Feeling settled and well supported."
	if not here and activity in ["shopping", "social"]:
		person.reason = "Waiting for space at " + str(destination.name) + "."
	if person.unreachable:
		person.reason = "Cannot reach " + str(destination.name) + "."

func _settle_day() -> void:
	var day := int(state.minute) / 1440
	for person in state.residents:
		var household: Dictionary = state.households[int(str(person.household).get_slice("_", 1))]
		household.wallet += int(person.income) / 30
	for household in state.households:
		var owed := int(state.policies.contribution) / 30
		var paid := mini(int(household.wallet), owed)
		household.wallet -= paid
		household.arrears += owed - paid
		_credit(paid, "Resident contributions")
	for shop in state.shops:
		if shop.business.is_empty():
			continue
		var business: Dictionary = catalog.get_definition("businesses", shop.business)
		var footfall := float(state.parameters.width) / 36.0
		var profit := int(float(business.daily_revenue) * footfall) - int(business.daily_cost)
		shop.wallet += profit
		var rent := mini(maxi(0, int(shop.wallet)), 2500)
		shop.wallet -= rent
		shop.profit = profit - rent
		_credit(rent, str(business.name) + " lease")
	var people: int = state.residents.size()
	var water := people * 130.0
	var power := people * 4.5
	var waste := people * 0.8
	state.totals.water_l += water
	state.totals.power_kwh += power
	state.totals.waste_kg += waste
	var maintenance := float(catalog.get_definition("materials", state.parameters.material).get("maintenance", 1.0))
	var expense := int(water * 0.5 + power * 28.0 + waste * 18.0 + state.households.size() * 125 * maintenance)
	var affordable := _spend(expense, "Utilities & maintenance")
	for service in state.services:
		state.services[service] = minf(1.0, float(state.services[service]) + 0.05) if affordable else maxf(0.25, float(state.services[service]) - 0.1)
	if not affordable:
		_notice("Operating funds are low. Services are under pressure.")
	if day % 7 == 0:
		_notice("A week together. Compare your community's progress in Experiments.")

func _credit(amount: int, reason: String) -> void:
	state.funds += amount
	_add_ledger(amount, reason)

func _spend(amount: int, reason: String) -> bool:
	if amount < 0 or (not state.policies.unlimited_funds and int(state.funds) < amount):
		return false
	if state.policies.unlimited_funds and int(state.funds) < amount:
		_credit(amount - int(state.funds), "Experiment grant")
	state.funds -= amount
	_add_ledger(-amount, reason)
	return true

func _add_ledger(amount: int, reason: String) -> void:
	state.ledger.append({"minute": state.minute, "amount": amount, "reason": reason})
	if state.ledger.size() > 500:
		state.ledger.pop_front()

func _notice(message: String) -> void:
	state.notices.append({"minute": state.minute, "text": message})
	if state.notices.size() > 30:
		state.notices.pop_front()

func _apply_effects(effects: Array, pack_prefix: String) -> void:
	# Validate a complete effect batch and reserve spending before applying any effects.
	var spending := 0
	for effect in effects:
		if not effect is Dictionary:
			return
		match effect.get("type", ""):
			"spend":
				if not effect.get("amount") is int and not effect.get("amount") is float:
					return
				if int(effect.amount) < 0:
					return
				spending += int(effect.amount)
			"need":
				if not effect.get("need", "") in ["food", "rest", "social", "comfort"] or not is_finite(float(effect.get("amount", NAN))):
					return
			"mod_state":
				if not str(effect.get("id", "")).begins_with(pack_prefix + ":"):
					return
			"notice":
				pass
			_:
				return
	if not state.policies.unlimited_funds and int(state.funds) < spending:
		return
	for effect in effects:
		match effect.type:
			"spend": _spend(int(effect.amount), str(effect.get("reason", pack_prefix)))
			"need":
				for person in state.residents:
					if person.id == effect.get("resident"):
						person.needs[effect.need] = clampf(float(person.needs[effect.need]) + float(effect.amount), 0, 100)
			"mod_state": state.mod_state[effect.id] = effect.get("value")
			"notice": _notice(str(effect.get("text", "")))

func command(action: Dictionary) -> Dictionary:
	if state.has("evening"):
		if str(action.get("type", "")).begins_with("evening_"): return CBEvening.command(self, action)
		return _result(false, "This scenario uses the Inspect, Build, Try and Workshop tools.")
	match action.get("type", ""):
		"policy":
			var key := str(action.get("key", ""))
			if not state.policies.has(key):
				return _result(false, "Unknown policy.")
			state.policies[key] = clampi(int(action.value), 30000, 200000) if key == "contribution" else bool(action.value)
			return _result(true, "Community policy updated.")
		"furnish":
			var space: Dictionary = spaces.get(action.get("space", ""), {})
			var item := catalog.get_definition("furniture", str(action.get("item", "")))
			if space.is_empty() or item.is_empty() or space.kind != "home":
				return _result(false, "Choose an apartment and a valid item.")
			if space.furniture.size() >= 12:
				return _result(false, "This apartment is fully furnished (12 items).")
			if not _spend(int(item.cost), "Furniture: " + str(item.name)):
				return _result(false, "Not enough shared funds.")
			var index: int = space.furniture.size()
			space.furniture.append({"id": item.id, "x": (index % 3 - 1) * 1.6, "z": (index / 3 - 1) * 1.6, "rotation": 0})
			return _result(true, str(item.name) + " added to " + str(space.name), true)
		"lease":
			var business := str(action.get("business", ""))
			if business != "" and catalog.get_definition("businesses", business).is_empty():
				return _result(false, "Unknown business.")
			for shop in state.shops:
				if shop.space == action.get("space"):
					shop.business = business
					return _result(true, "Shop tenancy updated.", true)
			return _result(false, "Shop not found.")
		"improve":
			if not _spend(250000, "Service reliability upgrade"):
				return _result(false, "Not enough shared funds.")
			for service in state.services:
				state.services[service] = 1.0
			return _result(true, "Services restored to full capacity.")
		"rebuild":
			var config: Dictionary = state.parameters.duplicate(true)
			config.merge(action.get("parameters", {}), true)
			config.floors = clampi(int(config.floors), 5, 7)
			config.width = clampf(float(config.width), 28, 48)
			config.courtyard = clampf(float(config.courtyard), 10, float(config.width) - 16)
			if not catalog.generators.has(config.template) or catalog.get_definition("materials", config.material).is_empty():
				return _result(false, "Unknown template or material.")
			var layout: Dictionary = catalog.generators[config.template].call(config)
			var layout_error := CBValidation.layout_error(layout, catalog)
			if not layout_error.is_empty(): return _result(false, layout_error)
			var homes: Array = layout.spaces.filter(func(space: Dictionary) -> bool: return space.kind == "home")
			if homes.size() < state.households.size():
				return _result(false, "This design needs at least %s homes for existing households." % state.households.size())
			var cost := building_cost(config)
			if not _spend(cost, "Building improvements"):
				return _result(false, "This change needs €%s in shared funds." % (cost / 100))
			for i in state.households.size():
				var previous: Dictionary = spaces[state.households[i].home]
				homes[i].furniture = previous.furniture.duplicate(true)
				state.households[i].home = homes[i].id
			state.layout = layout
			state.parameters = config
			_index_spaces()
			for person in state.residents:
				var household: Dictionary = state.households[int(str(person.household).get_slice("_", 1))]
				var home: Dictionary = spaces[household.home]
				person.home = home.id
				person.node = home.node
				person.target = home.node
				person.position = home.position.duplicate()
				person.path = []
				person.travel_remaining = 0
			var shops: Array = layout.spaces.filter(func(space: Dictionary) -> bool: return space.kind == "shop")
			var previous_shops: Array = state.shops
			state.shops = []
			for i in shops.size():
				var previous: Dictionary = previous_shops[i].duplicate(true) if i < previous_shops.size() else {"business": "", "profit": 0, "wallet": 250000, "visits": 0}
				previous.space = shops[i].id
				state.shops.append(previous)
			spatial.rebuild(layout)
			return _result(true, "Your new design is ready. Everyone has a home.", true)
	return _result(false, "Unknown command.")

func building_cost(config: Dictionary) -> int:
	var multiplier := float(catalog.get_definition("materials", config.material).get("cost_multiplier", 1.0))
	return int((250000.0 * absf(float(config.width) - float(state.parameters.width)) + 2000000 * absi(int(config.floors) - int(state.parameters.floors)) + 1000000) * multiplier)

static func _result(ok: bool, message: String, geometry_changed: bool = false) -> Dictionary:
	return {"ok": ok, "message": message, "geometry_changed": geometry_changed}

func metrics() -> Dictionary:
	var values: Array = state.residents.map(func(person: Dictionary) -> float: return float(person.wellbeing))
	values.sort()
	var total := 0.0
	for value in values:
		total += float(value)
	var low := 0.0
	var sample := maxi(1, ceili(values.size() * 0.1))
	for i in sample:
		low += float(values[i])
	return {"minute": int(state.minute), "wellbeing": total / maxi(1, values.size()), "bottom_decile": low / sample, "funds": int(state.funds), "water_l": float(state.totals.water_l), "power_kwh": float(state.totals.power_kwh), "waste_kg": float(state.totals.waste_kg)}

func _record_metrics() -> void:
	state.history.append(metrics())
	if state.history.size() > 24 * 90:
		state.history.pop_front()
