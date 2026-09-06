extends Node
## 全局游戏状态单例（Autoload: Game）
## 职责：跨场景的生命/金币计数、关卡顺序表、输入动作注册、场景切换。

signal coins_changed(value: int)
signal lives_changed(value: int)
signal player_hurt   # 玩家受伤但生命未耗尽：关卡负责把玩家传送回出生点
signal game_over     # 生命耗尽：关卡负责显示 Game Over 画面

const START_LEVEL: String = "res://scenes/levels/level_1_1.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"

# 关卡顺序表（推进主干）。水墨 World2 接入示例：
#   { "scene": "res://scenes/levels/world2_ink/level_2_1.tscn", "world": "ink", "display": "水墨山水 2-1" }
const LEVEL_SEQUENCE: Array[Dictionary] = [
	{ "scene": "res://scenes/levels/level_1_1.tscn", "world": "forest", "display": "森林王国 1-1 苏醒之林" },
	{ "scene": "res://scenes/levels/level_1_2.tscn", "world": "forest", "display": "森林王国 1-2 黄昏林地" },
]

var lives: int = 3
var coins: int = 0
var is_game_over: bool = false

# ---------- 音频 ----------
const SFX_PATHS: Dictionary = {
	"jump": "res://assets/audio/sfx/jump.wav",
	"coin": "res://assets/audio/sfx/coin.wav",
	"hurt": "res://assets/audio/sfx/hurt.wav",
	"stomp": "res://assets/audio/sfx/stomp.wav",
	"bounce": "res://assets/audio/sfx/bounce.wav",
	"win": "res://assets/audio/sfx/win.wav",
	"game_over": "res://assets/audio/sfx/game_over.wav",
	"click": "res://assets/audio/sfx/click.wav",
}
const MUSIC_PATHS: Dictionary = {
	"menu": "res://assets/audio/music/menu_theme.wav",
	"level": "res://assets/audio/music/level_theme.wav",
}
const SFX_POOL_SIZE := 8

var _sfx_pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_track: String = ""


func _ready() -> void:
	# 输入动作必须最先注册（后续场景的 _physics_process 依赖它们）
	_setup_input()
	# 全局回退字体：开源中文像素字体（Fusion Pixel, OFL）
	var pixel_font: Font = load("res://assets/fonts/fusion_pixel.otf")
	if pixel_font:
		ThemeDB.fallback_font = pixel_font
	_setup_audio()
	reset_run()


## 音效池（8 路并发）+ BGM 播放器（finished 信号实现无缝循环）
func _setup_audio() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -12.0
	_music.finished.connect(func() -> void: _music.play())
	add_child(_music)


## 播放音效（池满时静默丢弃，避免卡顿）
func play_sfx(sfx_name: String, volume_db: float = -6.0) -> void:
	var path: String = SFX_PATHS.get(sfx_name, "")
	if path == "":
		push_warning("未知音效: %s" % sfx_name)
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = load(path)
			p.volume_db = volume_db
			p.play()
			return


## 播放 BGM：同名曲目已在播则不打断（跨场景无缝）
func play_music(music_name: String) -> void:
	if _music_track == music_name and _music.playing:
		return
	_music_track = music_name
	_music.stream = load(MUSIC_PATHS[music_name])
	_music.play()


func stop_music() -> void:
	_music_track = ""
	_music.stop()


## 用代码注册输入动作（比手写 project.godot 的 Object() 序列更可靠）
## 只绑逻辑键 keycode：Web 平台 physical keycode 不可靠（已踩坑）
func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE, KEY_W, KEY_UP])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k: Key in keys:
		# 双绑定：同一按键同时注册逻辑键与物理键事件，
		# 无论 Web 端事件填充的是 keycode 还是 physical_keycode 都能命中
		var ev := InputEventKey.new()
		ev.keycode = k
		InputMap.action_add_event(action, ev)
		var ev_phys := InputEventKey.new()
		ev_phys.physical_keycode = k
		InputMap.action_add_event(action, ev_phys)


## 开始新的一轮（生命/金币归零）
func reset_run() -> void:
	is_game_over = false
	lives = 3
	coins = 0
	coins_changed.emit(coins)
	lives_changed.emit(lives)


## 拾取金币
func add_coin(amount: int = 1) -> void:
	coins += amount
	coins_changed.emit(coins)


## 受到一次伤害：扣一条命。
## 生命未耗尽 → 通知关卡把玩家传送回出生点；耗尽 → 发 game_over（不自动重开）。
func hurt_player() -> void:
	if is_game_over:
		return
	lives -= 1
	lives_changed.emit(lives)
	if lives <= 0:
		is_game_over = true
		print("游戏结束")
		game_over.emit()
	else:
		print("受伤，当前生命: %d" % lives)
		player_hurt.emit()


## 通关：看顺序表里还有没有下一关；全通完回主菜单
func on_level_cleared(current_scene_path: String) -> void:
	var idx: int = _index_of(current_scene_path)
	if idx < 0:
		return
	if idx + 1 < LEVEL_SEQUENCE.size():
		var next_level: Dictionary = LEVEL_SEQUENCE[idx + 1]
		print("进入下一关: %s" % next_level["display"])
		get_tree().change_scene_to_file(next_level["scene"])
	else:
		print("全部关卡完成！")
		reset_run()
		get_tree().change_scene_to_file(MAIN_MENU)


## 取关卡显示名（供关卡开场标题用）
func display_name(scene_path: String) -> String:
	var idx: int = _index_of(scene_path)
	return str(LEVEL_SEQUENCE[idx]["display"]) if idx >= 0 else ""


func reload_current_level() -> void:
	get_tree().reload_current_scene()


func _index_of(scene_path: String) -> int:
	for i in LEVEL_SEQUENCE.size():
		if LEVEL_SEQUENCE[i]["scene"] == scene_path:
			return i
	return -1
