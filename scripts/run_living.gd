extends SceneTree
## Headless experiments use exactly the same generator, planner and commands as play.
func _initialize() -> void:
	var seed_value := 2406
	var hours := 168
	var hours_set := false
	var import_path := ""
	var export_path := ""
	var output := ""
	var kit_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="): seed_value = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--hours="):
			hours = int(argument.trim_prefix("--hours="))
			hours_set = true
		elif argument.begins_with("--import="): import_path = argument.trim_prefix("--import=")
		elif argument.begins_with("--export="): export_path = argument.trim_prefix("--export=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--kit="): kit_path = argument.trim_prefix("--kit=")
		else:
			_fail("Unknown argument: " + argument)
			return
	if seed_value < 1 or seed_value > 999999 or not hours in [24, 168, 720, 8760]:
		_fail("Use seed 1–999999 and hours 24, 168, 720 or 8760.")
		return
	var kit := CBLivingWorld.default_kit()
	if not kit_path.is_empty():
		var loaded := CBLabIO.read(kit_path)
		if not loaded.ok:
			_fail(loaded.message)
			return
		var issue := CBLivingWorld.kit_error(loaded.value)
		if not issue.is_empty():
			_fail(issue)
			return
		kit = loaded.value
	var created := CBWorldExperiment.generate(CBWorldSeed.seeds(seed_value), kit)
	if not import_path.is_empty():
		var loaded := CBLabIO.read(import_path)
		created = CBWorldExperiment.read_document(loaded.value) if loaded.ok else loaded
	if not created.ok:
		_fail(created.message)
		return
	var experiment: CBWorldExperiment = created.experiment
	while experiment.restore_hour > 0: experiment.tick()
	if not experiment.replay_error.is_empty():
		_fail(experiment.replay_error)
		return
	if import_path.is_empty() or hours_set:
		var started := experiment.start(hours)
		if not started.ok:
			_fail(started.message)
			return
		while experiment.phase == "running": experiment.tick()
	if not export_path.is_empty():
		var saved := CBLabIO.write_zip(export_path, "experiment.json", experiment.export_document())
		if not saved.ok:
			_fail(saved.message)
			return
	var futures: Array = []
	for world in experiment.worlds:
		futures.append({"mode": CBLivingWorld.MODES[world.mode], "report": world.model.report(), "plans": world.model.plans, "construction_cents": world.spent, "completed_projects": world.completed, "journal": world.journal})
	var result := {"runtime": CBWorldExperiment.RUNTIME, "title": experiment.world_title, "seeds": experiment.layer_seeds, "input_hash": experiment.export_document().input_hash, "futures": futures}
	if output.is_empty(): print(JSON.stringify(result, "", true, true))
	else:
		var saved := CBSaves.write(output, result)
		if not saved.ok:
			_fail(saved.message)
			return
	print("LIVING_RUN_OK hour=%d" % experiment.sim.state.hour)
	quit()

func _fail(message: String) -> void:
	printerr(message)
	quit(1)
