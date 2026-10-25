extends CharacterBody2D
## Personaje X. Parte 1: igual que el Prototipo, con animaciones de inicio y cierre
## (Run_1 -> Run_2, Dash_End, Shot_end) y disparo también en dash y en pared.
## Parte 2: agacharse (Down), escaleras (Up_1/2/3), Giga ataques, Exit, Win, Star,
## Shoryuken e Idle_Dmg. (Grip queda pendiente hasta tener el bloque.)
## Requiere en la escena: Sprite2D, AnimationPlayer y un Marker2D llamado "Shoot".
## Opcional: la escena del efecto de carga como hijo llamado "Carga", y Vida.tscn como hijo.
## Los sprites miran hacia la DERECHA (se voltean con flip_h al ir a la izquierda),
## excepto Wall_Slide y Wall_Shot_Slide, que se dibujaron mirando a la IZQUIERDA
## (ver wall_slide_sprite_faces_left).

enum State { NORMAL, DASH, WALL_SLIDE, HIT, DEAD, LADDER, LADDER_TOP, GIGA, SHORYUKEN, EXIT, WIN, STAR }

signal health_changed(hp: int, max_hp: int)  # el HUD de vida se conecta a esta señal
signal died

# Nombres de tus acciones del Mapa de entrada (cámbialos aquí si los renombras)
const IN_LEFT := &"Izq"
const IN_RIGHT := &"Drh"
const IN_JUMP := &"Jump"
const IN_DASH := &"Dash"
const IN_SHOOT := &"Shot"
const IN_UP := &"Up"
const IN_DOWN := &"Down"
# Acciones nuevas de la Parte 2: créalas en Proyecto > Configuración del proyecto > Mapa de entrada
const IN_GIGA_Z := &"Giga_Z"        # tecla Z
const IN_GIGA_X := &"Giga_X"        # tecla X
const IN_EXIT := &"Exit"            # flecha derecha
const IN_WIN := &"Win"              # flecha izquierda
const IN_SHORYUKEN := &"Shoryuken"  # flecha abajo

# Nombres de las capas de datos personalizados del TileSet (tipo bool) que marcan la escalera
const LADDER_DATA := "Escalera"     # true en los dos tiles de la escalera
const LADDER_TOP_DATA := "Tope"     # true solo en el tile de arriba (el que se pisa)

# Pares movimiento <-> disparo: al alternar entre ellos se conserva el punto de la animación,
# así no se reinicia ni se corta aunque espamees el disparo.
# (funciona mejor si las dos animaciones de un par duran lo mismo)
const SYNC_PAIRS := {
	&"Run_1": &"Run_Shot_1", &"Run_Shot_1": &"Run_1",
	&"Run_2": &"Run_Shot_2", &"Run_Shot_2": &"Run_2",
	&"Jump": &"Jump_Shot", &"Jump_Shot": &"Jump",
	&"Fall": &"Fall_Shot", &"Fall_Shot": &"Fall",
	&"Dash": &"Dash_Shot", &"Dash_Shot": &"Dash",
	&"Dash_End": &"Dash_Shot_End", &"Dash_Shot_End": &"Dash_End",
	&"Wall_Slide": &"Wall_Shot_Slide", &"Wall_Shot_Slide": &"Wall_Slide",
	&"Wall_Jump": &"Wall_Shot_Jump", &"Wall_Shot_Jump": &"Wall_Jump",
	&"Down": &"Down_Shot", &"Down_Shot": &"Down",
}

# Animaciones de cierre: qué se reproduce una vez al terminar la animación de la izquierda
# (si estás quieto en el suelo). Shot -> Shot_end se maneja aparte, porque espera a que termine la pose.
const TAILS := {
	&"Dash": &"Dash_End",
	&"Dash_Shot": &"Dash_Shot_End",
	&"Shot_Cargin": &"Shot_end",
}

# El loop de cada animación se pone desde el código: no importa cómo estén en el editor
const LOOPING := [&"Idle", &"Idle_Dmg", &"Run_2", &"Run_Shot_2", &"Shot_Cargin", &"Up_2"]
const ONE_SHOT := [
	&"Run_1", &"Run_Shot_1", &"Dash", &"Dash_End", &"Dash_Shot", &"Dash_Shot_End",
	&"Shot", &"Shot_end", &"Jump", &"Jump_Shot", &"Fall", &"Fall_Shot",
	&"Wall_Slide", &"Wall_Shot_Slide", &"Wall_Jump", &"Wall_Shot_Jump", &"Damage",
	&"Down", &"Down_Shot", &"Up_1", &"Up_3", &"Giga_Atk_1", &"Giga_Atk_2", &"Giga_Atk_3",
	&"Shoryuken", &"Shoryuken_End", &"Exit", &"Win", &"Star",
]

@export_group("Movimiento")
@export var run_speed := 150.0
@export var jump_velocity := -330.0
@export var gravity := 900.0
@export var max_fall_speed := 400.0
@export var jump_cut := 0.4              # al soltar el salto antes, recorta la subida
@export var dash_speed := 300.0
@export var dash_start_speed := 450.0    # empuje inicial del dash
@export var dash_burst_time := 0.15      # tiempo que tarda el empuje en bajar a dash_speed
@export var dash_time := 0.4
@export var dash_jump_speed := 220.0     # velocidad en el aire si saltas durante el dash (el "impulso")

@export_group("Pared")
@export var wall_slide_speed := 60.0         # velocidad de caída al deslizarte
@export var wall_jump_velocity := -330.0     # fuerza vertical del wall jump
@export var wall_jump_push := 200.0          # empuje horizontal, lejos de la pared
@export var wall_jump_lock_time := 0.15      # tiempo sin control horizontal tras el wall jump
@export var wall_slide_sprite_faces_left := true  # Wall_Slide y Wall_Shot_Slide se dibujaron mirando a la izquierda

