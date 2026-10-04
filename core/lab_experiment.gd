class_name CBLabExperiment
extends RefCounted
## Commands edit a draft; runs pin both alternatives. Restore replays trusted inputs,
## never accepting arbitrary imported temperatures, balances or claimed results.

var catalog: CBLabCatalog
var sim: CBLab
var reference: CBLab
var design: Dictionary
var baseline: Dictionary
var phase := "design"
var limit := 2160
var restore_hour := 0
var question := "Can everyone stay warm without unaffordable bills?"
var undo: Array = []
var notebook: Array = []

static func create(packs: Array, proposed: Dictionary = {}, original: Dictionary = {}) -> Dictionary:
	var compiled := CBLabCatalog.compile(packs)
	if not compiled.ok: return compiled
	var experiment := CBLabExperiment.new()
	experiment.catalog = compiled.catalog
	experiment.design = CBLab.default_design() if proposed.is_empty() else proposed.duplicate(true)
	experiment.baseline = experiment.design.duplicate(true) if original.is_empty() else original.duplicate(true)
	var result := experiment._rebuild(experiment.design, experiment.baseline, experiment.catalog)
	if not result.ok: return result
	return {"ok": true, "experiment": experiment, "message": "Experiment ready."}

func _rebuild(chosen: Dictionary, original: Dictionary, content: CBLabCatalog) -> Dictionary:
	var built := CBLab.create(content, chosen)
	if not built.ok: return built
	var ref := CBLab.create(content, original)
	if not ref.ok: return ref
	if chosen.climate != original.climate or chosen.seed != original.seed: return CBLabCatalog.fail("Alternatives must share the same weather and seed.")
	var left: Array = built.simulation.zones.map(func(z: Dictionary) -> String: return z.id)
	var right: Array = ref.simulation.zones.map(func(z: Dictionary) -> String: return z.id)
	if left != right: return CBLabCatalog.fail("This comparison needs matching home IDs. Start a separate experiment for a different population.")
	design = chosen.duplicate(true)
	baseline = original.duplicate(true)
	catalog = content
	sim = built.simulation
	reference = ref.simulation
	return {"ok": true, "message": "Design updated; no simulation time has passed."}

func edit(key: String, value: Variant) -> Dictionary:
	if phase != "design": return CBLabCatalog.fail("Choose Try another design before changing a running experiment.")
	if not design.has(key): return CBLabCatalog.fail("Unsupported design field.")
	var chosen := design.duplicate(true)
	var original := baseline.duplicate(true)
	chosen[key] = value
	if key == "layout": chosen.overrides = {}
	if key in ["climate", "seed"]: original[key] = value
	var before := {"design": design.duplicate(true), "baseline": baseline.duplicate(true)}
	var result := _rebuild(chosen, original, catalog)
	if result.ok:
		undo.append(before)
		if undo.size() > 24: undo.pop_front()
	return result

func undo_edit() -> Dictionary:
	if phase != "design" or undo.is_empty(): return CBLabCatalog.fail("No draft change to undo.")
	var last: Dictionary = undo.back()
	var result := _rebuild(last.design, last.baseline, catalog)
	if result.ok: undo.pop_back()
	return result

func install(pack: Variant) -> Dictionary:
	if phase != "design": return CBLabCatalog.fail("Return to design before adding a pack.")
	var candidates := catalog.packs.duplicate(true)
	if not pack is Dictionary: return CBLabCatalog.fail("Pack must be a JSON object.")
	if pack.get("id", "") == "core": return CBLabCatalog.fail("Create a separate namespace instead of replacing the reference kit.")
	for existing in candidates:
		if existing.id == pack.get("id", ""): return CBLabCatalog.fail("That namespace already exists in this experiment. Choose a new ID for this variation.")
	candidates.append(pack)
	var compiled := CBLabCatalog.compile(candidates)
	if not compiled.ok: return compiled
	var result := _rebuild(design, baseline, compiled.catalog)
	if result.ok: result.message = "Pack added to this experiment. Its definitions are available in Design."
	return result

