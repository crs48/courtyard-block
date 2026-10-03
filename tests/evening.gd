extends RefCounted

func scenario(catalog: CBCatalog, changes: Dictionary = {}) -> CBSimulation:
	var sim := CBSimulation.new(catalog)
	sim.create({"scenario": "evening"})
	sim.state.evening.design.merge(changes, true)
	return sim

func finish(sim: CBSimulation) -> Dictionary:
	CBEvening.start(sim)
	for tick in 24: sim.step()
	return CBEvening.report(sim)

func run(test: SceneTree, catalog: CBCatalog) -> void:
	var base := scenario(catalog)
	var baseline := finish(base)
	test.check(baseline.fed == 24 and baseline.on_time < 24, "Baseline feeds everyone but leaves some neighbours little courtyard time")
	var path := scenario(catalog, {"shortcut": true})
	var path_report := finish(path)
	test.check(path_report.travel < baseline.travel and path_report.free > baseline.free, "Shorter outside route saves measured travel time")
	var late := scenario(catalog, {"late_hours": true})
	var late_report := finish(late)
	test.check(late_report.on_time > baseline.on_time and late_report.labor > baseline.labor, "Extended hours help customers and require paid work")
	test.check(late_report.people[5].free < baseline.people[5].free, "Comparison exposes the late-shift worker's lost evening")
	var kitchen := scenario(catalog, {"service": "evening:kitchen"})
	var meals := finish(kitchen)
	test.check(meals.fed == 24 and meals.people[2].free < baseline.people[2].free, "Kitchen feeds its staff too, while exposing their reduced leisure")
	var pickup := scenario(catalog, {"service": "grocery_pickup:locker"})
	var parcels := finish(pickup)
	test.check(parcels.on_time == 24 and parcels.power > baseline.power, "Independent JSON pickup pack trades capital and energy for accessible groceries")
	test.check(parcels.capital > meals.capital, "Service alternatives have distinct capital tradeoffs")
	var no_power := scenario(catalog, {"service": "grocery_pickup:locker", "power": false})
	var blocked := finish(no_power)
	test.check(blocked.fed == 0 and no_power.state.totals.power_kwh == 0, "Food cannot be cooked or dispensed with required power disconnected")
	test.check(no_power.state.evening.events.any(func(event: Dictionary) -> bool: return event.text.contains("disconnected")), "Blocked service produces a causal explanation")
	var design := scenario(catalog)
	var untouched := design.state.duplicate(true)
	test.check(design.command({"type": "evening_design", "key": "shortcut", "value": true}).ok, "Design command accepts a route intervention")
	test.check(design.state.funds == untouched.funds, "Preview does not spend funds")
	test.check(design.command({"type": "evening_undo"}).ok and design.state.evening.design == untouched.evening.design, "Design undo restores the previous configuration")
	var invalid := catalog.get_definition("evening_services", "grocery_pickup:locker").duplicate(true)
	invalid.slots = 0
	test.check(not design.command({"type": "evening_recipe", "recipe": invalid}).ok, "Workshop rejects a service with no usable places")
	test.check(design.state.evening.design == untouched.evening.design, "Rejected recipe preserves the design")
	invalid.slots = 1
	invalid.arbitrary_script = "run()"
	test.check(not CBEvening.definition_error(invalid).is_empty(), "Bounded service schema rejects unknown behavior")
	var recipe := catalog.get_definition("evening_services", "grocery_pickup:locker").duplicate(true)
	recipe.name = "My tiny pantry"
	recipe.stock = 3
	test.check(design.command({"type": "evening_recipe", "recipe": recipe}).ok, "Workshop accepts a new declarative service")
	finish(design)
	test.check(design.state.evening.facilities["workshop:prototype"].served == 3, "Finite stock is allocated once and never overdrawn")
	for instance in [base, path, late, kitchen, pickup, no_power, design]:
		var e: Dictionary = instance.state.evening
		var wallets := 0
		for household in instance.state.households: wallets += int(household.wallet)
		var expected := 250000 + 8 * 35000 + int(e.external_wages) - int(e.capital) - int(e.operating) + int(e.staff_paid) - int(e.external_spending)
		test.check(int(instance.state.funds) + wallets == expected, "Local money transfers conserve balances; outside sources and sinks reconcile")
		test.check(instance.validate_save(instance.state).ok, "Completed scenario passes save validation")
		for f in e.facilities.values():
			test.check(f.stock >= 0 and int(f.stock) + int(f.served) == int(f.definition.stock), "Service stock and delivered portions reconcile")
	var replay := scenario(catalog, {"service": "evening:kitchen"})
	CBEvening.start(replay)
	for tick in 11: replay.step()
	var restored := CBSimulation.new(catalog)
	test.check(restored.load_state(JSON.parse_string(JSON.stringify(replay.state, "", true, true))).ok, "Running reservations and schedules survive JSON round trip")
	for tick in 13:
		replay.step()
		restored.step()
	test.check(test.equal_state(replay.state, restored.state), "Resuming mid-service preserves deterministic results")
	var corrupted := replay.state.duplicate(true)
	corrupted.evening.actors["resident_000"].destination = "missing"
	test.check(not restored.load_state(corrupted).ok, "Invalid activity destination is rejected before replacing live state")
	var old_time: int = restored.state.minute
	test.check(not restored.command({"type": "evening_design", "key": "shortcut", "value": true}).ok and restored.state.minute == old_time, "Finished trials require a reset before editing")
	test.check(restored.command({"type": "evening_reset"}).ok and restored.state.minute == 960 and restored.state.evening.attempts.size() == 1, "New trial keeps a compact result and resets the original people and budgets")
