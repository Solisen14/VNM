extends "res://dock_map.gd"

const State = preload("res://reboot_state.gd")
const FOG := Color("#070d10")
const HULL_BOUNDS := Rect2(380, 45, 2020, 1136)
const SIGNAL_OFFSETS := [Vector2(-32, 30), Vector2(43, 26), Vector2(-52, -28)]
# A modest editable surface is mapped onto the existing mothership artwork.
# The holes reveal machinery underneath rather than simulating free-moving atoms.
const FIELD_IMAGE_SIZE := Vector2i(160, 124)
const FIELD_BOUNDS := Rect2(290, -401, 480, 372)
const HULL_PEEL_BOUNDS := Rect2(1100, 245, 360, 220)
const CUT_TILE := 4

var hover := ""
var field_image: Image
var field_texture: ImageTexture
var field_cells: Array[Vector2i] = []
var field_original_colors: Array[Color] = []
var field_erased := 0
var wreck_image: Image
var wreck_texture: ImageTexture
var wreck_cells: Array[Vector2i] = []
var wreck_erased := 0

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hull = load_ship_art("res://assets/mothership.webp")
	reset_view()

func reset_view() -> void:
	camera = Vector2.ZERO
	zoom = 1.35
	following = true
	dragging = false
	hover = ""
	build_ore_pixels()
	build_wreck_pixels()

func set_zoom(factor: float, anchor: Vector2) -> void:
	if game.state.phase < State.Phase.SENSORS:
		return
	var fixed := world_point(anchor)
	var previous := zoom
	zoom = clampf(zoom * factor, 0.18, 8.0)
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
	sync_matter_visuals(state)
	if hull:
		draw_buried_refinery(state)
		var exterior: Texture2D = wreck_texture if wreck_texture != null else hull
		draw_texture_rect(exterior, Rect2(screen_point(HULL_BOUNDS.position), HULL_BOUNDS.size * zoom), false)
	draw_ore_field()
	draw_fog(state)
	draw_arc(screen_point(state.player), State.SENSOR_RANGE * zoom, 0, TAU, 72, Color("#4b7772"), 1, true)

	if state.has_destination:
		var end := screen_point(state.destination)
		draw_dashed_line(screen_point(state.player), end, Color(CYAN, 0.52), 1.2, 7.0)
		reticle(end, CYAN, 10)
	if state.phase == State.Phase.HAULING:
		var source := State.HULL_WORKSITE if state.salvage_mode else State.FIELD
		draw_route_hint(screen_point(source), screen_point(State.STOCKPILE))
	if state.phase >= State.Phase.ORDERS:
		if state.is_charted(state.miner_position):
			draw_worker_light(state.miner_position, state.miner_heading, true, state.miner_cargo > 0)
			if state.miner_work_time > 0:
				var duration := (State.HULL_CUT_TIME if state.salvage_mode else State.MINER_EXTRACTION_TIME) if state.to_field else State.MINER_UNLOAD_TIME
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
	draw_scale_ruler()

func draw_route_hint(from: Vector2, to: Vector2) -> void:
	# A faint, schematic traffic corridor. Workers themselves steer along
	# individual curved paths rather than snapping to this drawn line.
	var axis := to - from
	var normal := axis.orthogonal().normalized()
	var bend := minf(30.0, axis.length() * 0.10)
	var curve := PackedVector2Array()
	for i in range(25):
		var t := float(i) / 24.0
		curve.append(from.lerp(to, t) + normal * sin(PI * t) * bend)
	draw_polyline(curve, Color(CYAN, 0.24), 1.0, true)

func draw_scale_ruler() -> void:
	var scale_metres := 1000.0
	if zoom > 5.0:
		scale_metres = 25.0
	elif zoom > 1.5:
		scale_metres = 100.0
	elif zoom > 0.55:
		scale_metres = 500.0
	var pixels := scale_metres / State.METRES_PER_WORLD_UNIT * zoom
	var right := size.x - 20.0
	var left := right - pixels
	var y := size.y - 22.0
	var tint := Color("#8ca6a2")
	draw_line(Vector2(left, y), Vector2(right, y), tint, 1.5, true)
	draw_line(Vector2(left, y - 4.0), Vector2(left, y + 3.0), tint, 1.5, true)
	draw_line(Vector2(right, y - 4.0), Vector2(right, y + 3.0), tint, 1.5, true)
	var caption := "%d m" % int(scale_metres)
	write(Vector2(left, y - 8.0), caption, tint, 12)

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

