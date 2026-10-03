extends SceneTree
## Drives the actual scene's command and presentation boundary without writing player saves.

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL: " + description)

func run() -> void:
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	check(main.sim.state.has("evening") and main.paused, "Evening opens paused with a protected starting design")
	check(main.interface.pane == "Inspect", "Inspect is the first screen")
	main.interface.show_panel("Build")
	main._on_action({"type": "evening_service", "id": "grocery_pickup:locker"})
	check(main.sim.state.evening.design.service == "grocery_pickup:locker", "Build selects an independent content-pack service")
	main._on_action({"ui": "evening_run", "fast": true})
	for frame in 18: await process_frame
	check(main.sim.state.evening.phase == "complete" and main.paused and main.pending_steps == 0, "Fast trial finishes and pauses automatically")
	check(main.interface.pane == "Try" and not main.sim.state.evening.baseline.is_empty(), "Matched original comparison reaches the results view")
	check(main.sim.state.evening.baseline.minute == main.sim.state.minute, "Original and intervention have the same comparison horizon")
	main._on_action({"type": "evening_reset"})
	main.interface.show_panel("Workshop")
	await process_frame
	check(main.sim.state.minute == 960 and main.interface.pane == "Workshop", "Reset preserves the design and enables workshop editing")
	var recipe: Dictionary = main.catalog.get_definition("evening_services", "evening:kitchen").duplicate(true)
	recipe.name = "Test supper room"
	main._on_action({"type": "evening_recipe", "recipe": recipe})
	check(main.sim.state.evening.design.service == "workshop:prototype", "Workshop prototype flows through the command boundary")
	main.interface.show_panel("Inspect")
	main.interface.selected_resident = "resident_002"
	main._on_action({"ui": "evening_run", "fast": true})
	for frame in 6: await process_frame
	check(main.sim.state.evening.phase == "complete" and main.sim.state.evening.attempts.size() == 1, "Second design retains the previous trial in the notebook")
	var report := CBEvening.report(main.sim)
	check(report.fed == 24 and report.people[2].free < 45, "Custom kitchen feeds its worker and reports the time tradeoff")
	main._on_action({"type": "evening_reset"})
	root.size = Vector2i(390, 844)
	for frame in 3: await process_frame
	main.interface._responsive()
	main._compose_camera()
	check(main.interface.collapse_button.visible and main.camera.keep_aspect == Camera3D.KEEP_WIDTH, "Portrait mode provides a collapsible panel and fits the scene")
	main.interface.panel_collapsed = true
	main.interface._responsive()
	check(not main.interface.inspector.visible and main.interface.floor_bar.visible, "Hidden phone panel retains floor controls")
	main.interface.panel_collapsed = false
	root.size = Vector2i(844, 390)
	for frame in 3: await process_frame
	main.interface._responsive()
	check(main.interface.inspector.visible and main.interface.floor_bar.position.y < main.interface.bottom_bar.position.y, "Landscape controls occupy separate rows")
	print("PLAYABLE: %d checks, %d failures" % [checks, failures.size()])
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
