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
var last_frame_usec := 0
var simulated_steps := 0
var step_times: Array[float] = []
var stress_count := 0
var save_locked := false
var startup_issue := ""
var reference_sim: CBSimulation
var evening_smoke := false
var foundation := false
var last_portrait := false

func _ready() -> void:
	get_window().content_scale_size = Vector2i.ZERO
	_configure_scale()
	get_window().size_changed.connect(_configure_scale)
	for argument in OS.get_cmdline_user_args():
		if argument == "--foundation": foundation = true
		if argument == "--evening-smoke":
			evening_smoke = true
			smoke = true
		if argument == "--smoke": smoke = true
		if argument == "--benchmark": benchmark = true
		if argument.begins_with("--screenshot="): screenshot_path = argument.trim_prefix("--screenshot=")
	var with_evening := not foundation and not benchmark and (not smoke or evening_smoke)
	catalog = CBModLoader.create_catalog(not smoke, with_evening)
	if not catalog.errors.is_empty():
		startup_issue = "Mods could not load: " + "; ".join(catalog.errors)
		push_warning(startup_issue)
		save_locked = true
		catalog = CBModLoader.create_catalog(false, with_evening)
	sim = CBSimulation.new(catalog)
	if with_evening:
		sim.create({"scenario": "evening"})
		paused = true
	else: sim.create({"population": 150 if benchmark else 64, "floors": 7 if benchmark else 6})
	if benchmark:
		stress_count = 5000
		for i in 10000:
			catalog.register_content("furniture", {"id": "benchmark:item_%05d" % i, "name": "Benchmark item %s" % i, "cost": 100, "shape": "table", "benefit": 1})
	if not smoke and not benchmark and FileAccess.file_exists(_save_path()):
		var loaded := CBSaves.read(_save_path())
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
	interface.speed_button.text = "Play" if paused else "Pause"
	if sim.state.has("evening"):
		_start_reference()
		paused = true
		interface.speed_button.text = "Play"
	if not startup_issue.is_empty():
		var notice := AcceptDialog.new()
		notice.title = "Your saved community is protected"
		notice.dialog_text = startup_issue + "\n\nA temporary community is open. Restore the matching packs to resume.\nAutosave is disabled; export any new work separately."
		add_child(notice)
		notice.popup_centered(Vector2i(600, 200))
	if not benchmark:
		diorama.set_floor(1 if sim.state.has("evening") else 2)
		interface.floor_label.text = "Floor 1" if sim.state.has("evening") else "Floor 2"
	if OS.has_feature("web") and not OS.is_userfs_persistent():
		interface.toast("Browser storage is temporary. Export your community to keep it.")
	get_tree().auto_accept_quit = false
	_update_camera()
	_compose_camera()
	if smoke and not benchmark:
		paused = true
		interface.speed_button.text = "Play"
	if benchmark: speed = 20

func _configure_scale() -> void:
	var scale_value := 1.0
	if OS.has_feature("web"):
		scale_value = float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	elif OS.has_feature("mobile"):
		scale_value = maxf(1.0, float(mini(get_window().size.x, get_window().size.y)) / 390.0)
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

func _compose_camera() -> void:
	if not sim.state.has("evening"): return
	var viewport_size := get_viewport().get_visible_rect().size
	var portrait := viewport_size.x < 600 or (viewport_size.x < 1000 and viewport_size.y > viewport_size.x * 1.05)
	if portrait != last_portrait:
		camera.size = 82 if portrait else 68
		last_portrait = portrait
	camera.keep_aspect = Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT
	if portrait:
		camera.h_offset = 0
		camera.v_offset = 0 if interface.panel_collapsed else -viewport_size.y * 0.24 * camera.size / viewport_size.x
	else:
		var panel_width := 306 if viewport_size.x < 1100 else 410
		var left := 12 if viewport_size.x < 1100 else 200
		var right := viewport_size.x - 12 if interface.panel_collapsed and viewport_size.x < 1100 else viewport_size.x - panel_width - 28
		var center := (left + right) / 2.0
		camera.h_offset = (viewport_size.x / 2.0 - center) * camera.size / viewport_size.y
		camera.v_offset = 0

