class_name CBDiorama
extends Node3D
## Batched presentation of state; no authoritative simulation lives in scene nodes.

var batches: Dictionary = {}
var floor_nodes: Array[Node3D] = []
var residents_mesh: MultiMeshInstance3D
var resident_heads: MultiMeshInstance3D
var displayed_positions: Array[Vector3] = []
var resident_routes: Dictionary = {}
var last_targets: Dictionary = {}
var selected_floor := -1
var selection: MeshInstance3D
var catalog: CBCatalog
var state: Dictionary
var cube := BoxMesh.new()
var cylinder := CylinderMesh.new()
var sphere := SphereMesh.new()

func _init() -> void:
	cube.size = Vector3.ONE
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 8
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4

func rebuild(data: Dictionary, content: CBCatalog, stress_count: int = 0) -> void:
	state = data
	catalog = content
	for child in get_children():
		remove_child(child)
		child.queue_free()
	batches.clear()
	floor_nodes.clear()
	displayed_positions.clear()
	resident_routes.clear()
	last_targets.clear()
	var width: float = state.layout.width
	var half := width / 2.0
	_box(Vector3(0, -0.7, 0), Vector3(width + 16, 1, width + 16), "#d2cec0", -2)
	_box(Vector3(0, -0.15, 0), Vector3(width + 5, 0.35, width + 5), "#ece5d5", -2)
	# A quiet street frame, warm paving, and tiny lane markings.
	for sign_value in [-1, 1]:
		_box(Vector3(sign_value * (half + 5.1), -0.12, 0), Vector3(4, 0.15, width + 15), "#a9b0a8", -2)
		_box(Vector3(0, -0.12, sign_value * (half + 5.1)), Vector3(width + 15, 0.15, 4), "#a9b0a8", -2)
		for mark in range(-int(half), int(half), 4):
			_box(Vector3(sign_value * (half + 5.1), -0.02, mark), Vector3(0.13, 0.05, 1.8), "#e7e3d5", -2)
			_box(Vector3(mark, -0.02, sign_value * (half + 5.1)), Vector3(1.8, 0.05, 0.13), "#e7e3d5", -2)
	if catalog.visuals.has(state.parameters.template):
		_custom_building()
	elif state.layout.kind == "courtyard":
		_courtyard_building()
	else:
		_village()
	_garden(float(state.layout.courtyard))
	for space in state.layout.spaces:
		if space.kind == "home":
			for furniture in space.furniture:
				_furniture(space, furniture)
	for i in stress_count:
		var level := i % int(state.layout.floors)
		var side := i % 4
		var radius := half - 2.0
		var offset := float((i / 4) % 24) / 24.0 * width - half
		var p := Vector3(offset, level * 3.2 + 0.5, radius) if side % 2 == 0 else Vector3(radius, level * 3.2 + 0.5, offset)
		if side >= 2:
			p.x = -p.x
			p.z = -p.z
		_box(p, Vector3(0.3, 0.7, 0.3), "#bca889", level)
	_flush()
	_create_residents()
	selection = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.6
	ring.outer_radius = 0.78
	ring.rings = 24
	ring.ring_segments = 8
	selection.mesh = ring
	selection.material_override = _material(Color("#ebc17c"))
	selection.visible = false
	add_child(selection)
	set_floor(selected_floor)

func _custom_building() -> void:
	var primitives: Variant = catalog.visuals[state.parameters.template].call(state.layout.duplicate(true), state.parameters.duplicate(true))
	if not primitives is Array: return
	for primitive in primitives.slice(0, 100000):
		if not CBValidation.fields(primitive, {"position": "array", "size": "array", "color": "string", "floor": "number", "shape": "string"}): continue
		if not CBValidation.vector(primitive.position, 3) or not CBValidation.vector(primitive.size, 3): continue
		_shape(CBSpatial.vector(primitive.position), CBSpatial.vector(primitive.size), primitive.color, int(primitive.floor), primitive.shape, bool(primitive.get("wall", false)))

