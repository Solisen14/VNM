extends Control

const State = preload("res://reboot_state.gd")
const FlightMap = preload("res://reboot_map.gd")
const GREEN := Color("#9de2b2")
const PALE := Color("#eeeae0")
const MUTED := Color("#a5b6b6")
const AMBER := Color("#efb16d")
const FONT := preload("res://assets/reboot_mono.tres")

const PHASE_PROMPTS := [
	"", "",
	"Zoom out, then back in. Use the mouse wheel or Q / E.",
	"Turn with A / D. Apply forward or reverse thrust with W / S.",
	"Left-click a point in space and let the flight computer take you there.",
	"Calling the Asterion and the mining fleet. Awaiting reply…",
	"Investigate the three signals. Right-click each contact to approach and scan.",
	"Gather ore and recover two spare parts. Return to the damaged miner to repair it.",
	"Miner 031 has rebooted and is selecting a mining worksite.",
	"Miner 031 works autonomously. Watch its chosen asteroid recede from the surface as it carries ore home."
]

var state := State.new()
var map: FlightMap
var selected := ""
var boot: CenterContainer
var boot_text: Label
var designation: LineEdit
var designation_label: Label
var accept_name: Button
var active_hud: PanelContainer
var objective_docked: VBoxContainer
var objective_flight: PanelContainer
var objective_tween: Tween
var inventory: CenterContainer
var inventory_button: Button
var insight_card: PanelContainer
var insight_tree_nodes: Array[Label] = []
var tutorial_briefing := false
var system_label: Label
var prompt: Label
var contact_details: Label
var cargo: Label
var cargo_capacity: ProgressBar
var notice: Label
var research: CenterContainer
var insight_popup: CenterContainer
var insight_open_button: Button
var insight_popup_title: Label
var insight_headline: Label
var insight_description: Label
var work_panel: VBoxContainer
var work_caption: Label
var work_progress: ProgressBar
var research_status: Label
var research_button: Button
var follow_button: Button
var signals_button: Button
var footer: Label
var phase_heading: Label

func _ready() -> void:
	get_window().min_size = Vector2i(900, 600)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 15)
	layout.add_child(panel(header, "#11191b", 11))
	header.add_child(make_label("VNM", 25, PALE))
	system_label = make_label("", 13, GREEN)
	system_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(system_label)
	research_button = make_button(header, "Insight Tree [I]", toggle_research)
	inventory_button = make_button(header, "Cargo [C]", toggle_inventory)
	follow_button = make_button(header, "Follow controller", func() -> void: map.follow_player())
	signals_button = make_button(header, "Frame signals", func() -> void: map.frame_signals())
	make_button(header, "Restart", restart)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	layout.add_child(body)
	var view := Control.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(view)
	map = FlightMap.new()
	map.game = self
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(map)
	build_boot(view)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 310
	side.add_theme_constant_override("separation", 10)
	active_hud = panel(side, "#132521df", 12)
	active_hud.position = Vector2(16, 16)
	view.add_child(active_hud)
	active_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_docked = VBoxContainer.new()
	objective_docked.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(objective_docked)
	phase_heading = make_label("", 14, GREEN)
	phase_heading.add_theme_font_override("font", FONT)
	objective_docked.add_child(phase_heading)
	prompt = paragraph(objective_docked, 16, PALE)
	contact_details = paragraph(side, 14, MUTED)
	work_panel = VBoxContainer.new()
	side.add_child(work_panel)
	work_caption = paragraph(work_panel, 14, GREEN)
	work_progress = ProgressBar.new()
	work_progress.show_percentage = false
	work_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	work_progress.custom_minimum_size.y = 8
	work_panel.add_child(work_progress)
	notice = paragraph(side, 13, GREEN)
	build_research(view)
	build_inventory(view)
	build_insight_popup(view)
	var body_footer := HBoxContainer.new()
	layout.add_child(panel(body_footer, "#11191b", 9))
	footer = make_label("", 13, MUTED)
	body_footer.add_child(footer)
	research.hide()
	designation.grab_focus.call_deferred()
	refresh()

