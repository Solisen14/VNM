extends Control

const Motion = preload("res://worker_motion.gd")
const INBOUND := Vector2(-350, 0)
const OUTBOUND := Vector2(350, 0)
const MAX_SPEED := 110.0
const ACCELERATION := 70.0

var positions: Array[Vector2] = []
var velocities: Array[Vector2] = []
var flight_clocks: Array[float] = []
var docking_delays: Array[float] = []
var to_outbound: Array[bool] = []
var selected_count := 10

func _ready() -> void:
	get_window().min_size = Vector2i(900, 620)
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(18, 16)
	toolbar.add_theme_constant_override("separation", 8)
	add_child(toolbar)
	var heading := Label.new()
	heading.text = "VNM  /  SWARM FLIGHT LAB"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("#e5f1ef"))
	toolbar.add_child(heading)
	for count in [1, 10, 100, 1000]:
		var button := Button.new()
		button.text = "%d workers" % count
		button.pressed.connect(configure.bind(count))
		toolbar.add_child(button)
	configure(10)

func configure(count: int) -> void:
	selected_count = count
	positions.clear()
	velocities.clear()
	flight_clocks.clear()
	docking_delays.clear()
	to_outbound.clear()
	for i in range(count):
		var p := float(i) / float(maxi(count, 1))
		var origin := INBOUND.lerp(OUTBOUND, p)
		origin.y += float(posmod(i * 23, 47) - 23) * 1.3
		positions.append(origin)
		velocities.append(Vector2.ZERO)
		flight_clocks.append(float(i % 19) * 0.37)
		docking_delays.append(0.0)
		to_outbound.append(i % 2 == 0)
	queue_redraw()

func _physics_process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for i in range(positions.size()):
		if docking_delays[i] > 0.0:
			docking_delays[i] = maxf(0.0, docking_delays[i] - dt)
			continue
		var target := OUTBOUND if to_outbound[i] else INBOUND
		var distance := positions[i].distance_to(target)
		if distance <= 2.5:
			positions[i] = target
			velocities[i] = Vector2.ZERO
			docking_delays[i] = 0.7 + float(i % 7) * 0.19
			to_outbound[i] = not to_outbound[i]
			flight_clocks[i] = 0.0
			continue
		flight_clocks[i] += dt
		var new_velocity := Motion.next_velocity(
			positions[i], velocities[i], target, dt,
			flight_clocks[i], float(i) * 0.618, MAX_SPEED, ACCELERATION
		)
		velocities[i] = new_velocity
		var step := new_velocity * dt
		if step.length() >= distance:
			positions[i] = target
		else:
			positions[i] += step
	queue_redraw()

func to_screen(point: Vector2) -> Vector2:
	var factor := minf(size.x / 960.0, size.y / 620.0)
	return size * 0.5 + point * factor

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#080e13"))
	for i in range(145):
		var p := Vector2(fposmod(i * 183.4, size.x), fposmod(i * i * 29.9, size.y))
		draw_circle(p, 0.55, Color(0.65, 0.76, 0.82, 0.28), true)
	var source := to_screen(INBOUND)
	var destination := to_screen(OUTBOUND)
	draw_circle(source, 24, Color("#283b3d"), true)
	draw_circle(source, 25, Color("#809b9d"), false, 1.2)
	draw_circle(destination, 37, Color("#263337"), true)
	draw_circle(destination, 38, Color("#a08b72"), false, 1.2)
	draw_string(get_theme_default_font(), source + Vector2(-46, 43), "ORE FIELD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c7d3d5"))
	draw_string(get_theme_default_font(), destination + Vector2(-60, 56), "WRECK STOCKPILE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c7d3d5"))
	for i in range(positions.size()):
		var at := to_screen(positions[i])
		draw_circle(at, 3.1, Color(0.72, 0.89, 1.0, 0.17), true)
		draw_circle(at, 1.05, Color("#f7fcff"), true)
	draw_string(get_theme_default_font(), Vector2(18, size.y - 41),
		"Workers: %d    |    FPS: %d    |    Shared flight physics" % [selected_count, Engine.get_frames_per_second()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#c3d3d2"))
	draw_string(get_theme_default_font(), Vector2(18, size.y - 18),
		"Visual steering stress test only. Flocking, obstacle avoidance and material processing arrive in later passes.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#92a9ac"))
