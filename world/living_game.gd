class_name CBLivingGame
extends CBLabGame
const WORLD_SAVE := "user://living-world.json"
var loading: CBWorldExperiment
var loading_from_save := false
var last_revision := -1
var last_proposals := -1

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument in ["--living-test", "--living-smoke"]: test_mode = true
	get_tree().auto_accept_quit = false
	get_window().content_scale_size = Vector2i.ZERO
	_scale()
	get_window().size_changed.connect(_scale)
	var created := CBWorldExperiment.generate(CBWorldSeed.seeds(2406))
	if not created.ok:
		push_error(created.message)
		return
	experiment = created.experiment
	var issue := ""
	if not test_mode and FileAccess.file_exists(WORLD_SAVE):
		var stored := CBLabIO.read(WORLD_SAVE)
		var restored := CBWorldExperiment.read_document(stored.value) if stored.ok else stored
		if restored.ok:
			loading = restored.experiment
			loading_from_save = true
		else:
			save_locked = true
			issue = "Saved world protected: " + restored.message
	_environment()
	camera.size = 76
	view = CBLivingView.new()
	add_child(view)
	view.draw_lab(experiment.sim)
	ui = CBLivingInterface.new()
	ui.game = self
	add_child(ui)
	ui.action.connect(command)
	if not issue.is_empty(): ui.toast(issue)
	_compose_camera()

func _process(delta: float) -> void:
	if experiment == null or ui == null: return
	_compose_camera()
	var start := Time.get_ticks_usec()
	var steps := 0
	if loading != null:
		while loading.restore_hour > 0 and steps < 48 and Time.get_ticks_usec() - start < 4000:
			loading.tick()
			steps += 1
		if loading.restore_hour == 0:
			if loading.replay_error.is_empty():
				experiment = loading
				save_locked = false
				(ui as CBLivingInterface).seed_draft = loading.layer_seeds.duplicate()
				(ui as CBLivingInterface).workshop_text = ""
				(ui as CBLivingInterface).editor = null
				dirty = true
				ui.toast("World restored from pinned inputs and decisions.")
				loading = null
				_redraw()
			else:
				ui.show_error(loading.replay_error + " Your previous world is intact.")
				loading = null
				if loading_from_save: save_locked = true
		else: ui.toast("Replaying world · day %d of %d" % [int(loading.sim.state.hour) / 24, loading.restore_hour / 24])
	else:
		var old_phase := experiment.phase
		while experiment.phase == "running" and steps < 6 and Time.get_ticks_usec() - start < 4000:
			experiment.tick()
			steps += 1
		if steps > 0: dirty = true
		var world := _world()
		if world.revision != last_revision:
			last_revision = world.revision
			_redraw()
		elif world.proposals.size() != last_proposals and ui.pane == "Design": ui.show_panel("Design")
		last_proposals = world.proposals.size()
		if old_phase == "running" and experiment.phase == "paused":
			ui.show_panel(ui.pane)
			ui.toast("The three futures reached the same date. Read proposals or compare what changed.")
			_save()
	refresh_elapsed += delta
	save_elapsed += delta
	if refresh_elapsed >= 0.15:
		refresh_elapsed = 0
		view.refresh()
		(view as CBLivingView).show_work(_world())
		ui.refresh()
	if save_elapsed >= 5 and dirty:
		save_elapsed = 0
		_save()

func _world() -> CBLivingWorld:
	var e := experiment as CBWorldExperiment
	return e.worlds[e.active]

func command(input: Dictionary) -> void:
	var e := experiment as CBWorldExperiment
	var interface := ui as CBLivingInterface
	var result := {"ok": true, "message": ""}
	if loading != null and not input.type in ["lens", "rotate", "zoom", "collapse"]:
		ui.toast("Finishing replay before changing worlds.")
		return
	match input.type:
		"future":
			e.select_future(int(input.index))
			_clear_preview()
			_redraw()
		"new_world":
			result = _replace(CBWorldExperiment.generate(input.seeds, e.living_kit, e.source_packs))
		"remix":
			var parsed := CBLabIO.parse_text(str(input.text))
			if parsed.ok:
				var issue := CBLivingWorld.kit_error(parsed.value)
				result = _replace(CBWorldExperiment.generate(e.layer_seeds, parsed.value, e.source_packs)) if issue.is_empty() else CBLabCatalog.fail(issue)
			else: result = parsed
		"preview":
			e.phase = "paused"
			interface.draft_command = input.command.duplicate(true)
			interface.draft_result = _world().preview(input.command)
			ui.show_panel("People")
			(view as CBLivingView).show_preview(interface.draft_result.get("plans", []), int(input.command.home), interface.draft_result.ok)
		"confirm_preview":
			if interface.draft_command.is_empty(): return
			result = e.act("build", interface.draft_command)
			if result.ok:
				_clear_preview()
				_redraw()
		"cancel_preview":
			_clear_preview()
			ui.show_panel("People")
		"build":
			result = e.act("build", input.command)
			if result.ok: _redraw()
		"accept", "dismiss":
			result = e.act(input.type, int(input.home))
			if result.ok: _redraw()
		"run":
			_clear_preview()
			result = e.start(int(input.hours))
			ui.show_panel(ui.pane)
		"pause":
			_clear_preview()
			e.pause()
			ui.show_panel(ui.pane)
		"select":
			_clear_preview()
			selected = clampi(int(input.index), 0, e.sim.zones.size() - 1)
			view.selected = selected
			view.refresh()
			ui.show_panel("People")
		"export": _export(str(input.get("kind", "experiment")))
		"legacy":
			_save()
			get_parent().open_mode(str(input.mode))
		_:
			super.command(input)
			return
	dirty = true
	if not result.message.is_empty(): ui.toast(result.message)
	if not result.ok: ui.show_error(result.message)
	ui.refresh()

