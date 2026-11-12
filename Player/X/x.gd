extends CharacterBody2D

enum State { NORMAL, DASH, WALL_SLIDE, HIT, DEAD, LADDER, LADDER_TOP, GIGA, SHORYUKEN, EXIT, WIN, STAR }

signal health_changed(hp: int, max_hp: int)
signal died

const IN_LEFT := &"Izq"
const IN_RIGHT := &"Drh"
const IN_JUMP := &"Jump"
const IN_DASH := &"Dash"
const IN_SHOOT := &"Shot"
const IN_UP := &"Up"
const IN_DOWN := &"Down"
const IN_GIGA_Z := &"Giga_Z"
const IN_GIGA_X := &"Giga_X"
const IN_EXIT := &"Exit"
const IN_WIN := &"Win"
const IN_SHORYUKEN := &"Shoryuken"

const LADDER_DATA := "Escalera"
const LADDER_TOP_DATA := "Tope"
const LADDER_NUDGE := 4.0
const NO_SHOOT := [State.HIT, State.DEAD, State.LADDER, State.LADDER_TOP, State.GIGA, State.SHORYUKEN, State.EXIT, State.WIN, State.STAR]

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
const TAILS := {&"Dash": &"Dash_End", &"Dash_Shot": &"Dash_Shot_End", &"Shot_Cargin": &"Shot_end"}
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
@export var jump_cut := 0.4
@export var dash_speed := 300.0
@export var dash_start_speed := 450.0
@export var dash_burst_time := 0.15
@export var dash_time := 0.4
@export var dash_jump_speed := 220.0

@export_group("Pared")
@export var wall_slide_speed := 60.0
@export var wall_jump_velocity := -330.0
@export var wall_jump_push := 200.0
@export var wall_jump_lock_time := 0.15
@export var wall_slide_sprite_faces_left := true

@export_group("Disparo")
@export var bullet_scene: PackedScene
@export var shoot_cooldown := 1.0
@export var shoot_pose_time := 0.35
@export var charge_start_delay := 0.25
@export var charge_medium_time := 0.8
@export var charge_max_time := 1.8

@export_group("Vida")
@export var max_hp_start := 25
@export var max_hp_limit := 100
@export var hit_knockback := 80.0
@export var invincible_time := 1.0
@export var hit_anim := &"Damage"
@export var dead_anim := &"Damage"
@export var restart_delay := 1.5
@export var low_hp_ratio := 0.3

@export_group("Efecto de carga")
@export var charge_fx: Node2D
@export var charge_anim_1 := &"Carga-1"
@export var charge_anim_2 := &"Carga-2"

@export_group("Estela (dash)")
@export var trail_enabled := true
@export var trail_interval := 0.04
@export var trail_fade_time := 0.25
@export var trail_color := Color(0.5, 0.8, 1.0, 0.6)

@export_group("Escalera")
@export var ladder_speed := 90.0

@export_group("Shoryuken")
@export var shoryuken_jump := -380.0
@export var shoryuken_push := 80.0
@export var shoryuken_damage := 8
@export var shoryuken_fire_delay := 0.0
@export var shoryuken_scene: PackedScene
@export var shoryuken_fire_offset := Vector2(24.0, -20.0)
@export var shoryuken_hit_size := Vector2(32.0, 40.0)
@export_flags_2d_physics var shoryuken_hit_mask := 4

@export_group("Star, Exit y Win")
@export var star_on_start := true
@export var star_spawn_height := 0.0
@export var exit_rise_speed := 400.0
@export var exit_rise_time := 5.0
@export var win_restart_delay := 5.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var muzzle: Marker2D = $Shoot

