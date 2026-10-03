extends Node3D

var catalog: CBCatalog
var sim: CBSimulation
var diorama: CBDiorama
var interface: CBInterface
var camera: Camera3D
var camera_yaw := PI / 4.0
var camera_focus := Vector3(0, 5, 0)
var paused := false
var speed := 1
var accumulated := 0.0
var refresh_accumulated := 0.0
var autosave_accumulated := 0.0
var dragging := false
var drag_distance := 0.0
var last_touch_distance := 0.0
var touches: Dictionary = {}
var other_branch: Dictionary = {}
var browser_callback: JavaScriptObject
var file_purpose := ""
var pending_steps := 0
var smoke := false
var benchmark := false
var screenshot_path := ""
var frames := 0
var frame_times: Array[float] = []
var stress_count := 0
var save_locked := false
var startup_issue := ""

func _ready() -> void:
	get_window().content_scale_size = Vector2i.ZERO
	_configure_scale()
	get_window().size_changed.connect(_configure_scale)
	for argument in OS.get_cmdline_user_args():
		if argument == "--smoke": smoke = true
		if argument == "--benchmark": benchmark = true
		if argument.begins_with("--screenshot="): screenshot_path = argument.trim_prefix("--screenshot=")
	catalog = CBModLoader.create_catalog(not smoke)
	if not catalog.errors.is_empty():
		startup_issue = "Mods could not load: " + "; ".join(catalog.errors)
		push_warning(startup_issue)
		save_locked = true
		catalog = CBModLoader.create_catalog(false)
	sim = CBSimulation.new(catalog)
	sim.create({"population": 150 if benchmark else 64, "floors": 7 if benchmark else 6})
	if benchmark:
		stress_count = 5000
		for i in 10000:
			catalog.register_content("furniture", {"id": "benchmark:item_%05d" % i, "name": "Benchmark item %s" % i, "cost": 100, "shape": "table", "benefit": 1})
	if not smoke and not benchmark and FileAccess.file_exists(CBSaves.SAVE_PATH):
		var loaded := CBSaves.read(CBSaves.SAVE_PATH)
		if loaded.ok:
			var result := sim.load_state(loaded.state)
			if not result.ok:
				startup_issue = result.message
				save_locked = true
		else:
			startup_issue = loaded.message
			save_locked = true
	if FileAccess.file_exists(CBSaves.FORK_PATH) and not smoke:
		var loaded := CBSaves.read(CBSaves.FORK_PATH)
		if loaded.ok: other_branch = loaded.state
	_environment()
	diorama = CBDiorama.new()
	add_child(diorama)
	diorama.rebuild(sim.state, catalog, stress_count)
	interface = CBInterface.new()
	add_child(interface)
	interface.setup(sim)
	interface.action.connect(_on_action)
	if not startup_issue.is_empty():
		var notice := AcceptDialog.new()
		notice.title = "Your saved community is protected"
		notice.dialog_text = startup_issue + "\n\nA temporary community is open. Restore the matching packs to resume.\nAutosave is disabled; export any new work separately."
		add_child(notice)
		notice.popup_centered(Vector2i(600, 200))
	if not benchmark:
		diorama.set_floor(2)
		interface.floor_label.text = "Floor 2"
	if OS.has_feature("web") and not OS.is_userfs_persistent():
		interface.toast("Browser storage is temporary. Export your community to keep it.")
	get_tree().auto_accept_quit = false
	_update_camera()
	if smoke and not benchmark:
		paused = true
		interface.speed_button.text = "Play"
	if benchmark: speed = 20

func _configure_scale() -> void:
	var scale_value := 1.0
	if OS.has_feature("web"):
		scale_value = float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	elif OS.has_feature("mobile"):
		scale_value = maxf(1.0, float(get_window().size.y) / 390.0)
	if not is_equal_approx(get_window().content_scale_factor, scale_value):
		get_window().content_scale_factor = scale_value

