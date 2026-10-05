extends RefCounted

func run(test: SceneTree) -> void:
	var layers := CBWorldSeed.seeds(2406)
	var created := CBWorldExperiment.generate(layers)
	test.check(created.ok, "Living world generates: " + created.message)
	if not created.ok: return
	var e: CBWorldExperiment = created.experiment
	test.check(CBLabCatalog.canonical(e.worlds[0].model.state) == CBLabCatalog.canonical(e.worlds[2].model.state), "Three futures start with identical people, weather and accounts")
	var repeat: CBWorldExperiment = CBWorldExperiment.generate(layers).experiment
	test.check(e.export_document() == repeat.export_document(), "Same layer seeds reproduce the same world")
	for seed_value in range(1, 41):
		var varied := CBWorldExperiment.generate(CBWorldSeed.seeds(seed_value))
		test.check(varied.ok, "Generated seed %d is buildable" % seed_value)
	var other_layers := layers.duplicate()
	other_layers.people += 1
	var changed: CBWorldExperiment = CBWorldExperiment.generate(other_layers).experiment
	test.check(changed.sim.plans == e.sim.plans and changed.sim.climate == e.sim.climate and changed.design == e.design, "Rerolling residents preserves locked geometry, weather and resources")
	var world := e.worlds[0]
	var before := CBLabCatalog.canonical(world.model.state)
	var rejected := world.request(CBLivingWorld.action("move", 0, [0, 0]))
	test.check(not rejected.ok and before == CBLabCatalog.canonical(world.model.state), "Overlapping reserved yard is rejected atomically")
	var command := CBLivingWorld.action("add", 0, [2, 4, 3])
	var preview := world.preview(command)
	test.check(preview.ok and before == CBLabCatalog.canonical(world.model.state), "Room preview is valid and has no simulation side effects")
	if not preview.ok: return
	var balance := world.model.money()
	var original_state := world.model.state.duplicate(true)
	var original_zones := world.model.zones.duplicate(true)
	test.check(world.request(command).ok and world.model.money() == balance - preview.cost, "Construction debits the correct account once at approval")
	test.check(world.model.plans[0].rooms.size() == 3 and world.pending.due == preview.hours, "Geometry stays unchanged until the paid construction duration elapses")
	test.check(not world.request(command).ok, "One crew cannot accept overlapping queued work")
	# Isolate completion from hourly resource flows to check exact live-state retention.
	world.model.state.hour = world.pending.due
	world._finish()
	test.check(world.model.plans[0].rooms.size() == 4 and world.model.zones[0].floor_m2 == 60, "Completed addition changes geometry and thermal floor area")
	for key in ["water_l", "battery_kwh", "rain_l", "sewage_l", "history", "totals"]:
		test.check(world.model.state[key] == original_state[key], "Construction preserves live " + key)
	var old_energy := 0.0
	var new_energy := 0.0
	for i in original_zones.size():
		for key in ["air_c", "mass_c"]:
			old_energy += float(original_zones[i][key]) * (float(original_state.homes[i][key]) + 273.15)
			new_energy += float(world.model.zones[i][key]) * (float(world.model.state.homes[i][key]) + 273.15)
	test.check(absf(new_energy - old_energy - world.energy_exchange_j) < 0.001, "Added thermal mass has explicit boundary energy; construction does not create heat")
	var tank_before: float = world.model.state.water_l
	var tank_result := world.request(CBLivingWorld.action("upgrade", -1, "tank"))
	test.check(tank_result.ok, "Utility construction uses the shared action pipeline")
	world._finish()
	test.check(world.model.state.water_l == tank_before and world.model.design.tank_l == 3000, "Extra tank capacity arrives empty")
	e = CBWorldExperiment.generate(layers).experiment
	e.select_future(2)
	test.check(e.act("build", CBLivingWorld.action("protect", 0, true)).ok, "Player can protect a home from autonomous work")
	var timer := Time.get_ticks_usec()
	e.start(720)
	while e.phase == "running": e.tick()
	print("LIVING BENCHMARK: 3 futures / 30 days %.2f ms" % ((Time.get_ticks_usec() - timer) / 1000.0))
	test.check(e.worlds[0].completed == 0 and not e.worlds[0].proposals.is_empty(), "Guide mode asks instead of building")
	test.check(e.worlds[2].completed > e.worlds[0].completed, "Autonomous residents visibly change their future")
	test.check(e.worlds[2].model.plans[0].rooms.size() == 3 and e.worlds[2].model.plans[0].assembly == "core:light_wall", "Protected home remains unchanged by agents")
	for w in e.worlds:
		test.check(w.model.state.hour == 720 and w.model.weather(720) == e.worlds[0].model.weather(720), "Futures retain a matched clock and weather stream")
		for amount in w.model.state.owners.values(): test.check(amount >= 0, "Autonomy respects owner funds")
		test.check(w.model.state.shared_capital_cents >= 0, "Autonomy respects the shared capital grant")
	e.select_future(0)
	var accepted := e.act("accept", int(e.worlds[0].proposals[0].command.home))
	test.check(accepted.ok, "Player can approve a neighbour proposal after the world has run")
	e.start(168)
	while e.phase == "running": e.tick()
	var exported: Dictionary = JSON.parse_string(JSON.stringify(e.export_document(), "", true, true))
	var loaded := CBWorldExperiment.read_document(exported)
	test.check(loaded.ok, "Living world accepts its pinned portable document")
	if loaded.ok:
		var restored: CBWorldExperiment = loaded.experiment
		while restored.restore_hour > 0: restored.tick()
		test.check(restored.replay_error.is_empty(), "Mid-run player decisions replay successfully")
		for i in 3:
			test.check(CBLabCatalog.canonical(restored.worlds[i].model.state) == CBLabCatalog.canonical(e.worlds[i].model.state), "Replay restores exact running state in future %d" % i)
			test.check(CBLabCatalog.canonical(restored.worlds[i].journal) == CBLabCatalog.canonical(e.worlds[i].journal), "Replay restores explanations in future %d" % i)
			test.check(restored.worlds[i].pending == e.worlds[i].pending, "Replay restores construction progress in future %d" % i)
	for mutation in [func(v: Dictionary) -> void: v.hour = -1, func(v: Dictionary) -> void: v.inputs.kit.room_hours = 0, func(v: Dictionary) -> void: v.commands[0].value.value = "not bool", func(v: Dictionary) -> void: v.runtime = "future-model", func(v: Dictionary) -> void: v.active = INF]:
		var bad := exported.duplicate(true)
		mutation.call(bad)
		test.check(not CBWorldExperiment.read_document(bad).ok, "Malformed living experiment is rejected")
