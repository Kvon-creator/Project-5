extends CanvasLayer
## The heads-up display.
##
## OWNER: Daryl Watkins-Mattocks (proposed), by Nov 18.
## GDD architecture box: "HUD.gd / HUD.tscn / No mechanic state / Draws HP,
## meter, room, boost".
## Reads: GameManager, Player, GrazeMeter
##        ("Room number, HP and boost, meter fill").
##
## The GDD says this script holds NO mechanic state, and it does not. It only
## listens to signals and draws. That is why it is the one script in the
## project that is finished rather than stubbed - there is no mechanic in it
## to leave for anyone.
##
## Layout decision. The avoid list bans anything that hides bullets or the
## player hitbox, and this is a bullet hell, so the HUD stays pinned to the
## screen edges and the whole middle is left clear. Nothing here floats over
## the play area.

@onready var hp_bar: ProgressBar = $Root/TopLeft/HPBar
@onready var hp_label: Label = $Root/TopLeft/HPBar/HPLabel
@onready var meter_bar: ProgressBar = $Root/BottomCentre/MeterBar
@onready var meter_label: Label = $Root/BottomCentre/MeterBar/MeterLabel
@onready var shockwave_hint: Label = $Root/BottomCentre/ShockwaveHint
@onready var room_label: Label = $Root/TopRight/RoomLabel
@onready var boost_bar: ProgressBar = $Root/TopLeft/BoostBar
@onready var boost_label: Label = $Root/TopLeft/BoostBar/BoostLabel
@onready var end_screen: Control = $Root/EndScreen
@onready var end_title: Label = $Root/EndScreen/Panel/VBox/Title
@onready var end_subtitle: Label = $Root/EndScreen/Panel/VBox/Subtitle
@onready var end_button: Button = $Root/EndScreen/Panel/VBox/RestartButton

var _meter_full: bool = false
var _shockwave_pulse: Tween

## Added at runtime so HUD.tscn stays as generated: the wave counter under
## the room label, and the boss bar across the top.
var wave_label: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_label: Label
var _boss: Enemy

## Equipment (Items.gd - not in the GDD), also built at runtime: extra lives
## beside the HP bar, a row of what has been picked up under it, the two
## ability slots bottom-left with their keys and cooldowns, and a banner
## naming each pickup. All pinned to the edges, like the rest.
var lives_box: HBoxContainer
var lives_label: Label
var item_row: HBoxContainer
var ability_row: HBoxContainer
var _ability_slots: Dictionary = {}     # id -> {icon, shade, label}
var banner: VBoxContainer
var banner_title: Label
var banner_blurb: Label
var _banner_tween: Tween


func _ready() -> void:
	end_screen.visible = false
	boost_bar.visible = false
	shockwave_hint.visible = false
	end_button.pressed.connect(_on_restart_pressed)
	_build_extras()
	_connect_sources.call_deferred()


## Wire up to whatever is in the scene. Deferred so every node is ready first,
## and defensive so the HUD still loads if a mechanic script is mid-rewrite.
func _connect_sources() -> void:
	var gm := GameManager.instance
	if gm:
		gm.room_changed.connect(set_room)
		set_room(gm.room_index)
		if is_instance_valid(gm.room):
			gm.room.wave_started.connect(set_wave)
			gm.room.room_started.connect(func(_i: int) -> void: set_wave(-1, 0))
			gm.room.boss_spawned.connect(show_boss)

		if is_instance_valid(gm.player):
			gm.player.hp_changed.connect(set_hp)
			set_hp(gm.player.hp, gm.player.MAX_HP)

			var meter := gm.player.get_node_or_null("GrazeMeter")
			if meter:
				meter.meter_changed.connect(set_meter)
				meter.meter_full.connect(_on_meter_full)
				meter.meter_no_longer_full.connect(_on_meter_not_full)
				set_meter(meter.meter, meter.METER_MAX)

			var loadout: Loadout = gm.player.loadout
			if loadout:
				loadout.item_added.connect(_on_item_added)
				loadout.lives_changed.connect(set_lives)
				loadout.cooldown_changed.connect(_on_cooldown)
				set_lives(loadout.extra_lives)
			var dodge: Dodge = gm.player.dodge
			if dodge:
				_add_ability_slot("dodge")
				dodge.cooldown_changed.connect(
						func(r: float, t: float) -> void: _on_cooldown("dodge", r, t))

	CombatRewards.boost_started.connect(_on_boost_started)
	CombatRewards.boost_ended.connect(_on_boost_ended)
	CombatRewards.boost_time_changed.connect(_on_boost_time)


# --------------------------------------------------------------------------
# Draw
# --------------------------------------------------------------------------

