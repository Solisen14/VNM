extends SceneTree

const State = preload("res://reboot_state.gd")

func _initialize() -> void:
	call_deferred("verify_insight")

func verify_insight() -> void:
	var scene: PackedScene = load("res://reboot.tscn")
	var game: Control = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.state.begin("HAL")
	game.state.set_phase(State.Phase.HAULING)
	game.state.scanned = {"ore": true, "miner": true, "wreck": true}
	game.state.active_drones = 1
	game.state.salvage_insight_ready = true
	await process_frame
	await process_frame
	assert(game.insight_popup.visible, "Second Insight should pause the simulation")
	assert(game.insight_headline.text.contains("Why is the ore stockpiling here?"),
		"Missing intake motivation on second Insight popup")
	game.open_first_insight()
	assert(game.state.salvage_insight_unlocked, "Opening the tree didn't unlock salvage")
	assert(not game.insight_popup.visible, "Salvage popup stayed open")
	assert(game.state.is_visible("salvage_1") and game.state.is_visible("salvage_3"),
		"New repairable workers not pinged")
	game.refresh()
	assert(game.research_status.text.contains("refinery-access plating"), "Insight tree didn't advance")
	assert(game.state.contact_name("stockpile") == "Collection Point", "Collection site reveals its function too early")
	# The reported screenshot showed HAL carrying three ore units: a repair
	# package takes another three slots, so the previous UI silently blocked it.
	game.state.ore = 3
	game.state.cargo_fe = 2
	game.state.cargo_cu = 1
	game.state.stock_fe = 10
	game.state.stock_cu = 6
	game.state.stock_ore = 16
	game.selected = "salvage_1"
	game.refresh()
	assert(game.prompt.text.contains("first unload HAL's cargo"), "Missing step-by-step repair prompt")
	assert(game.contact_details.text.contains("First unload"), "Damaged drone has no contextual repair explanation")
	game.state.issue("salvage_1")
	assert(game.state.notice.contains("First unload"), "Right-clicking a blocked worker gives no feedback")
	game.state.player = State.STOCKPILE
	game.state.velocity = Vector2.ZERO
	game.state.issue("stockpile")
	assert(game.state.work_action == "Unload raw ore", "Right-click could not unload HAL at Collection Point")
	game.state.tick_work(State.WORK_TIMES["Unload raw ore"] + 0.02)
	assert(game.state.ore == 0 and game.state.stock_ore == 19, "Ore was not deposited")
	game.state.issue("stockpile")
	assert(game.state.work_action == "Collect repair supplies", "No repair supply action after unloading")
	game.state.tick_work(State.WORK_TIMES["Collect repair supplies"] + 0.02)
	assert(game.state.repair_kits == 1, "Failed to collect repair kit")
	game.refresh()
	assert(game.prompt.text.contains("Repair supplies aboard!"), "Player not told to repair worker")
	game.state.player = State.SALVAGE_SPAWNS[0]
	game.state.issue("salvage_1")
	assert(game.state.work_action == "Repair worker", "Right-click on damaged worker didn't start repair")
	game.state.tick_work(State.WORK_TIMES["Repair worker"] + 0.02)
	assert(game.state.salvage_worker_active("salvage_1"), "Damaged worker didn't become active")
	assert(game.state.repair_kits == 0 and game.state.active_drones == 2, "Repair consumed incorrect resources")

	# Edge scrolling must decouple the camera from follow mode without
	# acting on ordinary map-center mouse movement or outside the viewport.
	game.map.camera = Vector2(100.0, 100.0)
	game.map.following = true
	var original: Vector2 = game.map.camera
	var edge := Vector2(game.map.size.x - 1.0, game.map.size.y * 0.5)
	game.map.pan_from_edge(edge, 0.25)
	assert(not game.map.following and game.map.camera.x > original.x,
		"Cursor-at-edge camera movement isn't working")
	var after: Vector2 = game.map.camera
	game.map.pan_from_edge(game.map.size * 0.5, 0.25)
	game.map.pan_from_edge(Vector2(-20, -20), 0.25)
	assert(game.map.camera.is_equal_approx(after), "Camera pans while the cursor is not at an edge")
	print("PASS: VNM Pass 3 UI, intuitive repair steps, Collection Point and camera edge scrolling")
	quit(0)
