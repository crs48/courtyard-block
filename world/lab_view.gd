class_name CBLabView
extends CBDiorama
## The physical model supplies geometry and outcomes. This view only draws them.

var envelopes: Array[MeshInstance3D] = []
var captions: Array[Label3D] = []
var lab: CBLab
var lens := "materials"
var selected := 0
const OWNER_COLORS := {"west": "#b48368", "east": "#78978b", "commons": "#8c87a6"}

func draw_lab(model: CBLab) -> void:
	lab = model
	for child in get_children():
		remove_child(child)
		child.queue_free()
	batches.clear()
	floor_nodes.clear()
	envelopes.clear()
	captions.clear()
	_box(Vector3(0, -0.75, 0), Vector3(58, 1.4, 52), "#c4c7ae", -1)
	_box(Vector3(0, -0.03, 0), Vector3(55, 0.16, 49), "#dedbc7", -1)
	_box(Vector3(0, 0.04, 0), Vector3(12, 0.15, 22), "#a1ae82", -1)
	for i in 12:
		_box(Vector3(-2.3 + i % 3 * 2.3, 0.15, -10 + i / 3 * 5.0), Vector3(2, 0.08, 4.5), "#e4ddc5", -1)
	for i in lab.zones.size():
		var z: Dictionary = lab.zones[i]
		var p := CBSpatial.vector(z.position)
		var w: float = z.width
		var d: float = z.depth
		var height: float = lab.house.height_m
		_box(p + Vector3(0, 0.12, 0), Vector3(w + 0.55, 0.3, d + 0.55), "#b6a287", 0)
		if p.y > 0:
			_box(p + Vector3(0, -0.13, 0), Vector3(w + 1.7, 0.3, d + 1.7), "#a1805e", 0)
			for x in [-1, 1]:
				for zz in [-1, 1]:
					_shape(Vector3(p.x + x * w * 0.38, p.y / 2, p.z + zz * d * 0.38), Vector3(0.65, p.y, 0.65), "#786b51", 0, "cylinder")
			for step in 7:
				_box(Vector3(p.x, step * p.y / 7, p.z + d / 2 + (7 - step) * 0.7), Vector3(1.7, 0.25, 0.8), "#a1805e", 0)
		var envelope := MeshInstance3D.new()
		envelope.mesh = cube
		envelope.scale = Vector3(w, height, d)
		envelope.position = p + Vector3(0, height / 2 + 0.22, 0)
		envelope.material_override = _material(Color(z.wall.color))
		add_child(envelope)
		envelopes.append(envelope)
		_box(p + Vector3(0, height + 0.34, 0), Vector3(w + 0.5, 0.28, d + 0.5), "#65766c", 0)
		_box(p + Vector3(0, height + 0.53, 0), Vector3(w + 0.15, 0.12, d + 0.15), "#7e8c71", 0)
		for side in [-1, 1]:
			for x in [-1, 1]:
				_box(p + Vector3(x * w * 0.27, 1.75, side * (d / 2 + 0.025)), Vector3(w * 0.28, 1.45, 0.1), "#476467", 0)
				_box(p + Vector3(x * w * 0.27, 1.72, side * (d / 2 + 0.09)), Vector3(0.08, 1.5, 0.07), "#ded1b7", 0)
		_box(p + Vector3(0, 1.05, d / 2 + 0.06), Vector3(1.05, 1.85, 0.12), "#645a48", 0)
		_box(p + Vector3(0, 2.1, d / 2 + 0.2), Vector3(1.6, 0.16, 0.9), str(OWNER_COLORS[z.owner]), 0)
		if lab.design.solar_kw > 0:
			for panel in 2:
				_box(p + Vector3(-w * 0.23 + panel * w * 0.46, height + 0.7, -0.6), Vector3(w * 0.36, 0.12, d * 0.45), "#466879", 0)
		# Paths and utilities share endpoints, not simulation semantics.
		var entry := Vector3(p.x, 0.12, p.z + d / 2 + 1.2)
		_box(Vector3(p.x / 2, 0.1, entry.z), Vector3(absf(p.x) + 1, 0.08, 1.5), "#c6bfa6", -1)
		var caption := Label3D.new()
		caption.font_size = 36
		caption.pixel_size = 0.018
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.no_depth_test = true
		caption.outline_size = 8
		caption.outline_modulate = Color("#f7f2e4")
		caption.modulate = Color("#293e35")
		caption.position = p + Vector3(0, height + 2.7, 0)
		add_child(caption)
		captions.append(caption)
		for person in 2:
			var spot := entry + Vector3(person * 0.6 - 0.3, 0, 0.8)
			_shape(spot + Vector3(0, 0.6, 0), Vector3(0.4, 0.75, 0.4), "#bc8b67" if person == 0 else "#758d8b", 0, "cylinder")
			_shape(spot + Vector3(0, 1.1, 0), Vector3(0.42, 0.42, 0.42), "#c49a78", 0, "sphere")
	for i in 15:
		var angle := i * TAU / 15
		var p := Vector3(cos(angle) * 25, 0, sin(angle) * 22)
		_shape(p + Vector3(0, 2.0, 0), Vector3(0.4, 4.0, 0.4), "#8b795b", 0, "cylinder")
		_shape(p + Vector3(0, 4.5, 0), Vector3(3.4, 4.2, 3.4), ["#7b946d", "#91a178", "#688567"][i % 3], 0, "sphere")
	_box(Vector3(0, 1.15, 14), Vector3(4, 2.2, 3), "#869994", 0)
	for i in 3:
		_shape(Vector3(-1.25 + i * 1.25, 1.3, 15.56), Vector3(0.8, 0.8, 0.12), "#435f5c", 0, "sphere")
	_shape(Vector3(5, 1.4, 14), Vector3(2, 2.8, 2), "#97b2b5", 0, "cylinder")
	for i in 3: _box(Vector3(-5.0 - i * 0.9, 0.6, 14), Vector3(0.75, 1.2, 0.85), "#738476", 0)
	for x in [-3, 3]:
		_box(Vector3(x, 0.7, 2), Vector3(0.75, 0.22, 3), "#a88661", 0)
		_box(Vector3(x, 0.35, 2), Vector3(0.3, 0.7, 2.3), "#5f7360", 0)
	_flush()
	_label_3d("SHARED SYSTEMS", Vector3(0, 4.3, 14), Color("#426954"))
	selection = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.0
	ring.rings = 32
	selection.mesh = ring
	selection.material_override = _material(Color("#eac47f"))
	add_child(selection)
	refresh()