@export_group("Disparo")
@export var bullet_scene: PackedScene  # arrastra aquí tu Shot.tscn
@export var shoot_cooldown := 1.0      # latencia entre disparos al espamear (seg)
@export var shoot_pose_time := 0.35    # cuánto dura la pose de disparo tras tirar (seg); después sale Shot_end
@export var charge_start_delay := 0.25 # tiempo presionado para entrar a modo carga
@export var charge_medium_time := 0.8  # tiempo presionado para nivel 2
@export var charge_max_time := 1.8     # tiempo presionado para nivel 3

@export_group("Vida")
@export var max_hp_start := 25         # vida máxima con la que empieza
@export var max_hp_limit := 100        # límite al que puede expandirse con items
@export var hit_knockback := 80.0      # retroceso al recibir daño (0 = sin retroceso)
@export var invincible_time := 1.0     # invulnerabilidad tras recibir daño (parpadea)
@export var hit_anim := &"Damage"
@export var dead_anim := &"Damage"     # X todavía no tiene animación de muerte: se queda en Damage
@export var restart_delay := 1.5       # segundos tras morir antes de reiniciar el nivel (negativo = no reinicia)

@export_group("Efecto de carga")
@export var charge_fx: Node2D            # nodo del efecto (si se llama "Carga" lo encuentra solo)
@export var charge_anim_1 := &"Carga-1"  # se ve del nivel 2 hasta antes del nivel 3
@export var charge_anim_2 := &"Carga-2"  # se ve en el nivel 3 (sustituye al 1)

@export_group("Estela (dash)")
@export var trail_enabled := true
@export var trail_interval := 0.04       # cada cuánto deja una copia (seg)
@export var trail_fade_time := 0.25      # cuánto tarda cada copia en desaparecer (seg)
@export var trail_color := Color(0.5, 0.8, 1.0, 0.6)  # color y transparencia de las copias

@export_group("Agacharse")
@export var crouch_shape_shrink := 0.0   # px que se achica la caja de colisión al agacharse (0 = no cambia)

@export_group("Escalera")
@export var ladder_speed := 90.0         # velocidad al subir y bajar
@export var ladder_descend_nudge := 4.0  # px que se hunde para atravesar el tile de arriba al bajar desde el tope
@export var ladder_can_shoot := false    # true = permite disparar en la escalera (sin animación propia)

@export_group("Giga ataques")
@export var giga_air_hover := true       # true = en Giga_Atk_2 se queda flotando mientras dura la animación

@export_group("Shoryuken")
@export var shoryuken_jump := -380.0     # impulso vertical al activarlo
@export var shoryuken_push := 80.0       # empuje horizontal hacia donde mira
@export var shoryuken_damage := 8        # daño de su hitbox (nodo ShoryukenHitbox)

@export_group("Star, Exit y Win")
@export var star_on_start := true        # al empezar el nivel cae y hace la animación Star
@export var star_spawn_height := 0.0     # px que sube al empezar para que la caída se note (0 = donde lo pusiste)
@export var star_fall_anim := &""        # animación mientras cae (vacío = se queda en el primer cuadro de Star)
@export var exit_rise_speed := 400.0     # velocidad con la que sube en Exit
@export var exit_rise_time := 5.0        # segundos que sube antes de reiniciar el nivel
@export var win_restart_delay := 5.0     # segundos desde que presionas Win hasta reiniciar el nivel

@export_group("Vida baja")
@export var low_hp_ratio := 0.3          # con esta fracción de vida o menos usa Idle_Dmg en vez de Idle

@export_group("Depuración")
@export var debug_log := false           # imprime la vida en Salida cada vez que cambia
@export var debug_anim := false          # imprime en Salida cada cambio de animación

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var muzzle: Marker2D = $Shoot

var state := State.NORMAL
var facing := 1
var move_dir := 0.0
var state_time_left := 0.0
var cooldown_left := 0.0
var pose_left := 0.0
var just_fired := false     # true el frame en que sale un disparo
var holding_shoot := false
var charge := 0.0
var air_boost := false      # true tras saltar desde un dash, hasta aterrizar o cambiar de dirección
var wall_dir := 0           # lado de la pared: 1 = derecha, -1 = izquierda
var wall_lock_left := 0.0
var wall_jump_active := false  # true desde un wall jump hasta que empiezas a caer
var run_phase := 1          # 1 = Run_1 (arranque), 2 = Run_2 (ciclo)
var tail_anim: StringName = &""  # animación de cierre en curso (Dash_End, Shot_end...)
var missing_warned := {}
var charge_fx_player: AnimationPlayer
var charge_fx_current: StringName = &""
var trail_timer := 0.0
var max_hp := 25
var hp := 25
var invincible_left := 0.0

# --- Parte 2
var crouching := false
var body_shape: CollisionShape2D
var stand_rect := Rect2(-8.0, -24.0, 16.0, 48.0)  # caja de colisión de pie, relativa al origen
var stand_pos := Vector2.ZERO
var stand_height := 48.0
var crouch_shape_applied := false
var ladder_layers: Array[TileMapLayer] = []
var ladder_searched := false
var ladder_lock_left := 0.0
var ladder_time := 0.0
var ladder_dir_y := 0.0
var ladder_intro := false
var ladder_intro_len := 0.0
var giga_anim: StringName = &""
var giga_in_air := false
var shoryuken_phase := 0     # 0 = Shoryuken (con daño), 1 = Shoryuken_End
var shoryuken_active := false
var shoryuken_hitbox: Area2D
var shoryuken_hit_bodies: Array = []
var exit_phase := 0          # 0 = animación Exit, 1 = subiendo
var star_landed := false
var restart_pending := false

