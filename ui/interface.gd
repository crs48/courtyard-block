class_name CBInterface
extends CanvasLayer

signal action(command: Dictionary)
const INK := Color("#293e35")
const MUTED := Color("#7c8175")
const PAPER := Color("#faf7ee")
const GREEN := Color("#426954")
var sim: CBSimulation
var root: Control
var body: VBoxContainer
var inspector: PanelContainer
var panel_scroll: ScrollContainer
var panel_identity := ""
var nav: VBoxContainer
var metrics_bar: HBoxContainer
var wellbeing_label: Label
var funds_label: Label
var date_label: Label
var status_label: Label
var floor_label: Label
var pane := "Overview"
var selected_resident := ""
var selected_home := ""
var comparison: Dictionary = {}
var dynamic_labels: Dictionary = {}
var buttons: Dictionary = {}
var curve: CBHistoryChart
var speed_button: Button
var save_button: Button
var compact_navigation: OptionButton
var bottom_bar: PanelContainer
var floor_bar: HBoxContainer
var floor_spin: SpinBox
var width_spin: SpinBox
var court_spin: SpinBox
var material_option: OptionButton
var template_option: OptionButton
var proposed: Dictionary = {}
var brand: VBoxContainer
var collapse_button: Button
var panel_collapsed := false
var is_evening := false

func setup(model: CBSimulation) -> void:
	sim = model
	is_evening = sim.state.has("evening")
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	brand = VBoxContainer.new()
	brand.position = Vector2(28, 24)
	root.add_child(brand)
	_label(brand, "COURTYARD\nBLOCK", 29, INK)
	_label(brand, "A small place. A shared life.", 12, MUTED)
	metrics_bar = HBoxContainer.new()
	metrics_bar.position = Vector2(285, 30)
	metrics_bar.add_theme_constant_override("separation", 28)
	root.add_child(metrics_bar)
	var residents := VBoxContainer.new()
	metrics_bar.add_child(residents)
	_label(residents, "NEIGHBOURS", 10, MUTED)
	dynamic_labels.population = _label(residents, str(sim.state.residents.size()), 24, INK)
	var happiness := VBoxContainer.new()
	metrics_bar.add_child(happiness)
	_label(happiness, "WELL-BEING", 10, MUTED)
	wellbeing_label = _label(happiness, "76 / 100", 24, INK)
	var finances := VBoxContainer.new()
	metrics_bar.add_child(finances)
	_label(finances, "SHARED FUNDS", 10, MUTED)
	funds_label = _label(finances, "€250,000", 24, INK)
	save_button = _button(root, "Save community", func() -> void: action.emit({"ui": "save"}))
	save_button.size = Vector2(156, 42)
	nav = VBoxContainer.new()
	nav.position = Vector2(28, 178)
	nav.add_theme_constant_override("separation", 9)
	root.add_child(nav)
	var names := ["Inspect", "Build", "Try", "Workshop"] if is_evening else ["Overview", "Residents", "Build", "Co-op", "Experiments", "Mods"]
	compact_navigation = OptionButton.new()
	for section in names: compact_navigation.add_item(section)
	compact_navigation.position = Vector2(250, 30)
	compact_navigation.size = Vector2(170, 44)
	compact_navigation.item_selected.connect(func(index: int) -> void: show_panel(names[index]))
	root.add_child(compact_navigation)
	collapse_button = _button(root, "Hide panel", func() -> void:
		panel_collapsed = not panel_collapsed
		_responsive())
	collapse_button.visible = false
	for i in names.size():
		var section: String = names[i]
		var button := _button(nav, "%02d   %s" % [i + 1, section], func() -> void: show_panel(section))
		button.custom_minimum_size = Vector2(164, 45)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buttons[section] = button
	inspector = PanelContainer.new()
	inspector.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	inspector.position = Vector2(-370, 112)
	inspector.size = Vector2(342, 650)
	inspector.add_theme_stylebox_override("panel", _box(PAPER, 16, 23))
	root.add_child(inspector)
	var scroll := ScrollContainer.new()
	panel_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	var bottom := PanelContainer.new()
	bottom_bar = bottom
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.position = Vector2(28, -92)
	bottom.size = Vector2(530, 64)
	bottom.add_theme_stylebox_override("panel", _box(PAPER, 12, 12))
	root.add_child(bottom)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	bottom.add_child(tools)
	speed_button = _button(tools, "Pause", func() -> void: action.emit({"ui": "pause"}))
	var speed := OptionButton.new()
	for value in ["1×", "5×", "20×"]: speed.add_item(value)
	speed.item_selected.connect(func(index: int) -> void: action.emit({"ui": "speed", "value": [1, 5, 20][index]}))
	tools.add_child(speed)
	date_label = _label(tools, "Day 1 · 08:00", 14, INK)
	date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(tools, "−", func() -> void: action.emit({"ui": "zoom", "value": 1.12}))
	_button(tools, "+", func() -> void: action.emit({"ui": "zoom", "value": 0.89}))
	_button(tools, "Rotate", func() -> void: action.emit({"ui": "rotate", "value": -PI / 2.0}))
	var floors := HBoxContainer.new()
	floor_bar = floors
	floors.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	floors.position = Vector2(-360, -82)
	floors.add_theme_constant_override("separation", 10)
	root.add_child(floors)
	_button(floors, "−", func() -> void: action.emit({"ui": "floor", "value": -1}))
	floor_label = _label(floors, "All floors", 14, INK)
	floor_label.custom_minimum_size.x = 110
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(floors, "+", func() -> void: action.emit({"ui": "floor", "value": 1}))
	_button(floors, "All", func() -> void: action.emit({"ui": "all_floors"}))
	status_label = _label(root, "Drag to explore · Scroll to zoom · Select a floor to look inside", 12, MUTED)
	status_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status_label.position = Vector2(30, -22)
	root.resized.connect(_responsive)
	show_panel("Inspect" if is_evening else "Overview")
	_responsive()

