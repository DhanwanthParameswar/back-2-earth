extends RefCounted
## Prototype rules. Model output is a proposal; only this reducer grants progress.

var flags: Dictionary = {}
var route := ""
var carrying := ""
var version := 0
var journal: Array[String] = []

func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))

func objective() -> String:
	if has_flag("departed"): return "Back to Earth"
	if has_flag("clamps"): return "Everyone is ready. Board the shuttle."
	if powered(): return "Release the docking clamps in the shuttle bay."
	if not has_flag("locker_clear"): return "Work with Aaron to clear the jammed locker from the hallway."
	if not has_flag("assessed"): return "Inspect the launch terminal in the junction."
	if route == "engineering":
		if not has_flag("isolated"): return "Isolate the damaged engineering circuit."
		if not has_flag("fuse_taken"): return "Collect a replacement fuse from the storage room."
		if not has_flag("fuse_installed"): return "Install the replacement in the distribution cabinet."
		if not has_flag("fault_found"): return "Test the repaired supply at the distribution cabinet."
		if not has_flag("aux_off"): return "Disconnect the shorted auxiliary branch."
		return "Restart the distribution cabinet."
	if route == "battery":
		if not has_flag("battery_out"): return "Decide what to save, then disconnect the lab battery."
		if not has_flag("battery_loaded"): return "Ask Aaron to help load the battery onto the cart."
		if not has_flag("battery_taken"): return "Collect the loaded battery cart."
		return "Connect the battery at the shuttle bay's emergency socket."
	return "Choose a plan: repair Engineering or use the Laboratory battery."

func powered() -> bool:
	return has_flag("engineering_power") or has_flag("battery_connected")

func ending() -> String:
	if route == "engineering": return "A SHIP LEFT BEHIND. NOTHING ELSE."
	if has_flag("samples_saved"): return "THE IMPORTANT THINGS."
	return "EVERYONE IS HOME."

func apply(action: String) -> Dictionary:
	if has_flag("departed"): return _no("The crew is already on the way home.")
	var line := ""
	match action:
		"help_locker":
			if has_flag("locker_clear"): return _no("The doorway is already clear. I'll stay with you.")
			return _grant("locker_ready", "Aaron is holding the locker. Push it with E.")
		"push_locker":
			if not has_flag("locker_ready"): return _no("It catches at the top. Aaron could hold it while you push.")
			return _grant("locker_clear", "Together, you slide the locker clear. The junction is open.")
		"assess":
			if not has_flag("locker_clear"): return _no("Clear the jammed locker from the hallway first.")
			return _grant("assessed", "Shuttle intact. Clamps unpowered. Repair Engineering, or divert the lab battery; its samples will lose cooling.")
		"choose_engineering", "choose_battery":
			if not has_flag("assessed"): return _no("Check the junction launch terminal before choosing a plan.")
			var wanted := "engineering" if action == "choose_engineering" else "battery"
			if route == wanted: return _no("That's our current plan. " + objective())
			if powered() or has_flag("isolated") or has_flag("battery_out"):
				return _no("We've committed equipment to this route. " + objective())
			route = wanted
			line = "Engineering route agreed. Aaron will read diagnostics while you repair the supply." if wanted == "engineering" else "Battery route agreed. Cooling stays on until you explicitly disconnect it. Ask about saving the samples."
		"isolate":
			if route != "engineering": return _no("Agree on the Engineering repair at the junction terminal first.")
			return _grant("isolated", "Circuit isolated. The cabinet is safe to work on.")
		"take_fuse":
			if route != "engineering" or not has_flag("isolated"): return _no("Isolate the engineering circuit before taking a replacement.")
			if has_flag("fuse_taken"): return _no("You've already collected the replacement fuse.")
			carrying = "fuse"
			return _grant("fuse_taken", "Replacement fuse collected. Bring it to the distribution cabinet.")
		"cabinet":
			if not has_flag("isolated"): return _no("Live circuit. Use the isolation switch first.")
			if not has_flag("fuse_installed"):
				if carrying != "fuse": return _no("The fuse is burned out. There's a spare in the storage room.")
				carrying = ""
				return _grant("fuse_installed", "Replacement fitted. Test the supply at this cabinet.")
			if not has_flag("aux_off"): return _grant("fault_found", "Breaker tripped safely. The cabin-lighting branch is shorted. Disconnect AUX at the adjacent panel.")
			return _grant("engineering_power", "Shuttle bay power restored. The lab remains cold; cabin lighting has been sacrificed.")
		"aux":
			if not has_flag("fault_found"): return _no("Test the repaired cabinet first; we need to identify the fault.")
			return _grant("aux_off", "Damaged cabin-lighting branch isolated. Restart the cabinet.")
		"fetch_case":
			if not has_flag("assessed"): return _no("Check the shuttle's condition at the junction terminal first.")
			if has_flag("battery_out"): return _no("Cooling has already stopped; the samples are no longer viable.")
			return _grant("case_requested", "Dhan is fetching the insulated case from the shuttle. Meet him at the lab freezer.")
		"case_arrived": return _grant("case_arrived", "Dhan delivered the case beside the lab freezer. Pack the priority rack before disconnecting power.")
		"pack_samples":
			if has_flag("battery_out"): return _no("The samples were lost when cooling stopped. We can still get everyone home.")
			if not has_flag("case_arrived"): return _no("Ask Dhan to fetch the insulated sample case first.")
			return _grant("samples_saved", "Priority rack secured in the insulated case. The remaining samples must stay behind.")
		"disconnect_battery":
			if route != "battery": return _no("Agree on the battery route at the junction terminal first.")
			return _grant("battery_out", "Freezer shut down. Battery released. Aaron can help load it onto the cart.")
		"load_battery":
			if not has_flag("battery_out"): return _no("Disconnect the lab battery before we lift it.")
			return _grant("battery_loaded", "Together, you and Aaron load the heavy battery. Collect the cart with E.")
		"take_cart":
			if not has_flag("battery_loaded"): return _no("Too heavy for one person. Ask Aaron to help load the cart.")
			if has_flag("battery_taken"): return _no("The cart is already with you.")
			carrying = "battery cart"
			return _grant("battery_taken", "Cart collected. Bring it to the emergency socket in the shuttle bay.")
		"connect_battery":
			if powered(): return _no("The shuttle bay already has power.")
			if carrying != "battery cart": return _no("Bring the loaded lab battery cart to this socket.")
			carrying = ""
			return _grant("battery_connected", "Emergency supply connected. The docking controls are awake.")
		"release":
			if not powered(): return _no("Docking controls have no power. Restore Engineering or connect the lab battery.")
			return _grant("clamps", "Docking clamps released. Dhan and Aaron are boarding; join them at the shuttle.")
		"launch":
			if not has_flag("clamps"): return _no("Release the docking clamps before boarding.")
			return _grant("departed", "Three crew aboard. Destination: Earth.")
		_: return _no("That action isn't available. " + objective())
	version += 1
	journal.append(line)
	return {"ok": true, "line": line}

func _grant(key: String, line: String) -> Dictionary:
	if has_flag(key): return _no("Already done. " + objective())
	flags[key] = true
	version += 1
	journal.append(line)
	return {"ok": true, "line": line}

func _no(line: String) -> Dictionary:
	return {"ok": false, "line": line}