func refresh() -> void:
	if lab == null: return
	selected = clampi(selected, 0, lab.zones.size() - 1)
	for i in envelopes.size():
		var z: Dictionary = lab.zones[i]
		var home: Dictionary = lab.state.homes[i]
		var color_value := Color(z.wall.color)
		if lens == "temperature":
			color_value = Color("#7ba6b5") if home.air_c < 18 else (Color("#d48661") if home.air_c > 28 else Color("#c7ba8b"))
		elif lens == "owners": color_value = Color(OWNER_COLORS[z.owner])
		envelopes[i].material_override.albedo_color = color_value
		captions[i].text = "%02d · %.1f°" % [i + 1, home.air_c] if lens == "temperature" else "%02d" % (i + 1)
		captions[i].modulate = Color("#a0683b") if i == selected else Color("#3a5548")
	var p := CBSpatial.vector(lab.zones[selected].position)
	selection.position = p + Vector3(0, 0.23, 0)
	selection.scale = Vector3(float(lab.zones[selected].width) * 0.85, 0.12, float(lab.zones[selected].depth) * 0.85)

func pick(camera: Camera3D, screen: Vector2) -> int:
	var nearest := -1
	var distance := 70.0
	for i in lab.zones.size():
		var p := CBSpatial.vector(lab.zones[i].position) + Vector3(0, lab.house.height_m / 2, 0)
		var candidate := camera.unproject_position(p).distance_to(screen)
		if candidate < distance:
			distance = candidate
			nearest = i
	return nearest
