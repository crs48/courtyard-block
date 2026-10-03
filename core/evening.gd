class_name CBEvening
extends RefCounted
## A bounded, minute-resolved scenario. Definitions describe services; events explain outcomes.

const START := 960
const END := 1320
const CLUB_START := 1170
const CLUB_END := 1260
const VERSION := 1
const SERVICE_FIELDS := {"id": "string", "name": "string", "description": "string", "kind": "string", "open": "number", "close": "number", "duration": "number", "slots": "number", "stock": "number", "price": "number", "unit_cost": "number", "capital": "number", "staff": "number", "water": "number", "power": "number", "sewage": "number", "waste": "number", "remote_minutes": "number", "color": "string"}

static func definition_error(value: Variant) -> String:
	if not CBValidation.fields(value, SERVICE_FIELDS): return "Service needs all fields from the example, with their declared types."
	for key in value:
		if not SERVICE_FIELDS.has(key): return "Unsupported service field: " + str(key)
	if str(value.id).split(":").size() != 2 or not CBModLoader.valid_pack_id(str(value.id).get_slice(":", 0)) or not CBModLoader.valid_pack_id(str(value.id).get_slice(":", 1)): return "Use a namespaced ID such as my_pack:pickup."
	if value.name.is_empty() or value.name.length() > 60 or value.description.length() > 400: return "Use a name of 1–60 characters and a description under 400."
	if not value.kind in ["groceries", "meal"]: return "Supported activities are groceries and meal. New activities need an engine extension."
	for key in ["open", "close", "duration", "slots", "stock", "price", "unit_cost", "capital", "staff", "remote_minutes"]:
		if float(value[key]) != floorf(float(value[key])): return key + " must be a whole number."
	if value.open < START or value.close > END or value.close <= value.open or value.duration < 1 or value.duration > 60 or value.open + value.duration > value.close: return "Choose operating hours within 16:00–22:00 and a session of 1–60 minutes."
	if value.slots < 1 or value.slots > 24 or value.stock < 1 or value.stock > 150 or value.staff < 0 or value.staff > 1: return "Use 1–24 places, 1–150 portions, and 0 or 1 staff."
	for key in ["price", "unit_cost", "capital", "water", "power", "sewage", "waste", "remote_minutes"]:
		if value[key] < 0: return key + " cannot be negative."
	if value.price > 10000 or value.unit_cost > 10000 or value.capital > 1000000 or value.remote_minutes > 90: return "Money or travel time exceeds this scenario's limits."
	if value.water > 20 or value.power > 3 or value.sewage > 20 or value.waste > 1: return "Resource demand exceeds this scenario's per-portion limits."
	if not Color.html_is_valid(value.color): return "Choose a valid HTML color."
	return ""

static func default_design() -> Dictionary:
	return {"shortcut": false, "late_hours": false, "service": "", "space": "shop_0_0", "recipe": {}, "water": true, "power": true, "sewage": true, "collection": true}

static func setup(sim: CBSimulation, design: Dictionary = {}) -> void:
	var chosen := default_design()
	chosen.merge(design, true)
	sim.state.minute = START
	sim.state.name = "An evening back"
	sim.state.funds = 250000
	sim.state.history = []
	sim.state.ledger = []
	sim.state.notices = []
	sim.state.evening = {"version": VERSION, "phase": "design", "design": chosen, "undo": [], "actors": {}, "pantries": {}, "facilities": {}, "events": [], "capital": 0, "operating": 0, "income": 0, "external_wages": 0, "external_spending": 0, "staff_paid": 0, "baseline": {}, "attempts": [], "resources": {"water": 120.0, "power": 12.0, "sewage": 120.0, "waste": 0.0, "waste_capacity": 5.0, "collected": 0.0}}
	var work_ends := [1020, 1040, 1060, 1090, 1095, 1100, 1110, 1085]
	for i in sim.state.residents.size():
		var person: Dictionary = sim.state.residents[i]
		var household: int = i / 3
		var work_end: int = work_ends[household % work_ends.size()] if i % 3 == 0 else 1020 + (i % 3) * 10
		person.name = ["Maya Chen", "Leo Silva", "Nora Bauer"][i] if i < 3 else person.name
		person.reason = "Finishes work at %s. Wants time in the courtyard this evening." % clock(work_end)
		person.activity = "work"
		person.node = sim.spaces.city.node
		person.target = person.node
		person.position = sim.spaces.city.position.duplicate()
		person.path = []
		person.travel_remaining = 0
		sim.state.evening.actors[person.id] = {"work_end": work_end, "status": "work", "until": work_end, "destination": "city", "service": "", "meal_at": -1, "free": 0, "travel": 0, "wait": 0, "labor": 0, "spent": 0, "tried": [], "paid": false, "shopper": i % 3 == 0, "pace": 1.4 if household == 7 else 1.0, "staff": "", "queued_at": 0}
	for household in sim.state.households:
		household.wallet = 35000
		sim.state.evening.pantries[household.id] = {"raw": 0, "meals": 0}
	sim._record_metrics()

