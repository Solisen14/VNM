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
	game.state.phase_time = 3.0
	game._physics_process(0.01)
	assert(game.insight_popup.visible, "Sensor briefing did not appear")
	var briefed_at: float = game.state.phase_time
	game._physics_process(1.0)
	assert(game.state.phase_time == briefed_at, "Briefing did not pause the tutorial")
	game.insight_open_button.pressed.emit()
	assert(game.objective_flight != null and game.active_hud.visible, "Objective did not start docking")
	await create_timer(0.45).timeout
	assert(game.objective_flight == null and game.objective_docked.modulate.a == 1.0, "Objective did not finish docking")
	game.state.set_phase(State.Phase.HAULING)
	game.state.scanned = {"ore": true, "miner": true, "wreck": true}
	game.state.active_drones = 1
	game.state.salvage_insight_ready = true
	game._physics_process(0.01)
	assert(game.insight_popup.visible, "Second Insight should pause the simulation")
	assert(game.insight_headline.text.contains("Why is the ore stockpiling here?"),
		"Missing intake motivation on second Insight popup")
	var insight_key := InputEventKey.new()
	insight_key.physical_keycode = KEY_I
	insight_key.pressed = true
	game._unhandled_key_input(insight_key)
	assert(game.state.salvage_insight_unlocked, "Opening the tree didn't unlock salvage")
	assert(not game.insight_popup.visible, "Salvage popup stayed open")
	assert(game.state.is_visible("salvage_1") and game.state.is_visible("salvage_3"),
		"New repairable workers not pinged")
	game.refresh()
	assert(game.research_status.text.contains("Salvage unlocked"), "Insight tree didn't advance")
	assert(game.research.visible and game.insight_tree_nodes.size() == 5, "Insight window did not show the progression")
	game.inventory_button.pressed.emit()
	assert(game.inventory.visible and not game.research.visible, "Cargo button did not switch windows")
	game.state.ore = 2
	game.state.cargo_fe = 2
	game.refresh()
	assert(game.cargo_capacity.value == 2 and game.cargo.text.contains("Fe 2"), "Cargo display did not update")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_key_input(escape)
	assert(not game.inventory.visible, "Escape did not close cargo")
	game.state.refinery_exposed = true
	game.state.refinery_phase = State.RefineryPhase.EXPOSED
	game._physics_process(0.01)
	assert(game.insight_popup.visible and game.insight_headline.text.contains("recover the refinery"))
	game._unhandled_key_input(insight_key)
	assert(game.state.refinery_phase == State.RefineryPhase.DISCONNECTING)
	game._unhandled_key_input(escape)
	game.state.refinery_phase = State.RefineryPhase.STAGED
	game.state.refinery_position = State.REFINERY_STAGING
	game.refresh()
	assert(game.placement_button.visible)
	game.placement_button.pressed.emit()
	assert(game.placing_refinery)
	var site := State.REFINERY_STAGING + Vector2(240, -130)
	game.state.player = site + Vector2(30, 0)
	game.state.chart_position()
	game.map.queue_redraw()
	await process_frame
	game.left_command(State.REFINERY_BAY)
	assert(game.placing_refinery and game.state.refinery_phase == State.RefineryPhase.STAGED)
	game._unhandled_key_input(escape)
	assert(not game.placing_refinery)
	game.placement_button.pressed.emit()
	game.left_command(site)
	assert(not game.placing_refinery and game.state.refinery_phase == State.RefineryPhase.HAULING)
	assert(not game.state.has_destination, "Placement also issued a flight waypoint")
	game.restart()
	assert(not game.research.visible and not game.inventory.visible and not game.active_hud.visible,
		"Restart left a gameplay overlay open")
	print("PASS: VNM Insight windows, objective HUD and refinery placement controls")
	quit(0)