var state := State.NORMAL
var facing := 1
var move_dir := 0.0
var state_time_left := 0.0
var cooldown_left := 0.0
var pose_left := 0.0
var just_fired := false
var holding_shoot := false
var charge := 0.0
var air_boost := false
var wall_dir := 0
var wall_lock_left := 0.0
var wall_jump_active := false
var run_phase := 1
var tail_anim: StringName = &""
var special_anim: StringName = &""
var missing_warned := {}
var charge_fx_player: AnimationPlayer
var charge_fx_current: StringName = &""
var trail_timer := 0.0
var max_hp := 25
var hp := 25
var invincible_left := 0.0
var crouching := false
var stand_rect := Rect2(-8.0, -24.0, 16.0, 48.0)
var ladder_layers: Array[TileMapLayer] = []
var ladder_searched := false
var ladder_lock_left := 0.0
var ladder_time := 0.0
var ladder_dir_y := 0.0
var ladder_intro := false
var ladder_intro_len := 0.0
var giga_in_air := false
var shoryuken_phase := 0
var shoryuken_fired := false
var shoryuken_fx: Node2D
var shoryuken_hitbox: Area2D
var shoryuken_hit_bodies: Array = []
var exit_phase := 0
var star_landed := false

var charging: bool:
	get:
		return holding_shoot and charge >= charge_start_delay


func _ready() -> void:
	add_to_group("Player")
	var tree := get_node_or_null("AnimationTree") as AnimationTree
	if tree:
		tree.active = false
	for n in LOOPING:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for n in ONE_SHOT:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_NONE
	_setup_charge_fx()
	_setup_stand_rect()
	max_hp = clampi(max_hp_start, 1, max_hp_limit)
	hp = max_hp
	_emit_health.call_deferred()
	if star_on_start and anim.has_animation(&"Star"):
		global_position.y -= star_spawn_height
		special_anim = &"Star"
		state = State.STAR


func _setup_stand_rect() -> void:
	for child in get_children():
		var cs := child as CollisionShape2D
		if cs != null and cs.shape != null:
			var r := cs.shape.get_rect()
			stand_rect = Rect2(cs.position + r.position, r.size)
			return


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
	_apply_facing()
	_handle_shoot(delta)
	_update_charge_fx()
	move_and_slide()
	_after_move()
	_update_animation()
	_update_trail(delta)
	_update_blink()


func _state_normal(delta: float) -> void:
	if is_on_floor():
		air_boost = false
	if _try_special_actions():
		return

	crouching = is_on_floor() and Input.is_action_pressed(IN_DOWN) and move_dir == 0.0

	if wall_lock_left > 0.0:
		velocity.x = facing * wall_jump_push
	else:
		if move_dir != 0.0:
			var new_facing := 1 if move_dir > 0.0 else -1
			if new_facing != facing:
				air_boost = false
			facing = new_facing
		velocity.x = facing * dash_jump_speed if air_boost else move_dir * run_speed
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


func _try_wall_slide() -> void:
	if wall_lock_left > 0.0 or is_on_floor() or not is_on_wall():
		return
	if velocity.y <= 0.0 or move_dir == 0.0:
		return
	var toward_wall := -signf(get_wall_normal().x)
	if signf(move_dir) != toward_wall:
		return
	wall_dir = int(toward_wall)
	facing = -wall_dir
	air_boost = false
	wall_jump_active = false
	state = State.WALL_SLIDE


func _state_wall_slide(delta: float) -> void:
	if is_on_floor() or not is_on_wall() or signf(move_dir) != float(wall_dir):
		velocity.x = 0.0
		state = State.NORMAL
		return
	facing = -wall_dir
	if Input.is_action_just_pressed(IN_JUMP):
		velocity = Vector2(facing * wall_jump_push, wall_jump_velocity)
		wall_lock_left = wall_jump_lock_time
		wall_jump_active = true
		state = State.NORMAL
		return
	velocity.x = wall_dir * 20.0
	velocity.y = minf(velocity.y + gravity * delta, wall_slide_speed)


func _state_dash(delta: float) -> void:
	var t := clampf((dash_time - state_time_left) / dash_burst_time, 0.0, 1.0)
	velocity.x = facing * lerpf(dash_start_speed, dash_speed, t)
	_apply_gravity(delta)
	state_time_left -= delta
	if is_on_floor() and Input.is_action_just_pressed(IN_JUMP):
		velocity.y = jump_velocity
		air_boost = true
		state = State.NORMAL
	elif state_time_left <= 0.0 or not is_on_floor():
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
	muzzle.position.x = absf(muzzle.position.x) * facing


