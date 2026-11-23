extends "res://dock_map.gd"

const State = preload("res://reboot_state.gd")
const FOG := Color("#070d10")
const HULL_BOUNDS := Rect2(380, 45, 2020, 1136)
const SIGNAL_OFFSETS := [Vector2(-32, 30), Vector2(43, 26), Vector2(-52, -28)]

var hover := ""

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hull = load_ship_art("res://assets/mothership.webp")
	reset_view()

func reset_view() -> void:
	camera = Vector2.ZERO
	zoom = 0.82
	following = true
	dragging = false
	hover = ""

func set_zoom(factor: float, anchor: Vector2) -> void:
	if game.state.phase < State.Phase.SENSORS:
		return
	var fixed := world_point(anchor)
	var previous := zoom
	zoom = clampf(zoom * factor, 0.22, 1.8)
	camera += fixed - world_point(anchor)
	game.state.mark_zoom(previous, zoom)
	following = false

func _gui_input(event: InputEvent) -> void:
	if game.state.phase < State.Phase.SENSORS:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			if dragging:
				following = false
		elif event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP: set_zoom(1.15, event.position)
				MOUSE_BUTTON_WHEEL_DOWN: set_zoom(1 / 1.15, event.position)
				MOUSE_BUTTON_LEFT:
					game.left_command(world_point(event.position))
				MOUSE_BUTTON_RIGHT:
					var contact := at_marker(event.position)
					if not contact.is_empty():
						game.right_command(contact)
		accept_event()
	elif event is InputEventMouseMotion:
		hover = at_marker(event.position)
		if dragging:
			camera -= event.relative / zoom
			accept_event()

func marker_position(contact: String) -> Vector2:
	var point: Vector2 = game.state.position_of(contact)
	var index := State.PRIMARY.find(contact)
	if index >= 0 and not game.state.scanned.has(contact):
		return point + SIGNAL_OFFSETS[index]
	return point

func frame_signals() -> void:
	following = false
	camera = Vector2(540, 180)
	zoom = clampf((size.x - 125.0) / 1400.0, 0.25, 0.67)

func contact_screen_point(contact: String) -> Vector2:
	return screen_point(marker_position(contact)).clamp(Vector2(18, 32), size - Vector2(105, 33))

func at_marker(point: Vector2) -> String:
	var closest := 38.0
	var found := ""
	for contact in State.CONTACTS:
		if not game.state.is_visible(contact):
			continue
		var marker := contact_screen_point(contact)
		var label_x := clampf(point.x, marker.x + 15, marker.x + 120)
		var distance := minf(point.distance_to(marker), point.distance_to(Vector2(label_x, marker.y - 14)))
		if distance < closest:
			closest = distance
			found = contact
	return found

