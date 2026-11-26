extends RefCounted
## One placed structure. A later logistics system can feed its dedicated buffers.

const MATERIALS := ["Fe", "Cu", "Si"]
const BUFFER_CAPACITY := 12

var position := Vector2.ZERO
var specialization := ""
var raw_input := 0
var refined_output := 0
var seconds_per_unit := 4.0
var power_draw := 18
var controller_id := 0
var repaired := false
var powered := false
var commissioned := false

func select_material(material: String) -> bool:
	if not specialization.is_empty() or material not in MATERIALS:
		return false
	specialization = material
	return true

func accepts_material(material: String) -> bool:
	return not specialization.is_empty() and material == specialization and raw_input < BUFFER_CAPACITY

func receive_raw(material: String, offered: int) -> int:
	if offered <= 0 or not accepts_material(material):
		return 0
	var accepted := mini(offered, BUFFER_CAPACITY - raw_input)
	raw_input += accepted
	return accepted

func can_operate() -> bool:
	return repaired and powered and controller_id != 0 and not specialization.is_empty()

func status() -> String:
	if not repaired:
		return "DAMAGED / OFFLINE"
	if not powered:
		return "RESTORED / UNPOWERED"
	if controller_id == 0:
		return "POWERED / CONTROL UNAVAILABLE"
	return "ONLINE / IDLE" if commissioned else "COMMISSIONING"