func _process(delta: float) -> void:
	if sim == null or diorama == null: return
	_compose_camera()
	frames += 1
	var now := Time.get_ticks_usec()
	if (smoke or benchmark) and frames > 120: frame_times.append((now - last_frame_usec) / 1000.0)
	last_frame_usec = now
	if reference_sim != null:
		for _step in 2:
			reference_sim.step()
		if reference_sim.state.evening.phase == "complete":
			sim.state.evening.baseline = CBEvening.report(reference_sim)
			reference_sim = null
			if interface.pane == "Try": interface.show_panel("Try")
	if not paused:
		accumulated += delta * speed
	var steps := 0
	while (accumulated >= 1.0 or pending_steps > 0) and steps < 8:
		sim.step()
		simulated_steps += 1
		if smoke or benchmark: step_times.append(sim.last_step_usec / 1000.0)
		if pending_steps > 0: pending_steps -= 1
		else: accumulated -= 1.0
		steps += 1
		if sim.state.has("evening") and sim.state.evening.phase == "complete":
			diorama.snap_people()
			paused = true
			pending_steps = 0
			accumulated = 0
			interface.speed_button.text = "Play"
			interface.show_panel("Try")
			interface.toast("Evening complete. Who gained time, and who still needs a better solution?")
			break
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
		CBSaves.write(_save_path(), sim.state)
	if smoke and frames == 90:
		_smoke_actions()
	if smoke and frames == (3720 if benchmark else 150):
		_finish_smoke()

func _smoke_actions() -> void:
	if benchmark: return
	if evening_smoke:
		_on_action({"type": "evening_service", "id": "evening:kitchen"})
		_on_action({"ui": "evening_run", "fast": true})
		return
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
	step_times.sort()
	var report := {"platform": OS.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "residents": sim.state.residents.size(), "stress_objects": stress_count, "catalogue": catalog.list_content("furniture").size(), "frames": frame_times.size(), "p95_ms": _percentile(frame_times, 0.95), "p99_ms": _percentile(frame_times, 0.99), "maximum_ms": frame_times.back() if not frame_times.is_empty() else 0, "simulation_steps": simulated_steps, "simulation_step_p95_ms": _percentile(step_times, 0.95), "viewport": str(get_viewport().get_visible_rect().size), "debug_build": OS.is_debug_build()}
	print("SMOKE_OK " + JSON.stringify(report))
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").courtyardBenchmark = JSON.stringify(report)
		paused = true
		set_process(false)
		return
	if benchmark:
		var report_directory := "res://artifacts" if OS.has_feature("editor") else "user://benchmarks"
		DirAccess.make_dir_recursive_absolute(report_directory)
		var report_file := FileAccess.open(report_directory.path_join("native-benchmark.json"), FileAccess.WRITE)
		if report_file != null: report_file.store_string(JSON.stringify(report, "  "))
	get_tree().quit()

func _percentile(values: Array[float], fraction: float) -> float:
	return values[mini(values.size() - 1, int(values.size() * fraction))] if not values.is_empty() else 0.0

