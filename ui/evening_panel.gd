class_name CBEveningPanel
extends RefCounted
## Scenario presentation only. Every edit is sent through the simulation command boundary.

static func draw(ui: CBInterface) -> void:
	match ui.pane:
		"Inspect": inspect(ui)
		"Build": build(ui)
		"Try": experiments(ui)
		"Workshop": workshop(ui)

static func inspect(ui: CBInterface) -> void:
	var e: Dictionary = ui.sim.state.evening
	ui._eyebrow("01  NOTICE A PROBLEM")
	ui._heading("An evening back")
	ui._text("24 neighbours. One shared evening. Can everyone find time for dinner and a little life outside work?")
	ui.dynamic_labels.evening_summary = ui._label(ui.body, "", 17, ui.GREEN)
	if e.phase == "design":
		ui._text("The grocer closes at 18:30. Several neighbours finish work late; the market is a long walk away.")
		ui._button(ui.body, "Watch this evening", func() -> void: ui.action.emit({"ui": "evening_run", "fast": false}))
		ui._button(ui.body, "Explore a change", func() -> void: ui.show_panel("Build"))
	elif e.phase == "complete":
		ui._button(ui.body, "See what changed", func() -> void: ui.show_panel("Try"))
	ui._separator()
	ui._eyebrow("FOLLOW A NEIGHBOUR")
	if ui.selected_resident.is_empty(): ui.selected_resident = "resident_021"
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 48
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.fit_to_longest_item = false
	for person in ui.sim.state.residents:
		selector.add_item(person.name)
		selector.set_item_metadata(selector.item_count - 1, person.id)
		if person.id == ui.selected_resident: selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(index: int) -> void:
		ui.selected_resident = str(selector.get_item_metadata(index))
		ui.show_panel("Inspect")
		ui.action.emit({"ui": "resident", "id": ui.selected_resident}))
	ui.body.add_child(selector)
	var person := ui._person(ui.selected_resident)
	if person.is_empty(): return
	var actor: Dictionary = e.actors[person.id]
	ui._text("Work ends %s · %s\n%s" % [CBEvening.clock(int(actor.work_end)), "collects groceries for three" if actor.shopper else "shares a household dinner", "Takes a gentler walking pace." if actor.pace > 1 else "Hopes to join the courtyard from 19:30."])
	ui.dynamic_labels.evening_person = ui._label(ui.body, "", 16, ui.GREEN)
	ui.dynamic_labels.evening_timeline = ui._label(ui.body, "", 14, ui.INK)
	ui._separator()
	ui._eyebrow("LEARN BY TRYING")
	ui._text("Observe > change one thing > compare. A good idea makes life easier; a great one notices who still needs help.")

static func _toggle(ui: CBInterface, title: String, description: String, key: String) -> void:
	var button := CheckButton.new()
	button.text = title
	button.custom_minimum_size.y = 48
	button.button_pressed = bool(ui.sim.state.evening.design[key])
	button.toggled.connect(func(value: bool) -> void: ui.action.emit({"type": "evening_design", "key": key, "value": value}))
	ui.body.add_child(button)
	ui._text(description)

