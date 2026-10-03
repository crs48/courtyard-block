class_name CBModLoader
extends RefCounted

const BUNDLED := ["res://content/base", "res://mods/soft_spaces", "res://mods/community_kitchen", "res://mods/garden_village"]
const INSTALL_ROOT := "user://mods"
const MAX_ARCHIVE_BYTES := 64 * 1024 * 1024
const MAX_EXPANDED_BYTES := 128 * 1024 * 1024

static func create_catalog(include_installed: bool = true) -> CBCatalog:
	var roots: Array = BUNDLED.duplicate()
	if include_installed and DirAccess.dir_exists_absolute(INSTALL_ROOT):
		for directory in DirAccess.get_directories_at(INSTALL_ROOT):
			if not directory.begins_with("."):
				roots.append(INSTALL_ROOT.path_join(directory))
	return load_roots(roots)

static func load_roots(roots: Array) -> CBCatalog:
	var catalog := CBCatalog.new()
	var pending: Dictionary = {}
	for root_value in roots:
		var root := str(root_value)
		var manifest_path := root.path_join("manifest.json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not parsed is Dictionary:
			catalog.errors.append("Invalid manifest: " + root)
			continue
		var manifest: Dictionary = parsed
		var id := str(manifest.get("id", ""))
		if not valid_pack_id(id) or pending.has(id):
			catalog.errors.append("Invalid or duplicate pack ID: " + id)
			continue
		if int(manifest.get("api_version", 0)) != CBCatalog.API_VERSION:
			catalog.errors.append("Unsupported API version: " + id)
			continue
		manifest["root"] = root
		pending[id] = manifest
	while not pending.is_empty():
		var progress := false
		var ids: Array = pending.keys()
		ids.sort()
		for id in ids:
			var manifest: Dictionary = pending[id]
			var ready := true
			for dependency in manifest.get("dependencies", {}):
				if not catalog.packs.has(dependency) or catalog.packs[dependency].version != manifest.dependencies[dependency]:
					ready = false
			if not ready:
				continue
			_register(catalog, manifest)
			pending.erase(id)
			progress = true
		if not progress:
			catalog.errors.append("Missing, incompatible, or cyclic dependencies: " + ", ".join(pending.keys()))
			break
	return catalog

static func _register(catalog: CBCatalog, manifest: Dictionary) -> void:
	var prior_errors := catalog.errors.size()
	var pack_prefix := str(manifest.id) + ":"
	for kind in manifest.get("content", {}):
		for definition in manifest.content[kind]:
			if not definition is Dictionary or not str(definition.get("id", "")).begins_with(pack_prefix):
				catalog.errors.append("Definition is outside pack pack_prefix: " + str(manifest.id))
				continue
			catalog.register_content(str(kind), definition)
	var entry := str(manifest.get("entry", ""))
	var digest_text := FileAccess.get_file_as_string(str(manifest.root).path_join("manifest.json"))
	if not entry.is_empty():
		if not safe_relative(entry) or not entry.ends_with(".gd"):
			catalog.errors.append("Invalid script entry: " + entry)
			return
		var path := str(manifest.root).path_join(entry)
		digest_text += FileAccess.get_file_as_string(path)
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			catalog.errors.append("Cannot load script: " + path)
			return
		var extension: RefCounted = script.new()
		if not extension.has_method("register"):
			catalog.errors.append("Script must define register(catalog): " + entry)
			return
		extension.call("register", catalog)
		manifest["instance"] = extension # Retain callback owner for the catalogue lifetime.
	if catalog.errors.size() == prior_errors:
		manifest["digest"] = digest_text.sha256_text()
		catalog.packs[manifest.id] = manifest

static func valid_pack_id(id: String) -> bool:
	if id.is_empty() or id.length() > 64:
		return false
	for character in id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_-":
			return false
	return true

static func safe_relative(path: String) -> bool:
	return not path.is_empty() and not path.is_absolute_path() and not path.contains("..") and not path.contains(":") and not path.contains("\\")

static func install_zip(path: String) -> Dictionary:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > MAX_ARCHIVE_BYTES:
		return {"ok": false, "message": "Pack missing or exceeds 64 MiB."}
	source.close()
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {"ok": false, "message": "Choose a .cbmod.zip archive."}
	var files := zip.get_files()
	if not "manifest.json" in files or files.size() > 2048:
		zip.close()
		return {"ok": false, "message": "Archive needs a root manifest.json and at most 2048 files."}
	var manifest: Variant = JSON.parse_string(zip.read_file("manifest.json").get_string_from_utf8())
	if not manifest is Dictionary or not valid_pack_id(str(manifest.get("id", ""))):
		zip.close()
		return {"ok": false, "message": "Invalid manifest or pack ID."}
	var id := str(manifest.id)
	if id in ["base", "soft_spaces", "community_kitchen", "garden_village"] or DirAccess.dir_exists_absolute(INSTALL_ROOT.path_join(id)):
		zip.close()
		return {"ok": false, "message": "Pack already exists. Remove it before installing another version."}
	var buffers: Dictionary = {}
	var total := 0
	for file in files:
		if file.ends_with("/"):
			continue
		if not safe_relative(file):
			zip.close()
			return {"ok": false, "message": "Unsafe archive path."}
		var buffer := zip.read_file(file)
		total += buffer.size()
		if total > MAX_EXPANDED_BYTES:
			zip.close()
			return {"ok": false, "message": "Expanded pack exceeds 128 MiB."}
		buffers[file] = buffer
	zip.close()
	var destination := INSTALL_ROOT.path_join(id)
	for file in buffers:
		var output := destination.path_join(file)
		if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK:
			return {"ok": false, "message": "Cannot create mod directory."}
		var handle := FileAccess.open(output, FileAccess.WRITE)
		if handle == null:
			return {"ok": false, "message": "Cannot write mod file."}
		handle.store_buffer(buffers[file])
		handle.close()
	return {"ok": true, "message": str(manifest.get("name", id)) + " installed. Restart the game to activate."}
