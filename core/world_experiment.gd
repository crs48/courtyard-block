class_name CBWorldExperiment
extends CBLabExperiment
## Three counterfactuals share initial conditions and hourly weather. Portable
## experiments contain pinned inputs and player commands, never imported balances.
const RUNTIME := "living-worlds-1.0.0"
var worlds: Array[CBLivingWorld] = []
var active := 1
var layer_seeds: Dictionary
var source_packs: Array
var living_kit: Dictionary
var world_title := ""
var commands: Array = []
var replay_commands: Array = []
var replay_cursor := 0
var replay_error := ""

static func generate(seed_layers: Dictionary, kit: Dictionary = {}, packs: Array = []) -> Dictionary:
	var rules := CBLivingWorld.default_kit() if kit.is_empty() else kit.duplicate(true)
	var issue := CBLivingWorld.kit_error(rules)
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	var inputs := CBLabCatalog.builtin_packs() if packs.is_empty() else packs.duplicate(true)
	var generated := CBWorldSeed.generate(seed_layers, inputs)
	if not generated.ok: return generated
	var e := CBWorldExperiment.new()
	e.layer_seeds = seed_layers.duplicate(true)
	e.source_packs = inputs
	e.living_kit = rules
	e.catalog = generated.catalog
	e.world_title = generated.title
	e.phase = "paused"
	e.limit = 168
	for mode in 3:
		var built := CBLivingModel.build(e.catalog, generated.design, generated.plans)
		if not built.ok: return built
		var world := CBLivingWorld.new()
		world.model = built.simulation
		world.kit = rules.duplicate(true)
		world.profiles = generated.profiles.duplicate(true)
		world.mode = mode
		for balance in world.model.state.owners.values():
			if balance < 0: return CBLabCatalog.fail("Generated buildings exceed their initial capital.")
		if world.model.state.shared_capital_cents < 0: return CBLabCatalog.fail("Generated equipment exceeds its grant.")
		e.worlds.append(world)
	e.select_future(1)
	return {"ok": true, "experiment": e, "message": generated.message}

func select_future(index: int) -> void:
	active = clampi(index, 0, 2)
	sim = worlds[active].model
	reference = worlds[0].model
	design = sim.design
	baseline = reference.design

func act(kind: String, value: Variant) -> Dictionary:
	if restore_hour > 0: return CBLabCatalog.fail("Wait for replay to finish.")
	if commands.size() >= 512: return CBLabCatalog.fail("This experiment has reached its 512 player-command limit. Export it and start a new seed.")
	var record := {"hour": int(sim.state.hour), "branch": active, "kind": kind, "value": value}
	var result := _apply(record)
	if result.ok:
		commands.append(record.duplicate(true))
		phase = "paused"
		select_future(active)
	return result

func _apply(record: Dictionary) -> Dictionary:
	var world := worlds[int(record.branch)]
	match record.kind:
		"build": return world.request(record.value)
		"accept": return world.accept(int(record.value))
		"dismiss": return world.dismiss(int(record.value))
	return CBLabCatalog.fail("Unsupported player command.")

func start(hours: int) -> Dictionary:
	if restore_hour > 0: return CBLabCatalog.fail("Wait for replay to finish.")
	if not hours in [24, 168, 720, 8760]: return CBLabCatalog.fail("Run one day, one week, one month or the remaining year.")
	if sim.state.hour >= CBLab.YEAR_HOURS: return CBLabCatalog.fail("This fixed-cohort prototype ends after one year. Export or choose a new world.")
	limit = mini(CBLab.YEAR_HOURS, int(sim.state.hour) + hours)
	phase = "running"
	return {"ok": true, "message": "All three futures are advancing through the same weather."}

func pause() -> void:
	if phase == "running": phase = "paused"
	elif sim.state.hour < limit: phase = "running"
	else: start(168)

func tick() -> void:
	if restore_hour > 0:
		if not _replay_at_hour(): return
		if sim.state.hour < restore_hour:
			for world in worlds: world.step()
			select_future(active)
		if sim.state.hour >= restore_hour:
			if not _replay_at_hour(): return
			restore_hour = 0
			phase = "paused"
		return
	if phase != "running": return
	for world in worlds: world.step()
	select_future(active)
	if sim.state.hour >= limit: phase = "paused"

