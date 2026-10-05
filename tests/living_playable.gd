extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func settle(frames: int = 5) -> void:
	for frame in frames: await process_frame

func finish(game: CBLivingGame) -> void:
	for frame in 4000:
		await process_frame
		if game.experiment.phase != "running" and game.loading == null: return
	check(false, "Living simulation completes within the frame-budgeted scene limit")

func run() -> void:
	root.size = Vector2i(1440, 900)
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await settle()
	var game := main.lab_game as CBLivingGame
	check(game != null, "Default entry point opens living worlds")
	if game == null:
		quit(1)
		return
	var e := game.experiment as CBWorldExperiment
	var ui := game.ui as CBLivingInterface
	check(e.sim.state.hour == 0 and e.phase == "paused", "World waits for the player's first experiment")
	game.command({"type": "future", "index": 0})
	game.command({"type": "select", "index": 0})
	game.command({"type": "preview", "command": CBLivingWorld.action("add", 0, [2, 4, 3])})
	check(ui.draft_result.ok and (game.view as CBLivingView).ghost != null, "Build panel exposes a valid 3D room preview")
	check(e.worlds[0].spent == 0, "Preview spends nothing")
	game.command({"type": "cancel_preview"})
	check(ui.draft_command.is_empty() and (game.view as CBLivingView).ghost == null, "Cancel removes the preview without changing the world")
	game.command({"type": "preview", "command": CBLivingWorld.action("add", 0, [2, 4, 3])})
	game.command({"type": "confirm_preview"})
	check(not e.worlds[0].pending.is_empty() and e.worlds[0].spent > 0, "Confirm starts a paid construction project")
	game.command({"type": "run", "hours": 168})
	game.command({"type": "pause"})
	var paused_hour := int(e.sim.state.hour)
	await settle()
	check(e.sim.state.hour == paused_hour, "Pause freezes all three futures")
	game.command({"type": "pause"})
	await finish(game)
	check(e.sim.state.hour == 168 and e.worlds[2].model.state.hour == 168, "Week completes with all futures at the same hour")
	check(e.worlds[0].model.plans[0].rooms.size() == 4 and game.view.lab == e.sim, "Completed construction redraws the live model")
	var document := e.export_document()
	check(game.restore(document).ok, "Controller stages a portable import")
	check(game.experiment == e, "Import keeps the current experiment until replay validates")
	await finish(game)
	var restored := game.experiment as CBWorldExperiment
	check(restored != e and CBLabCatalog.canonical(restored.sim.state) == CBLabCatalog.canonical(e.sim.state), "Frame-budgeted replay atomically installs the identical world")
	var malformed := document.duplicate(true)
	malformed.commands[0].value.value = [0, 1, 1]
	check(not game.restore(malformed).ok and game.experiment == restored, "Malformed commands preserve the current world")
	var impossible := document.duplicate(true)
	impossible.commands[0].value = CBLivingWorld.action("move", 0, [0, 0])
	check(game.restore(impossible).ok, "Syntactically valid command is checked during replay")
	await finish(game)
	check(game.experiment == restored, "Semantically impossible replay never replaces the active world")
	for child in game.ui.get_children():
		if child is AcceptDialog: child.queue_free()
	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1440, 900)]:
		root.size = dimensions
		for section in ["Design", "People", "Compare", "Workshop", "Evidence"]:
			ui.show_panel(section)
			await settle()
			ui.responsive()
			game._compose_camera()
			check(ui.inspector.position.x >= 0 and ui.inspector.position.x + ui.inspector.size.x <= dimensions.x + 1, "%s panel fits %s" % [section, dimensions])
			check(ui.body.size.x <= ui.scroll.size.x + 1, "%s content fits without horizontal scrolling" % section)
		check(ui.footer.position.x + ui.footer.size.x <= dimensions.x and ui.footer.position.y + ui.footer.size.y <= dimensions.y, "Time controls remain within the screen")
		if dimensions.x == 390:
			ui.show_panel("People")
			game.command({"type": "collapse"})
			check(not ui.inspector.visible, "Phone can reveal the full scene")
			ui.show_panel("Compare")
			await settle()
			check(ui.inspector.visible, "Switching panels restores phone controls")
		if DisplayServer.get_name() != "headless":
			ui.show_panel("People")
			await settle(10)
			get_root().get_texture().get_image().save_png("res://artifacts/living-%dx%d.png" % [dimensions.x, dimensions.y])
	print("LIVING PLAYABLE: %d checks, %d failures" % [checks, failures.size()])
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
