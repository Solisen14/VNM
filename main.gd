extends Control

const Simulation = preload("res://simulation.gd")
const MAP_SCRIPT = preload("res://system_map.gd")
const CYAN := Color("#76e5ec")
const GOLD := Color("#f5bd76")
const MUTED := Color("#9aafc4")
const WHITE := Color("#edf6ff")

var sim := Simulation.new()
var map: Control
var stocks: Label
var objective: Label
var insight_button: Button
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
	side.custom_minimum_size.x = 292
	side.add_theme_constant_override("separation", 7)
	var scroller := ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.add_child(side)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(section(scroller, Color("#101a29"), 15))

	side.add_child(label("DIRECTIVE", 13, CYAN))
	objective = paragraph(side, "")
	insight_button = button(side, "Insight · Salvage the refinery", salvage)
	factory_button = button(side, "Place factory  ·  %d metal" % Simulation.FACTORY_COST, begin_placement.bind("factory"))
	relay_button = button(side, "Place relay  ·  %d metal" % Simulation.RELAY_COST, begin_placement.bind("relay"))
	toggle_relay_button = button(side, "Take relay offline", toggle_relay)
	placement_status = paragraph(side, "", 13, GOLD)

	side.add_child(HSeparator.new())
	side.add_child(label("ORDERS FOR NEW DRONES", 13, CYAN))
	generation_label = paragraph(side, "", 13, MUTED)
	for action in ["Mine", "Deliver", "Repair"]:
		var row := HBoxContainer.new()
		side.add_child(row)
		var action_label := label(action, 14, WHITE)
		action_label.custom_minimum_size.x = 57
		row.add_child(action_label)
		var slider := HSlider.new()
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		sliders.append(slider)
		var value := label("", 14, GOLD)
		value.custom_minimum_size.x = 29
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		slider_labels.append(value)
	apply_button = button(side, "Apply template", apply_template)

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
	refresh()

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
		accumulator += minf(delta, 0.15) * speed
		while accumulator >= 0.05:
			accumulator -= 0.05
			sim.tick(0.05)
	refresh()
	map.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		placement = ""

func refresh() -> void:
	stocks.text = "ORE IN BUFFER  %d      METAL AT WRECK  %d      DRONES  %d" % [
		sim.ore_buffer, sim.metal, sim.drones.size()
	]
	if not sim.insight:
		objective.text = "The ship is gone. The five are still mining. Wait for their holds to fill."
	elif not sim.refinery:
		objective.text = "All holds full. Ship intake offline. The processing bay still responds."
	elif not sim.factory:
		objective.text = "The refinery is running. Refine enough metal to place a drone factory."
	elif sim.generation == 1:
		objective.text = "Set priorities and apply a template. The factory will keep making drones as metal arrives."
	elif sim.drones.size() == 5:
		objective.text = "The five are supplying the factory for its first build."
	elif not sim.outer_seen:
		objective.text = "A new generation is active. Place a relay near the eastern edge of your sensor range."
	else:
		objective.text = "Outer ore field charted. Take the relay offline to see how the map handles lost telemetry."
	insight_button.visible = not sim.refinery
	insight_button.disabled = not sim.insight
	factory_button.visible = not sim.factory
	factory_button.disabled = not sim.refinery or sim.metal < Simulation.FACTORY_COST
	relay_button.disabled = not sim.refinery or (not sim.relay and sim.metal < Simulation.RELAY_COST)
	relay_button.text = "Move sensor relay" if sim.relay else "Place relay  ·  %d metal" % Simulation.RELAY_COST
	toggle_relay_button.visible = sim.relay
	toggle_relay_button.text = "Take relay offline" if sim.relay_online else "Bring relay online"
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
	generation_label.text = "%s\nFactory metal  %d  ·  %d per drone\n%s" % [
		template_status, sim.factory_metal, Simulation.DRONE_COST, sim.factory_status()
	]
	if not placement.is_empty():
		var problem := sim.place_error(placement, map.world_point(map.get_local_mouse_position()))
		placement_status.text = "Click a site on the map." if problem.is_empty() else problem
	else:
		placement_status.text = ""
	zoom_label.text = "%d%%" % roundi(map.zoom * 100.0)
	refresh_detail()

func refresh_detail() -> void:
	if selected < 0 or selected >= sim.drones.size():
		detail.text = "Click a visible drone to see its inherited priorities and current order."
		return
	var drone := sim.drones[selected]
	if not sim.in_coverage(drone.position):
		detail.text = "Drone %02d · Signal lost\nCurrent telemetry unavailable." % drone.id
		return
	detail.text = "Drone %02d · Gen %d · %s\nOre %d/%d  ·  Metal %d  ·  Wear %d%%\nMine %d  /  Deliver %d  /  Repair %d\n%s" % [
		drone.id, drone.generation, drone.order, drone.ore, Simulation.CAPACITY,
		drone.cargo_metal, roundi(100.0 - drone.condition),
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

func restart() -> void:
	sim = Simulation.new()
	selected = -1
	placement = ""
	accumulator = 0.0
	reset_sliders()
	map.recenter()
