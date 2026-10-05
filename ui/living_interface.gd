class_name CBLivingInterface
extends CBLabInterface
var seed_draft: Dictionary = {}
var locks := {"layout": false, "climate": false, "resources": false, "people": false}
var gallery_round := 0
var root_seed_value := 2406
var draft_command: Dictionary = {}
var draft_result: Dictionary = {}

func _living() -> CBWorldExperiment:
	return game.experiment as CBWorldExperiment

func _branch() -> CBLivingWorld:
	return _living().worlds[_living().active]

func _ready() -> void:
	seed_draft = _living().layer_seeds.duplicate()
	super._ready()
	brand.text = "COURTYARD BLOCK  /  LIVING WORLDS"
	title.text = "One seed. Three futures."
	for pair in [["Design", "World"], ["People", "Build"], ["Compare", "Futures"], ["Workshop", "Workshop"]]: tabs[pair[0]].text = pair[1]
	for button in [season_button, year_button, pause_button]:
		for connection in button.pressed.get_connections(): button.pressed.disconnect(connection.callable)
	season_button.text = "+1 week"
	season_button.pressed.connect(func() -> void: action.emit({"type": "run", "hours": 168}))
	year_button.text = "+1 month"
	year_button.pressed.connect(func() -> void: action.emit({"type": "run", "hours": 720}))
	pause_button.pressed.connect(func() -> void: action.emit({"type": "pause"}))
	share.text = "Share this world"
	toast("Pick a home to build. Advance a week to hear from your neighbours.")
	refresh()
	responsive()

func _future_controls() -> void:
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 46
	selector.fit_to_longest_item = false
	for name_value in CBLivingWorld.MODES: selector.add_item(name_value)
	selector.select(_living().active)
	selector.item_selected.connect(func(index: int) -> void: action.emit({"type": "future", "index": index}))
	body.add_child(selector)
	_text(["Neighbours propose. You approve each project.", "Neighbours can build affordable projects within the delegated budget. Larger ideas come to you.", "Owners and the co-op delegate a larger project budget. Neighbours can add rooms and improve shared services."][_living().active])

func _design() -> void:
	_heading("01  BUILD TOGETHER", "A world with its own ideas")
	_future_controls()
	_text(_living().world_title, INK)
	_text("1. Tap a home and try a room addition.\n2. Run a week. Read what neighbours want to do.\n3. Switch futures to see what different freedoms change.")
	dynamic.work = _text("", GREEN)
	_proposals()
	_rule()
	_heading("START SOMEWHERE UNEXPECTED", "Explore starting worlds")
	_text("Browse seeds, then start a fresh set of three futures. Your current world is backed up before replacement.")
	var root_seed := _number("World seed", 1, 999999, root_seed_value, 1)
	_button(body, "Preview seed layers", func() -> void:
		root_seed.apply()
		root_seed_value = int(root_seed.value)
		var next := CBWorldSeed.seeds(root_seed_value)
		for layer in CBWorldSeed.LAYERS:
			if not locks[layer]: seed_draft[layer] = next[layer]
		show_panel("Design"))
	for layer in CBWorldSeed.LAYERS:
		var layer_name: String = layer
		var row := HBoxContainer.new()
		body.add_child(row)
		var lock := CheckButton.new()
		lock.text = "Lock " + layer_name
		lock.button_pressed = locks[layer_name]
		lock.custom_minimum_size.y = 44
		lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lock.toggled.connect(func(value: bool) -> void: locks[layer_name] = value)
		row.add_child(lock)
		_button(row, str(seed_draft[layer_name]) + " ↻", func() -> void:
			if locks[layer_name]: toast("Unlock this layer before rerolling it."); return
			seed_draft[layer_name] = 1 + CBWorldSeed.sample(int(seed_draft[layer_name]), "reroll", 999999)
			show_panel("Design"))
	var preview := CBWorldSeed.generate(seed_draft, _living().source_packs)
	_text("Preview: " + (str(preview.title) + " · %d homes" % preview.plans.size() if preview.ok else preview.message), INK)
	_button(body, "Start these three futures", func() -> void: action.emit({"type": "new_world", "seeds": seed_draft.duplicate()}), true)
	_rule()
	_label(body, "POSSIBLE STARTING POINTS", 11, GREEN)
	for i in 3:
		var chosen := CBWorldSeed.seeds(1 + CBWorldSeed.sample(2406 + gallery_round, "gallery%d" % i, 999999))
		for layer in CBWorldSeed.LAYERS:
			if locks[layer]: chosen[layer] = seed_draft[layer]
		var generated := CBWorldSeed.generate(chosen, _living().source_packs)
		if not generated.ok: continue
		_button(body, generated.title, func() -> void:
			seed_draft = chosen.duplicate()
			show_panel("Design"))
	_button(body, "More starting points ↻", func() -> void: gallery_round += 1; show_panel("Design"))
	_text("These are synthetic communities, with correlated climate inputs and independently rerollable layers. They are not predictions of real places.")

