extends CanvasLayer













signal battle_finished(result: String, enemy_id: String)

const FONT_SIZE: = 16
const TYPE_SPEED: = 46.0

const COLOR_TEXT: = Color(0.93, 0.88, 0.75, 1.0)
const COLOR_TEXT_DIM: = Color(0.93, 0.88, 0.75, 0.4)
const COLOR_ACCENT: = Color(1.0, 0.85, 0.45, 1.0)
const COLOR_PANEL_BG: = Color(0.05, 0.04, 0.13, 0.92)
const COLOR_PANEL_BORDER: = Color(0.78, 0.6, 0.26, 0.65)
const COLOR_HP: = Color(0.82, 0.25, 0.28, 1.0)
const COLOR_HP_GHOST: = Color(0.95, 0.82, 0.55, 0.9)
const COLOR_HP_BG: = Color(0.16, 0.06, 0.09, 0.95)
const COLOR_PLAYER_HP: = Color(0.32, 0.7, 0.38, 1.0)
const COLOR_XP: = Color(0.45, 0.55, 0.9, 1.0)
const COLOR_EXPOSED: = Color(0.95, 0.45, 0.95, 1.0)
const COLOR_CRIT: = Color(1.0, 0.78, 0.25, 1.0)
const COLOR_PLAYER_DMG: = Color(1.0, 0.42, 0.38, 1.0)
const COLOR_HEAL: = Color(0.55, 0.95, 0.6, 1.0)

const TEX_PANEL: = "res://assets/ui/battle/panel.png"
const TEX_CURSOR: = "res://assets/ui/battle/cursor.png"
const TEX_SLASH: = "res://assets/ui/battle/slash_sheet.png"
const TEX_BACKDROP: = "res://assets/ui/battle/backdrop.png"
const TEX_BANNER: = "res://assets/ui/battle/banner.png"
const TEX_B2_COMMAND: = "res://assets/ui/battle_v2/command_card.png"
const TEX_B2_COMMAND_SELECTED: = "res://assets/ui/battle_v2/command_card_selected.png"
const TEX_B2_ENEMY: = "res://assets/ui/battle_v2/panel_enemy.png"
const TEX_B2_INTENT: = "res://assets/ui/battle_v2/panel_intent.png"
const TEX_B2_LOG: = "res://assets/ui/battle_v2/panel_log.png"
const TEX_B2_PLAYER: = "res://assets/ui/battle_v2/panel_player.png"
const TEX_B2_ORNAMENT: = "res://assets/ui/battle_v2/ornament_gem.png"
const TEX_B2_TURN_ORDER_ENEMY: = "res://assets/ui/battle_v2/turn_order_card_enemy.png"
const TEX_B2_TURN_ORDER_ALLY: = "res://assets/ui/battle_v2/turn_order_card_ally.png"
const TEX_B2_ICON_ATTACK: = "res://assets/ui/battle_v2/icons/icon_attack.png"
const TEX_B2_ICON_SKILL: = "res://assets/ui/battle_v2/icons/icon_skill.png"
const TEX_B2_ICON_PROBE: = "res://assets/ui/battle_v2/icons/icon_probe.png"
const TEX_B2_ICON_ITEM: = "res://assets/ui/battle_v2/icons/icon_item.png"
const TEX_B2_ICON_GUARD: = "res://assets/ui/battle_v2/icons/icon_guard.png"
const TEX_B2_ICON_FLEE: = "res://assets/ui/battle_v2/icons/icon_flee.png"
const TEX_B2_ICON_FINISHER: = "res://assets/ui/battle_v2/icons/icon_finisher.png"
const TEX_B2_ICON_SPARE: = "res://assets/ui/battle_v2/icons/icon_spare.png"

enum UiMode{NONE, TYPING, CONFIRM, MENU}

signal _confirmed
signal _menu_picked(id: String)


var enemy: Dictionary = {}
var enemy_id: String = ""
var enemy_hp: int = 1
var enemy_max_hp: int = 1
var enemy_attack: int = 1
var enemy_defense: int = 0
var enemy_speed: int = 1

var player_stats: Dictionary = {}
var player_sp: int = 0
var focus_active: bool = false
var hexed: bool = false
var guarding: bool = false
var _companion_levelups: Array = []

var exposed_turns: int = 0
var finisher_used: bool = false
var weakness_found: bool = false
var probe_options: Array = []
var triggered_phases: Dictionary = {}
var phase_damage_bonus: float = 1.0
var phase_defense_factor: float = 1.0
var intent: Dictionary = {}
var turns_since_heavy: int = 99
var flee_failed_count: int = 0

var _ui_mode: UiMode = UiMode.NONE
var _type_target: String = ""
var _type_progress: float = 0.0
var _menu_ids: Array[String] = []
var _menu_items: Array[Control] = []
var _menu_index: int = 0
var _battle_over: bool = false


var _panel_style: StyleBox = null
var _cursor_texture: Texture2D = null
var _slash_frames: SpriteFrames = null
var _banner_texture: Texture2D = null
var _texture_cache: Dictionary = {}

var _shake_time: float = 0.0
var _shake_strength: float = 0.0

var _root: Control


var _design: Control
var _fx_layer: Control
var _enemy_panel: Panel
var _enemy_name_label: Label
var _enemy_rank_label: Label
var _enemy_hp_bar: Control
var _enemy_hp_ghost: Control
var _enemy_status_label: Label
var _intent_label: Label
var _intent_icon: TextureRect
var _turn_stack: Control
var _turn_cards: Array[Control] = []
var _turn_active_actor: = "player"
var _portrait_holder: Control
var _portrait: TextureRect
var _portrait_flash: TextureRect
var _portrait_glow: TextureRect
var _log_panel: Panel
var _log_label: RichTextLabel
var _continue_marker: Label
var _menu_panel: Panel
var _menu_row: HBoxContainer
var _menu_cursor: Control
var _menu_descs: Array[String] = []
var _menu_info_icon: TextureRect
var _menu_info_name: Label
var _menu_info_desc: Label
var _hint_label: Label
var _player_panel: Panel
var _player_panel_label: Label
var _enemy_lv_label: Label
var _enemy_hp_text: Label
var _player_lv_label: Label
var _player_hp_text: Label
var _player_xp_text: Label
var _player_status_label: Label
var _player_hp_bar: Control
var _player_hp_ghost: Control
var _xp_bar: Control
var _sp_pips: Array[CanvasItem] = []
var _sp_pip_row: Control

const ENEMY_HP_BAR_W: = 170.0
const PLAYER_HP_BAR_W: = 130.0
const DESIGN_SIZE: = Vector2(960, 540)
const ENEMY_PANEL_POS: = Vector2(2, 2)
const ENEMY_PANEL_SIZE: = Vector2(312, 96)
const LOG_PANEL_POS: = Vector2(2, 106)
const LOG_PANEL_SIZE: = Vector2(330, 152)
const PLAYER_PANEL_POS: = Vector2(2, 380)
const PLAYER_PANEL_SIZE: = Vector2(312, 158)
const MENU_PANEL_POS: = Vector2(404, 422)
const MENU_PANEL_SIZE: = Vector2(470, 172)
const TURN_ORDER_TITLE_POS: = Vector2(778, 2)
const TURN_ORDER_TITLE_SIZE: = Vector2(176, 18)
const TURN_ORDER_STACK_POS: = Vector2(0, 28)
const TURN_ORDER_STACK_SIZE: = Vector2(960, 230)
const PORTRAIT_HOME: = Vector2(350, 48)
const PORTRAIT_SIZE: = Vector2(280, 290)
const PLAYER_FX_CENTER: = Vector2(124, 454)
const SCREEN_CENTER: = Vector2(480, 270)


func open(enemy_data: Dictionary) -> void :
    enemy = enemy_data
    enemy_id = str(enemy.get("id", ""))
    var stats: Dictionary = enemy.get("stats", {}) as Dictionary
    enemy_max_hp = max(int(stats.get("max_hp", 40)), 1)
    enemy_hp = enemy_max_hp
    enemy_attack = max(int(stats.get("attack", 8)), 1)
    enemy_defense = max(int(stats.get("defense", 2)), 0)
    enemy_speed = max(int(stats.get("speed", 6)), 1)

    player_stats = GameManager.player_battle_stats()
    player_sp = int(player_stats.get("sp_max", 3))
    probe_options = ((enemy.get("weakness", {}) as Dictionary).get("probe_options", []) as Array).duplicate(true)

    GameManager.ui_blocking_input = true
    layer = 80
    transform = Transform2D.IDENTITY

    if not GameManager.companion_leveled.is_connected(_on_companion_leveled):
        GameManager.companion_leveled.connect(_on_companion_leveled)
    _load_ui_kit()
    _build_ui()
    _run_battle()





func _load_ui_kit() -> void :
    if ResourceLoader.exists(TEX_PANEL):
        var panel_texture: Texture2D = load(TEX_PANEL)
        var style: = StyleBoxTexture.new()
        style.texture = panel_texture
        style.set_texture_margin_all(11.0)
        style.set_content_margin_all(4.0)
        _panel_style = style
    if ResourceLoader.exists(TEX_CURSOR):
        _cursor_texture = load(TEX_CURSOR)
    if ResourceLoader.exists(TEX_BANNER):
        _banner_texture = load(TEX_BANNER)
    if ResourceLoader.exists(TEX_SLASH):
        var sheet: Texture2D = load(TEX_SLASH)
        _slash_frames = SpriteFrames.new()
        _slash_frames.remove_animation("default")
        _slash_frames.add_animation("slash")
        _slash_frames.set_animation_speed("slash", 16.0)
        _slash_frames.set_animation_loop("slash", false)
        for index in range(4):
            var atlas: = AtlasTexture.new()
            atlas.atlas = sheet
            atlas.region = Rect2(index * 96, 0, 96, 96)
            _slash_frames.add_frame("slash", atlas)


func _load_png_texture(path: String) -> Texture2D:
    if _texture_cache.has(path):
        return _texture_cache[path]
    var texture: Texture2D = null
    if ResourceLoader.exists(path):
        texture = load(path)
    else:
        var image: = Image.new()
        if image.load(ProjectSettings.globalize_path(path)) == OK:
            texture = ImageTexture.create_from_image(image)
    _texture_cache[path] = texture
    return texture




const BATTLE_V3_DIR: = "res://assets/ui/battle_v3/"


func _v3(file_name: String) -> Texture2D:
    var path: = BATTLE_V3_DIR + file_name
    return load(path) if ResourceLoader.exists(path) else null




func _cropped_portrait(texture: Texture2D, out_size: int, circle: bool) -> Texture2D:
    if texture == null:
        return null
    var image: = texture.get_image()
    if image == null:
        return texture
    image = image.duplicate()
    if image.is_compressed():
        image.decompress()
    image.convert(Image.FORMAT_RGBA8)
    var side: int = mini(image.get_width(), image.get_height())
    var square: = image.get_region(Rect2i(
        int((image.get_width() - side) / 2.0), int((image.get_height() - side) / 2.0), side, side))
    var interp: = Image.INTERPOLATE_NEAREST if side <= 96 else Image.INTERPOLATE_LANCZOS
    square.resize(out_size, out_size, interp)
    if circle:
        var radius: = out_size * 0.5
        for y in range(out_size):
            for x in range(out_size):
                var dist: = Vector2(x - radius + 0.5, y - radius + 0.5).length()
                if dist > radius - 1.5:
                    var color: = square.get_pixel(x, y)
                    color.a *= clampf(radius - dist, 0.0, 1.0)
                    square.set_pixel(x, y, color)
    return ImageTexture.create_from_image(square)



