class_name CBLabInterface
extends CanvasLayer

signal action(value: Dictionary)
const INK := Color("#293f36")
const MUTED := Color("#738174")
const GREEN := Color("#3c715d")
const PAPER := Color("#faf7ed")
var game: CBLabGame
var root: Control
var inspector: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var brand: Label
var title: Label
var date: Label
var nav: HBoxContainer
var tabs: Dictionary = {}
var world_tools: HBoxContainer
var share: Button
var footer: HBoxContainer
var season_button: Button
var year_button: Button
var pause_button: Button
var collapse_button: Button
var progress: ProgressBar
var toast_label: Label
var summary: PanelContainer
var cold_label: Label
var cost_label: Label
var debt_label: Label
var pane := "Design"
var portrait := false
var collapsed := false
var panel_width := 430.0
var dynamic: Dictionary = {}
var chart: CBLabChart
var workshop_text := ""
var editor: TextEdit
var lens: OptionButton

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	brand = _label(root, "COURTYARD BLOCK  /  COMMUNITY LAB", 12, MUTED)
	title = _label(root, "Warm homes, shared systems", 34)
	date = _label(root, "", 14, GREEN)
	nav = HBoxContainer.new()
	nav.add_theme_constant_override("separation", 7)
	root.add_child(nav)
	for name_value in ["Design", "People", "Compare", "Workshop"]:
		var section: String = name_value
		tabs[section] = _button(nav, section, func() -> void: show_panel(section))
	share = _button(root, "Export experiment", func() -> void: action.emit({"type": "export"}))
	world_tools = HBoxContainer.new()
	world_tools.add_theme_constant_override("separation", 6)
	root.add_child(world_tools)
	lens = OptionButton.new()
	for text in ["Materials", "Temperature", "Ownership"]: lens.add_item(text)
	lens.custom_minimum_size = Vector2(122, 44)
	lens.item_selected.connect(func(index: int) -> void: action.emit({"type": "lens", "value": ["materials", "temperature", "owners"][index]}))
	world_tools.add_child(lens)
	_button(world_tools, "−", func() -> void: action.emit({"type": "zoom", "factor": 1.1}))
	_button(world_tools, "+", func() -> void: action.emit({"type": "zoom", "factor": 0.9}))
	_button(world_tools, "Turn", func() -> void: action.emit({"type": "rotate"}))
	collapse_button = _button(world_tools, "Scene", func() -> void: action.emit({"type": "collapse"}))
	inspector = PanelContainer.new()
	inspector.add_theme_stylebox_override("panel", _box(PAPER, 18))
	root.add_child(inspector)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	body.minimum_size_changed.connect(func() -> void: responsive.call_deferred())
	summary = PanelContainer.new()
	summary.add_theme_stylebox_override("panel", _box(Color("#f6f2e6"), 16))
	root.add_child(summary)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 32)
	summary.add_child(metrics)
	cold_label = _metric(metrics, "OCCUPIED COLD HOURS")
	cost_label = _metric(metrics, "SHARED OPERATING COST")
	debt_label = _metric(metrics, "UNPAID HOUSEHOLD BILLS")
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	season_button = _button(footer, "Run 90 days", func() -> void: action.emit({"type": "run", "hours": 2160}), true)
	year_button = _button(footer, "Run 1 year", func() -> void: action.emit({"type": "run", "hours": 8760}), true)
	pause_button = _button(footer, "Undo", func() -> void:
		var phase := game.experiment.phase
		action.emit({"type": "undo" if phase == "design" else ("reset" if phase == "complete" else "pause")}))
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.max_value = 1
	progress.add_theme_stylebox_override("background", _box(Color("#dbdece"), 0))
	progress.add_theme_stylebox_override("fill", _box(GREEN, 0))
	root.add_child(progress)
	toast_label = _label(root, "Change a wall, follow a household, try a different year.", 12, MUTED)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.resized.connect(responsive)
	show_panel("Design")
	responsive()

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	for control in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "SpinBox", "TextEdit"]: theme.set_color("font_color", control, INK)
	for control in ["Button", "OptionButton"]:
		theme.set_color("font_hover_color", control, INK)
		theme.set_color("font_pressed_color", control, INK)
		theme.set_stylebox("normal", control, _box(Color("#eeeddf"), 10))
		theme.set_stylebox("hover", control, _box(Color("#e0e5d5"), 10))
		theme.set_stylebox("pressed", control, _box(Color("#d5decb"), 10))
		theme.set_stylebox("disabled", control, _box(Color("#eeeadd"), 10))
		theme.set_color("font_disabled_color", control, Color("#949d90"))
	for control in ["TextEdit", "LineEdit"]:
		theme.set_stylebox("normal", control, _box(Color("#eeeede"), 10))
		theme.set_stylebox("focus", control, _box(Color("#e6ecdf"), 10))
	return theme

