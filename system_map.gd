extends Control

const Simulation = preload("res://simulation.gd")
const CYAN := Color("#76e5ec")
const GOLD := Color("#f5bd76")
const DIM := Color("#76899c")
const PALETTE := [CYAN, GOLD, Color("#cba7fc"), Color("#9ee1a7")]

var game: Control
var centre := Vector2(140, 0)
var zoom := 0.85
var stars := PackedVector3Array()
var drag_started := false
var dragged := false
var press_at := Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 784
	for i in range(620):
		stars.append(Vector3(rng.randf_range(0, 1800), rng.randf_range(0, 1100), rng.randf()))

func recenter() -> void:
	centre = Vector2(140, 0)
	zoom = 0.85

func world_point(point: Vector2) -> Vector2:
	return (point - size / 2.0) / zoom + centre

func screen_point(point: Vector2) -> Vector2:
	return (point - centre) * zoom + size / 2.0

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var anchor := world_point(event.position)
			var factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
			zoom = clampf(zoom * factor, 0.32, 3.4)
			centre += anchor - world_point(event.position)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag_started = true
				dragged = false
				press_at = event.position
			elif drag_started:
				drag_started = false
				if not dragged:
					map_click(event.position)
			accept_event()
	elif event is InputEventMouseMotion and drag_started:
		dragged = dragged or event.position.distance_to(press_at) > 5.0
		if dragged:
			centre -= event.relative / zoom

func map_click(point: Vector2) -> void:
	if not game.placement.is_empty():
		if game.sim.place(game.placement, world_point(point)):
			game.placement = ""
		return
	var nearest := 17.0
	game.selected = -1
	for i in range(game.sim.drones.size()):
		var drone = game.sim.drones[i]
		if game.sim.in_coverage(drone.position):
			var distance := point.distance_to(screen_point(drone.position))
			if distance < nearest:
				nearest = distance
				game.selected = i

func _draw() -> void:
	if not is_instance_valid(game):
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#080e1b"))
	for star in stars:
		var parallax := 0.08 + star.z * 0.11
		var x := fposmod(star.x - centre.x * parallax, 1800.0)
		var y := fposmod(star.y - centre.y * parallax, 1100.0)
		var tint := Color(0.57, 0.68, 0.85, 0.16 + star.z * 0.54)
		draw_circle(Vector2(x, y), 0.55 + star.z * 0.85, tint, true, -1, true)
	draw_grid()
	draw_coverage(Simulation.WRECK, Simulation.HOME_RANGE)
	if game.sim.relay_online:
		draw_coverage(game.sim.relay_position, Simulation.RELAY_RANGE)
	if game.sim.relay:
		var origin := screen_point(Simulation.WRECK)
		var target := screen_point(game.sim.relay_position)
		draw_dashed_line(origin, target, Color("#3d6171"), 1.0, 6.0)
	if game.sim.factory:
		draw_dashed_line(screen_point(Simulation.WRECK), screen_point(game.sim.factory_position), Color("#6b5741"), 1.0, 6.0)
	draw_field(Simulation.INNER, "INNER ORE FIELD", 0, true)
	if game.sim.outer_seen:
		draw_field(Simulation.OUTER, "OUTER ORE FIELD", 1, game.sim.in_coverage(Simulation.OUTER))
	draw_wreck()
	if game.sim.factory:
		draw_structure(game.sim.factory_position, "DRONE FACTORY", GOLD, false)
	if game.sim.relay:
		var relay_label := "SENSOR RELAY" if game.sim.relay_online else "RELAY OFFLINE"
		var tint := CYAN if game.sim.relay_online else DIM
		draw_structure(game.sim.relay_position, relay_label, tint, true)
	for i in range(game.sim.drones.size()):
		var drone = game.sim.drones[i]
		if game.sim.in_coverage(drone.position):
			draw_drone(drone, i == game.selected)
	if not game.placement.is_empty():
		var pointer := get_local_mouse_position()
		if Rect2(Vector2.ZERO, size).has_point(pointer):
			var valid: bool = game.sim.place_error(game.placement, world_point(pointer)).is_empty()
			var tint := CYAN if valid else Color("#ee8585")
			draw_arc(pointer, 16.0, 0.0, TAU, 32, tint, 1.5, true)
			draw_line(pointer - Vector2(8, 0), pointer + Vector2(8, 0), tint)
			draw_line(pointer - Vector2(0, 8), pointer + Vector2(0, 8), tint)
	write(Vector2(24, 35), "HOME SYSTEM", 17, Color("#e1ecfa"))
	write(Vector2(24, 57), "Cyan boundary · live sensor coverage", 12, DIM)