func start(hours: int) -> Dictionary:
	if not hours in [168, 2160, CBLab.YEAR_HOURS]: return CBLabCatalog.fail("Choose one week, 90 days or one year.")
	if phase == "design":
		var result := _rebuild(design, baseline, catalog)
		if not result.ok: return result
	if hours <= sim.state.hour: return CBLabCatalog.fail("This period has already finished. Try another design or a longer period.")
	limit = hours
	phase = "running"
	return {"ok": true, "message": "Running both designs through the same weather."}

func tick() -> void:
	if phase != "running" and restore_hour <= 0: return
	var target := restore_hour if restore_hour > 0 else limit
	if sim.state.hour < target:
		sim.step()
		reference.step()
	if sim.state.hour >= target:
		if restore_hour > 0:
			restore_hour = 0
			phase = "complete" if sim.state.hour >= limit else "paused"
		else: phase = "complete"

func pause() -> void:
	if phase == "running": phase = "paused"
	elif phase == "paused": phase = "running"

func reset() -> Dictionary:
	if sim.state.hour > 0:
		notebook.append({"design": design.duplicate(true), "report": sim.report(), "reference": reference.report()})
		if notebook.size() > 6: notebook.pop_front()
	var result := _rebuild(design, baseline, catalog)
	if result.ok:
		phase = "design"
		restore_hour = 0
	return result

func pin_baseline() -> Dictionary:
	if phase != "design": return CBLabCatalog.fail("Return to design before replacing the reference.")
	var result := _rebuild(design, design, catalog)
	if result.ok:
		undo.clear()
		result.message = "This design is now the reference for your next changes."
	return result

func export_document() -> Dictionary:
	return {"format": "courtyard-experiment", "schema_version": 2, "runtime": CBLab.RUNTIME, "question": question, "packs": catalog.packs.duplicate(true), "pack_lock": catalog.lock(), "design": design.duplicate(true), "baseline": baseline.duplicate(true), "progress": {"hour": restore_hour if restore_hour > 0 else sim.state.hour, "limit": limit}}

static func from_document(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 9: return CBLabCatalog.fail("Invalid experiment document.")
	for key in ["format", "schema_version", "runtime", "question", "packs", "pack_lock", "design", "baseline", "progress"]:
		if not value.has(key): return CBLabCatalog.fail("Missing experiment field: " + key)
	if value.format != "courtyard-experiment" or value.schema_version != 2 or value.runtime != CBLab.RUNTIME: return CBLabCatalog.fail("This experiment needs its original model runtime: " + str(value.runtime))
	if not value.question is String or value.question.length() > 200: return CBLabCatalog.fail("Question must be at most 200 characters.")
	if not value.packs is Array or not value.design is Dictionary or not value.baseline is Dictionary: return CBLabCatalog.fail("Malformed experiment inputs.")
	var progress: Variant = value.progress
	if not progress is Dictionary or progress.size() != 2 or not progress.has("hour") or not progress.has("limit"): return CBLabCatalog.fail("Malformed progress record.")
	if not CBValidation.number(progress.hour) or not CBValidation.number(progress.limit): return CBLabCatalog.fail("Invalid progress horizon.")
	if float(progress.hour) != floorf(progress.hour) or progress.hour < 0 or float(progress.limit) != floorf(progress.limit) or not int(progress.limit) in [168, 2160, 8760] or progress.hour > progress.limit: return CBLabCatalog.fail("Invalid progress horizon.")
	var created := create(value.packs, value.design, value.baseline)
	if not created.ok: return created
	var experiment: CBLabExperiment = created.experiment
	if CBLabCatalog.canonical(value.pack_lock) != CBLabCatalog.canonical(experiment.catalog.lock()): return CBLabCatalog.fail("Pack contents do not match the experiment's hashes. The original remains unchanged.")
	experiment.question = value.question
	experiment.limit = int(progress.limit)
	experiment.restore_hour = int(progress.hour)
	experiment.phase = "paused" if progress.hour > 0 else "design"
	created.message = "Restoring the recorded hour from pinned inputs." if progress.hour > 0 else "Experiment imported."
	return created