func _responsive() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < 1100
	var portrait := viewport_size.x < 600 or (viewport_size.x < 1000 and viewport_size.y > viewport_size.x * 1.05)
	metrics_bar.visible = not compact
	nav.visible = not compact
	compact_navigation.visible = compact
	nav.position.y = 156 if compact else 178
	var panel_width := (306 if compact else (410 if is_evening else 342))
	inspector.position = Vector2(viewport_size.x - panel_width - 28, 88 if compact else 112)
	inspector.size = Vector2(panel_width, maxf(120, viewport_size.y - (188 if compact else 218)))
	save_button.position = Vector2(viewport_size.x - 184, 30)
	bottom_bar.size.x = 460 if compact else 530
	bottom_bar.position = Vector2(28, viewport_size.y - 92)
	floor_bar.position = Vector2(viewport_size.x - 322, viewport_size.y - 82)
	status_label.position = Vector2(30, viewport_size.y - 22)
	status_label.size.x = viewport_size.x - 60
	status_label.clip_text = true
	brand.visible = not compact
	save_button.visible = not portrait
	floor_bar.visible = true
	collapse_button.visible = compact
	inspector.visible = not (compact and panel_collapsed)
	collapse_button.text = "Show panel" if panel_collapsed else "Hide panel"
	if portrait:
		floor_bar.position = Vector2(12, 68)
		compact_navigation.position = Vector2(12, 12)
		compact_navigation.size = Vector2(viewport_size.x - 140, 48)
		collapse_button.position = Vector2(viewport_size.x - 120, 12)
		collapse_button.size = Vector2(108, 48)
		collapse_button.text = "Show panel" if panel_collapsed else "Hide panel"
		inspector.position = Vector2(12, viewport_size.y * 0.37)
		inspector.size = Vector2(viewport_size.x - 24, maxf(100, viewport_size.y * 0.63 - 98))
		inspector.add_theme_stylebox_override("panel", _box(PAPER, 16, 16))
		bottom_bar.position = Vector2(8, viewport_size.y - 78)
		bottom_bar.size = Vector2(viewport_size.x - 16, 58)
		var row: HBoxContainer = bottom_bar.get_child(0)
		row.add_theme_constant_override("separation", 3)
		for child in row.get_children():
			if child is Button and child.text == "Rotate": child.visible = false
		status_label.position = Vector2(12, viewport_size.y - 19)
	else:
		compact_navigation.position = Vector2(28, 30)
		compact_navigation.size = Vector2(170, 44)
		collapse_button.position = Vector2(210, 30)
		collapse_button.size = Vector2(108, 44)
		if compact:
			floor_bar.position = Vector2(28, 88)
			bottom_bar.size.x = viewport_size.x - 56
		var row: HBoxContainer = bottom_bar.get_child(0)
		row.add_theme_constant_override("separation", 10)
		for child in row.get_children():
			if child is Button and child.text == "Rotate": child.visible = true
	for button in buttons.values():
		button.custom_minimum_size = Vector2(136 if compact else 164, 42)