func _environment() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#e6e5d9")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff3db")
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	add_child(environment_node)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48, -35, 0)
	sunlight.light_color = Color("#fff0ce")
	sunlight.light_energy = 0.5
	sunlight.shadow_enabled = true
	sunlight.directional_shadow_max_distance = 130
	sunlight.shadow_bias = 0.08
	add_child(sunlight)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 68
	camera.near = 0.1
	camera.far = 500
	camera.h_offset = 6.5
	add_child(camera)
	camera.make_current()

func _update_camera() -> void:
	camera.position = camera_focus + Vector3(sin(camera_yaw) * 75, 60, cos(camera_yaw) * 75)
	camera.look_at(camera_focus)

func _process(delta: float) -> void:
	if sim == null or diorama == null: return
	frames += 1
	if (smoke or benchmark) and frames > 120: frame_times.append(delta * 1000.0)
	if not paused:
		accumulated += delta * speed
	var steps := 0
	while (accumulated >= 1.0 or pending_steps > 0) and steps < 8:
		sim.step()
		if pending_steps > 0: pending_steps -= 1
		else: accumulated -= 1.0
		steps += 1
		if pending_steps == 0 and paused:
			_update_comparison()
	diorama.update_people(delta)
	refresh_accumulated += delta
	autosave_accumulated += delta
	if refresh_accumulated > 0.5:
		refresh_accumulated = 0.0
		interface.refresh()
	if autosave_accumulated > 30 and not smoke and not benchmark and not save_locked:
		autosave_accumulated = 0.0
		CBSaves.write(CBSaves.SAVE_PATH, sim.state)
	if smoke and frames == 90:
		_smoke_actions()
	if smoke and frames == (3720 if benchmark else 150):
		_finish_smoke()

func _smoke_actions() -> void:
	if benchmark: return
	_on_action({"ui": "home", "id": sim.state.residents[0].home})
	_on_action({"type": "furnish", "space": sim.state.residents[0].home, "item": "soft_spaces:reading_chair"})
	_on_action({"type": "policy", "key": "shared_meals", "value": true})
	for tick in 48: sim.step()
	interface.selected_home = ""
	interface.show_panel("Overview")
	diorama.set_floor(2)
	interface.floor_label.text = "Floor 2"
	interface.toast("Welcome to your courtyard. Every small choice makes a difference.")

func _finish_smoke() -> void:
	if not screenshot_path.is_empty() and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(screenshot_path)
	frame_times.sort()
	var report := {"platform": OS.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "residents": sim.state.residents.size(), "stress_objects": stress_count, "catalogue": catalog.list_content("furniture").size(), "frames": frame_times.size(), "p95_ms": frame_times[int(frame_times.size() * 0.95)] if not frame_times.is_empty() else 0, "simulation_step_ms": sim.last_step_usec / 1000.0}
	print("SMOKE_OK " + JSON.stringify(report))
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").courtyardBenchmark = JSON.stringify(report)
		paused = true
		set_process(false)
		return
	if benchmark:
		DirAccess.make_dir_recursive_absolute("res://artifacts")
		var report_file := FileAccess.open("res://artifacts/native-benchmark.json", FileAccess.WRITE)
		if report_file != null: report_file.store_string(JSON.stringify(report, "  "))
	get_tree().quit()

