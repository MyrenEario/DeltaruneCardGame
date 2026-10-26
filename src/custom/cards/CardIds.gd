# Stable, hidden identity for cards.
#
# Every card carries a permanent "id" that never changes (even when the card is
# renamed). Decks, formats and the campaign reference cards by this id, so a
# rename can never break them. Nothing user-facing should ever show an id.
class_name CardIds
extends Reference


# Returns a fresh 128-bit id as 32 lowercase hex characters.
static func new_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d-%d-%d" % [
		OS.get_ticks_usec(), OS.get_unix_time(), randi()])
	var parts := []
	for _index in range(4):
		parts.append("%08x" % (rng.randi() & 0xFFFFFFFF))
	return PoolStringArray(parts).join("")