static func clock(minute: int) -> String:
	return "%02d:%02d" % [minute / 60, minute % 60]

static func service_definition(sim: CBSimulation, design: Dictionary) -> Dictionary:
	if design.service == "workshop:prototype": return design.recipe
	return sim.catalog.get_definition("evening_services", str(design.service))

static func price(sim: CBSimulation, design: Dictionary) -> int:
	var definition := service_definition(sim, design)
	return (30000 if design.shortcut else 0) + (15000 if design.late_hours else 0) + int(definition.get("capital", 0))

static func command(sim: CBSimulation, action: Dictionary) -> Dictionary:
	var e: Dictionary = sim.state.evening
	if action.type == "evening_reset":
		var design: Dictionary = e.design.duplicate(true)
		var baseline: Dictionary = e.baseline.duplicate(true)
		var attempts: Array = e.attempts.duplicate(true)
		if e.phase == "complete":
			attempts.append(report(sim))
			if attempts.size() > 8: attempts.pop_front()
		var seed_value := int(sim.state.seed)
		sim.create({"scenario": "evening", "population": 24, "household_size": 3}, seed_value)
		sim.state.evening.design = design
		sim.state.evening.baseline = baseline
		sim.state.evening.attempts = attempts
		return result(true, "Back at 16:00 with the same people and resources. Try another idea.", true)
	if e.phase != "design": return result(false, "Choose Try another idea to edit a copy of the starting evening.")
	if action.type == "evening_undo":
		if e.undo.is_empty(): return result(false, "There are no design changes to undo.")
		e.design = e.undo.pop_back()
		return result(true, "Design change undone.", true)
	if action.type == "evening_start":
		return start(sim)
	var candidate: Dictionary = e.design.duplicate(true)
	match action.type:
		"evening_design":
			var key := str(action.get("key", ""))
			if not key in ["shortcut", "late_hours", "water", "power", "sewage", "collection"] or not action.get("value") is bool: return result(false, "Unknown design setting.")
			candidate[key] = action.value
		"evening_service":
			var id := str(action.get("id", ""))
			if not id.is_empty() and sim.catalog.get_definition("evening_services", id).is_empty(): return result(false, "Service definition is unavailable.")
			candidate.service = id
			candidate.space = str(action.get("space", "shop_0_0"))
		"evening_recipe":
			var recipe: Variant = action.get("recipe")
			var error := definition_error(recipe)
			if not error.is_empty(): return result(false, error)
			candidate.recipe = recipe.duplicate(true)
			candidate.recipe.id = "workshop:prototype"
			candidate.service = "workshop:prototype"
		"evening_space": candidate.space = str(action.get("space", ""))
		_: return result(false, "Unknown evening action.")
	if not sim.spaces.has(candidate.space) or sim.spaces[candidate.space].kind != "shop": return result(false, "Choose an available ground-floor room.")
	var definition := service_definition(sim, candidate)
	var required := price(sim, candidate) + int(definition.get("stock", 0)) * int(definition.get("unit_cost", 0))
	if required > sim.state.funds: return result(false, "This design and its opening stock exceed the shared budget.")
	e.undo.append(e.design.duplicate(true))
	if e.undo.size() > 20: e.undo.pop_front()
	e.design = candidate
	return result(true, "Design ready to try. Costs are charged when the evening starts.", true)

static func result(ok: bool, message: String, geometry: bool = false) -> Dictionary:
	return {"ok": ok, "message": message, "geometry_changed": geometry}

