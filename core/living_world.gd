class_name CBLivingWorld
extends RefCounted
## One command pipeline for players and neighbours. Preview is pure; enqueue pays;
## completion swaps only compiled geometry, retaining every running stock/account.
const MODES := ["Guide", "Collaborate", "Let it grow"]
var model: CBLivingModel
var kit: Dictionary
var profiles: Array
var mode := 0
var pending: Dictionary = {}
var proposals: Array = []
var journal: Array = []
var protected_homes: Array = []
var cooldowns: Dictionary = {}
var revision := 0
var spent := 0
var completed := 0
var energy_exchange_j := 0.0
var imported_mass_kg := 0.0
var removed_mass_kg := 0.0

static func default_kit() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://content/living/kit.json"))

static func kit_error(value: Variant) -> String:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://schemas/living-kit.schema.json"))
	var issue := CBLabCatalog.validate(value, schema, "Living kit")
	if not issue.is_empty(): return issue
	var ids := {}
	for upgrade in value.upgrades:
		if not CBModLoader.valid_pack_id(upgrade.id) or ids.has(upgrade.id): return "Upgrade IDs must be unique lowercase identifiers."
		ids[upgrade.id] = true
	return ""

static func action(kind: String, home: int = -1, value: Variant = null) -> Dictionary:
	return {"kind": kind, "home": home, "value": value}

static func action_error(command: Variant, home_count: int) -> String:
	if not command is Dictionary or command.size() != 3: return "Invalid building command."
	for key in ["kind", "home", "value"]:
		if not command.has(key): return "Missing command field: " + key
	if not command.kind in ["add", "remove", "insulate", "move", "upgrade", "protect"]: return "Unsupported building action."
	if not CBValidation.number(command.home) or command.home != floorf(command.home) or command.home < -1 or command.home >= home_count: return "Unknown home."
	if command.kind == "upgrade":
		if command.home != -1 or not command.value is String: return "Shared improvements need a recipe ID."
	elif command.home < 0: return "Select a home."
	match command.kind:
		"insulate":
			if not command.value is String or command.value.length() > 120: return "Choose a wall assembly."
		"add":
			if not command.value is Array or command.value.size() != 3: return "Choose a side, width and depth."
			for v in command.value:
				if not CBValidation.number(v) or v != floorf(v): return "Rooms snap to whole metres."
			if command.value[0] < 0 or command.value[0] > 3 or command.value[1] < 2 or command.value[1] > 8 or command.value[2] < 2 or command.value[2] > 8: return "Invalid room dimensions."
		"move":
			if not command.value is Array or command.value.size() != 2: return "Choose grid coordinates."
			for v in command.value:
				if not CBValidation.number(v) or absf(v) > 30 or v != floorf(v): return "Move within the site on the metre grid."
		"remove":
			if command.value != null: return "Remove only the most recent addition."
		"protect":
			if not command.value is bool: return "Protection must be true or false."
	return ""

func preview(command: Dictionary) -> Dictionary:
	var issue := action_error(command, model.plans.size())
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	if command.kind == "protect": return {"ok": true, "message": "Protection updated."}
	if not pending.is_empty(): return CBLabCatalog.fail("Let the current project finish first. One crew works on this community.")
	var plans := model.plans.duplicate(true)
	var design := model.design.duplicate(true)
	var cost := 0
	var hours := int(kit.upgrade_hours)
	var payer := "shared"
	var title := ""
	var index := int(command.home)
	if index >= 0: payer = plans[index].owner
	match command.kind:
		"add":
			var w := int(command.value[1])
			var d := int(command.value[2])
			var low := Vector2i(100, 100)
			var high := Vector2i(-100, -100)
			for r in plans[index].rooms:
				low = low.min(Vector2i(int(r[0]), int(r[1])))
				high = high.max(Vector2i(int(r[0] + r[2]), int(r[1] + r[3])))
			var origins := [[high.x, low.y], [low.x, high.y], [low.x - w, low.y], [low.x, low.y - d]]
			var origin: Array = origins[int(command.value[0])]
			plans[index].rooms.append([origin[0], origin[1], w, d])
			cost = w * d * int(kit.room_cost_cents_m2)
			hours = int(kit.room_hours)
			title = "Add a %d m² room" % (w * d)
		"remove":
			if plans[index].rooms.size() <= 3: return CBLabCatalog.fail("The three original rooms remain habitable. Only additions can be removed.")
			var room: Array = plans[index].rooms.pop_back()
			cost = int(room[2] * room[3] * kit.demolition_cents_m2)
			hours = int(kit.room_hours)
			title = "Remove the latest room addition"
		"insulate":
			if model.catalog.definition("assemblies", command.value).is_empty(): return CBLabCatalog.fail("Unknown wall assembly.")
			if plans[index].assembly == command.value: return CBLabCatalog.fail("This home already uses that wall.")
			plans[index].assembly = command.value
			# Full replacement purchase + removal labor. No resale or free salvage.
			cost = roundi(model.zones[index].wall_area * (model.catalog.assembly(command.value).cost_cents_m2 + 2000))
			title = "Replace walls: " + model.catalog.definition("assemblies", command.value).name
		"move":
			if int(plans[index].x) == int(command.value[0]) and int(plans[index].z) == int(command.value[1]): return CBLabCatalog.fail("That home is already here.")
			plans[index].x = int(command.value[0])
			plans[index].z = int(command.value[1])
			cost = roundi(model.zones[index].floor_m2 * 20000)
			hours = int(kit.room_hours)
			title = "Relocate the home"
		"upgrade":
			var recipe := {}
			for option in kit.upgrades:
				if option.id == command.value: recipe = option
			if recipe.is_empty(): return CBLabCatalog.fail("Unknown upgrade recipe.")
			design[recipe.field] += float(recipe.amount)
			cost = int(recipe.cost_cents)
			title = recipe.name
	var built := CBLivingModel.build(model.catalog, design, plans)
	if not built.ok: return built
	var available := int(model.state.shared_capital_cents if payer == "shared" else model.state.owners[payer])
	if cost > available: return CBLabCatalog.fail("%s needs €%d; only €%d remains." % [payer, cost / 100, available / 100])
	return {"ok": true, "message": title, "title": title, "cost": cost, "hours": hours, "payer": payer, "plans": plans, "design": design, "candidate": built.simulation}

