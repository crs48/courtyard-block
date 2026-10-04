class_name CBLabGame
extends Node3D

const SAVE_PATH := "user://community-lab.json"
var experiment: CBLabExperiment
var view: CBLabView
var ui: CBLabInterface
var camera: Camera3D
var yaw := PI / 4.0
var focus := Vector3(0, 1, 0)
var dragging := false
var drag_distance := 0.0
var test_mode := false
var save_locked := false
var dirty := false
var save_elapsed := 0.0
var refresh_elapsed := 0.0
var browser_callback: JavaScriptObject
var file_purpose := ""
var selected := 0
var smoke := false
var screenshot := ""
var frames := 0
var finished_frames := 0
var touches: Dictionary = {}
var touch_distance := 0.0

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument in ["--lab-smoke", "--lab-test"]: test_mode = true
		if argument == "--lab-smoke": smoke = true
		if argument.begins_with("--screenshot="): screenshot = argument.trim_prefix("--screenshot=")
	get_tree().auto_accept_quit = false
	get_window().content_scale_size = Vector2i.ZERO
	_scale()
	get_window().size_changed.connect(_scale)
	var created := CBLabExperiment.create(CBLabCatalog.builtin_packs())
	if not created.ok:
		push_error(created.message)
		return
	experiment = created.experiment
	var issue := ""
	if not test_mode and FileAccess.file_exists(SAVE_PATH):
		var stored := CBLabIO.read(SAVE_PATH)
		var restored := CBLabExperiment.from_document(stored.value) if stored.ok else stored
		if restored.ok: experiment = restored.experiment
		else:
			save_locked = true
			issue = "Saved experiment protected: " + restored.message + " Export this draft or explicitly start fresh."
	_environment()
	view = CBLabView.new()
	add_child(view)
	view.draw_lab(experiment.sim)
	ui = CBLabInterface.new()
	ui.game = self
	add_child(ui)
	ui.action.connect(command)
	if not issue.is_empty(): ui.toast(issue)
	if experiment.restore_hour > 0: ui.show_panel("Compare")
	_compose_camera()

func _scale() -> void:
	var factor := 1.0
	if OS.has_feature("web"): factor = float(JavaScriptBridge.eval("window.devicePixelRatio || 1"))
	elif OS.has_feature("mobile"): factor = maxf(1.0, float(mini(get_window().size.x, get_window().size.y)) / 390.0)
	get_window().content_scale_factor = factor

