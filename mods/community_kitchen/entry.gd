extends RefCounted

func register(catalog: CBCatalog) -> void:
	catalog.register_system("community_kitchen:shared_supper", shared_supper, 60)
	catalog.register_panel("community_kitchen:panel", panel)

func shared_supper(snapshot: Dictionary) -> Array:
	if int(snapshot.minute) % 1440 != 19 * 60 or not snapshot.policies.get("shared_meals", false):
		return []
	var effects: Array = []
	var present: Array = snapshot.residents.filter(func(person: Dictionary) -> bool: return person.activity == "social" and person.get("travel_remaining", 0) == 0)
	if present.is_empty():
		return []
	var cost := present.size() * 175
	if not snapshot.policies.unlimited_funds and snapshot.funds < cost:
		return [{"type": "notice", "text": "Shared supper needs more funds."}]
	effects.append({"type": "spend", "amount": cost, "reason": "Community supper"})
	for person in present:
		effects.append({"type": "need", "resident": person.id, "need": "food", "amount": 20.0})
		effects.append({"type": "need", "resident": person.id, "need": "social", "amount": 12.0})
	effects.append({"type": "mod_state", "id": "community_kitchen:meals", "value": int(snapshot.mod_state.get("community_kitchen:meals", 0)) + present.size()})
	return effects

func panel(snapshot: Dictionary) -> Dictionary:
	return {"title": "Community kitchen", "text": "%s shared meals served. Enable shared suppers in the co-op panel." % snapshot.mod_state.get("community_kitchen:meals", 0)}
