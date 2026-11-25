extends "res://dock_map.gd"

const State = preload("res://reboot_state.gd")
const OreField = preload("res://ore_field.gd")
const FOG := Color("#070d10")
const HULL_BOUNDS := Rect2(380, 45, 2020, 1136)
const SIGNAL_OFFSETS := [Vector2(-32, 30), Vector2(43, 26), Vector2(-52, -28)]
# A modest editable surface is mapped onto the existing mothership artwork.
# The holes reveal machinery underneath rather than simulating free-moving atoms.
const ROCK_IMAGE_EDGE := 48
const HULL_PEEL_BOUNDS := Rect2(1100, 245, 360, 220)
const CUT_TILE := 4

var hover := ""
var rock_images: Array[Image] = []
var rock_textures: Array[ImageTexture] = []
var rock_cells: Array = []
var rock_original_colors: Array = []
var rock_erased := PackedInt32Array()
var wreck_image: Image
var wreck_texture: ImageTexture
var wreck_site_cells: Array = []
var wreck_site_erased := PackedInt32Array()

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
					if contact.is_empty() and game.state.scanned.has("ore"):
						var under_cursor := world_point(event.position)
						if game.state.is_charted(under_cursor) and OreField.within_field(under_cursor):
							contact = "ore"
					if not contact.is_empty():
						game.right_command(contact)
		accept_event()
	elif event is InputEventMouseMotion:
		hover = at_marker(event.position)
		if hover.is_empty() and game.state.scanned.has("ore"):
			var under_cursor := world_point(event.position)
			if game.state.is_charted(under_cursor) and OreField.within_field(under_cursor):
				hover = "ore"
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
	draw_refinery_intake()
	draw_fog(state)
	draw_arc(screen_point(state.player), State.SENSOR_RANGE * zoom, 0, TAU, 72, Color("#4b7772"), 1, true)

	if state.has_destination:
		var end := screen_point(state.destination)
		draw_dashed_line(screen_point(state.player), end, Color(CYAN, 0.52), 1.2, 7.0)
		reticle(end, CYAN, 10)
	if state.phase == State.Phase.HAULING and state.miner_rock >= 0:
		var source := State.HULL_WORKSITE if state.salvage_mode else state.miner_worksite
		draw_route_hint(screen_point(source), screen_point(State.STOCKPILE))
	if state.phase >= State.Phase.ORDERS:
		if state.is_charted(state.miner_position):
			draw_worker_light(state.miner_position, state.miner_heading, true, state.miner_cargo > 0)
			if state.miner_work_time > 0:
				var duration := (State.HULL_CUT_TIME if state.salvage_mode else State.MINER_EXTRACTION_TIME) if state.to_field else State.MINER_UNLOAD_TIME
				draw_work_arc(screen_point(state.miner_position), 13, state.miner_work_time / duration)
		else:
			reticle(screen_point(state.miner_position), Color(CYAN, 0.65), 7)
	if state.salvage_insight_unlocked:
		for worker in state.salvage_workers:
			if not bool(worker["active"]):
				continue
			var worker_position: Vector2 = worker["position"]
			if state.is_charted(worker_position):
				draw_worker_light(worker_position, float(worker["heading"]), true, int(worker["cargo"]) > 0)
				if float(worker["time"]) > 0.0:
					var duration: float = State.HULL_CUT_TIME if bool(worker["to_hull"]) else State.MINER_UNLOAD_TIME
					draw_work_arc(screen_point(worker_position), 12.0, float(worker["time"]) / duration)
	for contact in State.CONTACTS:
		if state.is_visible(contact):
			draw_contact(state, contact)
	draw_controller(state)
	draw_field_composition(state)
	if not state.work_action.is_empty():
		draw_work_arc(screen_point(state.player), 32 * clampf(zoom, 0.5, 1.55), state.work_fraction())
	draw_string(get_theme_default_font(), Vector2(17, size.y - 18),
		"LOCAL SENSOR RANGE  /  %d%% VIEW" % roundi(zoom * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
	draw_scale_ruler()

func draw_refinery_intake() -> void:
	# Explicitly outside the upper hull edge: a provisional intake staging pad.
	var pad := screen_point(State.STOCKPILE)
	var mouth := screen_point(State.REFINERY_INTAKE)
	var radius := maxf(6.0, 18.0 * zoom)
	draw_line(pad, mouth, Color("#769f91"), maxf(1.0, 2.0 * zoom), true)
	draw_circle(pad, radius + 4.0 * zoom, Color(0.04, 0.12, 0.14, 0.78), true)
	draw_circle(pad, radius, Color("#92aea5"), false, maxf(1.0, 1.8 * zoom))
	draw_line(pad + Vector2(-10, 0) * zoom, pad + Vector2(10, 0) * zoom, Color("#b3d8cb"), 2.0, true)
	draw_line(pad + Vector2(0, -10) * zoom, pad + Vector2(0, 10) * zoom, Color("#b3d8cb"), 2.0, true)
	draw_rect(Rect2(mouth - Vector2(22, 11) * zoom, Vector2(44, 22) * zoom), Color("#344d4c"))
	draw_rect(Rect2(mouth - Vector2(22, 11) * zoom, Vector2(44, 22) * zoom), Color("#a4c1aa"), false, maxf(1.0, zoom))
	if zoom > 0.65:
		write(pad + Vector2(-37, -24), "STAGING PAD", Color("#a9c8b9"), 11)
		write(mouth + Vector2(-30, -17), "INTAKE", Color("#b6c7ad"), 11)

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
	# Independent transparent textures: each asteroid is consumed from the
	# edge facing the stockpile, not from the field's central POI marker.
	rock_images.clear()
	rock_textures.clear()
	rock_cells.clear()
	rock_original_colors.clear()
	rock_erased.clear()
	var colors := [Color("#777c78"), Color("#a18d7f"), Color("#697b7e"), Color("#535b57")]
	for index in range(OreField.ROCK_COUNT):
		var image := Image.create_empty(ROCK_IMAGE_EDGE, ROCK_IMAGE_EDGE, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var cells: Array[Vector2i] = []
		var center := Vector2.ONE * float(ROCK_IMAGE_EDGE) * 0.5
		var radius := float(ROCK_IMAGE_EDGE) * 0.43
		for y in range(ROCK_IMAGE_EDGE):
			for x in range(ROCK_IMAGE_EDGE):
				var offset := Vector2(float(x), float(y)) - center
				var angle := atan2(offset.y, offset.x)
				var rough_edge := radius * (0.90 + 0.11 * sin(angle * 7.0 + float(index)) +
					0.05 * cos(angle * 13.0 + float(index) * 2.3))
				if offset.length() > rough_edge:
					continue
				var material_id := posmod(x * 17 + y * 31 + index * 11, 13)
				var tint: Color = colors[0 if material_id < 6 else (1 if material_id < 9 else (2 if material_id < 12 else 3))]
				image.set_pixel(x, y, tint)
				cells.append(Vector2i(x, y))
		var face := (OreField.near_surface(index, State.STOCKPILE) - OreField.rock_center(index)).normalized()
		# Sort by the stockpile-facing exposed surface, with a ragged face.
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (Vector2(a) - center).dot(face) + 1.2 * sin(float(a.x * 3 + a.y * 7))
			var db := (Vector2(b) - center).dot(face) + 1.2 * sin(float(b.x * 3 + b.y * 7))
			return da > db
		)
		var originals: Array[Color] = []
		for pixel in cells:
			originals.append(image.get_pixel(pixel.x, pixel.y))
		rock_images.append(image)
		rock_textures.append(ImageTexture.create_from_image(image))
		rock_cells.append(cells)
		rock_original_colors.append(originals)
		rock_erased.append(0)

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
	wreck_site_cells.clear()
	wreck_site_erased.clear()
	var site_pixels: Array[Vector2] = []
	for i in range(State.SALVAGE_SITES.size()):
		var site: Vector2 = State.SALVAGE_SITES[i]
		site_pixels.append((site - HULL_BOUNDS.position) / HULL_BOUNDS.size * Vector2(w, h))
		wreck_site_cells.append([])
		wreck_site_erased.append(0)
	for y in range(y0, y1, CUT_TILE):
		for x in range(x0, x1, CUT_TILE):
			if wreck_image.get_pixel(x, y).a <= 0.25:
				continue
			var cell := Vector2i(x, y)
			var which := 0
			var nearest := INF
			for i in range(site_pixels.size()):
				var dist := Vector2(cell).distance_squared_to(site_pixels[i])
				if dist < nearest:
					nearest = dist
					which = i
			wreck_site_cells[which].append(cell)
	# Each salvager peels its own hull zone from the intake-facing surface,
	# leaving a ragged frontier directly adjacent to that worksite.
	for i in range(wreck_site_cells.size()):
		var anchor: Vector2 = site_pixels[i]
		var direction: Vector2 = (State.STOCKPILE - State.SALVAGE_SITES[i]).normalized()
		var working_axis := (direction * Vector2(w, h) / HULL_BOUNDS.size).normalized()
		var cells: Array = wreck_site_cells[i]
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var first := (Vector2(a) - anchor).dot(working_axis)
			var second := (Vector2(b) - anchor).dot(working_axis)
			first += 6.0 * sin(float(a.x) * 0.075 + float(a.y) * 0.11)
			second += 6.0 * sin(float(b.x) * 0.075 + float(b.y) * 0.11)
			return first > second
		)
	wreck_texture = ImageTexture.create_from_image(wreck_image)

func sync_matter_visuals(state: State) -> void:
	for index in range(OreField.ROCK_COUNT):
		var image: Image = rock_images[index]
		var cells: Array = rock_cells[index]
		var originals: Array = rock_original_colors[index]
		var current := rock_erased[index]
		var target := clampi(floori(float(cells.size()) * state.rock_visual_units(index)), 0, cells.size())
		if target == current:
			continue
		while current < target:
			var cell: Vector2i = cells[current]
			image.set_pixel(cell.x, cell.y, Color.TRANSPARENT)
			current += 1
		while current > target:
			current -= 1
			var cell: Vector2i = cells[current]
			var original: Color = originals[current]
			image.set_pixel(cell.x, cell.y, original)
		rock_erased[index] = current
		rock_textures[index].update(image)
	if wreck_texture != null:
		var any_changed := false
		for i in range(wreck_site_cells.size()):
			var cells: Array = wreck_site_cells[i]
			var target := clampi(floori(float(cells.size()) * state.hull_site_visual_units(i)), 0, cells.size())
			var current := wreck_site_erased[i]
			# Upload only after a worthwhile change, unless a region completes.
			if target - current < 12 and target != cells.size():
				continue
			while current < target:
				var pixel: Vector2i = cells[current]
				for py in range(pixel.y, mini(pixel.y + CUT_TILE, wreck_image.get_height())):
					for px in range(pixel.x, mini(pixel.x + CUT_TILE, wreck_image.get_width())):
						wreck_image.set_pixel(px, py, Color.TRANSPARENT)
				current += 1
			wreck_site_erased[i] = current
			any_changed = true
		if any_changed:
			wreck_texture.update(wreck_image)

func draw_ore_field() -> void:
	for index in range(OreField.ROCK_COUNT):
		var center := OreField.rock_center(index)
		var radius := OreField.rock_radius(index)
		var bounds := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		draw_texture_rect(rock_textures[index], Rect2(screen_point(bounds.position), bounds.size * zoom), false)

func draw_field_composition(state: State) -> void:
	if not state.scanned.has("ore"):
		return
	if hover != "ore" and zoom < 1.65:
		return
	var anchor := screen_point(OreField.CENTER)
	if anchor.x < -120.0 or anchor.x > size.x + 120.0 or anchor.y < -100.0 or anchor.y > size.y + 100.0:
		return
	var p := Vector2(
		clampf(anchor.x + 30.0, 14.0, maxf(14.0, size.x - 248.0)),
		clampf(anchor.y - 115.0, 42.0, maxf(42.0, size.y - 130.0))
	)
	var area := Rect2(p, Vector2(235, 119))
	draw_rect(area, Color(0.045, 0.085, 0.105, 0.94))
	draw_rect(area, Color(CYAN, 0.60), false, 1.0)
	write(p + Vector2(11, 18), "DEPLETED FIELD / SCAN", CYAN, 12)
	var left := state.field_remaining_material()
	var available := int(left["Fe"]) + int(left["Cu"]) + int(left["Si"])
	write(p + Vector2(11, 34), "RAW MATTER  %d / %d" % [available, OreField.TOTAL_UNITS], Color("#c1ced0"), 11)
	for line in range(3):
		var symbol := "Fe" if line == 0 else ("Cu" if line == 1 else "Si")
		var remaining := int(left[symbol])
		var initial := OreField.FE_UNITS if line == 0 else (OreField.CU_UNITS if line == 1 else OreField.SI_UNITS)
		var pigment := Color("#a6b5b7") if line == 0 else (Color("#cf8e67") if line == 1 else Color("#d9c291"))
		var y := p.y + 52.0 + float(line) * 19.0
		write(Vector2(p.x + 11.0, y + 5.0), "%s %.1f%%" % [symbol, 100.0 * float(initial) / float(OreField.TOTAL_UNITS)], pigment, 11)
		draw_rect(Rect2(p.x + 91.0, y - 4.0, 108.0, 6.0), Color("#34464c"))
		draw_rect(Rect2(p.x + 91.0, y - 4.0, 108.0 * float(remaining) / float(initial), 6.0), pigment)
		write(Vector2(p.x + 203.0, y + 5.0), "%d" % remaining, Color("#c1ced0"), 11)

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
	var tint := AMBER if unresolved or contact.begins_with("parts") or (contact.begins_with("salvage_") and not state.salvage_worker_active(contact)) else CYAN
	if unresolved:
		draw_arc(point, 18, 0, TAU, 30, Color(tint, 0.30), 1.0, true)
	elif contact.begins_with("parts") and on_screen and state.is_charted(state.position_of(contact)):
		draw_worker_light(state.position_of(contact), -0.52, false)
	elif contact == "miner" and on_screen and state.phase < State.Phase.ORDERS:
		draw_worker_light(state.miner_position, -0.25, false)
	elif contact.begins_with("salvage_") and not state.salvage_worker_active(contact) and on_screen:
		draw_worker_light(state.position_of(contact), -0.20, false)
	var highlight: bool = contact == game.selected or contact == hover
	var quiet_worker: bool = (contact == "miner" and state.phase >= State.Phase.ORDERS) or (contact.begins_with("salvage_") and state.salvage_worker_active(contact))
	if not quiet_worker or highlight:
		reticle(point, tint, 12 if highlight else 8)
	if quiet_worker and not highlight:
		return # The active worker is a tiny light, not permanent UI clutter.
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