func _box(color_value: Color, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color_value
	box.set_corner_radius_all(10)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func _label(parent: Node, text_value: String, font_size: int = 14, color_value: Color = INK) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color_value)
	if parent == body: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _text(text_value: String, color_value: Color = MUTED) -> Label:
	var label := _label(body, text_value, 14, color_value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(parent: Node, text_value: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.clip_text = parent == body
	button.custom_minimum_size = Vector2(44, 44)
	button.pressed.connect(callback)
	if primary:
		button.add_theme_stylebox_override("normal", _box(GREEN, 12))
		button.add_theme_stylebox_override("hover", _box(Color("#315e4b"), 12))
		button.add_theme_color_override("font_color", PAPER)
		button.add_theme_color_override("font_hover_color", PAPER)
	parent.add_child(button)
	return button

func _metric(parent: Node, heading: String) -> Label:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	_label(column, heading, 10, MUTED)
	return _label(column, "—", 25, INK)

static func euros(cents: float) -> String:
	return "€" + grouped(roundi(cents / 100.0))

static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0: result += ","
		result += digits[i]
	return ("−" if value < 0 else "") + result

func responsive() -> void:
	if inspector == null: return
	var size := get_viewport().get_visible_rect().size
	portrait = size.x < 700 or (size.x < 900 and size.y > size.x * 1.1)
	panel_width = clampf(size.x * 0.33, 340, 450)
	brand.position = Vector2(24, 22)
	title.position = Vector2(24, 42)
	title.add_theme_font_size_override("font_size", 34)
	nav.position = Vector2(24, 104)
	for button in tabs.values(): button.custom_minimum_size.x = 105
	date.position = Vector2(26, 166)
	world_tools.position = Vector2(24, size.y - 208)
	share.position = Vector2(size.x - 222, 28)
	share.size = Vector2(198, 44)
	share.visible = not portrait
	inspector.position = Vector2(size.x - panel_width - 24, 104)
	inspector.size = Vector2(panel_width, maxf(140, size.y - 184))
	summary.position = Vector2(24, size.y - 148)
	summary.size = Vector2(maxf(320, size.x - panel_width - 72), 78)
	summary.visible = not portrait and size.x > 1150
	footer.position = Vector2(24, size.y - 58)
	footer.size = Vector2(maxf(350, size.x - panel_width - 72), 44)
	progress.position = Vector2(size.x - panel_width - 24, size.y - 68)
	progress.size = Vector2(panel_width, 5)
	toast_label.position = Vector2(size.x - panel_width - 24, size.y - 54)
	toast_label.size = Vector2(panel_width, 44)
	collapse_button.visible = portrait
	if portrait:
		brand.position = Vector2(14, 14)
		brand.add_theme_font_size_override("font_size", 10)
		title.position = Vector2(14, 35)
		title.add_theme_font_size_override("font_size", 22)
		nav.position = Vector2(12, 82)
		for button in tabs.values(): button.custom_minimum_size.x = maxf(65, (size.x - 45) / 4)
		date.position = Vector2(14, 134)
		world_tools.position = Vector2(12, 160)
		var top := maxf(270, size.y * 0.39)
		inspector.position = Vector2(12, top)
		inspector.size = Vector2(size.x - 24, maxf(100, size.y - top - 103))
		footer.position = Vector2(12, size.y - 56)
		footer.size = Vector2(size.x - 24, 44)
		for button in [season_button, year_button, pause_button]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.position = Vector2(12, size.y - 64)
		progress.size = Vector2(size.x - 24, 4)
		toast_label.position = Vector2(14, size.y - 95)
		toast_label.size = Vector2(size.x - 28, 29)
		toast_label.add_theme_font_size_override("font_size", 11)
	else:
		brand.add_theme_font_size_override("font_size", 12)
		toast_label.add_theme_font_size_override("font_size", 12)
		for button in [season_button, year_button, pause_button]: button.size_flags_horizontal = Control.SIZE_FILL
		if size.x <= 1150:
			world_tools.position = Vector2(24, size.y - 116)
			for button in tabs.values(): button.custom_minimum_size.x = 80
	inspector.visible = not (portrait and collapsed)
	collapse_button.text = "Details" if collapsed else "Scene"

func show_panel(section: String) -> void:
	if editor != null and is_instance_valid(editor): workshop_text = editor.text
	editor = null
	if section != pane:
		scroll.set_deferred("scroll_vertical", 0)
		collapsed = false
	pane = section
	dynamic.clear()
	chart = null
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for key in tabs: tabs[key].modulate = Color.WHITE if key == pane else Color(1, 1, 1, 0.67)
	match pane:
		"Design": _design()
		"People": _people()
		"Compare": _compare()
		"Workshop": _workshop()
		"Evidence": _evidence()
	refresh()
	responsive.call_deferred()

func open_draft(pack: Dictionary) -> void:
	workshop_text = JSON.stringify(pack, "  ")
	if editor != null and is_instance_valid(editor): editor.text = workshop_text
	show_panel("Workshop")

func _heading(eyebrow: String, heading: String) -> void:
	_label(body, eyebrow, 11, GREEN)
	var label := _label(body, heading, 25, INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _rule() -> void:
	body.add_child(HSeparator.new())

func _select(label: String, family: String, current: String, callback: Callable) -> OptionButton:
	_text(label, INK)
	var option := OptionButton.new()
	option.custom_minimum_size.y = 46
	option.fit_to_longest_item = false
	for item in game.experiment.catalog.list_content(family):
		option.add_item(item.name)
		option.set_item_metadata(option.item_count - 1, item.id)
		if item.id == current: option.select(option.item_count - 1)
	option.item_selected.connect(func(index: int) -> void: callback.call(str(option.get_item_metadata(index))))
	body.add_child(option)
	return option

func _design() -> void:
	var e := game.experiment
	_heading("01  COMPOSE A COMMUNITY", "A different way to live")
	_text("Change a wall or a shared system. Watch a winter, see who struggles, then improve your design.")
	if e.phase != "design":
		_text("This run uses a frozen design. Return to the starting point to make a variation; the last result stays in your notebook.")
		_button(body, "Try another design", func() -> void: action.emit({"type": "reset"}), true)
		return
	for row in [["Settlement", "layouts", "layout"], ["Wall assembly · default for all homes", "assemblies", "assembly"], ["Weather · shared by both alternatives", "climates", "climate"]]:
		var key: String = row[2]
		_select(row[0], row[1], e.design[key], func(id: String) -> void: action.emit({"type": "edit", "key": key, "value": id}))
	var wall := e.catalog.assembly(e.design.assembly)
	_text("Wall U-value %.2f W/m²K · %.0f kg/m²\nConstruction %s · %d homes / %d residents" % [wall.u, wall.mass_kg_m2, euros(e.sim.capital), e.sim.zones.size(), e.sim.zones.size() * 3])
	if not e.design.overrides.is_empty():
		_text("%d home-specific wall variations are retained." % e.design.overrides.size())
		_button(body, "Clear home-specific variations", func() -> void: action.emit({"type": "edit", "key": "overrides", "value": {}}))
	_button(body, "Why these numbers?", func() -> void: show_panel("Evidence"))
	_rule()
	_select("Heating and cooling", "plants", e.design.plant, func(id: String) -> void: action.emit({"type": "edit", "key": "plant", "value": id}))
	_select("Shared bills and capacity allocation", "policies", e.design.policy, func(id: String) -> void: action.emit({"type": "edit", "key": "policy", "value": id}))
	_text("Three property accounts own the homes. A separate utility association operates the equipment, purchases services and collects household bills.")
	_rule()
	_label(body, "RESOURCE CONNECTIONS", 11, GREEN)
	for row in [["Solar panels · kW", "solar_kw", 0, 50, 2], ["Battery · kWh", "battery_kwh", 0, 200, 10], ["Grid connection · kW", "grid_kw", 0, 100, 3], ["Potable water storage · L", "tank_l", 0, 10000, 500], ["Rainwater for flushing · L", "rain_tank_l", 0, 10000, 500], ["Municipal water · L/day", "water_l_day", 0, 10000, 500], ["Wastewater removal · L/day", "sewage_l_day", 0, 10000, 500], ["Bin storage · kg", "waste_kg", 1, 1000, 10], ["Waste pickup · every N days", "pickup_days", 1, 14, 1]]:
		var key: String = row[1]
		var spin := _number(row[0], row[2], row[3], e.design[key], row[4])
		# Apply explicitly so keyboard entry and dragging never rebuild a focused field.
		_button(body, "Apply " + row[0].split(" · ")[0].to_lower(), func() -> void:
			spin.apply()
			action.emit({"type": "edit", "key": key, "value": spin.value}))
	_rule()
	_text("What are you testing?", INK)
	var question_field := LineEdit.new()
	question_field.text = e.question
	question_field.max_length = 200
	question_field.custom_minimum_size.y = 44
	question_field.text_changed.connect(func(value: String) -> void:
		e.question = value
		game.dirty = true)
	body.add_child(question_field)
	_button(body, "Make this the reference design", func() -> void: action.emit({"type": "baseline"}))
	_text("Reference wall: " + e.catalog.definition("assemblies", e.baseline.assembly).name + ". Weather and seed always match.")

func _number(label: String, low: float, high: float, value: float, step: float = 1.0) -> SpinBox:
	_text(label, INK)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.y = 44
	body.add_child(spin)
	return spin

func _people() -> void:
	var e := game.experiment
	_heading("02  FOLLOW THE CONSEQUENCES", "Every home has a story")
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 46
	selector.fit_to_longest_item = false
	for home in e.sim.state.homes: selector.add_item(home.name + " · " + home.id)
	selector.select(game.selected)
	selector.item_selected.connect(func(index: int) -> void: action.emit({"type": "select", "index": index}))
	body.add_child(selector)
	var home: Dictionary = e.sim.state.homes[game.selected]
	var z: Dictionary = e.sim.zones[game.selected]
	_label(body, home.name + " · 3 residents", 19)
	_text("Owner: " + _owner_name(z.owner) + "\nWall: " + e.catalog.definition("assemblies", z.assembly).name)
	dynamic.person = _text("", INK)
	_label(body, "THE SHARED SYSTEMS", 11, GREEN)
	dynamic.systems = _text("", INK)
	_text("Occupied hours below 18°C and above 28°C use this scenario's comfort bands. Household routines and incomes are fixed assumptions, not a demographic forecast.")
	if e.phase == "design":
		_select("Try a wall just for this home", "assemblies", z.assembly, func(id: String) -> void:
			var overrides: Dictionary = e.design.overrides.duplicate(true)
			overrides[z.id] = id
			action.emit({"type": "edit", "key": "overrides", "value": overrides}))
	_rule()
	_label(body, "WHAT TO INVESTIGATE", 11, GREEN)
	dynamic.advice = _text("")
	_rule()
	_label(body, "RECENT COMMUNITY EVENTS", 11, GREEN)
	dynamic.events = _text("")
	_button(body, "See the comparison", func() -> void: show_panel("Compare"))

static func _owner_name(id: String) -> String:
	return {"west": "West co-op", "east": "East property owner", "commons": "Commons trust"}.get(id, id)

func _compare() -> void:
	var e := game.experiment
	_heading("03  LEARN FROM THE YEAR", "What changed?")
	_text(e.question, INK)
	_text("Same households, same weather, same clock. Green is your design; brown is the reference.")
	dynamic.progress = _text("", GREEN)
	_label(body, "Occupied cold person-hours · cumulative", 13, INK)
	chart = CBLabChart.new()
	chart.custom_minimum_size.y = 154
	body.add_child(chart)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 9)
	body.add_child(grid)
	for text_value in ["", "Reference", "Your design"]: _label(grid, text_value, 12, MUTED)
	for row in [["Cold person-hours", "cold_person_hours"], ["Hot person-hours", "hot_person_hours"], ["Construction", "capital_cents"], ["Operating cost", "operating_cents"], ["Imported power", "grid_kwh"], ["Unmet water · L", "water_unserved_l"], ["Sewer overflow · L", "sewage_overflow_l"], ["Unpaid bills", "arrears_cents"], ["Service labor · h", "labor_hours"]]:
		var label := _label(grid, row[0], 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dynamic["ref_" + row[1]] = _label(grid, "—", 13, Color("#947355"))
		dynamic["alt_" + row[1]] = _label(grid, "—", 13, GREEN)
	_rule()
	dynamic.conclusion = _text("", INK)
	_button(body, "Try another design", func() -> void: action.emit({"type": "reset"}), true)
	_button(body, "Export this experiment", func() -> void: action.emit({"type": "export"}))
	_button(body, "Export results as JSON", func() -> void: action.emit({"type": "export", "kind": "results"}))
	_button(body, "Import a friend's experiment", func() -> void: action.emit({"type": "import", "purpose": "experiment"}))
	if not e.notebook.is_empty():
		_rule()
		_label(body, "YOUR EXPERIMENT NOTEBOOK", 11, GREEN)
		for i in e.notebook.size():
			var entry: Dictionary = e.notebook[i]
			_text("Trial %d · %d days\n%s cold person-hours · %s operating cost" % [i + 1, int(entry.report.hour) / 24, grouped(entry.report.cold_person_hours), euros(entry.report.operating_cents)])
	_rule()
	_button(body, "Start fresh (backs up saved experiment)", func() -> void: action.emit({"type": "fresh"}))
	_text("Prototype scope: one year, fixed households, thermal and utility balances. Weather, prices and reference materials are illustrative. Evidence and limitations are always inspectable.")

func _workshop() -> void:
	var e := game.experiment
	_heading("04  MAKE SOMETHING REUSABLE", "Your community workshop")
	_text("Create a wall pack with the form, or edit any supported definition in JSON. The same physics runs every compatible assembly.")
	if e.phase != "design":
		_button(body, "Return to design to add a pack", func() -> void: action.emit({"type": "reset"}))
	_label(body, "REMIX A MATERIAL + WALL", 11, GREEN)
	var id_field := LineEdit.new()
	id_field.text = "my_walls_%d" % e.catalog.packs.size()
	id_field.placeholder_text = "Unique lowercase pack ID"
	id_field.custom_minimum_size.y = 44
	body.add_child(id_field)
	var name_field := LineEdit.new()
	name_field.text = "My warm wall"
	name_field.custom_minimum_size.y = 44
	body.add_child(name_field)
	var fields: Dictionary = {}
	var chosen := e.catalog.definition("materials", "core:insulation")
	var selector := _select("Start from a material", "materials", "core:insulation", func(id: String) -> void:
		var material := e.catalog.definition("materials", id)
		for key in fields: fields[key].value = material[key])
	selector.disabled = false
	var properties: Dictionary = CBLabCatalog.schema["$defs"].materials.properties
	var labels := {"conductivity_w_mk": "Thermal conductivity", "density_kg_m3": "Density", "heat_capacity_j_kgk": "Specific heat capacity", "price_cents_m3": "Material price", "carbon_kg_m3": "Embodied carbon (declared boundary)"}
	for key in labels:
		var spec: Dictionary = properties[key]
		fields[key] = _number(labels[key] + " · " + str(spec.get("description", "")), spec.minimum, spec.maximum, chosen[key], 0.005 if key == "conductivity_w_mk" else 1)
	var thickness := _number("Core layer thickness · m", 0.005, 0.8, 0.16, 0.01)
	var labor := _number("Assembly labor · cents/m²", 0, 50000, 6500, 500)
	_text("The new core sits between two 30 mm timber skins. These fields come from the same schema that validates imported packs. Form-created values are labeled synthetic.")
	_button(body, "Create a draft pack ↓", func() -> void:
		var id := id_field.text.strip_edges()
		if not CBModLoader.valid_pack_id(id):
			toast("Use a unique lowercase ID with letters, numbers and underscores.")
			return
		var material := chosen.duplicate(true)
		material.id = id + ":material"
		material.name = name_field.text.strip_edges() + " material"
		material.evidence = id + ":assumptions"
		for key in fields: material[key] = fields[key].value
		var evidence := {"id": material.evidence, "name": "Workshop assumptions", "status": "synthetic", "source": "", "notes": "Player-authored values. Add sources, measurement conditions and the embodied-carbon boundary before making empirical claims.", "license": "Unspecified", "geography": "Unspecified", "period": "Unspecified"}
		var wall := {"id": id + ":wall", "name": name_field.text.strip_edges(), "layers": [{"material": "core:timber", "thickness_m": 0.03}, {"material": material.id, "thickness_m": thickness.value}, {"material": "core:timber", "thickness_m": 0.03}], "labor_cents_m2": labor.value, "evidence": material.evidence}
		var pack := {"api_version": 2, "model": CBLabCatalog.MODEL, "id": id, "name": name_field.text.strip_edges(), "version": "1.0.0", "dependencies": {"core": "1.0.0"}, "content": {"evidence": [evidence], "materials": [material], "assemblies": [wall]}}
		workshop_text = JSON.stringify(pack, "  ")
		editor.text = workshop_text
		toast("Draft ready below. Review its evidence, then add it to this experiment."))
	_rule()
	_label(body, "DATA PACK · JSON & EVIDENCE", 11, GREEN)
	if workshop_text.is_empty():
		var example_text := JSON.stringify(CBLabCatalog.builtin_packs()[1], "  ")
		workshop_text = example_text.replace("hemp_lab", "my_hemp_%d" % e.catalog.packs.size())
	editor = TextEdit.new()
	editor.text = workshop_text
	editor.custom_minimum_size = Vector2(0, 280)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.add_theme_font_size_override("font_size", 12)
	body.add_child(editor)
	_button(body, "Validate & add to this experiment", func() -> void: action.emit({"type": "install_draft", "text": editor.text}), true).disabled = e.phase != "design"
	_button(body, "Export draft as a mod", func() -> void: action.emit({"type": "export", "kind": "pack", "text": editor.text}))
	_button(body, "Import a data mod", func() -> void: action.emit({"type": "import", "purpose": "pack"}))
	_button(body, "Import hourly weather CSV", func() -> void: action.emit({"type": "import", "purpose": "weather"}))
	_text("Weather CSV: hour,temperature_c,solar_w_m2,rain_mm; 8,760 rows, hours 0–8759. Review source, location, year and license in its evidence record. Imported weather starts unverified.")
	_rule()
	_button(body, "Export schema for editors", func() -> void: action.emit({"type": "export", "kind": "schema"}))
	_button(body, "Export an AI drafting prompt", func() -> void: action.emit({"type": "export", "kind": "prompt"}))
	_text("AI is optional: take the prompt to your preferred assistant, then paste the resulting data. Nothing is sent automatically. Unsupported mechanisms produce errors, not invented simulation effects.")
	_button(body, "Inspect sources & model limits", func() -> void: show_panel("Evidence"))
	_rule()
	_label(body, "EXPERIMENT CONTENT", 11, GREEN)
	for pack in e.catalog.packs: _text(pack.name + " · " + pack.version + "\n" + pack.id + " · " + CBLabCatalog.digest(pack).substr(0, 12))
	_button(body, "Open the evening game", func() -> void: action.emit({"type": "legacy", "mode": "evening"}))
	_button(body, "Open the original sandbox", func() -> void: action.emit({"type": "legacy", "mode": "foundation"}))

func _evidence() -> void:
	_heading("THE ASSUMPTIONS ARE PART OF THE GAME", "Why these numbers?")
	_text("Reference values are synthetic teaching assumptions. Imported source labels are author claims. This release has balance and analytical tests; it has not been calibrated against real communities.", INK)
	for item in game.experiment.catalog.list_content("evidence"):
		_rule()
		_label(body, item.name, 17)
		_text(str(item.status).to_upper() + " · " + item.geography + "\nPeriod: " + item.period)
		_text(item.notes)
		_text("Source: " + (item.source if not item.source.is_empty() else "No empirical source supplied") + "\nLicense: " + item.license)
	_rule()
	_label(body, "MODEL BOUNDARY", 11, GREEN)
	_text("Hourly two-node thermal zones; shared walls exchange heat. Constrained heat/cooling, grid, solar and battery dispatch. Finite potable/rain tanks, wastewater storage and removal, waste bins and collection. Separate property, household and utility accounts.")
	_text("Comfort bands: below 18°C / above 28°C during assumed home occupancy. Water: 80% becomes wastewater, 20% leaves the modeled water system. Rainwater only serves flushing. Sewer storage: 1,000 L. Grid price: €0.35/kWh; water €0.005/L; sewage €0.003/L. Synthetic money assumptions are identical in matched runs.")
	_text("Reference houses are single-level boxes. Declared support checks use assembly mass plus a 150 kg/m² live-load assumption. No living-tree mechanics, detailed structural analysis, ground/moisture model, hydraulic pressure, fire/flood damage, births, migration or century forecasts. Exterior climate acts on exposed roof and floor; imported solar uses a simple window projection.")
	_text("Construction excludes land and financing. Material carbon covers walls under the author's declared boundary, not total building life-cycle emissions. Billing shares grid costs by electricity use or equally; other service costs are shared equally. Arrears remain visible and can delay maintenance.")
	_button(body, "Back to design", func() -> void: show_panel("Design"))

func refresh() -> void:
	if game == null or game.experiment == null: return
	var e := game.experiment
	var s := e.sim.state
	var restoring := e.restore_hour > 0
	lens.select(["materials", "temperature", "owners"].find(game.view.lens))
	date.text = "%s · %d neighbours · %s" % [CBLab.date_label(int(s.hour)), s.homes.size() * 3, "restoring" if restoring else e.phase]
	progress.value = float(s.hour) / maxi(1, e.restore_hour if restoring else e.limit)
	season_button.disabled = restoring or e.phase == "running" or s.hour >= 2160
	year_button.disabled = restoring or e.phase == "running" or s.hour >= 8760
	pause_button.text = {"design": "Undo", "running": "Pause", "paused": "Resume", "complete": "Try again"}.get(e.phase, "Pause")
	pause_button.disabled = restoring or (e.phase == "design" and e.undo.is_empty())
	cold_label.text = grouped(int(s.totals.cold_person_hours)) + " h"
	cost_label.text = euros(s.totals.operating_cents)
	debt_label.text = euros(e.sim.arrears())
	if dynamic.has("person"):
		var home: Dictionary = s.homes[game.selected]
		var original: Dictionary = e.reference.state.homes[game.selected]
		var z: Dictionary = e.sim.zones[game.selected]
		dynamic.person.text = "Inside now · %.1f°C\nOccupied cold hours · %s (reference %s)\nOccupied hot hours · %s\nBills so far · %s\nUnpaid · %s\nDeclared support load · %.0f%%" % [home.air_c, grouped(home.cold_hours), grouped(original.cold_hours), grouped(home.hot_hours), euros(home.billed_cents), euros(home.arrears_cents), z.mass_kg / z.support_kg * 100]
		var plant_status := "waiting for repair funds" if s.awaiting_repair else ("under maintenance" if s.hour < s.repair_until else "available")
		dynamic.systems.text = "Operating reserve · %s\nHeating / cooling · %s\nPotable storage · %.0f / %.0f L\nWastewater backlog · %.0f / 1,000 L\nBins · %.0f / %.0f kg\nStreet litter · %.0f kg\nBattery · %.1f / %.0f kWh\nOwner's remaining capital · %s" % [euros(s.utility_cents), plant_status, s.water_l, e.design.tank_l, s.sewage_l, s.waste_kg, e.design.waste_kg, s.litter_kg, s.battery_kwh, e.design.battery_kwh, euros(s.owners[z.owner])]
		dynamic.advice.text = "Cold hours depend on the envelope, weather, available heating and outages. Try changing just this home's wall, then compare."
		if home.arrears_cents > 0: dynamic.advice.text += "\n\nThis household could not pay all its bills. Its remaining monthly income is limited; compare envelope efficiency and billing policies rather than treating shared funds as household affordability."
		var events := ""
		for event in s.events.slice(maxi(0, s.events.size() - 7)):
			events += CBLab.date_label(event.hour) + " · " + event.title + "\n" + event.detail + "\n\n"
		dynamic.events.text = events
	if chart != null:
		chart.original = e.reference.state.history
		chart.alternative = s.history
		chart.queue_redraw()
	if dynamic.has("progress"):
		dynamic.progress.text = ("Restoring" if restoring else ("Ready to run" if s.hour == 0 else "Comparing")) + " · %d of %d days" % [int(s.hour) / 24, e.limit / 24]
		var left := e.reference.report()
		var right := e.sim.report()
		for key in right:
			if not dynamic.has("ref_" + key): continue
			dynamic["ref_" + key].text = euros(left[key]) if key.ends_with("cents") else grouped(roundi(float(left[key])))
			dynamic["alt_" + key].text = euros(right[key]) if key.ends_with("cents") else grouped(roundi(float(right[key])))
		var delta := int(right.cold_person_hours) - int(left.cold_person_hours)
		dynamic.conclusion.text = "Run a season to see whether your idea helps." if s.hour == 0 else ("Your design has %s %s cold person-hours so far. Construction changes by %s. Inspect households to see who still needs help." % [grouped(absi(delta)), "fewer" if delta <= 0 else "more", euros(right.capital_cents - left.capital_cents)])

func toast(message: String) -> void:
	toast_label.text = message

func show_error(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "This change needs attention"
	dialog.dialog_text = message
	dialog.dialog_autowrap = true
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	var viewport_size := get_viewport().get_visible_rect().size
	dialog.popup_centered(Vector2i(mini(540, int(viewport_size.x) - 40), 200))