# true cuando ya se mantuvo la tecla lo suficiente para considerarse "modo carga"
var charging: bool:
	get:
		return holding_shoot and charge >= charge_start_delay


func _ready() -> void:
	add_to_group("Player")  # Metalls, las balas y el HUD reconocen al jugador por este grupo
	# Si el AnimationTree está activo, manda sobre el AnimationPlayer. Lo apagamos.
	var tree := get_node_or_null("AnimationTree") as AnimationTree
	if tree:
		tree.active = false
	_setup_loops()
	_setup_charge_fx()
	_setup_body_shape()
	_setup_shoryuken()
	max_hp = clampi(max_hp_start, 1, max_hp_limit)
	hp = max_hp
	_emit_health.call_deferred()  # diferido: así el HUD ya está conectado
	_setup_star()


func _setup_loops() -> void:
	for n in LOOPING:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ONE_SHOT:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_NONE


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	pose_left = maxf(pose_left - delta, 0.0)
	wall_lock_left = maxf(wall_lock_left - delta, 0.0)
	invincible_left = maxf(invincible_left - delta, 0.0)
	ladder_lock_left = maxf(ladder_lock_left - delta, 0.0)
	move_dir = Input.get_axis(IN_LEFT, IN_RIGHT)

	match state:
		State.NORMAL:
			_state_normal(delta)
		State.DASH:
			_state_dash(delta)
		State.WALL_SLIDE:
			_state_wall_slide(delta)
		State.HIT:
			_state_hit(delta)
		State.DEAD:
			_state_dead(delta)
		State.LADDER:
			_state_ladder(delta)
		State.LADDER_TOP:
			_state_ladder_top(delta)
		State.GIGA:
			_state_giga(delta)
		State.SHORYUKEN:
			_state_shoryuken(delta)
		State.EXIT:
			_state_exit(delta)
		State.WIN:
			_state_win(delta)
		State.STAR:
			_state_star(delta)

	if state != State.NORMAL:
		crouching = false
	_apply_crouch_shape(crouching)
	_apply_facing()
	_handle_shoot(delta)
	_update_charge_fx()
	move_and_slide()
	_after_move()
	_update_animation()
	_update_trail(delta)
	_update_blink()


# ---------------------------------------------------------------- MOVIMIENTO

func _state_normal(delta: float) -> void:
	if is_on_floor():
		air_boost = false

	# Acciones especiales (Exit, Win, Giga, Shoryuken, escalera): cambian de estado y salen
	if _try_special_actions():
		return

	# Agacharse: solo quieto en el suelo y con Down presionado
	var want_crouch := is_on_floor() and Input.is_action_pressed(IN_DOWN) and move_dir == 0.0
	if crouching and not want_crouch and is_on_floor() and not _can_stand():
		want_crouch = true  # hay techo encima: sigue agachado hasta que haya espacio
	crouching = want_crouch

	if wall_lock_left > 0.0:
		# Tras un wall jump: empuje fijo lejos de la pared, sin control horizontal
		velocity.x = facing * wall_jump_push
	else:
		if move_dir != 0.0:
			var new_facing := 1 if move_dir > 0.0 else -1
			if new_facing != facing:
				air_boost = false  # cambiar de dirección cancela el impulso
			facing = new_facing

		if air_boost:
			velocity.x = facing * dash_jump_speed  # mantiene el impulso hacia adelante
		else:
			velocity.x = move_dir * run_speed
	if crouching:
		velocity.x = 0.0
	_apply_gravity(delta)

	if is_on_floor():
		if Input.is_action_just_pressed(IN_JUMP):
			velocity.y = jump_velocity
		elif Input.is_action_just_pressed(IN_DASH):
			_start_state(State.DASH, dash_time)
	elif Input.is_action_just_released(IN_JUMP) and velocity.y < 0.0:
		velocity.y *= jump_cut

	_try_wall_slide()


# Empieza el wall slide: en el aire, cayendo, tocando pared y presionando hacia ella
func _try_wall_slide() -> void:
	if wall_lock_left > 0.0 or is_on_floor() or not is_on_wall():
		return
	if velocity.y <= 0.0 or move_dir == 0.0:
		return
	var toward_wall := -signf(get_wall_normal().x)  # normal apunta lejos de la pared
	if signf(move_dir) != toward_wall:
		return
	wall_dir = int(toward_wall)
	facing = -wall_dir  # mira hacia el lado contrario a la pared
	air_boost = false
	wall_jump_active = false
	state = State.WALL_SLIDE


func _state_wall_slide(delta: float) -> void:
	var pressing_wall := signf(move_dir) == float(wall_dir)
	if is_on_floor() or not is_on_wall() or not pressing_wall:
		velocity.x = 0.0
		state = State.NORMAL
		return

	# Wall jump: saltas hacia donde miras (lejos de la pared)
	if Input.is_action_just_pressed(IN_JUMP):
		facing = -wall_dir
		velocity = Vector2(facing * wall_jump_push, wall_jump_velocity)
		wall_lock_left = wall_jump_lock_time
		wall_jump_active = true  # mientras sube se ve Wall_Jump
		state = State.NORMAL
		return

	facing = -wall_dir
	velocity.x = wall_dir * 20.0  # empuja un poco hacia la pared para seguir pegado
	velocity.y = minf(velocity.y + gravity * delta, wall_slide_speed)


# Empuje inicial del dash: arranca en dash_start_speed y baja a dash_speed
func _dash_speed_now() -> float:
	var elapsed := dash_time - state_time_left
	var t := clampf(elapsed / dash_burst_time, 0.0, 1.0)
	return lerpf(dash_start_speed, dash_speed, t)