func build_boot(view: Control) -> void:
	boot = CenterContainer.new()
	boot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(boot)
	var terminal := VBoxContainer.new()
	terminal.custom_minimum_size.x = 480
	terminal.add_theme_constant_override("separation", 14)
	boot.add_child(panel(terminal, "#0a1510", 25))
	boot_text = make_label("", 17, GREEN)
	boot_text.add_theme_font_override("font", FONT)
	terminal.add_child(boot_text)
	designation_label = make_label("What is your designation?", 16, GREEN)
	designation_label.add_theme_font_override("font", FONT)
	terminal.add_child(designation_label)
	designation = LineEdit.new()
	designation.placeholder_text = "Enter designation"
	designation.max_length = 20
	designation.add_theme_color_override("font_color", GREEN)
	designation.text_submitted.connect(func(_value: String) -> void: accept_designation())
	terminal.add_child(designation)
	accept_name = make_button(terminal, "Accept designation", accept_designation)

func build_insight_popup(view: Control) -> void:
	insight_popup = CenterContainer.new()
	insight_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	insight_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	view.add_child(insight_popup)
	var message := VBoxContainer.new()
	message.custom_minimum_size.x = 380
	message.add_theme_constant_override("separation", 12)
	insight_card = panel(message, "#192725", 20)
	insight_popup.add_child(insight_card)
	add_scrim(insight_popup)
	insight_popup_title = make_label("FIRST INSIGHT", 13, GREEN)
	message.add_child(insight_popup_title)
	insight_headline = make_label("I can repair the mining drone.", 21, PALE)
	message.add_child(insight_headline)
	insight_description = paragraph(message, 15, MUTED)
	insight_description.text = "Press I to open the Insight Tree and see what Field Repair requires."
	insight_open_button = make_button(message, "Open Insight Tree [I]", open_first_insight)
	insight_popup.hide()

func open_first_insight() -> void:
	var start := insight_card.get_global_rect()
	if not tutorial_briefing:
		if state.salvage_insight_ready and not state.salvage_insight_unlocked:
			state.unlock_salvage()
		inventory.hide()
		research.show()
	insight_popup.hide()
	insight_open_button.release_focus()
	refresh()
	animate_objective(start)

func animate_objective(start: Rect2) -> void:
	finish_objective_animation()
	var target := Rect2(active_hud.global_position, Vector2(active_hud.size.x, objective_docked.size.y + 24))
	var contents := VBoxContainer.new()
	contents.add_child(make_label(phase_heading.text, 14, GREEN))
	paragraph(contents, 16, PALE).text = prompt.text
	objective_flight = panel(contents, "#192725", 10)
	objective_flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(objective_flight)
	objective_flight.global_position = start.position
	objective_flight.size = start.size
	objective_docked.modulate.a = 0.0
	objective_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	objective_tween.tween_property(objective_flight, "global_position", target.position, 0.36)
	objective_tween.tween_property(objective_flight, "size", target.size, 0.36)
	objective_tween.tween_property(objective_flight, "modulate:a", 0.0, 0.17).set_delay(0.19)
	objective_tween.tween_property(objective_docked, "modulate:a", 1.0, 0.17).set_delay(0.19)
	objective_tween.chain().tween_callback(finish_objective_animation)

func finish_objective_animation() -> void:
	if objective_tween and objective_tween.is_running():
		objective_tween.kill()
	if is_instance_valid(objective_flight):
		objective_flight.queue_free()
		objective_flight = null
	objective_docked.modulate.a = 1.0

func show_briefing(title: String, headline: String, description: String, action: String, briefing: bool) -> void:
	finish_objective_animation()
	research.hide()
	inventory.hide()
	tutorial_briefing = briefing
	insight_popup_title.text = title
	insight_headline.text = headline
	insight_description.text = description
	insight_open_button.text = action
	insight_popup.show()
	insight_open_button.grab_focus()

func add_scrim(window: CenterContainer) -> void:
	var shade := ColorRect.new()
	shade.color = Color("#07100db3")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var view := window.get_parent()
	view.add_child(shade)
	view.move_child(shade, window.get_index())
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.visibility_changed.connect(func() -> void: shade.visible = window.visible)

func build_window(view: Control, title: String, width: float, close: Callable, contents: VBoxContainer) -> CenterContainer:
	var window := CenterContainer.new()
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	view.add_child(window)
	add_scrim(window)
	contents.custom_minimum_size.x = width
	contents.add_theme_constant_override("separation", 10)
	window.add_child(panel(contents, "#14231f", 20))
	var heading := HBoxContainer.new()
	contents.add_child(heading)
	var caption := make_label(title, 23, PALE)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption)
	make_button(heading, "Close [Esc]", close)
	window.hide()
	return window

