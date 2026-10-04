extends SceneTree
## Capture genuine in-engine images for the website. Run with -- --lab-test.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1120, 840)
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	for frame in 5: await process_frame
	var game: CBLabGame = main.lab_game
	for child in game.get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color.WHITE
	game.set_process(false)
	game.ui.root.hide()
	game.camera.size = 60
	game.camera.h_offset = 0
	game.camera.v_offset = 0
	game.command({"type": "edit", "key": "assembly", "value": "core:warm_wall"})
	game.view.lens = "materials"
	for layout in ["courtyard", "cluster", "canopy"]:
		game.command({"type": "edit", "key": "layout", "value": "core:" + layout})
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var file: String = "res://website/src/assets/" + str(layout) + ".png"
		var result := root.get_texture().get_image().save_png(file)
		if result != OK:
			push_error("Could not capture " + file)
			quit(1)
			return
	print("SITE_IMAGES_READY")
	quit()