static func _external(id: String, name_value: String, distance: int, closing: int, cost: int) -> Dictionary:
	return {"id": id, "name": name_value, "description": "Outside service", "kind": "groceries", "open": START, "close": closing, "duration": 4, "slots": 2, "stock": 120, "price": cost, "unit_cost": 0, "capital": 0, "staff": 0, "water": 0.0, "power": 0.0, "sewage": 0.0, "waste": 0.0, "remote_minutes": distance, "color": "#698a67"}

static func start(sim: CBSimulation) -> Dictionary:
	var e: Dictionary = sim.state.evening
	var definition := service_definition(sim, e.design)
	var capital := price(sim, e.design)
	var stock_cost := int(definition.get("stock", 0)) * int(definition.get("unit_cost", 0))
	if capital + stock_cost > sim.state.funds: return result(false, "Not enough funds for construction and opening stock.")
	e.capital = capital
	sim._spend(capital, "Evening design construction")
	e.facilities = {}
	var grocer := _external("evening:grocer", "Neighbourhood grocer", 12 if e.design.shortcut else 28, 1200 if e.design.late_hours else 1110, 400)
	_add_facility(e, grocer, "city", false)
	_add_facility(e, _external("evening:market", "Late market", 38, END, 650), "city", false)
	if not definition.is_empty():
		_add_facility(e, definition, e.design.space, true)
		_pay(sim, stock_cost, "Opening food delivery")
		if definition.staff == 1:
			e.actors[sim.state.residents[2].id].staff = definition.id
	if e.design.late_hours:
		e.actors[sim.state.residents[5].id].staff = "evening:grocer"
	e.phase = "running"
	_event(sim, "", "start", "Evening started. Follow the grocery trips, then compare everyone's time.")
	return result(true, "The evening is underway.")

static func _add_facility(e: Dictionary, definition: Dictionary, space: String, local: bool) -> void:
	e.facilities[definition.id] = {"definition": definition.duplicate(true), "space": space, "local": local, "stock": int(definition.stock), "busy": [], "served": 0}

static func _pay(sim: CBSimulation, amount: int, reason: String) -> bool:
	if not sim._spend(amount, reason): return false
	sim.state.evening.operating += amount
	return true

static func _event(sim: CBSimulation, actor: String, kind: String, message: String) -> void:
	var entries: Array = sim.state.evening.events
	entries.append({"minute": int(sim.state.minute), "actor": actor, "kind": kind, "text": message})
	if entries.size() > 1024: entries.pop_front()
	if not actor.is_empty():
		for person in sim.state.residents:
			if person.id == actor:
				person.reason = message
				break

static func travel_time(sim: CBSimulation, person: Dictionary, facility: Dictionary) -> int:
	var actor: Dictionary = sim.state.evening.actors[person.id]
	var route := sim.spatial.route(int(person.node), int(sim.spaces[facility.space].node))
	if route.is_empty(): return 10000
	var metres := 0.0
	for i in range(1, route.size()): metres += CBSpatial.vector(route[i - 1]).distance_to(CBSpatial.vector(route[i]))
	return maxi(1, ceili((metres / 50.0 + float(facility.definition.remote_minutes)) * float(actor.pace)))

static func _move(sim: CBSimulation, person: Dictionary, destination: String, duration: int, next_status: String) -> void:
	var actor: Dictionary = sim.state.evening.actors[person.id]
	var target: Dictionary = sim.spaces[destination]
	person.path = sim.spatial.route(int(person.node), int(target.node))
	person.target = target.node
	person.travel_total = duration
	person.travel_remaining = duration
	actor.destination = destination
	actor.status = next_status
	actor.until = int(sim.state.minute) + duration
	person.activity = "travelling"

static func advance(sim: CBSimulation) -> void:
	var e: Dictionary = sim.state.evening
	if e.phase != "running": return
	for _minute in CBSimulation.STEP_MINUTES:
		if int(sim.state.minute) >= END: break
		sim.state.minute += 1
		var now := int(sim.state.minute)
		for facility in e.facilities.values():
			facility.busy = facility.busy.filter(func(slot: Dictionary) -> bool: return int(slot.until) > now)
		if now == 1260 and e.design.collection and _pay(sim, 1200, "Scheduled waste collection"):
			e.resources.collected += e.resources.waste
			e.resources.waste = 0.0
			_event(sim, "", "collection", "Waste collected at 21:00. Storage is available again.")
		# Stable rotating priority avoids always giving the first household the final slot.
		for offset in sim.state.residents.size():
			var index: int = (offset + now) % sim.state.residents.size()
			_update(sim, sim.state.residents[index])
		if now % 60 == 0: sim._record_metrics()
	if sim.state.minute == END:
		e.phase = "complete"
		_event(sim, "", "complete", "The evening is complete. Compare the same neighbours, then try another idea.")

