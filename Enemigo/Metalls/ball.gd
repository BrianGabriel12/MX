extends Area2D
## Bala del enemigo Metalls. Raíz: Area2D con Sprite2D y CollisionShape2D.

@export var speed := 120.0
@export var damage := 2
@export var lifetime := 3.0   # segundos antes de desaparecer sola

var direction := -1
var shooter: Node = null  # quien la disparó: no se golpea a sí mismo


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func setup(dir: int, from: Node = null) -> void:
	direction = dir
	shooter = from


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body == shooter or body.is_in_group("Enemy"):
		return  # ignora a su dueño y a otros enemigos
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