func show_panel(section: String) -> void:
	if is_evening:
		if section in ["Residents", "Overview"]: section = "Inspect"
		if not section in ["Inspect", "Build", "Try", "Workshop"]: section = "Try"
	var identity := section + ":" + (selected_resident if section == "Residents" else (selected_home if section == "Build" else ""))
	if identity != panel_identity:
		panel_scroll.set_deferred("scroll_vertical", 0)
		panel_identity = identity
	pane = section
	for i in compact_navigation.item_count:
		if compact_navigation.get_item_text(i) == section: compact_navigation.select(i)
	dynamic_labels.clear()
	curve = null
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for name_value in buttons:
		buttons[name_value].modulate = Color.WHITE if name_value == section else Color(1, 1, 1, 0.65)
	if is_evening:
		CBEveningPanel.draw(self)
		refresh()
		return
	match section:
		"Overview": _overview()
		"Residents": _residents()
		"Build": _build()
		"Co-op": _coop()
		"Experiments": _experiments()
		"Mods": _mods()
	refresh()

func _overview() -> void:
	_eyebrow("YOUR SHARED PLACE")
	_heading("Good morning,\nneighbour.")
	_text("A little city around a garden. Make room for the lives you want to share.")
	_separator()
	_stat("People calling this home", str(sim.state.residents.size()))
	_stat("Households", str(sim.state.households.size()))
	_stat("Ground-floor businesses", str(sim.state.shops.filter(func(shop: Dictionary) -> bool: return shop.business != "").size()))
	_separator()
	_eyebrow("HOW LIFE FEELS")
	curve = CBHistoryChart.new()
	curve.custom_minimum_size = Vector2(240, 100)
	body.add_child(curve)
	dynamic_labels.summary = _label(body, "", 14, GREEN)
	_text("Happiness has many sides. Look at individual stories as well as the average.")
	_button(body, "Meet your neighbours", func() -> void: show_panel("Residents"))
	_button(body, "Shape your building", func() -> void: show_panel("Build"))
	_separator()
	_eyebrow("A SMALL IDEA")
	_text("Try a reading nook, a new shop, or supper together. Fork your community to see what changes.")

func _residents() -> void:
	_eyebrow("PEOPLE, NOT JUST NUMBERS")
	_heading("Your neighbours")
	if selected_resident != "":
		var person := _person(selected_resident)
		if not person.is_empty():
			_label(body, person.name, 23, INK)
			_text("Loves %s · Skilled in %s\nValues %s" % [person.interest, person.skill, person.preference])
			dynamic_labels.person = _label(body, "", 14, GREEN)
			for need in person.needs:
				var row := HBoxContainer.new()
				body.add_child(row)
				var label := _label(row, str(need).capitalize(), 13, MUTED)
				label.custom_minimum_size.x = 72
				var bar := ProgressBar.new()
				bar.custom_minimum_size = Vector2(150, 14)
				bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bar.show_percentage = false
				bar.value = person.needs[need]
				row.add_child(bar)
				dynamic_labels[need] = bar
			dynamic_labels.reason = _label(body, person.reason, 14, INK)
			dynamic_labels.reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_button(body, "Visit their apartment", func() -> void: action.emit({"ui": "home", "id": person.home}))
			_button(body, "All neighbours", func() -> void: selected_resident = ""; show_panel("Residents"))
			return
	var search := LineEdit.new()
	search.placeholder_text = "Find a name or an interest…"
	body.add_child(search)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 7)
	body.add_child(list)
	var populate := func(query: String) -> void:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
		for person in sim.state.residents:
			if not query.is_empty() and not (str(person.name) + str(person.interest)).to_lower().contains(query.to_lower()): continue
			var id := str(person.id)
			var button := _button(list, "%s\n%s · %s%% well-being" % [person.name, str(person.interest).capitalize(), int(person.wellbeing)], func() -> void: selected_resident = id; show_panel("Residents"); action.emit({"ui": "resident", "id": id}))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size.y = 56
	search.text_changed.connect(populate)
	populate.call("")

