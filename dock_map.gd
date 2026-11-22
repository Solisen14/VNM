extends Control

const Mission = preload("res://dock_state.gd")
const Opening = preload("res://opening.gd")
const CYAN := Color("#9adbd4")
const AMBER := Color("#efb16d")
const INK := Color("#0b1112")
const ART_RECT := Rect2(-1220, -285, 2440, 1372.5)
const CONTACTS := ["worker", "salvage", "cache", "depot", "observation", "dock"]

var game: Control
var camera := Vector2(155, 155)
var zoom := 0.83
var following := false
var dragging := false
var hull: Texture2D
var intact_hull: Texture2D

func _ready() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hull = load_ship_art("res://assets/mothership.webp")
	intact_hull = load_ship_art("res://assets/mothership-intact.webp")

func load_ship_art(path: String) -> Texture2D:
	# A source checkout has the image even before Godot creates its import cache.
	# Exported builds use the imported texture when the original file is absent.
	if FileAccess.file_exists(path):
		var pixels := Image.new()
		var error := pixels.load_webp_from_buffer(FileAccess.get_file_as_bytes(path))
		if error == OK:
			pixels.generate_mipmaps()
			return ImageTexture.create_from_image(pixels)
	elif ResourceLoader.exists(path, "Texture2D"):
		var imported := ResourceLoader.load(path, "Texture2D") as Texture2D
		if imported != null:
			return imported
	push_error("Dock 03 could not load mothership artwork at %s" % path)
	return null

func reset_view() -> void:
	camera = Vector2(155, 155)
	zoom = 0.83
	following = false

func follow_player() -> void:
	following = true
	camera = game.state.player

func world_point(point: Vector2) -> Vector2:
	return (point - size * 0.5) / zoom + camera

func screen_point(point: Vector2) -> Vector2:
	return (point - camera) * zoom + size * 0.5

func _process(delta: float) -> void:
	if following:
		camera = camera.lerp(game.state.player, 1.0 - exp(-delta * 7.0))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			if dragging:
				following = false
		elif event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
					var fixed := world_point(event.position)
					var factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
					zoom = clampf(zoom * factor, 0.3, 1.65)
					camera += fixed - world_point(event.position)
					following = false
				MOUSE_BUTTON_RIGHT:
					if not game.cinematic and not game.tutorial_paused:
						game.state.destination = world_point(event.position).clamp(Vector2(-1120, -470), Vector2(1120, 700))
						following = true
				MOUSE_BUTTON_LEFT:
					if not game.cinematic:
						select_at(event.position)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		camera -= event.relative / zoom
		accept_event()

func select_at(point: Vector2) -> void:
	var distance := 56.0
	game.selected = ""
	for contact in CONTACTS:
		if not is_visible_contact(contact):
			continue
		var marker := screen_point(game.state.target_position(contact))
		var candidate := minf(point.distance_to(marker), point.distance_to(marker + contact_caption_offset(contact) + Vector2(20, -9)))
		if candidate < distance:
			game.selected = contact
			distance = candidate

func contact_caption_offset(contact: String) -> Vector2:
	if contact == "depot":
		return Vector2(13, 23)
	return Vector2(14, -10)

func is_visible_contact(contact: String) -> bool:
	return contact != "cache" or game.state.phase >= Mission.Phase.ROUTE_SOURCE

func contact_label(contact: String) -> String:
	match contact:
		"worker": return "Worker 031"
		"salvage": return "Service locker"
		"cache": return "Scrap cache"
		"depot": return "Wreck stockpile"
		"observation": return "Aft breach"
		"dock": return "Dock 03"
	return ""

func _draw() -> void:
	if not is_instance_valid(game):
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#090e11"))
	for i in range(100):
		var star := Vector2(fposmod(i * 161.73 - camera.x * 0.11, size.x + 1), fposmod(i * i * 29.1 - camera.y * 0.11, size.y + 1))
		draw_circle(star, 0.7, Color(0.56, 0.66, 0.68, 0.18 + (i % 4) * 0.06), true, -1, true)
	var plate := intact_hull if game.cinematic and game.time < game.BLAST_AT and intact_hull else hull
	if plate:
		draw_texture_rect(plate, Rect2(screen_point(ART_RECT.position), ART_RECT.size * zoom), false)
	else:
		write(Vector2(22, size.y - 24), "MOTHERSHIP ART UNAVAILABLE · CHECK PROJECT ASSETS", AMBER)
	if game.cinematic:
		draw_opening()
		return

	if game.state.phase >= Mission.Phase.ROUTE_DESTINATION:
		var start := screen_point(Mission.CACHE)
		var end := screen_point(Mission.DEPOT) if game.state.phase == Mission.Phase.RUNNING else get_local_mouse_position()
		draw_dashed_line(start, end, Color(CYAN, 0.72), 1.4, 8.0)
		if game.state.phase == Mission.Phase.RUNNING:
			var point := start.lerp(end, 0.5)
			var heading := (end - start).normalized()
			draw_polyline(PackedVector2Array([point - heading * 10 + heading.orthogonal() * 5, point, point - heading * 10 - heading.orthogonal() * 5]), CYAN, 1.5, true)
	if game.state.player.distance_to(game.state.destination) > 12.0:
		draw_dashed_line(screen_point(game.state.player), screen_point(game.state.destination), Color(CYAN, 0.32), 1.0, 6.0)
	var powered: bool = game.state.phase >= Mission.Phase.ROUTE_SOURCE
	draw_craft(game.state.worker, game.state.worker_heading, CYAN if powered else AMBER, powered, 0.82)
	draw_craft(game.state.player, game.state.player_heading, CYAN, true, 1.0)
	var player_marker := screen_point(game.state.player)
	reticle(player_marker, CYAN, 12.0)
	write(player_marker + Vector2(15, 19), game.state.shipmates[0].to_upper(), CYAN)
	for contact in CONTACTS:
		if not is_visible_contact(contact):
			continue
		var point := screen_point(game.state.target_position(contact))
		var active: bool = game.selected == contact
		var relevant: bool = game.state.next_contact() == contact
		var tint := AMBER if (contact == "worker" and not powered) or relevant else Color("#b4c6c8")
		reticle(point, tint if active or relevant else Color(tint, 0.60), 16.0 if active else 10.0)
		write(point + contact_caption_offset(contact), contact_label(contact).to_upper(), tint)