func _anim_len(anim_name: StringName, fallback: float) -> float:
	if anim.has_animation(anim_name):
		return maxf(anim.get_animation(anim_name).length, 0.05)
	return fallback


func _reset_actions() -> void:
	holding_shoot = false
	charge = 0.0
	pose_left = 0.0
	air_boost = false
	wall_jump_active = false
	wall_lock_left = 0.0
	crouching = false
	tail_anim = &""


func _start_special(new_state: State, anim_name: StringName, duration: float) -> void:
	_reset_actions()
	state = new_state
	special_anim = anim_name
	state_time_left = duration
	velocity.x = 0.0


func _try_special_actions() -> bool:
	if wall_lock_left > 0.0:
		return false
	var grounded := is_on_floor()
	if Input.is_action_just_pressed(IN_EXIT):
		exit_phase = 0
		_start_special(State.EXIT, &"Exit", _anim_len(&"Exit", 0.5))
	elif Input.is_action_just_pressed(IN_WIN):
		_start_special(State.WIN, &"Win", win_restart_delay)
	elif Input.is_action_just_pressed(IN_GIGA_Z):
		giga_in_air = not grounded
		var giga := &"Giga_Atk_1" if grounded else &"Giga_Atk_2"
		_start_special(State.GIGA, giga, _anim_len(giga, 0.5))
	elif Input.is_action_just_pressed(IN_GIGA_X) and grounded:
		giga_in_air = false
		_start_special(State.GIGA, &"Giga_Atk_3", _anim_len(&"Giga_Atk_3", 0.5))
	elif Input.is_action_just_pressed(IN_SHORYUKEN) and grounded:
		_start_special(State.SHORYUKEN, &"Shoryuken", _anim_len(&"Shoryuken", 0.4))
		shoryuken_phase = 0
		shoryuken_fired = false
		shoryuken_hit_bodies.clear()
		velocity = Vector2(facing * shoryuken_push, shoryuken_jump)
	else:
		return _try_start_ladder()
	return true


func _after_move() -> void:
	if state == State.LADDER:
		_ladder_after_move()
	elif state == State.STAR and not star_landed and is_on_floor():
		star_landed = true
		state_time_left = _anim_len(&"Star", 0.5)
		anim.stop()
		anim.play(&"Star")


func _restart_level() -> void:
	set_physics_process(false)
	get_tree().reload_current_scene()


func _find_ladder_layers() -> void:
	ladder_searched = true
	var root := get_tree().current_scene
	if root == null:
		return
	for node in root.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer != null and layer.tile_set != null and layer.tile_set.get_custom_data_layer_by_name(LADDER_DATA) >= 0:
			ladder_layers.append(layer)


func _ladder_at(world_pos: Vector2) -> Dictionary:
	for layer in ladder_layers:
		var cell := layer.local_to_map(layer.to_local(world_pos))
		var data := layer.get_cell_tile_data(cell)
		if data == null or not bool(data.get_custom_data(LADDER_DATA)):
			continue
		var ts := layer.tile_set
		var is_top := ts.get_custom_data_layer_by_name(LADDER_TOP_DATA) >= 0 and bool(data.get_custom_data(LADDER_TOP_DATA))
		var center := layer.to_global(layer.map_to_local(cell))
		return {
			"kind": 2 if is_top else 1,
			"center_x": center.x,
			"top_y": center.y - ts.tile_size.y * 0.5 * absf(layer.global_scale.y),
		}
	return {"kind": 0}


func _ladder_probe_body(include_below := false) -> Dictionary:
	var cx := global_position.x + stand_rect.get_center().x
	var feet := global_position.y + stand_rect.end.y
	var head := global_position.y + stand_rect.position.y
	var points: Array[float] = [feet - 4.0, (feet + head) * 0.5, head + 4.0]
	if include_below:
		points.append(feet + 2.0)
	for y in points:
		var info := _ladder_at(Vector2(cx, y))
		if info["kind"] != 0:
			return info
	return {"kind": 0}