func _build() -> void:
	_eyebrow("ROOM FOR POSSIBILITY")
	_heading("Make it your own")
	if selected_home != "" and sim.spaces.has(selected_home):
		var home: Dictionary = sim.spaces[selected_home]
		_label(body, home.name, 20, INK)
		_text("%s of 12 furnishing spots filled. Each piece contributes to comfort and daily life." % home.furniture.size())
		var search := LineEdit.new()
		search.placeholder_text = "Search furniture…"
		body.add_child(search)
		var list := VBoxContainer.new()
		body.add_child(list)
		var populate := func(query: String) -> void:
			for child in list.get_children():
				list.remove_child(child)
				child.queue_free()
			var count := 0
			for item in sim.catalog.list_content("furniture"):
				if not query.is_empty() and not str(item.name).to_lower().contains(query.to_lower()): continue
				if count >= 40: break
				count += 1
				var id := str(item.id)
				var button := _button(list, "%s  ·  %s" % [item.name, euros(int(item.cost))], func() -> void: action.emit({"type": "furnish", "space": selected_home, "item": id}))
				button.tooltip_text = str(item.get("description", ""))
		search.text_changed.connect(populate)
		populate.call("")
		_button(body, "Building design", func() -> void: selected_home = ""; show_panel("Build"))
		return
	_text("Explore a new shape for your community. Existing households stay together.")
	template_option = OptionButton.new()
	for template in sim.catalog.list_content("templates"):
		template_option.add_item(template.name)
		template_option.set_item_metadata(template_option.item_count - 1, template.id)
		if template.id == sim.state.parameters.template: template_option.select(template_option.item_count - 1)
	body.add_child(template_option)
	floor_spin = _number("Storeys", 5, 7, sim.state.parameters.floors, 1)
	width_spin = _number("Footprint · metres", 28, 48, sim.state.parameters.width, 2)
	court_spin = _number("Courtyard · metres", 10, 24, sim.state.parameters.courtyard, 2)
	_label(body, "Building material", 12, MUTED)
	material_option = OptionButton.new()
	for material in sim.catalog.list_content("materials"):
		material_option.add_item(material.name)
		material_option.set_item_metadata(material_option.item_count - 1, material.id)
		if material.id == sim.state.parameters.material: material_option.select(material_option.item_count - 1)
	body.add_child(material_option)
	dynamic_labels.estimate = _label(body, "", 13, GREEN)
	dynamic_labels.estimate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var estimate := func(_value: Variant = null) -> void:
		court_spin.max_value = minf(24, width_spin.value - 16)
		var cost := sim.building_cost({"width": width_spin.value, "floors": floor_spin.value, "material": material_option.get_selected_metadata()})
		dynamic_labels.estimate.text = "Improvement budget: " + euros(cost)
	for control in [floor_spin, width_spin, court_spin]: control.value_changed.connect(estimate)
	material_option.item_selected.connect(estimate)
	estimate.call()
	_button(body, "Apply building improvements", func() -> void: action.emit({"type": "rebuild", "parameters": {"floors": int(floor_spin.value), "width": width_spin.value, "courtyard": court_spin.value, "material": material_option.get_selected_metadata(), "template": template_option.get_selected_metadata()}}))
	_separator()
	_text("To furnish an apartment, choose a floor and select a home in the model, or visit someone through Residents.")
	_button(body, "Furnish the first apartment", func() -> void: action.emit({"ui": "home", "id": sim.state.residents[0].home}))

