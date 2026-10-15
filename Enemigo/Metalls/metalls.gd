extends CharacterBody2D
## Enemigo Metalls.
## Nodos: Sprite2D, AnimationPlayer, CollisionShape2D y un Marker2D llamado "Muzzle" (salida de la bala).
## Animaciones: Idle, Move, Shield, Shot. El jugador debe estar en el grupo "Player".
##
## Ciclo: Idle/Move (al azar) -> Shot (al ver al jugador o por azar) -> espera de 1 a 3 s
## (al azar: camina al lado contrario o activa Shield) -> vuelve a salir y disparar.
## En Shield NO recibe daño; en cualquier otro estado sí.

enum State { IDLE, MOVE, SHIELD, SHOT }

@export_group("Vida")
@export var max_hp := 6

@export_group("Movimiento")
@export var move_speed := 40.0
@export var gravity := 900.0
@export var patrol_range := 48.0       # cuánto se aleja de su punto inicial al caminar
@export var idle_time_min := 1.0
@export var idle_time_max := 2.0
@export var move_time_min := 1.0
@export var move_time_max := 2.0

@export_group("Ataque")
@export var bullet_scene: PackedScene  # ball.tscn
@export var detect_range := 220.0      # distancia horizontal para detectar al jugador
@export var detect_height := 64.0      # tolerancia vertical para detectarlo
@export var random_shot_chance := 0.25 # probabilidad de disparar "por gusto" al decidir qué hacer
@export var shot_fire_delay := 0.25    # segundo de la animación Shot en el que sale la bala
@export var rest_time_min := 1.0       # tras disparar: espera mínima antes de volver a disparar
@export var rest_time_max := 3.0       # tras disparar: espera máxima (se elige un tiempo al azar entre ambos)
@export var walk_away_chance := 0.5    # tras disparar: probabilidad de caminar al lado contrario (si no, Shield)

@export_group("Sprite")
@export var sprite_faces_left := true  # el sprite se dibujó mirando a la izquierda

@export_group("Depuración")
@export var debug_log := false         # imprime en Salida lo que hace (útil para ajustar la detección)

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var muzzle: Marker2D = $Muzzle

var hp := 1
var state := State.IDLE
var facing := -1
var state_time := 0.0       # tiempo que falta para terminar el estado
var state_elapsed := 0.0    # tiempo que lleva en el estado
var cooldown_left := 0.0
var origin_x := 0.0
var muzzle_offset_x := 0.0
var shot_fired := false
var player: Node2D = null
var warned_no_player := false
var walking_away := false   # true mientras camina al lado contrario después de disparar


func _ready() -> void:
	add_to_group("Enemy")
	hp = max_hp
	origin_x = global_position.x
	muzzle_offset_x = absf(muzzle.position.x)
	_enter(State.IDLE)


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	state_time -= delta
	state_elapsed += delta

	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	match state:
		State.IDLE:
			_state_idle()
		State.MOVE:
			_state_move()
		State.SHIELD:
			_state_shield()
		State.SHOT:
			_state_shot()

	_apply_facing()
	move_and_slide()


# ------------------------------------------------------------------- ESTADOS

func _enter(new_state: State, duration := -1.0) -> void:
	state = new_state
	walking_away = false
	if debug_log:
		print("Metalls -> ", State.keys()[new_state])
	state_elapsed = 0.0
	shot_fired = false
	match state:
		State.IDLE:
			state_time = randf_range(idle_time_min, idle_time_max)
			_play(&"Idle")
		State.MOVE:
			state_time = duration if duration > 0.0 else randf_range(move_time_min, move_time_max)
			_play(&"Move")
		State.SHIELD:
			state_time = duration if duration > 0.0 else randf_range(rest_time_min, rest_time_max)
			_play(&"Shield")
		State.SHOT:
			state_time = anim.get_animation(&"Shot").length
			_play(&"Shot")


func _state_idle() -> void:
	velocity.x = 0.0
	if _check_attack():
		return
	if state_time <= 0.0:
		_decide_next()


