extends SceneTree
## Renderer-free CLI, using exactly the playable lab's validator and model.
## godot --headless --path . --script scripts/run_lab.gd -- --hours=8760

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	printerr(message)
	quit(1)

func run() -> void:
	var options: Dictionary = {"hours": "8760", "import": "", "pack": "", "assembly": "", "layout": "", "climate": "", "output": "", "save": "", "validate-pack": ""}
	for argument in OS.get_cmdline_user_args():
		if argument == "--help":
			print("Community lab: --hours=168|2160|8760 --import=experiment.json|zip --pack=manifest.json|zip --assembly=namespace:id --layout=namespace:id --climate=namespace:id --output=results.json --save=experiment.zip --validate-pack=manifest.json|zip")
			quit()
			return
		var pieces := argument.trim_prefix("--").split("=", true, 1)
		if pieces.size() != 2 or not options.has(pieces[0]):
			fail("Unknown argument: " + argument)
			return
		options[pieces[0]] = pieces[1]
	if not str(options.hours).is_valid_int() or not int(options.hours) in [168, 2160, 8760]:
		fail("Choose --hours=168, 2160 or 8760.")
		return
	var result := CBLabExperiment.create(CBLabCatalog.builtin_packs())
	if not options.import.is_empty():
		var source := CBLabIO.read(options.import)
		result = CBLabExperiment.from_document(source.value) if source.ok else source
	if not result.ok:
		fail(result.message)
		return
	var experiment: CBLabExperiment = result.experiment
	for key in ["validate-pack", "pack"]:
		if str(options[key]).is_empty(): continue
		var source := CBLabIO.read(options[key], "manifest.json")
		if not source.ok:
			fail(source.message)
			return
		# A bundled sample can be validated without installing its namespace twice.
		if key == "validate-pack":
			var candidates := experiment.catalog.packs.filter(func(p: Dictionary) -> bool: return p.id != source.value.get("id", ""))
			candidates.append(source.value)
			var compiled := CBLabCatalog.compile(candidates)
			if not compiled.ok:
				fail(compiled.message)
				return
			print("PACK_VALID " + str(source.value.id) + " " + CBLabCatalog.digest(source.value))
			quit()
			return
		result = experiment.install(source.value)
		if not result.ok:
			fail(result.message)
			return
	for key in ["assembly", "layout", "climate"]:
		if str(options[key]).is_empty(): continue
		result = experiment.edit(key, options[key])
		if not result.ok:
			fail(result.message)
			return
	var target := int(options.hours)
	if target < experiment.restore_hour:
		fail("Requested horizon precedes the imported experiment. Import a draft to run a shorter scenario.")
		return
	var started := Time.get_ticks_usec()
	while experiment.restore_hour > 0: experiment.tick()
	if experiment.sim.state.hour < target:
		result = experiment.start(target)
		if not result.ok:
			fail(result.message)
			return
		while experiment.phase == "running": experiment.tick()
	var report := {"runtime": CBLab.RUNTIME, "godot": Engine.get_version_info().string, "pack_lock": experiment.catalog.lock(), "question": experiment.question, "design": experiment.design, "baseline": experiment.baseline, "reference": experiment.reference.report(), "alternative": experiment.sim.report(), "elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0}
	if not options.output.is_empty():
		var file := FileAccess.open(options.output, FileAccess.WRITE)
		if file == null:
			fail("Cannot write result file: " + str(options.output))
			return
		file.store_string(JSON.stringify(report, "  ", true, true) + "\n")
		file.close()
	if not options.save.is_empty():
		if not str(options.save).ends_with(".zip"):
			fail("Use a .zip filename for --save.")
			return
		result = CBLabIO.write_zip(options.save, "experiment.json", experiment.export_document())
		if not result.ok:
			fail(result.message)
			return
	print("LAB_RESULT " + JSON.stringify(report, "", true, true))
	quit()