static func _staffing(sim: CBSimulation, person: Dictionary, actor: Dictionary) -> bool:
	if actor.staff.is_empty(): return false
	var e: Dictionary = sim.state.evening
	var facility: Dictionary = e.facilities[actor.staff]
	var opening := int(facility.definition.open) if facility.local else 1110
	var closing := int(facility.definition.close)
	var now := int(sim.state.minute)
	# Reserve preparation and the whole shift; this cannot overlap another activity.
	if now < opening - 15 or now >= closing: return false
	if actor.status != "staff":
		if actor.status not in ["idle", "work", "staff_ready"] or (actor.status == "work" and now < actor.work_end): return false
		actor.status = "staff"
		actor.until = closing
		actor.destination = facility.space
		person.position = sim.spaces[facility.space].position.duplicate()
		person.node = sim.spaces[facility.space].node
		person.target = person.node
		person.path = []
		_event(sim, person.id, "staff", "Preparing and staffing %s until %s; this uses their evening too." % [facility.definition.name, clock(closing)])
	if not _pay(sim, 25, "Service shift wage"):
		person.activity = "waiting for wages"
		return true
	var household: Dictionary = sim.state.households[int(str(person.household).get_slice("_", 1))]
	household.wallet += 25
	e.staff_paid += 25
	actor.labor += 1
	person.activity = "staffing"
	return true