static func build(ui: CBInterface) -> void:
	var e: Dictionary = ui.sim.state.evening
	ui._eyebrow("02  TRY AN IDEA")
	ui._heading("Make room for life")
	if e.phase != "design":
		ui._text("This evening is already underway or complete. Return to its starting point to try a different design with the same neighbours.")
		ui._button(ui.body, "Try another idea", func() -> void: ui.action.emit({"type": "evening_reset"}))
		return
	ui._text("Changes are previews until you run the evening. Combine ideas, or test one at a time.")
	ui._stat("Construction preview", ui.euros(CBEvening.price(ui.sim, e.design)))
	ui._button(ui.body, "Try this design", func() -> void: ui.show_panel("Try"))
	var undo := ui._button(ui.body, "Undo last change", func() -> void: ui.action.emit({"type": "evening_undo"}))
	undo.disabled = e.undo.is_empty()
	ui._separator()
	_toggle(ui, "Open the market footpath · €300", "Outside walk: 28 > 12 minutes, plus the route through the building. Helps reach the grocer before closing.", "shortcut")
	_toggle(ui, "Keep the grocer open late · €150", "Closing: 18:30 > 20:00. Jules takes a paid shift, including preparation, at €15/hour.", "late_hours")
	ui._separator()
	ui._eyebrow("A USEFUL ROOM")
	ui._text("Choose one service. It occupies a real ground-floor room and needs stock, utilities and, where specified, a worker.")
	var definition := CBEvening.service_definition(ui.sim, e.design)
	if not definition.is_empty():
		ui._label(ui.body, "Selected: " + str(definition.name), 17, ui.GREEN)
		ui._stat("Opening delivery", ui.euros(int(definition.stock) * int(definition.unit_cost)))
		var rooms := OptionButton.new()
		rooms.custom_minimum_size.y = 48
		rooms.fit_to_longest_item = false
		for space in ui.sim.state.layout.spaces:
			if space.kind != "shop": continue
			rooms.add_item(space.name)
			rooms.set_item_metadata(rooms.item_count - 1, space.id)
			if space.id == e.design.space: rooms.select(rooms.item_count - 1)
		rooms.item_selected.connect(func(index: int) -> void: ui.action.emit({"type": "evening_space", "space": rooms.get_item_metadata(index)}))
		ui.body.add_child(rooms)
		ui._button(ui.body, "Remove proposed service", func() -> void: ui.action.emit({"type": "evening_service", "id": ""}))
	for item in ui.sim.catalog.list_content("evening_services"):
		var id := str(item.id)
		ui._button(ui.body, "%s · %s" % [item.name, ui.euros(int(item.capital))], func() -> void: ui.action.emit({"type": "evening_service", "id": id, "space": e.design.space}))
		ui._text(item.description)
	ui._separator()
	ui._eyebrow("ESSENTIAL CONNECTIONS")
	ui._text("The starting community has 120 L water, 12 kWh power, 120 L wastewater capacity and a 5 kg waste store for this six-hour test. Consumption is reserved when an activity starts.")
	_toggle(ui, "Water connected", "Required for home cooking and the shared kitchen.", "water")
	_toggle(ui, "Power connected", "Required for cooking and chilled grocery collection.", "power")
	_toggle(ui, "Wastewater connected", "Used water needs somewhere to go.", "sewage")
	_toggle(ui, "Waste pickup at 21:00 · €12", "Collection clears the shared store. Without it, waste remains on site.", "collection")

static func experiments(ui: CBInterface) -> void:
	var e: Dictionary = ui.sim.state.evening
	ui._eyebrow("03  WATCH & COMPARE")
	ui._heading("What if we tried…")
	if e.phase == "design":
		ui._text("Run from 16:00 to 22:00. The original arrangement is simulated alongside your design with the same 24 people, work times and starting resources.")
		ui._stat("Construction", ui.euros(CBEvening.price(ui.sim, e.design)))
		ui._button(ui.body, "Watch the evening", func() -> void: ui.action.emit({"ui": "evening_run", "fast": false}))
		ui._button(ui.body, "Get results quickly", func() -> void: ui.action.emit({"ui": "evening_run", "fast": true}))
		ui._button(ui.body, "Back to my design", func() -> void: ui.show_panel("Build"))
	elif e.phase == "running":
		ui._text("Watch neighbours travel, collect groceries and share dinner. Inspect anyone to follow their actual events.")
		ui.dynamic_labels.evening_summary = ui._label(ui.body, "", 18, ui.GREEN)
		ui._button(ui.body, "Fast-forward to the results", func() -> void: ui.action.emit({"ui": "evening_fast"}))
		ui._button(ui.body, "Follow a neighbour", func() -> void: ui.show_panel("Inspect"))
	else:
		var current := CBEvening.report(ui.sim)
		ui._label(ui.body, "%d of 24 found an evening" % current.on_time, 23, ui.GREEN)
		ui._text("At least 45 minutes in the courtyard after dinner, during its 19:30–21:00 activities. This is one measure, not a complete well-being score.")
		ui._button(ui.body, "Try another idea", func() -> void: ui.action.emit({"type": "evening_reset"}))
		if e.baseline.is_empty():
			ui._text("Finishing the original arrangement for a matched comparison…")
		else:
			var baseline: Dictionary = e.baseline
			ui._eyebrow("ORIGINAL  /  YOUR DESIGN")
			ui._stat("Ate dinner", "%d / %d" % [baseline.fed, current.fed])
			ui._stat("Found at least 45 min together", "%d / %d" % [baseline.on_time, current.on_time])
			ui._stat("Courtyard time · total min", "%d / %d" % [baseline.free, current.free])
			ui._stat("Travel · total min", "%d / %d" % [baseline.travel, current.travel])
			ui._stat("Cooking & shifts · total min", "%d / %d" % [baseline.labor, current.labor])
			ui._stat("Household food spending", "%s / %s" % [ui.euros(baseline.spending), ui.euros(current.spending)])
			ui._stat("Construction · once", "%s / %s" % [ui.euros(baseline.capital), ui.euros(current.capital)])
			ui._stat("Operations less sales", "%s / %s" % [ui.euros(int(baseline.operating) - int(baseline.income)), ui.euros(int(current.operating) - int(current.income))])
			ui._stat("Energy · kWh", "%.1f / %.1f" % [baseline.power, current.power])
			ui._separator()
			ui._eyebrow("WHOSE EVENING CHANGED?")
			var differences := 0
			for i in current.people.size():
				var person: Dictionary = current.people[i]
				var before: Dictionary = baseline.people[i]
				if person.free == before.free: continue
				differences += 1
				var id := str(person.id)
				ui._button(ui.body, "%s · %d > %d min" % [person.name.get_slice(" ", 0), before.free, person.free], func() -> void: ui.selected_resident = id; ui.show_panel("Inspect"); ui.action.emit({"ui": "resident", "id": id}))
			if differences == 0: ui._text("The same courtyard time for everyone. Try a route, schedule or service change.")
			if not e.design.recipe.is_empty() and e.design.service == "workshop:prototype": ui._text("This trial uses your custom service definition. Its costs and resource assumptions are part of the experiment.")
	ui._separator()
	ui._eyebrow("YOUR EXPERIMENT NOTEBOOK")
	ui._text("%d completed trials kept. Observe a cause, compare alternatives, then remix a piece of your own." % (e.attempts.size() + (1 if e.phase == "complete" else 0)))
	for previous in e.attempts.slice(maxi(0, e.attempts.size() - 3)):
		ui._text("%d neighbours found an evening · %s construction · %.1f kWh" % [previous.on_time, ui.euros(previous.capital), previous.power])
	ui._button(ui.body, "Export this community", func() -> void: ui.action.emit({"ui": "export"}))
	ui._button(ui.body, "Import a community", func() -> void: ui.action.emit({"ui": "import"}))
	ui._button(ui.body, "Start a fresh evening", func() -> void: ui.action.emit({"ui": "new_community"}))
	ui._text("Starting fresh keeps the previous saved evening as a timestamped backup.")

