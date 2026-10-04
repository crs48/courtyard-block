extends SceneTree
## Exercises the actual command/view boundary without touching a player's save.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func settle(frames: int = 5) -> void:
	for frame in frames: await process_frame

func finish(game: CBLabGame) -> void:
	for frame in 2500:
		await process_frame
		if game.experiment.phase == "complete" and game.experiment.restore_hour == 0: return
	check(false, "Frame-budgeted simulation completed within the scene test limit")

func button(ui: CBLabInterface, prefix: String) -> Button:
	for child in ui.body.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	return null

func run() -> void:
	root.size = Vector2i(1440, 900)
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var game: CBLabGame = main.lab_game
	check(game != null and game.experiment.phase == "design", "Default scene opens the annual lab without advancing time")
	check(game.test_mode and main.sim == null, "Lab tests protect saves and do not also advance the legacy model")
	var ui := game.ui
	check(ui.pane == "Design" and game.view.envelopes.size() == 8, "Design opens with eight visible physical homes")
	game.command({"type": "edit", "key": "layout", "value": "core:canopy"})
	check(game.view.lab.zones[0].position[1] > 0, "Elevated layout reaches physical state and rendering")
	game.command({"type": "undo"})
	check(game.experiment.design.layout == "core:courtyard", "Undo restores the original layout through the command boundary")
	ui.show_panel("Workshop")
	await settle()
	var draft_button := button(ui, "Create a draft pack")
	check(draft_button != null, "Workshop exposes a form-based mod authoring action")
	draft_button.pressed.emit()
	var draft := CBLabIO.parse_text(ui.editor.text)
	check(draft.ok and draft.value.content.materials[0].evidence.begins_with("my_walls_"), "Workshop form creates an evidence-bearing independent material pack")
	var custom_id: String = draft.value.id
	button(ui, "Validate & add").pressed.emit()
	check(game.experiment.catalog.definition("assemblies", custom_id + ":wall").size() > 0 and ui.pane == "Design", "Form-created pack installs without restarting or changing game code")
	game.command({"type": "edit", "key": "assembly", "value": custom_id + ":wall"})
	game.command({"type": "select", "index": 2})
	check(ui.pane == "People" and game.view.selected == 2, "House selection reaches the household inspector")
	game.command({"type": "run", "hours": 2160})
	check(game.view.lab == game.experiment.sim, "Starting a run binds the diorama to the newly initialized physical state")
	game.command({"type": "pause"})
	var paused_hour := int(game.experiment.sim.state.hour)
	await settle()
	check(game.experiment.sim.state.hour == paused_hour and ui.pause_button.text == "Resume", "Pause freezes both alternatives and exposes resume")
	game.command({"type": "pause"})
	await finish(game)
	check(game.experiment.sim.state.hour == 2160 and game.experiment.reference.state.hour == 2160 and ui.pane == "Compare", "Season finishes with a matched comparison")
	game.command({"type": "run", "hours": 8760})
	await finish(game)
	check(game.experiment.sim.state.totals.cold_person_hours < game.experiment.reference.state.totals.cold_person_hours, "Independent workshop wall changes annual outcomes")
	check(ui.lens.selected == 1 and ui.year_button.disabled, "Completed run displays temperature lens and disables the exhausted horizon")
	check(game.view.captions[0].text.ends_with("%.1f°" % game.experiment.sim.state.homes[0].air_c), "Final rendered temperature matches the completed model, not a stale draft")
	var portable := game.experiment.export_document()
	var previous := CBLabCatalog.canonical(game.experiment.sim.report())
	check(game.restore(portable).ok, "Scene accepts a complete portable experiment")
	await finish(game)
	check(CBLabCatalog.canonical(game.experiment.sim.report()) == previous, "Frame-budgeted import replay reproduces the annual report")
	var bad := portable.duplicate(true)
	bad.pack_lock = []
	check(not game.restore(bad).ok and CBLabCatalog.canonical(game.experiment.sim.report()) == previous, "Failed import leaves the active experiment intact")
	game.command({"type": "reset"})
	check(game.experiment.notebook.size() == 1 and game.experiment.phase == "design", "Retry retains a session notebook entry")
	ui.show_panel("Workshop")
	ui.editor.text = "old editor draft"
	ui.open_draft(draft.value)
	check(CBLabIO.parse_text(ui.editor.text).ok, "Import replaces an open workshop draft instead of silently retaining old text")
	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1440, 900)]:
		root.size = dimensions
		for section in ["Design", "People", "Compare", "Workshop", "Evidence"]:
			ui.show_panel(section)
			await settle()
			ui.responsive()
			game._compose_camera()
			check(ui.inspector.position.x >= 0 and ui.inspector.position.x + ui.inspector.size.x <= dimensions.x + 1, "%s stays within %s viewport" % [section, dimensions])
			check(ui.body.size.x <= ui.scroll.size.x + 1, "%s content fits its horizontal scroll viewport" % section)
		check(ui.footer.position.y + ui.footer.size.y <= dimensions.y, "Run controls remain on screen")
		if dimensions.x == 390:
			check(ui.collapse_button.visible and game.camera.keep_aspect == Camera3D.KEEP_WIDTH, "Phone has a visible scene/details control and fitted camera")
			game.command({"type": "collapse"})
			check(not ui.inspector.visible, "Phone scene control reveals the world")
			ui.show_panel("People")
			await settle()
			check(ui.inspector.visible, "Choosing a different pane restores collapsed phone details")
	print("LAB PLAYABLE: %d checks, %d failures" % [checks, failures.size()])
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