func _courtyard_building() -> void:
	var width: float = state.layout.width
	var court: float = state.layout.courtyard
	var h := width / 2.0
	var c := court / 2.0
	var depth := (width - court) / 2.0
	var wall_color := str(catalog.get_definition("materials", state.parameters.material).get("color", "#d3a082"))
	for level in int(state.layout.floors):
		var y := level * 3.2
		for side in 4:
			var along_x := side % 2 == 0
			var sign_value := -1 if side in [0, 3] else 1
			var radius := (h + c) / 2.0
			var center := Vector3(0, y, radius * sign_value) if along_x else Vector3(radius * sign_value, y, 0)
			var dimensions := Vector3(width, 0.26, depth) if along_x else Vector3(depth, 0.26, court)
			_box(center, dimensions, "#e8dbc4", level)
			for inner in [false, true]:
				var boundary: float = (c if inner else h) * sign_value
				var length := court if inner else width
				var color_value := "#dec8a8" if inner else wall_color
				var base := Vector3(0, y + 0.5, boundary) if along_x else Vector3(boundary, y + 0.5, 0)
				_box(base, Vector3(length, 0.85, 0.28) if along_x else Vector3(0.28, 0.85, length), color_value, level, true)
				base.y = y + 2.95
				_box(base, Vector3(length + 0.3, 0.35, 0.5) if along_x else Vector3(0.5, 0.35, length + 0.3), "#e9d7bd", level, true)
				var count := maxi(3, int(length / 3.2))
				for j in count:
					var offset := -length / 2.0 + (j + 0.5) * length / count
					var window := Vector3(offset, y + 1.8, boundary) if along_x else Vector3(boundary, y + 1.8, offset)
					_box(window, Vector3(1.95, 1.85, 0.14) if along_x else Vector3(0.14, 1.85, 1.95), "#647e79" if level > 0 else "#4b6660", level, true)
					var pier := window
					if along_x: pier.x += length / count / 2.0
					else: pier.z += length / count / 2.0
					_box(pier, Vector3(0.65, 2.5, 0.38) if along_x else Vector3(0.38, 2.5, 0.65), color_value, level, true)
					_box(window, Vector3(0.09, 1.9, 0.19) if along_x else Vector3(0.19, 1.9, 0.09), "#eadbc4", level, true)
					if level > 0 and not inner:
						var balcony := window
						balcony.y = y + 0.2
						if along_x: balcony.z += sign_value * 0.6
						else: balcony.x += sign_value * 0.6
						_box(balcony, Vector3(2.1, 0.18, 1.25) if along_x else Vector3(1.25, 0.18, 2.1), "#d7c5ab", level, true)
						balcony.y += 0.5
						if along_x: balcony.z += sign_value * 0.5
						else: balcony.x += sign_value * 0.5
						_box(balcony, Vector3(2.1, 0.8, 0.1) if along_x else Vector3(0.1, 0.8, 2.1), "#8b9987", level, true)
		# Partitions are low enough to make the active floor easy to read.
		for space in state.layout.spaces:
			if int(space.floor) != level or not space.kind in ["home", "shop"]:
				continue
			var p := CBSpatial.vector(space.position)
			var size := Vector2(float(space.size[0]), float(space.size[1]))
			_box(p + Vector3(size.x / 2, 0.4, 0), Vector3(0.13, 0.8, size.y), "#eee2ce", level)
			_box(p + Vector3(0, 0.02, 0), Vector3(size.x - 0.3, 0.08, size.y - 0.3), "#d5bb94" if int(space.node) % 2 else "#e0cbb0", level)
	for shop in state.shops:
		if shop.business.is_empty(): continue
		var space: Dictionary = _space(shop.space)
		var p := CBSpatial.vector(space.position)
		var side := int(space.get("side", 2))
		var outward := Vector3(0, 0, -1) if side == 0 else (Vector3.RIGHT if side == 1 else (Vector3.BACK if side == 2 else Vector3.LEFT))
		var color_value := str(catalog.get_definition("businesses", shop.business).get("color", "#6c8a71"))
		var front := p + outward * ((width - court) / 4.0 + 0.6)
		_box(front + Vector3(0, 2.65, 0), Vector3(4.7, 0.2, 1.4) if side % 2 == 0 else Vector3(1.4, 0.2, 4.7), color_value, 0)
		for k in 3:
			var table := front + outward * 2.0 + (Vector3.RIGHT if side % 2 == 0 else Vector3.BACK) * (k - 1) * 1.8
			_shape(table + Vector3(0, 0.6, 0), Vector3(0.9, 0.12, 0.9), "#d2af78", 0, "cylinder")
			_box(table + Vector3(0, 0.3, 0), Vector3(0.12, 0.6, 0.12), "#697768", 0)