func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	# Tweened rather than snapped, so a 10-damage hit is something the player
	# SEES land. At 10 hits from full, each one is a tenth of the bar.
	var tween := create_tween()
	tween.tween_property(hp_bar, "value", float(hp), 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hp_label.text = "%d / %d" % [hp, max_hp]

	# The bar shifts toward Blood Rust as HP drops, so low health is readable
	# in peripheral vision while the player's eyes are on the bullets.
	var frac := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var fill := _bar_fill(hp_bar)
	if fill:
		fill.bg_color = Palette.BLOOD_RUST.lerp(Palette.EMBER,
				clampf(frac, 0.0, 1.0))


func set_meter(value: int, max_value: int) -> void:
	meter_bar.max_value = max_value
	var tween := create_tween()
	tween.tween_property(meter_bar, "value", float(value), 0.12)
	meter_label.text = "GRAZE  %d / %d" % [value, max_value]


func _build_extras() -> void:
	wave_label = Label.new()
	wave_label.name = "WaveLabel"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.add_theme_color_override("font_color", Palette.PARCHMENT)
	wave_label.add_theme_font_size_override("font_size", 14)
	room_label.get_parent().add_child(wave_label)

	boss_box = VBoxContainer.new()
	boss_box.name = "BossBox"
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -220
	boss_box.offset_right = 220
	boss_box.offset_top = 14
	boss_box.visible = false
	boss_label = Label.new()
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_color_override("font_color", Palette.PARCHMENT)
	boss_label.add_theme_font_size_override("font_size", 15)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(440, 14)
	boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.BLOOD_RUST
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.05, 0.1, 0.85)
	boss_bar.add_theme_stylebox_override("fill", fill)
	boss_bar.add_theme_stylebox_override("background", bg)
	boss_box.add_child(boss_label)
	boss_box.add_child(boss_bar)
	$Root.add_child(boss_box)
	_build_equipment()


func _build_equipment() -> void:
	# Extra lives: the Phoenix Seal medallion and a count, beside the HP bar.
	lives_box = HBoxContainer.new()
	lives_box.name = "Lives"
	lives_box.position = Vector2(330, 17)
	lives_box.add_theme_constant_override("separation", 2)
	lives_box.visible = false
	var seal := TextureRect.new()
	seal.texture = Items.hud_icon("phoenix_seal")
	seal.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	seal.custom_minimum_size = Vector2(32, 32)
	seal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lives_box.add_child(seal)
	lives_label = _small_label(16, Palette.EMBER.lerp(Palette.PARCHMENT, 0.4))
	lives_box.add_child(lives_label)
	$Root.add_child(lives_box)

	# What has been picked up, a row of small medallions under the bars.
	item_row = HBoxContainer.new()
	item_row.name = "ItemRow"
	item_row.add_theme_constant_override("separation", 3)
	$Root/TopLeft.add_child(item_row)

	# Ability slots, bottom-left: medallion, key, cooldown shade.
	ability_row = HBoxContainer.new()
	ability_row.name = "Abilities"
	ability_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ability_row.offset_left = 24
	ability_row.offset_top = -78
	ability_row.add_theme_constant_override("separation", 10)
	$Root.add_child(ability_row)

	# The pickup banner, high and centred, clear of the play area's middle.
	banner = VBoxContainer.new()
	banner.name = "ItemBanner"
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -260
	banner.offset_right = 260
	banner.offset_top = 64
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_title = _small_label(22, Palette.PARCHMENT)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_blurb = _small_label(14, Palette.PARCHMENT)
	banner_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_title)
	banner.add_child(banner_blurb)
	$Root.add_child(banner)


func _small_label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", Palette.INK)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", size)
	return l


func set_lives(lives: int) -> void:
	lives_box.visible = lives > 0
	lives_label.text = "x%d" % lives


func _on_item_added(id: String) -> void:
	_show_banner(id)
	match Items.kind(id):
		Items.Kind.CONSUMABLE, Items.Kind.LIFE:
			return   # shown by the HP bar and the lives count
		Items.Kind.ABILITY:
			if id == "blot_bomb":
				_add_ability_slot(id)
				return
	var icon := TextureRect.new()
	icon.texture = Items.hud_icon(id)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = "%s - %s" % [Items.display_name(id), Items.info(id).get("blurb", "")]
	item_row.add_child(icon)


func _add_ability_slot(id: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var icon := TextureRect.new()
	# The dodge wears the Shadow Step medallion: that item is its upgrade.
	icon.texture = Items.icon("shadow_step" if id == "dodge" else id)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var key := _small_label(12, Palette.PARCHMENT)
	key.text = "SPACE" if id == "dodge" else "E"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key)
	ability_row.add_child(box)
	_ability_slots[id] = {"icon": icon, "key": key}


