class_name CBLivingView
extends CBLabView
## Room geometry is rendered directly from the same grid used by the thermal model.
var room_meshes: Array = []
var ghost: Node3D
var construction_label: Label3D

func draw_lab(model: CBLab) -> void:
	lab = model
	for child in get_children():
		remove_child(child)
		child.queue_free()
	batches.clear()
	floor_nodes.clear()
	room_meshes.clear()
	envelopes.clear()
	captions.clear()
	ghost = null
	var living := model as CBLivingModel
	var arid: bool = lab.climate.mean_c > 18
	_box(Vector3(0, -0.7, 0), Vector3(66, 1.4, 66), "#b4b29a" if arid else "#afb89b", -1)
	_box(Vector3(0, 0.02, 0), Vector3(64, 0.12, 64), "#ddd0ad" if arid else "#c4cead", -1)
	for i in living.plans.size():
		var plan: Dictionary = living.plans[i]
		var z: Dictionary = living.zones[i]
		for r_index in plan.rooms.size():
			var r: Array = plan.rooms[r_index]
			var p := Vector3(float(plan.x + r[0]) + float(r[2]) / 2, 0, float(plan.z + r[1]) + float(r[3]) / 2)
			var width := float(r[2])
			var depth := float(r[3])
			_box(p + Vector3(0, 0.17, 0), Vector3(width, 0.3, depth), "#b0a188", 0)
			var floor_mesh := MeshInstance3D.new()
			floor_mesh.mesh = cube
			floor_mesh.position = p + Vector3(0, 0.36, 0)
			floor_mesh.scale = Vector3(width - 0.15, 0.12, depth - 0.15)
			floor_mesh.material_override = _material(Color(z.wall.color))
			add_child(floor_mesh)
			room_meshes.append({"home": i, "mesh": floor_mesh})
			for side in [-1, 1]:
				_box(p + Vector3(side * (width - 0.15) / 2, 0.8, 0), Vector3(0.18, 1.0, depth), "#eee3c7", 0)
				_box(p + Vector3(0, 0.8, side * (depth - 0.15) / 2), Vector3(width, 1.0, 0.18), "#eee3c7", 0)
			# Room interiors explain the cutaway scale, without invented furniture benefits.
			if r_index == 1:
				_box(p + Vector3(0, 0.7, 0), Vector3(1.8, 0.55, 2.1), "#8b9d93", 0)
				_box(p + Vector3(0, 1.0, -0.65), Vector3(1.6, 0.15, 0.55), "#f2ecd8", 0)
			elif r_index == 2:
				_box(p + Vector3(0, 0.55, 0), Vector3(1, 0.32, 1.6), "#eeeede", 0)
			else:
				_box(p + Vector3(0, 0.9, 0), Vector3(1.5, 0.15, 1), "#aa8760", 0)
				for side in [-1, 1]: _box(p + Vector3(0, 0.66, side), Vector3(1.4, 0.45, 0.48), "#8d9d7d", 0)
			if r_index == 0 and lab.design.solar_kw > 0:
				_box(p + Vector3(width * 0.3, 1.45, -depth * 0.28), Vector3(1.1, 0.12, 1.6), "#466879", 0)
		var center := CBSpatial.vector(z.position)
		var entry := Vector3(float(plan.x) + 3, 0.12, float(plan.z) + 8.8)
		_box(Vector3(entry.x / 2, 0.12, entry.z), Vector3(absf(entry.x) + 1, 0.08, 1), "#e4dcc5", -1)
		for person in 2:
			var spot := entry + Vector3(person * 0.65, 0, 0.8)
			_shape(spot + Vector3(0, 0.5, 0), Vector3(0.38, 0.75, 0.38), "#b88b6b" if person == 0 else "#648981", 0, "cylinder")
			_shape(spot + Vector3(0, 0.98, 0), Vector3(0.4, 0.4, 0.4), "#c99b76", 0, "sphere")
		var caption := Label3D.new()
		caption.font_size = 36
		caption.pixel_size = 0.029
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.no_depth_test = true
		caption.outline_size = 8
		caption.outline_modulate = Color("#f7f2e4")
		caption.position = center + Vector3(0, 3.2, 0)
		add_child(caption)
		captions.append(caption)
	_box(Vector3(0, 0.14, 0), Vector3(8, 0.16, 8), "#b6bea8", -1)
	_box(Vector3(-1.5, 1, 0), Vector3(2, 1.8, 2.4), "#7d9690", 0)
	_shape(Vector3(1.5, 1.2, 0), Vector3(1.5, 2.4, 1.5), "#91afb1", 0, "cylinder")
	for bin_index in mini(8, ceili(lab.design.waste_kg / 20)):
		_box(Vector3(-2.5 + (bin_index % 4) * 0.8, 0.6, 2.5 + (bin_index / 4) * 0.9), Vector3(0.6, 1, 0.7), "#6a8074", 0)
	for i in 22:
		var angle := i * TAU / 22
		var radius := 27 + CBWorldSeed.sample(int(lab.design.seed), "tree%d" % i, 3)
		var p := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		if arid and i % 3 != 0: continue
		_shape(p + Vector3(0, 1.4, 0), Vector3(0.35, 2.8, 0.35), "#8c795d", 0, "cylinder")
		_shape(p + Vector3(0, 3, 0), Vector3(2.8, 3, 2.8), "#a2ab7b" if arid else "#7d9a72", 0, "sphere")
	_flush()
	selection = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	selection.mesh = ring
	selection.material_override = _material(Color("#e5b566"))
	add_child(selection)
	construction_label = Label3D.new()
	construction_label.font_size = 32
	construction_label.pixel_size = 0.035
	construction_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	construction_label.no_depth_test = true
	construction_label.outline_size = 8
	construction_label.outline_modulate = Color("#f7f2e4")
	construction_label.modulate = Color("#94612d")
	add_child(construction_label)
	refresh()