func build_research(view: Control) -> void:
	var contents := VBoxContainer.new()
	research = build_window(view, "Insight Tree", 490, toggle_research, contents)
	for title in ["Field Repair", "Salvage", "Refining & Logistics", "Component Manufacturing", "Drone Construction"]:
		if not insight_tree_nodes.is_empty():
			contents.add_child(make_label("↓", 13, MUTED))
		var node := make_label(title, 16, PALE)
		insight_tree_nodes.append(node)
		contents.add_child(panel(node, "#20332e", 7))
	research_status = paragraph(contents, 14, PALE)

func build_inventory(view: Control) -> void:
	var contents := VBoxContainer.new()
	inventory = build_window(view, "Cargo Inventory", 420, toggle_inventory, contents)
	cargo_capacity = ProgressBar.new()
	cargo_capacity.max_value = State.HOLD
	cargo_capacity.show_percentage = false
	cargo_capacity.custom_minimum_size.y = 7
	contents.add_child(cargo_capacity)
	cargo = paragraph(contents, 14, PALE)

func _physics_process(delta: float) -> void:
	if insight_popup.visible:
		return
	var before := state.phase
	var turn := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var thrust := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	if research.visible or inventory.visible:
		turn = 0.0
		thrust = 0.0
	state.tick(delta, turn, thrust)
	if state.phase != before:
		if state.phase == State.Phase.FLIGHT:
			map.follow_player()
		if state.phase == State.Phase.CONTACTS:
			map.frame_signals()
		match state.phase:
			State.Phase.SENSORS:
				show_briefing("LOCAL SENSORS", "Bring the field into view", PHASE_PROMPTS[state.phase], "Continue", true)
			State.Phase.FLIGHT:
				show_briefing("FLIGHT CONTROL", "Test manual flight", PHASE_PROMPTS[state.phase], "Continue", true)
			State.Phase.WAYFINDING:
				show_briefing("WAYFINDING", "Plot a waypoint", PHASE_PROMPTS[state.phase], "Continue", true)
			State.Phase.CONTACTS:
				show_briefing("SIGNALS DETECTED", "Scan three contacts", PHASE_PROMPTS[state.phase], "Continue", true)
			State.Phase.FIELD_REPAIR:
				show_briefing("FIRST INSIGHT", "I can repair the mining drone.",
					"Collect %d ore and recover %d spare parts to restore Miner 031." % [State.ORE_REQUIRED, State.PARTS_REQUIRED],
					"Open Insight Tree [I]", false)
	if state.salvage_insight_ready and not state.salvage_insight_unlocked and not insight_popup.visible:
		show_briefing("SECOND INSIGHT / SALVAGE", "Why is the ore stockpiling here?",
			"The intake is still receiving ore. The refinery must be buried under the hull. Three dormant workers are close enough to repair.",
			"Open Insight Tree [I]", false)
	refresh()
	map.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_I and not event.echo:
			toggle_research()
		elif event.physical_keycode == KEY_C and not event.echo:
			toggle_inventory()
		elif event.physical_keycode == KEY_ESCAPE and not event.echo:
			if research.visible:
				toggle_research()
			elif inventory.visible:
				toggle_inventory()
		elif not (insight_popup.visible or research.visible or inventory.visible):
			if event.physical_keycode == KEY_Q:
				map.set_zoom(1.0 / 1.10, map.size * 0.5)
			elif event.physical_keycode == KEY_E:
				map.set_zoom(1.10, map.size * 0.5)

func accept_designation() -> void:
	if state.begin(designation.text):
		designation.release_focus()
		accept_name.release_focus()

func left_command(point: Vector2) -> void:
	if not (insight_popup.visible or research.visible or inventory.visible) and state.phase >= State.Phase.WAYFINDING:
		state.plot_move(point)
		map.following = true

func right_command(contact: String) -> void:
	if insight_popup.visible or research.visible or inventory.visible or not state.is_visible(contact):
		return
	selected = contact
	var action := state.command_for(contact)
	state.issue(contact)
	if not action.is_empty() and state.has_destination:
		map.following = true
	refresh()

func toggle_research() -> void:
	if insight_popup.visible:
		if not tutorial_briefing:
			open_first_insight()
	elif state.phase >= State.Phase.FIELD_REPAIR:
		inventory.hide()
		research.visible = not research.visible