func _on_action(command: Dictionary) -> void:
	if command.has("type"):
		if command.type == "evening_reset":
			paused = true
			pending_steps = 0
			accumulated = 0
			interface.speed_button.text = "Play"
		var result := sim.command(command)
		interface.toast(result.message)
		if result.get("geometry_changed", false):
			diorama.rebuild(sim.state, catalog, stress_count)
			if command.type in ["evening_service", "evening_recipe", "evening_space"]:
				diorama.set_floor(0)
				interface.floor_label.text = "Ground floor"
			interface.show_panel("Build" if command.type == "evening_reset" else interface.pane)
			if sim.state.layout.kind == "village": camera.size = sim.state.layout.width * 1.25
		interface.refresh()
		return
	match command.get("ui", ""):
		"pause":
			if sim.state.has("evening"):
				if sim.state.evening.phase == "design":
					_run_evening(false)
					return
				if sim.state.evening.phase == "complete":
					interface.show_panel("Try")
					return
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
		"evening_run": _run_evening(bool(command.get("fast", false)))
		"evening_fast":
			if sim.state.has("evening") and sim.state.evening.phase == "running":
				paused = true
				pending_steps = ceili(float(CBEvening.END - int(sim.state.minute)) / CBSimulation.STEP_MINUTES)
		"evening_export_pack": _export_evening_pack(command.recipe)
		"evening_export_prompt":
			var prompt := "Help me design a Courtyard Block evening service. Return one JSON object using EXACTLY the fields in this example. No code or extra fields.\n\nSupported kind: groceries (three portions per household purchase, then 25 minutes cooking and 15 eating) or meal (one portion per customer). Time is integer minutes after midnight, within 960–1320. Duration: 1–60, slots: 1–24, stock: 1–150, staff: 0 or 1. Price/unit_cost are integer cents per portion; capital is integer cents. Water/sewage are L per portion, power is kWh per portion, waste is kg per portion. Bounds: water/sewage 0–20, power 0–3, waste 0–1; price/unit_cost 0–10000, capital 0–1000000, remote_minutes 0–90. Name <=60 characters, description <=400. Use a namespaced lowercase ID. Only known requirements can be simulated. State synthetic assumptions in the description; do not pretend these are measured facts.\n\nSuggest a practical tradeoff, not a free unlimited service. The host validates the result before use.\n\nExample:\n" + JSON.stringify(command.recipe, "  ")
			_export_bytes(prompt.to_utf8_buffer(), "courtyard-service-prompt.txt", "text/plain")
		"home":
			interface.selected_home = command.id
			var space: Dictionary = sim.spaces[command.id]
			diorama.set_floor(int(space.floor))
			interface.floor_label.text = "Floor %s" % space.floor
			diorama.highlight(space)
			interface.show_panel("Build")
		"save": interface.toast("Saved community is protected. Export this community instead." if save_locked else CBSaves.write(_save_path(), sim.state).message)
		"load":
			var saved := CBSaves.read(_save_path())
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
		"new_community": _new_community()
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
	if data.has("evening") != sim.state.has("evening"):
		interface.toast("Open this save in its matching mode: the evening scenario or --foundation sandbox.")
		return
	var result := sim.load_state(data)
	interface.toast(result.message)
	if result.ok:
		if sim.state.has("evening"):
			paused = true
			interface.speed_button.text = "Play"
			pending_steps = 0
			accumulated = 0
			reference_sim = null
			_start_reference()
		diorama.rebuild(sim.state, catalog, stress_count)
		interface.selected_home = ""
		interface.selected_resident = ""
		interface.show_panel(interface.pane)
		_update_comparison()

func _new_community() -> void:
	var evening := sim.state.has("evening")
	var stamp := str(int(Time.get_unix_time_from_system())) + "-" + str(Time.get_ticks_usec())
	var paths: Array = [_save_path()] if evening else [CBSaves.SAVE_PATH, CBSaves.FORK_PATH]
	for path in paths:
		if FileAccess.file_exists(path):
			var backup: String = str(path).get_basename() + ".backup-" + stamp + ".json"
			if DirAccess.copy_absolute(path, backup) != OK:
				interface.toast("Unable to back up the previous community; no changes made.")
				return
	if not evening and FileAccess.file_exists(CBSaves.FORK_PATH): DirAccess.remove_absolute(CBSaves.FORK_PATH)
	other_branch = {}
	save_locked = false
	pending_steps = 0
	accumulated = 0
	sim.create({"scenario": "evening"} if evening else {})
	if evening:
		paused = true
		reference_sim = null
		_start_reference()
		interface.speed_button.text = "Play"
	interface.comparison = {}
	interface.selected_home = ""
	interface.selected_resident = ""
	diorama.rebuild(sim.state, catalog)
	diorama.set_floor(1 if evening else 2)
	interface.floor_label.text = "Floor 1" if evening else "Floor 2"
	interface.show_panel("Overview")
	interface.toast("New community started. Previous saves are kept as timestamped backups.")
	CBSaves.write(_save_path(), sim.state)

