extends CanvasLayer
## HUD de vida (Partes 1 y 2). Va como HIJO de Prototipo.
## Nodos: Marco (Node2D) con cuatro Sprite2D: Top, Mid, Down y Life (la barra verde).
## La barra crece hacia ARRIBA: Down queda fijo abajo, Mid se estira y Top sube encima de Mid.
## Life (verde) sale desde el borde de abajo de Mid y sube según la vida actual.
## El script coloca y escala Marco por su cuenta: no hace falta moverlo a mano en el editor.
## Ojo: la cámara (y su zoom) NO afecta a un CanvasLayer, por eso el HUD tiene su propia escala.

@export var px_per_hp := 1.0             # píxeles de alto que suma cada punto de vida
@export var bar_scale := 3.0             # tamaño del HUD (mejor con números enteros: se ve más nítido)
@export var margin := Vector2(24, 24)    # separación al borde izquierdo y superior de la pantalla
@export var life_offset := Vector2.ZERO  # ajuste fino de la barra verde dentro del marco (píxeles del sprite)
@export var fill_speed := 80.0           # puntos de vida por segundo con que sube/baja el verde (0 = al instante)

@onready var marco: Node2D = $Marco
@onready var top: Sprite2D = $Marco/Top
@onready var mid: Sprite2D = $Marco/Mid
@onready var down: Sprite2D = $Marco/Down
@onready var life: Sprite2D = get_node_or_null("Marco/Life") as Sprite2D

var player: Node
var target_hp := 0.0   # vida real
var shown_hp := 0.0    # vida que se está dibujando (se acerca a target_hp poco a poco)
var snap_next := true  # la primera vez la barra aparece llena al instante, sin animación


func _ready() -> void:
	marco.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art nítido
	for s: Sprite2D in [top, mid, down]:
		s.centered = false
	mid.region_enabled = true  # Mid se estira repitiendo su textura hacia arriba
	mid.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	if life == null:
		push_warning("Vida: falta el nodo Life (un Sprite2D hijo de Marco con la barra verde).")
	else:
		life.centered = false
		life.region_enabled = true
		life.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		life.z_index = 1  # se dibuja encima de Mid

	player = get_parent()
	if not player.has_signal("health_changed"):
		push_warning("Vida: instancia esta escena como hijo de Prototipo (y usa el prototipo.gd nuevo).")
		return
	player.health_changed.connect(_on_health_changed)
	_set_max_hp(player.max_hp)
	target_hp = player.hp
	shown_hp = target_hp


func _on_health_changed(hp: int, max_hp: int) -> void:
	_set_max_hp(max_hp)
	target_hp = hp
	if snap_next:
		shown_hp = target_hp
		snap_next = false


func _process(delta: float) -> void:
	if fill_speed <= 0.0:
		shown_hp = target_hp
	else:
		shown_hp = move_toward(shown_hp, target_hp, fill_speed * delta)
	_draw_life()


# Barra verde: nace en el borde de abajo de Mid y sube según la vida que se está mostrando
func _draw_life() -> void:
	if life == null or life.texture == null or down.texture == null:
		return
	var life_w := life.texture.get_width()
	var h := roundf(shown_hp * px_per_hp)
	life.visible = h > 0.0
	life.region_rect = Rect2(0, 0, life_w, h)
	life.position = Vector2(floorf(-life_w / 2.0), -down.texture.get_height() - h) + life_offset


# Acomoda Down, Mid y Top según la vida máxima actual, y coloca Marco en la pantalla
func _set_max_hp(max_hp: int) -> void:
	if top.texture == null or mid.texture == null or down.texture == null:
		push_warning("Vida: asigna una textura a Top, Mid y Down.")
		return
	var top_size := top.texture.get_size()
	var down_size := down.texture.get_size()
	var mid_w := mid.texture.get_width()
	var mid_h := roundf(max_hp * px_per_hp)

	# Dentro de Marco: todo centrado en X; el borde de abajo de Down está en y = 0 y se construye hacia arriba
	down.position = Vector2(floorf(-down_size.x / 2.0), -down_size.y)
	mid.region_rect = Rect2(0, 0, mid_w, mid_h)
	mid.position = Vector2(floorf(-mid_w / 2.0), -down_size.y - mid_h)
	top.position = Vector2(floorf(-top_size.x / 2.0), -down_size.y - mid_h - top_size.y)

	# Marco en pantalla: el borde de abajo queda donde llegaría la barra con la vida al límite,
	# así con la vida máxima la barra cabe justo debajo del margen de arriba y nunca se sale
	var limit_h := top_size.y + roundf(player.max_hp_limit * px_per_hp) + down_size.y
	var widest := maxf(top_size.x, maxf(mid_w, down_size.x))
	marco.scale = Vector2(bar_scale, bar_scale)
	marco.position = Vector2(margin.x + widest * bar_scale / 2.0, margin.y + limit_h * bar_scale).round()
