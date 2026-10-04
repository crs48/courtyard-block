extends RefCounted

func run(test: SceneTree) -> void:
	var packs := CBLabCatalog.builtin_packs()
	var compiled := CBLabCatalog.compile(packs)
	test.check(compiled.ok, "API v2 reference and independent hemp packs compile")
	if not compiled.ok: return
	var catalog: CBLabCatalog = compiled.catalog
	test.check(catalog.list_content("assemblies").size() == 4, "Independent data pack adds a physical assembly")
	var canonical := CBLabCatalog.compile(JSON.parse_string(CBLabCatalog.canonical(packs)))
	test.check(canonical.ok and canonical.catalog.lock() == catalog.lock(), "Pack hashes survive JSON number normalization")
	for mutation in [func(p: Array) -> void: p[1].entry = "evil.gd", func(p: Array) -> void: p[1].content.materials[0].conductivity_w_mk = 0, func(p: Array) -> void: p[1].content.materials[0].conductivity_w_mk = INF, func(p: Array) -> void: p[1].content.assemblies[0].layers[0].material = "missing:material", func(p: Array) -> void: p[1].content.materials[0].id = "core:overwritten", func(p: Array) -> void: p[1].dependencies = {}, func(p: Array) -> void: p[1].model = "unknown-solver", func(p: Array) -> void: p[0].dependencies = {"hemp_lab": "1.0.0"}]:
		var broken := packs.duplicate(true)
		mutation.call(broken)
		test.check(not CBLabCatalog.compile(broken).ok, "Unsafe or invalid data pack rejected")
	var changed := packs.duplicate(true)
	changed[1].content.evidence[0].notes += " revised"
	test.check(CBLabCatalog.compile(changed).catalog.lock() != catalog.lock(), "Evidence edits participate in full data-pack identity")
	var d := CBLab.default_design()
	var original := CBLab.create(catalog, d)
	test.check(original.ok, "Default annual design compiles")
	if not original.ok: return
	var sim: CBLab = original.simulation
	var started := Time.get_ticks_usec()
	for hour in 8760: sim.step()
	print("LAB BENCHMARK: 24 people / 1 year %.2f ms (headless local reference)" % ((Time.get_ticks_usec() - started) / 1000.0))
	_balances(test, sim)
	test.check(sim.state.hour == 8760 and sim.state.history.size() == 366, "Year has bounded daily history and completes at the exact horizon")
	var done := CBLabCatalog.canonical(sim.state)
	sim.step()
	test.check(done == CBLabCatalog.canonical(sim.state), "A finished year does not advance")
	d.assembly = "core:warm_wall"
	var warm: CBLab = CBLab.create(catalog, d).simulation
	for hour in 8760: warm.step()
	_balances(test, warm)
	test.check(warm.state.totals.cold_person_hours < sim.state.totals.cold_person_hours and warm.capital > sim.capital, "Insulation trades higher construction cost for less cold exposure")
	test.check(warm.state.totals.grid_kwh < sim.state.totals.grid_kwh, "Derived wall physics affects purchased electricity")
	test.check(warm.state.totals.cool_kwh > 0 and warm.state.totals.labor_hours > 0, "Summer cooling and maintenance labor are accounted")
	for hour in [0, 790, 2000, 6300]: test.check(sim.weather(hour) == warm.weather(hour), "Design does not change external weather or outage stream")
	for layout in ["core:cluster", "core:canopy"]:
		d.layout = layout
		var result := CBLab.create(catalog, d)
		test.check(result.ok, "Same physical components work in " + layout)
		if result.ok:
			for hour in 168: result.simulation.step()
			_balances(test, result.simulation)
	d.assembly = "core:earth_wall"
	test.check(not CBLab.create(catalog, d).ok, "Heavy assembly exceeds declared elevated support capacity")
	d.layout = "core:cluster"
	test.check(CBLab.create(catalog, d).ok, "The same heavy wall is allowed on declared ground supports")
	d = CBLab.default_design()
	d.water_l_day = 0
	d.sewage_l_day = 0
	d.rain_tank_l = 1000
	d.waste_kg = 10
	d.pickup_days = 14
	var limited: CBLab = CBLab.create(catalog, d).simulation
	for hour in 168: limited.step()
	_balances(test, limited)
	test.check(limited.state.totals.water_unserved_l > 0 and limited.state.totals.sewage_overflow_l > 0 and limited.state.litter_kg > 0, "Finite water, sewer and bin capacities create explicit failures")
	test.check(limited.state.totals.rain_used_l > 0 and limited.state.totals.water_unserved_l > 0, "Rainwater substitutes for flushing without becoming potable")
	var matrix := [[4.0, -1.0], [-1.0, 3.0]]
	var inv := CBLab.invert(matrix)
	test.check(absf(inv[0][0] - 3.0 / 11.0) < 0.00000001 and absf(inv[0][1] - 1.0 / 11.0) < 0.00000001, "Thermal solver agrees with an analytical matrix inverse")
	test.check(CBLab.allocate([1.0, 9.0], 6.0, "equal") == [1.0, 5.0], "Equal allocation redistributes unused shares without wasting capacity")
	test.check(CBLab.allocate([1.0, 9.0], 5.0) == [0.5, 4.5], "Proportional allocation respects demand")
	test.check(CBLab.split_cents(5, [1.0, 1.0, 1.0]) == [2, 2, 1], "Bill allocation preserves every cent")
	_thermal_fixture(test, catalog)
	_experiments(test, packs)
	_io(test, packs)