func _make_chip(rect: Rect2) -> Dictionary:
    var root: = Control.new()
    root.position = rect.position
    root.size = rect.size
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var chip_texture: = _v3("lv_chip.png")
    if chip_texture != null:
        var art: = TextureRect.new()
        art.texture = chip_texture
        art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        art.stretch_mode = TextureRect.STRETCH_SCALE
        art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        art.size = rect.size
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(art)
    else:
        var panel: = Panel.new()
        panel.size = rect.size
        var style: = StyleBoxFlat.new()
        style.bg_color = Color(0.03, 0.045, 0.09, 0.92)
        style.border_color = Color(0.76, 0.58, 0.27, 0.85)
        style.set_border_width_all(1)
        style.set_corner_radius_all(5)
        panel.add_theme_stylebox_override("panel", style)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(panel)
    var label: = UiKit.make_label_strong("", 12, UiKit.COLOR_TEXT)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.position = Vector2.ZERO
    label.size = rect.size
    label.clip_text = true
    root.add_child(label)
    return {"root": root, "label": label}



func _make_portrait_token(rect: Rect2, portrait: Texture2D) -> Control:
    var root: = Control.new()
    root.position = rect.position
    root.size = rect.size
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var inset: = rect.size * 0.11
    var picture: = TextureRect.new()
    picture.texture = _cropped_portrait(portrait, int(rect.size.x - inset.x * 2.0), false)
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_SCALE
    picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    picture.position = inset
    picture.size = rect.size - inset * 2.0
    picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(picture)
    var frame_texture: = _v3("token_frame.png")
    if frame_texture != null:
        var frame: = TextureRect.new()
        frame.texture = frame_texture
        frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        frame.stretch_mode = TextureRect.STRETCH_SCALE
        frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        frame.size = rect.size
        frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
        root.add_child(frame)
    else:
        root.add_child(UiKit.make_ornate_frame(rect.size, "slot.png", 0.22, 12.0))
    return root



func _fit_label_font(label: Label, start_size: int, min_size: int) -> void :
    var font: = label.get_theme_font("font")
    if font == null:
        font = ThemeDB.fallback_font
    var size: = start_size
    while size > min_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x > label.size.x:
        size -= 1
    label.add_theme_font_size_override("font_size", size)





func _make_ornate_bar(rect: Rect2, kind: String, ghost_tint: Color) -> Dictionary:
    var bar: = UiKit.make_bar(rect, kind)
    var root: Control = bar["root"]
    var ghost: Control
    var gold_texture: = UiKit.kit_texture("bar_fill_gold.png")
    if gold_texture != null:
        ghost = Control.new()
        ghost.size = rect.size
        ghost.clip_contents = true
        ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var ghost_fill: = TextureRect.new()
        ghost_fill.texture = gold_texture
        ghost_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ghost_fill.stretch_mode = TextureRect.STRETCH_SCALE
        ghost_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        ghost_fill.size = rect.size
        ghost_fill.modulate = ghost_tint
        ghost_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
        ghost.add_child(ghost_fill)
    else:
        var ghost_flat: = ColorRect.new()
        ghost_flat.color = ghost_tint
        ghost_flat.size = rect.size
        ghost = ghost_flat

    root.add_child(ghost)
    root.move_child(ghost, 1)
    return {"root": root, "fill": bar["fill"], "ghost": ghost}


func _make_panel_style(bg: Color = COLOR_PANEL_BG, border: Color = COLOR_PANEL_BORDER, radius: int = 5) -> StyleBox:
    var flat: = StyleBoxFlat.new()
    flat.bg_color = bg
    flat.border_color = border
    flat.set_border_width_all(2)
    flat.set_corner_radius_all(radius)
    flat.shadow_color = Color(0, 0, 0, 0.42)
    flat.shadow_size = 10
    flat.shadow_offset = Vector2(0, 2)
    flat.content_margin_left = 12
    flat.content_margin_right = 12
    flat.content_margin_top = 10
    flat.content_margin_bottom = 10
    return flat


func _make_panel_node(rect: Rect2, danger: bool = false) -> Panel:
    var panel: = Panel.new()
    panel.position = rect.position
    panel.size = rect.size
    if UiKit.kit_texture("panel_frame.png") != null:
        panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
        var frame: = UiKit.make_ornate_frame(rect.size, "panel_frame.png", 0.16, 24.0)
        if danger:
            frame.modulate = Color(1.0, 0.58, 0.52, 1.0)
        panel.add_child(frame)
    else:
        var style: = _make_panel_style()
        if danger:
            (style as StyleBoxFlat).bg_color = Color(0.08, 0.02, 0.03, 0.86)
            (style as StyleBoxFlat).border_color = Color(0.88, 0.2, 0.18, 0.72)
        panel.add_theme_stylebox_override("panel", style)
    return panel


func _add_texture(parent: Control, path: String, rect: Rect2, alpha: float = 1.0, behind: bool = false) -> TextureRect:
    var texture: = _load_png_texture(path)
    var node: = TextureRect.new()
    node.position = rect.position
    node.size = rect.size
    node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    node.stretch_mode = TextureRect.STRETCH_SCALE
    node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    node.mouse_filter = Control.MOUSE_FILTER_IGNORE
    node.modulate.a = alpha
    if texture != null:
        node.texture = texture
    if behind:
        parent.add_child(node)
        parent.move_child(node, 0)
    else:
        parent.add_child(node)
    return node


func _make_label(text: String, font_size: int, color: Color) -> Label:
    return UiKit.make_label(text, font_size, color)



func _make_header_label(text: String, font_size: int, color: Color) -> Label:
    return UiKit.make_label_strong(text, font_size, color)



func _make_display_label(text: String, font_size: int, color: Color) -> Label:
    return UiKit.make_title(text, font_size, color)