func _village() -> void:
	for space in state.layout.spaces:
		if not space.kind in ["home", "shop"]: continue
		var p := CBSpatial.vector(space.position)
		_box(p, Vector3(5.8, 0.25, 5.8), "#ded0b8", 0)
		for side in [-1, 1]:
			_box(p + Vector3(side * 2.7, 1.4, 0), Vector3(0.2, 2.8, 5.5), "#d4b38f", 0, true)
			_box(p + Vector3(0, 1.4, side * 2.7), Vector3(5.5, 2.8, 0.2), "#dfc8aa", 0, true)
		_box(p + Vector3(0, 2.95, 0), Vector3(6.1, 0.35, 6.1), "#859a7d", 0, true)
		_box(p + Vector3(0, 1.6, 2.82), Vector3(2.4, 1.4, 0.1), "#668880", 0, true)
		_tree(p + Vector3(-3.3, 0, -3.2), 2.2)

func _garden(court: float) -> void:
	_box(Vector3(0, 0.02, 0), Vector3(court - 0.5, 0.15, court - 0.5), "#a8b88a", -2)
	_box(Vector3(0, 0.12, 0), Vector3(2.1, 0.05, court), "#e5d6b8", -2)
	_box(Vector3(0, 0.12, 0), Vector3(court, 0.05, 2.1), "#e5d6b8", -2)
	_shape(Vector3(0, 0.2, 0), Vector3(3.1, 0.4, 3.1), "#ddd2ba", -2, "cylinder")
	_shape(Vector3(0, 0.44, 0), Vector3(2.7, 0.12, 2.7), "#94b4b3", -2, "cylinder")
	for side in [-1, 1]:
		for other in [-1, 1]:
			_tree(Vector3(side * court * 0.28, 0, other * court * 0.28), 3.7)
			var bed := Vector3(side * court * 0.25, 0.3, other * 1.8)
			_box(bed, Vector3(3, 0.55, 1.2), "#b99e76", -2)
			for flower in 6:
				_shape(bed + Vector3(-1.2 + flower * 0.45, 0.5, 0), Vector3(0.6, 0.7, 0.6), "#839b64", -2, "sphere")
		var bench := Vector3(side * 2.5, 0.5, 2.5)
		_box(bench, Vector3(2.1, 0.18, 0.7), "#b79161", -2)
		_box(bench + Vector3(0, 0.4, 0.3), Vector3(2.1, 0.6, 0.12), "#b79161", -2)
	for i in 7:
		_tree(Vector3(-state.layout.width / 2.0 - 1.8, 0, -state.layout.width / 2.0 + i * state.layout.width / 6.0), 3.0)

func _tree(p: Vector3, height: float) -> void:
	_box(p + Vector3(0, height / 2.0, 0), Vector3(0.28, height, 0.28), "#997858", -2)
	_shape(p + Vector3(0, height, 0), Vector3(height * 0.85, height * 0.8, height * 0.85), "#7f9b6f", -2, "sphere")
	_shape(p + Vector3(0.4, height + 0.7, 0.2), Vector3(height * 0.65, height * 0.6, height * 0.65), "#94ab78", -2, "sphere")

func _furniture(space: Dictionary, furniture: Dictionary) -> void:
	var item := catalog.get_definition("furniture", str(furniture.id))
	var p := CBSpatial.vector(space.position) + Vector3(float(furniture.x), 0.25, float(furniture.z))
	var level := int(space.floor)
	var color_value := str(item.get("color", "#c9bba6"))
	match item.get("shape", "table"):
		"bed":
			_box(p + Vector3(0, 0.25, 0), Vector3(1.5, 0.45, 2.2), "#b59770", level)
			_box(p + Vector3(0, 0.55, 0.1), Vector3(1.45, 0.25, 1.9), color_value, level)
			_box(p + Vector3(0, 0.75, -0.65), Vector3(1.1, 0.18, 0.4), "#faf1dc", level)
		"sofa":
			_box(p + Vector3(0, 0.35, 0), Vector3(1.7, 0.55, 0.85), color_value, level)
			_box(p + Vector3(0, 0.7, -0.35), Vector3(1.7, 0.7, 0.18), color_value, level)
		"plant":
			_shape(p + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), "#c79775", level, "cylinder")
			_shape(p + Vector3(0, 0.8, 0), Vector3(0.9, 1, 0.9), color_value, level, "sphere")
		"shelf":
			_box(p + Vector3(0, 0.9, 0), Vector3(1.2, 1.8, 0.4), color_value, level)
			for i in 3:
				_box(p + Vector3(0, 0.4 + i * 0.5, 0.23), Vector3(1, 0.3, 0.12), "#81948a", level)
		_:
			_box(p + Vector3(0, 0.7, 0), Vector3(1.4, 0.12, 0.9), color_value, level)
			for side in [-1, 1]:
				_box(p + Vector3(side * 0.55, 0.35, 0), Vector3(0.12, 0.7, 0.6), "#ad8c63", level)