static func workshop(ui: CBInterface) -> void:
	ui._button(ui.body, "Open the annual community lab", func() -> void: ui.action.emit({"ui": "lab"}))
	var e: Dictionary = ui.sim.state.evening
	ui._eyebrow("04  INVENT A POSSIBILITY")
	ui._heading("Your little workshop")
	ui._text("Remix a useful piece. Every service uses the same stock, capacity, staffing and resource rules—including the pickup-locker mod.")
	if e.phase != "design":
		ui._button(ui.body, "Start another experiment", func() -> void: ui.action.emit({"type": "evening_reset"}))
		ui._text("Return to 16:00 before applying a new definition.")
		return
	var recipe: Dictionary = e.design.recipe.duplicate(true) if not e.design.recipe.is_empty() else ui.sim.catalog.get_definition("evening_services", "grocery_pickup:locker").duplicate(true)
	var templates := OptionButton.new()
	templates.custom_minimum_size.y = 48
	templates.fit_to_longest_item = false
	for item in ui.sim.catalog.list_content("evening_services"):
		templates.add_item("Remix: " + str(item.name))
		templates.set_item_metadata(templates.item_count - 1, item.id)
		if item.kind == recipe.kind: templates.select(templates.item_count - 1)
	ui.body.add_child(templates)
	ui._label(ui.body, "Name", 13, ui.MUTED)
	var name_input := LineEdit.new()
	name_input.text = "My " + str(recipe.name).to_lower() if e.design.recipe.is_empty() else str(recipe.name)
	name_input.max_length = 60
	name_input.custom_minimum_size.y = 48
	ui.body.add_child(name_input)
	ui._label(ui.body, "Closes", 13, ui.MUTED)
	var closing := OptionButton.new()
	closing.custom_minimum_size.y = 48
	for minute in range(CBEvening.START + 15, CBEvening.END + 1, 15):
		closing.add_item(CBEvening.clock(minute))
		closing.set_item_metadata(closing.item_count - 1, minute)
	_select_time(closing, int(recipe.close))
	ui.body.add_child(closing)
	var places := ui._number("People / shopping parties served at once", 1, 24, recipe.slots, 1)
	var stock := ui._number("Opening stock · portions", 1, 150, recipe.stock, 1)
	var cost := ui._number("Price per portion · €", 0, 100, float(recipe.price) / 100, 0.5)
	var draft := func() -> Dictionary:
		var value := recipe.duplicate(true)
		value.id = "workshop:prototype"
		value.name = name_input.text
		value.close = int(closing.get_selected_metadata())
		value.slots = int(places.value)
		value.stock = int(stock.value)
		value.price = int(cost.value * 100)
		return value
	ui._button(ui.body, "Use this prototype", func() -> void: ui.action.emit({"type": "evening_recipe", "recipe": draft.call()}))
	ui._text("Construction, stock deliveries, energy and staffing still count. Changes affect the next trial; the original arrangement is retained for comparison.")
	ui._separator()
	ui._eyebrow("JSON & AI-ASSISTED REMIXING")
	ui._text("Export a prompt for your preferred AI, then paste a service definition below. No AI account is required to use this editor; nothing is sent automatically.")
	var editor := TextEdit.new()
	editor.custom_minimum_size = Vector2(0, 230)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text = JSON.stringify(draft.call(), "  ")
	ui.body.add_child(editor)
	templates.item_selected.connect(func(index: int) -> void:
		var value: Dictionary = ui.sim.catalog.get_definition("evening_services", str(templates.get_item_metadata(index))).duplicate(true)
		recipe.clear()
		recipe.merge(value)
		name_input.text = "My " + str(value.name).to_lower()
		_select_time(closing, int(value.close))
		places.value = value.slots
		stock.value = value.stock
		cost.value = float(value.price) / 100
		editor.text = JSON.stringify(draft.call(), "  "))
	ui._button(ui.body, "Copy form values into JSON", func() -> void: editor.text = JSON.stringify(draft.call(), "  "))
	ui._button(ui.body, "Validate & use pasted JSON", func() -> void:
		if editor.text.length() > 16000:
			ui.toast("Use a service definition smaller than 16 KB.")
			return
		var parsed: Variant = JSON.parse_string(editor.text)
		ui.action.emit({"type": "evening_recipe", "recipe": parsed}))
	ui._button(ui.body, "Export a reusable mod pack", func() -> void:
		var value: Variant = JSON.parse_string(editor.text)
		var error := CBEvening.definition_error(value)
		if not error.is_empty(): ui.toast(error); return
		ui.action.emit({"ui": "evening_export_pack", "recipe": value}))
	ui._button(ui.body, "Export an AI drafting prompt", func() -> void: ui.action.emit({"ui": "evening_export_prompt", "recipe": draft.call()}))
	ui._button(ui.body, "Install a trusted mod…", func() -> void: ui.action.emit({"ui": "install_mod"}))
	ui._text("Installed packs activate after restart. Start a fresh evening for the new pack set; existing saves stay protected. Source-code packs have the game's file and network capabilities.")
	ui._text("This editor supports groceries and meals. Novel activity types need an engine extension; unsupported fields are rejected rather than converted into happiness bonuses.")

