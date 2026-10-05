extends CharacterBody2D
## Personaje estilo Mega Man X.
## Requiere en la escena: Sprite2D, AnimationPlayer y un Marker2D llamado "Shoot".
## Los sprites deben mirar hacia la DERECHA (se voltean con flip_h al ir a la izquierda).

enum State { NORMAL, DASH, SLIDE }  # más adelante: HIT, DEAD

# Nombres de tus acciones del Mapa de entrada (cámbialos aquí si los renombras)
const IN_LEFT := &"Izq"
const IN_RIGHT := &"Drh"
const IN_DOWN := &"Down"
const IN_JUMP := &"Jump"
const IN_DASH := &"Dash"
const IN_SHOOT := &"Shot"

@export_group("Movimiento")
@export var run_speed := 150.0
@export var jump_velocity := -330.0
@export var gravity := 900.0
@export var max_fall_speed := 400.0
@export var jump_cut := 0.4            # al soltar el salto antes, recorta la subida
@export var dash_speed := 300.0
@export var dash_time := 0.4
@export var dash_jump_speed := 220.0   # velocidad en el aire si saltas durante el dash (el "impulso")
@export var slide_speed := 220.0
@export var slide_time := 0.5

@export_group("Disparo")
@export var bullet_scene: PackedScene  # arrastra aquí tu Shot.tscn
@export var shoot_cooldown := 1.0      # latencia entre disparos al espamear (seg)
@export var shoot_pose_time := 0.35    # cuánto dura la pose de disparo tras tirar (seg)
@export var charge_start_delay := 0.25 # tiempo presionado para entrar a modo carga
@export var charge_medium_time := 0.8  # tiempo presionado para nivel 2
@export var charge_max_time := 1.8     # tiempo presionado para nivel 3

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var muzzle: Marker2D = $Shoot

var state := State.NORMAL
var facing := 1
var move_dir := 0.0
var state_time_left := 0.0
var cooldown_left := 0.0
var pose_left := 0.0
var holding_shoot := false
var charge := 0.0
var muzzle_offset_x := 0.0
var air_boost := false  # true tras saltar desde un dash, hasta aterrizar o cambiar de dirección

# true cuando ya se mantuvo la tecla lo suficiente para considerarse "modo carga"
var charging: bool:
	get:
		return holding_shoot and charge >= charge_start_delay


func _ready() -> void:
	muzzle_offset_x = absf(muzzle.position.x)
	# Si el AnimationTree está activo, manda sobre el AnimationPlayer. Lo apagamos.
	var tree := get_node_or_null("AnimationTree") as AnimationTree
	if tree:
		tree.active = false


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	pose_left = maxf(pose_left - delta, 0.0)
	move_dir = Input.get_axis(IN_LEFT, IN_RIGHT)

	match state:
		State.NORMAL:
			_state_normal(delta)
		State.DASH:
			_state_burst(dash_speed, delta)
		State.SLIDE:
			_state_burst(slide_speed, delta)

	_apply_facing()
	_handle_shoot(delta)
	move_and_slide()
	_update_animation()


# ---------------------------------------------------------------- MOVIMIENTO

func _state_normal(delta: float) -> void:
	if is_on_floor():
		air_boost = false

	if move_dir != 0.0:
		var new_facing := 1 if move_dir > 0.0 else -1
		if new_facing != facing:
			air_boost = false  # cambiar de dirección cancela el impulso
		facing = new_facing

	if air_boost:
		velocity.x = facing * dash_jump_speed  # mantiene el impulso hacia adelante
	else:
		velocity.x = move_dir * run_speed
	_apply_gravity(delta)

	if is_on_floor():
		if Input.is_action_just_pressed(IN_JUMP):
			velocity.y = jump_velocity
		elif Input.is_action_just_pressed(IN_DASH):
			if Input.is_action_pressed(IN_DOWN):  # Abajo + Dash = Slide
				_start_state(State.SLIDE, slide_time)
			else:
				_start_state(State.DASH, dash_time)
	elif Input.is_action_just_released(IN_JUMP) and velocity.y < 0.0:
		velocity.y *= jump_cut