func request(command: Dictionary, actor: String = "You", reason: String = "Player experiment") -> Dictionary:
	var checked := preview(command)
	if not checked.ok: return checked
	if command.kind == "protect":
		protected_homes.erase(int(command.home))
		if command.value: protected_homes.append(int(command.home))
		_log(actor, "Protected home" if command.value else "Released home", reason, 0)
		return checked
	if actor != "You" and int(command.home) in protected_homes: return CBLabCatalog.fail("This home is protected from autonomous construction.")
	if checked.payer == "shared": model.state.shared_capital_cents -= int(checked.cost)
	else: model.state.owners[checked.payer] -= int(checked.cost)
	spent += int(checked.cost)
	model._ledger(checked.payer, "construction", int(checked.cost), checked.title)
	pending = {"command": command.duplicate(true), "actor": actor, "reason": reason, "cost": checked.cost, "title": checked.title, "due": int(model.state.hour) + int(checked.hours), "plans": checked.plans, "design": checked.design}
	cooldowns[str(command.home)] = int(model.state.hour) + int(kit.cooldown_days) * 24
	proposals = proposals.filter(func(p: Dictionary) -> bool: return p.command.home != command.home)
	_log(actor, "Started: " + checked.title, reason, int(checked.cost))
	return {"ok": true, "message": "%s · €%d · ready in %d hours" % [checked.title, int(checked.cost) / 100, checked.hours]}

func _finish() -> void:
	var built := CBLivingModel.build(model.catalog, pending.design, pending.plans)
	assert(built.ok, "Only validated immutable queued plans may complete")
	var next: CBLivingModel = built.simulation
	next.state = model.state.duplicate(true)
	for i in next.zones.size():
		for pair in [["air_c", "air_c"], ["mass_c", "mass_c"]]:
			var old_capacity: float = model.zones[i][pair[0]]
			var new_capacity: float = next.zones[i][pair[0]]
			var old_temperature: float = model.state.homes[i][pair[1]]
			var added := maxf(0, new_capacity - old_capacity)
			var retained := minf(old_capacity, new_capacity)
			var incoming: float = model.state.weather.temperature_c
			next.state.homes[i][pair[1]] = (retained * old_temperature + added * incoming) / new_capacity
			energy_exchange_j += added * (incoming + 273.15) - maxf(0, old_capacity - new_capacity) * (old_temperature + 273.15)
		var mass_change: float = next.zones[i].mass_kg - model.zones[i].mass_kg
		# Record a full wall replacement even when total mass stays similar.
		if next.plans[i].assembly != model.plans[i].assembly:
			imported_mass_kg += next.zones[i].wall_area * next.zones[i].wall.mass_kg_m2
			removed_mass_kg += model.zones[i].wall_area * model.zones[i].wall.mass_kg_m2
		else:
			imported_mass_kg += maxf(0, mass_change)
			removed_mass_kg += maxf(0, -mass_change)
	model = next
	completed += 1
	revision += 1
	_log(pending.actor, "Finished: " + str(pending.title), pending.reason, 0)
	pending = {}

func _log(actor: String, title: String, reason: String, cost: int) -> void:
	journal.append({"hour": int(model.state.hour), "actor": actor, "title": title, "reason": reason, "cost": cost})
	if journal.size() > 200: journal.pop_front()

