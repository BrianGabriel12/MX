extends Area2D
## Item de vida. Escena: Area2D + (Sprite2D o AnimatedSprite2D) + CollisionShape2D.
## Life_Min cura 7, Life_Max cura 15 y Heart expande la barra 25 (y llena esa parte nueva).
## Detecta cuerpos de CUALQUIER capa y solo reacciona a quien pueda curarse (el jugador),
## así no depende de cómo tengas configuradas las capas de colisión.
## Si el item tiene un AnimatedSprite2D o un AnimationPlayer, reproduce su animación solo.

enum Tipo { LIFE_MIN, LIFE_MAX, HEART }
const CANTIDAD_POR_DEFECTO := {Tipo.LIFE_MIN: 7, Tipo.LIFE_MAX: 15, Tipo.HEART: 25}

@export var tipo := Tipo.LIFE_MIN
@export var cantidad := 0          # 0 = usa el valor por defecto del tipo (7, 15 o 25)
@export var animation_name := ""   # animación a reproducir (vacío = elige sola: Idle, default o la primera)
@export var force_loop := false    # true = fuerza el loop de la animación elegida; false = respeta el loop que pusiste en el editor
@export var debug_log := false     # imprime en Salida qué hace el item


func _ready() -> void:
	monitoring = true
	collision_layer = 0          # nadie necesita "ver" al item
	collision_mask = 0xFFFFFFFF  # el item ve cuerpos en todas las capas
	body_entered.connect(_on_body_entered)
	_start_animations()
	_check_shape.call_deferred()


func _check_shape() -> void:
	if PhysicsServer2D.area_get_shape_count(get_rid()) == 0:
		push_warning("Item '%s': no tiene forma de colisión. Agrégale un CollisionShape2D y asígnale una Shape (RectangleShape2D)." % name)


func _on_body_entered(body: Node2D) -> void:
	var method := "increase_max_hp" if tipo == Tipo.HEART else "heal"
	if debug_log:
		print("Item ", name, " tocó a ", body.name, " (tiene ", method, ": ", body.has_method(method), ")")
	if not body.has_method(method):
		return  # no es el jugador (un enemigo, el piso...): lo ignora
	var amount: int = cantidad if cantidad > 0 else CANTIDAD_POR_DEFECTO[tipo]
	if body.call(method, amount):
		queue_free()


# ---------------------------------------------------------------- ANIMACIÓN

func _start_animations() -> void:
	for n in find_children("*", "AnimatedSprite2D", true, false):
		_play_sprite(n as AnimatedSprite2D)
	for n in find_children("*", "AnimationPlayer", true, false):
		_play_player(n as AnimationPlayer)


func _play_sprite(s: AnimatedSprite2D) -> void:
	if s.sprite_frames == null:
		push_warning("Item '%s': el AnimatedSprite2D '%s' no tiene SpriteFrames." % [name, s.name])
		return
	var chosen := _pick(s.sprite_frames.get_animation_names(), String(s.animation))
	if chosen == "":
		return
	if force_loop:
		s.sprite_frames.set_animation_loop(chosen, true)
	s.play(chosen)
	if debug_log:
		print("Item ", name, ": AnimatedSprite2D reproduce '", chosen, "'")


func _play_player(p: AnimationPlayer) -> void:
	var chosen := _pick(p.get_animation_list(), String(p.autoplay))
	if chosen == "":
		return
	if force_loop:
		p.get_animation(chosen).loop_mode = Animation.LOOP_LINEAR
	p.play(chosen)
	if debug_log:
		print("Item ", name, ": AnimationPlayer reproduce '", chosen, "'")


# Elige qué animación reproducir: la que pusiste en animation_name; si no, "Idle" o "default";
# si no, la que ya tenía asignada; si no, la primera (ignorando RESET)
func _pick(names: PackedStringArray, current: String) -> String:
	if animation_name != "":
		if names.has(animation_name):
			return animation_name
		push_warning("Item '%s': no existe la animación '%s'. Disponibles: %s" % [name, animation_name, ", ".join(names)])
	for preferred in ["idle", "default"]:
		for n in names:
			if n.to_lower() == preferred:
				return n
	if current != "" and names.has(current):
		return current
	for n in names:
		if n != "RESET":
			return n
	push_warning("Item '%s': no encontré ninguna animación para reproducir." % name)
	return ""
