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
	"Right-click the ore field to assign Miner 031 its first haul.",
	"Miner 031 is working the field. Watch it deliver ore to the wreck stockpile."
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
var system_label: Label
var prompt: Label
var contact_details: Label
var cargo: Label
var notice: Label
var research: PanelContainer
var insight_popup: CenterContainer
var insight_open_button: Button
var work_panel: VBoxContainer
var work_caption: Label
var work_progress: ProgressBar
var research_title: Label
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
	research_button = make_button(header, "Insights [I]", toggle_research)
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
	build_insight_popup(view)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 282
	side.add_theme_constant_override("separation", 10)
	active_hud = panel(side, "#141c1f", 15)
	body.add_child(active_hud)
	phase_heading = make_label("", 14, GREEN)
	side.add_child(phase_heading)
	prompt = paragraph(side, 16, PALE)
	side.add_child(HSeparator.new())
	contact_details = paragraph(side, 14, MUTED)
	work_panel = VBoxContainer.new()
	side.add_child(work_panel)
	work_caption = paragraph(work_panel, 14, GREEN)
	work_progress = ProgressBar.new()
	work_progress.show_percentage = false
	work_progress.custom_minimum_size.y = 8
	work_panel.add_child(work_progress)
	cargo = paragraph(side, 14, PALE)
	notice = paragraph(side, 13, GREEN)
	build_research(side)
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
	message.custom_minimum_size.x = 320
	message.add_theme_constant_override("separation", 12)
	insight_popup.add_child(panel(message, "#192725", 18))
	message.add_child(make_label("FIRST INSIGHT", 13, GREEN))
	message.add_child(make_label("I can repair the mining drone.", 21, PALE))
	var instruction := paragraph(message, 15, MUTED)
	instruction.text = "Press I to open the Insight Tree and see what Field Repair requires."
	insight_open_button = make_button(message, "Open Insight Tree [I]", open_first_insight)
	insight_popup.hide()

func open_first_insight() -> void:
	insight_popup.hide()
	research.show()
	insight_open_button.release_focus()
	refresh()

func build_research(side: VBoxContainer) -> void:
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 8)
	research = panel(contents, "#202a2a", 10)
	side.add_child(research)
	contents.add_child(make_label("INSIGHT TREE", 12, GREEN))
	research_title = make_label("◆  Field Repair", 19, PALE)
	contents.add_child(research_title)
	research_status = paragraph(contents, 14, PALE)

func _physics_process(delta: float) -> void:
	if insight_popup.visible:
		return
	var before := state.phase
	var turn := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var thrust := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
	state.tick(delta, turn, thrust)
	if state.phase != before:
		if state.phase == State.Phase.FLIGHT:
			map.follow_player()
		if state.phase == State.Phase.CONTACTS:
			map.frame_signals()
		if state.phase == State.Phase.FIELD_REPAIR:
			insight_popup.show()
			insight_open_button.grab_focus()
	refresh()
	map.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.physical_keycode == KEY_Q:
			map.set_zoom(1.0 / 1.10, map.size * 0.5)
		elif event.physical_keycode == KEY_E:
			map.set_zoom(1.10, map.size * 0.5)
		elif event.physical_keycode == KEY_I and not event.echo:
			toggle_research()

func accept_designation() -> void:
	if state.begin(designation.text):
		designation.release_focus()
		accept_name.release_focus()

func left_command(point: Vector2) -> void:
	if not insight_popup.visible and state.phase >= State.Phase.WAYFINDING:
		state.plot_move(point)
		map.following = true

func right_command(contact: String) -> void:
	if insight_popup.visible or not state.is_visible(contact):
		return
	selected = contact
	var action := state.command_for(contact)
	state.issue(contact)
	if not action.is_empty() and state.has_destination:
		map.following = true
	refresh()

func toggle_research() -> void:
	if insight_popup.visible:
		open_first_insight()
	elif state.phase >= State.Phase.FIELD_REPAIR:
		research.visible = not research.visible

func restart() -> void:
	state = State.new()
	selected = ""
	map.reset_view()
	designation.clear()
	insight_popup.hide()
	research.hide()
	refresh()
	designation.grab_focus()