func dismiss(home: int) -> Dictionary:
	var found := false
	for proposal in proposals:
		if int(proposal.command.home) == home:
			_log("You", "Declined: " + str(proposal.title), "Try another solution after the cooldown.", 0)
			found = true
	if not found: return CBLabCatalog.fail("This proposal has already changed.")
	proposals = proposals.filter(func(p: Dictionary) -> bool: return int(p.command.home) != home)
	cooldowns[str(home)] = int(model.state.hour) + int(kit.cooldown_days) * 24
	return {"ok": true, "message": "Proposal declined. Neighbours will wait before reconsidering."}

func accept(home: int) -> Dictionary:
	for proposal in proposals:
		if int(proposal.command.home) == home: return request(proposal.command, "You", "Approved " + str(proposal.actor) + ": " + str(proposal.reason))
	return CBLabCatalog.fail("This proposal has already changed.")

func step() -> void:
	model.step()
	if not pending.is_empty() and model.state.hour >= pending.due: _finish()
	if int(model.state.hour) % 24 == 0 and model.state.hour < CBLab.YEAR_HOURS: _consider()

func _consider() -> void:
	if not pending.is_empty(): return
	var options: Array = []
	var s := model.state
	for i in model.plans.size():
		if i in protected_homes or int(cooldowns.get(str(i), 0)) > s.hour: continue
		var home: Dictionary = s.homes[i]
		var z: Dictionary = model.zones[i]
		var target: float = kit.space_targets_m2_person[int(profiles[i].space_index)] * 3
		var cold := maxf(0, 19 - float(home.air_c))
		var warmth_score: float = (cold * 12 + (4 if model.weather(int(s.hour)).temperature_c < 8 else 0)) * kit.weights.warmth
		if z.wall.u > model.catalog.assembly("core:warm_wall").u * 1.2:
			options.append({"command": action("insulate", i, "core:warm_wall"), "actor": home.name, "reason": "Our home is %.1f°C. Better walls may reduce heating demand; affordability still matters." % home.air_c, "score": warmth_score})
		if z.floor_m2 < target:
			for side in 4:
				options.append({"command": action("add", i, [side, 4, 3]), "actor": home.name, "reason": "We have %.0f m² for three people and would like %.0f m². An extra room also costs money and heat." % [z.floor_m2, target], "score": (target - z.floor_m2) * float(kit.weights.space) * (1.0 + int(profiles[i].priority) * 0.15)})
		elif model.plans[i].rooms.size() > 3 and z.floor_m2 - 12 >= target and cold > 2:
			options.append({"command": action("remove", i), "actor": home.name, "reason": "The last addition is surplus to our space target and adds heating demand.", "score": cold * 10 * float(kit.weights.warmth)})
	if int(cooldowns.get("-1", 0)) <= s.hour:
		var demand: float = model.plans.size() * 3 * model.house.water_l_person_day
		for recipe in kit.upgrades:
			var score := 0.0
			var reason := ""
			match recipe.field:
				"water_l_day":
					score = maxf(0, demand - model.design.water_l_day) / 12 * float(kit.weights.water)
					reason = "Our connection supplies %.0f L/day; residents need %.0f L/day." % [model.design.water_l_day, demand]
				"sewage_l_day":
					score = maxf(0, demand * 0.8 - model.design.sewage_l_day) / 10 * float(kit.weights.water)
					reason = "Expected sewage exceeds removal capacity; storage only delays overflow."
				"waste_kg":
					score = maxf(0, model.plans.size() * 3 * model.house.waste_kg_person_day * model.design.pickup_days - model.design.waste_kg) * float(kit.weights.waste)
					reason = "Bins are too small for the collection interval."
				"solar_kw":
					score = maxf(0, 6 - model.design.solar_kw) * 2 * float(kit.weights.power)
					reason = "Local solar could reduce grid purchases. Night-time demand still needs the grid or storage."
				"battery_kwh":
					score = (12.0 if not s.grid_available and model.design.battery_kwh < 30 else 0.0) * float(kit.weights.power)
					reason = "The outage revealed a storage gap. New capacity arrives empty and must charge."
			options.append({"command": action("upgrade", -1, recipe.id), "actor": "Utility co-op", "reason": reason, "score": score})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var selected_homes := {}
	for option in options:
		if option.score <= 0 or selected_homes.has(option.command.home): continue
		var checked := preview(option.command)
		if not checked.ok: continue
		selected_homes[option.command.home] = true
		option["title"] = checked.title
		option["cost"] = checked.cost
		var ceiling := int(kit.collaborate_limit_cents if mode == 1 else kit.grow_limit_cents)
		if mode > 0 and checked.cost <= ceiling:
			request(option.command, option.actor, option.reason)
			return
		var already := false
		for proposal in proposals:
			if proposal.command.home == option.command.home: already = true
		if not already:
			proposals.append(option)
			_log(option.actor, "Proposed: " + str(option.title), option.reason, 0)
