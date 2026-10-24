class_name WaveComposition
extends Resource
## One Inspector-editable wave mix. Weights need not add up to one.
@export_range(1, 1000) var wave: int = 1
@export_range(0.0, 100.0, 0.05) var skeleton: float = 1.0
@export_range(0.0, 100.0, 0.05) var zombie: float = 0.0
@export_range(0.0, 100.0, 0.05) var archer: float = 0.0
@export_range(0.0, 100.0, 0.05) var slime: float = 0.0
@export_range(0.0, 100.0, 0.05) var boss: float = 0.0

func weights() -> Dictionary:
	var result: Dictionary = {}
	for kind in ["skeleton", "zombie", "archer", "slime", "boss"]:
		var weight := float(get(kind))
		if weight > 0.0:
			result[kind] = weight
	return result
