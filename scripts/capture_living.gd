extends SceneTree
## Capture actual matched futures for the website; never load or overwrite saves.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1120, 840)
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	for frame in 5: await process_frame
	var game := main.lab_game as CBLivingGame
	game.set_process(false)
	var experiment := game.experiment as CBWorldExperiment
	experiment.start(720)
	while experiment.phase == "running": experiment.tick()
	for child in game.get_children():
		if child is WorldEnvironment: child.environment.background_color = Color.WHITE
	game.ui.root.hide()
	game.camera.size = 79
	game.camera.h_offset = 0
	game.camera.v_offset = 0
	for i in 3:
		game.command({"type": "future", "index": i})
		game.view.selection.hide()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://website/src/assets/living-%s.png" % ["guide", "collaborate", "grow"][i]
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Could not capture " + path)
			quit(1)
			return
	print("LIVING_SITE_IMAGES_READY")
	quit()
