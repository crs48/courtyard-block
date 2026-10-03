extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var catalog := CBModLoader.create_catalog(false)
	check(catalog.errors.is_empty(), "Bundled packs load: " + str(catalog.errors))
	check(catalog.packs.size() == 6, "All six packs registered")
	check(catalog.generators.has("garden_village:cluster"), "Mod generator registered")
	check(catalog.visuals.has("garden_village:cluster"), "Mod owns its building visuals")
	check(catalog.systems.size() == 1 and catalog.panels.size() == 1, "Behavior and panel hooks registered")
	if not catalog.errors.is_empty():
		_finish()
		return
	var sim := CBSimulation.new(catalog)
	sim.create({"floors": 7, "population": 150}, 1234)
	check(sim.state.residents.size() == 150, "150-resident benchmark population")
	for space in sim.state.layout.spaces:
		check(not sim.spatial.route(0, int(space.node)).is_empty(), "Reachable: " + str(space.id))
	var twin := CBSimulation.new(catalog)
	twin.create({"floors": 7, "population": 150}, 1234)
	var start := Time.get_ticks_usec()
	for tick in 96 * 7:
		sim.step()
		twin.step()
	check(JSON.stringify(sim.state) == JSON.stringify(twin.state), "Seeded seven-day replay matches")
	print("BENCHMARK 150 residents / 7 days / 2 runs: %.2f ms" % ((Time.get_ticks_usec() - start) / 1000.0))
	for person in sim.state.residents:
		check(person.wellbeing >= 0 and person.wellbeing <= 100, "Bounded well-being")
		check(not person.unreachable, "Resident route remains reachable")
	check(sim.state.funds >= 0, "No negative shared funds")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.state, "", true, true))
	var restored := CBSimulation.new(catalog)
	check(restored.load_state(snapshot).ok, "JSON save restores")
	sim.step()
	restored.step()
	check(equal_state(sim.state, restored.state), "Save/resume preserves outcomes")
	var broken: Dictionary = snapshot.duplicate(true)
	broken.packs[0].digest = "wrong"
	check(not restored.load_state(broken).ok, "Incompatible pack rejected")
	check(restored.state.minute == sim.state.minute, "Failed load preserves live state")
	for mutation in [func(value: Dictionary) -> void: value.residents[0].needs = null, func(value: Dictionary) -> void: value.layout.edges.append([0, 999999]), func(value: Dictionary) -> void: value.households[0].home = "missing", func(value: Dictionary) -> void: value.packs = ["invalid"], func(value: Dictionary) -> void: value.residents = []]:
		var malformed := snapshot.duplicate(true)
		mutation.call(malformed)
		check(not restored.load_state(malformed).ok, "Malformed save rejected without mutation")
	check(restored.state.minute == sim.state.minute, "Malformed imports preserve live simulation")
	var original: Dictionary = sim.state.duplicate(true)
	var fork := CBSaves.fork_state(sim.state, "A second possibility")
	fork.policies.shared_meals = true
	check(not original.policies.shared_meals, "Fork is independent")
	var home: String = sim.state.residents[0].home
	var funds: int = sim.state.funds
	var furniture_before: int = sim.spaces[home].furniture.size()
	check(sim.command({"type": "furnish", "space": home, "item": "soft_spaces:reading_chair"}).ok, "Data mod furniture can be placed")
	check(sim.spaces[home].furniture.size() == furniture_before + 1 and sim.state.funds == funds - 9500, "Furniture costs and placement agree")
	sim.state.funds = 0
	check(not sim.command({"type": "furnish", "space": home, "item": "base:bed"}).ok, "Insufficient funds reject placement")
	check(sim.spaces[home].furniture.size() == furniture_before + 1, "Rejected placement is atomic")
	check(not sim.command({"type": "rebuild", "parameters": {"floors": 5}}).ok, "Rebuild cannot displace households")
	sim.state.funds = 100000000
	check(sim.command({"type": "rebuild", "parameters": {"template": "garden_village:cluster"}}).ok, "Alternative settlement generated without core edits")
	check(sim.state.residents.size() == 150, "Rebuild preserves all people")
	var shapes: Array = catalog.visuals["garden_village:cluster"].call(sim.state.layout, sim.state.parameters)
	check(not shapes.is_empty() and CBValidation.vector(shapes[0].size, 3), "Generator supplies batched visual primitives")
	for person in sim.state.residents:
		check(sim.spaces.has(person.home), "Every person retains a valid home")
	var kitchen := CBSimulation.new(catalog)
	kitchen.create()
	kitchen.command({"type": "policy", "key": "shared_meals", "value": true})
	for tick in 48:
		kitchen.step()
	check(int(kitchen.state.mod_state.get("community_kitchen:meals", 0)) > 0, "Runtime system serves shared supper")
	check(CBSaves.write("user://test_roundtrip.json", kitchen.state).ok, "Atomic save writes")
	check(CBSaves.read("user://test_roundtrip.json").ok, "Saved file reads")
	DirAccess.remove_absolute("user://test_roundtrip.json")
	var empty := CBCatalog.new()
	var definition := {"id": "test:item", "name": "Test table", "cost": 100, "shape": "table", "benefit": 2}
	check(empty.register_content("furniture", definition), "Namespaced content accepted")
	check(not empty.register_content("furniture", definition), "Duplicate ID rejected")
	check(not empty.register_content("furniture", {"id": "test:broken"}), "Malformed furniture rejected")
	check(not CBModLoader.safe_relative("../escape.gd"), "Archive traversal rejected")
	check(not CBModLoader.safe_relative("/absolute.gd"), "Absolute archive path rejected")
	_test_packs()
	var baseline := CBSimulation.new(catalog)
	baseline.create()
	var alternative := CBSimulation.new(catalog)
	alternative.load_state(CBSaves.fork_state(baseline.state, "Alternative"))
	for tick in 8: baseline.step()
	for tick in 4: alternative.step()
	var comparison := CBSaves.compare(baseline.state, alternative.state)
	check(comparison.ok and comparison.elapsed == 60 and comparison.left.minute == comparison.right.minute, "Comparison aligns unequal branch progress to common hour")
	var before_effects := baseline.state.duplicate(true)
	baseline._apply_effects([{"type": "spend", "amount": 100}, {"type": "need", "need": "invalid", "amount": 10}], "test")
	check(equal_state(before_effects, baseline.state), "Invalid effect batch is atomic")
	load("res://tests/evening.gd").new().run(self, catalog)
	_finish()