func _try_start_ladder() -> bool:
	var up := Input.is_action_pressed(IN_UP)
	var down := Input.is_action_pressed(IN_DOWN)
	if ladder_lock_left > 0.0 or (not up and not down):
		return false
	if not ladder_searched:
		_find_ladder_layers()
	if up:
		var info := _ladder_probe_body()
		if info["kind"] != 0:
			_start_ladder(info, false)
			return true
	if down and is_on_floor():
		var below := _ladder_at(Vector2(global_position.x + stand_rect.get_center().x, global_position.y + stand_rect.end.y + 2.0))
		if below["kind"] == 2:
			_start_ladder(below, true)
			return true
	return false


func _start_ladder(info: Dictionary, from_top: bool) -> void:
	_reset_actions()
	state = State.LADDER
	velocity = Vector2.ZERO
	global_position.x = float(info["center_x"]) - stand_rect.get_center().x
	if from_top:
		global_position.y += LADDER_NUDGE
	ladder_time = 0.0
	ladder_dir_y = 0.0
	ladder_intro = anim.has_animation(&"Up_1")
	ladder_intro_len = _anim_len(&"Up_1", 0.0)


func _state_ladder(delta: float) -> void:
	ladder_time += delta
	if ladder_intro and ladder_time >= ladder_intro_len:
		ladder_intro = false
	ladder_dir_y = 0.0 if ladder_intro else Input.get_axis(IN_UP, IN_DOWN)
	velocity = Vector2(0.0, ladder_dir_y * ladder_speed)
	if Input.is_action_just_pressed(IN_JUMP):
		_leave_ladder(move_dir != 0.0)


func _leave_ladder(jump: bool) -> void:
	state = State.NORMAL
	ladder_lock_left = 0.25
	velocity = Vector2.ZERO
	if jump:
		facing = 1 if move_dir > 0.0 else -1
		velocity = Vector2(facing * run_speed, jump_velocity)


func _ladder_after_move() -> void:
	if ladder_time < 0.1:
		return
	if ladder_dir_y > 0.0 and is_on_floor():
		_leave_ladder(false)
		return
	if ladder_dir_y < 0.0:
		var cx := global_position.x + stand_rect.get_center().x
		var feet := global_position.y + stand_rect.end.y
		if _ladder_at(Vector2(cx, feet - 1.0))["kind"] == 0:
			var under := _ladder_at(Vector2(cx, feet + 3.0))
			if under["kind"] != 0:
				_start_special(State.LADDER_TOP, &"Up_3", _anim_len(&"Up_3", 0.0))
				global_position.y = float(under["top_y"]) - stand_rect.end.y
				ladder_lock_left = 0.4
				return
	if _ladder_probe_body(true)["kind"] == 0:
		_leave_ladder(false)


func _state_ladder_top(delta: float) -> void:
	velocity = Vector2(0.0, 20.0)
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


func _state_giga(delta: float) -> void:
	velocity.x = 0.0
	if giga_in_air:
		velocity.y = 0.0
	else:
		_apply_gravity(delta)
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


func _state_shoryuken(delta: float) -> void:
	_apply_gravity(delta)
	state_time_left -= delta
	if shoryuken_phase == 0:
		velocity.x = facing * shoryuken_push
		if shoryuken_fire_delay >= 0.0 and anim.assigned_animation == &"Shoryuken" and anim.current_animation_position >= shoryuken_fire_delay:
			fire_shoryuken()
		_shoryuken_damage()
		if state_time_left <= 0.0:
			shoryuken_phase = 1
			state_time_left = _anim_len(&"Shoryuken_End", 0.0)
			_clear_fire()
	else:
		velocity.x = move_toward(velocity.x, 0.0, shoryuken_push * 6.0 * delta)
		if state_time_left <= 0.0:
			state = State.NORMAL