static func _update(sim: CBSimulation, person: Dictionary) -> void:
	var e: Dictionary = sim.state.evening
	var actor: Dictionary = e.actors[person.id]
	var now := int(sim.state.minute)
	person.needs.food = maxf(0, float(person.needs.food) - 0.07)
	person.needs.rest = maxf(0, float(person.needs.rest) - 0.025)
	person.wellbeing = (float(person.needs.food) + float(person.needs.rest) + float(person.needs.social) + float(person.needs.comfort)) / 4.0
	if not actor.paid and now >= actor.work_end:
		var household: Dictionary = sim.state.households[int(str(person.household).get_slice("_", 1))]
		household.wallet += 8000
		e.external_wages += 8000
		actor.paid = true
		_event(sim, person.id, "work", "Finished outside work. €80 wages received by the household.")
	if _staffing(sim, person, actor): return
	if actor.status == "staff" and now >= actor.until:
		actor.status = "idle"
		_event(sim, person.id, "staff", "Shift finished after %d minutes of paid preparation and service." % int(actor.labor))
		var workplace: Dictionary = e.facilities[actor.staff]
		if workplace.local and workplace.definition.kind == "meal" and actor.meal_at < 0:
			actor.service = actor.staff
			_serve(sim, person, true)
			if actor.status == "service": return
	if actor.status == "work" and now >= actor.until:
		actor.status = "idle"
	if actor.status == "work": return
	if actor.status in ["outbound", "returning", "walking_home"]:
		actor.travel += 1
		person.travel_remaining = maxi(0, int(actor.until) - now)
		if now < actor.until: return
		person.node = person.target
		person.position = sim.spaces[actor.destination].position.duplicate()
		if actor.status == "outbound":
			actor.status = "queue"
			actor.queued_at = now
		else:
			actor.status = "idle"
	if actor.status == "queue":
		_serve(sim, person)
		return
	if actor.status == "service":
		if now < actor.until: return
		var facility: Dictionary = e.facilities[actor.service]
		if facility.definition.kind == "meal":
			_eaten(sim, person, str(facility.definition.name))
		else:
			e.pantries[person.household].raw += 3
			_event(sim, person.id, "groceries", "Collected three portions at %s. Bringing groceries home." % facility.definition.name)
			_move(sim, person, person.home, travel_time(sim, person, facility), "returning")
		return
	if actor.status == "cooking":
		actor.labor += 1
		if now < actor.until: return
		e.pantries[person.household].meals += 3
		actor.status = "idle"
		_event(sim, person.id, "cooking", "Cooked three portions for the household. Dinner is ready.")
	if actor.status == "eating":
		if now < actor.until: return
		_eaten(sim, person, "home")
	if actor.status != "idle": return
	if actor.meal_at >= 0:
		if now >= CLUB_START and now < CLUB_END:
			if person.node != sim.spaces.courtyard.node:
				person.path = sim.spatial.route(int(person.node), int(sim.spaces.courtyard.node))
				person.node = sim.spaces.courtyard.node
				person.target = person.node
				person.position = sim.spaces.courtyard.position.duplicate()
			actor.free += 1
			person.activity = "evening in the courtyard"
			person.needs.social = minf(100, float(person.needs.social) + 0.15)
		else: person.activity = "free time"
		return
	if not actor.staff.is_empty():
		var facility: Dictionary = e.facilities[actor.staff]
		var begins := int(facility.definition.open) if facility.local else 1110
		if now < begins - 15:
			# A shift is a commitment, not a second job layered over a grocery trip.
			actor.status = "staff_ready"
			person.activity = "available before shift"
			return
	var pantry: Dictionary = e.pantries[person.household]
	if person.node != sim.spaces[person.home].node and not actor.shopper:
		_move(sim, person, person.home, 3, "walking_home")
		return
	if pantry.meals > 0:
		pantry.meals -= 1
		actor.status = "eating"
		actor.until = now + 15
		person.activity = "eating at home"
		return
	if actor.shopper and pantry.raw >= 3 and person.node == sim.spaces[person.home].node:
		var error := _resources_error(e, 6.0, 0.6, 6.0, 0.36)
		if error.is_empty():
			pantry.raw -= 3
			_consume(sim, 6.0, 0.6, 6.0, 0.36)
			actor.status = "cooking"
			actor.until = now + 25
			person.activity = "cooking for household"
		else: _reason_once(sim, person, error)
		return
	var best := ""
	var best_finish := 100000
	for id in e.facilities:
		var facility: Dictionary = e.facilities[id]
		var definition: Dictionary = facility.definition
		if id in actor.tried or (definition.kind == "groceries" and (not actor.shopper or pantry.raw > 0)): continue
		var travel := travel_time(sim, person, facility)
		var arrive := maxi(now + travel, int(definition.open))
		if arrive + int(definition.duration) > int(definition.close):
			if id == "evening:grocer":
				_reason_once(sim, person, "Grocer closes at %s; arrival would be %s. Looking for another option." % [clock(int(definition.close)), clock(now + travel)])
			continue
		var finish := arrive + int(definition.duration) + (travel + 40 if definition.kind == "groceries" else 0)
		if finish < best_finish:
			best = str(id)
			best_finish = finish
	if not best.is_empty():
		actor.service = best
		var facility: Dictionary = e.facilities[best]
		_event(sim, person.id, "travel", "Heading to %s · %s min each way." % [facility.definition.name, travel_time(sim, person, facility)])
		_move(sim, person, facility.space, travel_time(sim, person, facility), "outbound")
	else:
		person.activity = "waiting for dinner"
		actor.wait += 1
		if actor.shopper: _reason_once(sim, person, "No feasible food service remains this evening.")

static func _reason_once(sim: CBSimulation, person: Dictionary, message: String) -> void:
	if person.reason != message: _event(sim, person.id, "blocked", message)

