extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: Variant = NativeSandWorld.new()
	world.reset(66004, 1)
	var pacing: Dictionary = world.evaluate_progression_pacing(3564, 200000)
	var production: Dictionary = pacing.concentrate_recovery_cumulative
	var seconds := float(production.estimated_seconds)
	var glass_rate := float(production.glass) / seconds
	var iron_rate := float(production.iron) / seconds
	var gold_rate := float(production.gold) / seconds
	var order := ["automation.basic_sensing", "automation.logic_control", "automation.timed_control", "automation.machine_control", "automation.advanced_routing"]
	var definitions: Dictionary = {}
	for definition: Dictionary in world.get_research_definitions(): definitions[definition.id] = definition
	for research_id: String in order:
		var cost: Dictionary = definitions[research_id].costs
		var paths := {
			"automation.basic_sensing": ["automation.basic_sensing"],
			"automation.logic_control": ["automation.basic_sensing", "automation.logic_control"],
			"automation.timed_control": ["automation.basic_sensing", "automation.logic_control", "automation.timed_control"],
			"automation.machine_control": ["automation.basic_sensing", "automation.logic_control", "processing.dry_separation", "automation.machine_control"],
			"automation.advanced_routing": ["automation.basic_sensing", "automation.logic_control", "processing.dry_separation", "automation.machine_control", "automation.advanced_routing"],
		}
		var cumulative := {"glass": 0, "iron": 0, "gold": 0}
		for path_id: String in paths[research_id]:
			var path_cost: Dictionary = definitions[path_id].costs
			cumulative.glass += int(path_cost.glass)
			cumulative.iron += int(path_cost.iron)
			cumulative.gold += int(path_cost.gold)
		var estimate := maxf(float(cumulative.glass) / glass_rate, float(cumulative.iron) / iron_rate)
		if cumulative.gold > 0: estimate = maxf(estimate, float(cumulative.gold) / gold_rate)
		print("phase6_research id=%s cost_glass=%d cost_iron=%d cost_gold=%d cumulative_glass=%d cumulative_iron=%d cumulative_gold=%d estimated_seconds=%.2f" % [
			research_id, cost.glass, cost.iron, cost.gold, cumulative.glass, cumulative.iron, cumulative.gold, estimate
		])
	print("phase6_research_rates profile=3564 glass_per_s=%.2f iron_per_s=%.2f gold_per_s=%.3f source_seconds=%.3f" % [glass_rate, iron_rate, gold_rate, seconds])
	quit(0)