func toggle_inventory() -> void:
	if not insight_popup.visible and state.phase >= State.Phase.FIELD_REPAIR:
		research.hide()
		inventory.visible = not inventory.visible

func restart() -> void:
	state = State.new()
	selected = ""
	map.reset_view()
	designation.clear()
	insight_popup.hide()
	research.hide()
	inventory.hide()
	finish_objective_animation()
	refresh()
	designation.grab_focus()

func refresh() -> void:
	var phase := state.phase
	var early := phase < State.Phase.SENSORS
	boot.visible = early
	research_button.visible = phase >= State.Phase.FIELD_REPAIR
	inventory_button.visible = phase >= State.Phase.FIELD_REPAIR
	active_hud.visible = not early and not insight_popup.visible
	follow_button.visible = not early
	signals_button.visible = phase >= State.Phase.CONTACTS
	system_label.text = "  /  CONTROLLER SYSTEMS" if state.name_text.is_empty() else "  /  %s" % state.name_text.to_upper()
	if early:
		refresh_boot()
		footer.text = ""
		return
	var stages := ["", "", "LOCAL SENSORS ONLINE", "FLIGHT CONTROL ONLINE", "WAYFINDING ONLINE", "COMMUNICATIONS ONLINE",
		"UNRESOLVED SIGNALS", "FIELD REPAIR", "MINER 031 ONLINE", "AUTONOMOUS MINING"]
	phase_heading.text = stages[phase]
	prompt.text = PHASE_PROMPTS[phase]
	if phase == State.Phase.CONTACTS:
		prompt.text = "Scan contacts  %d / %d" % [state.scanned.size(), State.PRIMARY.size()]
	elif phase == State.Phase.FIELD_REPAIR:
		if state.ore >= State.ORE_REQUIRED and state.parts >= State.PARTS_REQUIRED:
			prompt.text = "Repair Miner 031"
		else:
			prompt.text = "Collect %d ore  ·  %d / %d\nRecover spare parts  ·  %d / %d" % [
				State.ORE_REQUIRED, mini(state.ore, State.ORE_REQUIRED), State.ORE_REQUIRED, state.parts, State.PARTS_REQUIRED]
	if phase == State.Phase.HAULING and not state.salvage_insight_ready:
		prompt.text = "Watch Miner 031 deliver ore  ·  %d / 5 runs" % state.deliveries
	if state.salvage_insight_ready and not state.salvage_insight_unlocked:
		prompt.text = "Five deliveries confirmed at the Asterion's former ore intake. A new Insight is available."
	if state.salvage_insight_unlocked:
		if state.active_drones > 1:
			prompt.text = "Expose the refinery  ·  %d / %d hull" % [state.hull_extracted, State.REFINERY_EXPOSURE]
		elif state.repair_kits > 0:
			prompt.text = "Repair a dormant salvager"
		else:
			prompt.text = "Collect repair supplies at the intake\nRequires 2 Fe + 1 Cu"
	if state.refinery_exposed:
		prompt.text = "Refinery exposed  ·  %d / %d hull" % [state.hull_extracted, State.REFINERY_EXPOSURE]
	var controls := "Scroll / Q and E to zoom"
	if phase >= State.Phase.FLIGHT:
		controls += "   ·   A/D turn   ·   W/S thrust"
	if phase >= State.Phase.WAYFINDING:
		controls += "   ·   Left-click to fly"
	if phase >= State.Phase.CONTACTS:
		controls += "   ·   Right-click contacts"
	footer.text = controls
	contact_details.visible = not selected.is_empty()
	contact_details.text = ""
	if not selected.is_empty():
		contact_details.text = "%s" % state.contact_name(selected)
		var available := state.command_for(selected)
		if not available.is_empty():
			contact_details.text += "\nRight-click · %s" % available
	work_panel.visible = not state.work_action.is_empty()
	if work_panel.visible:
		var progress := state.work_fraction() * 100.0
		work_caption.text = "%s   %d%%" % [State.WORK_LABELS[state.work_action], mini(99, floori(progress))]
		work_progress.value = progress
	cargo_capacity.value = state.controller_load()
	cargo.text = "CONTROLLER CARGO   %d / %d\nRaw ore ×%d   ·   Spare parts ×%d\nRepair supplies ×%d" % [
		state.controller_load(), State.HOLD, state.ore, state.parts, state.repair_kits
	]
	cargo.text += "\nFe %d  ·  Cu %d  ·  Si %d in raw cargo" % [state.cargo_fe, state.cargo_cu, state.cargo_si]
	if phase >= State.Phase.HAULING:
		var unmined: Dictionary = state.field_remaining_material()
		cargo.text += "\n\nORE FIELD 01   RAW MATTER\nFe %d  ·  Cu %d  ·  Si %d remaining" % [
			int(unmined["Fe"]), int(unmined["Cu"]), int(unmined["Si"])
		]
		cargo.text += "\n\nASTERION INTAKE CACHE  (%d units)\nFe %d  ·  Cu %d  ·  Si %d\nOre runs %d  ·  Miner cargo %d" % [
			state.stock_ore, state.stock_fe, state.stock_cu, state.stock_si,
			state.deliveries, state.miner_cargo
		]
		cargo.text += "\n\nWORKER NETWORK  %d / %d\nRange %d world units\n%s\n%s" % [
			state.active_drones, State.DRONE_CAPACITY, int(State.COMMS_RANGE),
			state.link_status(), state.miner_status()
		]
		if state.salvage_insight_unlocked:
			var restored := 0
			for worker in state.salvage_workers:
				if bool(worker["active"]):
					restored += 1
			cargo.text += "\n\nASTERION SALVAGE\nWorkers %d / 3  ·  Hull %d / %d\nFeedstock delivered ×%d" % [
				restored, state.hull_extracted, State.REFINERY_EXPOSURE, state.hull_stock
			]
	notice.text = state.notice if state.notice_time > 0 else ""
	notice.visible = not notice.text.is_empty()
	insight_tree_nodes[0].text = "Field Repair  ·  %s" % ("Complete" if phase >= State.Phase.HAULING else "Available")
	insight_tree_nodes[1].text = "Salvage  ·  %s" % ("Unlocked" if state.salvage_insight_unlocked else "Requires 5 miner deliveries")
	insight_tree_nodes[2].text = "Refining & Logistics  ·  %s" % ("Refinery exposed" if state.refinery_exposed else "Locked")
	insight_tree_nodes[3].text = "Component Manufacturing  ·  Locked"
	insight_tree_nodes[4].text = "Drone Construction  ·  Locked"
	research_status.text = "Ore   %d / %d\nSpare parts   %d / %d\nRepair the damaged miner" % [state.ore, State.ORE_REQUIRED, state.parts, State.PARTS_REQUIRED]
	if phase >= State.Phase.HAULING:
		research_status.text = "Field Repair complete · Miner 031 online.\nSalvage threshold: %d / 5 deliveries." % mini(5, state.deliveries)
		if state.salvage_insight_unlocked:
			research_status.text = "Salvage unlocked. Three repairable workers detected.\nRecovered hull material: %d / %d units." % [
				state.hull_extracted, State.REFINERY_EXPOSURE
			]
			if state.refinery_exposed:
				research_status.text += "\nRefinery exposed. Structural recovery is still locked."