func fire_shoryuken() -> void:
	if state != State.SHORYUKEN or shoryuken_phase != 0 or shoryuken_fired or shoryuken_scene == null:
		return
	shoryuken_fired = true
	var node := shoryuken_scene.instantiate() as Node2D
	add_child(node)
	node.position = Vector2(shoryuken_fire_offset.x * facing, shoryuken_fire_offset.y)
	node.scale.x = absf(node.scale.x) * facing
	shoryuken_fx = node

	shoryuken_hitbox = Area2D.new()
	shoryuken_hitbox.collision_layer = 0
	shoryuken_hitbox.collision_mask = shoryuken_hit_mask
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = shoryuken_hit_size
	cs.shape = rect
	shoryuken_hitbox.add_child(cs)
	node.add_child(shoryuken_hitbox)

	var players := node.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap := players[0] as AnimationPlayer
		for n in ap.get_animation_list():
			if n != "RESET":
				ap.play(n)
				ap.animation_finished.connect(_clear_fire)
				break


func _clear_fire(_anim_name := &"") -> void:
	shoryuken_hitbox = null
	if is_instance_valid(shoryuken_fx):
		shoryuken_fx.queue_free()
	shoryuken_fx = null


func _shoryuken_damage() -> void:
	if shoryuken_hitbox == null:
		return
	for body in shoryuken_hitbox.get_overlapping_bodies():
		if body != self and not shoryuken_hit_bodies.has(body) and body.has_method("take_damage"):
			shoryuken_hit_bodies.append(body)
			body.take_damage(shoryuken_damage)


func _state_exit(delta: float) -> void:
	state_time_left -= delta
	if exit_phase == 0:
		velocity.x = 0.0
		_apply_gravity(delta)
		if state_time_left <= 0.0:
			exit_phase = 1
			state_time_left = exit_rise_time
			collision_layer = 0
			collision_mask = 0
	else:
		velocity = Vector2(0.0, -exit_rise_speed)
		if state_time_left <= 0.0:
			_restart_level()


func _state_win(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)
	state_time_left -= delta
	if state_time_left <= 0.0:
		_restart_level()


func _state_star(delta: float) -> void:
	velocity.x = 0.0
	if not star_landed:
		_apply_gravity(delta)
		return
	velocity.y = 0.0
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


func _handle_shoot(delta: float) -> void:
	if state in NO_SHOOT:
		holding_shoot = false
		charge = 0.0
		return
	if Input.is_action_just_pressed(IN_SHOOT):
		holding_shoot = true
		charge = 0.0
		if cooldown_left <= 0.0:
			_fire(1)
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
		return
	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.set_level(level, facing)
	cooldown_left = shoot_cooldown
	pose_left = shoot_pose_time
	just_fired = true


func _update_animation() -> void:
	var cur := anim.assigned_animation
	if not anim.is_playing():
		if tail_anim != &"" and cur == tail_anim:
			tail_anim = &""
		if cur == &"Run_1" or cur == &"Run_Shot_1":
			run_phase = 2

	var shooting := pose_left > 0.0 or charging
	var on_floor := is_on_floor()
	var grounded_normal := state == State.NORMAL and on_floor and not crouching
	var running := grounded_normal and move_dir != 0.0
	if not running:
		run_phase = 1
	if not (grounded_normal and move_dir == 0.0 and not charging):
		tail_anim = &""
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
		State.SHORYUKEN:
			next = &"Shoryuken" if shoryuken_phase == 0 else &"Shoryuken_End"
		State.LADDER_TOP, State.GIGA, State.EXIT, State.WIN, State.STAR:
			next = special_anim
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

	if state == State.LADDER and anim.assigned_animation == &"Up_2":
		if ladder_dir_y == 0.0:
			anim.pause()
		elif not anim.is_playing():
			anim.play(&"Up_2")
	elif state == State.STAR and not star_landed:
		anim.pause()
		anim.seek(0.0, true)