# Dash y Slide: avanzan hacia donde miras, solo desde el suelo
func _state_burst(speed: float, delta: float) -> void:
	velocity.x = facing * speed
	_apply_gravity(delta)
	state_time_left -= delta

	# Saltar durante el dash: sales del dash con un pequeño impulso hacia adelante
	if state == State.DASH and is_on_floor() and Input.is_action_just_pressed(IN_JUMP):
		velocity.y = jump_velocity
		air_boost = true
		state = State.NORMAL
		return

	if state_time_left <= 0.0 or not is_on_floor():
		state = State.NORMAL


func _start_state(new_state: State, duration: float) -> void:
	state = new_state
	state_time_left = duration


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _apply_facing() -> void:
	sprite.flip_h = facing < 0
	muzzle.position.x = muzzle_offset_x * facing  # el Marker2D no se voltea solo


# ------------------------------------------------------------------- DISPARO

func _handle_shoot(delta: float) -> void:
	# No hay animación de disparo en Dash/Slide, así que ahí no se dispara
	if state != State.NORMAL:
		holding_shoot = false
		charge = 0.0
		return

	if Input.is_action_just_pressed(IN_SHOOT):
		holding_shoot = true
		charge = 0.0
		if cooldown_left <= 0.0:
			_fire(1)  # disparo normal inmediato (respeta la latencia)

	if holding_shoot:
		charge += delta
		if Input.is_action_just_released(IN_SHOOT):
			if charge >= charge_max_time:
				_fire(3)
			elif charge >= charge_medium_time:
				_fire(2)
			holding_shoot = false
			charge = 0.0


func _fire(level: int) -> void:
	if bullet_scene == null:
		push_warning("Asigna bullet_scene (Shot.tscn) en el Inspector del personaje.")
		return
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.set_level(level, facing)  # tu función: reproduce "Shot_<nivel>"
	cooldown_left = shoot_cooldown
	pose_left = shoot_pose_time


# ---------------------------------------------------------------- ANIMACIONES

func _update_animation() -> void:
	var shooting := pose_left > 0.0 or charging
	var next: StringName

	match state:
		State.DASH:
			next = &"Dash"
		State.SLIDE:
			next = &"Slide"
		_:
			if not is_on_floor():
				if velocity.y < 0.0:
					next = &"Jump_shot" if shooting else &"Jump"
				else:
					next = &"Fall_shot" if shooting else &"Fall_1"
			elif move_dir != 0.0:
				next = &"Run_Shot" if shooting else &"Run"
			elif charging:
				next = &"Shot_Cargin"
			elif shooting:
				next = &"Shot"
			else:
				next = &"Idle"

	_play(next)


# Pares movimiento <-> disparo: al alternar entre ellos se conserva el punto de la animación,
# así no se reinicia ni se corta aunque espamees el disparo.
# (funciona mejor si las dos animaciones de un par duran lo mismo)
const SYNC_PAIRS := {
	&"Run": &"Run_Shot", &"Run_Shot": &"Run",
	&"Jump": &"Jump_shot", &"Jump_shot": &"Jump",
	&"Fall_1": &"Fall_shot", &"Fall_shot": &"Fall_1",
}


func _play(next: StringName) -> void:
	var current := anim.assigned_animation  # current_animation queda vacío al terminar una animación sin loop
	if current == next:
		return

	var keep_pos: bool = SYNC_PAIRS.get(StringName(current), &"") == next
	var pos := 0.0
	if keep_pos:
		if anim.is_playing():
			pos = anim.current_animation_position
		else:
			pos = anim.get_animation(current).length  # la anterior ya terminó: estaba en su último cuadro

	anim.play(next)
	if keep_pos:
		anim.seek(pos, true)