func build_ore_pixels() -> void:
	field_image = Image.create_empty(FIELD_IMAGE_SIZE.x, FIELD_IMAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	field_image.fill(Color.TRANSPARENT)
	field_cells.clear()
	var metals := [Color("#777870"), Color("#a38b70"), Color("#758b8e"), Color("#494d48")]
	for i in range(26):
		var offset := Vector2.from_angle(i * 2.39996) * sqrt(float(i)) * 21.0
		var center := (State.FIELD + offset - FIELD_BOUNDS.position) / 3.0
		var radius := float(8 + (i * 9 % 13)) / 3.0
		for y in range(maxi(0, floori(center.y - radius - 2)), mini(FIELD_IMAGE_SIZE.y, ceili(center.y + radius + 3))):
			for x in range(maxi(0, floori(center.x - radius - 2)), mini(FIELD_IMAGE_SIZE.x, ceili(center.x + radius + 3))):
				var point := Vector2(x, y) - center
				var edge := radius * (0.88 + 0.10 * sin(atan2(point.y, point.x) * 6.0 + float(i)))
				if point.length() <= edge:
					var material_id := posmod(x * 17 + y * 31 + i * 11, 13)
					var tint: Color = metals[0 if material_id < 6 else (1 if material_id < 9 else (2 if material_id < 12 else 3))]
					field_image.set_pixel(x, y, tint)
	for y in range(FIELD_IMAGE_SIZE.y):
		for x in range(FIELD_IMAGE_SIZE.x):
			if field_image.get_pixel(x, y).a > 0.1:
				field_cells.append(Vector2i(x, y))
	field_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(Vector2(80, 62)) < Vector2(b).distance_squared_to(Vector2(80, 62))
	)
	field_original_colors.clear()
	for p in field_cells:
		field_original_colors.append(field_image.get_pixel(p.x, p.y))
	field_texture = ImageTexture.create_from_image(field_image)
	field_erased = 0

func build_wreck_pixels() -> void:
	if hull == null:
		return
	wreck_image = hull.get_image()
	if wreck_image == null:
		return
	wreck_image.convert(Image.FORMAT_RGBA8)
	var w := wreck_image.get_width()
	var h := wreck_image.get_height()
	var x0 := clampi(floori((HULL_PEEL_BOUNDS.position.x - HULL_BOUNDS.position.x) / HULL_BOUNDS.size.x * w), 0, w)
	var y0 := clampi(floori((HULL_PEEL_BOUNDS.position.y - HULL_BOUNDS.position.y) / HULL_BOUNDS.size.y * h), 0, h)
	var x1 := clampi(ceili((HULL_PEEL_BOUNDS.end.x - HULL_BOUNDS.position.x) / HULL_BOUNDS.size.x * w), 0, w)
	var y1 := clampi(ceili((HULL_PEEL_BOUNDS.end.y - HULL_BOUNDS.position.y) / HULL_BOUNDS.size.y * h), 0, h)
	wreck_cells.clear()
	for y in range(y0, y1, CUT_TILE):
		for x in range(x0, x1, CUT_TILE):
			if wreck_image.get_pixel(x, y).a > 0.25:
				wreck_cells.append(Vector2i(x, y))
	# A jagged cutting front works across the hull instead of random holes.
	wreck_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var lhs := float(a.x) + 11.0 * sin(a.y * 0.075) + 7.0 * sin(a.x * 0.09 + a.y * 0.11)
		var rhs := float(b.x) + 11.0 * sin(b.y * 0.075) + 7.0 * sin(b.x * 0.09 + b.y * 0.11)
		return lhs < rhs
	)
	wreck_texture = ImageTexture.create_from_image(wreck_image)
	wreck_erased = 0

func sync_matter_visuals(state: State) -> void:
	if field_texture != null:
		var field_target := clampi(floori(float(field_cells.size()) * state.field_cut_fraction()), 0, field_cells.size())
		if field_target != field_erased:
			while field_erased < field_target:
				var p := field_cells[field_erased]
				field_image.set_pixel(p.x, p.y, Color.TRANSPARENT)
				field_erased += 1
			# A cancelled manual extraction has not transferred matter yet.
			while field_erased > field_target:
				field_erased -= 1
				var p := field_cells[field_erased]
				field_image.set_pixel(p.x, p.y, field_original_colors[field_erased])
			field_texture.update(field_image)
	if wreck_texture != null:
		var wreck_target := clampi(floori(float(wreck_cells.size()) * state.hull_cut_fraction()), 0, wreck_cells.size())
		# Limit large texture uploads to meaningful progress steps.
		if wreck_target - wreck_erased >= 14 or (wreck_target == wreck_cells.size() and wreck_target > wreck_erased):
			while wreck_erased < wreck_target:
				var p := wreck_cells[wreck_erased]
				for py in range(p.y, mini(p.y + CUT_TILE, wreck_image.get_height())):
					for px in range(p.x, mini(p.x + CUT_TILE, wreck_image.get_width())):
						wreck_image.set_pixel(px, py, Color.TRANSPARENT)
				wreck_erased += 1
			wreck_texture.update(wreck_image)

func draw_ore_field() -> void:
	if field_texture != null:
		draw_texture_rect(field_texture, Rect2(screen_point(FIELD_BOUNDS.position), FIELD_BOUNDS.size * zoom), false)