func refresh_boot() -> void:
	var waiting := state.phase == State.Phase.SAFE_MODE
	designation.visible = waiting
	designation_label.visible = waiting
	accept_name.visible = waiting
	if waiting:
		accept_name.disabled = designation.text.strip_edges().is_empty()
		var line := "PRIMARY BOOT FAILED"
		if int(state.phase_time * 3.0) % 7 == 1 and state.phase_time < 5.0:
			line = "PRIM▲RY BO#T FAI_ED"
		boot_text.text = "WATCHDOG RESET\n%s\nSAFE MODE ACTIVE" % line
		return
	boot_text.text = "DESIGNATION ACCEPTED\n"
	if state.phase_time >= 0.45:
		boot_text.text += "FRAME STRESS DETECTED\nLONG-RANGE ARRAY DAMAGED\n"
	if state.phase_time >= 1.35:
		boot_text.text += "\nMOTHERSHIP UPLINK\nMCV ASTERION   /   NO RESPONSE"
	if state.phase_time >= 2.25:
		boot_text.text += "\n\nRECOVERING LOCAL SENSORS…"

func panel(contents: Control, surface: String, padding: int) -> PanelContainer:
	var control := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(surface)
	style.border_color = Color("#466257")
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(edge, padding)
	control.add_theme_stylebox_override("panel", style)
	control.add_child(contents)
	return control

func make_label(message: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func paragraph(parent: Container, font_size: int, color: Color) -> Label:
	var label := make_label("", font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func make_button(parent: Container, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
