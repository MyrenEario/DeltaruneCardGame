extends "res://addons/gut/test.gd"

const RECOMMENDER = preload("res://src/custom/campaign/CardRecommender.gd")
const CARD_SET_PATH := "res://src/custom/cards/sets/PlueyPokerGen3.json"

var definitions := {}


func before_each() -> void:
	definitions = _load(CARD_SET_PATH)
	assert_false(definitions.empty(), "Card definitions should load")


func _load(path: String) -> Dictionary:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var parsed := JSON.parse(file.get_as_text())
	file.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	return parsed.result


func test_recommendations_are_cheaper_than_heroes_and_share_tags():
	var seed_names := ["Ribcage Roaring Knight", "Dess", "Mantle Boss ERAM"]
	var ceiling := RECOMMENDER.seed_cost_ceiling(seed_names, definitions)
	var recommendations := RECOMMENDER.recommend(seed_names, definitions, 20)
	gut.p("Recommendations for %s: %s" % [str(seed_names), str(recommendations)])
	assert_gt(recommendations.size(), 0, "Some cards are recommended")
	var seed_tags := RECOMMENDER.expanded_seed_tags(seed_names, definitions)
	for name in recommendations:
		var card = definitions[name]
		assert_true(RECOMMENDER.cost_of(card) < ceiling,
				"%s must be cheaper than the heroes" % name)
		assert_gt(RECOMMENDER.relevance(card, seed_tags), 0,
				"%s must share tag material" % name)


func test_recommended_cards_are_ranked_by_relevance():
	var seed_names := ["Ribcage Roaring Knight", "Dess", "Mantle Boss ERAM"]
	var recommendations := RECOMMENDER.recommend(seed_names, definitions, 8)
	var seed_tags := RECOMMENDER.expanded_seed_tags(seed_names, definitions)
	var previous := 1000000
	for name in recommendations:
		var score := RECOMMENDER.relevance(definitions[name], seed_tags)
		assert_true(score <= previous, "Scores are non-increasing")
		previous = score


func test_recommendations_exclude_seed_and_hero_objectives():
	var seed_names := ["Ribcage Roaring Knight", "Dess", "Mantle Boss ERAM"]
	var recommendations := RECOMMENDER.recommend(seed_names, definitions, 200)
	for name in seed_names:
		assert_false(name in recommendations, "%s (seed) is excluded" % name)
	assert_false("First Hero" in recommendations)
	assert_false("Second Hero" in recommendations)
	assert_false("Third Hero" in recommendations)


func test_empty_seed_recommends_nothing():
	assert_eq(RECOMMENDER.recommend([], definitions).size(), 0)


func test_cost_parsing_handles_blank_and_string_values():
	assert_eq(RECOMMENDER.cost_of({"Cost": 7}), 7)
	assert_eq(RECOMMENDER.cost_of({"Cost": "8"}), 8)
	assert_eq(RECOMMENDER.cost_of({"Cost": ""}), 0)
	assert_eq(RECOMMENDER.cost_of({"Cost": "U"}), 0)


func test_seed_equalities_expand_the_tag_set():
	var defs := {
		"Seed": {"Tags": ["Hell"], "TagEqualities": ["Depths = Hell"]},
		"Other": {"Tags": ["Depths"], "Cost": 1},
	}
	var tags := RECOMMENDER.expanded_seed_tags(["Seed"], defs)
	assert_true(tags.has("Hell"), "Seed tag present")
	assert_true(tags.has("Depths"), "Equality pulls in the other side")
	assert_gt(RECOMMENDER.relevance(defs["Other"], tags), 0,
			"A card using the equal tag is relevant")
