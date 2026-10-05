class_name FloatingText3D
extends RefCounted
## Numeri e scritte che salgono e svaniscono sopra un punto del mondo 3D (danni, cure, "!").

const DAMAGE := Color(1.0, 0.92, 0.35)
const PLAYER_DAMAGE := Color(1.0, 0.35, 0.3)
const HEAL := Color(0.45, 1.0, 0.45)


static func spawn(parent: Node, pos: Vector3, text: String, color: Color = DAMAGE, size: int = 72) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = size
	l.outline_size = 8
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_modulate = Color(0.15, 0.06, 0.05)
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.0, 0.0)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", pos.y + 0.7, 0.75).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.75).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)