func _build_ui() -> void :
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_root)


    var dim: = ColorRect.new()
    dim.color = Color(0.015, 0.016, 0.024, 0.9)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(dim)
    var backdrop_texture: = _load_battle_backdrop_texture()
    if backdrop_texture != null:
        var backdrop: = TextureRect.new()
        backdrop.texture = backdrop_texture
        backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
        backdrop.modulate = Color(1, 1, 1, 0.9)
        _root.add_child(backdrop)

    _design = Control.new()
    _design.position = ((get_viewport().get_visible_rect().size - DESIGN_SIZE) * 0.5).floor()
    _design.size = DESIGN_SIZE
    _design.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_design)


    _enemy_panel = _make_panel_node(Rect2(ENEMY_PANEL_POS, ENEMY_PANEL_SIZE))
    _design.add_child(_enemy_panel)

    var medallion_portrait: = TextureRect.new()
    medallion_portrait.texture = _cropped_portrait(_battle_portrait_texture(), 128, true)
    medallion_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    medallion_portrait.stretch_mode = TextureRect.STRETCH_SCALE
    medallion_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    medallion_portrait.position = Vector2(16, 15)
    medallion_portrait.size = Vector2(66, 66)
    medallion_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _enemy_panel.add_child(medallion_portrait)
    var ring_texture: = _v3("portrait_ring.png")
    if ring_texture != null:
        var ring: = TextureRect.new()
        ring.texture = ring_texture
        ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ring.stretch_mode = TextureRect.STRETCH_SCALE
        ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        ring.position = Vector2(9, 3)
        ring.size = Vector2(80, 89)
        ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _enemy_panel.add_child(ring)

    _enemy_name_label = _make_display_label("", 22, COLOR_TEXT)
    _enemy_name_label.position = Vector2(100, 12)
    _enemy_name_label.size = Vector2(138, 30)
    _enemy_name_label.clip_text = true
    _enemy_panel.add_child(_enemy_name_label)

    var enemy_chip: = _make_chip(Rect2(238, 16, 58, 21))
    _enemy_panel.add_child(enemy_chip["root"])
    _enemy_lv_label = enemy_chip["label"]
    _enemy_rank_label = _enemy_lv_label

    var enemy_hp_tag: = UiKit.make_label_strong("HP", 12, COLOR_ACCENT)
    enemy_hp_tag.position = Vector2(100, 50)
    enemy_hp_tag.size = Vector2(24, 18)
    _enemy_panel.add_child(enemy_hp_tag)

    var enemy_bar: = _make_ornate_bar(Rect2(126, 50, ENEMY_HP_BAR_W, 16), "red", COLOR_HP_GHOST)
    _enemy_panel.add_child(enemy_bar["root"])
    _enemy_hp_ghost = enemy_bar["ghost"]
    _enemy_hp_bar = enemy_bar["fill"]

    _enemy_hp_text = UiKit.make_label_strong("", 10, Color(0.98, 0.95, 0.88, 0.96))
    _enemy_hp_text.position = Vector2(126, 50)
    _enemy_hp_text.size = Vector2(ENEMY_HP_BAR_W, 16)
    _enemy_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _enemy_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _enemy_panel.add_child(_enemy_hp_text)

    _enemy_status_label = _make_label("", 12, COLOR_EXPOSED)
    _enemy_status_label.position = Vector2(126, 70)
    _enemy_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _enemy_status_label.size = Vector2(ENEMY_HP_BAR_W, 16)
    _enemy_panel.add_child(_enemy_status_label)

    _build_turn_order_strip()


    _portrait_holder = Control.new()
    _portrait_holder.position = PORTRAIT_HOME + Vector2(120, 0)
    _portrait_holder.size = PORTRAIT_SIZE
    _portrait_holder.modulate.a = 0.0
    _design.add_child(_portrait_holder)

    _portrait = TextureRect.new()
    _portrait.size = PORTRAIT_SIZE
    _portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    _portrait.pivot_offset = Vector2(PORTRAIT_SIZE.x * 0.5, PORTRAIT_SIZE.y)
    _portrait_holder.add_child(_portrait)
    _load_portrait()

    var add_material: = CanvasItemMaterial.new()
    add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

    _portrait_glow = _portrait.duplicate() as TextureRect
    _portrait_glow.material = add_material
    _portrait_glow.modulate = Color(COLOR_EXPOSED, 0.0)
    _portrait_holder.add_child(_portrait_glow)

    _portrait_flash = _portrait.duplicate() as TextureRect
    _portrait_flash.material = add_material.duplicate()
    _portrait_flash.modulate = Color(1, 1, 1, 0.0)
    _portrait_holder.add_child(_portrait_flash)


    _log_panel = Panel.new()
    _log_panel.position = LOG_PANEL_POS
    _log_panel.size = LOG_PANEL_SIZE
    _log_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    _log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _design.add_child(_log_panel)


    var scrim: = TextureRect.new()
    var scrim_gradient: = Gradient.new()
    scrim_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
    scrim_gradient.colors = PackedColorArray([
        Color(0.008, 0.012, 0.028, 0.72), 
        Color(0.008, 0.012, 0.028, 0.52), 
        Color(0.008, 0.012, 0.028, 0.0), 
    ])
    var scrim_texture: = GradientTexture2D.new()
    scrim_texture.gradient = scrim_gradient
    scrim_texture.fill = GradientTexture2D.FILL_RADIAL
    scrim_texture.fill_from = Vector2(0.5, 0.5)
    scrim_texture.fill_to = Vector2(0.5, 0.0)
    scrim_texture.width = 330
    scrim_texture.height = 152
    scrim.texture = scrim_texture
    scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    scrim.stretch_mode = TextureRect.STRETCH_SCALE
    scrim.position = Vector2(-26, -18)
    scrim.size = Vector2(382, 188)
    scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_panel.add_child(scrim)


    var warning_texture: = _v3("warning_triangle.png")
    if warning_texture != null:
        _intent_icon = TextureRect.new()
        _intent_icon.texture = warning_texture
        _intent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        _intent_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _intent_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        _intent_icon.position = Vector2(6, 6)
        _intent_icon.size = Vector2(22, 22)
        _intent_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _log_panel.add_child(_intent_icon)

    _intent_label = _make_label("", 13, Color(0.98, 0.92, 0.78, 0.98))
    var intent_font: = UiKit.body_font()
    if intent_font != null:
        var italic: = FontVariation.new()
        italic.base_font = intent_font
        italic.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.22, 1.0), Vector2.ZERO)
        _intent_label.add_theme_font_override("font", italic)
    _intent_label.position = Vector2(36, 0)
    _intent_label.size = Vector2(286, 46)
    _intent_label.add_theme_font_size_override("font_size", 13)
    _intent_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
    _intent_label.add_theme_constant_override("shadow_offset_x", 1)
    _intent_label.add_theme_constant_override("shadow_offset_y", 1)
    _intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _intent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _intent_label.clip_text = false
    _intent_label.max_lines_visible = 3
    _intent_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
    _log_panel.add_child(_intent_label)

    var log_divider: = ColorRect.new()
    log_divider.color = Color(0.76, 0.58, 0.27, 0.4)
    log_divider.position = Vector2(6, 50)
    log_divider.size = Vector2(300, 1)
    log_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_panel.add_child(log_divider)

    _log_label = RichTextLabel.new()
    _log_label.bbcode_enabled = true
    _log_label.scroll_active = false
    _log_label.fit_content = false
    _log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _log_label.position = Vector2(6, 58)
    _log_label.size = Vector2(300, 82)
    _log_label.add_theme_font_size_override("normal_font_size", FONT_SIZE - 1)
    _log_label.add_theme_color_override("default_color", COLOR_TEXT)
    _log_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    _log_label.add_theme_constant_override("shadow_offset_x", 1)
    _log_label.add_theme_constant_override("shadow_offset_y", 1)
    _log_label.add_theme_constant_override("line_separation", 3)
    _log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _log_panel.add_child(_log_label)

    _continue_marker = _make_label("v", FONT_SIZE, COLOR_ACCENT)
    _continue_marker.position = Vector2(292, 120)
    _continue_marker.visible = false
    _log_panel.add_child(_continue_marker)


    _menu_panel = Panel.new()
    _menu_panel.position = MENU_PANEL_POS
    _menu_panel.size = MENU_PANEL_SIZE
    _menu_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
    _menu_panel.visible = false
    _design.add_child(_menu_panel)

    # Info readout (icon + name + optional description) on a soft scrim,
    # directly above the icon-only command row — no frame, mockup-style.
    var info_scrim := TextureRect.new()
    var info_gradient := Gradient.new()
    info_gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
    info_gradient.colors = PackedColorArray([
        Color(0.008, 0.012, 0.028, 0.72),
        Color(0.008, 0.012, 0.028, 0.50),
        Color(0.008, 0.012, 0.028, 0.0),
    ])
    var info_texture := GradientTexture2D.new()
    info_texture.gradient = info_gradient
    info_texture.fill = GradientTexture2D.FILL_RADIAL
    info_texture.fill_from = Vector2(0.5, 0.5)
    info_texture.fill_to = Vector2(0.5, 0.0)
    info_texture.width = 470
    info_texture.height = 86
    info_scrim.texture = info_texture
    info_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    info_scrim.stretch_mode = TextureRect.STRETCH_SCALE
    info_scrim.position = Vector2(-20, -34)
    info_scrim.size = Vector2(510, 104)
    info_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _menu_panel.add_child(info_scrim)

    _menu_info_icon = TextureRect.new()
    _menu_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _menu_info_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _menu_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    _menu_info_icon.position = Vector2(80, 8)
    _menu_info_icon.size = Vector2(34, 34)
    _menu_info_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _menu_panel.add_child(_menu_info_icon)

    _menu_info_name = UiKit.make_title("", 16, COLOR_ACCENT)
    _menu_info_name.position = Vector2(124, 2)
    _menu_info_name.size = Vector2(336, 22)
    _menu_info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _menu_info_name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _menu_info_name.clip_text = false
    _menu_info_name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
    _menu_panel.add_child(_menu_info_name)

    _menu_info_desc = _make_label("", 10, Color(0.93, 0.88, 0.72, 0.98))
    _menu_info_desc.position = Vector2(124, 26)
    _menu_info_desc.size = Vector2(346, 14)
    _menu_info_desc.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
    _menu_info_desc.add_theme_constant_override("shadow_offset_x", 1)
    _menu_info_desc.add_theme_constant_override("shadow_offset_y", 1)
    _menu_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _menu_info_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _menu_info_desc.clip_text = false
    _menu_info_desc.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
    _menu_panel.add_child(_menu_info_desc)

    _menu_row = HBoxContainer.new()
    _menu_row.position = Vector2(0, 56)
    _menu_row.size = Vector2(470, 60)
    _menu_row.add_theme_constant_override("separation", 8)
    _menu_panel.add_child(_menu_row)

    _menu_cursor = Control.new()
    var cursor_line: = ColorRect.new()
    cursor_line.color = Color(1.0, 0.79, 0.35, 0.95)
    cursor_line.size = Vector2(64, 2)
    _menu_cursor.add_child(cursor_line)
    _menu_cursor.visible = false
    _menu_panel.add_child(_menu_cursor)


    _player_panel = _make_panel_node(Rect2(PLAYER_PANEL_POS, PLAYER_PANEL_SIZE))
    _design.add_child(_player_panel)

    var hero_holder: = Control.new()
    hero_holder.position = Vector2(14, 14)
    hero_holder.size = Vector2(110, 130)
    hero_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _player_panel.add_child(hero_holder)
    var hero_picture: = TextureRect.new()
    var hero_texture: = _hero_portrait_texture()
    hero_picture.texture = hero_texture
    hero_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE


    hero_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if hero_texture != null and hero_texture.get_width() > 200 else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    hero_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if hero_texture != null and hero_texture.get_width() > 200 else CanvasItem.TEXTURE_FILTER_NEAREST
    hero_picture.position = Vector2(5, 5)
    hero_picture.size = hero_holder.size - Vector2(10, 10)
    hero_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hero_holder.add_child(hero_picture)
    hero_holder.add_child(UiKit.make_ornate_frame(hero_holder.size, "slot.png", 0.2, 14.0, false))

    _player_panel_label = _make_display_label(_player_name(), 24, COLOR_ACCENT)
    _player_panel_label.position = Vector2(140, 10)
    _player_panel_label.size = Vector2(92, 30)
    _player_panel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _player_panel_label.clip_text = false
    _player_panel_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
    _player_panel.add_child(_player_panel_label)

    var player_chip: = _make_chip(Rect2(238, 14, 58, 21))
    _player_panel.add_child(player_chip["root"])
    _player_lv_label = player_chip["label"]

    var player_hp_tag: = UiKit.make_label_strong("HP", 12, COLOR_ACCENT)
    player_hp_tag.position = Vector2(140, 48)
    player_hp_tag.size = Vector2(24, 18)
    _player_panel.add_child(player_hp_tag)

    var player_bar: = _make_ornate_bar(Rect2(166, 48, PLAYER_HP_BAR_W, 16), "green", COLOR_HP_GHOST)
    _player_panel.add_child(player_bar["root"])
    _player_hp_ghost = player_bar["ghost"]
    _player_hp_bar = player_bar["fill"]

    _player_hp_text = UiKit.make_label_strong("", 10, Color(0.98, 0.95, 0.88, 0.96))
    _player_hp_text.position = Vector2(166, 48)
    _player_hp_text.size = Vector2(PLAYER_HP_BAR_W, 16)
    _player_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _player_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _player_panel.add_child(_player_hp_text)

    _player_status_label = UiKit.make_label_strong("", 10, COLOR_ACCENT)
    _player_status_label.position = Vector2(140, 68)
    _player_status_label.size = Vector2(156, 14)
    _player_panel.add_child(_player_status_label)

    _sp_pip_row = Control.new()
    _sp_pip_row.position = Vector2(140, 88)
    _player_panel.add_child(_sp_pip_row)
    _build_sp_pips()

    var xp_label: = UiKit.make_label_strong("XP", 11, COLOR_TEXT_DIM)
    xp_label.position = Vector2(140, 116)
    _player_panel.add_child(xp_label)

    var xp_bar: = UiKit.make_bar(Rect2(166, 116, PLAYER_HP_BAR_W, 11), "blue")
    _player_panel.add_child(xp_bar["root"])
    _xp_bar = xp_bar["fill"]

    _player_xp_text = _make_label("", 9, COLOR_TEXT_DIM)
    _player_xp_text.position = Vector2(166, 130)
    _player_xp_text.size = Vector2(PLAYER_HP_BAR_W, 12)
    _player_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _player_panel.add_child(_player_xp_text)

    _hint_label = _make_label("Arrows Move    Enter Select    / Esc Back", 13, COLOR_TEXT_DIM)
    _hint_label.position = Vector2(476, 520)
    _hint_label.size = Vector2(420, 20)
    _hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _hint_label.visible = false
    _design.add_child(_hint_label)


    _fx_layer = Control.new()
    _fx_layer.position = Vector2.ZERO
    _fx_layer.size = DESIGN_SIZE
    _fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _design.add_child(_fx_layer)

    _refresh_enemy_panel()
    _refresh_player_panel()
    _play_intro_animation()


func _build_turn_order_strip() -> void :


    var title: = _make_display_label("TURN ORDER", 11, COLOR_ACCENT)
    title.position = TURN_ORDER_TITLE_POS
    title.size = TURN_ORDER_TITLE_SIZE
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _design.add_child(title)

    _turn_stack = Control.new()
    _turn_stack.position = TURN_ORDER_STACK_POS
    _turn_stack.size = TURN_ORDER_STACK_SIZE
    _turn_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _design.add_child(_turn_stack)
    _update_turn_order(_turn_active_actor, false)


const TURN_CARD_SIZE: = Vector2(148, 44)
const TURN_CARD_RIGHT: = 954.0
const TURN_CARD_TUCK: = 0.0
const TURN_CARD_POP: = 6.0




