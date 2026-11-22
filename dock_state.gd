extends RefCounted

signal milestone(title: String, message: String, action: String)

const START := Vector2(135, 180)
const WORKER := Vector2(390, 280)
const SALVAGE := Vector2(-230, 365)
const CACHE := Vector2(640, 440)
const DEPOT := Vector2(-20, 280)
const OBSERVATION := Vector2(-600, 350)
const DOCK := Vector2(50, 45)
const REACH := 84.0
const CARGO_SLOTS := 4
const WORKER_CAPACITY := 3
const CACHE_INITIAL := 27

enum Phase { APPROACH, SALVAGE_PART, RETURN_PART, AUTHORIZE, REPAIR, ROUTE_SOURCE, ROUTE_DESTINATION, RUNNING }

var phase := Phase.APPROACH
var player := START
var destination := START
var worker := WORKER
var secured_module := false
var cargo_module := false
var cargo_scrap := 0
var wreck_scrap := 0
var cache_scrap := CACHE_INITIAL
var worker_cargo := 0
var deliveries := 0
var to_cache := true
var worker_heading := 0.0
var player_heading := 0.0
var shipmates: Array[String] = ["Pip", "Moxie", "Cricket", "Finch", "Nell"]

func tick(delta: float, steering: Vector2) -> void:
	if steering != Vector2.ZERO:
		destination = player + steering.normalized() * 150.0
	var old_position := player
	player = player.move_toward(destination, 220.0 * delta)
	if player != old_position:
		player_heading = old_position.angle_to_point(player)
	if phase == Phase.RUNNING:
		update_route(delta)

func update_route(delta: float) -> void:
	var waypoint := CACHE if to_cache else DEPOT
	if to_cache and cache_scrap == 0 and worker == CACHE:
		return
	if worker != waypoint:
		worker_heading = worker.angle_to_point(waypoint)
		worker = worker.move_toward(waypoint, 150.0 * delta)
		return
	if to_cache:
		worker_cargo = mini(WORKER_CAPACITY, cache_scrap)
		cache_scrap -= worker_cargo
		to_cache = worker_cargo == 0
	else:
		wreck_scrap += worker_cargo
		worker_cargo = 0
		to_cache = true
		deliveries += 1
		if deliveries == 1:
			milestone.emit("First delivery confirmed", "Worker 031 unloaded scrap at the stockpile. The route will keep running while you survey the wreck.", "Resume operations")

func target_position(contact: String) -> Vector2:
	match contact:
		"worker": return worker
		"salvage": return SALVAGE
		"cache": return CACHE
		"depot": return DEPOT
		"observation": return OBSERVATION
	return DOCK

func nearby(contact: String) -> bool:
	return player.distance_to(target_position(contact)) <= REACH

func action_label(contact: String) -> String:
	match phase:
		Phase.APPROACH:
			if contact == "worker": return "Inspect diagnostics"
		Phase.SALVAGE_PART:
			if contact == "salvage": return "Recover repair kit"
		Phase.RETURN_PART:
			if contact == "depot": return "Deposit salvage"
		Phase.AUTHORIZE:
			if contact == "depot": return "Authorize repair"
		Phase.REPAIR:
			if contact == "worker": return "Fit control module"
		Phase.ROUTE_SOURCE:
			if contact == "cache": return "Set pickup"
		Phase.ROUTE_DESTINATION:
			if contact == "depot": return "Set drop-off & start route"
	return ""

func requires_proximity() -> bool:
	return phase in [Phase.APPROACH, Phase.SALVAGE_PART, Phase.RETURN_PART, Phase.REPAIR]

func act(contact: String) -> void:
	if action_label(contact).is_empty() or (requires_proximity() and not nearby(contact)):
		return
	match phase:
		Phase.APPROACH:
			phase = Phase.SALVAGE_PART
		Phase.SALVAGE_PART:
			cargo_module = true
			cargo_scrap = 2
			phase = Phase.RETURN_PART
		Phase.RETURN_PART:
			secured_module = true
			cargo_module = false
			wreck_scrap += cargo_scrap
			cargo_scrap = 0
			phase = Phase.AUTHORIZE
			milestone.emit("Control module secured", "The replacement module is reserved at the stockpile. Authorize the repair when you’re ready to carry it back to Worker 031.", "Authorize repair")
		Phase.AUTHORIZE:
			cargo_module = true
			secured_module = false
			phase = Phase.REPAIR
		Phase.REPAIR:
			cargo_module = false
			phase = Phase.ROUTE_SOURCE
			milestone.emit("Worker 031 reporting", "Its drive is online. Select the scrap cache as a pickup point, then the stockpile as the drop-off. Worker 031 will shuttle between them.", "Plan a route")
		Phase.ROUTE_SOURCE:
			phase = Phase.ROUTE_DESTINATION
		Phase.ROUTE_DESTINATION:
			phase = Phase.RUNNING

func next_contact() -> String:
	match phase:
		Phase.APPROACH, Phase.REPAIR: return "worker"
		Phase.SALVAGE_PART: return "salvage"
		Phase.RETURN_PART, Phase.AUTHORIZE, Phase.ROUTE_DESTINATION: return "depot"
		Phase.ROUTE_SOURCE: return "cache"
	return ""

func objective() -> String:
	match phase:
		Phase.APPROACH: return "Approach Worker 031 and inspect its drive."
		Phase.SALVAGE_PART: return "Recover the repair kit from the open service locker."
		Phase.RETURN_PART: return "Bring the salvaged parts to the stockpile."
		Phase.AUTHORIZE: return "Authorize the reserved module for Worker 031."
		Phase.REPAIR: return "Return to Worker 031 and fit the module."
		Phase.ROUTE_SOURCE: return "Select a scrap cache as the route’s pickup point."
		Phase.ROUTE_DESTINATION: return "Select the stockpile as the drop-off and start the route."
	if deliveries == 0:
		return "Watch Worker 031 complete its first haul."
	return "Route established. Survey the aft breach while Worker 031 keeps hauling."