static func _select_time(control: OptionButton, minute: int) -> void:
	for index in control.item_count:
		if control.get_item_metadata(index) == minute:
			control.select(index)
			return
	control.add_item(CBEvening.clock(minute))
	control.set_item_metadata(control.item_count - 1, minute)
	control.select(control.item_count - 1)

static func refresh(ui: CBInterface) -> void:
	var e: Dictionary = ui.sim.state.evening
	if ui.dynamic_labels.has("evening_summary"):
		var r := CBEvening.report(ui.sim)
		ui.dynamic_labels.evening_summary.text = "Ready to explore · 16:00" if e.phase == "design" else "%d / 24 ate dinner · %d found at least 45 min together" % [r.fed, r.on_time]
	if ui.dynamic_labels.has("evening_person"):
		var person := ui._person(ui.selected_resident)
		if person.is_empty(): return
		var a: Dictionary = e.actors[person.id]
		ui.dynamic_labels.evening_person.text = "%s\n%d min travel · %d min cooking / shifts" % [str(person.activity).capitalize(), a.travel, a.labor]
		var lines: Array[String] = []
		for event in e.events:
			if event.actor == person.id: lines.append("%s  %s" % [CBEvening.clock(int(event.minute)), event.text])
		ui.dynamic_labels.evening_timeline.text = "Their timeline will appear here as the evening unfolds." if lines.is_empty() else "\n\n".join(lines.slice(maxi(0, lines.size() - 8)))