# Dash: avanza hacia donde miras, solo desde el suelo
func _state_dash(delta: float) -> void:
	velocity.x = facing * _dash_speed_now()
	_apply_gravity(delta)
	state_time_left -= delta

	# Saltar durante el dash: sales del dash con un pequeño impulso hacia adelante
	if is_on_floor() and Input.is_action_just_pressed(IN_JUMP):
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
	var drawn_left := state == State.WALL_SLIDE and wall_slide_sprite_faces_left
	sprite.flip_h = (facing > 0) if drawn_left else (facing < 0)
	# El Marker2D no se voltea solo. Se usa su |x|, así puedes animar su posición mirando a la derecha
	muzzle.position.x = absf(muzzle.position.x) * facing


# ------------------------------------------------- PARTE 2: ACCIONES ESPECIALES

# Acciones del Mapa de entrada: si todavía no las creaste, avisa una vez en vez de llenar la Salida de errores
func _has_action(action: StringName) -> bool:
	if InputMap.has_action(action):
		return true
	if not missing_warned.has(action):
		missing_warned[action] = true
		push_warning("X: falta la acción '%s' en el Mapa de entrada (Proyecto > Configuración del proyecto)." % str(action))
	return false


func _just(action: StringName) -> bool:
	return _has_action(action) and Input.is_action_just_pressed(action)


func _held(action: StringName) -> bool:
	return _has_action(action) and Input.is_action_pressed(action)


# Si falta la animación avisa una vez y devuelve false
func _need_anim(anim_name: StringName) -> bool:
	if anim.has_animation(anim_name):
		return true
	if not missing_warned.has(anim_name):
		missing_warned[anim_name] = true
		push_warning("X: no existe la animación '%s' en el AnimationPlayer (revisa que se llame igual, con las mismas mayúsculas)." % str(anim_name))
	return false


func _anim_len(anim_name: StringName, fallback: float) -> float:
	if anim.has_animation(anim_name):
		return maxf(anim.get_animation(anim_name).length, 0.05)
	return fallback


# Limpia lo que no debe seguir activo al empezar una acción especial
func _reset_actions() -> void:
	holding_shoot = false
	charge = 0.0
	pose_left = 0.0
	air_boost = false
	wall_jump_active = false
	wall_lock_left = 0.0
	crouching = false
	tail_anim = &""


func _shoot_blocked() -> bool:
	match state:
		State.HIT, State.DEAD, State.LADDER_TOP, State.GIGA, State.SHORYUKEN, State.EXIT, State.WIN, State.STAR:
			return true
		State.LADDER:
			return not ladder_can_shoot
	return false


func _is_low_hp() -> bool:
	return hp > 0 and max_hp > 0 and float(hp) / float(max_hp) <= low_hp_ratio


# Se llama desde el estado NORMAL. Devuelve true si empezó una acción (y por eso se sale del frame normal)
func _try_special_actions() -> bool:
	if wall_lock_left > 0.0:
		return false
	if _just(IN_EXIT):
		return _start_exit()
	if _just(IN_WIN):
		return _start_win()
	if _just(IN_GIGA_Z):
		if is_on_floor():
			return _start_giga(&"Giga_Atk_1", false)
		return _start_giga(&"Giga_Atk_2", true)
	if _just(IN_GIGA_X) and is_on_floor():
		return _start_giga(&"Giga_Atk_3", false)
	if is_on_floor() and _just(IN_SHORYUKEN):
		return _start_shoryuken()
	return _try_start_ladder()


# Se llama después de move_and_slide(): cosas que dependen de dónde terminó el cuerpo
func _after_move() -> void:
	match state:
		State.LADDER:
			_ladder_after_move()
		State.STAR:
			if not star_landed and is_on_floor():
				star_landed = true  # tocó el suelo: ahora sí hace la animación
				state_time_left = _anim_len(&"Star", 0.5)
				anim.stop()
				anim.play(&"Star")


func _restart_once() -> void:
	if restart_pending:
		return
	restart_pending = true
	_restart_level()


# ------------------------------------------------------------------ AGACHARSE

# Busca la CollisionShape2D del cuerpo y calcula su caja de pie (la usan la escalera y el agacharse)
func _setup_body_shape() -> void:
	for child in get_children():
		var cs := child as CollisionShape2D
		if cs != null and cs.shape != null:
			body_shape = cs
			break
	if body_shape == null:
		return
	body_shape.shape = body_shape.shape.duplicate()  # evita tocar el recurso compartido con otras copias
	stand_pos = body_shape.position
	var half := Vector2(8.0, 24.0)
	var rect := body_shape.shape as RectangleShape2D
	var cap := body_shape.shape as CapsuleShape2D
	var circ := body_shape.shape as CircleShape2D
	if rect != null:
		half = rect.size * 0.5
		stand_height = rect.size.y
	elif cap != null:
		half = Vector2(cap.radius, cap.height * 0.5)
		stand_height = cap.height
	elif circ != null:
		half = Vector2(circ.radius, circ.radius)
		stand_height = circ.radius * 2.0
	stand_rect = Rect2(stand_pos - half, half * 2.0)


# Achica la caja de colisión al agacharse (si crouch_shape_shrink > 0). Los pies no se mueven.
func _apply_crouch_shape(crouch: bool) -> void:
	if body_shape == null or crouch_shape_shrink <= 0.0 or crouch == crouch_shape_applied:
		return
	var shrink := crouch_shape_shrink if crouch else 0.0
	var new_height := maxf(stand_height - shrink, 4.0)
	var rect := body_shape.shape as RectangleShape2D
	var cap := body_shape.shape as CapsuleShape2D
	if rect != null:
		rect.size.y = new_height
	elif cap != null:
		cap.height = new_height
	else:
		return
	body_shape.position.y = stand_pos.y + (stand_height - new_height) * 0.5
	crouch_shape_applied = crouch