func draw_buried_refinery(state: State) -> void:
	var at := screen_point(State.HULL_WORKSITE + Vector2(36, 20))
	var unit := zoom
	var hull_bay := Rect2(at + Vector2(-105, -70) * unit, Vector2(210, 140) * unit)
	draw_rect(hull_bay, Color("#152024"))
	draw_rect(hull_bay.grow(-8.0 * unit), Color("#2b3637"), false, 2.0)
	for i in range(5):
		var x := -81.0 + float(i) * 35.0
		var center := at + Vector2(x, 3) * unit
		draw_rect(Rect2(center - Vector2(12, 39) * unit, Vector2(24, 78) * unit), Color("#4e6866"))
		draw_line(center - Vector2(0, 30) * unit, center + Vector2(0, 30) * unit, Color("#a0c1aa"), 2.0)
	for y in [-48.0, 49.0]:
		draw_line(at + Vector2(-92, y) * unit, at + Vector2(93, y) * unit, Color("#996e54"), 5.0 * unit)
	if state.refinery_exposed:
		write(at + Vector2(-98, -82) * unit, "DAMAGED REFINERY ASSEMBLY", CYAN, 13)

func draw_contact(state: State, contact: String) -> void:
	var actual := screen_point(marker_position(contact))
	var point := contact_screen_point(contact)
	var on_screen := point.is_equal_approx(actual)
	var unresolved := contact in State.PRIMARY and not state.scanned.has(contact)
	var tint := AMBER if unresolved or contact.begins_with("parts") else CYAN
	if unresolved:
		draw_arc(point, 18, 0, TAU, 30, Color(tint, 0.30), 1.0, true)
	elif contact.begins_with("parts") and on_screen and state.is_charted(state.position_of(contact)):
		draw_worker_light(state.position_of(contact), -0.52, false)
	elif contact == "miner" and on_screen and state.phase < State.Phase.ORDERS:
		draw_worker_light(state.miner_position, -0.25, false)
	var highlight: bool = contact == game.selected or contact == hover
	if contact != "miner" or state.phase < State.Phase.ORDERS or highlight:
		reticle(point, tint, 12 if highlight else 8)
	if contact == "miner" and state.phase >= State.Phase.ORDERS and not highlight:
		return # Keep the active worker as a white dot until inspected.
	var caption := state.contact_name(contact).to_upper()
	if not on_screen:
		caption += "  ·  OFF SCREEN"
	if contact == hover and not state.command_for(contact).is_empty():
		caption += "  /  " + state.command_for(contact).to_upper()
	write(point + Vector2(14, -10), caption, tint, 12)

func draw_worker_light(position: Vector2, angle: float, operating: bool, loaded := false) -> void:
	var at := screen_point(position)
	var screen_length := State.WORKER_WORLD_LENGTH * zoom
	var core_radius := maxf(1.0, screen_length * 0.42)
	var white := Color("#f1f8ff") if operating else Color("#87918e")
	# One bright nucleus and a faint halo. No elaborate sprite is required.
	if operating:
		draw_circle(at, maxf(3.0, core_radius * 2.4), Color(0.73, 0.90, 1.0, 0.16), true)
		draw_circle(at, core_radius, Color("#ffffff") if not loaded else Color("#d5edf6"), true)
		if loaded:
			draw_circle(at, maxf(2.3, core_radius * 1.45), Color(0.6, 0.9, 1.0, 0.17), false, 1.0)
	else:
		draw_circle(at, core_radius, white, true)
	# Only at close inspection zoom does a small directional body appear.
	if screen_length >= 6.0:
		var direction := Vector2.from_angle(angle)
		var side := direction.orthogonal()
		var tip := at + direction * (screen_length * 0.55)
		draw_line(at - direction * (screen_length * 0.4), tip, white, maxf(1.0, screen_length * 0.22), true)
		draw_line(at + side * (screen_length * 0.22), at - side * (screen_length * 0.22), white, 1.0, true)

func draw_controller(state: State) -> void:
	var center := screen_point(state.player)
	# 25 m of ship across a 5 km mothership, rather than an icon that's 1/40
	# the hull's length. The reticle and label remain legible when zoomed out.
	var unit := State.CONTROLLER_WORLD_LENGTH * zoom / 47.0
	var profile := PackedVector2Array([
		Vector2(-22, -11), Vector2(0, -11), Vector2(16, -7),
		Vector2(21, 0), Vector2(16, 7), Vector2(0, 11),
		Vector2(-22, 11), Vector2(-26, 6), Vector2(-26, -6)
	])
	for i in range(profile.size()):
		profile[i] = center + profile[i].rotated(state.heading) * unit
	draw_colored_polygon(profile, Color("#727973"))
	profile.append(profile[0])
	draw_polyline(profile, Color("#c1c7b3"), 1.0, true)
	var forward := Vector2.from_angle(state.heading)
	var side := forward.orthogonal()
	draw_line(center - forward * 11 * unit, center + forward * 15 * unit,
		Color("#242d2b"), maxf(1.0, 4.0 * unit), true)
	for offset in [-6, 6]:
		var port := center + (-forward * 23.0 + side * float(offset)) * unit
		draw_circle(port, maxf(0.85, 2.0 * unit),
			Color(CYAN, 0.42 if state.velocity.length() < 8 else 0.90), true)
	var marker_radius := maxf(9.0, 27.0 * unit)
	reticle(center, CYAN, marker_radius)
	write(center + Vector2(marker_radius + 6.0, 10.0), state.name_text.to_upper(), CYAN, 13)