func _environment() -> void:
	var node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#eeeade")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#f9efd9")
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	node.environment = environment
	add_child(node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color("#fff1d5")
	sun.light_energy = 0.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 66
	camera.far = 300
	add_child(camera)
	camera.make_current()

func _compose_camera() -> void:
	if ui == null: return
	var size := get_viewport().get_visible_rect().size
	camera.position = focus + Vector3(sin(yaw) * 65, 52, cos(yaw) * 65)
	camera.look_at(focus)
	camera.keep_aspect = Camera3D.KEEP_WIDTH if ui.portrait else Camera3D.KEEP_HEIGHT
	if ui.portrait:
		camera.h_offset = 0
		camera.v_offset = 0 if ui.collapsed else -(size.y / 2 - size.y * 0.29) * camera.size / size.x
	else:
		camera.h_offset = ui.panel_width * 0.48 * camera.size / size.y if not ui.collapsed else 0
		camera.v_offset = 0

func _process(delta: float) -> void:
	if experiment == null or ui == null: return
	frames += 1
	_compose_camera()
	var old_phase := experiment.phase
	var old_restore := experiment.restore_hour
	var start := Time.get_ticks_usec()
	var steps := 0
	while (experiment.phase == "running" or experiment.restore_hour > 0) and steps < 96 and Time.get_ticks_usec() - start < 4000:
		experiment.tick()
		steps += 1
	if steps > 0: dirty = true
	refresh_elapsed += delta
	save_elapsed += delta
	if experiment.phase != old_phase or (old_restore > 0 and experiment.restore_hour == 0):
		ui.show_panel("Compare")
		if experiment.phase == "complete":
			ui.toast("Both designs reached the same date. Inspect the households, then try another idea.")
			_save()
	if refresh_elapsed > 0.2:
		refresh_elapsed = 0
		view.refresh()
		ui.refresh()
	if save_elapsed > 5 and dirty:
		save_elapsed = 0
		_save()
	if smoke and frames == 5:
		command({"type": "edit", "key": "assembly", "value": "core:warm_wall"})
		command({"type": "run", "hours": 8760})
	if smoke and experiment.phase == "complete":
		finished_frames += 1
		if finished_frames == 10:
			if not screenshot.is_empty() and DisplayServer.get_name() != "headless": get_viewport().get_texture().get_image().save_png(screenshot)
			print("LAB_SMOKE_OK " + JSON.stringify({"hour": experiment.sim.state.hour, "reference_hour": experiment.reference.state.hour, "cold_person_hours": experiment.sim.state.totals.cold_person_hours, "viewport": str(get_viewport().get_visible_rect().size)}))
			get_tree().quit()

func command(action: Dictionary) -> void:
	var result := {"ok": true, "message": ""}
	match action.get("type", ""):
		"edit":
			result = experiment.edit(str(action.key), action.value)
			if result.ok: _redraw()
		"undo":
			result = experiment.undo_edit()
			if result.ok: _redraw()
		"reset":
			result = experiment.reset()
			if result.ok:
				_redraw()
				ui.show_panel("Design")
		"baseline": result = experiment.pin_baseline()
		"run":
			result = experiment.start(int(action.hours))
			if result.ok:
				view.lens = "temperature"
				ui.show_panel("Compare")
		"pause": experiment.pause()
		"select":
			selected = clampi(int(action.index), 0, experiment.sim.zones.size() - 1)
			view.selected = selected
			view.refresh()
			ui.show_panel("People")
		"lens":
			view.lens = str(action.value)
			view.refresh()
		"rotate": yaw += PI / 2
		"zoom": camera.size = clampf(camera.size * float(action.factor), 35, 110)
		"collapse":
			ui.collapsed = not ui.collapsed
			ui.responsive()
		"import": _pick_file(str(action.purpose))
		"install_draft":
			var parsed := CBLabIO.parse_text(str(action.text))
			result = experiment.install(parsed.value) if parsed.ok else parsed
			if result.ok:
				_redraw()
				ui.show_panel("Design")
		"export": _export(str(action.get("kind", "experiment")), str(action.get("text", "")))
		"fresh":
			if not test_mode and FileAccess.file_exists(SAVE_PATH):
				var backup := SAVE_PATH + ".backup-" + str(int(Time.get_unix_time_from_system()))
				if DirAccess.copy_absolute(SAVE_PATH, backup) != OK:
					ui.toast("Could not back up the saved experiment. No changes made.")
					return
			experiment = CBLabExperiment.create(CBLabCatalog.builtin_packs()).experiment
			save_locked = false
			_redraw()
			ui.show_panel("Design")
			result.message = "Fresh experiment. Previous save backed up."
		"legacy":
			_save()
			get_parent().open_mode(str(action.mode))
	dirty = true
	if not result.message.is_empty(): ui.toast(result.message)
	if not result.ok: ui.show_error(result.message)
	ui.refresh()

func _redraw() -> void:
	selected = mini(selected, experiment.sim.zones.size() - 1)
	view.selected = selected
	view.draw_lab(experiment.sim)
	ui.show_panel(ui.pane)

func _save() -> void:
	if test_mode or save_locked or experiment == null: return
	var result := CBSaves.write(SAVE_PATH, experiment.export_document())
	if result.ok: dirty = false
	elif ui != null: ui.toast(result.message)

func restore(value: Variant) -> Dictionary:
	var result := CBLabExperiment.from_document(value)
	if result.ok:
		experiment = result.experiment
		dirty = true
		_redraw()
		ui.show_panel("Compare" if experiment.restore_hour > 0 else "Design")
	return result

func _export(kind: String, draft_text: String = "") -> void:
	if kind == "schema":
		_export_bytes(FileAccess.get_file_as_bytes("res://schemas/lab-pack.schema.json"), "community-lab-schema.json", "application/json")
		return
	if kind == "prompt":
		var prompt := "Create a Courtyard Block data-only API v2 pack using this schema. Return JSON only; no scripts. Use a unique lowercase namespace and exact dependencies on the included packs. Reference existing materials or define new ones with evidence. Do not invent measured facts or sources; mark invented inputs synthetic. Every added assembly uses layers with material IDs and thickness in metres. New model algorithms, moisture, structural engineering and new social activities are not supported. Explain limitations in evidence notes.\n\nSCHEMA\n" + FileAccess.get_file_as_string("res://schemas/lab-pack.schema.json") + "\n\nCURRENT PACKS\n" + JSON.stringify(experiment.catalog.packs, "  ")
		_export_bytes(prompt.to_utf8_buffer(), "community-mod-prompt.txt", "text/plain")
		return
	var value: Dictionary = experiment.export_document()
	var member := "experiment.json"
	var filename := "warm-homes.cbexperiment.zip"
	if kind == "pack":
		var parsed := CBLabIO.parse_text(draft_text)
		if not parsed.ok:
			ui.show_error(parsed.message)
			return
		var trial_packs := experiment.catalog.packs.duplicate(true)
		trial_packs.append(parsed.value)
		var validated := CBLabCatalog.compile(trial_packs)
		if not validated.ok:
			ui.show_error(validated.message)
			return
		value = parsed.value
		member = "manifest.json"
		filename = str(value.id) + ".cbmod.zip"
	if kind == "results":
		var report := {"runtime": CBLab.RUNTIME, "pack_lock": experiment.catalog.lock(), "question": experiment.question, "design": experiment.design, "baseline": experiment.baseline, "alternative": experiment.sim.report(), "reference": experiment.reference.report()}
		_export_bytes(JSON.stringify(report, "  ", true, true).to_utf8_buffer(), "community-results.json", "application/json")
		return
	var path := "user://lab-export.zip"
	var written := CBLabIO.write_zip(path, member, value)
	if written.ok:
		_export_bytes(FileAccess.get_file_as_bytes(path), filename, "application/zip")
		DirAccess.remove_absolute(path)
	else: ui.toast(written.message)

func _export_bytes(bytes: PackedByteArray, filename: String, mime: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, filename, mime)
		ui.toast("Download ready: " + filename)
		return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.use_native_dialog = true
	dialog.current_file = filename
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: ui.toast("Unable to write file.")
		else:
			file.store_buffer(bytes)
			file.close()
			ui.toast("Exported " + filename)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func _pick_file(purpose: String) -> void:
	file_purpose = purpose
	if OS.has_feature("web"):
		browser_callback = JavaScriptBridge.create_callback(_browser_file)
		JavaScriptBridge.get_interface("window").courtyardLabImport = browser_callback
		JavaScriptBridge.eval("(function(){const i=document.createElement('input');i.type='file';i.accept='.json,.zip,.csv';i.onchange=()=>{const f=i.files[0];if(!f)return;if(f.size>8388608){window.courtyardLabImport('','');return;}const r=new FileReader();r.onload=()=>window.courtyardLabImport(f.name,String(r.result).split(',')[1]);r.readAsDataURL(f);};i.click();})()", true)
	else:
		var dialog := FileDialog.new()
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.use_native_dialog = true
		dialog.add_filter("*.csv" if purpose == "weather" else "*.json,*.zip", "Weather data" if purpose == "weather" else "Community experiment or data pack")
		dialog.file_selected.connect(func(path: String) -> void: _import_file(path); dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered_ratio(0.7)

func _browser_file(arguments: Array) -> void:
	if arguments.size() != 2 or str(arguments[0]).is_empty() or str(arguments[1]).length() > 11200000:
		ui.toast("Choose a file smaller than 8 MiB.")
		return
	var path := "user://lab-incoming." + ("zip" if str(arguments[0]).to_lower().ends_with(".zip") else "json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		ui.toast("Cannot read selected file.")
		return
	file.store_buffer(Marshalls.base64_to_raw(str(arguments[1])))
	file.close()
	_import_file(path)
	DirAccess.remove_absolute(path)

func _import_file(path: String) -> void:
	var result: Dictionary
	if file_purpose == "weather":
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > CBLabIO.MAX_BYTES:
			ui.toast("Weather file unavailable or larger than 8 MiB.")
			return
		result = CBLabIO.weather_pack(file.get_as_text(), "weather_%d" % experiment.catalog.packs.size())
		file.close()
		if result.ok:
			ui.open_draft(result.pack)
	else:
		result = CBLabIO.read(path, "manifest.json" if file_purpose == "pack" else "experiment.json")
		if result.ok:
			if file_purpose == "pack":
				ui.open_draft(result.value)
				result.message = "Review this data pack, then add it to your experiment."
			else: result = restore(result.value)
	ui.toast(str(result.get("message", "Ready.")))
	if not result.ok: ui.show_error(result.message)

func _unhandled_input(event: InputEvent) -> void:
	if camera == null: return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(35, camera.size * 0.94)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(110, camera.size * 1.06)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_distance = 0
			else:
				dragging = false
				if drag_distance < 6:
					var index := view.pick(camera, event.position)
					if index >= 0: command({"type": "select", "index": index})
	if event is InputEventMouseMotion and dragging:
		drag_distance += event.relative.length()
		var right := camera.global_basis.x
		var forward := Vector3(-right.z, 0, right.x)
		focus -= (right * event.relative.x + forward * event.relative.y) * camera.size / get_viewport().get_visible_rect().size.y
	if event is InputEventScreenTouch:
		if event.pressed: touches[event.index] = event.position
		else: touches.erase(event.index)
		touch_distance = 0
	if event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() == 2:
			var positions: Array = touches.values()
			var distance: float = positions[0].distance_to(positions[1])
			if touch_distance > 0: camera.size = clampf(camera.size * touch_distance / maxf(distance, 1), 35, 110)
			touch_distance = distance
	if event is InputEventMagnifyGesture: camera.size = clampf(camera.size / event.factor, 35, 110)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: command({"type": "pause"})
		if event.keycode == KEY_Q: yaw -= PI / 2
		if event.keycode == KEY_E: yaw += PI / 2

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		get_tree().quit()
	if what == NOTIFICATION_APPLICATION_PAUSED: _save()
