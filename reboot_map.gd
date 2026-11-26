extends "res://dock_map.gd"

const CONTROLLER_SPRITE := preload("res://assets/controller_drone.png")
const CONTROLLER_2_SPRITE := preload("res://assets/controller_2.png")
const State = preload("res://reboot_state.gd")
const OreField = preload("res://ore_field.gd")
const Industry = State.Industry
const FOG := Color("#070d10")
const HULL_BOUNDS := State.HULL_BOUNDS
const SIGNAL_OFFSETS := [Vector2(-32, 30), Vector2(43, 26), Vector2(-52, -28)]
# A modest editable surface is mapped onto the existing mothership artwork.
# The holes reveal machinery underneath rather than simulating free-moving atoms.
const ROCK_IMAGE_EDGE := 48
const HULL_PEEL_BOUNDS := Rect2(1100, 245, 360, 220)
const CUT_TILE := 4
const REACTOR_PEEL_BOUNDS := Rect2(Industry.REACTOR_BAY - Vector2(78, 60), Vector2(156, 120))

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
var reactor_cells: Array[Vector2i] = []
var reactor_erased := 0

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

# Edge-scroll is confined to the actual map viewport, never the sidebar.
# Moving the cursor to the outer 36 pixels gently disengages HAL follow.
const EDGE_PAN_MARGIN := 36.0
const EDGE_PAN_SCREEN_SPEED := 560.0

func pan_from_edge(pointer: Vector2, delta: float) -> void:
	if size.x < EDGE_PAN_MARGIN * 3.0 or size.y < EDGE_PAN_MARGIN * 3.0:
		return
	if pointer.x < 0.0 or pointer.y < 0.0 or pointer.x > size.x or pointer.y > size.y:
		return
	var movement := Vector2.ZERO
	if pointer.x < EDGE_PAN_MARGIN:
		movement.x = -(EDGE_PAN_MARGIN - pointer.x) / EDGE_PAN_MARGIN
	elif pointer.x > size.x - EDGE_PAN_MARGIN:
		movement.x = (pointer.x - (size.x - EDGE_PAN_MARGIN)) / EDGE_PAN_MARGIN
	if pointer.y < EDGE_PAN_MARGIN:
		movement.y = -(EDGE_PAN_MARGIN - pointer.y) / EDGE_PAN_MARGIN
	elif pointer.y > size.y - EDGE_PAN_MARGIN:
		movement.y = (pointer.y - (size.y - EDGE_PAN_MARGIN)) / EDGE_PAN_MARGIN
	if movement.length_squared() <= 0.0001:
		return
	following = false
	var magnitude := minf(1.0, movement.length())
	var displacement := movement.normalized() * (EDGE_PAN_SCREEN_SPEED * magnitude / zoom) * delta
	camera = (camera + displacement).clamp(State.WORLD.position, State.WORLD.end)