func _on_cooldown(id: String, remaining: float, _total: float) -> void:
	var slot: Dictionary = _ability_slots.get(id, {})
	if slot.is_empty():
		return
	var ready := remaining <= 0.0
	(slot["icon"] as TextureRect).modulate = Color.WHITE if ready else Color(0.45, 0.42, 0.48, 1.0)
	var key := "SPACE" if id == "dodge" else "E"
	(slot["key"] as Label).text = key if ready else "%.1f" % remaining


func _show_banner(id: String) -> void:
	banner_title.text = Items.display_name(id).to_upper()
	banner_title.add_theme_color_override("font_color",
			Items.kind_colour(id).lerp(Palette.PARCHMENT, 0.35))
	banner_blurb.text = str(Items.info(id).get("blurb", ""))
	if _banner_tween:
		_banner_tween.kill()
	banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(2.2)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.5)


func set_wave(index: int, count: int) -> void:
	wave_label.text = "" if index < 0 else "WAVE  %d / %d" % [index + 1, count]


func show_boss(boss: Enemy) -> void:
	_boss = boss
	boss_box.visible = true
	boss_bar.max_value = boss.max_hp
	boss_bar.value = boss.hp
	_set_boss_label(1)
	boss.hp_changed.connect(func(hp: int, _max: int) -> void:
		create_tween().tween_property(boss_bar, "value", float(hp), 0.15))
	boss.died.connect(func(_e: Enemy) -> void: boss_box.visible = false)
	if boss.has_signal("phase_changed"):
		boss.phase_changed.connect(_set_boss_label)


func _set_boss_label(phase: int) -> void:
	const NUMERALS := ["I", "II", "III"]
	boss_label.text = "THE INK SCRIBE   -   PHASE %s" % NUMERALS[clampi(phase - 1, 0, 2)]


func set_room(index: int) -> void:
	# GDD: rooms 1-6 combat, 7 elite, 8 boss.
	var suffix := ""
	if index == 7:
		suffix = "  ELITE"
	elif index == 8:
		suffix = "  BOSS"
	room_label.text = "ROOM  %d / 8%s" % [index, suffix]


func _on_meter_full() -> void:
	if _meter_full:
		return
	_meter_full = true
	shockwave_hint.visible = true
	shockwave_hint.modulate.a = 1.0
	# A slow pulse on the hint, not the bar. Pulsing the bar would drag the
	# eye to the bottom of the screen at the exact moment the player most
	# needs to be watching bullets.
	if _shockwave_pulse and _shockwave_pulse.is_valid():
		_shockwave_pulse.kill()
	_shockwave_pulse = create_tween().set_loops()
	_shockwave_pulse.tween_property(shockwave_hint, "modulate:a", 0.45, 0.5)
	_shockwave_pulse.tween_property(shockwave_hint, "modulate:a", 1.0, 0.5)


func _on_meter_not_full() -> void:
	_meter_full = false
	if _shockwave_pulse and _shockwave_pulse.is_valid():
		_shockwave_pulse.kill()
	_shockwave_pulse = null
	shockwave_hint.modulate.a = 1.0
	shockwave_hint.visible = false


func _on_boost_started(_duration: float) -> void:
	boost_bar.visible = true


func _on_boost_ended() -> void:
	boost_bar.visible = false


func _on_boost_time(remaining: float, duration: float) -> void:
	boost_bar.max_value = duration
	boost_bar.value = remaining
	boost_label.text = "+20%%  %.1fs" % remaining


# --------------------------------------------------------------------------
# End screen
# --------------------------------------------------------------------------

func show_end_screen(won: bool) -> void:
	end_screen.visible = true
	end_screen.modulate.a = 0.0
	if won:
		end_title.text = "RUN COMPLETE"
		end_title.add_theme_color_override("font_color", Palette.GRAZE_GOLD)
		end_subtitle.text = "You beat the boss in room 8."
	else:
		end_title.text = "RUN OVER"
		end_title.add_theme_color_override("font_color", Palette.BLOOD_RUST)
		# GDD: "nothing carries over between runs."
		end_subtitle.text = "Restarting at room 1 with new layouts."
	create_tween().tween_property(end_screen, "modulate:a", 1.0, 0.35)


func _on_restart_pressed() -> void:
	if GameManager.instance:
		GameManager.instance.restart()


## Reach into a ProgressBar's fill StyleBox so the colour can be animated.
## Returns null if the theme has not been overridden, which keeps this safe
## if someone restyles the bars later.
func _bar_fill(bar: ProgressBar) -> StyleBoxFlat:
	var sb := bar.get_theme_stylebox("fill")
	return sb as StyleBoxFlat
