extends RefCounted

func register(catalog: CBCatalog) -> void:
	catalog.register_generator("garden_village:cluster", generate)

func generate(parameters: Dictionary) -> Dictionary:
	var layout: Dictionary = {"points": [{"id": 0, "position": [0, 0, 0]}], "edges": [], "spaces": [{"id": "courtyard", "name": "The common green", "kind": "garden", "floor": 0, "node": 0, "position": [0, 0, 0], "size": [14, 14], "capacity": 150, "furniture": []}], "floors": 2, "width": 62.0, "courtyard": 14.0, "kind": "village"}
	var count := maxi(16, ceili(float(parameters.get("population", 64)) / 2.0))
	layout.width = maxf(62.0, (15.0 + floorf((count + 3) / 16.0) * 8.5) * 2.0 + 14.0)
	for i in count + 4:
		var angle := TAU * (i % 16) / 16.0 + (i / 16) * 0.09
		var radius := 15.0 + (i / 16) * 8.5
		var position: Array = [cos(angle) * radius, 0, sin(angle) * radius]
		var id: int = layout.points.size()
		layout.points.append({"id": id, "position": position})
		layout.edges.append([0, id])
		var home := i < count
		layout.spaces.append({"id": ("home_0_" if home else "shop_0_") + str(i if home else i - count), "name": ("Cottage " if home else "Village shop ") + str(i + 1), "kind": "home" if home else "shop", "floor": 0, "node": id, "position": position, "size": [5.4, 5.4], "capacity": 4 if home else 12, "furniture": []})
	var gate: int = layout.points.size()
	layout.points.append({"id": gate, "position": [0, 0, 34]})
	layout.edges.append([0, gate])
	layout.spaces.append({"id": "city", "name": "The wider region", "kind": "external", "floor": 0, "node": gate, "position": [0, 0, 34], "size": [3, 3], "capacity": 10000, "furniture": []})
	return layout