func _standing_animation(prev: StringName, shooting: bool) -> StringName:
	if charging:
		return &"Shot_Cargin"
	if just_fired:
		tail_anim = &""
		if prev == &"Shot" and not anim.is_playing():
			anim.play(&"Shot")
		return &"Shot"
	if prev == &"Shot" and not shooting and anim.is_playing():
		return &"Shot"
	if tail_anim == &"":
		var t: StringName = &"Shot_end" if prev == &"Shot" and not shooting else TAILS.get(prev, &"")
		if t != &"" and anim.has_animation(t):
			tail_anim = t
	if tail_anim != &"":
		return tail_anim
	if shooting:
		return &"Shot"
	return &"Idle_Dmg" if hp > 0 and float(hp) / float(max_hp) <= low_hp_ratio and anim.has_animation(&"Idle_Dmg") else &"Idle"


func _play(next: StringName) -> void:
	if not anim.has_animation(next):
		if not missing_warned.has(next):
			missing_warned[next] = true
			push_warning("X: falta la animación '%s'" % str(next))
		return
	var current := anim.assigned_animation
	if current == next:
		return
	var keep_pos: bool = SYNC_PAIRS.get(current, &"") == next
	var pos := 0.0
	if keep_pos:
		pos = anim.current_animation_position if anim.is_playing() else anim.get_animation(current).length
	anim.play(next)
	if keep_pos:
		anim.seek(pos, true)


func _setup_charge_fx() -> void:
	if charge_fx == null:
		charge_fx = get_node_or_null("Carga") as Node2D
	if charge_fx == null:
		return
	var players := charge_fx.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		charge_fx_player = players[0] as AnimationPlayer
	charge_fx.hide()


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


func _update_trail(delta: float) -> void:
	if not trail_enabled or state != State.DASH:
		trail_timer = 0.0
		return
	trail_timer -= delta
	if trail_timer > 0.0:
		return
	trail_timer = trail_interval
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
	parent.move_child(ghost, get_index())
	ghost.global_position = sprite.global_position
	ghost.global_scale = sprite.global_scale
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, trail_fade_time)
	tween.tween_callback(ghost.queue_free)


func take_damage(amount: int) -> void:
	if amount <= 0 or invincible_left > 0.0 or state in [State.DEAD, State.STAR, State.EXIT, State.WIN]:
		return
	hp = maxi(hp - amount, 0)
	_emit_health()
	if hp == 0:
		_die()
	else:
		_start_hit()


func _start_hit() -> void:
	_reset_actions()
	_clear_fire()
	state = State.HIT
	state_time_left = _anim_len(hit_anim, 0.4)
	invincible_left = invincible_time
	ladder_lock_left = 0.3
	velocity = Vector2(-facing * hit_knockback, 0.0)


func _state_hit(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, hit_knockback * 4.0 * delta)
	_apply_gravity(delta)
	state_time_left -= delta
	if state_time_left <= 0.0:
		state = State.NORMAL


func _die() -> void:
	_reset_actions()
	_clear_fire()
	state = State.DEAD
	velocity.x = 0.0
	invincible_left = 0.0
	died.emit()
	if restart_delay >= 0.0:
		get_tree().create_timer(restart_delay).timeout.connect(_restart_level)


func _state_dead(delta: float) -> void:
	velocity.x = 0.0
	_apply_gravity(delta)


func _update_blink() -> void:
	var blink := invincible_left > 0.0 and int(invincible_left * 20.0) % 2 == 0
	sprite.modulate.a = 0.35 if blink else 1.0


func _emit_health() -> void:
	health_changed.emit(hp, max_hp)


func heal(amount: int) -> bool:
	if state == State.DEAD or amount <= 0:
		return false
	hp = mini(hp + amount, max_hp)
	_emit_health()
	return true


func increase_max_hp(amount: int) -> bool:
	var added := mini(amount, max_hp_limit - max_hp)
	if state == State.DEAD or added <= 0:
		return false
	max_hp += added
	hp += added
	_emit_health()
	return true