static func _serve(sim: CBSimulation, person: Dictionary, staff_meal: bool = false) -> void:
	var e: Dictionary = sim.state.evening
	var actor: Dictionary = e.actors[person.id]
	var facility: Dictionary = e.facilities[actor.service]
	var d: Dictionary = facility.definition
	var now := int(sim.state.minute)
	var quantity := 3 if d.kind == "groceries" else 1
	var cost := int(d.price) * quantity
	var household: Dictionary = sim.state.households[int(str(person.household).get_slice("_", 1))]
	var failure := ""
	staff_meal = staff_meal and actor.staff == actor.service and facility.local and d.kind == "meal" and now == int(d.close)
	if not staff_meal and now + int(d.duration) > int(d.close): failure = "Closed before service could finish."
	elif facility.stock < quantity: failure = "Not enough food in stock."
	elif household.wallet < cost: failure = "Household cannot afford this purchase."
	elif facility.local: failure = _resources_error(e, float(d.water) * quantity, float(d.power) * quantity, float(d.sewage) * quantity, float(d.waste) * quantity)
	if not failure.is_empty():
		_event(sim, person.id, "blocked", "%s: %s" % [d.name, failure])
		actor.tried.append(actor.service)
		actor.status = "idle"
		return
	var staffed := true
	if not staff_meal and (int(d.staff) == 1 or (actor.service == "evening:grocer" and e.design.late_hours and now >= 1110)):
		staffed = false
		for worker_id in e.actors:
			var worker: Dictionary = e.actors[worker_id]
			if worker.staff == actor.service and worker.status == "staff" and sim.state.funds >= 25: staffed = true
	if now < d.open or facility.busy.size() >= int(d.slots) or not staffed:
		actor.wait += 1
		person.activity = "waiting at " + str(d.name)
		_reason_once(sim, person, "%s: %s" % [d.name, "Not open yet." if now < d.open else ("Waiting for staff." if not staffed else "All places are occupied; waiting for a space.")])
		return
	# Reserve money, stock, inputs and output capacity together before granting a slot.
	household.wallet -= cost
	actor.spent += cost
	facility.stock -= quantity
	facility.served += quantity
	if facility.local:
		sim._credit(cost, str(d.name) + " sales")
		e.income += cost
		_consume(sim, float(d.water) * quantity, float(d.power) * quantity, float(d.sewage) * quantity, float(d.waste) * quantity)
	else: e.external_spending += cost
	actor.status = "service"
	actor.until = now + int(d.duration)
	facility.busy.append({"actor": person.id, "until": actor.until})
	person.activity = "eating together" if d.kind == "meal" else "collecting groceries"
	_event(sim, person.id, "service", "%s: a place and %s portion(s) reserved. Paid €%.2f." % [d.name, quantity, cost / 100.0])

static func _resources_error(e: Dictionary, water: float, power: float, sewage: float, waste: float) -> String:
	for demand in [["water", water], ["power", power], ["sewage", sewage]]:
		if demand[1] > 0 and not e.design[demand[0]]: return str(demand[0]).capitalize() + " is disconnected."
		if float(e.resources[demand[0]]) + 0.00001 < demand[1]: return "Insufficient " + str(demand[0]) + " capacity."
	if float(e.resources.waste) + waste > float(e.resources.waste_capacity) + 0.00001: return "Waste storage is full; collection is needed."
	return ""

static func _consume(sim: CBSimulation, water: float, power: float, sewage: float, waste: float) -> void:
	var r: Dictionary = sim.state.evening.resources
	r.water -= water
	r.power -= power
	r.sewage -= sewage
	r.waste += waste
	sim.state.totals.water_l += water
	sim.state.totals.power_kwh += power
	sim.state.totals.waste_kg += waste

static func _eaten(sim: CBSimulation, person: Dictionary, where_value: String) -> void:
	var actor: Dictionary = sim.state.evening.actors[person.id]
	actor.meal_at = int(sim.state.minute)
	actor.status = "idle"
	person.needs.food = minf(100, float(person.needs.food) + 45)
	_event(sim, person.id, "meal", "Finished dinner at %s at %s." % [where_value, clock(actor.meal_at)])

static func report(sim: CBSimulation) -> Dictionary:
	var e: Dictionary = sim.state.evening
	var result_value := {"fed": 0, "on_time": 0, "free": 0, "travel": 0, "wait": 0, "labor": 0, "spending": 0, "people": [], "capital": int(e.capital), "operating": int(e.operating), "income": int(e.income), "water": float(sim.state.totals.water_l), "power": float(sim.state.totals.power_kwh), "waste": float(sim.state.totals.waste_kg), "minute": int(sim.state.minute), "design": e.design.duplicate(true)}
	for person in sim.state.residents:
		var a: Dictionary = e.actors[person.id]
		result_value.people.append({"id": person.id, "name": person.name, "meal_at": a.meal_at, "free": a.free, "labor": a.labor, "travel": a.travel, "wait": a.wait, "spent": a.spent})
		if a.meal_at >= 0: result_value.fed += 1
		if a.free >= 45: result_value.on_time += 1
		for key in ["free", "travel", "wait", "labor"]: result_value[key] += int(a[key])
		result_value.spending += int(a.spent)
	return result_value