# ¿Hay espacio para ponerse de pie? (solo importa si se achica la caja al agacharse)
func _can_stand() -> bool:
	if crouch_shape_shrink <= 0.0 or not crouch_shape_applied:
		return true
	return not test_move(global_transform, Vector2(0.0, -crouch_shape_shrink))


# ------------------------------------------------------------------ ESCALERAS

func _body_cx() -> float:
	return global_position.x + stand_rect.get_center().x


func _feet_y() -> float:
	return global_position.y + stand_rect.end.y


# Busca las capas de tiles que tienen la capa de datos "Escalera"
func _find_ladder_layers() -> void:
	ladder_searched = true
	ladder_layers.clear()
	var root := get_tree().current_scene
	if root == null:
		return
	for node in root.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer != null and layer.tile_set != null:
			if layer.tile_set.get_custom_data_layer_by_name(LADDER_DATA) >= 0:
				ladder_layers.append(layer)


# ¿Qué hay en este punto del mundo? kind: 0 = nada, 1 = escalera, 2 = tope de la escalera
func _ladder_at(world_pos: Vector2) -> Dictionary:
	for layer in ladder_layers:
		if not is_instance_valid(layer):
			continue
		var cell := layer.local_to_map(layer.to_local(world_pos))
		var data := layer.get_cell_tile_data(cell)
		if data == null or not bool(data.get_custom_data(LADDER_DATA)):
			continue
		var ts := layer.tile_set
		var is_top := false
		if ts.get_custom_data_layer_by_name(LADDER_TOP_DATA) >= 0:
			is_top = bool(data.get_custom_data(LADDER_TOP_DATA))
		var center := layer.to_global(layer.map_to_local(cell))
		return {
			"kind": 2 if is_top else 1,
			"center_x": center.x,
			"top_y": center.y - ts.tile_size.y * 0.5 * absf(layer.global_scale.y),
		}
	return {"kind": 0}


# Revisa varios puntos del cuerpo; devuelve el primer tile de escalera que toca
func _ladder_probe_body(include_below := false) -> Dictionary:
	var cx := _body_cx()
	var feet := _feet_y()
	var head := global_position.y + stand_rect.position.y
	var points: Array[float] = [feet - 4.0, (feet + head) * 0.5, head + 4.0]
	if include_below:
		points.append(feet + 2.0)
	for y in points:
		var info := _ladder_at(Vector2(cx, y))
		if info["kind"] != 0:
			return info
	return {"kind": 0}


# Up junto a una escalera: se agarra y sube. Down parado sobre el tope: se agarra y baja.
func _try_start_ladder() -> bool:
	if ladder_lock_left > 0.0:
		return false
	var up := _held(IN_UP)
	var down := Input.is_action_pressed(IN_DOWN)
	if not up and not down:
		return false
	if not ladder_searched:
		_find_ladder_layers()
	if ladder_layers.is_empty():
		if up and not missing_warned.has(&"ladder_layers"):
			missing_warned[&"ladder_layers"] = true
			push_warning("X: no encuentro tiles de escalera. En el TileSet agrega las capas de datos personalizados 'Escalera' y 'Tope' (bool) y márcalas en los tiles de la escalera.")
		return false
	if up:
		var info := _ladder_probe_body()
		if info["kind"] != 0 and _need_anim(&"Up_2"):
			_start_ladder(info, false)
			return true
	if down and is_on_floor():
		var below := _ladder_at(Vector2(_body_cx(), _feet_y() + 2.0))
		if below["kind"] == 2 and _need_anim(&"Up_2"):
			_start_ladder(below, true)
			return true
	return false


func _start_ladder(info: Dictionary, from_top: bool) -> void:
	_reset_actions()
	state = State.LADDER
	velocity = Vector2.ZERO
	global_position.x = float(info["center_x"]) - stand_rect.get_center().x  # se centra en la escalera
	if from_top:
		global_position.y += ladder_descend_nudge  # se hunde un poco para atravesar el tile de arriba
	ladder_time = 0.0
	ladder_dir_y = 0.0
	ladder_intro = anim.has_animation(&"Up_1")
	ladder_intro_len = _anim_len(&"Up_1", 0.0)


func _state_ladder(delta: float) -> void:
	ladder_time += delta
	if ladder_intro and ladder_time >= ladder_intro_len:
		ladder_intro = false  # terminó Up_1: ya puede moverse con Up_2
	ladder_dir_y = 0.0
	if _held(IN_UP):
		ladder_dir_y -= 1.0
	if Input.is_action_pressed(IN_DOWN):
		ladder_dir_y += 1.0
	if ladder_intro:
		ladder_dir_y = 0.0
	velocity = Vector2(0.0, ladder_dir_y * ladder_speed)
	if Input.is_action_just_pressed(IN_JUMP):
		_leave_ladder(move_dir != 0.0)  # salta si presionas una dirección; si no, solo se suelta


func _leave_ladder(jump: bool) -> void:
	state = State.NORMAL
	ladder_lock_left = 0.25  # evita volver a agarrarse al instante
	velocity = Vector2.ZERO
	if jump and move_dir != 0.0:
		facing = 1 if move_dir > 0.0 else -1
		velocity = Vector2(facing * run_speed, jump_velocity)