func _coop() -> void:
	_eyebrow("BETTER, TOGETHER")
	_heading("The co-op")
	_text("Balance affordability, reliable services, and the places that bring people together.")
	var dues := _number("Monthly contribution · €/household", 300, 2000, float(sim.state.policies.contribution) / 100.0, 50)
	dues.value_changed.connect(func(value: float) -> void: action.emit({"type": "policy", "key": "contribution", "value": int(value * 100)}))
	var meals := CheckButton.new()
	meals.text = "Shared suppers at 19:00"
	meals.button_pressed = sim.state.policies.shared_meals
	meals.toggled.connect(func(value: bool) -> void: action.emit({"type": "policy", "key": "shared_meals", "value": value}))
	body.add_child(meals)
	_text("The kitchen mod brings neighbours together over an affordable shared meal.")
	_separator()
	_eyebrow("EVERYDAY ESSENTIALS")
	for service in sim.state.services:
		_stat(str(service).capitalize(), "%s%%" % int(sim.state.services[service] * 100))
	_button(body, "Restore services · €2,500", func() -> void: action.emit({"type": "improve"}))
	_separator()
	_eyebrow("LIFE AT STREET LEVEL")
	for shop in sim.state.shops:
		_label(body, sim.spaces[shop.space].name, 13, INK)
		var options := OptionButton.new()
		options.add_item("Available to let")
		options.set_item_metadata(0, "")
		for business in sim.catalog.list_content("businesses"):
			options.add_item(business.name)
			options.set_item_metadata(options.item_count - 1, business.id)
			if business.id == shop.business: options.select(options.item_count - 1)
		var space_id := str(shop.space)
		options.item_selected.connect(func(index: int) -> void: action.emit({"type": "lease", "space": space_id, "business": options.get_item_metadata(index)}))
		body.add_child(options)

func _experiments() -> void:
	_eyebrow("WHAT IF WE LIVED DIFFERENTLY?")
	_heading("Other possibilities")
	_text("Keep a baseline, change one thing, and compare both communities at the same point in time.")
	var unlimited := CheckButton.new()
	unlimited.text = "Unlimited funds"
	unlimited.button_pressed = sim.state.policies.unlimited_funds
	unlimited.toggled.connect(func(value: bool) -> void: action.emit({"type": "policy", "key": "unlimited_funds", "value": value}))
	body.add_child(unlimited)
	_button(body, "Fork this community", func() -> void: action.emit({"ui": "fork"}))
	_button(body, "Switch to the other branch", func() -> void: action.emit({"ui": "switch_branch"}))
	_button(body, "Simulate one week", func() -> void: action.emit({"ui": "week"}))
	_separator()
	if comparison.get("ok", false):
		_eyebrow("AFTER %s SHARED HOURS" % (int(comparison.elapsed) / 60))
		_stat("Well-being · this / other", "%.0f / %.0f" % [comparison.left.wellbeing, comparison.right.wellbeing])
		_stat("Least happy 10%", "%.0f / %.0f" % [comparison.left.bottom_decile, comparison.right.bottom_decile])
		_stat("Shared funds", "%s / %s" % [euros(int(comparison.left.funds)), euros(int(comparison.right.funds))])
		_stat("Water used · litres", "%s / %s" % [int(comparison.left.water_l), int(comparison.right.water_l)])
	else:
		_text(comparison.get("message", "Your comparison will appear here after both branches have lived a little."))
	_separator()
	_button(body, "Export community", func() -> void: action.emit({"ui": "export"}))
	_button(body, "Import community", func() -> void: action.emit({"ui": "import"}))
	_button(body, "Load last save", func() -> void: action.emit({"ui": "load"}))
	_button(body, "Start a new community", func() -> void: action.emit({"ui": "new_community"}))
	_text("A grounded game model, not a prediction. Housing and water benchmarks are documented; behavior and balancing assumptions are adjustable.")

