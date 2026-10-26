extends "res://addons/gut/test.gd"

const CAMPAIGN_DATA = preload("res://src/custom/campaign/CampaignData.gd")
const CAMPAIGN_PROGRESS = preload("res://src/custom/campaign/CampaignProgress.gd")

const TEST_SAVE_PATH := "user://test_campaign_progress.json"

var campaign: Dictionary


func before_each() -> void:
	campaign = CAMPAIGN_DATA.load_campaign()
	_remove_test_save()


func after_each() -> void:
	_remove_test_save()


func _remove_test_save() -> void:
	var dir := Directory.new()
	if dir.file_exists(TEST_SAVE_PATH):
		dir.remove(TEST_SAVE_PATH)


func test_default_progress_unlocks_only_first_opponent():
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_eq(progress.get("completed"), [])
	assert_true(CAMPAIGN_PROGRESS.is_unlocked(campaign, progress, "king"))
	assert_false(CAMPAIGN_PROGRESS.is_unlocked(campaign, progress, "queen"))
	assert_false(CAMPAIGN_PROGRESS.is_unlocked(campaign, progress, "eram"))


func test_completing_opponent_unlocks_next():
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	progress = CAMPAIGN_PROGRESS.record_completion(campaign, progress, "king")
	assert_true(CAMPAIGN_PROGRESS.is_completed(progress, "king"))
	assert_true(CAMPAIGN_PROGRESS.is_unlocked(campaign, progress, "queen"))
	assert_false(CAMPAIGN_PROGRESS.is_unlocked(campaign, progress, "roaring_knight"))


func test_record_completion_does_not_duplicate():
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	progress = CAMPAIGN_PROGRESS.record_completion(campaign, progress, "king")
	progress = CAMPAIGN_PROGRESS.record_completion(campaign, progress, "king")
	assert_eq(progress.completed.size(), 1)


func test_save_and_load_round_trip():
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	progress = CAMPAIGN_PROGRESS.record_completion(campaign, progress, "king")
	progress = CAMPAIGN_PROGRESS.record_completion(campaign, progress, "queen")
	assert_eq(CAMPAIGN_PROGRESS.save_progress(progress, TEST_SAVE_PATH), OK)
	var reloaded = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_true(CAMPAIGN_PROGRESS.is_completed(reloaded, "king"))
	assert_true(CAMPAIGN_PROGRESS.is_completed(reloaded, "queen"))
	assert_eq(reloaded.get("last_opponent"), "queen")


func test_first_incomplete_id_tracks_progress():
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_eq(CAMPAIGN_PROGRESS.first_incomplete_id(campaign, progress), "king")
	progress = CAMPAIGN_PROGRESS.record_completion(campaign, progress, "king")
	assert_eq(CAMPAIGN_PROGRESS.first_incomplete_id(campaign, progress), "queen")


func test_corrupt_save_falls_back_to_default():
	var file := File.new()
	assert_eq(file.open(TEST_SAVE_PATH, File.WRITE), OK)
	file.store_string("this is not json")
	file.close()
	var progress = CAMPAIGN_PROGRESS.load_progress(TEST_SAVE_PATH)
	assert_eq(progress.get("completed"), [])
	assert_true(CAMPAIGN_PROGRESS.is_unlocked(campaign, progress, "king"))
