class_name CBSpatial
extends RefCounted

var graph := AStar3D.new()
var routes: Dictionary = {}

func rebuild(layout: Dictionary) -> void:
	graph.clear()
	routes.clear()
	for point in layout.points:
		graph.add_point(int(point.id), vector(point.position))
	for edge in layout.edges:
		graph.connect_points(int(edge[0]), int(edge[1]))

func route(from: int, to: int) -> Array:
	var key := "%s:%s" % [from, to]
	if not routes.has(key):
		var result: Array = []
		if graph.has_point(from) and graph.has_point(to):
			for point in graph.get_point_path(from, to):
				result.append([point.x, point.y, point.z])
		routes[key] = result
	return routes[key]

static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
