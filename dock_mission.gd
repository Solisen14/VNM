extends Control

const Mission = preload("res://dock_state.gd")
const Opening = preload("res://opening.gd")
const DockMap = preload("res://dock_map.gd")
const CYAN := Color("#9adbd4")
const AMBER := Color("#efb16d")
const MUTED := Color("#a3b1b3")
const TEXT := Color("#ebe8df")
const BLAST_AT := 8.0
const REBOOT_AT := 9.5
const HANDOFF_AT := 14.0

var state := Mission.new()
var opening := Opening.new()
var time := 0.0
var cinematic := true
var manually_paused := false
var tutorial_paused := false
var selected := ""
var speed := 1
var map: DockMap
var mission_status: Label
var system_status: Label
var pause_button: Button
var speed_button: Button
var skip_button: Button
var contact_name: Label
var contact_status: Label
var contact_action: Button
var cargo: Label
var stock: Label
var route: Label
var network: Label
var card: PanelContainer
var card_title: Label
var card_text: Label
var card_button: Button
var rename_field: LineEdit

func _ready() -> void:
	get_window().min_size = Vector2i(900, 600)
	theme = screen_theme()
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(panel(header, Color("#111819"), 12))
	var title := label("VNM", 25, TEXT)
	header.add_child(title)
	system_status = label("", 14, CYAN)
	system_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(system_status)
	skip_button = button(header, "Skip opening", finish_opening)
	pause_button = button(header, "Pause", toggle_pause)
	speed_button = button(header, "1×", cycle_speed)
	button(header, "Restart", restart)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	layout.add_child(body)
	var view := Control.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(view)
	map = DockMap.new()
	map.game = self
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.add_child(map)

	var message := VBoxContainer.new()
	message.add_theme_constant_override("separation", 8)
	card_title = label("", 22, TEXT)
	message.add_child(card_title)
	card_text = paragraph(message, 15, TEXT)
	card_button = button(message, "", dismiss_milestone)
	card = panel(message, Color("#202b2d"), 16)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.offset_left = -205
	card.offset_right = 205
	card.offset_bottom = -24
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	view.add_child(card)
	card.hide()

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 290
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(panel(scroll, Color("#151d20"), 13))
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 9)
	scroll.add_child(side)
	section(side, "OPERATIONS")
	mission_status = paragraph(side, 15, TEXT)
	section(side, "SELECTED CONTACT")
	contact_name = paragraph(side, 20, TEXT)
	contact_status = paragraph(side, 14, MUTED)
	contact_action = button(side, "", use_contact)
	section(side, "CONTROL DRONE CARGO")
	cargo = paragraph(side, 14, TEXT)
	section(side, "WRECK STOCKPILE")
	stock = paragraph(side, 14, TEXT)
	section(side, "HAUL ROUTE")
	route = paragraph(side, 14, TEXT)
	section(side, "LOCAL CONTROL NETWORK")
	network = paragraph(side, 14, MUTED)
	rename_field = LineEdit.new()
	rename_field.max_length = 18
	rename_field.placeholder_text = "Rename your drone"
	rename_field.text_submitted.connect(rename_player)
	side.add_child(rename_field)

	var footer := HBoxContainer.new()
	layout.add_child(panel(footer, Color("#111819"), 9))
	var help := label("WASD / Right-click to fly   ·   Left-click to inspect   ·   Middle-drag to pan   ·   Scroll to zoom", 13, MUTED)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	button(footer, "Follow drone", map.follow_player)
	state.milestone.connect(show_milestone)
	refresh()

func _process(delta: float) -> void:
	if not manually_paused and not tutorial_paused:
		if cinematic:
			time += delta
			if time >= HANDOFF_AT:
				finish_opening()
		else:
			var direction := Vector2.ZERO
			if not rename_field.has_focus():
				direction = Vector2(
					int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)),
					int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
				)
			advance_mission(delta * speed, direction)
	refresh()
	map.queue_redraw()

func advance_mission(delta: float, direction: Vector2) -> void:
	state.tick(delta, direction)
	state.player = state.player.clamp(Vector2(-1120, -470), Vector2(1120, 700))
	state.destination = state.destination.clamp(Vector2(-1120, -470), Vector2(1120, 700))

func finish_opening() -> void:
	if not cinematic:
		return
	cinematic = false
	selected = "worker"
	map.follow_player()
	show_milestone("Four peers online", "The mothership link is down. Four other control drones answered the local handshake. Worker 031 is drifting off Dock 03 and still responds to diagnostics.", "Take control")

func show_milestone(title_text: String, message: String, action: String) -> void:
	tutorial_paused = true
	card_title.text = title_text
	card_text.text = message
	card_button.text = action
	card.show()

func dismiss_milestone() -> void:
	tutorial_paused = false
	card.hide()
	if state.phase == Mission.Phase.AUTHORIZE and not cinematic:
		state.act("depot")

func use_contact() -> void:
	if tutorial_paused or cinematic:
		return
	state.act(selected)

func rename_player(value: String) -> void:
	var name_text := value.strip_edges()
	if not name_text.is_empty():
		state.shipmates[0] = name_text
	rename_field.clear()
	rename_field.release_focus()

func toggle_pause() -> void:
	if not tutorial_paused:
		manually_paused = not manually_paused