func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(game) or not is_visible_in_tree():
		return
	if game.state.phase < State.Phase.WAYFINDING or game.insight_popup.visible or dragging:
		return
	if get_viewport().gui_get_hovered_control() != self:
		return
	pan_from_edge(get_local_mouse_position(), delta)

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
					if contact.is_empty() and game.state.salvage_insight_unlocked:
						if HULL_PEEL_BOUNDS.has_point(world_point(event.position)):
							contact = "wreck"
					if not contact.is_empty():
						game.right_command(contact)
		accept_event()
	elif event is InputEventMouseMotion:
		hover = at_marker(event.position)
		if hover.is_empty() and game.state.scanned.has("ore"):
			var under_cursor := world_point(event.position)
			if game.state.is_charted(under_cursor) and OreField.within_field(under_cursor):
				hover = "ore"
		if hover.is_empty() and game.state.salvage_insight_unlocked:
			if HULL_PEEL_BOUNDS.has_point(world_point(event.position)):
				hover = "wreck"
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
	for contact in game.state.contacts:
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
		draw_refinery_bay(state)
		if state.industry.stage >= Industry.Stage.REACTOR_CUT:
			draw_rect(Rect2(screen_point(REACTOR_PEEL_BOUNDS.position), REACTOR_PEEL_BOUNDS.size * zoom), Color("#242b2c"))
			if state.industry.stage < Industry.Stage.REACTOR_EXTRACT:
				draw_auxiliary_reactor(Industry.REACTOR_BAY, Color.WHITE, false)
		var exterior: Texture2D = wreck_texture if wreck_texture != null else hull
		draw_texture_rect(exterior, Rect2(screen_point(HULL_BOUNDS.position), HULL_BOUNDS.size * zoom), false)
	draw_ore_field()
	draw_industrial_structures(state)
	draw_collection_fixture(state)
	if state.refinery_phase >= State.RefineryPhase.EXTRACTING:
		if state.refinery_phase >= State.RefineryPhase.ANCHORING:
			draw_refinery_anchors(state)
		draw_refinery_assembly(state.refinery_position, Color.WHITE)
		draw_refinery_tow(state)
	draw_fog(state)
	if state.refinery_phase >= State.RefineryPhase.EXTRACTING:
		draw_refinery_marker(state)
	if game.placing_refinery and not (game.research.visible or game.inventory.visible):
		if state.industry.stage in [Industry.Stage.REACTOR_SITE, Industry.Stage.CABLE_ROUTE]:
			draw_industrial_preview(state)
		else:
			draw_refinery_preview(state)
	draw_salvage_access_zone(state)
	draw_industrial_signals(state)
	draw_arc(screen_point(state.player), State.SENSOR_RANGE * zoom, 0, TAU, 72, Color("#4b7772"), 1, true)

	if state.has_destination:
		var end := screen_point(state.destination)
		draw_dashed_line(screen_point(state.player), end, Color(CYAN, 0.52), 1.2, 7.0)
		reticle(end, CYAN, 10)
	if state.phase == State.Phase.HAULING and (state.miner_rock >= 0 or state.miner_hull_site >= 0):
		var source: Vector2 = State.SALVAGE_SITES[state.miner_hull_site] if state.salvage_mode and state.miner_hull_site >= 0 else state.miner_worksite
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
				draw_worker_light(worker_position, float(worker["heading"]), true, int(worker["cargo"]) > 0 or (state.industry.crew == state.salvage_workers.find(worker) and state.industry.job_cargo > 0))
				if float(worker["time"]) > 0.0:
					var duration: float = (State.HULL_CUT_TIME if String(worker["task"]) == "hull" else State.MINER_EXTRACTION_TIME) if bool(worker["to_hull"]) else State.MINER_UNLOAD_TIME
					draw_work_arc(screen_point(worker_position), 12.0, float(worker["time"]) / duration)
	for contact in game.state.contacts:
		if state.is_visible(contact):
			draw_contact(state, contact)
	draw_controller(state)
	draw_field_composition(state)
	if not state.work_action.is_empty():
		draw_work_arc(screen_point(state.player), 32 * clampf(zoom, 0.5, 1.55), state.work_fraction())
	draw_string(get_theme_default_font(), Vector2(17, size.y - 18),
		"LOCAL SENSOR RANGE  /  %d%% VIEW" % roundi(zoom * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
	draw_scale_ruler()

func draw_collection_fixture(state: State) -> void:
	var at := screen_point(State.STOCKPILE)
	var deck := Rect2(at - Vector2(32, 15) * zoom, Vector2(64, 30) * zoom)
	draw_rect(deck, Color("#303c3b"))
	draw_rect(deck, Color("#87908a"), false, maxf(1.0, zoom))
	for x in [-21.0, 0.0, 21.0]:
		var bin := Rect2(at + Vector2(x - 8.0, -10.0) * zoom, Vector2(16, 20) * zoom)
		draw_rect(bin, Color("#655f4c"))
		draw_line(bin.position, Vector2(bin.end.x, bin.position.y), AMBER, maxf(1.0, zoom))
	if state.salvage_insight_unlocked:
		draw_line(at, screen_point(State.REFINERY_INTAKE), Color("#769f91"), maxf(1.0, 2.0 * zoom), true)

func draw_salvage_access_zone(state: State) -> void:
	if not state.salvage_insight_unlocked:
		return
	var rect := Rect2(screen_point(HULL_PEEL_BOUNDS.position), HULL_PEEL_BOUNDS.size * zoom)
	var shade := Color("#6e797a") if state.refinery_exposed else Color("#e4ac6b")
	draw_rect(rect, Color(shade, 0.08))
	draw_rect(rect, Color(shade, 0.65), false, maxf(1.0, zoom))
	for i in range(State.SALVAGE_SITES.size()):
		if state.hull_site_units[i] >= State.SALVAGE_SITE_QUOTA:
			continue
		reticle(screen_point(State.SALVAGE_SITES[i]), shade, maxf(5.0, 7.0 * zoom))
	var title := "REFINERY EXPOSED / ACCESS CLOSED" if state.refinery_exposed else "AUTHORIZED SALVAGE / REFINERY ACCESS ONLY"
	write(rect.position + Vector2(4.0, -11.0), title, shade, 12)

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
	reactor_cells.clear()
	reactor_erased = 0
	var texture_extent := Vector2(w, h)
	var start := Vector2i((REACTOR_PEEL_BOUNDS.position - HULL_BOUNDS.position) * texture_extent / HULL_BOUNDS.size)
	var finish := Vector2i((REACTOR_PEEL_BOUNDS.end - HULL_BOUNDS.position) * texture_extent / HULL_BOUNDS.size)
	for y in range(start.y, finish.y, CUT_TILE):
		for x in range(start.x, finish.x, CUT_TILE):
			if wreck_image.get_pixel(x, y).a > 0.25:
				reactor_cells.append(Vector2i(x, y))
	reactor_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y + 8.0 * sin(a.x * 0.16) < b.y + 8.0 * sin(b.x * 0.16))
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
			erase_wreck_tiles(cells, current, target)
			wreck_site_erased[i] = target
			any_changed = true
		var reactor_target := floori(float(reactor_cells.size()) * state.industry.reactor_cuts / Industry.CUT_REQUIRED)
		if reactor_target > reactor_erased:
			erase_wreck_tiles(reactor_cells, reactor_erased, reactor_target)
			reactor_erased = reactor_target
			any_changed = true
		if any_changed:
			wreck_texture.update(wreck_image)

func erase_wreck_tiles(cells: Array, from: int, to: int) -> void:
	for i in range(from, to):
		var pixel: Vector2i = cells[i]
		for py in range(pixel.y, mini(pixel.y + CUT_TILE, wreck_image.get_height())):
			for px in range(pixel.x, mini(pixel.x + CUT_TILE, wreck_image.get_width())):
				wreck_image.set_pixel(px, py, Color.TRANSPARENT)

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

func draw_refinery_bay(state: State) -> void:
	var at := screen_point(State.REFINERY_BAY)
	var hull_bay := Rect2(at + Vector2(-105, -70) * zoom, Vector2(210, 140) * zoom)
	draw_rect(hull_bay, Color("#152024"))
	draw_rect(hull_bay.grow(-8.0 * zoom), Color("#354344"), false, 2.0)
	if state.refinery_phase < State.RefineryPhase.EXTRACTING:
		draw_refinery_assembly(State.REFINERY_BAY, Color.WHITE)

func draw_refinery_assembly(position: Vector2, tint: Color) -> void:
	var at := screen_point(position)
	var extent := State.REFINERY_SIZE * zoom
	var bounds := Rect2(at - extent * 0.5, extent)
	draw_rect(bounds, Color("#263538") * tint)
	draw_rect(bounds, Color("#81948b") * tint, false, maxf(1.0, 3.0 * zoom))
	for i in range(5):
		var center := at + Vector2(-70.0 + float(i) * 35.0, 0.0) * zoom
		draw_rect(Rect2(center - Vector2(12, 39) * zoom, Vector2(24, 78) * zoom), Color("#4e6866") * tint)
		draw_line(center - Vector2(0, 30) * zoom, center + Vector2(0, 30) * zoom, Color("#a0c1aa") * tint, maxf(1.0, 2.0 * zoom))
	for y in [-48.0, 49.0]:
		draw_line(at + Vector2(-86, y) * zoom, at + Vector2(86, y) * zoom, Color("#996e54") * tint, maxf(1.0, 5.0 * zoom))

func draw_refinery_tow(state: State) -> void:
	if state.refinery_phase not in [State.RefineryPhase.EXTRACTING, State.RefineryPhase.HAULING]:
		return
	var at := screen_point(state.refinery_position)
	for i in state.refinery_crew:
		var worker: Vector2 = state.salvage_workers[i]["position"]
		draw_line(at.lerp(screen_point(worker), 0.64), screen_point(worker), CYAN, 1.0, true)

func draw_refinery_anchors(state: State) -> void:
	var deployed := 1.0 if state.refinery_phase == State.RefineryPhase.PLACED else clampf(
		state.refinery_work_time / State.REFINERY_ANCHOR_TIME, 0.0, 1.0)
	var at := screen_point(state.refinery_position)
	for x in [-72.0, 72.0]:
		for side in [-1.0, 1.0]:
			var mount := at + Vector2(x, side * State.REFINERY_SIZE.y * 0.5) * zoom
			var pad := mount + Vector2(0, side * 17.0 * deployed) * zoom
			draw_line(mount, pad, Color("#84978e"), maxf(1.0, 5.0 * zoom))
			draw_rect(Rect2(pad - Vector2(9, 4) * zoom, Vector2(18, 8) * zoom), Color("#697c73"))

func draw_refinery_marker(state: State) -> void:
	var at := screen_point(state.refinery_position)
	var title := "REFINERY / IN TOW"
	match state.refinery_phase:
		State.RefineryPhase.STAGED: title = "REFINERY / STAGED"
		State.RefineryPhase.ANCHORING: title = "REFINERY / ANCHORING"
		State.RefineryPhase.PLACED: title = "REFINERY / OFFLINE"
	write(at + Vector2(-State.REFINERY_SIZE.x * zoom * 0.5, -State.REFINERY_SIZE.y * zoom * 0.5 - 8.0),
		title, CYAN, 13)

func draw_industrial_structures(state: State) -> void:
	var industry := state.industry
	if industry.rich_field_discovered:
		for i in range(Industry.RICH_ROCKS):
			var remaining := Industry.RICH_UNITS_PER_ROCK - industry.rich_mined[i]
			if remaining <= 0:
				continue
			var at := screen_point(industry.rich_center(i))
			var radius := OreField.rock_radius(i) * zoom * sqrt(float(remaining) / Industry.RICH_UNITS_PER_ROCK)
			var face := PackedVector2Array()
			for corner in range(8):
				var angle := TAU * corner / 8.0
				face.append(at + Vector2.from_angle(angle) * radius * (0.85 + 0.14 * sin(i + corner * 2.8)))
			draw_colored_polygon(face, Color("#565853"))
			face.append(face[0])
			draw_polyline(face, Color("#94918a"), 1.0, true)
	if industry.stage >= Industry.Stage.REACTOR_EXTRACT:
		draw_auxiliary_reactor(industry.reactor_position, Color.WHITE, industry.reactor_ready)
		if industry.stage in [Industry.Stage.REACTOR_EXTRACT, Industry.Stage.REACTOR_TOW] and industry.crew >= 0:
			var worker: Vector2 = state.salvage_workers[industry.crew]["position"]
			draw_line(screen_point(industry.reactor_position), screen_point(worker), CYAN, 1.0, true)
	if industry.cable_route.size() == 3:
		var color := CYAN if industry.refinery.powered else AMBER
		var end := industry.cable_point(industry.cable_progress)
		var first := industry.cable_route[0]
		var middle := industry.cable_route[1]
		var first_fraction := first.distance_to(middle) / maxf(0.001, first.distance_to(middle) + middle.distance_to(industry.cable_route[2]))
		if industry.cable_progress > first_fraction:
			draw_line(screen_point(first), screen_point(middle), color, maxf(2.0, zoom * 2.0), true)
			first = middle
		draw_line(screen_point(first), screen_point(end), color, maxf(2.0, zoom * 2.0), true)
	if industry.stage >= Industry.Stage.CONTROLLER_REPAIR:
		var at := screen_point(industry.founder_position)
		var length := State.CONTROLLER_WORLD_LENGTH * zoom
		var extent := CONTROLLER_2_SPRITE.get_size() * (length / CONTROLLER_2_SPRITE.get_width())
		draw_set_transform(at, industry.founder_heading, Vector2.ONE)
		draw_texture_rect(CONTROLLER_2_SPRITE, Rect2(-extent * 0.5, extent), false)
		draw_set_transform(Vector2.ZERO)

func draw_auxiliary_reactor(point: Vector2, tint: Color, active: bool) -> void:
	var at := screen_point(point)
	var extent := Industry.REACTOR_SIZE * zoom
	draw_rect(Rect2(at - extent * 0.5, extent), Color("#333b3c") * tint)
	draw_rect(Rect2(at - extent * 0.5, extent), Color("#938570") * tint, false, maxf(1.0, zoom * 2.0))
	for x in [-46.0, 46.0]:
		draw_rect(Rect2(at + Vector2(x - 10, -35) * zoom, Vector2(20, 70) * zoom), Color("#6a6759") * tint)
	draw_circle(at, 33.0 * zoom, Color("#555b51") * tint, true)
	draw_circle(at, 26.0 * zoom, (Color("#e5ae66") if active else Color("#82705c")) * tint, false, maxf(2.0, 5.0 * zoom), true)
	draw_circle(at, 17.0 * zoom, Color("#262f34") * tint, true)

func draw_industrial_signals(state: State) -> void:
	var industry := state.industry
	if industry.stage == Industry.Stage.REACTOR_CUT or industry.stage == Industry.Stage.REACTOR_RELEASE:
		var area := Rect2(screen_point(REACTOR_PEEL_BOUNDS.position), REACTOR_PEEL_BOUNDS.size * zoom)
		draw_rect(area, AMBER, false, 1.0)
	if industry.stage == Industry.Stage.SEARCH:
		var estimate := Industry.SEARCH_CENTER.lerp(Industry.FOUNDER_SITE + Vector2(80, 40), float(industry.signal_strength) / 100.0)
		var at := screen_point(estimate)
		var radius := lerpf(295.0, 120.0, float(industry.signal_strength) / 100.0) * zoom
		draw_arc(at, radius, 0, TAU, 72, Color(AMBER, 0.72), 1.5, true)
		var label_at := at.clamp(Vector2(24, 35), size - Vector2(230, 35))
		write(label_at, "APPROXIMATE SIGNAL  %d%%" % industry.signal_strength, AMBER, 12)
	if industry.refinery.controller_id != 0:
		var port := screen_point(industry.dock_port())
		draw_line(port, screen_point(industry.refinery.position + Vector2(-53, 55)), Color("#bdb3ff"), 2.0, true)

func draw_industrial_preview(state: State) -> void:
	var cursor := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(cursor):
		return
	var point := world_point(cursor)
	var industry := state.industry
	var reactor_preview := industry.stage == Industry.Stage.REACTOR_SITE
	var error := industry.reactor_site_error(state, point) if reactor_preview else industry.cable_error(state, point)
	var tint := CYAN if error.is_empty() else AMBER
	if reactor_preview:
		draw_dashed_line(screen_point(Industry.REACTOR_STAGING), cursor, tint, 1.0, 7.0)
		draw_auxiliary_reactor(point, Color(tint, 0.65), false)
	else:
		draw_dashed_line(screen_point(industry.reactor_position), cursor, tint, 2.0, 7.0)
		draw_dashed_line(cursor, screen_point(industry.refinery.position), tint, 2.0, 7.0)
	var caption := error
	if error.is_empty():
		caption = "Click to place reactor" if reactor_preview else "Click to install · %d conduit" % industry.route_cost(point)
	write(cursor.clamp(Vector2(12, 24), size - Vector2(320, 24)) + Vector2(0, -9), caption, tint, 13)

func draw_refinery_preview(state: State) -> void:
	var cursor := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(cursor):
		return
	var point := world_point(cursor)
	var error := state.refinery_placement_error(point)
	var tint := Color("#8cdebb") if error.is_empty() else Color("#f0aa79")
	draw_dashed_line(screen_point(State.REFINERY_STAGING), cursor, Color(tint, 0.6), 1.0, 6.0)
	draw_refinery_assembly(point, Color(tint, 0.65))
	var extent := State.REFINERY_SIZE * zoom
	draw_rect(Rect2(cursor - extent * 0.5, extent), tint, false, 1.0)
	var caption := "Click to anchor here" if error.is_empty() else error
	write(Vector2(clampf(cursor.x, 12.0, maxf(12.0, size.x - 300.0)), maxf(20.0, cursor.y - extent.y * 0.5 - 10.0)),
		caption, tint, 13)

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
	# The texture faces right. Keep the hull at physical scale and the reticle readable.
	var hull_length := State.CONTROLLER_WORLD_LENGTH * zoom
	var sprite_size := CONTROLLER_SPRITE.get_size() * (hull_length / CONTROLLER_SPRITE.get_width())
	draw_set_transform(center, state.heading, Vector2.ONE)
	draw_texture_rect(CONTROLLER_SPRITE, Rect2(-sprite_size * 0.5, sprite_size), false)
	draw_set_transform(Vector2.ZERO)
	var marker_radius := maxf(9.0, hull_length * 0.57)
	reticle(center, CYAN, marker_radius)
	var forward := Vector2.from_angle(state.heading)
	draw_line(center + forward * (marker_radius + 1.0), center + forward * (marker_radius + 5.0),
		CYAN, 1.5, true)
	write(center + Vector2(marker_radius + 6.0, 10.0), state.name_text.to_upper(), CYAN, 13)
