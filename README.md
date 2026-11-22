# VNM

A Godot 4 prototype about five surviving control drones. The project opens at Dock 03.

## Run

1. On GitHub, choose **Code → Download ZIP** and extract the project.
2. Open Godot 4. In Project Manager, click **Import** and select `project.godot`.
3. Press **F5** to play.

## Dock 03

After the fleet recall, watch the local network reboot or choose **Skip opening**. Move with **WASD** or right-click a point on the map. Left-click a contact, fly within reach, and use the action in the sidebar. Middle-drag pans and the mouse wheel zooms. **Follow drone** recenters the camera.

Inspect Worker 031, recover a repair kit from the service locker, and take it to the wreck stockpile. The control module stays reserved until you authorize its use. Bring it back to Worker 031 and fit it. Then select the scrap cache as its pickup and the wreck stockpile as its drop-off. The worker keeps hauling on its own while you explore. The sidebar shows your cargo, stock on hand, and cargo in transit separately.

## Earlier factory prototype

Open `main.tscn` and press **F6** to run the earlier single-system sandbox and its original mining-drone opening.

### From wreck to factory

1. Watch the fleet recall and blast, or choose **Skip intro**. The five survivors resume their original mining orders.
2. When their holds fill, select **Insight · Coordinate the Five**. This brings the refinery online and unlocks separate priorities for each founder.
3. Select a founder and raise **Salvage** to 100. They recover frames or control modules from amber debris and carry them to the wreck. Spend one control module to restore the maintenance fabricator.
4. The refinery separates ore into iron, carbon, copper, and silicon according to the field’s composition. The fabricator makes frames from 3 iron and 1 carbon, and control modules from 2 copper and 2 silicon. The wreck holds the element and component inventories.
5. With **Restore** enabled, a founder can collect a control module and carry it to a disabled violet drone. The restored miner follows its original orders. Lower **Restore** if you want to reserve modules for construction.
6. Spend **3 frames and 2 control modules** to place the drone factory. Apply a template once. Haulers stock the factory’s internal inventory, and it assembles drones continuously using one frame and one module each. Apply different priorities to start a new generation.

Founders are individually programmable. A mine-only founder caches ore at the field so a haul-only founder can collect it. Fabricated drones inherit the active template. Use **Service** for routine wear and **Restore** for disabled miners.

## Map and controls

- Drag to pan, scroll to zoom, and click drones or wreckage to inspect them.
- Spend one frame on a relay near the right edge of the cyan sensor circle. The outer field is richer in copper and silicon. Choose a mining preference once it is charted.
- Use **1×** to cycle speed, **Pause** to stop time, or **Restart** to replay the opening.

`opening.gd` runs the fleet recall and blast. `simulation.gd` runs drone decisions and production. `system_map.gd` draws the map. `main.gd` handles the interface.