func _update_turn_order(active: String, animate: bool = true) -> void :
    _turn_active_actor = active
    if _turn_stack == null:
        return
    for card in _turn_cards:
        if animate:
            # Departing queue scrolls up and fades out.
            var out := create_tween()
            out.tween_property(card, "position:y", card.position.y - 54.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
            out.parallel().tween_property(card, "modulate:a", 0.0, 0.22)
            out.tween_callback(card.queue_free)
        else:
            card.queue_free()
    _turn_cards.clear()

    var player_texture: = _player_turn_texture()
    var enemy_texture: = _battle_portrait_texture()
    var order: Array = []
    for index in range(4):
        var is_player: = (index % 2 == 0) == (active == "player")
        order.append({
            "actor": "player" if is_player else "enemy", 
            "texture": player_texture if is_player else enemy_texture, 
            "label": _player_name() if is_player else _enemy_name(),
        })

    for index in range(order.size()):
        var entry: Dictionary = order[index]
        var is_active: = index == 0
        var card: = _make_turn_card(entry, is_active)
        var final_x: = TURN_CARD_RIGHT - TURN_CARD_SIZE.x - (TURN_CARD_POP if is_active else 0.0) + (0.0 if is_active else TURN_CARD_TUCK)
        var y: = float(index) * (TURN_CARD_SIZE.y + 10.0)
        if animate:
            # Incoming queue scrolls UP into place while fading in.
            card.position = Vector2(final_x, y + 54.0)
            card.modulate.a = 0.0
            var rise := create_tween()
            rise.tween_property(card, "position:y", y, 0.28).set_delay(0.05 * index).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
            rise.parallel().tween_property(card, "modulate:a", 1.0 if index > 0 else 1.0, 0.26).set_delay(0.05 * index)
            if index > 0:
                rise.parallel().tween_property(card, "modulate", Color(0.72, 0.74, 0.84, 0.82), 0.26).set_delay(0.05 * index)
        else:
            card.position = Vector2(final_x, y)
        _turn_stack.add_child(card)
        _turn_cards.append(card)




func _player_turn_texture() -> Texture2D:
    return _hero_portrait_texture()


## Crop a character texture into a slanted banner that FILLS a turn card:
## center-cropped to the card aspect (face-biased), then alpha-masked to the
## card art's parallelogram interior so it never spills past the gold border.
func _banner_portrait(texture: Texture2D, out_w: int = 296, out_h: int = 88) -> Texture2D:
    if texture == null:
        return null
    var image := texture.get_image()
    if image == null:
        return texture
    image = image.duplicate()
    if image.is_compressed():
        image.decompress()
    image.convert(Image.FORMAT_RGBA8)
    var ratio := float(out_w) / float(out_h)
    var crop_w := float(image.get_width())
    var crop_h := crop_w / ratio
    if crop_h > float(image.get_height()):
        crop_h = float(image.get_height())
        crop_w = crop_h * ratio
    var x0 := int((image.get_width() - crop_w) * 0.5)
    var y0 := int(clampf((image.get_height() - crop_h) * 0.32, 0.0, float(image.get_height()) - crop_h))
    var band := image.get_region(Rect2i(x0, y0, int(crop_w), int(crop_h)))
    var interp := Image.INTERPOLATE_NEAREST if image.get_width() <= 96 else Image.INTERPOLATE_LANCZOS
    band.resize(out_w, out_h, interp)
    var slant := out_w * 0.145
    var inset := out_w * 0.028
    for y in range(out_h):
        var t := float(y) / float(out_h - 1)
        var left_edge := slant * (1.0 - t) + inset
        var right_edge := float(out_w) - inset * 1.6
        var row_alpha := 1.0 if y >= int(inset) and y < out_h - int(inset) else 0.0
        for x in range(out_w):
            var alpha := row_alpha
            if float(x) < left_edge:
                alpha *= clampf(float(x) - left_edge + 1.5, 0.0, 1.0)
            elif float(x) > right_edge:
                alpha *= clampf(right_edge - float(x) + 1.5, 0.0, 1.0)
            if alpha < 1.0:
                var color := band.get_pixel(x, y)
                color.a *= alpha
                band.set_pixel(x, y, color)
    return ImageTexture.create_from_image(band)


func _make_turn_card(entry: Dictionary, is_active: bool) -> Control:
    var card := Control.new()
    card.size = TURN_CARD_SIZE
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var art := _v3("turncard_active.png" if is_active else "turncard.png")
    if art != null:
        var backing := TextureRect.new()
        backing.texture = art
        backing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        backing.stretch_mode = TextureRect.STRETCH_SCALE
        backing.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        backing.size = TURN_CARD_SIZE
        backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(backing)
    else:
        var flat := ColorRect.new()
        flat.color = Color(0.14, 0.11, 0.04, 0.92) if is_active else Color(0.03, 0.045, 0.09, 0.85)
        flat.size = TURN_CARD_SIZE
        flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(flat)

    # The character image fills the whole card (parallelogram-masked band),
    # no name text — the picture IS the card.
    var source: Texture2D = entry.get("texture")
    var banner := TextureRect.new()
    banner.texture = _banner_portrait(source)
    banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    banner.stretch_mode = TextureRect.STRETCH_SCALE
    banner.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if source != null and source.get_width() > 96 else CanvasItem.TEXTURE_FILTER_NEAREST
    banner.size = TURN_CARD_SIZE
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    card.add_child(banner)

    if not is_active:
        card.modulate = Color(0.72, 0.74, 0.84, 0.82)
    return card

func _build_sp_pips() -> void :
    for pip in _sp_pips:
        pip.queue_free()
    _sp_pips.clear()
    var sp_max: int = int(player_stats.get("sp_max", 3))
    var filled_texture: = _v3("sp_gem.png")
    var empty_texture: = _v3("sp_gem_empty.png")
    for index in range(sp_max):
        if filled_texture != null:
            var gem: = TextureRect.new()
            gem.texture = filled_texture
            gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
            gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
            gem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
            gem.position = Vector2(index * 24, 0)
            gem.size = Vector2(18, 18)
            gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
            gem.set_meta("empty_texture", empty_texture)
            gem.set_meta("filled_texture", filled_texture)
            _sp_pip_row.add_child(gem)
            _sp_pips.append(gem)
        else:
            var pip: = ColorRect.new()
            pip.size = Vector2(10, 10)
            pip.position = Vector2(index * 18 + 5, 2)
            pip.rotation_degrees = 45.0
            pip.pivot_offset = Vector2(5, 5)
            _sp_pip_row.add_child(pip)
            _sp_pips.append(pip)
    _refresh_sp_pips()


func _refresh_sp_pips() -> void :
    for index in range(_sp_pips.size()):
        var pip: = _sp_pips[index]
        var filled: = index < player_sp
        if pip is TextureRect and pip.has_meta("filled_texture"):
            var empty_texture: Texture2D = pip.get_meta("empty_texture")
            if empty_texture != null:
                (pip as TextureRect).texture = pip.get_meta("filled_texture") if filled else empty_texture
            else:
                (pip as TextureRect).texture = pip.get_meta("filled_texture")
                pip.modulate = Color(1, 1, 1, 1.0) if filled else Color(0.35, 0.35, 0.42, 0.8)
        elif pip is ColorRect:
            (pip as ColorRect).color = COLOR_ACCENT if filled else Color(0.25, 0.22, 0.3, 0.9)


func _play_intro_animation() -> void :

    var flash: = ColorRect.new()
    flash.color = Color(1, 1, 1, 0.85)
    flash.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(flash)
    var flash_tween: = create_tween()
    flash_tween.tween_property(flash, "color:a", 0.0, 0.45)
    flash_tween.tween_callback(flash.queue_free)



    var off: Vector2 = _design.position
    _enemy_panel.position.y = -ENEMY_PANEL_SIZE.y - 40.0 - off.y
    _log_panel.position.x = -LOG_PANEL_SIZE.x - 40.0 - off.x
    _menu_panel.position.y = DESIGN_SIZE.y + 24.0 + off.y
    _player_panel.position.x = -PLAYER_PANEL_SIZE.x - 40.0 - off.x

    var slide: = create_tween().set_parallel(true)
    slide.tween_property(_enemy_panel, "position:y", ENEMY_PANEL_POS.y, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    slide.tween_property(_log_panel, "position:x", LOG_PANEL_POS.x, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    slide.tween_property(_menu_panel, "position:y", MENU_PANEL_POS.y, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    slide.tween_property(_player_panel, "position:x", PLAYER_PANEL_POS.x, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    slide.tween_property(_portrait_holder, "position", PORTRAIT_HOME, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    slide.tween_property(_portrait_holder, "modulate:a", 1.0, 0.4)

    _start_breathing()


func _start_breathing() -> void :
    var breath: = create_tween().set_loops()
    breath.tween_property(_portrait, "scale", Vector2(1.0, 1.015), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    breath.tween_property(_portrait, "scale", Vector2(1.0, 1.0), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _battle_portrait_texture() -> Texture2D:
    var portrait_file: String = str(enemy.get("battle_portrait_file", ""))
    var texture: Texture2D = null
    if not portrait_file.is_empty():
        texture = GameManager.load_texture(GameManager.get_scene_asset_path(portrait_file))
    if texture == null:
        var sheet_file: String = str(enemy.get("sprite_sheet_file", ""))
        var sheet: Texture2D = null
        if not sheet_file.is_empty():
            sheet = GameManager.load_texture(GameManager.get_scene_asset_path(sheet_file))
        if sheet == null:
            sheet = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
        if sheet != null:
            var atlas: = AtlasTexture.new()
            atlas.atlas = sheet
            atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
            texture = atlas
    return texture



func _hero_portrait_texture() -> Texture2D:
    var emotion_portrait: = _player_emotion_portrait_texture("neutral")
    if emotion_portrait != null:
        return emotion_portrait
    var hero: = _v3("hero_portrait.png")
    if hero != null:
        return hero
    var sheet: = GameManager.load_texture(GameManager.get_player_sprite_path())
    if sheet == null:
        sheet = GameManager.load_texture(GameManager.DEFAULT_PLAYER_SPRITE_PATH)
    if sheet != null:
        var atlas: = AtlasTexture.new()
        atlas.atlas = sheet
        atlas.region = Rect2(0, 0, GameManager.CHARACTER_FRAME_SIZE, GameManager.CHARACTER_FRAME_SIZE)
        return atlas
    return null


func _player_emotion_portrait_texture(emotion: String) -> Texture2D:
    var package: Dictionary = GameManager.get_scene_package()
    var characters: Dictionary = package.get("characters", {}) as Dictionary
    var main_character: Variant = characters.get("main_character", {})
    if main_character is Dictionary:
        return _character_emotion_portrait_texture(main_character as Dictionary, emotion)
    return null


func _character_emotion_portrait_texture(character: Dictionary, emotion: String) -> Texture2D:
    var emotion_info: Variant = character.get("emotion_portraits")
    if not (emotion_info is Dictionary):
        return null
    var portraits: Array = (emotion_info as Dictionary).get("portraits", []) as Array
    for wanted in [_normalize_battle_emotion(emotion), "neutral"]:
        for raw_portrait in portraits:
            if not (raw_portrait is Dictionary):
                continue
            var portrait: Dictionary = raw_portrait as Dictionary
            if str(portrait.get("emotion", "")) != wanted:
                continue
            var file_name: String = str(portrait.get("file", ""))
            if file_name.is_empty():
                continue
            var texture: Texture2D = GameManager.load_texture(GameManager.get_scene_asset_path(file_name))
            if texture != null:
                return texture
    return null


func _normalize_battle_emotion(emotion: String) -> String:
    match emotion.strip_edges().to_lower():
        "happy", "joy", "joyful", "pleased", "relieved":
            return "happy"
        "angry", "anger", "mad", "irritated", "annoyed":
            return "angry"
        "sad", "sorrow", "worried", "wary", "uneasy", "haunted", "tired", "afraid", "scared":
            return "sad"
        _:
            return "neutral"


func _load_portrait() -> void :
    var texture: = _battle_portrait_texture()
    if texture == null:
        _portrait.modulate = Color(1.0, 0.45, 0.45)
    _portrait.texture = texture


    if texture != null and texture.get_width() > 200:
        _portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    else:
        _portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _load_battle_backdrop_texture() -> Texture2D:
    var backdrop_file: String = str(enemy.get("battle_background_file", ""))
    if backdrop_file.is_empty():
        var package: Dictionary = GameManager.get_scene_package()
        var battle_background: Dictionary = package.get("battle_background", {}) as Dictionary
        backdrop_file = str(battle_background.get("image", ""))
    if not backdrop_file.is_empty():
        var texture: = GameManager.load_texture(GameManager.get_scene_asset_path(backdrop_file))
        if texture != null:
            return texture
    if ResourceLoader.exists(TEX_BACKDROP):
        return load(TEX_BACKDROP) as Texture2D
    return null





func _shake(strength: float, duration: float) -> void :
    _shake_strength = max(_shake_strength, strength)
    _shake_time = max(_shake_time, duration)


func _portrait_center() -> Vector2:
    return _portrait_holder.position + Vector2(PORTRAIT_SIZE.x * 0.5, PORTRAIT_SIZE.y * 0.46)


func _flash_portrait(color: Color = Color(1, 1, 1, 1), strength: float = 0.85) -> void :
    _portrait_flash.modulate = Color(color.r, color.g, color.b, strength)
    var tween: = create_tween()
    tween.tween_property(_portrait_flash, "modulate:a", 0.0, 0.28)


func _spawn_slash(at: Vector2, tint: Color = Color(1, 1, 1, 1), effect_scale: float = 1.3, flipped: bool = false) -> void :
    if _slash_frames != null:
        var slash: = AnimatedSprite2D.new()
        slash.sprite_frames = _slash_frames
        slash.position = at
        slash.scale = Vector2( - effect_scale if flipped else effect_scale, effect_scale)
        slash.modulate = tint
        slash.rotation_degrees = randf_range(-18.0, 18.0)
        _fx_layer.add_child(slash)
        slash.play("slash")
        slash.animation_finished.connect(slash.queue_free)
    else:

        var line: = Line2D.new()
        line.width = 3.0
        line.default_color = tint if tint != Color(1, 1, 1, 1) else COLOR_ACCENT
        for step in range(9):
            var angle: float = deg_to_rad(-60.0 + step * 15.0)
            line.add_point(at + Vector2(cos(angle), sin(angle)) * 34.0)
        _fx_layer.add_child(line)
        var tween: = create_tween()
        tween.tween_property(line, "modulate:a", 0.0, 0.25)
        tween.tween_callback(line.queue_free)


func _spawn_particles(at: Vector2, color: Color, amount: int = 14, spread_up: bool = true) -> void :
    var particles: = CPUParticles2D.new()
    particles.position = at
    particles.one_shot = true
    particles.emitting = true
    particles.amount = amount
    particles.lifetime = 0.6
    particles.explosiveness = 0.95
    particles.direction = Vector2(0, -1) if spread_up else Vector2(0, 1)
    particles.spread = 70.0
    particles.gravity = Vector2(0, 160.0)
    particles.initial_velocity_min = 40.0
    particles.initial_velocity_max = 95.0
    particles.scale_amount_min = 1.0
    particles.scale_amount_max = 2.4
    particles.color = color
    _fx_layer.add_child(particles)
    get_tree().create_timer(1.4).timeout.connect(particles.queue_free)


func _spawn_damage_number(at: Vector2, text: String, color: Color, big: bool = false) -> void :
    var label: = _make_label(text, 14 if big else 11, color)
    label.position = at + Vector2(randf_range(-12.0, 12.0), -6.0)
    label.pivot_offset = Vector2(12, 8)
    label.scale = Vector2(1.7, 1.7)
    _fx_layer.add_child(label)
    var tween: = create_tween()
    tween.tween_property(label, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.parallel().tween_property(label, "position:y", label.position.y - 24.0, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.25)
    tween.tween_callback(label.queue_free)


func _enemy_hit_react(heavy: bool = false) -> void :
    _flash_portrait()
    _shake(5.0 if heavy else 3.0, 0.3 if heavy else 0.22)
    var recoil: = create_tween()
    recoil.tween_property(_portrait_holder, "position", PORTRAIT_HOME + Vector2(10, -4), 0.07)
    recoil.tween_property(_portrait_holder, "position", PORTRAIT_HOME, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enemy_lunge() -> void :
    var lunge: = create_tween()
    lunge.tween_property(_portrait_holder, "position", PORTRAIT_HOME + Vector2(-22, 6), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
    lunge.tween_property(_portrait_holder, "position", PORTRAIT_HOME, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_exposed_glow(active: bool) -> void :
    if active:
        var pulse: = create_tween().set_loops()
        pulse.set_meta("exposed_pulse", true)
        pulse.tween_property(_portrait_glow, "modulate:a", 0.45, 0.55).set_trans(Tween.TRANS_SINE)
        pulse.tween_property(_portrait_glow, "modulate:a", 0.12, 0.55).set_trans(Tween.TRANS_SINE)
        _portrait_glow.set_meta("pulse_tween", pulse)
    else:
        var pulse: Variant = _portrait_glow.get_meta("pulse_tween") if _portrait_glow.has_meta("pulse_tween") else null
        if pulse is Tween and (pulse as Tween).is_valid():
            (pulse as Tween).kill()
        var fade: = create_tween()
        fade.tween_property(_portrait_glow, "modulate:a", 0.0, 0.3)


func _animate_enemy_hp() -> void :
    if _enemy_hp_text != null:
        _enemy_hp_text.text = "%d / %d" % [maxi(enemy_hp, 0), enemy_max_hp]
    var ratio: float = clampf(float(enemy_hp) / float(enemy_max_hp), 0.0, 1.0)
    var tween: = create_tween()
    tween.tween_property(_enemy_hp_bar, "size:x", ENEMY_HP_BAR_W * ratio, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var ghost: = create_tween()
    ghost.tween_property(_enemy_hp_ghost, "size:x", ENEMY_HP_BAR_W * ratio, 0.5).set_delay(0.35).set_trans(Tween.TRANS_CUBIC)


func _animate_player_hp() -> void :
    var max_hp: int = int(player_stats.get("max_hp", 80))
    if _player_hp_text != null:
        _player_hp_text.text = "%d / %d" % [GameManager.get_player_hp(), max_hp]
    var ratio: float = clampf(float(GameManager.get_player_hp()) / float(max_hp), 0.0, 1.0)
    var tween: = create_tween()
    tween.tween_property(_player_hp_bar, "size:x", PLAYER_HP_BAR_W * ratio, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    var ghost: = create_tween()
    ghost.tween_property(_player_hp_ghost, "size:x", PLAYER_HP_BAR_W * ratio, 0.5).set_delay(0.35).set_trans(Tween.TRANS_CUBIC)
    if _player_hp_bar.size.x / PLAYER_HP_BAR_W > ratio:
        var damage_flash: = create_tween()
        damage_flash.tween_property(_player_panel, "modulate", Color(1.0, 0.6, 0.6), 0.08)
        damage_flash.tween_property(_player_panel, "modulate", Color.WHITE, 0.3)





func _run_battle() -> void :
    await get_tree().create_timer(0.6).timeout
    for line in _dialogue("intro"):
        await _say(line)

    _pick_enemy_intent()
    var enemy_first: bool = enemy_speed > int(player_stats.get("speed", 9))
    if enemy_first:
        await _say("%s moves first!" % _enemy_name())
        await _enemy_turn()

    while not _battle_over:
        _apply_party_regen()
        await _player_turn()
        if _battle_over:
            break
        await _check_phases()
        if _battle_over:
            break
        await _enemy_turn()
        if exposed_turns > 0:
            exposed_turns -= 1
            if exposed_turns == 0:
                _set_exposed_glow(false)
                await _say("The opening closes. %s steadies itself." % _enemy_name())
            _refresh_enemy_panel()


func _player_turn() -> void :
    _update_turn_order("player")
    guarding = false
    var ids: Array[String] = ["attack", "skill", "probe", "item", "guard", "flee"]
    var labels: Array[String] = ["Attack", "Skill", "Probe", "Item", "Guard", "Flee"]
    var descs: Array[String] = [
        "A precise strike with your blade.",
        "Channel a special technique.",
        "Study the enemy for a weakness.",
        "Use something from your pack.",
        "Brace yourself and recover 1 SP.",
        "Attempt to escape the battle.",
    ]
    if exposed_turns > 0 and not finisher_used:
        ids.insert(0, "finisher")
        labels.insert(0, "Resolve Strike!")
        descs.insert(0, "Exploit the opening — a decisive blow.")
    if bool(enemy.get("can_spare", false)) and enemy_hp <= int(enemy_max_hp * 0.3):
        ids.append("spare")
        labels.append("Spare")
        descs.append("Show mercy and end the fight.")

    var choice: String = await _menu(ids, labels, descs)
    match choice:
        "attack":
            await _player_attack(1.0, "You strike!", COLOR_ACCENT)
        "finisher":
            finisher_used = true
            _flash_portrait(COLOR_EXPOSED, 1.0)
            _shake(7.0, 0.4)
            _spawn_slash(_portrait_center(), COLOR_EXPOSED, 1.9)
            _spawn_slash(_portrait_center() + Vector2(8, 10), Color(1, 1, 1, 0.9), 1.5, true)
            await _player_attack(3.0, "You answer its secret with one decisive blow!", COLOR_EXPOSED)
        "skill":
            await _skill_menu()
        "probe":
            await _probe_menu()
        "item":
            await _item_menu()
        "guard":
            guarding = true
            player_sp = mini(player_sp + 1, int(player_stats.get("sp_max", 3)))
            _refresh_player_panel()
            _spawn_particles(PLAYER_FX_CENTER, Color(0.6, 0.75, 1.0), 10)
            await _say("You brace yourself and watch carefully. (+1 SP)")
        "flee":
            await _try_flee()
        "spare":
            await _spare_enemy()


func _skill_menu() -> void :
    var skills: Array[Dictionary] = GameManager.player_skills()
    var ids: Array[String] = []
    var labels: Array[String] = []
    var descs: Array[String] = []
    for index in range(skills.size()):
        var skill: Dictionary = skills[index]
        ids.append(str(index))
        labels.append("%s (%d SP)" % [skill["name"], int(skill["sp_cost"])])
        descs.append(str(skill.get("desc", "")))
    ids.append("back")
    labels.append("Back")
    descs.append("")

    var choice: String = await _menu(ids, labels, descs)
    if choice == "back":
        await _player_turn()
        return
    var skill: Dictionary = skills[int(choice)]
    if player_sp < int(skill["sp_cost"]):
        await _say("Not enough SP. Guard to recover.")
        await _player_turn()
        return
    player_sp -= int(skill["sp_cost"])
    _refresh_player_panel()


    match str(skill.get("effect", "attack")):
        "focus":
            focus_active = true
            _spawn_particles(PLAYER_FX_CENTER, Color(0.45, 0.65, 1.0), 18)
            var aura: = create_tween()
            aura.tween_property(_player_panel, "modulate", Color(0.7, 0.85, 1.3), 0.2)
            aura.tween_property(_player_panel, "modulate", Color.WHITE, 0.5)
            await _say("You center yourself. Your next attack will hit twice as hard.")
        "heal":
            var heal_amount: int = int(round(float(skill["power"]))) + GameManager.player_level * 2
            GameManager.set_player_hp(GameManager.get_player_hp() + heal_amount)
            _animate_player_hp()
            _refresh_player_panel()
            _spawn_particles(PLAYER_FX_CENTER, COLOR_HEAL, 18)
            _spawn_damage_number(PLAYER_FX_CENTER + Vector2(0, -18), "+%d" % heal_amount, COLOR_HEAL)
            var glow: = create_tween()
            glow.tween_property(_player_panel, "modulate", Color(0.75, 1.25, 0.85), 0.2)
            glow.tween_property(_player_panel, "modulate", Color.WHITE, 0.5)
            await _say("You use %s and restore %d HP." % [skill["name"], heal_amount])
        "multi":
            var hits: int = clampi(int(round(float(skill["power"]))), 2, 4)
            var per_hit: float = 0.7
            for hit_index in range(hits):
                if _battle_over or enemy_hp <= 0:
                    break
                _spawn_slash(_portrait_center() + Vector2(randf_range(-14, 14), randf_range(-10, 10)), Color(0.7, 0.9, 1.0), 1.4, hit_index % 2 == 0)
                await _player_attack(per_hit, "%s — hit %d!" % [skill["name"], hit_index + 1], Color(0.7, 0.9, 1.0))
        "pierce":
            _spawn_slash(_portrait_center(), Color(1.0, 0.55, 0.85), 1.7)
            await _player_attack(float(skill["power"]), "You unleash %s — it pierces the guard!" % skill["name"], Color(1.0, 0.55, 0.85), true)
        _:
            _spawn_slash(_portrait_center(), Color(1.0, 0.62, 0.2), 1.6)
            await _player_attack(float(skill["power"]), "You unleash %s!" % skill["name"], Color(1.0, 0.62, 0.2))


func _item_menu() -> void :
    var usable: Array[Dictionary] = InventoryManager.usable_in_battle()
    if usable.is_empty():
        await _say("You carry nothing usable in battle.")
        await _player_turn()
        return
    var ids: Array[String] = []
    var labels: Array[String] = []
    var descs: Array[String] = []
    for index in range(usable.size()):
        var item: Dictionary = usable[index]
        ids.append(str(index))
        labels.append("%s ×%d" % [item.get("name", "?"), InventoryManager.count_of(str(item.get("id")))])
        descs.append(str(item.get("desc", item.get("description", ""))))
    ids.append("back")
    labels.append("Back")
    descs.append("")

    var choice: String = await _menu(ids, labels, descs)
    if choice == "back":
        await _player_turn()
        return
    var item: Dictionary = usable[int(choice)]
    var item_id: String = str(item.get("id"))
    if not InventoryManager.remove_item(item_id):
        await _player_turn()
        return
    match str(item.get("kind")):
        "heal":
            var amount: int = int(item.get("power", 40))
            GameManager.set_player_hp(GameManager.get_player_hp() + amount)
            _animate_player_hp()
            _refresh_player_panel()
            _spawn_particles(PLAYER_FX_CENTER, COLOR_HEAL, 16)
            _spawn_damage_number(PLAYER_FX_CENTER + Vector2(0, -18), "+%d" % amount, COLOR_HEAL)
            await _say("You use %s. Restored %d HP." % [item.get("name"), amount])
        "energy":
            var sp_gain: int = int(item.get("power", 2))
            player_sp = mini(player_sp + sp_gain, int(player_stats.get("sp_max", 3)))
            _refresh_player_panel()
            _spawn_particles(PLAYER_FX_CENTER, Color(0.55, 0.6, 1.0), 14)
            await _say("You use %s. Restored %d SP." % [item.get("name"), sp_gain])
        "buff":
            focus_active = true
            _spawn_particles(PLAYER_FX_CENTER, Color(1.0, 0.6, 0.3), 18)
            var aura: = create_tween()
            aura.tween_property(_player_panel, "modulate", Color(1.3, 1.0, 0.7), 0.2)
            aura.tween_property(_player_panel, "modulate", Color.WHITE, 0.5)
            await _say("You use %s. Your next attack is empowered!" % item.get("name"))


func _probe_menu() -> void :
    var weakness: Dictionary = enemy.get("weakness", {}) as Dictionary
    if weakness_found:
        await _say("You already see through it. Its weakness is laid bare.")
        await _player_turn()
        return
    if probe_options.is_empty():
        await _say("It refuses to answer anything more.")
        await _player_turn()
        return

    await _say(str(weakness.get("hint", "You look for a crack in its resolve.")))

    var ids: Array[String] = []
    var labels: Array[String] = []
    for index in range(probe_options.size()):
        ids.append(str(index))
        labels.append(str((probe_options[index] as Dictionary).get("text", "...")))
    ids.append("back")
    labels.append("Back")

    var choice: String = await _menu(ids, labels)
    if choice == "back":
        await _player_turn()
        return

    var option: Dictionary = probe_options[int(choice)] as Dictionary
    probe_options.remove_at(int(choice))
    await _say(str(option.get("reveal", "...")))

    if bool(option.get("correct", false)):
        weakness_found = true
        exposed_turns = int(weakness.get("vulnerable_turns", 3)) + 1
        _set_exposed_glow(true)
        _flash_portrait(COLOR_EXPOSED, 0.8)
        _shake(4.0, 0.3)
        _spawn_particles(_portrait_center(), COLOR_EXPOSED, 22)
        _refresh_enemy_panel()
        await _say("%s is EXPOSED! Your words found the wound. (damage x%.1f)" % [
            _enemy_name(), float(weakness.get("damage_multiplier", 2.0)), 
        ])
    else:
        await _say("Wrong nerve. %s lashes out while you hesitate!" % _enemy_name())
        await _enemy_strike(0.8, "")


func _player_attack(power: float, flavor: String, fx_color: Color = COLOR_ACCENT, ignore_defense: bool = false) -> void :
    var base: float = float(player_stats.get("attack", 12)) * power
    if focus_active:
        base *= 2.0
        focus_active = false
    if hexed:
        base *= 0.7
        hexed = false
    var weakness: Dictionary = enemy.get("weakness", {}) as Dictionary
    var exposed_now: bool = exposed_turns > 0
    if exposed_now:
        base *= float(weakness.get("damage_multiplier", 2.0))
    var variance: float = randf_range(0.85, 1.15)
    var crit: bool = randf() < 0.1

    var defense_cut: float = 0.0 if ignore_defense else enemy_defense * phase_defense_factor * 0.5
    var damage: int = maxi(int(round(base * variance * (1.5 if crit else 1.0) - defense_cut)), 1)
    enemy_hp = maxi(enemy_hp - damage, 0)

    _spawn_slash(_portrait_center(), fx_color, 1.5 if power > 1.2 else 1.25)
    _enemy_hit_react(power >= 1.5 or crit)
    _spawn_particles(_portrait_center(), fx_color if not exposed_now else COLOR_EXPOSED)
    _spawn_damage_number(
        _portrait_center() + Vector2(0, -34), 
        str(damage) + ("!" if crit else ""), 
        COLOR_CRIT if crit else (COLOR_EXPOSED if exposed_now else Color.WHITE), 
        crit or power >= 1.8, 
    )
    _animate_enemy_hp()
    _refresh_enemy_panel()

    var text: String = "%s %d damage%s" % [flavor + " ", damage, " — CRITICAL!" if crit else "."]
    await _say(text)

    if enemy_hp <= 0:
        await _victory()
    elif enemy_hp <= int(enemy_max_hp * 0.3):
        var low_lines: Array = _dialogue("low_hp")
        if not low_lines.is_empty() and not triggered_phases.has("_low_hp"):
            triggered_phases["_low_hp"] = true
            await _say("%s: \"%s\"" % [_enemy_name(), low_lines[0]])
            if bool(enemy.get("can_spare", false)):
                await _say("It is wavering. You could choose to spare it.")


func _check_phases() -> void :
    var ratio: float = float(enemy_hp) / float(enemy_max_hp)
    for phase in enemy.get("phases", []) as Array:
        if not (phase is Dictionary):
            continue
        var key: = str((phase as Dictionary).get("hp_ratio", 0.5))
        if triggered_phases.has(key):
            continue
        if ratio <= float((phase as Dictionary).get("hp_ratio", 0.5)):
            triggered_phases[key] = true
            _flash_portrait(Color(1.0, 0.4, 0.3), 0.7)
            _shake(4.0, 0.35)
            var beat: String = str((phase as Dictionary).get("story_beat", ""))
            if not beat.is_empty():
                await _say("%s: \"%s\"" % [_enemy_name(), beat])
            match str((phase as Dictionary).get("behavior", "aggressive")):
                "aggressive":
                    phase_damage_bonus = 1.15
                    await _say("Its attacks grow fiercer!")
                "desperate":
                    phase_damage_bonus = 1.3
                    phase_defense_factor = 0.6
                    await _say("It fights desperately — harder, but careless!")


func _enemy_turn() -> void :
    _update_turn_order("enemy")
    if _battle_over:
        return
    var skill: Dictionary = intent
    _pick_enemy_intent()
    await _enemy_use_skill(skill)


func _enemy_use_skill(skill: Dictionary) -> void :
    var kind: String = str(skill.get("kind", "strike"))
    var skill_name: String = str(skill.get("name", "Attack"))
    var power: float = float(skill.get("power", 1.0))
    if kind == "heavy":

        _portrait_flash.modulate = Color(1.0, 0.3, 0.2, 0.0)
        var windup: = create_tween()
        windup.tween_property(_portrait_flash, "modulate:a", 0.5, 0.35)
        windup.tween_property(_portrait_flash, "modulate:a", 0.0, 0.15)
        await windup.finished
    match kind:
        "hex":
            hexed = true
            _spawn_particles(PLAYER_FX_CENTER, Color(0.7, 0.35, 0.9), 16, false)
            await _enemy_strike(power * 0.5, "%s uses %s! A weakening curse clings to you." % [_enemy_name(), skill_name])
        "guard_break":
            if guarding:
                await _enemy_strike(power * 1.6, "%s uses %s — it smashes straight through your guard!" % [_enemy_name(), skill_name])
            else:
                await _enemy_strike(power * 0.9, "%s uses %s." % [_enemy_name(), skill_name])
        _:
            await _enemy_strike(power, "%s uses %s!" % [_enemy_name(), skill_name])


func _enemy_strike(power: float, flavor: String) -> void :
    var base: float = float(enemy_attack) * power * phase_damage_bonus
    var variance: float = randf_range(0.85, 1.15)
    var damage: float = base * variance - float(player_stats.get("defense", 5)) * 0.5
    if guarding:
        damage *= 0.5
    var final_damage: int = maxi(int(round(damage)), 1)

    _enemy_lunge()
    await get_tree().create_timer(0.14).timeout
    _shake(5.0 if power >= 1.5 else 3.0, 0.3)
    _spawn_damage_number(PLAYER_FX_CENTER + Vector2(10, -92), str(final_damage), COLOR_PLAYER_DMG, power >= 1.5)
    GameManager.set_player_hp(GameManager.get_player_hp() - final_damage)
    _animate_player_hp()
    _refresh_player_panel()

    var guard_note: String = " You guarded (halved)." if guarding else ""
    if flavor.is_empty():
        await _say("It hits you for %d.%s" % [final_damage, guard_note])
    else:
        await _say("%s %d damage to you.%s" % [flavor + " ", final_damage, guard_note])

    if GameManager.get_player_hp() <= 0:
        await _defeat()


func _pick_enemy_intent() -> void :
    var skills: Array = enemy.get("skills", []) as Array
    var usable: Array[Dictionary] = []
    for skill in skills:
        if skill is Dictionary:
            if str((skill as Dictionary).get("kind", "")) == "heavy" and turns_since_heavy < 2:
                continue
            usable.append(skill as Dictionary)
    if usable.is_empty():
        usable.append({"name": "Attack", "kind": "strike", "power": 1.0, "telegraph": ""})
    intent = usable[randi() % usable.size()]
    if str(intent.get("kind", "")) == "heavy":
        turns_since_heavy = 0
    else:
        turns_since_heavy += 1
    var telegraph: String = str(intent.get("telegraph", ""))
    if str(intent.get("kind", "")) == "heavy":
        _intent_label.add_theme_color_override("font_color", COLOR_HP.lightened(0.3))
    else:
        _intent_label.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78, 0.98))
    _intent_label.text = telegraph if not telegraph.is_empty() else "It watches you."
    _intent_label.modulate.a = 0.0
    var fade: = create_tween()
    fade.tween_property(_intent_label, "modulate:a", 1.0, 0.4)


func _try_flee() -> void :
    var chance: float = clampf(
        0.5 + 0.05 * float(int(player_stats.get("speed", 9)) - enemy_speed) + 0.15 * flee_failed_count, 
        0.25, 
        0.95, 
    )
    if randf() < chance:
        await _say("You slip away from the fight.")
        _finish("fled")
    else:
        flee_failed_count += 1
        _shake(2.0, 0.2)
        await _say("You can't get away!")


func _spare_enemy() -> void :
    for line in _dialogue("spare"):
        await _say("%s: \"%s\"" % [_enemy_name(), line])
    var fade: = create_tween()
    fade.tween_property(_portrait_holder, "modulate", Color(1, 1, 1, 0.35), 1.0)
    var xp: int = _scaled_battle_xp(int(int(enemy.get("xp_reward", 20)) * 0.6))
    await _grant_xp(xp, "You lower your weapon. +%d XP." % xp)
    _finish("spared")


func _victory() -> void :
    _set_exposed_glow(false)

    var dissolve: = create_tween()
    dissolve.tween_property(_portrait_holder, "modulate", Color(1.4, 1.4, 1.4, 0.0), 0.9).set_trans(Tween.TRANS_CUBIC)
    dissolve.parallel().tween_property(_portrait_holder, "position:y", PORTRAIT_HOME.y + 24.0, 0.9)
    _spawn_particles(_portrait_center(), Color(1, 1, 1, 0.9), 26)
    _shake(3.0, 0.25)

    for line in _dialogue("finish"):
        await _say(line)
    for line in _dialogue("player_victory"):
        await _say("%s: \"%s\"" % [_enemy_name(), line])

    _show_victory_banner()
    var xp: int = _scaled_battle_xp(int(enemy.get("xp_reward", 20)))
    if weakness_found:
        var bonus: int = int(xp * 0.25)
        xp += bonus
        await _grant_xp(xp, "Victory! +%d XP (+%d for understanding its story)." % [xp, bonus])
    else:
        await _grant_xp(xp, "Victory! +%d XP." % xp)
    var dropped: String = InventoryManager.roll_battle_drop(str(enemy.get("rank", "minion")))
    if not dropped.is_empty():
        _spawn_particles(SCREEN_CENTER, COLOR_ACCENT, 12)
        await _say("It left something behind: %s." % InventoryManager.item_def(dropped).get("name", dropped))
    _finish("victory")


func _show_victory_banner() -> void :
    var banner_root: = Control.new()
    banner_root.position = Vector2(480, 180)
    _fx_layer.add_child(banner_root)

    if _banner_texture != null:
        var ornament: = TextureRect.new()
        ornament.texture = _banner_texture
        ornament.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        var w: float = 360.0
        var h: float = w * float(_banner_texture.get_height()) / float(_banner_texture.get_width())
        ornament.size = Vector2(w, h)
        ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        ornament.position = Vector2( - w / 2.0, - h / 2.0)
        banner_root.add_child(ornament)

    var text: = _make_display_label("VICTORY", 34, COLOR_ACCENT)
    text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text.position = Vector2(-140, -22)
    text.size = Vector2(280, 44)
    banner_root.add_child(text)

    banner_root.scale = Vector2(0.2, 0.2)
    banner_root.pivot_offset = Vector2.ZERO
    banner_root.modulate.a = 0.0
    var pop: = create_tween()
    pop.tween_property(banner_root, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    pop.parallel().tween_property(banner_root, "modulate:a", 1.0, 0.3)
    for index in range(5):
        _spawn_particles(Vector2(randf_range(300, 660), randf_range(110, 230)), COLOR_ACCENT, 12)


func _apply_party_regen() -> void :


    var regen: int = int(player_stats.get("party_regen", 0))
    if regen <= 0:
        return
    var max_hp: int = int(player_stats.get("max_hp", 80))
    if GameManager.get_player_hp() >= max_hp:
        return
    GameManager.set_player_hp(GameManager.get_player_hp() + regen)
    _animate_player_hp()
    _refresh_player_panel()
    _spawn_particles(PLAYER_FX_CENTER, COLOR_HEAL, 8)
    _spawn_damage_number(PLAYER_FX_CENTER + Vector2(-6, -18), "+%d" % regen, COLOR_HEAL)


func _on_companion_leveled(npc_id: String, level: int) -> void :
    _companion_levelups.append({"npc_id": npc_id, "level": level})


## Level-gap governor: an enemy far below the player's level teaches little
## (mirrors the talk-XP scaling in GameManager.award_talk_xp) — grinding
## low-level minions can't push the player far past the zone's balance anchor.
## Applied at the reward call sites so the "+N XP" messages show the real number.
func _scaled_battle_xp(raw: int) -> int:
    var reference_level: int = int(enemy.get("level", 0))
    if reference_level <= 0:
        reference_level = ChapterFlow.expected_level_here()
    return maxi(1, int(round(float(raw) * GameManager.xp_gap_factor(reference_level))))


func _grant_xp(xp: int, message: String) -> void :

    var boosted: int = int(round(float(xp) * float(player_stats.get("party_xp_mult", 1.0))))
    _companion_levelups.clear()
    var levels: int = GameManager.grant_party_xp(boosted)
    player_stats = GameManager.player_battle_stats()
    var xp_tween: = create_tween()
    xp_tween.tween_property(
        _xp_bar, "size:x", 
        (PLAYER_HP_BAR_W - 30) * clampf(float(GameManager.player_xp) / float(GameManager.xp_to_next_level()), 0.0, 1.0), 
        0.7, 
    ).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _refresh_player_panel()
    await _say(message)
    if levels > 0:
        _build_sp_pips()
        _spawn_particles(PLAYER_FX_CENTER, COLOR_ACCENT, 28)
        _spawn_damage_number(PLAYER_FX_CENTER + Vector2(80, -80), "LEVEL UP!", COLOR_ACCENT, true)
        var glow: = create_tween()
        glow.tween_property(_player_panel, "modulate", Color(1.4, 1.3, 0.9), 0.25)
        glow.tween_property(_player_panel, "modulate", Color.WHITE, 0.6)
        await _say("LEVEL UP! You are now level %d. You feel restored and stronger." % GameManager.player_level)

    for entry in _companion_levelups:
        var npc_id: String = str((entry as Dictionary).get("npc_id", ""))
        var comp_name: String = PartyManager.companion_name(npc_id) if PartyManager.has_method("companion_name") else npc_id
        await _say("%s reached level %d!" % [comp_name, int((entry as Dictionary).get("level", 1))])
    _companion_levelups.clear()


func _defeat() -> void :
    var dark: = create_tween()
    dark.tween_property(_root, "modulate", Color(0.55, 0.5, 0.6), 1.2)
    for line in _dialogue("player_defeat"):
        await _say("%s: \"%s\"" % [_enemy_name(), line])
    GameManager.lose_xp_on_defeat()
    await _say("Your memory frays... you lose some experience and wake up where you started.")
    _finish("defeat")


func _finish(result: String) -> void :
    _battle_over = true
    GameManager.ui_blocking_input = false
    battle_finished.emit(result, enemy_id)
    queue_free()







func _decorate_log_line(text: String) -> String:
    var icon_file: = "log_sparkle.png"
    var lower: = text.to_lower()
    if lower.contains("damage") or lower.contains("attack") or lower.contains("strike") or lower.contains("hit"):
        icon_file = "log_sword.png"
    elif lower.contains("prepar") or lower.contains("smoke") or lower.contains("hex") or lower.contains("gather") or lower.contains("materializ"):
        icon_file = "log_swirl.png"
    var body: = text
    var enemy_name: = _enemy_name()
    if not enemy_name.is_empty():
        body = body.replace(enemy_name, "[color=#e5534b]%s[/color]" % enemy_name)
    var icon_path: = BATTLE_V3_DIR + icon_file
    if ResourceLoader.exists(icon_path):
        return "[img=15x15]%s[/img]  %s" % [icon_path, body]
    return body


func _say(text: String) -> void :
    if _battle_over:
        return
    _clear_menu()
    _continue_marker.visible = false
    _type_target = text
    _type_progress = 0.0
    _log_label.text = _decorate_log_line(text)
    _log_label.visible_characters = 0
    _ui_mode = UiMode.TYPING
    while _ui_mode == UiMode.TYPING:
        await get_tree().process_frame
    _continue_marker.visible = true
    var bounce: = create_tween().set_loops(3)
    bounce.tween_property(_continue_marker, "position:y", 124.0, 0.25)
    bounce.tween_property(_continue_marker, "position:y", 120.0, 0.25)
    _ui_mode = UiMode.CONFIRM
    await _confirmed
    _continue_marker.visible = false
    _ui_mode = UiMode.NONE


func _menu(ids: Array[String], labels: Array[String], descs: Array[String] = []) -> String:
    _clear_menu()
    _menu_ids = ids
    _menu_descs = descs
    _menu_index = 0
    _menu_panel.visible = true
    _menu_panel.modulate.a = 0.0
    if _hint_label != null:
        _hint_label.visible = false
    var panel_in: = create_tween()
    panel_in.tween_property(_menu_panel, "modulate:a", 1.0, 0.16)
    var count: int = maxi(labels.size(), 1)
    var card_w: float = minf(60.0, (470.0 - float(maxi(count - 1, 0) * 8)) / float(count))
    var total_w: float = card_w * float(count) + float(maxi(count - 1, 0) * 8)
    _menu_row.position.x = maxf((470.0 - total_w) * 0.5, 0.0)
    _menu_row.size.x = minf(total_w, 470.0)
    for index in range(labels.size()):
        var item: = _make_menu_card(labels[index], _menu_icon_path(ids[index], labels[index]), index, card_w)
        _menu_row.add_child(item)
        _menu_items.append(item)
    _menu_cursor.visible = true
    _ui_mode = UiMode.MENU
    _highlight_menu()
    var picked: String = await _menu_picked
    _menu_cursor.visible = false
    _clear_menu()
    _ui_mode = UiMode.NONE
    return picked


func _clear_menu() -> void :
    for item in _menu_items:
        item.queue_free()
    _menu_items.clear()
    _menu_ids.clear()
    if _menu_cursor != null:
        _menu_cursor.visible = false
    if _menu_panel != null:
        _menu_panel.visible = false
    if _hint_label != null:
        _hint_label.visible = false


func _highlight_menu() -> void :
    for index in range(_menu_items.size()):
        var selected: bool = index == _menu_index
        var item: = _menu_items[index]
        _set_menu_card_selected(item, selected)
        if selected:
            var bump: = create_tween()
            bump.tween_property(item, "position:y", -5.0, 0.08)
            bump.tween_property(item, "position:y", 0.0, 0.12)
    await get_tree().process_frame
    if _menu_index < _menu_items.size():
        _menu_cursor.visible = false


## Icon-only square chip; the readout above the row carries name/description.
func _make_menu_card(text: String, icon_path: String, index: int, width: float) -> Panel:
    var side := width
    var card := Panel.new()
    card.custom_minimum_size = Vector2(side, side)
    card.size = Vector2(side, side)
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    if UiKit.kit_texture("card.png") != null:
        card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
        var frame_normal := UiKit.make_ornate_frame(card.size, "card.png", 0.24, 14.0)
        var frame_selected := UiKit.make_ornate_frame(card.size, "card_selected.png", 0.24, 14.0)
        frame_selected.visible = false
        card.add_child(frame_normal)
        card.add_child(frame_selected)
        card.set_meta("frame_normal", frame_normal)
        card.set_meta("frame_selected", frame_selected)
    else:
        card.add_theme_stylebox_override("panel", _make_menu_card_style(false))
    card.gui_input.connect(_on_menu_card_gui_input.bind(index))
    card.set_meta("label_text", text)

    var icon_node: CanvasItem
    if not icon_path.is_empty():
        var icon_size := side - 20.0
        var icon := _add_texture(card, icon_path, Rect2((side - icon_size) * 0.5, (side - icon_size) * 0.5, icon_size, icon_size), 0.92)
        icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        icon_node = icon
    else:
        var icon := ColorRect.new()
        icon.color = Color(0.95, 0.8, 0.48, 0.72)
        icon.position = Vector2(side * 0.5 - 6, side * 0.5 - 6)
        icon.size = Vector2(12, 12)
        icon.rotation_degrees = 45
        icon.pivot_offset = Vector2(6, 6)
        card.add_child(icon)
        icon_node = icon
    card.set_meta("icon_node", icon_node)
    return card


## Fill the readout above the row from the selected entry.
func _refresh_menu_info() -> void:
    if _menu_info_name == null or _menu_index >= _menu_ids.size():
        return
    var id := _menu_ids[_menu_index]
    var label_text := ""
    if _menu_index < _menu_items.size() and _menu_items[_menu_index].has_meta("label_text"):
        label_text = str(_menu_items[_menu_index].get_meta("label_text"))
    var icon_path := _menu_icon_path(id, label_text)
    var icon_texture: Texture2D = _load_png_texture(icon_path) if not icon_path.is_empty() else null
    _menu_info_icon.texture = icon_texture
    _menu_info_icon.visible = icon_texture != null
    _menu_info_name.text = label_text
    var desc := ""
    if _menu_index < _menu_descs.size():
        desc = _menu_descs[_menu_index].strip_edges()
    _menu_info_desc.text = desc
    _menu_info_desc.visible = not desc.is_empty()
    _layout_menu_info(not desc.is_empty())


func _layout_menu_info(has_desc: bool) -> void:
    var name_h: = _wrapped_label_height(_menu_info_name, 22.0, 40.0)
    _menu_info_name.size.y = name_h
    if not has_desc:
        _menu_info_name.position.y = 8.0 if name_h <= 24.0 else 2.0
        _menu_info_desc.size.y = 0.0
        return

    var desc_h: = _wrapped_label_height(_menu_info_desc, 14.0, 36.0)
    var gap: = 2.0
    var row_top: = _menu_row.position.y if _menu_row != null else 56.0
    var total_h: = name_h + gap + desc_h
    var top: = minf(2.0, row_top - 4.0 - total_h)
    top = maxf(-28.0, top)
    _menu_info_name.position.y = top
    _menu_info_desc.position.y = top + name_h + gap
    _menu_info_desc.size.y = desc_h


func _wrapped_label_height(label: Label, min_height: float, max_height: float) -> float:
    var line_count: = maxi(label.get_line_count(), 1)
    var line_height: = float(label.get_line_height())
    if line_height <= 0.0:
        line_height = float(label.get_theme_font_size("font_size")) + 2.0
    return clampf(float(line_count) * line_height + 2.0, min_height, max_height)


func _make_menu_card_style(selected: bool) -> StyleBox:
    var texture: = UiKit.kit_texture("card_selected.png" if selected else "card.png")
    if texture != null:


        return UiKit.ninepatch_style(texture, minf(texture.get_width(), texture.get_height()) * 0.26, 6.0)
    var style: = StyleBoxFlat.new()
    style.bg_color = Color(0.03, 0.035, 0.045, 0.88) if not selected else Color(0.14, 0.1, 0.035, 0.95)
    style.border_color = Color(0.6, 0.5, 0.34, 0.58) if not selected else Color(1.0, 0.78, 0.32, 0.96)
    style.set_border_width_all(2)
    style.set_corner_radius_all(3)
    style.shadow_size = 6 if not selected else 16
    style.shadow_color = Color(0, 0, 0, 0.35) if not selected else Color(1.0, 0.63, 0.18, 0.34)
    return style


func _set_menu_card_selected(card: Control, selected: bool) -> void :
    if card.has_meta("frame_normal"):
        (card.get_meta("frame_normal") as Control).visible = not selected
        (card.get_meta("frame_selected") as Control).visible = selected
    elif card is Panel:
        (card as Panel).add_theme_stylebox_override("panel", _make_menu_card_style(selected))
    if card.has_meta("label_node"):
        var label: = card.get_meta("label_node") as Label
        if label != null:
            label.add_theme_color_override("font_color", COLOR_ACCENT if selected else COLOR_TEXT_DIM)
    if card.has_meta("icon_node"):
        var icon: = card.get_meta("icon_node") as CanvasItem
        if icon is ColorRect:
            icon.color = Color(1.0, 0.86, 0.4, 1.0) if selected else Color(0.95, 0.8, 0.48, 0.55)
        elif icon != null:
            icon.modulate = Color(1.18, 1.08, 0.82, 1.0) if selected else Color(0.82, 0.8, 0.74, 0.78)
    if selected:
        _refresh_menu_info()


func _menu_icon_path(id: String, label: String) -> String:

    var v3_path: = BATTLE_V3_DIR + "icon_%s.png" % id
    if ResourceLoader.exists(v3_path):
        return v3_path
    match id:
        "attack":
            return TEX_B2_ICON_ATTACK
        "skill":
            return TEX_B2_ICON_SKILL
        "probe":
            return TEX_B2_ICON_PROBE
        "item":
            return TEX_B2_ICON_ITEM
        "guard":
            return TEX_B2_ICON_GUARD
        "flee":
            return TEX_B2_ICON_FLEE
        "finisher":
            return TEX_B2_ICON_FINISHER
        "spare":
            return TEX_B2_ICON_SPARE
        "back":
            return ""
    var lower_label: = label.to_lower()
    if id.is_valid_int():
        if lower_label.contains("potion") or lower_label.contains("tonic") or lower_label.contains("elixir") or lower_label.contains("×"):
            return TEX_B2_ICON_ITEM
        return TEX_B2_ICON_SKILL
    return ""


func _on_menu_card_gui_input(event: InputEvent, index: int) -> void :
    if _ui_mode != UiMode.MENU or index < 0 or index >= _menu_ids.size():
        return
    if event is InputEventMouseMotion and _menu_index != index:
        _menu_index = index
        _highlight_menu()
    elif event is InputEventMouseButton:
        var mouse_event: = event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
            _menu_index = index
            _highlight_menu()
            _menu_picked.emit(_menu_ids[_menu_index])


func _process(delta: float) -> void :
    if _hint_label != null:
        _hint_label.visible = false
    if _menu_panel != null and _ui_mode != UiMode.MENU and _menu_items.is_empty():
        _menu_panel.visible = false

    if _ui_mode == UiMode.TYPING:
        _type_progress += TYPE_SPEED * delta
        var total_chars: int = _log_label.get_total_character_count()
        var visible_chars: int = mini(int(_type_progress), total_chars)
        _log_label.visible_characters = visible_chars
        if visible_chars >= total_chars:
            _finish_typing()

    if _shake_time > 0.0:
        _shake_time -= delta
        var decay: float = _shake_time * 3.0
        _root.position = Vector2(
            randf_range(-1.0, 1.0) * _shake_strength * decay, 
            randf_range(-1.0, 1.0) * _shake_strength * decay, 
        )
        if _shake_time <= 0.0:
            _root.position = Vector2.ZERO
            _shake_strength = 0.0


func _finish_typing() -> void :
    _log_label.visible_characters = -1
    _ui_mode = UiMode.NONE


func _unhandled_input(event: InputEvent) -> void :
    if _battle_over:
        return
    if event.is_action_pressed("ui_accept"):
        match _ui_mode:
            UiMode.TYPING:
                _finish_typing()
                get_viewport().set_input_as_handled()
            UiMode.CONFIRM:
                _confirmed.emit()
                get_viewport().set_input_as_handled()
            UiMode.MENU:
                if _menu_index < _menu_ids.size():
                    _menu_picked.emit(_menu_ids[_menu_index])
                get_viewport().set_input_as_handled()
        return
    if _ui_mode != UiMode.MENU:
        return
    var moved: = false
    if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
        _menu_index = (_menu_index + 1) % _menu_ids.size()
        moved = true
    elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
        _menu_index = (_menu_index - 1 + _menu_ids.size()) % _menu_ids.size()
        moved = true
    if moved:
        _highlight_menu()
        get_viewport().set_input_as_handled()





func _refresh_enemy_panel() -> void :
    _enemy_name_label.text = _enemy_name()
    _fit_label_font(_enemy_name_label, 22, 12)
    _enemy_lv_label.text = "Lv %d" % int(enemy.get("level", 1))
    _enemy_hp_text.text = "%d / %d" % [maxi(enemy_hp, 0), enemy_max_hp]
    _enemy_status_label.text = "EXPOSED %d" % exposed_turns if exposed_turns > 0 else ""


func _refresh_player_panel() -> void :
    var max_hp: int = int(player_stats.get("max_hp", 80))
    _player_panel_label.text = _player_name()
    _player_lv_label.text = "Lv.%d" % GameManager.player_level
    _player_hp_text.text = "%d / %d" % [GameManager.get_player_hp(), max_hp]
    var statuses: Array[String] = []
    if focus_active:
        statuses.append("FOCUS")
    if hexed:
        statuses.append("HEX")
    _player_status_label.text = "  ·  ".join(statuses)
    _player_xp_text.text = "%d / %d" % [GameManager.player_xp, GameManager.xp_to_next_level()]
    _refresh_sp_pips()
    _player_hp_bar.size.x = PLAYER_HP_BAR_W * clampf(float(GameManager.get_player_hp()) / float(max_hp), 0.0, 1.0)
    _xp_bar.size.x = PLAYER_HP_BAR_W * clampf(float(GameManager.player_xp) / float(GameManager.xp_to_next_level()), 0.0, 1.0)


func _enemy_name() -> String:
    return str(enemy.get("name", "Enemy"))


func _player_name() -> String:
    var package: Dictionary = GameManager.get_scene_package()
    var characters: Dictionary = package.get("characters", {}) as Dictionary
    var main_character: Variant = characters.get("main_character", {})
    if main_character is Dictionary:
        var name: String = str((main_character as Dictionary).get("name", "")).strip_edges()
        if not name.is_empty() and name.to_upper() != "YOU":
            return name
    return "Bạn"


func _dialogue(key: String) -> Array:
    var dialogue: Dictionary = enemy.get("dialogue", {}) as Dictionary
    var lines: Array = dialogue.get(key, []) as Array
    var result: Array = []
    for line in lines:
        var text: = str(line).strip_edges()
        if not text.is_empty():
            result.append(text)
    return result
