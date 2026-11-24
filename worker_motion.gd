extends RefCounted

# Shared steering for individual miners and the optional Swarm Flight Lab.
# This is purposeful destination-seeking with a gentle lateral wander.
# It is not flocking yet: separation, cohesion and avoidance belong to Pass 2.
static func next_velocity(
	position: Vector2,
	velocity: Vector2,
	target: Vector2,
	delta: float,
	elapsed: float,
	seed: float,
	max_speed: float,
	acceleration: float
) -> Vector2:
	var offset := target - position
	var distance := offset.length()
	if distance < 0.01:
		return velocity.move_toward(Vector2.ZERO, acceleration * delta)
	var direction := offset / distance
	var lateral := direction.orthogonal()
	# Deterministic offsets create individual, gently bowed routes without
	# making workers lose track of their destination.
	var sway := 0.22 * sin(elapsed * 0.67 + seed * 1.9)
	sway += 0.07 * sin(elapsed * 1.31 + seed * 3.1)
	var arrival_fade := clampf(distance / 130.0, 0.0, 1.0)
	var curved_heading := (direction + lateral * sway * arrival_fade).normalized()
	# The approach speed falls with remaining distance, so the worker visibly
	# brakes before reaching a mining or unloading position.
	var braking_speed := sqrt(2.0 * acceleration * 0.70 * distance)
	var speed := minf(max_speed, braking_speed)
	return velocity.move_toward(curved_heading * speed, acceleration * delta)