# Después de moverse: ¿llegó arriba, tocó el suelo o se acabó la escalera?
func _ladder_after_move() -> void:
	if ladder_time < 0.1:
		return
	if ladder_dir_y > 0.0 and is_on_floor():
		_leave_ladder(false)  # bajó hasta el suelo
		return
	if ladder_dir_y < 0.0:
		var cx := _body_cx()
		var feet := _feet_y()
		if _ladder_at(Vector2(cx, feet - 1.0))["kind"] == 0:
			var under := _ladder_at(Vector2(cx, feet + 3.0))
			if under["kind"] != 0:
				_start_ladder_top(under)  # llegó al tope
				return
	if _ladder_probe_body(true)["kind"] == 0:
		_leave_ladder(false)  # se acabó la escalera


# Llegó arriba: se coloca sobre el tile del tope y hace Up_3
func _start_ladder_top(info: Dictionary) -> void:
	state = State.LADDER_TOP
	global_position.y = float(info["top_y"]) - stand_rect.end.y
	velocity = Vector2.ZERO
	state_time_left = _anim_len(&"Up_3", 0.0)
	ladder_lock_left = 0.4


func _state_ladder_top(delta: float) -> void:
	velocity = Vector2(0.0, 20.0)  # una presión leve hacia abajo mantiene el contacto con el suelo
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


# ------------------------------------------------------------- GIGA ATAQUES

# Por ahora solo hacen la animación (el efecto y el daño se agregan después)
func _start_giga(anim_name: StringName, in_air: bool) -> bool:
	if not _need_anim(anim_name):
		return false
	_reset_actions()
	giga_anim = anim_name
	giga_in_air = in_air
	state = State.GIGA
	state_time_left = _anim_len(anim_name, 0.5)
	velocity.x = 0.0
	if in_air and giga_air_hover:
		velocity.y = 0.0
	return true


func _state_giga(delta: float) -> void:
	velocity.x = 0.0
	if giga_in_air and giga_air_hover:
		velocity.y = 0.0
	else:
		_apply_gravity(delta)
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


# ---------------------------------------------------------------- SHORYUKEN

func _setup_shoryuken() -> void:
	shoryuken_hitbox = get_node_or_null("ShoryukenHitbox") as Area2D
	if shoryuken_hitbox != null:
		shoryuken_hitbox.monitoring = false


func _start_shoryuken() -> bool:
	if not _need_anim(&"Shoryuken"):
		return false
	if shoryuken_hitbox == null and not missing_warned.has(&"ShoryukenHitbox"):
		missing_warned[&"ShoryukenHitbox"] = true
		push_warning("X: no encuentro el nodo 'ShoryukenHitbox' (Area2D hijo de X). El Shoryuken se mueve pero no hace daño.")
	_reset_actions()
	state = State.SHORYUKEN
	shoryuken_phase = 0
	state_time_left = _anim_len(&"Shoryuken", 0.4)
	velocity = Vector2(facing * shoryuken_push, shoryuken_jump)
	shoryuken_hit_bodies.clear()
	_set_shoryuken_hitbox(true)
	return true


func _state_shoryuken(delta: float) -> void:
	_apply_gravity(delta)
	state_time_left -= delta
	if shoryuken_phase == 0:
		velocity.x = facing * shoryuken_push
		_shoryuken_damage()
		if state_time_left <= 0.0:
			shoryuken_phase = 1  # empieza Shoryuken_End: ya no hace daño
			state_time_left = _anim_len(&"Shoryuken_End", 0.0)
			_set_shoryuken_hitbox(false)
	else:
		velocity.x = move_toward(velocity.x, 0.0, shoryuken_push * 6.0 * delta)
		if state_time_left <= 0.0:
			state = State.NORMAL


# Enciende o apaga el daño del nodo ShoryukenHitbox (se mira hacia donde mira X)
func _set_shoryuken_hitbox(active: bool) -> void:
	shoryuken_active = active
	if shoryuken_hitbox == null:
		return
	if active:
		shoryuken_hitbox.scale.x = float(facing)
	shoryuken_hitbox.set_deferred("monitoring", active)


func _shoryuken_damage() -> void:
	if shoryuken_hitbox == null or not shoryuken_active:
		return
	for body in shoryuken_hitbox.get_overlapping_bodies():
		if body == self or shoryuken_hit_bodies.has(body):
			continue
		if body.has_method("take_damage"):
			shoryuken_hit_bodies.append(body)  # cada enemigo recibe el golpe una sola vez
			body.take_damage(shoryuken_damage)


# ------------------------------------------------------- EXIT, WIN Y STAR

func _start_exit() -> bool:
	if not _need_anim(&"Exit"):
		return false
	_reset_actions()
	state = State.EXIT
	exit_phase = 0
	state_time_left = _anim_len(&"Exit", 0.5)
	velocity.x = 0.0
	return true


func _state_exit(delta: float) -> void:
	if exit_phase == 0:
		velocity.x = 0.0
		_apply_gravity(delta)
		state_time_left -= delta
		if state_time_left <= 0.0:
			exit_phase = 1  # terminó la animación: sube
			state_time_left = exit_rise_time
			collision_layer = 0  # atraviesa techos y enemigos
			collision_mask = 0
		return
	velocity = Vector2(0.0, -exit_rise_speed)
	state_time_left -= delta
	if state_time_left <= 0.0:
		_restart_once()


func _start_win() -> bool:
	if not _need_anim(&"Win"):
		return false
	_reset_actions()
	state = State.WIN
	state_time_left = win_restart_delay
	velocity.x = 0.0
	return true