func _on_action(command: Dictionary) -> void:
	if command.has("type"):
		var result := sim.command(command)
		interface.toast(result.message)
		if result.get("geometry_changed", false):
			diorama.rebuild(sim.state, catalog, stress_count)
			interface.show_panel(interface.pane)
			if sim.state.layout.kind == "village": camera.size = sim.state.layout.width * 1.25
		interface.refresh()
		return
	match command.get("ui", ""):
		"pause":
			paused = not paused
			interface.speed_button.text = "Play" if paused else "Pause"
		"speed": speed = int(command.value)
		"zoom": camera.size = clampf(camera.size * float(command.value), 18, 160)
		"rotate":
			camera_yaw += float(command.value)
			_update_camera()
		"floor":
			var floor_value := diorama.selected_floor
			if floor_value < 0: floor_value = int(sim.state.layout.floors) - 1
			else: floor_value = clampi(floor_value + int(command.value), 0, int(sim.state.layout.floors) - 1)
			diorama.set_floor(floor_value)
			interface.floor_label.text = "Ground floor" if floor_value == 0 else "Floor %s" % floor_value
		"all_floors":
			diorama.set_floor(-1)
			interface.floor_label.text = "All floors"
		"resident":
			for person in sim.state.residents:
				if person.id == command.id:
					diorama.highlight(sim.spaces[person.home])
		"home":
			interface.selected_home = command.id
			var space: Dictionary = sim.spaces[command.id]
			diorama.set_floor(int(space.floor))
			interface.floor_label.text = "Floor %s" % space.floor
			diorama.highlight(space)
			interface.show_panel("Build")
		"save": interface.toast("Saved community is protected. Export this community instead." if save_locked else CBSaves.write(CBSaves.SAVE_PATH, sim.state).message)
		"load":
			var saved := CBSaves.read(CBSaves.SAVE_PATH)
			if saved.ok: _restore(saved.state)
			else: interface.toast(saved.message)
		"fork":
			if save_locked:
				interface.toast("Restore the matching packs before replacing saved experiment branches.")
				return
			other_branch = sim.state.duplicate(true)
			other_branch.branch.origin_minute = sim.state.minute
			CBSaves.write(CBSaves.FORK_PATH, other_branch)
			sim.state = CBSaves.fork_state(sim.state, "Another possibility")
			sim.load_state(sim.state)
			diorama.rebuild(sim.state, catalog)
			_update_comparison()
			interface.toast("Baseline kept. You are now exploring another possibility.")
		"switch_branch":
			if other_branch.is_empty():
				interface.toast("Fork a community first.")
			else:
				var current: Dictionary = sim.state.duplicate(true)
				_restore(other_branch)
				other_branch = current
				CBSaves.write(CBSaves.FORK_PATH, other_branch)
				_update_comparison()
		"week":
			paused = true
			interface.speed_button.text = "Play"
			pending_steps = 96 * 7
			interface.toast("Living through one week…")
		"export": _export_save()
		"import": _pick_file("save")
		"install_mod":
			var confirmation := ConfirmationDialog.new()
			confirmation.dialog_text = "Trusted code mods can access the game's files and capabilities.\nChoose a pack only if you trust its creator. Restart after installing."
			confirmation.title = "Install a trusted mod"
			confirmation.confirmed.connect(func() -> void: _pick_file("mod"); confirmation.queue_free())
			confirmation.canceled.connect(confirmation.queue_free)
			add_child(confirmation)
			confirmation.popup_centered(Vector2i(520, 160))

func _restore(data: Dictionary) -> void:
	var result := sim.load_state(data)
	interface.toast(result.message)
	if result.ok:
		diorama.rebuild(sim.state, catalog, stress_count)
		interface.selected_home = ""
		interface.selected_resident = ""
		interface.show_panel(interface.pane)
		_update_comparison()

func _update_comparison() -> void:
	if other_branch.is_empty(): return
	interface.comparison = CBSaves.compare(sim.state, other_branch)
	if interface.pane == "Experiments": interface.show_panel("Experiments")