func cycle_speed() -> void:
	speed = 2 * speed if speed < 4 else 1

func restart() -> void:
	state = Mission.new()
	state.milestone.connect(show_milestone)
	time = 0.0
	cinematic = true
	manually_paused = false
	tutorial_paused = false
	selected = ""
	speed = 1
	card.hide()
	rename_field.clear()
	map.reset_view()

func refresh() -> void:
	pause_button.text = "Paused" if tutorial_paused else ("Resume" if manually_paused else "Pause")
	pause_button.disabled = tutorial_paused
	speed_button.text = "%d×" % speed
	speed_button.disabled = cinematic
	skip_button.visible = cinematic
	rename_field.visible = not cinematic
	if cinematic:
		refresh_opening()
		return
	system_status.text = "LOCAL CONTROL NETWORK   /   DOCK 03"
	mission_status.text = state.objective()
	var phase := state.phase
	contact_name.text = map.contact_label(selected) if not selected.is_empty() else "No contact selected"
	contact_status.text = contact_description()
	var action := state.action_label(selected)
	var distant := state.requires_proximity() and not state.nearby(selected)
	contact_action.visible = not action.is_empty()
	contact_action.disabled = distant or tutorial_paused
	contact_action.text = action
	if not action.is_empty() and distant:
		contact_status.text += "\nRight-click near the marker to approach."
	cargo.text = "%s · %d / %d slots\nHull scrap ×%d   ·   Control module ×%d" % [
		state.shipmates[0], int(state.cargo_scrap > 0) + int(state.cargo_module),
		Mission.CARGO_SLOTS, state.cargo_scrap, int(state.cargo_module)
	]
	stock.text = "Hull scrap ×%d\nControl module ×%d reserved" % [state.wreck_scrap, int(state.secured_module)]
	route.text = "Awaiting a worker assignment"
	if phase == Mission.Phase.ROUTE_DESTINATION:
		route.text = "Scrap cache selected\nChoose a drop-off"
	elif phase == Mission.Phase.RUNNING:
		var status := "Returning for pickup" if state.to_cache else "Outbound to stockpile"
		if state.cache_scrap == 0 and state.worker_cargo == 0:
			status = "Cache depleted"
		route.text = "%s\nAt cache %d   ·   In transit %d\nCompleted deliveries %d" % [
			status, state.cache_scrap, state.worker_cargo, state.deliveries
		]
	network.text = "  /  ".join(state.shipmates)

func contact_description() -> String:
	match selected:
		"worker":
			return "Diagnostic link active · Drive offline" if state.phase < Mission.Phase.ROUTE_SOURCE else "Drive online · Local control link established"
		"salvage":
			return "Intact control module and loose hull scrap" if state.phase <= Mission.Phase.SALVAGE_PART else "Repair kit recovered"
		"cache": return "%d hull scrap waiting for pickup" % state.cache_scrap
		"depot": return "Shared inventory and delivery point"
		"observation": return "Exposed aft hull · Survey waypoint"
		"dock": return "Mothership cargo deck · Emergency lights active"
	return "Select a marker on the map."

func refresh_opening() -> void:
	system_status.text = "MOTHERSHIP NETWORK   /   AUTOMATED SHIFT"
	mission_status.text = "Ore transfer in progress." if time < 4.5 else "Fleet recall confirmed. Workers returning to dock."
	if time >= BLAST_AT:
		system_status.text = "SIGNAL LOST" if time < REBOOT_AT else "LOCAL SYSTEMS   /   RESTART"
		mission_status.text = "Mothership link unavailable." if time < REBOOT_AT else "Attitude control restored. Searching for local peers."
	contact_name.text = "Ore hauler"
	contact_status.text = "Mothership telemetry" if time < BLAST_AT else "Uplink offline"
	contact_action.hide()
	cargo.text = "Cargo hold empty"
	stock.text = "Mothership logistics"
	route.text = "Automated mining circuit" if time < BLAST_AT else "Worker channels offline"
	network.text = "Peer handshakes pending"

func screen_theme() -> Theme:
	var style := Theme.new()
	style.default_font_size = 14
	style.set_color("font_color", "Button", TEXT)
	style.set_color("font_disabled_color", "Button", MUTED.darkened(0.25))
	for mode in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#253134") if mode != "disabled" else Color("#1c2426")
		box.border_color = CYAN if mode in ["hover", "pressed", "focus"] else Color("#485859")
		if mode == "focus":
			box.bg_color = Color.TRANSPARENT
		box.set_border_width_all(1)
		box.set_corner_radius_all(3)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		style.set_stylebox(mode, "Button", box)
	return style

func panel(content: Control, color: Color, margin: int) -> PanelContainer:
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("#364345")
	box.set_border_width_all(1)
	for edge in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(edge, margin)
	frame.add_theme_stylebox_override("panel", box)
	frame.add_child(content)
	return frame

func section(parent: VBoxContainer, title: String) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(label(title, 12, CYAN))

func label(message: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = message
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	return item

func paragraph(parent: Container, font_size: int, color: Color) -> Label:
	var item := label("", font_size, color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func button(parent: Container, title: String, callback: Callable) -> Button:
	var item := Button.new()
	item.text = title
	item.pressed.connect(callback)
	parent.add_child(item)
	return item