func _balances(test: SceneTree, sim: CBLab) -> void:
	var s := sim.state
	var t: Dictionary = s.totals
	var monetary: int = s.initial_money - sim.capital + t.income_cents - t.living_cents - t.operating_cents - t.owner_maintenance_cents
	test.check(sim.money() == monetary, "All local transfers and external monetary boundaries reconcile")
	var energy: float = t.grid_kwh + t.solar_kwh - t.electricity_served_kwh - t.battery_loss_kwh - t.curtailed_kwh - s.battery_kwh
	test.check(absf(energy) < 0.0001, "Electricity, batteries, losses and curtailment conserve energy")
	test.check(absf(sim.design.tank_l + t.water_import_l + t.rain_used_l - t.water_used_l - s.water_l) < 0.0001, "Potable inventory reconciles with all delivered water")
	test.check(absf(t.rain_collected_l - t.rain_used_l - t.rain_spill_l - s.rain_l) < 0.0001, "Rain tank volume balances")
	test.check(absf(t.water_used_l * 0.8 - t.sewage_removed_l - t.sewage_overflow_l - s.sewage_l) < 0.0001, "Wastewater removal, storage and discharge balance")
	test.check(absf(t.waste_produced_kg - t.waste_collected_kg - s.waste_kg - s.litter_kg) < 0.0001, "Waste remains in bins, litter or recorded collection")
	test.check(s.battery_kwh >= -0.000001 and s.battery_kwh <= sim.design.battery_kwh + 0.000001 and s.utility_cents >= 0, "Energy storage and shared funds stay bounded")
	for home in s.homes:
		test.check(home.wallet_cents >= 0 and home.billed_cents == home.paid_cents + home.arrears_cents, "Household invoices, payments and arrears reconcile")
	var cold := 0.0
	for home in s.homes: cold += float(home.cold_hours) * 3
	test.check(cold == t.cold_person_hours, "Population result preserves household exposure totals")

func _thermal_fixture(test: SceneTree, catalog: CBLabCatalog) -> void:
	var sim: CBLab = CBLab.create(catalog, CBLab.default_design()).simulation
	var zero: Array = []
	var cooling: Array = []
	for _zone in sim.zones:
		zero.append(0.0)
		# Cancel the modeled occupancy + electrical gains at midnight.
		cooling.append((240.0 + sim.house.power_kwh_person_day * 3.0 / 24.0 * 700.0) / 1000.0)
	var result := sim._thermal(20, 0, zero, cooling)
	for temperature in result: test.check(absf(temperature - 20) < 0.000001, "Uniform temperature with canceled gains remains at equilibrium")
	sim.state.homes[0].air_c = 25.0
	var next := sim._thermal(0, 0, zero, zero)
	var storage := 0.0
	var boundary := 0.0
	for i in sim.zones.size():
		var z: Dictionary = sim.zones[i]
		storage += z.air_c * (next[i * 2] - sim.state.homes[i].air_c) + z.mass_c * (next[i * 2 + 1] - sim.state.homes[i].mass_c)
		boundary += 3600 * (-z.air_h * next[i * 2] - z.mass_h * next[i * 2 + 1] + 240.0 + sim.house.power_kwh_person_day * 3.0 / 24.0 * 700.0)
	test.check(absf(storage - boundary) < 0.01, "Coupled thermal update conserves energy including party-wall exchanges")