func _state_win(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	state_time_left -= delta
	if state_time_left <= 0.0:
		_restart_once()


# Al empezar el nivel: cae y, al tocar el suelo, hace Star (sin moverse ni disparar hasta que termine)
func _setup_star() -> void:
	if not star_on_start or not _need_anim(&"Star"):
		return
	global_position.y -= star_spawn_height
	star_landed = false
	velocity = Vector2.ZERO
	state = State.STAR


func _state_star(delta: float) -> void:
	velocity.x = 0.0
	if not star_landed:
		_apply_gravity(delta)
		return
	velocity.y = 0.0
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


# ------------------------------------------------------------------- DISPARO

func _handle_shoot(delta: float) -> void:
	# Se puede disparar y cargar en casi cualquier estado; no al recibir daño, morir o en acciones especiales
	if _shoot_blocked():
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
	just_fired = true


# ---------------------------------------------------------------- ANIMACIONES

func _update_animation() -> void:
	var cur := anim.assigned_animation  # lo que se estaba mostrando hasta ahora

	# Animaciones de una sola vez que ya terminaron: pasan a la siguiente fase
	if not anim.is_playing():
		if tail_anim != &"" and cur == tail_anim:
			tail_anim = &""
		if cur == &"Run_1" or cur == &"Run_Shot_1":
			run_phase = 2

	var shooting := pose_left > 0.0 or charging
	var on_floor := is_on_floor()
	var running := state == State.NORMAL and on_floor and not crouching and move_dir != 0.0
	var idle_like := state == State.NORMAL and on_floor and not crouching and move_dir == 0.0 and not charging

	if not running:
		run_phase = 1  # al volver a correr empieza otra vez con Run_1
	if not idle_like:
		tail_anim = &""  # cualquier otra acción corta la animación de cierre
	if wall_jump_active and (on_floor or velocity.y >= 0.0 or state != State.NORMAL):
		wall_jump_active = false

	var next: StringName
	match state:
		State.DASH:
			next = &"Dash_Shot" if shooting else &"Dash"
		State.WALL_SLIDE:
			next = &"Wall_Shot_Slide" if shooting else &"Wall_Slide"
		State.HIT:
			next = hit_anim
		State.DEAD:
			next = dead_anim
		State.LADDER:
			next = &"Up_1" if ladder_intro else &"Up_2"
		State.LADDER_TOP:
			next = &"Up_3"
		State.GIGA:
			next = giga_anim
		State.SHORYUKEN:
			next = &"Shoryuken" if shoryuken_phase == 0 else &"Shoryuken_End"
		State.EXIT:
			next = &"Exit"
		State.WIN:
			next = &"Win"
		State.STAR:
			next = &"Star" if (star_landed or star_fall_anim == &"") else star_fall_anim
		_:
			if crouching and on_floor:
				next = &"Down_Shot" if shooting else &"Down"
			elif not on_floor:
				if wall_jump_active:
					next = &"Wall_Shot_Jump" if shooting else &"Wall_Jump"
				elif velocity.y < 0.0:
					next = &"Jump_Shot" if shooting else &"Jump"
				else:
					next = &"Fall_Shot" if shooting else &"Fall"
			elif running:
				next = StringName(("Run_Shot_" if shooting else "Run_") + str(run_phase))
			else:
				next = _standing_animation(cur, shooting)

	just_fired = false
	_play(next)
	_after_play()


# Ajustes justo después de elegir la animación: pausa en la escalera y en la caída de Star
func _after_play() -> void:
	if state == State.LADDER and not ladder_intro and anim.assigned_animation == &"Up_2":
		if ladder_dir_y == 0.0:
			if anim.is_playing():
				anim.pause()  # quieto en la escalera: se congela el cuadro
		elif not anim.is_playing():
			anim.play(&"Up_2")  # se mueve otra vez: continúa donde se quedó
	elif state == State.STAR and not star_landed and star_fall_anim == &"" and anim.assigned_animation == &"Star":
		if anim.is_playing():
			anim.pause()
			anim.seek(0.0, true)  # mientras cae se queda en el primer cuadro


# Quieto en el suelo: cargando, pose de disparo, animación de cierre (Shot_end, Dash_End...) o Idle
func _standing_animation(prev: StringName, shooting: bool) -> StringName:
	if charging:
		return &"Shot_Cargin" if anim.has_animation(&"Shot_Cargin") else &"Shot"
	if just_fired:
		tail_anim = &""  # un disparo nuevo corta el cierre
		if prev == &"Shot" and not anim.is_playing():
			anim.play(&"Shot")  # la pose anterior ya terminó: se repite para el nuevo disparo
		return &"Shot"
	if prev == &"Shot" and not shooting and anim.is_playing():
		return &"Shot"  # deja terminar la pose antes de pasar a Shot_end
	if tail_anim == &"":
		var t: StringName = TAILS.get(prev, &"")
		if prev == &"Shot" and not shooting:
			t = &"Shot_end"  # terminó la pose de disparo (ya no sigues disparando)
		if t != &"" and anim.has_animation(t):
			tail_anim = t
	if tail_anim != &"":
		return tail_anim
	if shooting:
		return &"Shot"
	return &"Idle_Dmg" if _is_low_hp() and anim.has_animation(&"Idle_Dmg") else &"Idle"


func _play(next: StringName) -> void:
	if not anim.has_animation(next):
		if not missing_warned.has(next):
			missing_warned[next] = true
			push_warning("X: no existe la animación '%s' en el AnimationPlayer (revisa que se llame igual, con las mismas mayúsculas)." % str(next))
		return
	var current := anim.assigned_animation  # current_animation queda vacío al terminar una animación sin loop
	if current == next:
		return
	if debug_anim:
		print("X: ", current, " -> ", next)

	var keep_pos: bool = SYNC_PAIRS.get(current, &"") == next
	var pos := 0.0
	if keep_pos:
		if anim.is_playing():
			pos = anim.current_animation_position
		else:
			pos = anim.get_animation(current).length  # la anterior ya terminó: estaba en su último cuadro

	anim.play(next)
	if keep_pos:
		anim.seek(pos, true)


# ------------------------------------------------------------------- EFECTOS

# Efecto de carga: se busca el nodo y su AnimationPlayer, y se deja oculto
func _setup_charge_fx() -> void:
	if charge_fx == null:
		charge_fx = get_node_or_null("Carga") as Node2D
	if charge_fx == null:
		push_warning("No encuentro el efecto de carga: instancia su escena como hijo de X y llámala 'Carga', o arrástrala al campo Charge Fx.")
		return
	var players := charge_fx.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_warning("El efecto de carga no tiene un AnimationPlayer.")
	else:
		charge_fx_player = players[0] as AnimationPlayer
	charge_fx.hide()


# Sin efecto antes del nivel 2; Carga-1 en el nivel 2; Carga-2 en el nivel 3 (el 1 deja de verse).
# Al soltar el disparo holding_shoot pasa a false y todo se oculta.
func _update_charge_fx() -> void:
	if charge_fx == null:
		return
	var wanted: StringName = &""
	if holding_shoot:
		if charge >= charge_max_time:
			wanted = charge_anim_2
		elif charge >= charge_medium_time:
			wanted = charge_anim_1
	if wanted == charge_fx_current:
		return
	charge_fx_current = wanted
	if wanted == &"":
		charge_fx.hide()
		if charge_fx_player:
			charge_fx_player.stop()
	else:
		charge_fx.show()
		if charge_fx_player and charge_fx_player.has_animation(wanted):
			charge_fx_player.play(wanted)
		elif charge_fx_player:
			push_warning("El efecto de carga no tiene la animación '%s'. Revisa charge_anim_1 / charge_anim_2." % str(wanted))


# Estela: durante el dash deja copias del sprite que se desvanecen
func _update_trail(delta: float) -> void:
	if not trail_enabled or state != State.DASH:
		trail_timer = 0.0
		return
	trail_timer -= delta
	if trail_timer > 0.0:
		return
	trail_timer = trail_interval
	_spawn_ghost()


func _spawn_ghost() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = sprite.texture
	ghost.hframes = sprite.hframes
	ghost.vframes = sprite.vframes
	ghost.frame = sprite.frame
	ghost.centered = sprite.centered
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.z_index = sprite.z_index
	ghost.modulate = trail_color
	var parent := get_parent()
	parent.add_child(ghost)
	parent.move_child(ghost, get_index())  # justo detrás del jugador
	ghost.global_position = sprite.global_position
	ghost.global_scale = sprite.global_scale
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, trail_fade_time)
	tween.tween_callback(ghost.queue_free)