func _test_packs() -> void:
	var root := "user://test_pack_fixtures"
	var fixtures := [
		{"id": "test_a", "name": "A", "version": "1", "api_version": 1, "dependencies": {"test_b": "1"}, "content": {}},
		{"id": "test_b", "name": "B", "version": "1", "api_version": 1, "dependencies": {"test_a": "1"}, "content": {}},
		{"id": "test_missing", "name": "Missing", "version": "1", "api_version": 1, "dependencies": {"absent": "1"}, "content": {}},
		{"id": "test_bad", "name": "Bad", "version": "1", "api_version": 1, "dependencies": {}, "content": {"furniture": [{"id": "test_bad:good", "name": "Good", "cost": 1, "shape": "table", "benefit": 1}, {"id": "test_bad:bad"}]}},
	]
	for manifest in fixtures:
		DirAccess.make_dir_recursive_absolute(root.path_join(manifest.id))
		var file := FileAccess.open(root.path_join(manifest.id).path_join("manifest.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest))
		file.close()
	check(not CBModLoader.load_roots([root.path_join("test_a"), root.path_join("test_b")]).errors.is_empty(), "Dependency cycle rejected")
	check(not CBModLoader.load_roots([root.path_join("test_missing")]).errors.is_empty(), "Missing dependency rejected")
	var failed := CBModLoader.load_roots([root.path_join("test_bad")])
	check(not failed.errors.is_empty() and failed.definitions.is_empty(), "Failed registration rolls back the whole pack")
	var manifest := {"id": "test_runtime", "name": "Runtime pack", "version": "1", "api_version": 1, "dependencies": {}, "entry": "entry.gd", "content": {}}
	var zip := ZIPPacker.new()
	zip.open(root.path_join("runtime.zip"))
	zip.start_file("manifest.json")
	zip.write_file(JSON.stringify(manifest).to_utf8_buffer())
	zip.close_file()
	zip.start_file("entry.gd")
	zip.write_file("extends RefCounted\nfunc register(catalog):\n\tcatalog.register_panel('test_runtime:panel', func(_state): return {'title': 'Loaded at runtime', 'text': 'Works'})\n".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(CBModLoader.install_zip(root.path_join("runtime.zip")).ok, "External source pack installs")
	var installed := CBModLoader.load_roots([CBModLoader.INSTALL_ROOT.path_join("test_runtime")])
	check(installed.errors.is_empty() and installed.panels.has("test_runtime:panel"), "External GDScript loads at runtime")
	for file in ["entry.gd", "manifest.json"]: DirAccess.remove_absolute(CBModLoader.INSTALL_ROOT.path_join("test_runtime").path_join(file))
	DirAccess.remove_absolute(CBModLoader.INSTALL_ROOT.path_join("test_runtime"))
	DirAccess.remove_absolute(root.path_join("runtime.zip"))
	for fixture in fixtures:
		DirAccess.remove_absolute(root.path_join(fixture.id).path_join("manifest.json"))
		DirAccess.remove_absolute(root.path_join(fixture.id))
	DirAccess.remove_absolute(root)

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func _finish() -> void:
	print("%s checks, %s failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func equal_state(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) < 0.00000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equal_state(a[key], b[key]):
				printerr("Mismatch at " + str(key))
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equal_state(a[i], b[i]): return false
		return true
	return a == b
