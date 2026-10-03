class_name CBSaves
extends RefCounted

const SAVE_PATH := "user://community.json"
const FORK_PATH := "user://comparison.json"

static func write(path: String, state: Dictionary) -> Dictionary:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "Storage is unavailable. Export a backup instead."}
	file.store_string(JSON.stringify(state, "", true, true))
	file.close()
	var error := DirAccess.rename_absolute(temporary, path)
	return {"ok": error == OK, "message": "Community saved." if error == OK else "Unable to replace save."}

static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "No saved community yet."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 64 * 1024 * 1024:
		return {"ok": false, "message": "Save cannot be read or exceeds 64 MiB."}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "message": "This file is not a valid community save."}
	return {"ok": true, "state": parsed}

static func fork_state(state: Dictionary, name: String) -> Dictionary:
	var fork: Dictionary = state.duplicate(true)
	fork.branch = {"parent": state.name, "origin_minute": state.minute}
	fork.name = name
	return fork

static func compare(left: Dictionary, right: Dictionary) -> Dictionary:
	var origin := maxi(int(left.branch.origin_minute), int(right.branch.origin_minute))
	var common := mini(int(left.minute), int(right.minute))
	var result: Dictionary = {"ok": false, "message": "Run both communities past the fork point."}
	if common <= origin:
		return result
	var l: Dictionary = {}
	var r: Dictionary = {}
	for sample in left.history:
		if int(sample.minute) <= common and int(sample.minute) >= origin:
			l = sample
	for sample in right.history:
		if int(sample.minute) <= common and int(sample.minute) >= origin:
			r = sample
	if l.is_empty() or r.is_empty() or int(l.minute) != int(r.minute):
		return result
	return {"ok": true, "minute": l.minute, "elapsed": int(l.minute) - origin, "left": l, "right": r}
