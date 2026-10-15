extends Area2D

@export var speed: float = 300.0

# Daño por nivel de carga: 1 = normal, 2 = medio, 3 = máximo
const DAMAGE_BY_LEVEL := {1: 2, 2: 6, 3: 10}

var direction: int = 1
var damage: int = 2

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta

func set_shot_type(anim_name: String, dir: int) -> void:
	direction = dir
	if anim_sprite:
		anim_sprite.play(anim_name)
		anim_sprite.flip_h = (direction < 0)

func set_level(lvl: int, dir: int) -> void:
	direction = dir
	damage = DAMAGE_BY_LEVEL.get(lvl, 2)
	var anim_name = "Shot_" + str(lvl)
	if anim_sprite:
		anim_sprite.play(anim_name)
		anim_sprite.flip_h = (direction < 0)

func _on_body_entered(body: Node2D) -> void:
	# Si choca contra el Prototipo (jugador), ignorarlo para que no explote en su cara
	if body.name == "Prototipo" or body.is_in_group("Player"):
		return
	# Si lo que toca puede recibir daño (un enemigo), se lo hace
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()

# Función para borrar la bala cuando sale de la pantalla
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
