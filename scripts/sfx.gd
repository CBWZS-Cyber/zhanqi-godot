extends Node
## 全局音效管理（autoload: Sfx）—— 用法：Sfx.play("click")
## 音源位于 res://assets/sfx/（click/victory 为 v1 街机风，其余为 v2 战争风）

const _STREAMS := {
	"click": preload("res://assets/sfx/click.wav"),
	"footstep": preload("res://assets/sfx/footstep.wav"),
	"dash": preload("res://assets/sfx/dash.wav"),
	"teleport": preload("res://assets/sfx/teleport.wav"),
	"explosion": preload("res://assets/sfx/explosion.wav"),
	"hit": preload("res://assets/sfx/hit.wav"),
	"alarm": preload("res://assets/sfx/alarm.wav"),
	"powerup": preload("res://assets/sfx/powerup.wav"),
	"error": preload("res://assets/sfx/error.wav"),
	"victory": preload("res://assets/sfx/victory.wav"),
}

func play(sfx_name: String, volume_db := 0.0) -> void:
	if not _STREAMS.has(sfx_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _STREAMS[sfx_name]
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
