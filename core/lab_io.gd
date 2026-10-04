class_name CBLabIO
extends RefCounted
## Data-only exchange. ZIPs contain exactly one bounded JSON member.
const MAX_BYTES := 8 * 1024 * 1024

static func parse_text(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return CBLabCatalog.fail("Choose a file smaller than 8 MiB.")
	var depth := 0
	var quoted := false
	var escaped := false
	for c in text:
		if quoted:
			if escaped: escaped = false
			elif c == "\\": escaped = true
			elif c == '"': quoted = false
		elif c == '"': quoted = true
		elif c in ["{", "["]:
			depth += 1
			if depth > 24: return CBLabCatalog.fail("JSON nesting exceeds the limit.")
		elif c in ["}", "]"]: depth -= 1
	var parser := JSON.new()
	if parser.parse(text) != OK: return CBLabCatalog.fail("JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	if not parser.data is Dictionary: return CBLabCatalog.fail("The file must contain one JSON object.")
	return {"ok": true, "value": parser.data}

static func read(path: String, member: String = "experiment.json") -> Dictionary:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > MAX_BYTES: return CBLabCatalog.fail("File unavailable or larger than 8 MiB.")
	var bytes := source.get_buffer(source.get_length())
	source.close()
	if not path.to_lower().ends_with(".zip"): return parse_text(bytes.get_string_from_utf8())
	var issue := zip_error(bytes, member)
	if not issue.is_empty(): return CBLabCatalog.fail(issue)
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return CBLabCatalog.fail("Unable to open data archive.")
	var data := zip.read_file(member)
	zip.close()
	if data.size() > MAX_BYTES: return CBLabCatalog.fail("Expanded file exceeds the limit.")
	return parse_text(data.get_string_from_utf8())

static func zip_error(bytes: PackedByteArray, member: String) -> String:
	# Inspect declared sizes before asking ZIPReader to decompress anything.
	if bytes.size() < 98: return "Invalid ZIP archive."
	var end := bytes.size() - 22
	if bytes.decode_u32(end) != 0x06054b50: return "Use a simple data ZIP without comments or appended content."
	if bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0 or bytes.decode_u16(end + 8) != 1 or bytes.decode_u16(end + 10) != 1: return "A data archive must contain exactly one JSON file."
	var central := int(bytes.decode_u32(end + 16))
	if central < 30 or central + 46 > end or bytes.decode_u32(central) != 0x02014b50: return "Invalid ZIP directory."
	if central + int(bytes.decode_u32(end + 12)) != end: return "Invalid ZIP directory length."
	var flags := int(bytes.decode_u16(central + 8))
	if flags & ~0x0808: return "Encrypted or unsupported ZIP flags."
	if not bytes.decode_u16(central + 10) in [0, 8]: return "Unsupported ZIP compression."
	var size := int(bytes.decode_u32(central + 24))
	if size < 2 or size > MAX_BYTES or bytes.decode_u32(central + 20) > MAX_BYTES: return "Expanded JSON exceeds the limit."
	var name_size := int(bytes.decode_u16(central + 28))
	var extras := int(bytes.decode_u16(central + 30))
	var comments := int(bytes.decode_u16(central + 32))
	if central + 46 + name_size + extras + comments != end: return "Unexpected ZIP directory content."
	if bytes.slice(central + 46, central + 46 + name_size).get_string_from_utf8() != member: return "Archive must contain only " + member + ". Scripts and assets are not supported by this data importer."
	if ((bytes.decode_u32(central + 38) >> 16) & 0xF000) == 0xA000: return "Symbolic links are not allowed."
	var local := int(bytes.decode_u32(central + 42))
	if local != 0 or bytes.decode_u32(0) != 0x04034b50: return "Invalid local ZIP header."
	var local_name := int(bytes.decode_u16(26))
	var local_extra := int(bytes.decode_u16(28))
	if 30 + local_name + local_extra > central or bytes.slice(30, 30 + local_name).get_string_from_utf8() != member: return "ZIP member names disagree."
	if 30 + local_name + local_extra + int(bytes.decode_u32(central + 20)) > central: return "Invalid compressed size."
	return ""

static func write_zip(path: String, member: String, value: Dictionary) -> Dictionary:
	var bytes := JSON.stringify(value, "", true, true).to_utf8_buffer()
	if bytes.size() > MAX_BYTES: return CBLabCatalog.fail("This experiment exceeds the portable 8 MiB limit.")
	var zip := ZIPPacker.new()
	if zip.open(path) != OK: return CBLabCatalog.fail("Cannot write archive.")
	if zip.start_file(member) != OK or zip.write_file(bytes) != OK or zip.close_file() != OK:
		zip.close()
		return CBLabCatalog.fail("Cannot write data member.")
	if zip.close() != OK: return CBLabCatalog.fail("Cannot finish archive.")
	return {"ok": true, "message": "Archive ready."}

static func weather_pack(csv: String, pack_id: String) -> Dictionary:
	if not CBModLoader.valid_pack_id(pack_id): return CBLabCatalog.fail("Choose a lowercase weather pack ID.")
	if csv.to_utf8_buffer().size() > MAX_BYTES: return CBLabCatalog.fail("Weather CSV exceeds 8 MiB.")
	var lines := csv.replace("\r", "").strip_edges().split("\n")
	if lines.size() != 8761 or lines[0].strip_edges() != "hour,temperature_c,solar_w_m2,rain_mm": return CBLabCatalog.fail("CSV needs the header hour,temperature_c,solar_w_m2,rain_mm and 8,760 hourly rows (0–8759).")
	var rows: Array = []
	for i in range(1, lines.size()):
		var fields := lines[i].strip_edges().split(",")
		if fields.size() != 4 or not fields[0].is_valid_int() or int(fields[0]) != i - 1: return CBLabCatalog.fail("Weather hours must be consecutive; check row %d." % (i + 1))
		var row: Array = []
		for j in range(1, 4):
			if not fields[j].is_valid_float(): return CBLabCatalog.fail("Non-numeric weather value at row %d." % (i + 1))
			row.append(float(fields[j]))
		if not CBValidation.number(row[0]) or row[0] < -80 or row[0] > 60 or not CBValidation.number(row[1]) or row[1] < 0 or row[1] > 1400 or not CBValidation.number(row[2]) or row[2] < 0 or row[2] > 200: return CBLabCatalog.fail("Weather value outside supported range at row %d." % (i + 1))
		rows.append(row)
	var evidence_id := pack_id + ":source"
	var definition := {"id": pack_id + ":year", "name": "Imported hourly weather", "mean_c": 10, "seasonal_c": 10, "diurnal_c": 3, "rain_mm_day": 2, "cold_snap_day": 30, "cold_snap_drop_c": 0, "outage_day": 32, "outage_hours": 0, "hourly": rows, "evidence": evidence_id}
	var evidence := {"id": evidence_id, "name": "User-supplied hourly data", "status": "estimated", "source": "", "notes": "Imported CSV; provenance has not been verified. Add the source, geography, period, license and preprocessing details before sharing measured-data claims. Solar is hourly mean irradiance; rain is hourly total. Non-leap local standard time starting Jan 1 00:00.", "geography": "Unspecified", "period": "Unspecified", "license": "Unspecified; confirm redistribution rights"}
	return {"ok": true, "pack": {"api_version": 2, "model": CBLabCatalog.MODEL, "id": pack_id, "name": "Imported weather", "version": "1.0.0", "dependencies": {"core": "1.0.0"}, "content": {"evidence": [evidence], "climates": [definition]}}, "message": "Weather imported as an unverified draft. Review its evidence before sharing."}
