extends Area2D

@export var speed: float = 300.0
var direction: int = 1

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
	var anim_name = "Shot_" + str(lvl)
	if anim_sprite:
		anim_sprite.play(anim_name)
		anim_sprite.flip_h = (direction < 0)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Prototipo" or body.is_in_group("Player"):
		return
	queue_free()

# Función para borrar la bala cuando sale de la pantalla
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