static func save_error(saved: Dictionary, catalog: CBCatalog) -> String:
	var e: Variant = saved.get("evening")
	if not CBValidation.fields(e, {"version": "number", "phase": "string", "design": "object", "actors": "object", "pantries": "object", "facilities": "object", "resources": "object", "events": "array", "undo": "array", "baseline": "object", "attempts": "array", "capital": "number", "operating": "number", "income": "number", "external_wages": "number", "external_spending": "number", "staff_paid": "number"}): return "Incomplete evening save."
	if e.version != VERSION or not e.phase in ["design", "running", "complete"] or saved.minute < START or saved.minute > END: return "Unsupported evening state."
	if saved.residents.size() != 24 or saved.households.size() != 8 or e.events.size() > 1024 or e.undo.size() > 20 or e.attempts.size() > 8: return "Invalid evening population or history."
	for design in [e.design] + e.undo:
		if not CBValidation.fields(design, {"shortcut": "bool", "late_hours": "bool", "service": "string", "space": "string", "recipe": "object", "water": "bool", "power": "bool", "sewage": "bool", "collection": "bool"}): return "Invalid evening design."
		if design.service == "workshop:prototype":
			if not definition_error(design.recipe).is_empty() or design.recipe.id != "workshop:prototype": return "Invalid workshop prototype."
		elif not design.service.is_empty() and catalog.get_definition("evening_services", design.service).is_empty(): return "Missing service pack."
		var room_found := false
		for space in saved.layout.spaces:
			if space.id == design.space and space.kind == "shop": room_found = true
		if not room_found: return "Unknown service room."
	if not CBValidation.fields(e.resources, {"water": "number", "power": "number", "sewage": "number", "waste": "number", "waste_capacity": "number", "collected": "number"}): return "Invalid resources."
	for value in e.resources.values():
		if not CBValidation.number(value) or value < -0.00001: return "Negative or invalid resource balance."
	for person in saved.residents:
		var a: Variant = e.actors.get(person.id)
		if not CBValidation.fields(a, {"work_end": "number", "status": "string", "until": "number", "destination": "string", "service": "string", "meal_at": "number", "free": "number", "travel": "number", "wait": "number", "labor": "number", "spent": "number", "tried": "array", "paid": "bool", "shopper": "bool", "pace": "number", "staff": "string", "queued_at": "number"}): return "Invalid evening resident."
		if not a.status in ["work", "idle", "staff", "staff_ready", "outbound", "returning", "walking_home", "queue", "service", "cooking", "eating"] or a.pace <= 0 or a.tried.size() > 16: return "Invalid activity."
		for key in ["service", "staff"]:
			if not a[key].is_empty() and not e.facilities.has(a[key]): return "Missing activity provider."
		var found := false
		for space in saved.layout.spaces:
			if space.id == a.destination: found = true
		if not found: return "Unknown activity destination."
	for household in saved.households:
		var pantry: Variant = e.pantries.get(household.id)
		if not CBValidation.fields(pantry, {"raw": "number", "meals": "number"}) or pantry.raw < 0 or pantry.meals < 0: return "Invalid food inventory."
	if e.facilities.size() > 3: return "Too many evening facilities."
	for id in e.facilities:
		var f: Variant = e.facilities[id]
		if not CBValidation.fields(f, {"definition": "object", "space": "string", "local": "bool", "stock": "number", "busy": "array", "served": "number"}): return "Invalid facility."
		if not definition_error(f.definition).is_empty() or id != f.definition.id or f.stock < 0 or f.busy.size() > f.definition.slots: return "Invalid service definition or reservation."
		var found := false
		for space in saved.layout.spaces:
			if space.id == f.space: found = true
		if not found: return "Invalid facility location."
		for slot in f.busy:
			if not CBValidation.fields(slot, {"actor": "string", "until": "number"}) or not e.actors.has(slot.actor): return "Invalid slot reservation."
	for event in e.events:
		if not CBValidation.fields(event, {"minute": "number", "actor": "string", "kind": "string", "text": "string"}): return "Invalid event record."
	return ""
