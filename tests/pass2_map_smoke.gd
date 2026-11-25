extends SceneTree

# Exercise the live Godot map at a real tutorial gameplay phase, not just
# parse the scripts at boot. This catches missing render data and UI regressions.
const State = preload("res://reboot_state.gd")

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var scene: PackedScene = load("res://reboot.tscn")
	assert(scene != null, "Main reboot scene missing")
	var game: Control = scene.instantiate()
	root.add_child(game)
	await process_frame
	game.state.begin("HAL")
	game.state.set_phase(State.Phase.HAULING)
	game.state.scanned = {"ore": true, "miner": true, "wreck": true}
	game.state.active_drones = 1
	assert(game.state.choose_mining_site(), "No asteroid available")
	assert(game.map.rock_textures.size() == 26, "Per-asteroid textures were not built")
	game.map.hover = "ore"
	game.map.zoom = 2.0
	game.map.camera = State.FIELD
	game.map.following = false
	game.state.miner_position = game.state.miner_worksite
	game.state.miner_work_time = State.MINER_EXTRACTION_TIME * 0.55
	game.refresh()
	game.map.queue_redraw()
	await process_frame
	await process_frame
	assert(game.map.rock_erased[game.state.miner_rock] > 0,
		"An active workface did not erode during extraction")
	assert(game.cargo.text.contains("WORKER NETWORK"), "Missing comms status UI")
	assert(game.cargo.text.contains("Fe"), "Missing element stock readout")
	game.state.tick_miner(State.MINER_EXTRACTION_TIME * 0.5)
	game.map.queue_redraw()
	await process_frame
	# Local salvage masking must only cut the currently worked hull section.
	game.state.salvage_insight_ready = true
	game.state.unlock_salvage()
	game.state.hull_site_units[0] = 2
	game.state.hull_extracted = 2
	game.map.queue_redraw()
	await process_frame
	await process_frame
	assert(game.map.wreck_site_erased[0] > 0, "Local salvage face failed to cut hull pixels")
	assert(game.map.wreck_site_erased[1] == 0 and game.map.wreck_site_erased[2] == 0,
		"Other salvage sites eroded before workers reached them")
	print("PASS: VNM Pass 2/3 gameplay HUD, asteroid erosion and localized hull salvage")
	quit(0)
