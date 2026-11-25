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
	print("PASS: VNM Pass 3 paused Insight HUD and three new worker signals")
	quit(0)