func _export_save() -> void:
	var bytes := JSON.stringify(sim.state, "", true, true).to_utf8_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, "courtyard-block.json", "application/json")
	else:
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.use_native_dialog = true
		dialog.current_file = "courtyard-block.json"
		dialog.add_filter("*.json", "Community save")
		dialog.file_selected.connect(func(path: String) -> void: interface.toast(CBSaves.write(path, sim.state).message); dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered_ratio(0.7)

func _pick_file(purpose: String) -> void:
	file_purpose = purpose
	if OS.has_feature("web"):
		browser_callback = JavaScriptBridge.create_callback(_browser_file)
		var window := JavaScriptBridge.get_interface("window")
		window.courtyardImport = browser_callback
		JavaScriptBridge.eval("(function(){const i=document.createElement('input');i.type='file';i.accept='.json,.zip';i.onchange=()=>{const f=i.files[0];if(!f)return;if(f.size>67108864){window.courtyardImport('', '');return;}const r=new FileReader();r.onload=()=>window.courtyardImport(f.name,String(r.result).split(',')[1]);r.readAsDataURL(f);};i.click();})()", true)
	else:
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.use_native_dialog = true
		dialog.add_filter("*.zip" if purpose == "mod" else "*.json", "Mod pack" if purpose == "mod" else "Community save")
		dialog.file_selected.connect(func(path: String) -> void: _import_file(path); dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered_ratio(0.7)

func _browser_file(arguments: Array) -> void:
	if arguments.size() != 2 or str(arguments[0]).is_empty():
		interface.toast("Choose a file smaller than 64 MiB.")
		return
	var path := "user://incoming.zip" if file_purpose == "mod" else "user://incoming.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		interface.toast("Unable to read the selected file.")
		return
	file.store_buffer(Marshalls.base64_to_raw(str(arguments[1])))
	file.close()
	_import_file(path)
	DirAccess.remove_absolute(path)

func _import_file(path: String) -> void:
	if file_purpose == "mod":
		interface.toast(CBModLoader.install_zip(path).message)
	else:
		var saved := CBSaves.read(path)
		if saved.ok: _restore(saved.state)
		else: interface.toast(saved.message)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: camera.size = maxf(18, camera.size * 0.94)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: camera.size = minf(160, camera.size * 1.06)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_distance = 0
			else:
				dragging = false
				if drag_distance < 5: _select_at(event.position)
	if event is InputEventMouseMotion and dragging:
		drag_distance += event.relative.length()
		var right := camera.global_basis.x
		var forward := Vector3(-right.z, 0, right.x)
		camera_focus -= (right * event.relative.x + forward * event.relative.y) * camera.size / 900.0
		_update_camera()
	if event is InputEventMagnifyGesture:
		camera.size = clampf(camera.size / event.factor, 18, 160)
	if event is InputEventScreenTouch:
		if event.pressed: touches[event.index] = event.position
		else: touches.erase(event.index)
		last_touch_distance = 0
	if event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() == 2:
			var positions: Array = touches.values()
			var distance: float = positions[0].distance_to(positions[1])
			if last_touch_distance > 0: camera.size = clampf(camera.size * last_touch_distance / maxf(distance, 1), 18, 160)
			last_touch_distance = distance
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _on_action({"ui": "pause"})
			KEY_Q: _on_action({"ui": "rotate", "value": -PI / 2})
			KEY_E: _on_action({"ui": "rotate", "value": PI / 2})

func _select_at(screen: Vector2) -> void:
	for i in sim.state.residents.size():
		var p := diorama.displayed_positions[i]
		if diorama.selected_floor >= 0 and p.y > diorama.selected_floor * 3.2 + 2.5: continue
		if camera.unproject_position(p + Vector3(0, 1, 0)).distance_to(screen) < 12:
			interface.selected_resident = sim.state.residents[i].id
			interface.show_panel("Residents")
			return
	var level := diorama.selected_floor
	if level < 0:
		interface.toast("Choose a floor with − or + to look inside and select a home.")
		return
	var plane := Plane(Vector3.UP, level * 3.2)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null: return
	for space in sim.state.layout.spaces:
		if space.kind != "home" or int(space.floor) != level: continue
		var p := CBSpatial.vector(space.position)
		if absf(hit.x - p.x) < float(space.size[0]) / 2 and absf(hit.z - p.z) < float(space.size[1]) / 2:
			_on_action({"ui": "home", "id": space.id})
			return

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sim != null and not smoke and not benchmark and not save_locked: CBSaves.write(CBSaves.SAVE_PATH, sim.state)
		get_tree().quit()
	if what == NOTIFICATION_APPLICATION_PAUSED and sim != null and not smoke and not benchmark and not save_locked:
		CBSaves.write(CBSaves.SAVE_PATH, sim.state)