func _experiments(test: SceneTree, packs: Array) -> void:
	var e: CBLabExperiment = CBLabExperiment.create(packs).experiment
	var original := CBLabCatalog.canonical(e.export_document())
	test.check(not e.edit("grid_kw", -1).ok and CBLabCatalog.canonical(e.export_document()) == original, "Invalid design edits are atomic")
	test.check(e.edit("assembly", "core:warm_wall").ok, "A design can select an assembly from data")
	test.check(e.undo_edit().ok and e.design.assembly == "core:light_wall", "Undo restores a complete draft")
	e.edit("assembly", "hemp_lab:wall")
	e.start(2160)
	for hour in 951: e.tick()
	var document: Dictionary = JSON.parse_string(CBLabCatalog.canonical(e.export_document()))
	var imported := CBLabExperiment.from_document(document)
	test.check(imported.ok, "Self-contained experiment imports without global mods: " + str(imported.get("message", "")))
	if not imported.ok: return
	var restored: CBLabExperiment = imported.experiment
	while restored.restore_hour > 0: restored.tick()
	test.check(CBLabCatalog.canonical(e.sim.state) == CBLabCatalog.canonical(restored.sim.state), "Replay from pinned inputs restores exact physical and financial state")
	restored.start(2160)
	for hour in 1209:
		e.tick()
		restored.tick()
	test.check(CBLabCatalog.canonical(e.sim.report()) == CBLabCatalog.canonical(restored.sim.report()), "Imported and original experiments continue identically")
	test.check(e.phase == "complete" and e.reference.state.hour == e.sim.state.hour, "Matched reference reaches the same horizon")
	test.check(not e.edit("assembly", "core:light_wall").ok, "Running/completed definitions remain frozen")
	e.reset()
	test.check(e.sim.state.hour == 0 and e.notebook.size() == 1 and e.phase == "design", "Retry preserves a notebook result and restores initial state")
	for mutation in [func(d: Dictionary) -> void: d.packs[1].content.materials[0].price_cents_m3 += 1, func(d: Dictionary) -> void: d.progress.hour = -1, func(d: Dictionary) -> void: d.progress.hour = 9000, func(d: Dictionary) -> void: d.runtime = "future", func(d: Dictionary) -> void: d.baseline.seed = 9, func(d: Dictionary) -> void: d.packs = [null]]:
		var invalid := document.duplicate(true)
		mutation.call(invalid)
		test.check(not CBLabExperiment.from_document(invalid).ok, "Changed lock, unsupported model or invalid progress rejected")
	var mod: Dictionary = packs[1].duplicate(true)
	mod.id = "fourth"
	mod.content = {"assemblies": [{"id": "fourth:wall", "name": "Independent fourth wall", "layers": [{"material": "core:timber", "thickness_m": 0.1}], "labor_cents_m2": 6000, "evidence": "core:assumptions"}]}
	test.check(e.install(mod).ok and e.edit("assembly", "fourth:wall").ok, "Independent assembly uses the same host physics without a new dispatch branch")

func _io(test: SceneTree, packs: Array) -> void:
	var e: CBLabExperiment = CBLabExperiment.create(packs).experiment
	var path := "user://lab-test.cbexperiment.zip"
	test.check(CBLabIO.write_zip(path, "experiment.json", e.export_document()).ok, "Portable experiment archive writes")
	var read := CBLabIO.read(path)
	test.check(read.ok and CBLabExperiment.from_document(read.get("value", {})).ok, "Portable archive restores its exact data and definitions")
	var bytes := FileAccess.get_file_as_bytes(path)
	var central := bytes.decode_u32(bytes.size() - 6)
	bytes.encode_u32(central + 24, 500000000)
	test.check(not CBLabIO.zip_error(bytes, "experiment.json").is_empty(), "Archive expansion bomb rejected before decompression")
	test.check(not CBLabIO.zip_error(FileAccess.get_file_as_bytes(path), "manifest.json").is_empty(), "Archive member allowlist rejects unexpected payloads")
	var inconsistent := FileAccess.get_file_as_bytes(path)
	inconsistent.encode_u32(22, 500000000)
	test.check(not CBLabIO.zip_error(inconsistent, "experiment.json").is_empty(), "Conflicting local expansion size is rejected before decompression")
	inconsistent = FileAccess.get_file_as_bytes(path)
	inconsistent.encode_u16(8, 99)
	test.check(not CBLabIO.zip_error(inconsistent, "experiment.json").is_empty(), "Conflicting compression headers are rejected")
	DirAccess.remove_absolute(path)
	test.check(not CBLabIO.parse_text('{"a":' + '['.repeat(30) + '0' + ']'.repeat(30) + '}').ok, "Excessive JSON depth rejected before parse")
	test.check(not CBLabIO.parse_text('{"a":').ok, "Malformed JSON gives a structured error")
	var csv := "hour,temperature_c,solar_w_m2,rain_mm\n"
	for hour in 8760: csv += "%d,10,100,0\n" % hour
	var weather := CBLabIO.weather_pack(csv, "weather_test")
	test.check(weather.ok and e.install(weather.get("pack", {})).ok, "Full hourly CSV becomes a portable evidence-bearing weather pack")
	test.check(e.edit("climate", "weather_test:year").ok and e.sim.weather(7).temperature_c == 10, "Imported weather drives both models without synthetic temperature substitution")
	for hour in 744: e.sim.step()
	test.check(not e.sim.state.events.any(func(event: Dictionary) -> bool: return event.kind == "weather"), "Imported weather does not announce a synthetic cold spell that was never applied")
	test.check(not CBLabIO.weather_pack(csv.replace("0,10,100,0\n", "0,nan,100,0\n"), "invalid").ok, "Weather importer rejects nonfinite values")