func refresh() -> void:
	if lab == null or selection == null: return
	selected = clampi(selected, 0, lab.zones.size() - 1)
	for entry in room_meshes:
		var home: Dictionary = lab.state.homes[entry.home]
		var z: Dictionary = lab.zones[entry.home]
		var color_value := Color(z.wall.color)
		if lens == "temperature": color_value = Color("#7ba6b5") if home.air_c < 18 else (Color("#d48661") if home.air_c > 28 else Color("#c7ba8b"))
		elif lens == "owners": color_value = Color(OWNER_COLORS[z.owner])
		entry.mesh.material_override.albedo_color = color_value
	for i in captions.size():
		captions[i].text = "%02d · %.1f°" % [i + 1, lab.state.homes[i].air_c] if lens == "temperature" else "%02d" % (i + 1)
		captions[i].modulate = Color("#a0683b") if i == selected else Color("#3a5548")
	selection.position = CBSpatial.vector(lab.zones[selected].position) + Vector3(0, 0.32, 0)
	selection.scale = Vector3(float(lab.zones[selected].width) * 0.8, 0.12, float(lab.zones[selected].depth) * 0.8)

func show_work(world: CBLivingWorld) -> void:
	construction_label.visible = not world.pending.is_empty()
	if world.pending.is_empty(): return
	var index := int(world.pending.command.home)
	construction_label.position = (CBSpatial.vector(lab.zones[index].position) if index >= 0 else Vector3.ZERO) + Vector3(0, 5.5, 0)
	construction_label.text = "BUILDING · %dh" % maxi(0, int(world.pending.due) - int(lab.state.hour))

func show_preview(plans: Array, home: int, valid: bool) -> void:
	if ghost != null:
		remove_child(ghost)
		ghost.queue_free()
	ghost = null
	if home < 0 or home >= plans.size(): return
	ghost = Node3D.new()
	add_child(ghost)
	var plan: Dictionary = plans[home]
	for room in plan.rooms:
		var mesh := MeshInstance3D.new()
		mesh.mesh = cube
		mesh.position = Vector3(float(plan.x + room[0]) + float(room[2]) / 2, 1.5, float(plan.z + room[1]) + float(room[3]) / 2)
		mesh.scale = Vector3(room[2], 2.8, room[3])
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.35, 0.75, 0.65, 0.35) if valid else Color(0.9, 0.35, 0.25, 0.35)
		mesh.material_override = material
		ghost.add_child(mesh)

func pick(camera: Camera3D, screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var point: Variant = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	if point != null:
		var cell := Vector2i(floori(point.x), floori(point.z))
		var living := lab as CBLivingModel
		for i in living.plans.size():
			if CBLivingModel.cells(living.plans[i]).has(cell): return i
	return super.pick(camera, screen)
