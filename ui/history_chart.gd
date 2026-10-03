class_name CBHistoryChart
extends Control

var samples: Array = []

func _draw() -> void:
	var rect := Rect2(Vector2(0, 10), size - Vector2(0, 20))
	for y in [25, 50, 75]:
		var height: float = rect.end.y - float(y) / 100.0 * rect.size.y
		draw_line(Vector2(0, height), Vector2(size.x, height), Color("#e6e2d6"), 1)
	if samples.is_empty(): return
	var count := mini(samples.size(), 72)
	var points := PackedVector2Array()
	for i in count:
		var value := float(samples[samples.size() - count + i].wellbeing)
		points.append(Vector2(float(i) / maxf(1, count - 1) * size.x, rect.end.y - value / 100.0 * rect.size.y))
	if points.size() == 1:
		points.append(Vector2(size.x, points[0].y))
	draw_polyline(points, Color("#78936b"), 2.5, true)
	draw_circle(points[-1], 4, Color("#426954"))