func _draw() -> void:
	if not is_instance_valid(game):
		return
	var state: State = game.state
	draw_rect(Rect2(Vector2.ZERO, size), Color("#11191c"))
	if state.phase < State.Phase.SENSORS:
		return
	draw_chart_background()
	if hull:
		draw_texture_rect(hull, Rect2(screen_point(HULL_BOUNDS.position), HULL_BOUNDS.size * zoom), false)
	draw_ore_field()
	draw_fog(state)
	draw_arc(screen_point(state.player), State.SENSOR_RANGE * zoom, 0, TAU, 72, Color("#4b7772"), 1, true)

	if state.has_destination:
		var end := screen_point(state.destination)
		draw_dashed_line(screen_point(state.player), end, Color(CYAN, 0.52), 1.2, 7.0)
		reticle(end, CYAN, 10)
	if state.phase == State.Phase.HAULING:
		draw_dashed_line(screen_point(State.FIELD), screen_point(State.STOCKPILE), Color(CYAN, 0.42), 1.25, 8)
	if state.phase >= State.Phase.ORDERS:
		if state.is_charted(state.miner_position):
			draw_craft(state.miner_position, state.miner_heading, CYAN, true, 0.85)
			if state.miner_work_time > 0:
				var duration := State.MINER_EXTRACTION_TIME if state.to_field else State.MINER_UNLOAD_TIME
				draw_work_arc(screen_point(state.miner_position), 13, state.miner_work_time / duration)
		else:
			reticle(screen_point(state.miner_position), Color(CYAN, 0.65), 7)
	for contact in State.CONTACTS:
		if state.is_visible(contact):
			draw_contact(state, contact)
	draw_controller(state)
	if not state.work_action.is_empty():
		draw_work_arc(screen_point(state.player), 32 * clampf(zoom, 0.5, 1.55), state.work_fraction())
	draw_string(get_theme_default_font(), Vector2(17, size.y - 18),
		"LOCAL SENSOR RANGE  /  %d%% VIEW" % roundi(zoom * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)

func draw_work_arc(point: Vector2, radius: float, fraction: float) -> void:
	draw_arc(point, radius, 0, TAU, 48, Color(CYAN, 0.22), 1.0, true)
	if fraction > 0:
		draw_arc(point, radius, -PI / 2, -PI / 2 + TAU * fraction, 48, CYAN, 2.0, true)

func draw_chart_background() -> void:
	for i in range(125):
		var star := Vector2(fposmod(i * 161.73 - camera.x * 0.11, size.x + 1), fposmod(i * i * 29.1 - camera.y * 0.11, size.y + 1))
		draw_circle(star, 0.8, Color(0.60, 0.70, 0.72, 0.27 + (i % 4) * 0.09), true, -1, true)

func draw_fog(state: State) -> void:
	var first := Vector2i((world_point(Vector2.ZERO) / State.GRID).floor())
	var last := Vector2i((world_point(size) / State.GRID).ceil())
	for y in range(first.y, last.y):
		var start := first.x
		for x in range(first.x, last.x + 1):
			if x == last.x or state.chart.has(Vector2i(x, y)):
				if x > start:
					var top_left := screen_point(Vector2(start, y) * State.GRID)
					var bottom_right := screen_point(Vector2(x, y + 1) * State.GRID)
					draw_rect(Rect2(top_left.floor(), bottom_right.floor() - top_left.floor()), FOG)
				start = x + 1

func draw_ore_field() -> void:
	for i in range(26):
		var offset := Vector2.from_angle(i * 2.39996) * sqrt(i) * 21
		var center := screen_point(State.FIELD + offset)
		var radius := (8 + (i * 9 % 13)) * zoom
		var stone := PackedVector2Array()
		for side in range(6):
			stone.append(center + Vector2.from_angle(side * TAU / 6 + i) * radius * (0.69 + 0.09 * ((side * 21 + i) % 4)))
		draw_colored_polygon(stone, Color("#494740"))
		stone.append(stone[0])
		draw_polyline(stone, Color("#777265"), 1.0, true)

func draw_contact(state: State, contact: String) -> void:
	var actual := screen_point(marker_position(contact))
	var point := contact_screen_point(contact)
	var on_screen := point.is_equal_approx(actual)
	var unresolved := contact in State.PRIMARY and not state.scanned.has(contact)
	var tint := AMBER if unresolved or contact.begins_with("parts") else CYAN
	if unresolved:
		draw_arc(point, 18, 0, TAU, 30, Color(tint, 0.30), 1.0, true)
	elif contact.begins_with("parts") and on_screen and state.is_charted(state.position_of(contact)):
		draw_craft(state.position_of(contact), -0.52, AMBER, false, 0.77)
	elif contact == "miner" and on_screen and state.phase < State.Phase.ORDERS:
		draw_craft(state.miner_position, -0.25, AMBER, false, 0.85)
	reticle(point, tint, 12 if contact == game.selected else 8)
	var caption := state.contact_name(contact).to_upper()
	if not on_screen:
		caption += "  ·  OFF SCREEN"
	if contact == hover and not state.command_for(contact).is_empty():
		caption += "  /  " + state.command_for(contact).to_upper()
	write(point + Vector2(14, -10), caption, tint, 12)

func draw_controller(state: State) -> void:
	var center := screen_point(state.player)
	var unit := clampf(zoom, 0.5, 1.55)
	var profile := PackedVector2Array([Vector2(-22,-11), Vector2(0,-11), Vector2(16,-7), Vector2(21,0), Vector2(16,7), Vector2(0,11), Vector2(-22,11), Vector2(-26,6), Vector2(-26,-6)])
	for i in range(profile.size()):
		profile[i] = center + profile[i].rotated(state.heading) * unit
	draw_colored_polygon(profile, Color("#727973"))
	profile.append(profile[0])
	draw_polyline(profile, Color("#c1c7b3"), 1.1, true)
	var forward := Vector2.from_angle(state.heading)
	var side := forward.orthogonal()
	draw_line(center - forward * 11 * unit, center + forward * 15 * unit, Color("#242d2b"), 4 * unit, true)
	for offset in [-6, 6]:
		var port := center + (-forward * 23 + side * float(offset)) * unit
		draw_circle(port, 3.0 * unit, Color(CYAN, 0.42 if state.velocity.length() < 8 else 0.90), true, -1, true)
	reticle(center, CYAN, 27 * unit)
	write(center + Vector2(27 * unit, 20), state.name_text.to_upper(), CYAN, 13)
