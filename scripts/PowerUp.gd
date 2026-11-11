class_name PowerUp
extends Area2D
## The Luminous Pigment Shell - the damage power-up.
##
## OWNER: Jarman (Combat Rewards). Due Nov 18.
## GDD, section 6: "Damage power-up drop - Every 5th enemy defeated",
## "+20% weapon damage for 10 s", "Does not stack; a new pickup resets the
## timer to 10 s".
##
## Teal, per the palette: Spirit Teal is "Player shots, damage power-up", so
## a pickup can never be mistaken for a threat. Hostile Magenta is the only
## colour that means danger.
##
## WHAT IS BUILT: the bob and pulse, the pickup flash, the handoff to
## CombatRewards. There is no TODO here - the stacking rule already lives in
## CombatRewards.start_boost(), so this script only has to call it.

signal collected

## How far the shell drifts up and down, in pixels, and how long one cycle
## takes. Motion is what makes a pickup findable on a busy floor.
const BOB_PIXELS: float = 4.0
const BOB_SECONDS: float = 1.6

@onready var sprite: Sprite2D = $Sprite

var _taken: bool = false


func _ready() -> void:
	add_to_group("powerup")
	_start_bob()


func _start_bob() -> void:
	var base := position.y
	var tween := create_tween().set_loops()
	tween.tween_property(self, "position:y", base - BOB_PIXELS,
			BOB_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", base,
			BOB_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)


func _on_body_entered(body: Node2D) -> void:
	if _taken or not (body is Player):
		return
	_taken = true
	collected.emit()
	# The stacking rule lives in CombatRewards, so this just asks for a boost
	# and lets that script decide whether it is a fresh one or a reset.
	CombatRewards.start_boost()
	_play_collect()


func _play_collect() -> void:
	# A short teal pop. Deliberately brief: the avoid list bans effects that
	# hide bullets, and a pickup goes off in the middle of a fight.
	set_deferred("monitoring", false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(1.6, 1.6), 0.18)
	tween.tween_property(sprite, "modulate", Palette.NIB_TEAL, 0.09)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.chain().tween_callback(queue_free)
