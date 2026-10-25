extends CharacterBody2D
## Personaje X, Parte 1: igual que el Prototipo, con animaciones de inicio y cierre
## (Run_1 -> Run_2, Dash_End, Shot_end) y disparo también en dash y en pared.
## Requiere en la escena: Sprite2D, AnimationPlayer y un Marker2D llamado "Shoot".
## Opcional: la escena del efecto de carga como hijo llamado "Carga", y Vida.tscn como hijo.
## Los sprites miran hacia la DERECHA (se voltean con flip_h al ir a la izquierda),
## excepto Wall_Slide y Wall_Shot_Slide, que se dibujaron mirando a la IZQUIERDA
## (ver wall_slide_sprite_faces_left).

enum State { NORMAL, DASH, WALL_SLIDE, HIT, DEAD }

signal health_changed(hp: int, max_hp: int)  # el HUD de vida se conecta a esta señal
signal died

# Nombres de tus acciones del Mapa de entrada (cámbialos aquí si los renombras)
const IN_LEFT := &"Izq"
const IN_RIGHT := &"Drh"
const IN_JUMP := &"Jump"
const IN_DASH := &"Dash"
const IN_SHOOT := &"Shot"

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
}

# Animaciones de cierre: qué se reproduce una vez al terminar la animación de la izquierda
# (si estás quieto en el suelo). Shot -> Shot_end se maneja aparte, porque espera a que termine la pose.
const TAILS := {
	&"Dash": &"Dash_End",
	&"Dash_Shot": &"Dash_Shot_End",
	&"Shot_Cargin": &"Shot_end",
}

# El loop de cada animación se pone desde el código: no importa cómo estén en el editor
const LOOPING := [&"Idle", &"Run_2", &"Run_Shot_2", &"Shot_Cargin"]
const ONE_SHOT := [
	&"Run_1", &"Run_Shot_1", &"Dash", &"Dash_End", &"Dash_Shot", &"Dash_Shot_End",
	&"Shot", &"Shot_end", &"Jump", &"Jump_Shot", &"Fall", &"Fall_Shot",
	&"Wall_Slide", &"Wall_Shot_Slide", &"Wall_Jump", &"Wall_Shot_Jump", &"Damage",
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
	max_hp = clampi(max_hp_start, 1, max_hp_limit)
	hp = max_hp
	_emit_health.call_deferred()  # diferido: así el HUD ya está conectado


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

	_apply_facing()
	_handle_shoot(delta)
	_update_charge_fx()
	move_and_slide()
	_update_animation()
	_update_trail(delta)
	_update_blink()


# ---------------------------------------------------------------- MOVIMIENTO

func _state_normal(delta: float) -> void:
	if is_on_floor():
		air_boost = false

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


# ------------------------------------------------------------------- DISPARO

func _handle_shoot(delta: float) -> void:
	# Se puede disparar y cargar en cualquier estado menos al recibir daño o estando muerto
	if state == State.HIT or state == State.DEAD:
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
	var running := state == State.NORMAL and on_floor and move_dir != 0.0
	var idle_like := state == State.NORMAL and on_floor and move_dir == 0.0 and not charging

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
		_:
			if not on_floor:
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
	return &"Shot" if shooting else &"Idle"


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