func refresh() -> void:
	var phase := state.phase
	var early := phase < State.Phase.SENSORS
	boot.visible = early
	active_hud.visible = not early
	research_button.visible = phase >= State.Phase.FIELD_REPAIR
	follow_button.visible = not early
	signals_button.visible = phase >= State.Phase.CONTACTS
	system_label.text = "  /  CONTROLLER SYSTEMS" if state.name_text.is_empty() else "  /  %s" % state.name_text.to_upper()
	if early:
		refresh_boot()
		footer.text = ""
		return
	var stages := ["", "", "LOCAL SENSORS ONLINE", "FLIGHT CONTROL ONLINE", "WAYFINDING ONLINE", "COMMUNICATIONS ONLINE",
		"UNRESOLVED SIGNALS", "FIELD REPAIR", "MINER 031 ONLINE", "HAUL ROUTE ACTIVE"]
	phase_heading.text = stages[phase]
	prompt.text = PHASE_PROMPTS[phase]
	if state.deliveries > 0:
		prompt.text = "First delivery confirmed. Right-click the Asterion to send Miner 031 to strip away the outer hull."
	if state.salvage_mode:
		prompt.text = "Hull recovery active. Watch the outer plating peel away and mixed material arrive at storage."
	if state.refinery_exposed:
		prompt.text = "Refinery assembly uncovered! It is damaged and not yet operational. Further recovery and processing come next."
	var controls := "Scroll / Q and E to zoom"
	if phase >= State.Phase.FLIGHT:
		controls += "   ·   A/D turn   ·   W/S thrust"
	if phase >= State.Phase.WAYFINDING:
		controls += "   ·   Left-click to fly"
	if phase >= State.Phase.CONTACTS:
		controls += "   ·   Right-click contacts"
	footer.text = controls
	contact_details.visible = phase >= State.Phase.CONTACTS
	contact_details.text = "CONTACTS IDENTIFIED   %d / 3" % state.scanned.size()
	if not selected.is_empty():
		contact_details.text += "\n%s" % state.contact_name(selected)
		var available := state.command_for(selected)
		if not available.is_empty():
			contact_details.text += "\nRight-click · %s" % available
	work_panel.visible = not state.work_action.is_empty()
	if work_panel.visible:
		var progress := state.work_fraction() * 100.0
		work_caption.text = "%s   %d%%" % [State.WORK_LABELS[state.work_action], mini(99, floori(progress))]
		work_progress.value = progress
	cargo.visible = phase >= State.Phase.FIELD_REPAIR
	cargo.text = "CONTROLLER CARGO   %d / %d\nOre ×%d   ·   Spare parts ×%d" % [state.ore + state.parts, State.HOLD, state.ore, state.parts]
	if phase == State.Phase.HAULING:
		cargo.text += "\n\nWRECK STOCKPILE\nOre ×%d  ·  Hull feedstock ×%d\nOre runs %d  ·  Salvage runs %d\nMiner cargo ×%d\n%s" % [
			state.stock_ore, state.hull_stock, state.deliveries, state.salvage_deliveries,
			state.miner_cargo, state.miner_status()
		]
		if state.salvage_mode or state.hull_extracted > 0:
			cargo.text += "\n\nASTERION EXCAVATION   %d%%" % roundi(state.hull_cut_fraction() * 100.0)
			cargo.text += "\nRefinery: EXPOSED / DAMAGED" if state.refinery_exposed else "\nRefinery: BURIED"
	notice.text = state.notice if state.notice_time > 0 else ""
	notice.visible = not notice.text.is_empty()
	research_title.text = "◆  Field Repair"
	research_status.text = "Ore   %d / %d\nSpare parts   %d / %d\nRepair the damaged miner" % [state.ore, State.ORE_REQUIRED, state.parts, State.PARTS_REQUIRED]
	if phase >= State.Phase.ORDERS:
		research_title.text += "  ✓"
		research_status.text = "Complete\nMiner 031 restored. Work orders unlocked."

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
	style.border_color = Color("#364844")
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