func _state_move() -> void:
	# Da la vuelta si choca con una pared o se pasó de su zona de patrulla
	if is_on_wall() or (global_position.x - origin_x) * facing >= patrol_range:
		if walking_away:
			velocity.x = 0.0
			_enter(State.IDLE)  # llegó al límite caminando: se queda quieto el resto de la espera
			return
		facing = -facing
	velocity.x = facing * move_speed
	if _check_attack():
		return
	if state_time <= 0.0:
		_decide_next()


func _state_shield() -> void:
	velocity.x = 0.0
	if state_time <= 0.0:
		_enter(State.IDLE)


func _state_shot() -> void:
	velocity.x = 0.0
	if not shot_fired and (state_elapsed >= shot_fire_delay or state_time <= 0.0):
		shot_fired = true
		_fire()
	if state_time <= 0.0:
		_after_shot()


# Tras disparar espera un tiempo al azar (1 a 3 s) antes de volver a salir a disparar.
# En ese tiempo decide: caminar al lado contrario o activar Shield.
func _after_shot() -> void:
	var rest := randf_range(rest_time_min, rest_time_max)
	cooldown_left = rest  # no vuelve a disparar hasta que termine la espera
	if randf() < walk_away_chance:
		facing = -facing  # da la espalda y camina al lado contrario
		_enter(State.MOVE, rest)
		walking_away = true
	else:
		_enter(State.SHIELD, rest)


# Si el jugador está a la vista dispara; si no, sigue con lo suyo
func _check_attack() -> bool:
	if cooldown_left > 0.0:
		return false
	var target := _find_player()
	if target == null:
		return false
	var d := target.global_position - global_position
	if debug_log and Engine.get_physics_frames() % 30 == 0:
		print("Metalls ve al jugador a dx=", snappedf(d.x, 1.0), " dy=", snappedf(d.y, 1.0), "  (rango ", detect_range, " / altura ", detect_height, ")")
	if absf(d.x) > detect_range or absf(d.y) > detect_height:
		return false
	facing = 1 if d.x > 0.0 else -1  # se voltea hacia el jugador
	_enter(State.SHOT)
	return true


# Busca al jugador: primero por el grupo "Player", si no por el nombre "Prototipo"
func _find_player() -> Node2D:
	if is_instance_valid(player):
		return player
	player = get_tree().get_first_node_in_group("Player") as Node2D
	if player == null:
		player = get_tree().current_scene.find_child("Prototipo", true, false) as Node2D
	if player == null and not warned_no_player:
		warned_no_player = true
		push_warning("Metalls: no encuentro al jugador. Agrega Prototipo al grupo 'Player'.")
	return player


# Decide qué hacer cuando termina Idle o Move
func _decide_next() -> void:
	if cooldown_left <= 0.0 and randf() < random_shot_chance:
		_enter(State.SHOT)  # disparo aleatorio
	elif randf() < 0.5:
		_enter(State.MOVE)
	else:
		_enter(State.IDLE)


# ------------------------------------------------------------------- DISPARO

func _fire() -> void:
	if bullet_scene == null:
		push_warning("Asigna bullet_scene (ball.tscn) en el Inspector de Metalls.")
		return
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.setup(facing, self)


# --------------------------------------------------------------------- DAÑO

func take_damage(amount: int) -> void:
	if state == State.SHIELD:
		return  # protegido: no recibe daño
	hp -= amount
	_flash()
	if hp <= 0:
		queue_free()  # luego se le puede poner animación de muerte o explosión


func _flash() -> void:
	sprite.modulate = Color(1.0, 0.4, 0.4)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)


# ------------------------------------------------------------------- VISUAL

func _apply_facing() -> void:
	sprite.flip_h = (facing > 0) if sprite_faces_left else (facing < 0)
	muzzle.position.x = muzzle_offset_x * facing  # el Marker2D no se voltea solo


func _play(anim_name: StringName) -> void:
	if anim.assigned_animation == anim_name and anim.is_playing():
		return
	anim.play(anim_name)
