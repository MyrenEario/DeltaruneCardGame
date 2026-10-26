class_name CampaignProgress
extends Reference

const CampaignDataScript = preload("res://src/custom/campaign/CampaignData.gd")
const SAVE_PATH := "user://campaign_progress.json"
const SCHEMA_VERSION := 1

var completed := []
var last_opponent := ""


static func load_progress(path := SAVE_PATH) -> Dictionary:
	var data := {
		"schema_version": SCHEMA_VERSION,
		"completed": [],
		"last_opponent": "",
	}
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return data
	var text := file.get_as_text()
	file.close()
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return data
	var result: Dictionary = parsed.result
	data["schema_version"] = int(result.get(
			"schema_version", SCHEMA_VERSION))
	data["last_opponent"] = str(result.get("last_opponent", ""))
	var completed_value = result.get("completed", [])
	if typeof(completed_value) == TYPE_ARRAY:
		for opponent_id in completed_value:
			var value := str(opponent_id)
			if not value.empty() and not value in data.completed:
				data.completed.append(value)
	return data


static func save_progress(data: Dictionary, path := SAVE_PATH) -> int:
	var file := File.new()
	if file.open(path, File.WRITE) != OK:
		return ERR_CANT_CREATE
	file.store_string(JSON.print(data, "\t"))
	file.close()
	return OK


static func is_completed(data: Dictionary, opponent_id: String) -> bool:
	return opponent_id in data.get("completed", [])


static func is_unlocked(campaign: Dictionary, data: Dictionary,
		opponent_id: String) -> bool:
	var opponent := CampaignDataScript.find_opponent(campaign, opponent_id)
	if opponent.empty():
		return false
	var unlock_after = opponent.get("unlock_after", null)
	if unlock_after == null or str(unlock_after).empty():
		return true
	return is_completed(data, str(unlock_after))


static func first_incomplete_id(campaign: Dictionary, data: Dictionary) -> String:
	for opponent in CampaignDataScript.get_opponents(campaign):
		if typeof(opponent) != TYPE_DICTIONARY:
			continue
		var opponent_id := str(opponent.get("id", ""))
		if opponent_id.empty():
			continue
		if not is_completed(data, opponent_id):
			return opponent_id
	return ""


static func record_completion(campaign: Dictionary, data: Dictionary,
		opponent_id: String) -> Dictionary:
	var updated: Dictionary = data.duplicate(true)
	if not "completed" in updated:
		updated["completed"] = []
	if not is_completed(updated, opponent_id):
		updated.completed.append(opponent_id)
	updated["last_opponent"] = opponent_id
	return updated
