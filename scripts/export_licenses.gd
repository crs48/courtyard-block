extends SceneTree
## Export the runtime's own license/copyright data alongside the distributed engine.
func _initialize() -> void:
	var text := "GODOT ENGINE\n\n" + Engine.get_license_text() + "\n\nTHIRD-PARTY COPYRIGHT NOTICES\n\n"
	for component in Engine.get_copyright_info():
		text += str(component.name) + "\n"
		for part in component.parts:
			text += "Files: " + ", ".join(part.files) + "\nCopyright: " + "; ".join(part.copyright) + "\nLicense: " + str(part.license) + "\n\n"
	text += "\nLICENSE TEXTS\n\n"
	var licenses := Engine.get_license_info()
	for name in licenses:
		text += str(name) + "\n\n" + str(licenses[name]) + "\n\n"
	var output := "res://exports/web/THIRD_PARTY_LICENSES.txt"
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write engine notices.")
		quit(1)
		return
	file.store_string(text)
	file.close()
	print("ENGINE_NOTICES_READY")
	quit()