# ---------------------------------------------------------------------- VIDA

# Lo llaman las balas y los enemigos: body.take_damage(cantidad)
func take_damage(amount: int) -> void:
	if state == State.DEAD or invincible_left > 0.0 or amount <= 0:
		return
	if state == State.STAR or state == State.EXIT or state == State.WIN:
		return  # durante Star, Exit y Win es invulnerable
	hp = maxi(hp - amount, 0)
	_emit_health()
	if hp == 0:
		_die()  # con la vida en 0 no se reproduce Damage: pasa directo a la muerte
	else:
		_start_hit()


func _start_hit() -> void:
	# Damage tiene prioridad sobre cualquier otro estado: corta dash, pared, carga...
	state = State.HIT
	state_time_left = anim.get_animation(hit_anim).length if anim.has_animation(hit_anim) else 0.4
	invincible_left = invincible_time
	air_boost = false
	wall_lock_left = 0.0
	wall_jump_active = false
	holding_shoot = false
	charge = 0.0
	pose_left = 0.0
	crouching = false
	ladder_lock_left = 0.3
	_set_shoryuken_hitbox(false)
	velocity = Vector2(-facing * hit_knockback, 0.0)  # retrocede (al lado contrario de donde mira)


func _state_hit(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, hit_knockback * 4.0 * delta)  # el retroceso se frena solo
	_apply_gravity(delta)
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


func _die() -> void:
	state = State.DEAD
	velocity.x = 0.0
	_set_shoryuken_hitbox(false)
	wall_jump_active = false
	holding_shoot = false
	charge = 0.0
	pose_left = 0.0
	invincible_left = 0.0
	died.emit()
	if restart_delay >= 0.0:
		get_tree().create_timer(restart_delay).timeout.connect(_restart_level)


func _restart_level() -> void:
	get_tree().reload_current_scene()


func _state_dead(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)  # si muere en el aire, cae y ahí se queda


# Parpadeo mientras dura la invulnerabilidad
func _update_blink() -> void:
	var blink := invincible_left > 0.0 and int(invincible_left * 20.0) % 2 == 0
	sprite.modulate.a = 0.35 if blink else 1.0


func _emit_health() -> void:
	if debug_log:
		print("Vida: ", hp, "/", max_hp)
	health_changed.emit(hp, max_hp)


# ------------------------------------------------------------ ITEMS DE VIDA

# Life_Min / Life_Max: curan (sin pasar de la vida máxima). Los llama item_vida.gd
func heal(amount: int) -> bool:
	if state == State.DEAD or amount <= 0:
		return false
	hp = mini(hp + amount, max_hp)
	_emit_health()
	return true


# Heart: expande la barra hasta max_hp_limit y llena esa parte nueva
func increase_max_hp(amount: int) -> bool:
	var added := mini(amount, max_hp_limit - max_hp)
	if state == State.DEAD or added <= 0:
		return false  # ya está en el límite (o muerto): el item no se consume
	max_hp += added
	hp += added
	_emit_health()
	return true