func _update_comparison() -> void:
	if other_branch.is_empty(): return
	interface.comparison = CBSaves.compare(sim.state, other_branch)
	if interface.pane == "Experiments": interface.show_panel("Experiments")

func _save_path() -> String:
	return "user://evening.json" if sim != null and sim.state.has("evening") else CBSaves.SAVE_PATH

func _start_reference() -> void:
	if not sim.state.has("evening") or not sim.state.evening.baseline.is_empty(): return
	reference_sim = CBSimulation.new(catalog)
	reference_sim.create({"scenario": "evening"}, int(sim.state.seed))
	CBEvening.start(reference_sim)

func _run_evening(fast: bool) -> void:
	if not sim.state.has("evening"): return
	if sim.state.evening.phase == "complete":
		interface.show_panel("Try")
		return
	if sim.state.evening.phase == "design":
		var result := sim.command({"type": "evening_start"})
		interface.toast(result.message)
		if not result.ok: return
		_start_reference()
	paused = fast
	accumulated = 0
	speed = 1
	pending_steps = ceili(float(CBEvening.END - int(sim.state.minute)) / CBSimulation.STEP_MINUTES) if fast else 0
	interface.speed_button.text = "Play" if paused else "Pause"
	interface.show_panel("Try")
	diorama.rebuild(sim.state, catalog)

func _export_evening_pack(recipe: Dictionary) -> void:
	var error := CBEvening.definition_error(recipe)
	if not error.is_empty():
		interface.toast(error)
		return
	var definition := recipe.duplicate(true)
	definition.id = "my_evening_pack:service"
	var manifest := {"id": "my_evening_pack", "name": definition.name, "version": "1.0.0", "api_version": 1, "dependencies": {"base": "1.0.0"}, "content": {"evening_services": [definition]}}
	var path := "user://evening-draft.cbmod.zip"
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		interface.toast("Unable to create pack archive.")
		return
	zip.start_file("manifest.json")
	zip.write_file(JSON.stringify(manifest, "  ").to_utf8_buffer())
	zip.close_file()
	zip.close()
	_export_bytes(FileAccess.get_file_as_bytes(path), "my-evening-pack.cbmod.zip", "application/zip")
	DirAccess.remove_absolute(path)

func _export_bytes(bytes: PackedByteArray, filename: String, mime: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, filename, mime)
		interface.toast("Download ready: " + filename)
		return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.use_native_dialog = true
	dialog.current_file = filename
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: interface.toast("Unable to write this file.")
		else:
			file.store_buffer(bytes)
			file.close()
			interface.toast("Exported " + filename)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

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
		if sim.state.has("evening") and space.kind == "shop" and level == 0:
			var room_position := CBSpatial.vector(space.position)
			if absf(hit.x - room_position.x) < float(space.size[0]) / 2 and absf(hit.z - room_position.z) < float(space.size[1]) / 2:
				interface.show_panel("Build")
				if sim.state.evening.phase == "design": _on_action({"type": "evening_space", "space": space.id})
				diorama.highlight(space)
				return
		if space.kind != "home" or int(space.floor) != level: continue
		var p := CBSpatial.vector(space.position)
		if absf(hit.x - p.x) < float(space.size[0]) / 2 and absf(hit.z - p.z) < float(space.size[1]) / 2:
			_on_action({"ui": "home", "id": space.id})
			return

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sim != null and not smoke and not benchmark and not save_locked: CBSaves.write(_save_path(), sim.state)
		get_tree().quit()
	if what == NOTIFICATION_APPLICATION_PAUSED and sim != null and not smoke and not benchmark and not save_locked:
		CBSaves.write(_save_path(), sim.state)
