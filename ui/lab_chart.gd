class_name CBLabChart
extends Control

var original: Array = []
var alternative: Array = []
var metric := "cold_hours"

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var maximum := 1.0
	for series in [original, alternative]:
		for sample in series: maximum = maxf(maximum, float(sample.get(metric, 0)))
	var rect := Rect2(44, 10, maxf(10, size.x - 54), maxf(10, size.y - 36))
	for fraction in [0.0, 0.5, 1.0]:
		var y: float = rect.end.y - fraction * rect.size.y
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("#dfded1"), 1)
		draw_string(font, Vector2(0, y + 4), "%.0f" % (maximum * fraction), HORIZONTAL_ALIGNMENT_LEFT, 42, 11, Color("#718077"))
	var count := maxi(original.size(), alternative.size())
	var series_index := 0
	for series in [original, alternative]:
		var points := PackedVector2Array()
		for i in series.size():
			points.append(Vector2(rect.position.x + float(i) / maxi(1, count - 1) * rect.size.x, rect.end.y - float(series[i].get(metric, 0)) / maximum * rect.size.y))
		if points.size() > 1: draw_polyline(points, Color("#b59476") if series_index == 0 else Color("#3c7160"), 2.5, true)
		series_index += 1
	draw_string(font, Vector2(rect.position.x, size.y - 2), "Day 1", HORIZONTAL_ALIGNMENT_LEFT, 80, 11, Color("#718077"))
	draw_string(font, Vector2(rect.end.x - 70, size.y - 2), "Day %d" % maxi(1, count - 1), HORIZONTAL_ALIGNMENT_RIGHT, 70, 11, Color("#718077"))