func _replay_at_hour() -> bool:
	while replay_cursor < replay_commands.size() and replay_commands[replay_cursor].hour == sim.state.hour:
		var record: Dictionary = replay_commands[replay_cursor]
		var result := _apply(record)
		if not result.ok:
			replay_error = "Recorded action %d cannot replay: %s" % [replay_cursor + 1, result.message]
			restore_hour = 0
			phase = "paused"
			return false
		commands.append(record.duplicate(true))
		replay_cursor += 1
		select_future(active)
	return true

func export_document() -> Dictionary:
	var inputs := {"seeds": layer_seeds, "packs": source_packs, "kit": living_kit}
	return {"format": "courtyard-living-world", "version": 1, "runtime": RUNTIME, "generator": CBWorldSeed.VERSION, "inputs": inputs.duplicate(true), "input_hash": CBLabCatalog.digest(inputs), "commands": commands.duplicate(true), "hour": int(sim.state.hour), "active": active, "limit": limit}

static func read_document(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 10: return CBLabCatalog.fail("Invalid living-world document.")
	for key in ["format", "version", "runtime", "generator", "inputs", "input_hash", "commands", "hour", "active", "limit"]:
		if not value.has(key): return CBLabCatalog.fail("Missing world field: " + key)
	if value.format != "courtyard-living-world" or value.version != 1 or value.runtime != RUNTIME or value.generator != CBWorldSeed.VERSION: return CBLabCatalog.fail("This world needs its original living-world runtime and generator.")
	for key in ["hour", "active", "limit"]:
		if not CBValidation.number(value[key]) or floorf(value[key]) != value[key]: return CBLabCatalog.fail("Invalid world clock or future.")
	if value.hour < 0 or value.hour > CBLab.YEAR_HOURS or value.limit < value.hour or value.limit > CBLab.YEAR_HOURS or value.active < 0 or value.active > 2: return CBLabCatalog.fail("Invalid world clock or future.")
	if not value.inputs is Dictionary or value.inputs.size() != 3: return CBLabCatalog.fail("Malformed world inputs.")
	for key in ["seeds", "packs", "kit"]:
		if not value.inputs.has(key): return CBLabCatalog.fail("Missing world input.")
	if not value.inputs.seeds is Dictionary or not value.inputs.packs is Array or value.inputs.packs.is_empty() or not value.inputs.kit is Dictionary or value.inputs.kit.is_empty(): return CBLabCatalog.fail("Malformed world inputs.")
	if value.input_hash != CBLabCatalog.digest(value.inputs): return CBLabCatalog.fail("World input hashes differ. Nothing was imported.")
	if not value.commands is Array or value.commands.size() > 512: return CBLabCatalog.fail("Too many recorded actions.")
	var created := generate(value.inputs.seeds, value.inputs.kit, value.inputs.packs)
	if not created.ok: return created
	var e: CBWorldExperiment = created.experiment
	var previous_hour := -1
	for record in value.commands:
		if not record is Dictionary or record.size() != 4: return CBLabCatalog.fail("Malformed action record.")
		for key in ["hour", "branch", "kind", "value"]:
			if not record.has(key): return CBLabCatalog.fail("Missing action field.")
		for key in ["hour", "branch"]:
			if not CBValidation.number(record[key]) or record[key] != floorf(record[key]): return CBLabCatalog.fail("Invalid recorded hour or branch.")
		if record.hour < previous_hour or record.hour > value.hour or record.hour < 0 or record.branch < 0 or record.branch > 2: return CBLabCatalog.fail("Actions must be ordered inside the recorded horizon.")
		previous_hour = int(record.hour)
		if record.kind == "build":
			var issue := CBLivingWorld.action_error(record.value, e.sim.zones.size())
			if not issue.is_empty(): return CBLabCatalog.fail(issue)
		elif record.kind in ["accept", "dismiss"]:
			if not CBValidation.number(record.value) or record.value != floorf(record.value) or record.value < -1 or record.value >= e.sim.zones.size(): return CBLabCatalog.fail("Unknown proposal household.")
		else: return CBLabCatalog.fail("Unsupported recorded command.")
	e.replay_commands = value.commands.duplicate(true)
	e.select_future(int(value.active))
	e.limit = int(value.limit)
	e.restore_hour = int(value.hour)
	if value.hour == 0 and not e._replay_at_hour(): return CBLabCatalog.fail(e.replay_error)
	created.message = "Replaying pinned inputs; the current world stays intact until validation completes."
	return created