func draw_grid() -> void:
	var interval := 100.0 * zoom
	var origin := screen_point(Vector2.ZERO)
	var grid := Color(0.29, 0.41, 0.57, 0.13)
	var x := fposmod(origin.x, interval)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid)
		x += interval
	var y := fposmod(origin.y, interval)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), grid)
		y += interval

func draw_coverage(origin: Vector2, radius: float) -> void:
	var point := screen_point(origin)
	draw_circle(point, radius * zoom, Color(0.16, 0.57, 0.68, 0.085), true, -1, true)
	draw_arc(point, radius * zoom, 0.0, TAU, 120, Color("#386d7c"), 1.0, true)

func draw_wreck() -> void:
	var point := screen_point(Simulation.WRECK)
	var tint := CYAN if game.sim.refinery else GOLD
	var shape := PackedVector2Array([Vector2(-21,-6), Vector2(10,-10), Vector2(21,-1), Vector2(11,8), Vector2(-5,7), Vector2(-21,3)])
	for i in range(shape.size()):
		shape[i] = point + shape[i] * clampf(zoom, 0.8, 1.55)
	draw_colored_polygon(shape, tint.darkened(0.65))
	shape.append(shape[0])
	draw_polyline(shape, tint, 1.5, true)
	draw_line(point + Vector2(-7, -9), point + Vector2(0, 9), tint, 1.5, true)
	var title := "SALVAGED REFINERY" if game.sim.refinery else "MINING SHIP WRECK"
	write(point + Vector2(-48, 32), title, 13, tint)

func draw_field(location: Vector2, title: String, number: int, live: bool) -> void:
	var point := screen_point(location)
	var rng := RandomNumberGenerator.new()
	rng.seed = 533 + number
	var tint := Color("#a5b7c9") if live else DIM.darkened(0.30)
	for i in range(13):
		var offset := Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(5, 48) * zoom
		var radius := rng.randf_range(2, 7) * clampf(zoom, 0.7, 1.5)
		var rock := PackedVector2Array()
		for vertex in range(6):
			rock.append(point + offset + Vector2.from_angle(vertex * TAU / 6.0) * radius * rng.randf_range(0.8, 1.2))
		draw_colored_polygon(rock, tint.darkened(0.6))
		rock.append(rock[0])
		draw_polyline(rock, tint, 1.0, true)
	write(point + Vector2(-46, -51 * zoom - 5), title, 13, tint)
	var status := "%d ore" % game.sim.ore_remaining[number] if live else "Last known position · signal lost"
	write(point + Vector2(-46, -51 * zoom + 13), status, 12, tint)

func draw_structure(location: Vector2, title: String, tint: Color, triangular: bool) -> void:
	var point := screen_point(location)
	var corners := 3 if triangular else 4
	var shape := PackedVector2Array()
	for i in range(corners):
		shape.append(point + Vector2.from_angle(-PI / 2.0 + i * TAU / corners) * 12)
	draw_colored_polygon(shape, tint.darkened(0.67))
	shape.append(shape[0])
	draw_polyline(shape, tint, 1.5, true)
	draw_circle(point, 2.2, tint, true, -1, true)
	write(point + Vector2(-34, 29), title, 12, tint)

func draw_drone(drone: Simulation.Drone, selected: bool) -> void:
	var point := screen_point(drone.position)
	var tint: Color = PALETTE[(drone.generation - 1) % PALETTE.size()]
	var angle: float = drone.position.angle_to_point(drone.target)
	var front := Vector2.from_angle(angle)
	var side := front.orthogonal()
	var shape := PackedVector2Array([point + front * 7.0, point - front * 4.0 + side * 4.0, point - front * 4.0 - side * 4.0])
	draw_colored_polygon(shape, tint)
	if selected:
		draw_arc(point, 11.0, 0, TAU, 32, tint, 1.4, true)
		draw_dashed_line(point, screen_point(drone.target), tint.darkened(0.48), 1.0, 5.0)
	if zoom >= 1.35 or selected:
		write(point + Vector2(11, -7), "%02d / G%d" % [drone.id, drone.generation], 12, tint)
	if zoom >= 1.35:
		draw_line(point + Vector2(-5, 9), point + Vector2(6, 9), tint.darkened(0.65), 2.0)
		draw_line(point + Vector2(-5, 9), point + Vector2(-5 + 11.0 * drone.ore / Simulation.CAPACITY, 9), tint, 2.0)

func write(point: Vector2, message: String, font_size: int, tint: Color) -> void:
	draw_string(get_theme_default_font(), point + Vector2(1, 1), message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#080e1b"))
	draw_string(get_theme_default_font(), point, message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