func _space(id: String) -> Dictionary:
	for space in state.layout.spaces:
		if space.id == id: return space
	return {}

func _box(p: Vector3, size: Vector3, color_value: String, level: int, wall: bool = false) -> void:
	_shape(p, size, color_value, level, "box", wall)

func _shape(p: Vector3, size: Vector3, color_value: String, level: int, shape: String, wall: bool = false) -> void:
	var key := "%s/%s/%s/%s" % [level, color_value, shape, wall]
	if not batches.has(key):
		batches[key] = {"transforms": [], "color": color_value, "level": level, "shape": shape, "wall": wall}
	batches[key].transforms.append(Transform3D(Basis.from_scale(size), p))

func _material(color_value: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = 0.88
	return material

func _flush() -> void:
	for key in batches:
		var batch: Dictionary = batches[key]
		var instance := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = cube if batch.shape == "box" else (cylinder if batch.shape == "cylinder" else sphere)
		multi.instance_count = batch.transforms.size()
		for i in batch.transforms.size():
			multi.set_instance_transform(i, batch.transforms[i])
		instance.multimesh = multi
		instance.material_override = _material(Color(batch.color))
		instance.set_meta("level", batch.level)
		instance.set_meta("wall", batch.wall)
		add_child(instance)
		floor_nodes.append(instance)
	batches.clear()

func _create_residents() -> void:
	for is_head in [false, true]:
		var instance := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = sphere if is_head else cylinder
		multi.instance_count = state.residents.size()
		instance.multimesh = multi
		var material := _material(Color.WHITE)
		material.vertex_color_use_as_albedo = true
		instance.material_override = material
		add_child(instance)
		if is_head: resident_heads = instance
		else: residents_mesh = instance
	for i in state.residents.size():
		displayed_positions.append(CBSpatial.vector(state.residents[i].position))
		residents_mesh.multimesh.set_instance_color(i, [Color("#b67b60"), Color("#6b8990"), Color("#b8a46b"), Color("#837b99")][i % 4])
		resident_heads.multimesh.set_instance_color(i, [Color("#dbb18d"), Color("#bd8867"), Color("#936448")][i % 3])

func update_people(delta: float) -> void:
	for i in state.residents.size():
		var person: Dictionary = state.residents[i]
		var target := CBSpatial.vector(person.position)
		if last_targets.get(person.id, -1) != int(person.target):
			last_targets[person.id] = int(person.target)
			resident_routes[person.id] = person.path.duplicate()
		var path: Array = resident_routes.get(person.id, [])
		if not path.is_empty():
			target = CBSpatial.vector(path[0])
			if displayed_positions[i].distance_to(target) < 0.3:
				path.pop_front()
		displayed_positions[i] = displayed_positions[i].move_toward(target, delta * 8.0)
		var p := displayed_positions[i]
		var visible_person := selected_floor < 0 or p.y < selected_floor * 3.2 + 2.5
		var body_size := Vector3(0.43, 0.75, 0.43) if visible_person else Vector3.ZERO
		var head_size := Vector3(0.42, 0.42, 0.42) if visible_person else Vector3.ZERO
		residents_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(body_size), p + Vector3(0, 0.65, 0)))
		resident_heads.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(head_size), p + Vector3(0, 1.2, 0)))

func set_floor(level: int) -> void:
	selected_floor = level
	for node in floor_nodes:
		var floor_value := int(node.get_meta("level", -2))
		node.visible = level < 0 or floor_value < level or (floor_value == level and not node.get_meta("wall", false))

func highlight(space: Dictionary) -> void:
	selection.visible = not space.is_empty()
	if selection.visible:
		selection.position = CBSpatial.vector(space.position) + Vector3(0, 0.3, 0)
		selection.scale = Vector3(3, 0.2, 3)
