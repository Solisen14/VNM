extends Control

const Simulation = preload("res://simulation.gd")
const Opening = preload("res://opening.gd")
const MAP_SCRIPT = preload("res://system_map.gd")
const CYAN := Color("#76e5ec")
const GOLD := Color("#f5bd76")
const MUTED := Color("#9aafc4")
const WHITE := Color("#edf6ff")

var sim := Simulation.new()
var opening := Opening.new()
var intro_active := true
var casualty_selection := -1
var map: Control
var stocks: Label
var objective: Label
var casualties_label: Label
var intro_button: Button
var insight_button: Button
var fabricator_button: Button
var inventory: Label
var field_option: OptionButton
var founder_panel: VBoxContainer
var founder_choice: OptionButton
var founder_sliders: Array[HSlider] = []
var founder_values: Array[Label] = []
var template_panel: VBoxContainer
var factory_button: Button
var relay_button: Button
var toggle_relay_button: Button
var apply_button: Button
var placement_status: Label
var generation_label: Label
var sliders: Array[HSlider] = []
var slider_labels: Array[Label] = []
var detail: Label
var zoom_label: Label
var speed_button: Button
var pause_button: Button
var speed := 1
var paused := false
var selected := -1
var placement := ""
var accumulator := 0.0

func _ready() -> void:
	get_window().min_size = Vector2i(960, 680)
	theme = build_theme()
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(section(header, Color("#111b2a"), 15))
	var title := label("THE FIRST FIVE", 25, WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	stocks = label("", 15, WHITE)
	header.add_child(stocks)
	pause_button = button(header, "Pause", toggle_pause)
	speed_button = button(header, "1×", cycle_speed)
	button(header, "Restart", restart)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	map = MAP_SCRIPT.new()
	map.game = self
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(map)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 330
	side.add_theme_constant_override("separation", 7)
	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.add_child(side)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(section(scroller, Color("#101a29"), 15))

	side.add_child(label("DIRECTIVE", 13, CYAN))
	objective = paragraph(side, "")
	intro_button = button(side, "Skip intro", finish_intro)
	casualties_label = paragraph(side, "", 13, MUTED)
	insight_button = button(side, "Insight · Coordinate the Five", salvage)
	fabricator_button = button(side, "Restore maintenance fabricator", restore_fabricator)
	factory_button = button(side, "Place factory · 3 frames + 2 modules", begin_placement.bind("factory"))
	relay_button = button(side, "Place relay · 1 frame", begin_placement.bind("relay"))
	toggle_relay_button = button(side, "Take relay offline", toggle_relay)
	placement_status = paragraph(side, "", 13, GOLD)
	inventory = paragraph(side, "", 14)
	field_option = OptionButton.new()
	field_option.add_item("Mining target · nearest")
	field_option.add_item("Mining target · inner field")
	field_option.add_item("Mining target · outer field")
	field_option.item_selected.connect(func(index: int) -> void: sim.mine_field = index - 1)
	side.add_child(field_option)

	founder_panel = VBoxContainer.new()
	side.add_child(founder_panel)
	founder_panel.add_child(HSeparator.new())
	founder_panel.add_child(label("THE FOUNDERS", 13, CYAN))
	founder_choice = OptionButton.new()
	for i in range(5):
		founder_choice.add_item("Founder %d" % (i + 1))
	founder_choice.item_selected.connect(load_founder)
	founder_panel.add_child(founder_choice)
	for action in ["Mine", "Haul", "Service", "Salvage", "Restore"]:
		add_priority(founder_panel, action, founder_sliders, founder_values)
	for slider in founder_sliders:
		slider.value_changed.connect(update_founder)

	template_panel = VBoxContainer.new()
	side.add_child(template_panel)
	template_panel.add_child(HSeparator.new())
	template_panel.add_child(label("ORDERS FOR NEW DRONES", 13, CYAN))
	generation_label = paragraph(template_panel, "", 13, MUTED)
	for action in ["Mine", "Haul", "Service"]:
		add_priority(template_panel, action, sliders, slider_labels)
	apply_button = button(template_panel, "Apply template", apply_template)

	side.add_child(HSeparator.new())
	side.add_child(label("DRONE TELEMETRY", 13, CYAN))
	detail = paragraph(side, "", 14, WHITE)
	detail.custom_minimum_size.y = 84

	var footer := HBoxContainer.new()
	layout.add_child(section(footer, Color("#111b2a"), 10))
	var controls := label("Scroll to zoom   ·   Drag to pan   ·   Click to inspect   ·   Esc cancels placement", 14, MUTED)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(controls)
	zoom_label = label("", 14, CYAN)
	footer.add_child(zoom_label)
	button(footer, "Recenter", map.recenter)
	reset_sliders()
	load_founder(0)
	refresh()

func add_priority(parent: VBoxContainer, action: String, controls: Array[HSlider], readings: Array[Label]) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var heading := label(action, 14, WHITE)
	heading.custom_minimum_size.x = 60
	row.add_child(heading)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	controls.append(slider)
	var reading := label("", 14, GOLD)
	reading.custom_minimum_size.x = 29
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(reading)
	readings.append(reading)

func load_founder(index: int) -> void:
	var drone := sim.drones[index]
	var values := [drone.weights.x, drone.weights.y, drone.weights.z, drone.salvage_priority, drone.restore_priority]
	for i in range(founder_sliders.size()):
		founder_sliders[i].set_value_no_signal(values[i])
		founder_values[i].text = str(values[i])

func update_founder(_value: float) -> void:
	if not sim.refinery:
		return
	var drone := sim.drones[founder_choice.selected]
	drone.weights = Vector3i(int(founder_sliders[0].value), int(founder_sliders[1].value), int(founder_sliders[2].value))
	drone.salvage_priority = int(founder_sliders[3].value)
	drone.restore_priority = int(founder_sliders[4].value)
	for i in range(founder_sliders.size()):
		founder_values[i].text = str(int(founder_sliders[i].value))

func section(child: Control, fill: Color, padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(edge, padding)
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(child)
	return panel

func build_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 14
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#23364a")
		style.set_corner_radius_all(5)
		style.set_border_width_all(1)
		style.border_color = Color("#38556a")
		style.content_margin_left = 11
		style.content_margin_right = 11
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		match state:
			"hover", "pressed":
				style.bg_color = Color("#304e63")
				style.border_color = CYAN
			"disabled":
				style.bg_color = Color("#182435")
				style.border_color = Color("#273749")
			"focus":
				style.bg_color = Color.TRANSPARENT
				style.border_color = CYAN
		result.set_stylebox(state, "Button", style)
	result.set_color("font_color", "Button", WHITE)
	result.set_color("font_disabled_color", "Button", MUTED.darkened(0.23))
	return result

func label(message: String, font_size: int, tint: Color) -> Label:
	var control := Label.new()
	control.text = message
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", tint)
	return control

func paragraph(parent: Control, message: String, font_size := 15, tint := WHITE) -> Label:
	var control := label(message, font_size, tint)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)
	return control

func button(parent: Control, title: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = title
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func _process(delta: float) -> void:
	if not paused:
		accumulator += minf(delta, 0.15) * (1 if intro_active else speed)
		while accumulator >= 0.05:
			accumulator -= 0.05
			opening.advance(0.05)
			if intro_active:
				if opening.time >= Opening.HANDOFF_AT:
					finish_intro()
			else:
				sim.tick(0.05)
	refresh()
	map.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		placement = ""

func refresh() -> void:
	stocks.text = "ORE IN BUFFER  %d      ACTIVE DRONES  %d" % [sim.ore_buffer[0] + sim.ore_buffer[1], sim.drones.size()]
	if intro_active:
		if opening.time < Opening.RECALL_AT:
			stocks.text = "FLEET ONLINE  %d" % Opening.FLEET_SIZE
			objective.text = "Human mining vessel  ·  Ore transfer in progress."
		elif opening.time < Opening.BLAST_AT:
			stocks.text = "FLEET RECALL  %d" % Opening.FLEET_SIZE
			objective.text = "Fleet recall in progress. All drones return to dock for departure."
		else:
			stocks.text = "SURVIVORS  5"
			objective.text = "Reactor breach. Ship signal lost. Five mining drones remain operational."
	elif not sim.insight:
		objective.text = "The ship is gone. The five are still mining. Wait for their holds to fill."
	elif not sim.refinery:
		objective.text = "All holds full. Coordinate the Five and bring the ship’s refinery online."
	elif not sim.fabricator:
		objective.text = "Raise a founder’s Salvage priority to recover intact parts. Spend one control module to restore the wreck’s fabricator."
	elif not sim.factory:
		objective.text = "Build a factory with 3 frames and 2 control modules. Founders with Restore priority can spend stored modules to revive old miners."
	elif sim.generation == 1:
		objective.text = "Apply a template under Orders for New Drones. Haulers will deliver components for continuous assembly."
	elif not sim.outer_seen:
		objective.text = "Place a relay near the right edge of sensor range to discover ore richer in copper and silicon."
	else:
		objective.text = "Choose an ore field to supply the components your factory needs."
	intro_button.visible = intro_active
	casualties_label.visible = intro_active and not opening.casualties.is_empty()
	if intro_active and casualties_label.visible:
		casualties_label.text = "%d destroyed in blast · %d disabled" % [opening.destroyed, opening.disabled]
	insight_button.visible = not intro_active and not sim.refinery
	insight_button.disabled = not sim.insight
	factory_button.visible = not intro_active and not sim.factory
	factory_button.disabled = not sim.can_build_factory()
	fabricator_button.visible = sim.refinery and not sim.fabricator
	fabricator_button.disabled = sim.modules == 0
	fabricator_button.text = "Restore fabricator · 1 control module"
	relay_button.visible = sim.refinery
	relay_button.disabled = not sim.relay and sim.frames < Simulation.RELAY_COST
	relay_button.text = "Move sensor relay" if sim.relay else "Place relay · 1 frame"
	toggle_relay_button.visible = sim.relay
	toggle_relay_button.text = "Take relay offline" if sim.relay_online else "Bring relay online"
	founder_panel.visible = sim.refinery
	template_panel.visible = sim.factory
	inventory.visible = sim.refinery
	inventory.text = "WRECK STORAGE\nIron %d  ·  Carbon %d\nCopper %d  ·  Silicon %d\nFrames %d  ·  Control modules %d" % [
		sim.elements.x, sim.elements.y, sim.elements.z, sim.elements.w, sim.frames, sim.modules
	]
	field_option.visible = sim.outer_seen
	field_option.set_item_disabled(2, not sim.in_coverage(Simulation.OUTER))
	var draft := priorities()
	var has_template := sim.generation > 1
	var has_changes := not has_template or draft != sim.latest_weights
	apply_button.disabled = not sim.factory or not has_changes or draft == Vector3i.ZERO
	apply_button.text = "Apply template" if has_changes else "Template applied"
	for i in range(sliders.size()):
		slider_labels[i].text = str(int(sliders[i].value))
		sliders[i].editable = sim.factory
	var template_status := "Draft Gen %d · Relative weights" % (sim.generation + 1)
	if has_template:
		template_status = "Active Gen %d · %d / %d / %d" % [
			sim.generation, sim.latest_weights.x, sim.latest_weights.y, sim.latest_weights.z
		]
		if has_changes:
			template_status += " · Draft Gen %d" % (sim.generation + 1)
	generation_label.text = "%s\nFactory stock · %d frames / %d modules\n%s" % [
		template_status, sim.factory_frames, sim.factory_modules, sim.factory_status()
	]
	if not placement.is_empty():
		var problem := sim.place_error(placement, map.world_point(map.get_local_mouse_position()))
		placement_status.text = "Click a site on the map." if problem.is_empty() else problem
	else:
		placement_status.text = ""
	zoom_label.text = "%d%%" % roundi(map.zoom * 100.0)
	refresh_detail()

func refresh_detail() -> void:
	if casualty_selection >= 0:
		var contact := opening.casualties[casualty_selection]
		if contact.removed:
			detail.text = "Recovered contact · Drone %03d" % contact.id
		elif not sim.in_coverage(contact.position):
			detail.text = "Contact lost · Outside sensor range"
		elif contact.kind == "disabled":
			detail.text = "Drone %03d · Disabled\nA founder can restore this drone with 1 control module." % contact.id
		else:
			detail.text = "Drone %03d · Destroyed\nSalvage yield: %s." % [contact.id, "frame" if contact.id % 2 == 0 else "control module"]
		return
	if intro_active:
		detail.text = "Monitoring fleet traffic."
		return
	if selected < 0 or selected >= sim.drones.size():
		detail.text = "Click a visible drone to see its inherited priorities and current order."
		return
	var drone := sim.drones[selected]
	if not sim.in_coverage(drone.position):
		detail.text = "Drone %02d · Signal lost\nCurrent telemetry unavailable." % drone.id
		return
	var lineage := "Gen %d" % drone.generation
	if drone.founder > 0:
		lineage = "Founder %d" % drone.founder
	elif drone.restored:
		lineage = "Restored · Original orders"
	detail.text = "Drone %03d · %s\n%s · Wear %d%%\nOre %d/%d · Frames %d · Modules %d\nMine %d / Haul %d / Service %d\n%s" % [
		drone.id, lineage, drone.order, roundi(100.0 - drone.condition),
		drone.ore, Simulation.CAPACITY, drone.frames, drone.modules,
		drone.weights.x, drone.weights.y, drone.weights.z, drone.reason
	]

func priorities() -> Vector3i:
	return Vector3i(int(sliders[0].value), int(sliders[1].value), int(sliders[2].value))

func reset_sliders() -> void:
	for i in range(sliders.size()):
		sliders[i].value = Simulation.ORIGINAL[i]

func salvage() -> void:
	if sim.insight:
		sim.refinery = true

func restore_fabricator() -> void:
	if sim.refinery and not sim.fabricator and sim.modules > 0:
		sim.modules -= 1
		sim.fabricator = true

func begin_placement(kind: String) -> void:
	placement = kind if placement != kind else ""

func toggle_relay() -> void:
	sim.relay_online = not sim.relay_online
	sim.update_discovery()

func apply_template() -> void:
	sim.apply_template(priorities())

func cycle_speed() -> void:
	speed = 2 * speed if speed < 4 else 1
	speed_button.text = "%d×" % speed

func toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Resume" if paused else "Pause"

func finish_intro() -> void:
	if not intro_active:
		return
	if opening.casualties.is_empty():
		opening.time = Opening.BLAST_AT
		opening.resolve_blast()
	opening.advance(maxf(0.0, Opening.HANDOFF_AT - opening.time))
	for i in range(sim.drones.size()):
		var drone := sim.drones[i]
		drone.position = opening.survivors[i]
		drone.id = opening.survivor_ids[i]
		sim.set_order(drone, "Mine", Simulation.INNER, "Original mining directive")
	sim.contacts = opening.casualties
	sim.next_drone_id = Opening.FLEET_SIZE + 1
	intro_active = false
	map.recenter()

func restart() -> void:
	sim = Simulation.new()
	opening = Opening.new()
	intro_active = true
	casualty_selection = -1
	paused = false
	pause_button.text = "Pause"
	selected = -1
	placement = ""
	accumulator = 0.0
	reset_sliders()
	founder_choice.select(0)
	load_founder(0)
	field_option.select(0)
	map.recenter()