func draw_opening() -> void:
	var elapsed: float = game.time
	if elapsed < game.BLAST_AT:
		var route_time := elapsed * Opening.RECALL_AT / 4.5 if elapsed < 4.5 else Opening.RECALL_AT + elapsed - 4.5
		var fleet_limit := 256
		for i in range(fleet_limit):
			var location: Vector2 = game.opening.position_at(i, route_time)
			var point := screen_point(Vector2(100, 95) + (location - Vector2(-150, 75)) * 1.75)
			draw_circle(point, 1.5 + (i % 3) * 0.27, AMBER if i % 3 == 0 else CYAN, true, -1, true)
		draw_craft(game.state.player, 0.30, CYAN, true, 1.0)
		var anchor := screen_point(game.state.player)
		reticle(anchor, CYAN, 12.0)
		write(anchor + Vector2(15, 19), game.state.shipmates[0].to_upper(), CYAN)
		var header := "ORE TRANSFER ACTIVE" if elapsed < 4.5 else "FLEET RECALL"
		write(Vector2(20, 28), header, CYAN, 16)
	elif elapsed < game.REBOOT_AT:
		var age: float = elapsed - game.BLAST_AT
		var origin := screen_point(Vector2(98, 50))
		var flash := maxf(0.0, 1.0 - age * 3.25)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.02, clampf(age * 1.6, 0.0, 1.0)))
		draw_circle(origin, 38 + age * 155, Color(1.0, 0.58, 0.29, flash), true, -1, true)
		draw_arc(origin, 28 + age * 390, 0, TAU, 84, Color(1.0, 0.64, 0.37, 0.70 * flash), 2, true)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.90, 0.74, flash * 0.55))
	else:
		var boot_age: float = elapsed - game.REBOOT_AT
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.05, maxf(0.0, 0.96 - boot_age * 0.65)))
		var lines := ["ATTITUDE CONTROL RESTORED", "LOCAL OPTICS ONLINE", "MOTHERSHIP LINK UNAVAILABLE"]
		for i in range(3):
			if boot_age >= i * 0.6:
				write(Vector2(24, 35 + 22 * i), lines[i], AMBER if i == 2 else CYAN, 15)
		for i in range(1, 5):
			if boot_age >= 1.4 + i * 0.56:
				write(Vector2(24, 116 + 20 * i), "%s   /   PEER ONLINE" % game.state.shipmates[i].to_upper(), CYAN, 14)
		if boot_age > 1.1:
			draw_craft(game.state.player, 0.30, CYAN, true, 1.0)

func draw_craft(location: Vector2, heading: float, tint: Color, lights: bool, scale_factor: float) -> void:
	var center := screen_point(location)
	var unit := clampf(zoom, 0.62, 1.5) * scale_factor
	var silhouette := PackedVector2Array([Vector2(-10, -6), Vector2(4, -6), Vector2(11, -3), Vector2(11, 3), Vector2(4, 6), Vector2(-10, 6)])
	for i in range(silhouette.size()):
		silhouette[i] = center + silhouette[i].rotated(heading) * unit
	draw_colored_polygon(silhouette, Color("#90948c") if lights else Color("#5f5e58"))
	silhouette.append(silhouette[0])
	draw_polyline(silhouette, tint.darkened(0.36), 1.0, true)
	if lights:
		for engine in [-3, 3]:
			var point := center + Vector2(-11, engine).rotated(heading) * unit
			draw_circle(point, 3.0 * unit, Color(tint, 0.25), true, -1, true)
			draw_circle(point, 1.45 * unit, tint, true, -1, true)

func reticle(point: Vector2, tint: Color, radius: float) -> void:
	for x in [-1, 1]:
		for y in [-1, 1]:
			var corner := point + Vector2(x, y) * radius
			draw_line(corner, corner - Vector2(x * 5, 0), tint, 1.5, true)
			draw_line(corner, corner - Vector2(0, y * 5), tint, 1.5, true)

func write(point: Vector2, caption: String, tint: Color, text_size := 13) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_rect(Rect2(point + Vector2(-3, -text_size + 1), Vector2(width + 7, text_size + 5)), Color(INK, 0.90))
	draw_string(font, point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, tint)