func _mods() -> void:
	_eyebrow("MADE TO BE MADE YOURS")
	_heading("A world of additions")
	_text("Add small comforts or entirely different ways of living. Installed code packs activate after restarting.")
	for id in sim.catalog.packs:
		var pack: Dictionary = sim.catalog.packs[id]
		_label(body, pack.name, 17, INK)
		_text("%s · v%s" % [id, pack.version])
		_separator()
	_button(body, "Install a trusted mod…", func() -> void: action.emit({"ui": "install_mod"}))
	_text("GDScript mods run with the game's capabilities. Only install code from creators you trust.")
	for callback in sim.catalog.panels.values():
		var panel: Dictionary = callback.call(sim.state.duplicate(true))
		_label(body, str(panel.get("title", "")), 17, INK)
		_text(str(panel.get("text", "")))
	_eyebrow("CREATOR KIT")
	_text("Start with mods/soft_spaces for data, community_kitchen for behavior, or garden_village for a new building generator. See docs/modding.md.")

func refresh() -> void:
	if sim.state.is_empty(): return
	var m := sim.metrics()
	wellbeing_label.text = "%s / 100" % int(m.wellbeing)
	funds_label.text = euros(int(sim.state.funds))
	var minute := int(sim.state.minute)
	date_label.text = "Day %s · %02d:%02d" % [minute / 1440 + 1, minute % 1440 / 60, minute % 60]
	if is_evening:
		date_label.text = CBEvening.clock(minute)
		CBEveningPanel.refresh(self)
		return
	if is_instance_valid(curve):
		curve.samples = sim.state.history
		curve.queue_redraw()
	if dynamic_labels.has("summary"):
		dynamic_labels.summary.text = "%.0f average · %.0f among the least happy 10%%" % [m.wellbeing, m.bottom_decile]
	if dynamic_labels.has("person"):
		var person := _person(selected_resident)
		if not person.is_empty():
			dynamic_labels.person.text = "%s · %s%% well-being" % [str(person.activity).capitalize(), int(person.wellbeing)]
			dynamic_labels.reason.text = person.reason
			for need in person.needs:
				if dynamic_labels.has(need): dynamic_labels[need].value = person.needs[need]

func _person(id: String) -> Dictionary:
	for person in sim.state.residents:
		if person.id == id: return person
	return {}

func toast(message: String) -> void:
	status_label.text = message

func _number(caption: String, minimum: float, maximum: float, value: float, step: float) -> SpinBox:
	_label(body, caption, 12, MUTED)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = value
	input.custom_minimum_size.y = 48
	body.add_child(input)
	return input

func _eyebrow(text: String) -> void: _label(body, text, 10, MUTED)
func _heading(text: String) -> void: _label(body, text, 28, INK)
func _text(text: String) -> void:
	var label := _label(body, text, 14, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _separator() -> void:
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", _box(Color("#e3e0d4"), 0, 0))
	line.custom_minimum_size.y = 2
	body.add_child(line)

func _stat(caption: String, value: String) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var label := _label(row, caption, 12, MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var amount := _label(row, value, 15, INK)
	amount.custom_minimum_size.x = 64
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _label(parent: Node, text: String, size_value: int, color_value: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color_value)
	if parent == body:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = parent == body or (body != null and body.is_ancestor_of(parent))
	button.custom_minimum_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func euros(cents: int) -> String:
	var digits := str(absi(cents) / 100)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0: result += ","
		result += digits[i]
	return ("−" if cents < 0 else "") + "€" + result

func _box(color_value: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color_value
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_stylebox("normal", "Button", _box(Color("#eeeade"), 8, 12))
	theme.set_stylebox("hover", "Button", _box(Color("#e3e7d6"), 8, 12))
	theme.set_stylebox("pressed", "Button", _box(GREEN, 8, 12))
	theme.set_stylebox("focus", "Button", _box(Color(0.5, 0.6, 0.4, 0.18), 8, 2))
	theme.set_stylebox("normal", "LineEdit", _box(Color("#eeeadf"), 7, 10))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_stylebox("normal", "OptionButton", _box(Color("#eeeade"), 8, 10))
	theme.set_color("font_color", "OptionButton", INK)
	theme.set_stylebox("background", "ProgressBar", _box(Color("#e7e3d6"), 5, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(Color("#8caa7f"), 5, 0))
	theme.set_color("font_color", "CheckButton", INK)
	return theme