func _proposals() -> void:
	var world := _branch()
	_label(body, "YOUR NEIGHBOURS' IDEAS", 11, GREEN)
	if world.proposals.is_empty():
		_text("No proposals yet. Advance time so residents can notice space, comfort and service problems.")
	for proposal in world.proposals.slice(0, 8):
		var index := int(proposal.command.home)
		_label(body, proposal.actor, 17)
		_text(proposal.reason, INK)
		_text(proposal.title + " · " + euros(int(proposal.cost)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		_button(row, "Approve", func() -> void: action.emit({"type": "accept", "home": index}), true).disabled = not world.pending.is_empty()
		_button(row, "Not now", func() -> void: action.emit({"type": "dismiss", "home": index}))

func _people() -> void:
	_heading("02  MAKE ROOM FOR AN IDEA", "Build and rearrange")
	_future_controls()
	var e := _living()
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 46
	selector.fit_to_longest_item = false
	for home in e.sim.state.homes: selector.add_item(home.name + " · " + home.id)
	selector.select(game.selected)
	selector.item_selected.connect(func(index: int) -> void: action.emit({"type": "select", "index": index}))
	body.add_child(selector)
	var index := game.selected
	var z: Dictionary = e.sim.zones[index]
	var plan: Dictionary = _branch().model.plans[index]
	dynamic.home_status = _text("", INK)
	var protect := CheckButton.new()
	protect.text = "Protect from neighbour construction"
	protect.button_pressed = index in _branch().protected_homes
	protect.custom_minimum_size.y = 44
	protect.toggled.connect(func(value: bool) -> void: action.emit({"type": "build", "command": CBLivingWorld.action("protect", index, value)}))
	body.add_child(protect)
	_text("Owner: " + _owner_name(z.owner) + ". Projects use this owner's capital. Three people remain in the home; space preferences are illustrative.")
	dynamic.work = _text("", GREEN)
	if not draft_command.is_empty():
		_rule()
		_label(body, "PREVIEW · NO MONEY SPENT", 11, GREEN)
		_text(draft_result.message, INK)
		if draft_result.ok:
			_text("%s · %d hours · paid by %s" % [euros(int(draft_result.cost)), draft_result.hours, draft_result.payer])
			_button(body, "Build this idea", func() -> void: action.emit({"type": "confirm_preview"}), true)
		_button(body, "Cancel preview", func() -> void: action.emit({"type": "cancel_preview"}))
	_rule()
	_label(body, "SNAP ON AN EDITABLE ROOM", 11, GREEN)
	var side := OptionButton.new()
	for side_name in ["East edge", "South edge", "West edge", "North edge"]: side.add_item(side_name)
	side.custom_minimum_size.y = 44
	body.add_child(side)
	var width := _number("Width · m", 2, 8, 4)
	var depth := _number("Depth · m", 2, 8, 3)
	_button(body, "Preview room addition", func() -> void:
		width.apply()
		depth.apply()
		action.emit({"type": "preview", "command": CBLivingWorld.action("add", index, [side.selected, int(width.value), int(depth.value)])}), true)
	_text("Rooms snap to a 1 m grid. Heat, wall area and rain capture follow the footprint. One thermal zone per home; no door routing or room-specific plumbing yet.")
	if plan.rooms.size() > 3:
		_button(body, "Preview removing latest addition", func() -> void: action.emit({"type": "preview", "command": CBLivingWorld.action("remove", index)}))
	_rule()
	_select("Replace this home's wall assembly", "assemblies", z.assembly, func(id: String) -> void: action.emit({"type": "preview", "command": CBLivingWorld.action("insulate", index, id)}))
	_rule()
	_label(body, "MOVE THE WHOLE HOME", 11, GREEN)
	var x := _number("Grid X", -30, 30, plan.x)
	var zz := _number("Grid Z", -30, 30, plan.z)
	_button(body, "Preview relocation", func() -> void:
		x.apply()
		zz.apply()
		action.emit({"type": "preview", "command": CBLivingWorld.action("move", index, [int(x.value), int(zz.value)])}))
	_rule()
	_label(body, "SHARED SYSTEMS", 11, GREEN)
	dynamic.utilities = _text("", INK)
	for recipe in e.living_kit.upgrades:
		var id: String = recipe.id
		_button(body, recipe.name + " · " + euros(int(recipe.cost_cents)), func() -> void: action.emit({"type": "preview", "command": CBLivingWorld.action("upgrade", -1, id)}))

func _compare() -> void:
	_heading("03  COMPARE POSSIBILITIES", "One beginning, different choices")
	_future_controls()
	_text("All three communities began with the same homes, people and accounts. They share the weather and clock. Player changes affect only the selected future.")
	for i in 3:
		var index := i
		_rule()
		_label(body, CBLivingWorld.MODES[i], 20)
		dynamic["future_%d" % i] = _text("", INK)
		_button(body, "Visit " + CBLivingWorld.MODES[i], func() -> void: action.emit({"type": "future", "index": index}))
	_rule()
	_text("More space can mean larger bills. More autonomy can spend reserves faster. Compare comfort, affordability and resource failures rather than chasing a single score.")
	_button(body, "Advance one day", func() -> void: action.emit({"type": "run", "hours": 24}))
	_button(body, "Run the remaining year", func() -> void: action.emit({"type": "run", "hours": 8760}))
	_button(body, "Share this experiment", func() -> void: action.emit({"type": "export"}))
	_button(body, "Import a friend's world", func() -> void: action.emit({"type": "import", "purpose": "world"}))
	_button(body, "Export all three results", func() -> void: action.emit({"type": "export", "kind": "results"}))

func _workshop() -> void:
	_heading("04  REMIX THE RULES", "A community you can share")
	_text("Export a world to preserve its seed layers, data packs, building recipes and your decisions. A friend replays the same three futures and can continue the experiment.")
	_button(body, "Share this world", func() -> void: action.emit({"type": "export"}), true)
	_button(body, "Import a world", func() -> void: action.emit({"type": "import", "purpose": "world"}))
	_rule()
	_label(body, "DATA-ONLY LIVING KIT", 11, GREEN)
	_text("Edit construction costs, work durations, resident priorities, delegated budgets and utility recipes. Validating starts a new matched experiment with these rules; your old world is backed up.")
	if workshop_text.is_empty(): workshop_text = JSON.stringify(_living().living_kit, "  ")
	editor = TextEdit.new()
	editor.text = workshop_text
	editor.custom_minimum_size.y = 280
	editor.add_theme_font_size_override("font_size", 12)
	body.add_child(editor)
	_button(body, "Validate & start this remix", func() -> void: action.emit({"type": "remix", "text": editor.text}), true)
	_button(body, "Export living-kit schema", func() -> void: action.emit({"type": "export", "kind": "schema"}))
	_button(body, "Export AI modding prompt", func() -> void: action.emit({"type": "export", "kind": "prompt"}))
	_button(body, "Add a material data pack to a new world", func() -> void: action.emit({"type": "import", "purpose": "pack"}))
	_text("No scripts or network calls run from a kit. The optional AI prompt describes supported operations and includes the schema. New physics still needs engine code and tests.")
	_rule()
	_label(body, "WHY THE NEIGHBOURHOOD CHANGED", 11, GREEN)
	dynamic.journal = _text("", INK)
	_button(body, "Refresh journal", func() -> void: refresh())
	_rule()
	_button(body, "Inspect assumptions & limits", func() -> void: show_panel("Evidence"))
	_button(body, "Open the original annual lab", func() -> void: action.emit({"type": "legacy", "mode": "lab"}))

func _evidence() -> void:
	_heading("KEEP THE EXPERIMENT HONEST", "What this model can tell you")
	_text("This is a one-year, fixed-cohort prototype. It models home thermal zones, shared heat and electricity, finite utility stocks, bills and paid construction. Inputs are synthetic and uncalibrated.", INK)
	_text("Residents choose among bounded local recipes once daily. They use current conditions and declared space preferences. They do not invent new algorithms, forecast perfectly, form new households or simulate generations.")
	_text("One crew handles projects serially. Imported materials and labor are included in prices; there is no local material inventory, freight, land market or permitting. Occupants remain in place during construction. Moves are an illustrative paid relocation, not a detailed construction sequence.")
	_text("Rooms connect along grid edges. The model calculates exposed walls and inter-home thermal contact automatically. It does not calculate door access, plumbing routes, moisture, structural engineering, wildfire, floods, births or migration. Visible people, furniture and paths are presentation.")
	_text("New battery and tank capacity is empty. Building changes retain balances and history, with added effective thermal capacity entering at outdoor temperature. Imported input hashes establish identity, not scientific validity.")
	for evidence in _living().catalog.list_content("evidence"):
		_rule()
		_text(evidence.name + " · " + evidence.status + "\n" + evidence.notes)
	_button(body, "Back to world", func() -> void: show_panel("Design"))

func refresh() -> void:
	if game == null or game.experiment == null: return
	var e := _living()
	var world := _branch()
	var s := e.sim.state
	var loading := (game as CBLivingGame).loading != null
	date.text = "%s · %s · %s" % [CBLab.date_label(int(s.hour)), CBLivingWorld.MODES[e.active], "loading" if loading else e.phase]
	progress.value = float(s.hour) / maxi(1, e.limit)
	season_button.disabled = loading or e.phase == "running" or s.hour >= 8760
	year_button.disabled = season_button.disabled
	pause_button.disabled = loading or s.hour >= 8760
	pause_button.text = "Pause" if e.phase == "running" else "Play"
	lens.select(["materials", "temperature", "owners"].find(game.view.lens))
	cold_label.text = grouped(int(s.totals.cold_person_hours)) + " h"
	cost_label.text = euros(int(s.totals.operating_cents))
	debt_label.text = euros(e.sim.arrears())
	if dynamic.has("work"):
		dynamic.work.text = "Crew available · %d completed projects" % world.completed if world.pending.is_empty() else "%s\n%s · ready in %dh" % [world.pending.actor, world.pending.title, maxi(0, int(world.pending.due) - int(s.hour))]
	if dynamic.has("home_status"):
		var home: Dictionary = s.homes[game.selected]
		var z: Dictionary = e.sim.zones[game.selected]
		dynamic.home_status.text = "%.0f m² · %.1f°C now\nCold / hot occupied hours: %d / %d\nBills: %s · unpaid: %s\nOwner's available capital: %s" % [z.floor_m2, home.air_c, home.cold_hours, home.hot_hours, euros(int(home.billed_cents)), euros(int(home.arrears_cents)), euros(int(s.owners[z.owner]))]
	if dynamic.has("utilities"):
		dynamic.utilities.text = "Co-op capital: %s\nWater: %.0f / %.0f L · battery: %.1f / %.0f kWh\nSewage backlog: %.0f L · litter: %.1f kg" % [euros(int(s.shared_capital_cents)), s.water_l, e.design.tank_l, s.battery_kwh, e.design.battery_kwh, s.sewage_l, s.litter_kg]
	for i in 3:
		if not dynamic.has("future_%d" % i): continue
		var w := e.worlds[i]
		var report := w.model.report()
		var area := 0.0
		for z in w.model.zones: area += float(z.floor_m2)
		dynamic["future_%d" % i].text = "%d projects · %.0f m² of homes\nConstruction since start: %s\nCold / hot person-hours: %s / %s\nOperating cost: %s · unpaid bills: %s\nUnmet water: %.0f L · sewer overflow: %.0f L" % [w.completed, area, euros(w.spent), grouped(int(report.cold_person_hours)), grouped(int(report.hot_person_hours)), euros(int(report.operating_cents)), euros(int(report.arrears_cents)), report.water_unserved_l, report.sewage_overflow_l]
	if dynamic.has("journal"):
		var lines: Array[String] = []
		for event in world.journal.slice(maxi(0, world.journal.size() - 20)):
			lines.append("%s · %s\n%s\n%s" % [CBLab.date_label(int(event.hour)), event.actor, event.title, event.reason])
		lines.reverse()
		dynamic.journal.text = "\n\n".join(lines) if not lines.is_empty() else "Advance time to begin the story."