func _clear_preview() -> void:
	var interface := ui as CBLivingInterface
	interface.draft_command = {}
	interface.draft_result = {}
	(view as CBLivingView).show_preview([], -1, true)

func _redraw() -> void:
	super._redraw()
	(view as CBLivingView).show_work(_world())

func _backup() -> Dictionary:
	if test_mode: return {"ok": true, "message": ""}
	var path := WORLD_SAVE + ".backup-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	if save_locked and FileAccess.file_exists(WORLD_SAVE):
		if DirAccess.copy_absolute(WORLD_SAVE, path + "-protected") != OK: return CBLabCatalog.fail("Could not back up the protected save.")
	return CBSaves.write(path, experiment.export_document())

func _replace(created: Dictionary) -> Dictionary:
	if not created.ok: return created
	var backed_up := _backup()
	if not backed_up.ok: return backed_up
	experiment = created.experiment
	save_locked = false
	var interface := ui as CBLivingInterface
	interface.seed_draft = (experiment as CBWorldExperiment).layer_seeds.duplicate()
	interface.workshop_text = ""
	interface.editor = null
	_clear_preview()
	selected = 0
	last_revision = -1
	_redraw()
	ui.show_panel("Design")
	dirty = true
	_save()
	return {"ok": true, "message": "New matched futures ready. Previous world backed up."}

func _save() -> void:
	if test_mode or save_locked or loading != null or experiment == null: return
	var result := CBSaves.write(WORLD_SAVE, experiment.export_document())
	if result.ok: dirty = false
	elif ui != null: ui.toast(result.message)

func restore(value: Variant) -> Dictionary:
	var result := CBWorldExperiment.read_document(value)
	if not result.ok: return result
	var backed_up := _backup()
	if not backed_up.ok: return backed_up
	experiment.phase = "paused"
	loading = result.experiment
	loading_from_save = false
	_clear_preview()
	return result

func _export(kind: String, _draft_text: String = "") -> void:
	var e := experiment as CBWorldExperiment
	if kind == "schema":
		_export_bytes(FileAccess.get_file_as_bytes("res://schemas/living-kit.schema.json"), "living-kit.schema.json", "application/json")
		return
	if kind == "prompt":
		var prompt := "Create a Courtyard Block living kit using the schema below. Return JSON only, no scripts. Start from the included kit. Supported changes: construction cost and time, household space targets, priority weights, delegated project budgets, utility upgrade recipes. Keep units and bounds. These are synthetic assumptions; do not invent evidence or imply new physics. Explain your intended experiment and tradeoffs in notes. Full world packs also support materials and assemblies through the separate lab-pack schema.\n\nSCHEMA\n" + FileAccess.get_file_as_string("res://schemas/living-kit.schema.json") + "\n\nCURRENT KIT\n" + JSON.stringify(e.living_kit, "  ")
		_export_bytes(prompt.to_utf8_buffer(), "living-world-mod-prompt.txt", "text/plain")
		return
	if kind == "results":
		var reports: Array = []
		for world in e.worlds: reports.append({"mode": CBLivingWorld.MODES[world.mode], "report": world.model.report(), "construction_spent_cents": world.spent, "completed_projects": world.completed, "construction_energy_exchange_j": world.energy_exchange_j, "imported_building_mass_kg": world.imported_mass_kg, "removed_building_mass_kg": world.removed_mass_kg, "journal": world.journal})
		_export_bytes(JSON.stringify({"runtime": CBWorldExperiment.RUNTIME, "input_hash": e.export_document().input_hash, "futures": reports}, "  ", true, true).to_utf8_buffer(), "three-futures-results.json", "application/json")
		return
	var path := "user://living-world-export.zip"
	var written := CBLabIO.write_zip(path, "experiment.json", e.export_document())
	if written.ok:
		_export_bytes(FileAccess.get_file_as_bytes(path), "courtyard-living-world.zip", "application/zip")
		DirAccess.remove_absolute(path)
	else: ui.toast(written.message)

func _import_file(path: String) -> void:
	var result := CBLabIO.read(path, "manifest.json" if file_purpose == "pack" else "experiment.json")
	if result.ok:
		if file_purpose == "pack":
			var e := experiment as CBWorldExperiment
			var packs := e.source_packs.duplicate(true)
			packs.append(result.value)
			result = _replace(CBWorldExperiment.generate(e.layer_seeds, e.living_kit, packs))
		else: result = restore(result.value)
	ui.toast(result.message)
	if not result.ok: ui.show_error(result.message)
