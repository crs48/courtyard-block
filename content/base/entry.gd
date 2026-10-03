extends RefCounted

func register(catalog: CBCatalog) -> void:
	catalog.register_generator("base:courtyard", generate)

func generate(parameters: Dictionary) -> Dictionary:
	var floors := clampi(int(parameters.get("floors", 6)), 5, 7)
	var width := clampf(float(parameters.get("width", 36.0)), 28.0, 48.0)
	var court := clampf(float(parameters.get("courtyard", 16.0)), 10.0, width - 16.0)
	var result: Dictionary = {"points": [], "edges": [], "spaces": [], "floors": floors, "width": width, "courtyard": court, "kind": "courtyard"}
	_add_point(result, [0.0, 0.0, 0.0])
	result.spaces.append({"id": "courtyard", "kind": "garden", "name": "The courtyard", "floor": 0, "node": 0, "position": [0, 0, 0], "size": [court, court], "capacity": 150, "furniture": []})
	var ring := court / 2.0 + 1.6
	for level in floors:
		var y := level * 3.2
		var corners: Array[int] = []
		for corner in [[-ring, -ring], [ring, -ring], [ring, ring], [-ring, ring]]:
			corners.append(_add_point(result, [corner[0], y, corner[1]]))
		for index in 4:
			result.edges.append([corners[index], corners[(index + 1) % 4]])
			if level > 0:
				result.edges.append([corners[index], corners[index] - 12])
			else:
				result.edges.append([0, corners[index]])
		var radius := (width + court) / 4.0
		var along := width / 4.0
		var depth := (width - court) / 2.0 - 0.6
		for side in 4:
			for slot in 2:
				var offset := (-1.0 if slot == 0 else 1.0) * along * 0.52
				var x := offset if side % 2 == 0 else (-radius if side == 3 else radius)
				var z := offset if side % 2 == 1 else (-radius if side == 0 else radius)
				var point := _add_point(result, [x, y, z])
				var nearest := corners[0]
				var distance := INF
				for candidate in corners:
					var candidate_distance := CBSpatial.vector(result.points[candidate].position).distance_to(Vector3(x, y, z))
					if candidate_distance < distance:
						nearest = candidate
						distance = candidate_distance
				result.edges.append([point, nearest])
				var size: Array = [along - 0.8, depth] if side % 2 == 0 else [depth, along - 0.8]
				var kind := "home" if level > 0 else "shop"
				result.spaces.append({"id": "%s_%s_%s" % [kind, level, side * 2 + slot], "name": "Apartment %s%02d" % [level, side * 2 + slot + 1] if level > 0 else "Shop %s" % (side * 2 + slot + 1), "kind": kind, "floor": level, "node": point, "position": [x, y, z], "size": size, "capacity": 4 if level > 0 else 12, "furniture": [], "side": side})
	var gate := _add_point(result, [0.0, 0.0, width / 2.0 + 6.0])
	result.edges.append([gate, 3])
	result.spaces.append({"id": "city", "name": "The wider city", "kind": "external", "floor": 0, "node": gate, "position": [0, 0, width / 2.0 + 6.0], "size": [3, 3], "capacity": 10000, "furniture": []})
	return result

func _add_point(layout: Dictionary, position: Array) -> int:
	var id: int = layout.points.size()
	layout.points.append({"id": id, "position": position})
	return id
